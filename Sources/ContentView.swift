import AppKit
import AVFAudio
import Collaboration
import Lottie
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class RecordingDestinationInbox {
    static let shared = RecordingDestinationInbox()

    private(set) var pending: RecordingDestination?

    func submit(_ destination: RecordingDestination) {
        pending = destination
    }

    func consume() -> RecordingDestination? {
        defer { pending = nil }
        return pending
    }
}

private enum SidebarSelection: Hashable {
    case all
    case favorites
    case memory
    case models
    case templates
    case settings
    case trash
    case folder(UUID)
}

private struct MacUserProfile {
    let name: String
    let image: NSImage?

    static var current: MacUserProfile {
        let identity = CBUserIdentity(
            posixUID: getuid(),
            authority: CBIdentityAuthority.local()
        )
        let fullName = identity?.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = fullName?.isEmpty == false ? fullName ?? NSFullUserName() : NSFullUserName()
        return MacUserProfile(
            name: resolvedName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? resolvedName,
            image: identity?.image
        )
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Folder.order) private var folders: [Folder]
    @Query(sort: \NoteTemplate.createdAt) private var templates: [NoteTemplate]

    let coordinator: AppCoordinator
    @State private var permissions = PermissionAccess()
    let calendarAccess: CalendarAccess
    @State private var notificationAccess = NotificationAccess.shared
    @State private var meetingActionInbox = MeetingActionInbox.shared
    @State private var recordingDestinationInbox = RecordingDestinationInbox.shared
    @State private var updater = BurritoUpdateManager.shared
    @State private var modelStore = ParakeetModelStore.shared
    @State private var languageModelStore = LocalLanguageModelStore.shared
    @State private var chatSessions = MemoryChatSessionStore()
    @State private var isSidebarVisible = true
    @State private var sidebarSelection: SidebarSelection? = .all
    @State private var selectedNoteID: UUID?
    @State private var selectedMemoryCitation: MemoryCitation?
    @State private var memoryFolderID: UUID?
    @State private var isCommandPalettePresented = false
    @State private var commandPaletteQuery = ""
    @State private var recordingDestination: RecordingDestination?
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var confirmingEmptyTrash = false
    @State private var ownershipStatus: OwnershipOperationStatus?
    @AppStorage("permissionOnboardingCompleted") private var permissionOnboardingCompleted = false
    @AppStorage("defaultTemplateID") private var defaultTemplateID = BuiltInTemplate.summary.rawValue
    @AppStorage("transcriptionLanguage") private var defaultLanguage = "en-US"
    @AppStorage("retainAudioDefault") private var defaultRetainsAudio = false
    @AppStorage(BurritoAppearance.storageKey) private var appearanceRawValue =
        BurritoAppearance.system.rawValue
    private let userProfile = MacUserProfile.current

    private var appearance: BurritoAppearance {
        BurritoAppearance.resolve(appearanceRawValue)
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    private var activeProcessingNote: Note? {
        notes.first { $0.processingStage != nil }
    }

    private var visibleNotes: [Note] {
        let filtered = notes.filter { note in
            let isInSection = switch sidebarSelection ?? .all {
            case .all:
                note.deletedAt == nil
            case .favorites:
                note.deletedAt == nil && note.isFavorite
            case .memory:
                false
            case .models:
                false
            case .templates:
                false
            case .settings:
                false
            case .trash:
                note.deletedAt != nil
            case .folder(let id):
                note.deletedAt == nil && note.folder?.id == id
            }
            return isInSection
        }

        return filtered.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var noteDays: [(date: Date, notes: [Note])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleNotes) {
            calendar.startOfDay(for: $0.updatedAt)
        }
        return grouped
            .map { (date: $0.key, notes: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if !permissionOnboardingCompleted || !permissions.allGranted {
                PermissionGateView(
                    permissions: permissions,
                    calendarAccess: calendarAccess
                ) {
                    permissionOnboardingCompleted = true
                }
            } else if let activeProcessingNote,
                      let processingStage = activeProcessingNote.processingStage {
                ScooterGenerationLoader(
                    stage: processingStage,
                    transcriptionEngine: finalTranscriptionEngine(
                        for: activeProcessingNote.languageIdentifier
                    )
                )
            } else if let selectedNote {
                NoteDetailView(
                    note: selectedNote,
                    chatSession: chatSessions.session(for: selectedNote.id),
                    externalCitedSegmentID: selectedMemoryCitation?.noteID == selectedNote.id
                        ? selectedMemoryCitation?.segmentID
                        : nil,
                    relatedNotes: relatedNotes(for: selectedNote),
                    coordinator: coordinator,
                    fileStore: LocalRecordingFileStore(),
                    folders: folders,
                    exportAction: { exportMarkdown(selectedNote) },
                    backAction: {
                        selectedNoteID = nil
                        selectedMemoryCitation = nil
                    },
                    selectRelatedNote: { selectedNoteID = $0 },
                    newRecordingAction: {
                        continueRecording(selectedNote)
                    }
                )
            } else if coordinator.captureState.isRecording {
                RecordingStatusView(coordinator: coordinator) {
                    Task { await coordinator.stop(context: modelContext) }
                }
            } else {
                home
            }
        }
        .frame(minWidth: 1_020, minHeight: 640)
        .tint(BurritoTheme.accent)
        .preferredColorScheme(appearance.colorScheme)
        .font(.spline(size: 13, weight: .regular))
        .sheet(item: $recordingDestination) { destination in
            RecordingSetupView(
                templates: templates,
                modelStore: modelStore,
                calendarEvent: destination.calendarEvent,
                openModels: {
                    recordingDestination = nil
                    selectedNoteID = nil
                    sidebarSelection = .models
                }
            ) { options in
                recordingDestination = nil
                Task {
                    await coordinator.start(
                        options: options,
                        destination: destination,
                        context: modelContext
                    )
                    selectedNoteID = coordinator.activeNoteID
                }
            }
        }
        .overlay {
            if isCommandPalettePresented {
                CommandPaletteView(
                    query: $commandPaletteQuery,
                    notes: notes.filter { $0.deletedAt == nil },
                    isSidebarVisible: isSidebarVisible,
                    dismiss: dismissCommandPalette,
                    selectCommand: performPaletteCommand,
                    selectNote: { noteID in
                        dismissCommandPalette()
                        selectedNoteID = noteID
                    }
                )
                .transition(commandPaletteTransition)
            } else if showingNewFolder {
                BurritoModalBackdrop {
                    NewFolderDialog(
                        name: $newFolderName,
                        cancel: {
                            newFolderName = ""
                            showingNewFolder = false
                        },
                        create: createFolder
                    )
                }
            } else if confirmingEmptyTrash {
                BurritoModalBackdrop {
                    BurritoMessageDialog(
                        title: "Empty Trash?",
                        message: "Every note in Trash will be permanently deleted. This cannot be undone.",
                        confirmTitle: "Empty Trash",
                        isDestructive: true,
                        cancel: { confirmingEmptyTrash = false },
                        confirm: {
                            confirmingEmptyTrash = false
                            emptyTrash()
                        }
                    )
                }
            } else if coordinator.smartStopStatus == .suggested {
                BurritoModalBackdrop {
                    BurritoMessageDialog(
                        title: "Is the meeting finished?",
                        message: "The scheduled meeting has ended and Burrito has heard sustained silence. Stop now to build the note, or keep recording.",
                        confirmTitle: "Stop recording",
                        isDestructive: false,
                        cancel: { coordinator.keepRecording() },
                        confirm: {
                            Task { await coordinator.stop(context: modelContext) }
                        }
                    )
                }
            } else if let error = coordinator.lastError {
                BurritoModalBackdrop {
                    if case .languageAssetMissing = error {
                        BurritoMessageDialog(
                            title: "Install transcription language",
                            message: error.recoveryMessage,
                            confirmTitle: "Install Language",
                            isDestructive: false,
                            isWorking: coordinator.isInstallingLanguageAsset,
                            cancel: { coordinator.dismissFailure() },
                            confirm: {
                                Task { await coordinator.installMissingLanguageAsset() }
                            }
                        )
                    } else {
                        BurritoMessageDialog(
                            title: "Burrito needs attention",
                            message: error.recoveryMessage,
                            confirmTitle: "Okay",
                            isDestructive: false,
                            cancel: nil,
                            confirm: { coordinator.dismissFailure() }
                        )
                    }
                }
            }
        }
        .onAppear {
            seedAndRecover()
            permissions.refresh()
            calendarAccess.refresh()
            Task { await notificationAccess.refresh() }
            synchronizeMeetingReminders()
            handlePendingMeetingAction()
            handlePendingRecordingDestination()
        }
        .task {
            await updater.checkIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refresh()
                calendarAccess.refresh()
                Task { await notificationAccess.refresh() }
                synchronizeMeetingReminders()
            }
        }
        .onChange(of: calendarAccess.upcomingEvents) {
            synchronizeMeetingReminders()
        }
        .onChange(of: notificationAccess.state) {
            if notificationAccess.canDeliverAlerts {
                synchronizeMeetingReminders()
            }
        }
        .onChange(of: meetingActionInbox.pending) {
            handlePendingMeetingAction()
        }
        .onChange(of: recordingDestinationInbox.pending) {
            handlePendingRecordingDestination()
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoNewRecording)) { _ in
            recordingDestination = .newNote
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoToggleRecording)) { _ in
            toggleRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoNewFolder)) { _ in
            showingNewFolder = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoCommandPalette)) { _ in
            presentCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoExportMarkdown)) { _ in
            if let selectedNote { exportMarkdown(selectedNote) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoOpenSettings)) { _ in
            selectedNoteID = nil
            sidebarSelection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoStopRecording)) { _ in
            guard coordinator.captureState.isRecording else { return }
            Task { await coordinator.stop(context: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoKeepRecording)) { _ in
            coordinator.keepRecording()
        }
    }

    private func finalTranscriptionEngine(for languageIdentifier: String) -> String {
        if let model = ParakeetModelStore.installedModel(for: languageIdentifier) {
            return model.displayName
        }
        return "Apple SpeechTranscriber"
    }

    private var home: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: 270)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Rectangle()
                    .fill(BurritoTheme.softBorder)
                    .frame(width: 1)
                    .transition(.opacity)
            }

            if sidebarSelection == .models {
                ModelsView(
                    modelStore: modelStore,
                    languageModelStore: languageModelStore
                )
            } else if sidebarSelection == .templates {
                TemplatesView(templates: templates)
            } else if sidebarSelection == .memory {
                MemoryChatView(
                    session: chatSessions.askBurrito,
                    documents: memoryNotes.map(memoryDocument),
                    languageIdentifier: defaultLanguage
                ) { citation in
                    selectedMemoryCitation = citation
                    selectedNoteID = citation.noteID
                }
            } else if sidebarSelection == .settings {
                BurritoSettingsView(
                    calendarAccess: calendarAccess,
                    exportLibrary: exportLibrary,
                    importLibrary: importLibrary,
                    ownershipStatus: ownershipStatus
                )
            } else {
                noteList
            }
        }
        .animation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? nil
                : .easeInOut(duration: 0.2),
            value: isSidebarVisible
        )
        .background(BurritoTheme.canvas)
        .overlay(alignment: .topLeading) {
            SidebarToggleButton(isExpanded: isSidebarVisible) {
                isSidebarVisible.toggle()
            }
            .padding(.leading, 92)
            .offset(y: -24)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 38)

            Button(action: presentCommandPalette) {
                HStack(spacing: 8) {
                    BurritoIcon(name: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    Text("Search")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("⌘K")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(BurritoTheme.softBorder.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .accessibilityLabel("Search notes and commands")
            .accessibilityHint("Opens the command palette")

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarNavigationButton(
                        title: "All Notes",
                        systemImage: "house.fill",
                        count: notes.filter { $0.deletedAt == nil }.count,
                        isSelected: sidebarSelection == .all
                    ) {
                        sidebarSelection = .all
                    }
                    SidebarNavigationButton(
                        title: "Favorites",
                        systemImage: "star.fill",
                        count: notes.filter { $0.deletedAt == nil && $0.isFavorite }.count,
                        isSelected: sidebarSelection == .favorites
                    ) {
                        sidebarSelection = .favorites
                    }
                    SidebarNavigationButton(
                        title: "Ask Burrito",
                        systemImage: "at",
                        count: 0,
                        isSelected: sidebarSelection == .memory
                    ) {
                        memoryFolderID = nil
                        sidebarSelection = .memory
                    }
                    SidebarNavigationButton(
                        title: "Models",
                        systemImage: "waveform",
                        count: 0,
                        isSelected: sidebarSelection == .models
                    ) {
                        sidebarSelection = .models
                    }
                    SidebarNavigationButton(
                        title: "Templates",
                        systemImage: "doc.text",
                        count: templates.count,
                        isSelected: sidebarSelection == .templates
                    ) {
                        sidebarSelection = .templates
                    }
                    SidebarNavigationButton(
                        title: "Trash",
                        systemImage: "trash.fill",
                        count: notes.filter { $0.deletedAt != nil }.count,
                        isSelected: sidebarSelection == .trash
                    ) {
                        sidebarSelection = .trash
                    }
                    SidebarNavigationButton(
                        title: "Settings",
                        systemImage: "gearshape",
                        count: 0,
                        isSelected: sidebarSelection == .settings
                    ) {
                        sidebarSelection = .settings
                    }

                    HStack {
                        BurritoSectionLabel(title: "Folders")
                        Spacer()
                        SidebarHeaderAddButton {
                            showingNewFolder = true
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 2)
                    .padding(.top, 22)
                    .padding(.bottom, 6)
                    ForEach(folders) { folder in
                        SidebarNavigationButton(
                            title: folder.name,
                            systemImage: "folder",
                            markerColor: FolderAccent.color(for: folder.id),
                            count: notes.filter { $0.deletedAt == nil && $0.folder?.id == folder.id }.count,
                            isSelected: sidebarSelection == .folder(folder.id)
                        ) {
                            sidebarSelection = .folder(folder.id)
                        }
                            .dropDestination(for: String.self) { values, _ in
                                return moveNotes(values, to: folder)
                            }
                            .contextMenu {
                                Button("Delete Folder", role: .destructive) {
                                    modelContext.delete(folder)
                                }
                            }
                    }

                }
                .padding(.horizontal, 8)
                .hidesEnclosingScrollIndicators()
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 0) {
                if updater.availableUpdate != nil {
                    UpdateAvailableCard(updater: updater)
                        .padding(8)
                }

                if notificationAccess.needsPrompt {
                    NotificationPermissionCard(access: notificationAccess)
                        .padding(8)
                }

                SidebarAccountCard(
                    profile: userProfile,
                    appearanceRawValue: $appearanceRawValue,
                    updater: updater
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(BurritoTheme.sidebar)
    }

    private var noteList: some View {
        ZStack(alignment: .top) {
            BurritoTheme.canvas

            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if sidebarSelection == .all {
                            Text("Coming up")
                                .font(.spline(size: 28, weight: .medium))
                                .padding(.bottom, 16)

                            CalendarCard(
                                calendarAccess: calendarAccess,
                                startRecording: startCalendarRecording,
                                openSettings: openCalendarSettings
                            )
                            .padding(.bottom, 24)
                        } else {
                            Text(sectionTitle)
                                .font(.spline(size: 26, weight: .bold))
                                .padding(.bottom, 20)
                        }
                    }
                    .frame(maxWidth: 780, alignment: .leading)
                    .padding(.horizontal, 38)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        notesTimeline
                    }
                    .frame(maxWidth: 780, alignment: .leading)
                    .padding(.horizontal, 38)
                    .padding(.bottom, 100)
                    .frame(maxWidth: .infinity)
                }
                .hidesEnclosingScrollIndicators()
            }
            .scrollIndicators(.hidden)
            .hidesEnclosingScrollIndicators()
        }
        .overlay(alignment: .topTrailing) {
            noteListAction
                .padding(.top, 12)
                .padding(.trailing, 18)
        }
    }

    @ViewBuilder
    private var noteListAction: some View {
        if sidebarSelection == .trash {
            Button {
                confirmingEmptyTrash = true
            } label: {
                BurritoLabel("Empty trash", systemImage: "trash")
            }
            .buttonStyle(HomeToolbarButtonStyle(destructive: true))
            .disabled(visibleNotes.isEmpty)
        } else {
            HStack(spacing: 8) {
                if case .folder(let folderID) = sidebarSelection {
                    Button {
                        memoryFolderID = folderID
                        sidebarSelection = .memory
                    } label: {
                        BurritoLabel("Ask folder", systemImage: "at")
                    }
                    .buttonStyle(HomeToolbarButtonStyle())
                }

                Button {
                    recordingDestination = .newNote
                } label: {
                    BurritoLabel("New recording", systemImage: "plus")
                }
                .buttonStyle(HomeToolbarButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var notesTimeline: some View {
        if visibleNotes.isEmpty {
            HomeEmptyState(
                isTrash: sidebarSelection == .trash,
                isSearching: false
            ) {
                recordingDestination = .newNote
            }
        } else {
            ForEach(noteDays, id: \.date) { group in
                Text(noteGroupTitle(for: group.date))
                    .font(.spline(size: 11, weight: 450))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 20)
                    .padding(.leading, 8)
                    .padding(.bottom, 6)
                ForEach(group.notes) { note in
                    TimelineNoteItem(
                        note: note,
                        folders: folders
                    ) {
                        selectedNoteID = note.id
                    }
                    .draggable(note.id.uuidString)
                    .contextMenu {
                        noteContextMenu(note)
                    }
                }
            }
        }
    }

    private func noteGroupTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    @ViewBuilder
    private func noteContextMenu(_ note: Note) -> some View {
        if note.deletedAt == nil {
            Button(note.isFavorite ? "Remove from Favorites" : "Favorite") {
                note.isFavorite.toggle()
            }
            Button("Move to Trash", role: .destructive) {
                note.deletedAt = .now
            }
        } else {
            Button("Restore") { note.deletedAt = nil }
            Button("Delete Permanently", role: .destructive) {
                modelContext.delete(note)
            }
        }
    }

    private var sectionTitle: String {
        switch sidebarSelection ?? .all {
        case .all: "All Notes"
        case .favorites: "Favorites"
        case .memory: "Ask Burrito"
        case .models: "Models"
        case .templates: "Templates"
        case .settings: "Settings"
        case .trash: "Trash"
        case .folder(let id): folders.first(where: { $0.id == id })?.name ?? "Folder"
        }
    }

    private func memoryDocument(_ note: Note) -> MemoryDocument {
        MemoryDocument(
            noteID: note.id,
            title: note.title,
            updatedAt: note.updatedAt,
            segments: note.transcriptSegments
        )
    }

    private var memoryFolder: Folder? {
        guard let memoryFolderID else { return nil }
        return folders.first { $0.id == memoryFolderID }
    }

    private var memoryNotes: [Note] {
        notes.filter { note in
            guard note.deletedAt == nil, !note.transcriptSegments.isEmpty else {
                return false
            }
            guard let memoryFolderID else { return true }
            return note.folder?.id == memoryFolderID
        }
    }

    private func seedAndRecover() {
        do {
            try SeedData.insertBuiltInTemplatesIfNeeded(context: modelContext)
            coordinator.recoverInterruptedNotes(context: modelContext)
        } catch {
            // Seed failures are exposed by the coordinator on subsequent storage operations.
        }
    }

    private func toggleRecording() {
        if coordinator.captureState.isRecording {
            Task { await coordinator.stop(context: modelContext) }
        } else if let selectedNote {
            continueRecording(selectedNote)
        } else {
            recordingDestination = .newNote
        }
    }

    private func continueRecording(_ note: Note) {
        Task {
            await coordinator.start(
                options: note.continuationRecordingOptions,
                destination: .appendToNote(id: note.id),
                context: modelContext
            )
            selectedNoteID = coordinator.activeNoteID
        }
    }

    private func presentCommandPalette() {
        commandPaletteQuery = ""
        withAnimation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? .easeOut(duration: 0.12)
                : .easeOut(duration: 0.18)
        ) {
            isCommandPalettePresented = true
        }
    }

    private func dismissCommandPalette() {
        commandPaletteQuery = ""
        withAnimation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? .easeOut(duration: 0.1)
                : .easeIn(duration: 0.13)
        ) {
            isCommandPalettePresented = false
        }
    }

    private var commandPaletteTransition: AnyTransition {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .opacity
        }
        return .modifier(
            active: CommandPalettePresentationModifier(
                opacity: 0,
                scale: 0.985,
                verticalOffset: -8
            ),
            identity: CommandPalettePresentationModifier(
                opacity: 1,
                scale: 1,
                verticalOffset: 0
            )
        )
    }

    private func performPaletteCommand(_ command: BurritoPaletteCommand) {
        dismissCommandPalette()

        switch command {
        case .newRecording:
            recordingDestination = .newNote
        case .newFolder:
            showingNewFolder = true
        case .allNotes:
            selectedNoteID = nil
            sidebarSelection = .all
        case .favorites:
            selectedNoteID = nil
            sidebarSelection = .favorites
        case .models:
            selectedNoteID = nil
            sidebarSelection = .models
        case .templates:
            selectedNoteID = nil
            sidebarSelection = .templates
        case .toggleSidebar:
            isSidebarVisible.toggle()
        case .settings:
            selectedNoteID = nil
            sidebarSelection = .settings
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Folder(name: name, order: folders.count))
        try? modelContext.save()
        newFolderName = ""
        showingNewFolder = false
    }

    private func moveNotes(_ values: [String], to folder: Folder) -> Bool {
        let ids = Set(values.compactMap(UUID.init(uuidString:)))
        let matches = notes.filter { ids.contains($0.id) }
        for note in matches { note.folder = folder }
        return !matches.isEmpty
    }

    private func emptyTrash() {
        for note in notes where note.deletedAt != nil {
            modelContext.delete(note)
        }
        try? modelContext.save()
        selectedNoteID = nil
    }

    private func openCalendarSettings() {
        calendarAccess.openSystemSettings()
    }

    private func relatedNotes(for note: Note) -> [Note] {
        guard let event = note.calendarEvent else { return [] }
        return notes.filter { candidate in
            guard candidate.id != note.id,
                  candidate.deletedAt == nil,
                  let candidateEvent = candidate.calendarEvent
            else {
                return false
            }
            return candidateEvent.relatedMeetingIdentifier == event.relatedMeetingIdentifier
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func startCalendarRecording(_ event: UpcomingCalendarEvent) {
        startCalendarRecording(event.snapshot, joinsMeeting: true)
    }

    private func startCalendarRecording(
        _ event: CalendarEventSnapshot,
        joinsMeeting: Bool
    ) {
        if joinsMeeting, let meetingURL = event.meetingURL {
            NSWorkspace.shared.open(meetingURL)
        }
        guard let template = templates.first(where: {
            $0.builtInID == BuiltInTemplate.meeting.rawValue
        })
            ?? templates.first(where: { $0.builtInID == defaultTemplateID })
            ?? templates.first
        else {
            recordingDestination = .calendarEvent(event)
            return
        }
        Task {
            await coordinator.start(
                options: RecordingOptions(
                    template: template.snapshot,
                    languageIdentifier: defaultLanguage,
                    mode: .meeting,
                    retainsAudio: defaultRetainsAudio
                ),
                destination: .calendarEvent(event),
                context: modelContext
            )
            selectedNoteID = coordinator.activeNoteID
        }
    }

    private func synchronizeMeetingReminders() {
        let events = calendarAccess.upcomingEvents
        Task {
            await MeetingReminderScheduler.shared.synchronize(events: events)
        }
    }

    private func handlePendingMeetingAction() {
        guard let action = meetingActionInbox.consume() else { return }
        switch action {
        case .record(let event, let joinsMeeting):
            startCalendarRecording(event, joinsMeeting: joinsMeeting)
        }
    }

    private func handlePendingRecordingDestination() {
        guard let destination = recordingDestinationInbox.consume() else { return }
        recordingDestination = destination
    }

    private func exportMarkdown(_ note: Note) {
        let panel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        panel.nameFieldStringValue = "\(note.title).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try note.exportedMarkdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func exportLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Export Burrito Library"
        panel.message = "Choose where Burrito should create the backup folder."
        panel.prompt = "Export Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let baseName = "Burrito Export \(formatter.string(from: .now))"
        var destination = parent.appending(path: baseName, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: destination.path()) {
            destination = parent.appending(
                path: "\(baseName) \(UUID().uuidString.prefix(4))",
                directoryHint: .isDirectory
            )
        }

        let recordingStore = LocalRecordingFileStore()
        let input = BurritoArchivePackage.prepareExport(
            notes: notes,
            folders: folders,
            templates: templates,
            recordingStore: recordingStore
        )
        ownershipStatus = .running("Exporting your library…")
        Task {
            do {
                let report = try await BurritoArchivePackage.export(
                    input,
                    to: destination
                )
                ownershipStatus = .success(
                    "Exported \(report.notesExported) notes and \(report.audioFilesExported) audio files to \(destination.lastPathComponent)."
                )
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                ownershipStatus = .failure(ownershipRecoveryMessage(for: error))
            }
        }
    }

    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Import Burrito Backup"
        panel.message = "Choose a Burrito export folder or its burrito.json file."
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }

        ownershipStatus = .running("Validating and importing your backup…")
        Task {
            do {
                let report = try await BurritoArchivePackage.restore(
                    from: source,
                    into: modelContext,
                    recordingStore: LocalRecordingFileStore()
                )
                ownershipStatus = .success(
                    "Imported \(report.notesInserted) notes, \(report.foldersInserted) folders, \(report.templatesInserted) templates, and \(report.audioFilesRestored) audio files. Skipped \(report.duplicatesSkipped) existing items."
                )
            } catch {
                ownershipStatus = .failure(ownershipRecoveryMessage(for: error))
            }
        }
    }

    private func ownershipRecoveryMessage(for error: Error) -> String {
        if let archiveError = error as? BurritoArchiveError {
            return archiveError.recoveryMessage
        }
        return "Burrito could not complete the library operation: \(error.localizedDescription) Existing notes were not changed."
    }
}

private enum BurritoPaletteCommand: String, CaseIterable, Identifiable {
    case newRecording
    case newFolder
    case allNotes
    case favorites
    case models
    case templates
    case toggleSidebar
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newRecording: "New recording"
        case .newFolder: "New folder"
        case .allNotes: "Go to All Notes"
        case .favorites: "Go to Favorites"
        case .models: "Manage transcription models"
        case .templates: "Manage note templates"
        case .toggleSidebar: "Toggle sidebar"
        case .settings: "Open Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .newRecording: "waveform"
        case .newFolder: "folder.badge.plus"
        case .allNotes: "house"
        case .favorites: "star"
        case .models: "waveform.badge.magnifyingglass"
        case .templates: "doc.text"
        case .toggleSidebar: "sidebar.left"
        case .settings: "gearshape"
        }
    }

    var shortcut: String? {
        switch self {
        case .newRecording: "⌘N"
        case .newFolder: "⇧⌘N"
        case .settings: "⌘,"
        case .allNotes, .favorites, .models, .templates, .toggleSidebar: nil
        }
    }

    fileprivate func matches(_ query: String) -> Bool {
        title.localizedStandardContains(query)
            || rawValue.localizedStandardContains(query)
    }
}

private struct CommandPalettePresentationModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let verticalOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
            .offset(y: verticalOffset)
    }
}

private struct CommandPaletteView: View {
    private enum ResultID: Hashable {
        case command(BurritoPaletteCommand)
        case note(UUID)
    }

    @Binding var query: String
    let notes: [Note]
    let isSidebarVisible: Bool
    let dismiss: () -> Void
    let selectCommand: (BurritoPaletteCommand) -> Void
    let selectNote: (UUID) -> Void

    @FocusState private var queryFocused: Bool
    @State private var selectedResult: ResultID?
    @Namespace private var selectionAnimation

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingCommands: [BurritoPaletteCommand] {
        guard !normalizedQuery.isEmpty else {
            return BurritoPaletteCommand.allCases
        }
        return BurritoPaletteCommand.allCases.filter { $0.matches(normalizedQuery) }
    }

    private var matchingNotes: [Note] {
        let candidates = notes.sorted { $0.updatedAt > $1.updatedAt }
        guard !normalizedQuery.isEmpty else {
            return Array(candidates.prefix(4))
        }
        return Array(
            candidates.filter {
                $0.title.localizedStandardContains(normalizedQuery)
                    || $0.markdownBody.localizedStandardContains(normalizedQuery)
                    || $0.userNotes.localizedStandardContains(normalizedQuery)
                    || ($0.calendarEvent?.generationContext
                        .localizedStandardContains(normalizedQuery) ?? false)
                    || Transcript.rendered($0.transcriptSegments)
                        .localizedStandardContains(normalizedQuery)
            }
            .prefix(8)
        )
    }

    private var hasResults: Bool {
        !matchingCommands.isEmpty || !matchingNotes.isEmpty
    }

    private var resultIDs: [ResultID] {
        matchingCommands.map(ResultID.command)
            + matchingNotes.map { ResultID.note($0.id) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    BurritoIcon(name: "magnifyingglass", size: 15)
                        .foregroundStyle(BurritoTheme.accent)

                    TextField("Search notes and commands", text: $query)
                        .textFieldStyle(.plain)
                        .font(.spline(size: 16, weight: .regular))
                        .focused($queryFocused)
                        .onSubmit(performFirstResult)
                        .onKeyPress(.downArrow) {
                            moveSelection(by: 1)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            moveSelection(by: -1)
                            return .handled
                        }

                    Text("ESC")
                        .font(.spline(size: 9, weight: 450))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(.horizontal, 18)
                .frame(height: 58)

                Rectangle()
                    .fill(BurritoTheme.softBorder)
                    .frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !matchingCommands.isEmpty {
                                paletteSectionTitle("Commands")
                                ForEach(matchingCommands) { command in
                                    commandRow(command)
                                        .id(ResultID.command(command))
                                }
                            }

                            if !matchingNotes.isEmpty {
                                paletteSectionTitle(
                                    normalizedQuery.isEmpty ? "Recent notes" : "Notes"
                                )
                                ForEach(matchingNotes) { note in
                                    noteRow(note)
                                        .id(ResultID.note(note.id))
                                }
                            }

                            if !hasResults {
                                VStack(spacing: 8) {
                                    BurritoIcon(name: "magnifyingglass", size: 20)
                                        .foregroundStyle(.tertiary)
                                    Text("Nothing found")
                                        .font(.spline(size: 13, weight: .regular))
                                    Text("Try a note title or command.")
                                        .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 42)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                    .hidesEnclosingScrollIndicators()
                    .onChange(of: selectedResult) { _, result in
                        guard let result else { return }
                        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                            proxy.scrollTo(result, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.14)) {
                                proxy.scrollTo(result, anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxHeight: 390)
            }
            .frame(width: 560)
            .background(BurritoTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BurritoTheme.softBorder)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 16)
        }
        .task {
            selectedResult = resultIDs.first
            await Task.yield()
            queryFocused = true
        }
        .onChange(of: query) {
            selectedResult = resultIDs.first
        }
        .onExitCommand(perform: dismiss)
        .accessibilityAddTraits(.isModal)
    }

    private func paletteSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.spline(size: 9, weight: 450))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func commandRow(_ command: BurritoPaletteCommand) -> some View {
        Button {
            selectCommand(command)
        } label: {
            HStack(spacing: 12) {
                BurritoIcon(name: command.systemImage, size: 13)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(command == .toggleSidebar
                    ? (isSidebarVisible ? "Hide sidebar" : "Show sidebar")
                    : command.title
                )
                .font(.spline(size: 13, weight: .regular))

                Spacer()

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.spline(size: 10, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            CommandPaletteRowButtonStyle()
        )
        .background {
            if selectedResult == .command(command) {
                selectionHighlight
            }
        }
        .padding(.horizontal, 6)
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            selectNote(note.id)
        } label: {
            HStack(spacing: 12) {
                BurritoIcon(name: note.templateSymbol, size: 13)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.spline(size: 13, weight: .regular))
                        .lineLimit(1)
                    Text(note.templateName)
                        .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(PaletteNoteAge.label(updatedAt: note.updatedAt))
                    .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            CommandPaletteRowButtonStyle()
        )
        .background {
            if selectedResult == .note(note.id) {
                selectionHighlight
            }
        }
        .padding(.horizontal, 6)
    }

    private var selectionHighlight: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(BurritoTheme.accentSoft)
            .matchedGeometryEffect(id: "command-palette-selection", in: selectionAnimation)
    }

    private func performFirstResult() {
        let result = selectedResult ?? resultIDs.first
        BurritoHaptics.trigger(.levelChange)
        switch result {
        case .command(let command):
            selectCommand(command)
        case .note(let noteID):
            selectNote(noteID)
        case nil:
            break
        }
    }

    private func moveSelection(by offset: Int) {
        guard !resultIDs.isEmpty else {
            selectedResult = nil
            return
        }

        let currentIndex = selectedResult.flatMap(resultIDs.firstIndex) ?? 0
        let nextIndex = (currentIndex + offset + resultIDs.count) % resultIDs.count
        updateSelection(resultIDs[nextIndex])
    }

    private func updateSelection(_ result: ResultID) {
        if selectedResult != result {
            BurritoHaptics.trigger(.alignment)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            selectedResult = result
        } else {
            withAnimation(.burritoSpring) {
                selectedResult = result
            }
        }
    }
}

private struct CommandPaletteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct SidebarAccountCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profile: MacUserProfile
    @Binding var appearanceRawValue: String
    @Bindable var updater: BurritoUpdateManager
    @State private var isProfilePresented = false

    private var appearance: BurritoAppearance {
        BurritoAppearance.resolve(appearanceRawValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("APPEARANCE")
                    .font(.spline(size: 9, weight: 450))
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 2) {
                    ForEach(BurritoAppearance.allCases) { option in
                        Button {
                            BurritoHaptics.trigger(.alignment)
                            if reduceMotion {
                                appearanceRawValue = option.rawValue
                            } else {
                                withAnimation(.burritoSpring) {
                                    appearanceRawValue = option.rawValue
                                }
                            }
                        } label: {
                            BurritoIcon(name: option.systemImage, size: 11)
                                .foregroundStyle(
                                    appearance == option ? BurritoTheme.accent : .secondary
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(
                                    appearance == option
                                        ? BurritoTheme.accentSoft
                                        : BurritoTheme.controlFill,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                        .accessibilityLabel("\(option.title) appearance")
                        .accessibilityAddTraits(appearance == option ? .isSelected : [])
                    }
                }
            }
            .padding(11)

            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)

            Button {
                isProfilePresented.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: profile.image ?? NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(BurritoTheme.softBorder)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.spline(size: 13, weight: 450))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("Local account")
                            .font(.spline(size: 10, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    BurritoIcon(
                        name: "ellipsis",
                        size: 10,
                        accessibilityLabel: "Account and updates"
                    )
                        .foregroundStyle(.tertiary)
                }
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: $isProfilePresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                AccountPopover(profile: profile, updater: updater)
            }
        }
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BurritoTheme.softBorder)
        }
    }
}

private struct AccountPopover: View {
    let profile: MacUserProfile
    @Bindable var updater: BurritoUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: profile.image ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.spline(size: 13, weight: 450))
                    Text("Private on this Mac")
                        .font(.spline(size: 10, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)

            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Burrito \(updater.currentVersion)")
                            .font(.spline(size: 12, weight: 450))
                        Text(updateDetail)
                            .font(.spline(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if updater.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if updater.availableUpdate != nil {
                    Button(primaryActionTitle) {
                        Task { await updater.performPrimaryAction() }
                    }
                    .buttonStyle(UpdateActionButtonStyle())
                } else {
                    Button("Check for Updates") {
                        Task { await updater.checkForUpdates() }
                    }
                    .buttonStyle(UpdateActionButtonStyle())
                    .disabled(updater.isChecking)
                }
            }
            .padding(14)
        }
        .frame(width: 250)
        .background(BurritoTheme.raised)
        .presentationBackground(BurritoTheme.raised)
    }

    private var primaryActionTitle: String {
        "Update Now"
    }

    private var updateDetail: String {
        switch updater.status {
        case .idle:
            "Updates are checked daily."
        case .checking:
            "Checking GitHub Releases…"
        case .upToDate:
            "You’re using the latest version."
        case .available(let update):
            "Version \(update.version) is ready."
        case .failed(let failure):
            "\(failure.message) \(failure.recovery)"
        }
    }
}

private struct UpdateAvailableCard: View {
    @Bindable var updater: BurritoUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                BurritoIcon(name: "arrow.down.circle", size: 11)
                    .foregroundStyle(BurritoTheme.accent)
                Text("UPDATE AVAILABLE")
                    .font(.system(size: 9, weight: 450, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }

            if let update = updater.availableUpdate {
                Text("Burrito \(update.version) is ready to install.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(actionTitle) {
                Task { await updater.performPrimaryAction() }
            }
            .buttonStyle(UpdateActionButtonStyle())
        }
        .padding(11)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BurritoTheme.softBorder)
        }
    }

    private var actionTitle: String {
        "Update Now"
    }
}

private struct UpdateActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.spline(size: 10, weight: 450))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .foregroundStyle(.primary)
            .background(
                configuration.isPressed
                    ? BurritoTheme.accentSoft
                    : BurritoTheme.controlFill,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(BurritoTheme.softBorder)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct NotificationPermissionCard: View {
    @Bindable var access: NotificationAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                BurritoIcon(name: "bell", size: 11)
                    .foregroundStyle(BurritoTheme.accent)
                Text("DON'T MISS A NOTE")
                    .font(.system(size: 9, weight: 450, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }

            Text(
                message
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await access.requestAccess() }
            } label: {
                Text(access.actionTitle)
                    .font(.system(size: 10, weight: 450))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .foregroundStyle(.primary)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(BurritoTheme.softBorder)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BurritoTheme.softBorder)
        }
    }

    private var message: String {
        switch access.state {
        case .needsAlertStyle:
            "Choose Banners or Alerts in System Settings."
        case .denied:
            "Notifications are off in System Settings."
        case .deliveryFailed:
            "macOS could not deliver the last notification."
        case .unknown, .needsAccess, .granted:
            "Know when recording starts and your note is ready."
        }
    }
}

private struct ModelsView: View {
    private enum Tab {
        case speechToText
        case textModels
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var modelStore: ParakeetModelStore
    @Bindable var languageModelStore: LocalLanguageModelStore

    @State private var selectedTab: Tab = .speechToText

    private var hasInstalledModels: Bool {
        ParakeetModelVariant.allCases.contains {
            if case .installed = modelStore.state(for: $0) {
                return true
            }
            return false
        }
    }

    private var activeEngineTitle: String {
        switch languageModelStore.selection {
        case .apple: "Apple Intelligence"
        case .local(let variant): variant.displayName
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44)

            // Header Section
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("Models")
                            .font(.spline(size: 26, weight: 450))
                            .foregroundStyle(.primary)

                        Text("On-device AI")
                            .font(.spline(size: 11, weight: 450, relativeTo: .caption))
                            .foregroundStyle(BurritoTheme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(BurritoTheme.accent.opacity(0.25))
                            }
                    }

                    Text("Download private models for transcription and note synthesis.")
                        .font(.spline(size: 13, weight: 400, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Segmented Tab Switcher (Speech to Text vs Text Models)
                HStack(spacing: 2) {
                    Button {
                        BurritoHaptics.trigger(.alignment)
                        withAnimation(reduceMotion ? nil : .burritoSpring) {
                            selectedTab = .speechToText
                        }
                    } label: {
                        BurritoLabel("Speech to Text", systemImage: "waveform")
                            .font(.spline(size: 12, weight: selectedTab == .speechToText ? 450 : 400))
                            .foregroundStyle(selectedTab == .speechToText ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                selectedTab == .speechToText ? BurritoTheme.controlFill : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        BurritoHaptics.trigger(.alignment)
                        withAnimation(reduceMotion ? nil : .burritoSpring) {
                            selectedTab = .textModels
                        }
                    } label: {
                        BurritoLabel("Text Models", systemImage: "sparkles")
                            .font(.spline(size: 12, weight: selectedTab == .textModels ? 450 : 400))
                            .foregroundStyle(selectedTab == .textModels ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                selectedTab == .textModels ? BurritoTheme.controlFill : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(3)
                .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 22)

            // Content Body for Selected Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if selectedTab == .speechToText {
                        // SPEECH TO TEXT TAB
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(BurritoTheme.accentSoft)
                                        .frame(width: 38, height: 38)
                                    BurritoIcon(name: hasInstalledModels ? "waveform" : "apple.logo", size: 16)
                                        .foregroundStyle(BurritoTheme.accent)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hasInstalledModels ? "Downloaded models active" : "Apple Speech active")
                                        .font(.spline(size: 13, weight: 450))
                                        .foregroundStyle(.primary)
                                    Text(
                                        hasInstalledModels
                                            ? "Parakeet handles supported languages; Apple Speech acts as fallback."
                                            : "Install a model below to process recordings automatically on-device."
                                    )
                                    .font(.spline(size: 11, weight: 400, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BurritoTheme.softBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                BurritoSectionLabel(title: "PARAKEET SPEECH MODELS")
                                Spacer()
                                Text("Models stay on this Mac")
                                    .font(.spline(size: 11, weight: 400, relativeTo: .caption))
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(spacing: 0) {
                                ForEach(
                                    Array(ParakeetModelVariant.allCases.enumerated()),
                                    id: \.element
                                ) { index, variant in
                                    ModelCatalogRow(
                                        variant: variant,
                                        state: modelStore.state(for: variant)
                                    ) {
                                        Task { await modelStore.install(variant) }
                                    }

                                    if index < ParakeetModelVariant.allCases.count - 1 {
                                        Divider().padding(.leading, 20)
                                    }
                                }
                            }
                            .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BurritoTheme.softBorder)
                            }
                        }

                        Text("Burrito automatically picks the optimal installed speech model for the recording language.")
                            .font(.spline(size: 11, weight: 400, relativeTo: .caption))
                            .foregroundStyle(.tertiary)

                    } else {
                        // TEXT MODELS TAB
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(BurritoTheme.accentSoft)
                                        .frame(width: 38, height: 38)
                                    BurritoIcon(name: "sparkles", size: 16)
                                        .foregroundStyle(BurritoTheme.accent)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active Engine: \(activeEngineTitle)")
                                        .font(.spline(size: 13, weight: 450))
                                        .foregroundStyle(.primary)
                                    Text("Used for prompt synthesis, structure parsing, and note generation.")
                                        .font(.spline(size: 11, weight: 400, relativeTo: .caption))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BurritoTheme.softBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                BurritoSectionLabel(title: "NOTE GENERATION MODELS")
                                Spacer()
                                Text("Apple Intelligence is the default")
                                    .font(.spline(size: 11, weight: 400, relativeTo: .caption))
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(spacing: 0) {
                                GenerationModelCatalogRow(
                                    title: "Apple Intelligence",
                                    summary: "Built into macOS. Lightweight, private, and always available.",
                                    parameterCount: "System model",
                                    downloadSize: "No download",
                                    isSelected: languageModelStore.selection == .apple,
                                    state: nil
                                ) {
                                    languageModelStore.select(.apple)
                                }

                                Divider().padding(.leading, 20)

                                ForEach(
                                    Array(LocalLanguageModelVariant.allCases.enumerated()),
                                    id: \.element
                                ) { index, variant in
                                    GenerationModelCatalogRow(
                                        title: variant.displayName,
                                        summary: variant.summary,
                                        parameterCount: variant.parameterCount,
                                        downloadSize: variant.downloadSize,
                                        isSelected: languageModelStore.selection == .local(variant),
                                        state: languageModelStore.state(for: variant)
                                    ) {
                                        switch languageModelStore.state(for: variant) {
                                        case .installed:
                                            languageModelStore.select(.local(variant))
                                        case .notInstalled, .paused, .failed:
                                            Task { await languageModelStore.install(variant) }
                                        case .downloading:
                                            languageModelStore.cancelInstallation(variant)
                                        }
                                    }

                                    if index < LocalLanguageModelVariant.allCases.count - 1 {
                                        Divider().padding(.leading, 20)
                                    }
                                }
                            }
                            .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BurritoTheme.softBorder)
                            }
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.top, 12)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(BurritoTheme.canvas)
        .onAppear {
            modelStore.refresh()
            languageModelStore.refresh()
        }
    }
}

private struct GenerationModelCatalogRow: View {
    let title: String
    let summary: String
    let parameterCount: String
    let downloadSize: String
    let isSelected: Bool
    let state: LocalLanguageModelState?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.spline(size: 14, weight: 450))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.spline(size: 12, weight: 400))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    ModelProperty(systemImage: "cpu", value: parameterCount)
                    ModelProperty(systemImage: "arrow.down.circle", value: downloadSize)
                    ModelProperty(systemImage: "lock", value: "On-device")
                    if state != nil {
                        ModelProperty(systemImage: "wrench.and.screwdriver", value: "Tool calling")
                    }
                }
            }

            Spacer(minLength: 18)
            modelAction.frame(minWidth: 88, alignment: .trailing)
        }
        .padding(20)
    }

    @ViewBuilder
    private var modelAction: some View {
        if isSelected {
            BurritoLabel("In use", systemImage: "checkmark")
                .font(.spline(size: 11, weight: 450))
                .foregroundStyle(BurritoTheme.accent)
        } else if let state {
            switch state {
            case .notInstalled:
                BurritoInlineButton(title: "Install", systemImage: "arrow.down", action: action)
            case .paused(let progress):
                VStack(alignment: .trailing, spacing: 6) {
                    BurritoInlineButton(title: "Resume", systemImage: "arrow.clockwise", action: action)
                    Text("\(max(1, Int(progress * 100)))% saved")
                        .font(.spline(size: 9, weight: 400, relativeTo: .caption2))
                        .foregroundStyle(.tertiary)
                }
            case .downloading(let progress):
                VStack(alignment: .trailing, spacing: 7) {
                    BurritoInlineButton(
                        title: "Cancel",
                        systemImage: "xmark",
                        action: action
                    )
                    Text("\(Int(progress * 100))%")
                        .font(.spline(size: 10, weight: 450, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(BurritoTheme.controlFill)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(BurritoTheme.accent)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(width: 82, height: 3)
                }
                .accessibilityLabel("Installing \(title)")
                .accessibilityValue("\(Int(progress * 100)) percent")
            case .installed:
                BurritoInlineButton(title: "Use", systemImage: "checkmark", action: action)
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 5) {
                    BurritoInlineButton(title: "Retry", systemImage: "arrow.clockwise", action: action)
                    Text(message)
                        .font(.spline(size: 9, weight: 400))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 130, alignment: .trailing)
                }
            }
        } else {
            BurritoInlineButton(title: "Use", systemImage: "apple.logo", action: action)
        }
    }
}

private struct ModelCatalogRow: View {
    let variant: ParakeetModelVariant
    let state: ParakeetModelState
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(variant.displayName)
                        .font(.spline(size: 14, weight: 450))
                        .foregroundStyle(.primary)
                    Text(variant.summary)
                        .font(.spline(size: 12, weight: 400))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    ModelProperty(
                        systemImage: "cpu",
                        value: variant.parameterCount
                    )
                    ModelProperty(
                        systemImage: "character.bubble",
                        value: variant.languageSummary
                    )
                    ModelProperty(
                        systemImage: "arrow.down.circle",
                        value: variant.downloadSize
                    )
                    ModelProperty(
                        systemImage: "lock",
                        value: "On-device"
                    )
                }
            }

            Spacer(minLength: 18)

            modelAction
                .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(20)
    }

    @ViewBuilder
    private var modelAction: some View {
        switch state {
        case .notInstalled:
            BurritoInlineButton(
                title: "Install",
                systemImage: "arrow.down",
                action: install
            )
        case .paused(let progress):
            VStack(alignment: .trailing, spacing: 6) {
                BurritoInlineButton(
                    title: "Resume",
                    systemImage: "arrow.clockwise",
                    action: install
                )
                Text("\(max(1, Int(progress * 100)))% saved")
                    .font(.spline(size: 9, weight: 400, relativeTo: .caption2))
                    .foregroundStyle(.tertiary)
            }
        case .downloading(let progress):
            VStack(alignment: .trailing, spacing: 7) {
                Text("\(Int(progress * 100))%")
                    .font(.spline(size: 10, weight: 450, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(BurritoTheme.controlFill)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(BurritoTheme.accent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(width: 82, height: 3)
            }
            .accessibilityLabel("Installing \(variant.displayName)")
            .accessibilityValue("\(Int(progress * 100)) percent")
        case .installed:
            BurritoLabel("Installed", systemImage: "checkmark")
                .font(.spline(size: 11, weight: 450))
                .foregroundStyle(BurritoTheme.accent)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 5) {
                BurritoInlineButton(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    action: install
                )
                Text(message)
                    .font(.spline(size: 9, weight: 400))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
        }
    }
}

private struct ModelProperty: View {
    let systemImage: String
    let value: String

    var body: some View {
        BurritoLabel(value, systemImage: systemImage)
            .font(.spline(size: 10, weight: 400, relativeTo: .caption2))
            .foregroundStyle(.secondary)
    }
}

private struct ScooterGenerationLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: ProcessingStage
    let transcriptionEngine: String

    private var stageIndex: Int {
        ProcessingStage.allCases.firstIndex(of: stage) ?? 0
    }

    private var copy: (eyebrow: String, title: String, detail: String) {
        switch stage {
        case .preparingAudio:
            (
                "SECURING THE RECORDING · 1 OF 4",
                "Packing up every sound",
                "Closing the audio tracks cleanly so nothing gets lost between record and replay."
            )
        case .transcribing:
            (
                "LOCAL TRANSCRIPTION · 2 OF 4",
                "Re-listening with \(transcriptionEngine)",
                "Rebuilding the transcript from the saved audio—not correcting the live preview."
            )
        case .organizing:
            (
                "SHAPING THE TRANSCRIPT · 3 OF 4",
                "Finding the thread",
                "Merging voices, restoring chronology, and separating the useful signal from repetition."
            )
        case .generatingNotes:
            (
                "WRITING YOUR NOTE · 4 OF 4",
                "Turning speech into something useful",
                "Building the note while testing its title against the full conversation."
            )
        }
    }

    var body: some View {
        ZStack {
            BurritoTheme.canvas.ignoresSafeArea()

            VStack(spacing: 4) {
                if reduceMotion {
                    LottieView(animation: .named("Scooter-loader"))
                        .currentProgress(0.5)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 320, height: 320)
                } else {
                    LottieView(animation: .named("Scooter-loader"))
                        .playing(loopMode: .loop)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 320, height: 320)
                }

                VStack(spacing: 12) {
                    Text(copy.eyebrow)
                        .font(.system(size: 10, weight: .init(450), design: .monospaced))
                        .tracking(1.35)
                        .foregroundStyle(BurritoTheme.accent.opacity(0.86))

                    Text(copy.title)
                        .font(.burritoDisplay(size: 28, weight: .init(400)))
                        .tracking(-0.35)
                        .foregroundStyle(.primary)

                    Text(copy.detail)
                        .font(.system(size: 14, weight: .init(400)))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 470)

                    HStack(spacing: 18) {
                        ForEach(
                            Array(ProcessingStage.allCases.enumerated()),
                            id: \.element
                        ) { index, item in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(stageColor(at: index))
                                    .frame(width: 5, height: 5)
                                Text(shortLabel(for: item))
                                    .font(.system(size: 10, weight: .init(450)))
                                    .foregroundStyle(stageColor(at: index))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .id(stage)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(y: 8))
                )
            }
            .offset(y: -22)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.32),
                value: stage
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(copy.title). \(copy.detail)")
    }

    private func shortLabel(for stage: ProcessingStage) -> String {
        switch stage {
        case .preparingAudio: "Audio"
        case .transcribing: "Transcript"
        case .organizing: "Structure"
        case .generatingNotes: "Note"
        }
    }

    private func stageColor(at index: Int) -> Color {
        if index == stageIndex {
            BurritoTheme.accent
        } else if index < stageIndex {
            BurritoTheme.accent.opacity(0.5)
        } else {
            Color.secondary.opacity(0.3)
        }
    }
}

private struct PermissionGateView: View {
    @Bindable var permissions: PermissionAccess
    @Bindable var calendarAccess: CalendarAccess
    let continueAction: () -> Void

    var body: some View {
        ZStack {
            BurritoTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                BurritoSectionLabel(title: "Permissions")
                VStack(alignment: .leading, spacing: 14) {
                    Text("Allow Burrito to listen\nand take notes")
                        .font(.burritoDisplay(size: 42, weight: .init(400)))
                        .tracking(-0.5)
                    Text("Burrito captures audio and transcribes it privately on this Mac. Nothing joins your calls and nothing is uploaded.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .frame(maxWidth: 620, alignment: .leading)
                }

                VStack(spacing: 0) {
                    PermissionRow(
                        title: "Transcribe your voice",
                        subtitle: "Microphone",
                        systemImage: "mic",
                        state: permissions.microphone,
                        openSettings: {
                            permissions.openSettings(for: .microphone)
                        }
                    ) {
                        Task { await permissions.requestMicrophone() }
                    }
                    Divider().opacity(0.45)
                    PermissionRow(
                        title: "Transcribe computer audio",
                        subtitle: "System Audio",
                        systemImage: "speaker.wave.2",
                        state: permissions.systemAudio,
                        openSettings: {
                            permissions.openSettings(for: .systemAudio)
                        }
                    ) {
                        permissions.requestSystemAudio()
                    }
                    Divider().opacity(0.45)
                    CalendarPermissionRow(calendarAccess: calendarAccess)
                }
                .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BurritoTheme.softBorder)
                }

                HStack {
                    Text(
                        permissions.allGranted
                            ? "Calendar is optional. Everything stays on this Mac."
                            : "Grant both audio permissions to continue. Calendar is optional."
                    )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    BurritoButton("Continue", systemImage: "arrow.right", action: continueAction)
                        .buttonStyle(BurritoActionButtonStyle(prominent: true))
                        .disabled(!permissions.allGranted)
                }
            }
            .padding(50)
            .frame(width: 820)
            .background(BurritoTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BurritoTheme.softBorder)
            }
        }
    }
}

private struct CalendarPermissionRow: View {
    @Bindable var calendarAccess: CalendarAccess

    var body: some View {
        HStack(spacing: 16) {
            BurritoIcon(name: "calendar", size: 16)
                .foregroundStyle(
                    calendarAccess.state == .authorized ? BurritoTheme.accent : .secondary
                )
                .frame(width: 36, height: 36)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Show upcoming meetings")
                    .font(.system(size: 14, weight: .init(450)))
                Text(calendarDetail)
                    .font(.caption)
                    .foregroundStyle(
                        calendarAccess.state == .denied ? Color.red : Color.secondary.opacity(0.7)
                    )
            }

            Spacer()
            calendarAction
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 82)
    }

    @ViewBuilder
    private var calendarAction: some View {
        switch calendarAccess.state {
        case .authorized:
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(BurritoTheme.accent)
                    BurritoIcon(name: "checkmark", size: 9)
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                Text("Connected")
            }
            .font(.system(size: 13, weight: .init(450)))
            .foregroundStyle(.secondary)
        case .requesting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 100)
        case .denied:
            Button("Open Settings") {
                calendarAccess.openSystemSettings()
            }
            .buttonStyle(BurritoActionButtonStyle(prominent: false))
        case .notDetermined, .failed:
            Button("Connect Calendar") {
                Task { await calendarAccess.requestAccess() }
            }
            .buttonStyle(BurritoActionButtonStyle(prominent: false))
        }
    }

    private var calendarDetail: String {
        switch calendarAccess.state {
        case .notDetermined:
            "Calendar · Optional"
        case .requesting:
            "Waiting for macOS permission…"
        case .authorized:
            "Calendar access allowed"
        case .denied:
            "Access denied — allow Burrito in System Settings."
        case .failed(let message):
            "Couldn’t connect: \(message)"
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let state: PermissionAccess.State
    let openSettings: () -> Void
    let request: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            BurritoIcon(name: systemImage, size: 16)
                .foregroundStyle(state == .granted ? BurritoTheme.accent : .secondary)
                .frame(width: 36, height: 36)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .init(450)))
                Text(state == .denied ? "Access denied — open System Settings to allow \(subtitle)." : subtitle)
                    .font(.caption)
                .foregroundStyle(state == .denied ? Color.red : Color.secondary.opacity(0.7))
            }
            Spacer()
            if state == .granted {
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(BurritoTheme.accent)
                        BurritoIcon(name: "checkmark", size: 9)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 18, height: 18)
                    Text("Allowed")
                }
                .font(.system(size: 13, weight: .init(450)))
                .foregroundStyle(.secondary)
            } else {
                Button(
                    state == .denied ? "Open Settings" : "Enable \(subtitle)",
                    action: state == .denied ? openSettings : request
                )
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 82)
    }
}

private struct BurritoActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .init(450)))
            .foregroundStyle(prominent ? Color(nsColor: .textBackgroundColor) : .primary)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                prominent ? Color.primary : BurritoTheme.controlFill,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(BurritoTheme.softBorder)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.34)
            .burritoPressFeedback(
                isPressed: configuration.isPressed,
                scale: configuration.isPressed ? 0.965 : 1
            )
    }
}

private struct HomeToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .init(450)))
            .foregroundStyle(destructive ? Color.red.opacity(0.82) : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                configuration.isPressed
                    ? BurritoTheme.controlFill.opacity(1.35)
                    : BurritoTheme.controlFill,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(BurritoTheme.softBorder.opacity(0.7))
            }
            .opacity(isEnabled ? 1 : 0.35)
            .burritoPressFeedback(
                isPressed: configuration.isPressed,
                scale: configuration.isPressed && isEnabled ? 0.965 : 1
            )
    }
}

private struct BurritoDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .init(450)))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(Color.red.opacity(0.78), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.34)
            .burritoPressFeedback(
                isPressed: configuration.isPressed,
                scale: configuration.isPressed ? 0.965 : 1,
                haptic: .levelChange
            )
    }
}

private struct BurritoIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .init(450)))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(BurritoTheme.softBorder) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.34)
            .burritoPressFeedback(
                isPressed: configuration.isPressed,
                scale: configuration.isPressed ? 0.95 : 1
            )
    }
}

private struct BurritoPressFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isPressed: Bool
    let scale: CGFloat
    let haptic: NSHapticFeedbackManager.FeedbackPattern

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .animation(reduceMotion ? nil : .burritoSpring, value: isPressed)
            .onChange(of: isPressed) { _, isPressed in
                if isPressed { BurritoHaptics.trigger(haptic) }
            }
    }
}

private extension View {
    func burritoPressFeedback(
        isPressed: Bool,
        scale: CGFloat,
        haptic: NSHapticFeedbackManager.FeedbackPattern = .generic
    ) -> some View {
        modifier(BurritoPressFeedbackModifier(
            isPressed: isPressed,
            scale: scale,
            haptic: haptic
        ))
    }
}

private struct SidebarToggleButton: View {
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            BurritoIcon(
                name: isExpanded
                    ? "arrow.left.to.line.compact"
                    : "arrow.right.to.line.compact",
                size: 16
            )
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .opacity(isHovered ? 1 : 0.76)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .help(isExpanded ? "Hide sidebar" : "Show sidebar")
        .accessibilityLabel(isExpanded ? "Hide sidebar" : "Show sidebar")
    }
}

private struct SidebarHeaderAddButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            BurritoIcon(name: "plus", size: 9)
                .foregroundStyle(isHovered ? .primary : .tertiary)
                .frame(width: 22, height: 22)
                .background(
                    isHovered ? BurritoTheme.controlFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .help("New folder")
        .accessibilityLabel("New folder")
    }
}

private struct BurritoInlineButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BurritoLabel(title, systemImage: systemImage)
                .font(.spline(size: 12, weight: 450))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BurritoTheme.softBorder)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct BurritoPopoverPanel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .init(450)))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            VStack(spacing: 3) {
                content()
            }
        }
        .padding(7)
        .frame(width: 216)
        .background(BurritoTheme.raised)
        .presentationBackground(BurritoTheme.raised)
    }
}

private struct NoteActionsPopoverPanel<Content: View>: View {
    let note: Note
    let sectionTitle: String
    @ViewBuilder let content: () -> Content

    private var context: String {
        if note.deletedAt != nil {
            return "In Trash"
        }
        return note.folder?.name ?? note.templateSnapshot.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                BurritoIcon(name: note.deletedAt == nil ? "note.text" : "trash", size: 13)
                    .foregroundStyle(BurritoTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.burritoDisplay(size: 15, weight: .init(450)))
                        .tracking(-0.15)
                        .lineLimit(1)
                    Text(context)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if note.isFavorite, note.deletedAt == nil {
                    BurritoIcon(
                        name: "star.fill",
                        size: 10,
                        accessibilityLabel: "Favorite"
                    )
                        .foregroundStyle(BurritoTheme.accent)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)

            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)

            Text(sectionTitle.uppercased())
                .font(.system(size: 9, weight: .init(450), design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 4)

            VStack(spacing: 3) {
                content()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 7)
        }
        .frame(width: 244)
        .background(BurritoTheme.raised)
        .overlay {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .stroke(BurritoTheme.softBorder.opacity(0.7), lineWidth: 0.5)
        }
        .presentationBackground(BurritoTheme.raised)
    }
}

private struct BurritoPopoverRow: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var tint: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            BurritoPopoverRowLabel(
                title: title,
                systemImage: systemImage,
                isSelected: isSelected,
                isHovered: isHovered,
                tint: tint
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct BurritoPopoverRowLabel: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var isHovered = false
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 9) {
            BurritoIcon(name: systemImage, size: 11)
                .foregroundStyle(tint ?? (isSelected ? BurritoTheme.accent : Color.secondary))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tint ?? Color.primary)
            Spacer()
            if isSelected {
                BurritoIcon(name: "checkmark", size: 10)
                    .foregroundStyle(BurritoTheme.accent)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .contentShape(Rectangle())
        .background(
            isHovered ? BurritoTheme.controlFill : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

private struct BurritoPopoverDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 0, style: .continuous)
            .fill(BurritoTheme.softBorder)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
    }
}

private struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.hideIndicators()
    }

    final class ProbeView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleIndicatorUpdate()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleIndicatorUpdate()
        }

        override func layout() {
            super.layout()
            hideIndicators()
        }

        func hideIndicators() {
            if let contentView = window?.contentView {
                hideIndicators(in: contentView)
                return
            }

            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    configure(scrollView)
                    return
                }
                ancestor = view.superview
            }
        }

        func scheduleIndicatorUpdate() {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.hideIndicators()
                try? await Task.sleep(for: .milliseconds(100))
                self?.hideIndicators()
                try? await Task.sleep(for: .milliseconds(500))
                self?.hideIndicators()
            }
        }

        func hideIndicators(in view: NSView) {
            if let scrollView = view as? NSScrollView {
                configure(scrollView)
            }
            for subview in view.subviews {
                hideIndicators(in: subview)
            }
        }

        func configure(_ scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.verticalScroller?.alphaValue = 0
            scrollView.verticalScroller?.isHidden = true
            scrollView.horizontalScroller?.alphaValue = 0
            scrollView.horizontalScroller?.isHidden = true
            if scrollView.hasVerticalScroller {
                scrollView.hasVerticalScroller = false
            }
            if scrollView.hasHorizontalScroller {
                scrollView.hasHorizontalScroller = false
            }
            scrollView.verticalScroller = nil
            scrollView.horizontalScroller = nil
            scrollView.autohidesScrollers = true
        }
    }
}

private extension View {
    func hidesEnclosingScrollIndicators() -> some View {
        background {
            ScrollIndicatorHider()
                .frame(width: 0, height: 0)
        }
    }
}

private struct BurritoModalBackdrop<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
            content()
                .background(BurritoTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BurritoTheme.softBorder)
                }
        }
    }
}

private struct NewFolderDialog: View {
    @Binding var name: String
    let cancel: () -> Void
    let create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("New folder")
                    .font(.burritoDisplay(size: 28, weight: .init(400)))
                Text("Give this collection a short, useful name.")
                    .foregroundStyle(.secondary)
            }
            TextField("Project conversations", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BurritoTheme.softBorder)
                }
                .onSubmit(create)
            HStack {
                Button("Cancel", action: cancel)
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
                Spacer()
                Button("Create folder", action: create)
                    .buttonStyle(BurritoActionButtonStyle(prominent: true))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 440)
    }
}

private struct BurritoMessageDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let isDestructive: Bool
    var isWorking = false
    let cancel: (() -> Void)?
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.burritoDisplay(size: 28, weight: .init(400)))
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            HStack {
                if let cancel {
                    Button("Cancel", action: cancel)
                        .buttonStyle(BurritoActionButtonStyle(prominent: false))
                }
                Spacer()
                if isDestructive {
                    Button(confirmTitle, action: confirm)
                        .buttonStyle(BurritoDestructiveButtonStyle())
                } else {
                    Button(action: confirm) {
                        HStack(spacing: 8) {
                            if isWorking {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isWorking ? "Installing…" : confirmTitle)
                        }
                    }
                        .buttonStyle(BurritoActionButtonStyle(prominent: true))
                        .disabled(isWorking)
                }
            }
        }
        .padding(26)
        .frame(width: 470)
    }
}

private struct SidebarItemLabel: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            BurritoLabel(title, systemImage: systemImage)
                .font(.spline(size: 13, weight: 400))
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(
                        .spline(size: 11, weight: 400, relativeTo: .caption)
                            .monospacedDigit()
                    )
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SidebarNavigationButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let systemImage: String
    var markerColor: Color? = nil
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            BurritoHaptics.trigger(.alignment)
            action()
        } label: {
            HStack(spacing: 8) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(BurritoTheme.accent)
                        .frame(width: 3, height: 16)
                        .transition(.scale(scale: 0.8, anchor: .center).combined(with: .opacity))
                }
                Group {
                    if let markerColor {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(markerColor)
                            .frame(width: 8, height: 8)
                    } else {
                        BurritoIcon(name: systemImage)
                            .foregroundStyle(isSelected ? BurritoTheme.accent : (isHovered ? .primary : .secondary))
                    }
                }
                .frame(width: 18)
                Text(title)
                    .font(.spline(size: 13, weight: isSelected ? 450 : 400))
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(
                            .spline(size: 11, weight: 400, relativeTo: .caption)
                                .monospacedDigit()
                        )
                        .foregroundStyle(isSelected ? BurritoTheme.accent : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? BurritoTheme.accentSoft : (isHovered ? BurritoTheme.controlFill : Color.clear),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .font(.spline(size: 13, weight: isSelected ? 450 : 400))
            .padding(.horizontal, 9)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .background(
            isSelected ? BurritoTheme.controlFill : (isHovered ? BurritoTheme.controlFill.opacity(0.45) : Color.clear),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .animation(reduceMotion ? nil : .burritoSpring, value: isSelected)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovered
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CalendarCard: View {
    let calendarAccess: CalendarAccess
    let startRecording: (UpcomingCalendarEvent) -> Void
    let openSettings: () -> Void

    private var today: Date { .now }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BurritoIcon(name: "calendar", size: 13)
                    .foregroundStyle(BurritoTheme.accent)
                Text(today.formatted(.dateTime.day().month(.abbreviated).weekday(.wide)))
                    .font(.spline(size: 12, weight: 450))
                    .foregroundStyle(.primary)
                Text("Recent & upcoming meetings")
                    .font(.spline(size: 12, weight: 400))
                    .foregroundStyle(.tertiary)
                Spacer()
                if calendarAccess.state == .authorized {
                    Button {
                        calendarAccess.refresh()
                    } label: {
                        BurritoLabel("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .font(.spline(size: 11, weight: 450))
                    .foregroundStyle(.tertiary)
                    .help("Refresh upcoming Calendar events")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            switch calendarAccess.state {
            case .notDetermined:
                CalendarConnectionState(
                    symbol: "calendar.badge.plus",
                    title: "Bring your day into focus",
                    detail: "Connect Calendar to see what’s coming up.",
                    buttonTitle: "Connect Calendar"
                ) {
                    Task { await calendarAccess.requestAccess() }
                }
            case .requesting:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting Calendar…")
                        .font(.spline(size: 12, weight: 400))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            case .authorized:
                if calendarAccess.upcomingEvents.isEmpty {
                    HStack(spacing: 8) {
                        BurritoIcon(name: "calendar.badge.clock", size: 12)
                            .foregroundStyle(.tertiary)
                        Text("No timed events found from the last 24 hours onward.")
                            .font(.spline(size: 11, weight: 400))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(calendarAccess.upcomingEvents.enumerated()), id: \.element.id) {
                            index, event in
                            UpcomingEventRow(event: event, startRecording: startRecording)
                            if index < calendarAccess.upcomingEvents.count - 1 {
                                RoundedRectangle(cornerRadius: 0, style: .continuous)
                                    .fill(BurritoTheme.softBorder.opacity(0.5))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            case .denied:
                CalendarConnectionState(
                    symbol: "calendar.badge.exclamationmark",
                    title: "Calendar access is off",
                    detail: "Allow Burrito in Privacy & Security → Calendars.",
                    buttonTitle: "Open System Settings",
                    action: openSettings
                )
            case .failed(let message):
                CalendarConnectionState(
                    symbol: "exclamationmark.triangle",
                    title: "Calendar couldn’t load",
                    detail: message,
                    buttonTitle: "Try Again"
                ) {
                    Task { await calendarAccess.requestAccess() }
                }
            }
        }
        .background(BurritoTheme.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder.opacity(0.7), lineWidth: 0.75)
        }
    }
}

private struct CalendarConnectionState: View {
    let symbol: String
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BurritoIcon(name: symbol, size: 16)
                .foregroundStyle(BurritoTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.spline(size: 12, weight: 450))
                Text(detail)
                    .font(.spline(size: 11, weight: 400))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(HomeToolbarButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct UpcomingEventRow: View {
    let event: UpcomingCalendarEvent
    let startRecording: (UpcomingCalendarEvent) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.spline(size: 12, weight: 450).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
                Text(event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.spline(size: 10, weight: 400, relativeTo: .caption2))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(BurritoTheme.accent)
                .frame(width: 3, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.spline(size: 13, weight: 450))
                    .lineLimit(1)
                Text(
                    event.endDate < .now
                        ? "Earlier · \(event.calendarName)"
                        : event.calendarName
                )
                    .font(.spline(size: 11, weight: 400, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            BurritoButton(
                event.meetingURL == nil ? "Record" : "Join + Record",
                systemImage: event.meetingURL == nil ? "waveform" : "video"
            ) {
                startRecording(event)
            }
            .buttonStyle(HomeToolbarButtonStyle())
        }
        .frame(minHeight: 52)
    }
}

private struct NoteIconBadge: View {
    let note: Note
    let isHovered: Bool

    private var iconName: String {
        if note.processingStage != nil {
            return "waveform"
        }
        if note.calendarEvent != nil {
            return "calendar"
        }
        return note.templateSnapshot.symbol
    }

    private var badgeBackground: Color {
        if note.processingStage != nil || note.isFavorite {
            return BurritoTheme.accentSoft
        }
        return isHovered ? BurritoTheme.controlFill : BurritoTheme.raised
    }

    private var iconColor: Color {
        if note.processingStage != nil || note.isFavorite {
            return BurritoTheme.accent
        }
        return isHovered ? .primary : .secondary
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(badgeBackground)
                .frame(width: 32, height: 32)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            note.processingStage != nil || note.isFavorite
                                ? BurritoTheme.accent.opacity(0.3)
                                : BurritoTheme.softBorder
                        )
                }

            BurritoIcon(name: iconName, size: 14)
                .foregroundStyle(iconColor)
        }
    }
}

private struct TimelineNoteRow: View {
    let note: Note
    var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            NoteIconBadge(note: note, isHovered: isHovered)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.spline(size: 14, weight: 450))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if note.isFavorite {
                        BurritoIcon(name: "star.fill", size: 10)
                            .foregroundStyle(BurritoTheme.accent)
                    }
                }
                Text(note.processingStage?.rawValue ?? NoteExcerpt.text(for: note))
                    .font(.spline(size: 11, weight: 400))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let folder = note.folder {
                FolderTag(folder: folder)
            }
            Text(note.updatedAt, style: .time)
                .font(.spline(size: 11, weight: 400))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(minWidth: 54, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

enum NoteExcerpt {
    static func text(for note: Note) -> String {
        let markdown = note.markdownBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !markdown.isEmpty {
            return markdown
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let humanNotes = note.userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !humanNotes.isEmpty {
            return humanNotes
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return note.transcriptSegments.first?.text ?? "Recording ready for your notes."
    }
}

private enum FolderAccent {
    static func color(for id: UUID) -> Color {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Color(
            hue: Double(hash % 360) / 360,
            saturation: 0.68,
            brightness: 0.9
        )
    }
}

private struct FolderTag: View {
    let folder: Folder

    private var color: Color {
        FolderAccent.color(for: folder.id)
    }

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 4)
            Text(folder.name)
                .lineLimit(1)
        }
        .font(.spline(size: 10, weight: 450))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityLabel("Folder: \(folder.name)")
    }
}

private struct TimelineNoteItem: View {
    @Environment(\.modelContext) private var modelContext

    let note: Note
    let folders: [Folder]
    let open: () -> Void

    @State private var isHovered = false
    @State private var showingActions = false
    @State private var showingFolders = false

    var body: some View {
        HStack(spacing: 2) {
            Button {
                BurritoHaptics.trigger(.alignment)
                open()
            } label: {
                TimelineNoteRow(note: note, isHovered: isHovered)
            }
            .buttonStyle(.plain)

            Button {
                BurritoHaptics.trigger(.generic)
                showingActions.toggle()
            } label: {
                BurritoIcon(name: "ellipsis", size: 13)
                    .foregroundStyle(isHovered || showingActions ? .primary : .tertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        showingActions ? BurritoTheme.controlFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovered || showingActions ? 1 : 0.3)
            .help("Note actions")
            .accessibilityLabel("Actions for \(note.title)")
            .popover(
                isPresented: $showingActions,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                noteActionsPopover
            }
        }
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .background(
            isHovered || showingActions ? BurritoTheme.paper.opacity(0.6) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if isHovered || showingActions {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(BurritoTheme.softBorder)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hover
            }
        }
        .onChange(of: showingActions) { _, isPresented in
            if !isPresented {
                showingFolders = false
            }
        }
    }

    @ViewBuilder
    private var noteActionsPopover: some View {
        if showingFolders {
            NoteActionsPopoverPanel(note: note, sectionTitle: "Choose folder") {
                BurritoPopoverRow(title: "Back", systemImage: "chevron.left") {
                    showingFolders = false
                }
                BurritoPopoverDivider()
                BurritoPopoverRow(
                    title: "No folder",
                    systemImage: "tray",
                    isSelected: note.folder == nil
                ) {
                    note.folder = nil
                    showingActions = false
                }
                ForEach(folders) { folder in
                    BurritoPopoverRow(
                        title: folder.name,
                        systemImage: "folder",
                        isSelected: note.folder?.id == folder.id
                    ) {
                        note.folder = folder
                        showingActions = false
                    }
                }
            }
        } else if note.deletedAt == nil {
            NoteActionsPopoverPanel(note: note, sectionTitle: "Actions") {
                BurritoPopoverRow(
                    title: note.isFavorite ? "Remove from favorites" : "Add to favorites",
                    systemImage: note.isFavorite ? "star.slash" : "star"
                ) {
                    note.isFavorite.toggle()
                    showingActions = false
                }
                BurritoPopoverRow(
                    title: note.folder == nil ? "Add to folder" : "Change folder",
                    systemImage: "folder"
                ) {
                    showingFolders = true
                }
                BurritoPopoverDivider()
                BurritoPopoverRow(
                    title: "Move to trash",
                    systemImage: "trash",
                    tint: .red
                ) {
                    note.deletedAt = .now
                    showingActions = false
                }
            }
        } else {
            NoteActionsPopoverPanel(note: note, sectionTitle: "Trash actions") {
                BurritoPopoverRow(title: "Restore note", systemImage: "arrow.uturn.backward") {
                    note.deletedAt = nil
                    showingActions = false
                }
                BurritoPopoverDivider()
                BurritoPopoverRow(
                    title: "Delete permanently",
                    systemImage: "trash",
                    tint: .red
                ) {
                    modelContext.delete(note)
                    showingActions = false
                }
            }
        }
    }
}

private struct HomeEmptyState: View {
    let isTrash: Bool
    let isSearching: Bool
    let start: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            BurritoIcon(name: isTrash ? "trash" : isSearching ? "magnifyingglass" : "waveform.badge.plus", size: 26)
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text(isTrash ? "Trash is empty" : isSearching ? "No matching notes" : "Nothing captured yet")
                    .font(.burritoDisplay(size: 20, weight: .init(400)))
                Text(isSearching ? "Try a different search." : isTrash ? "Deleted notes will appear here." : "Start a recording and Burrito will organize it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !isTrash && !isSearching {
                BurritoButton("New recording", systemImage: "plus", action: start)
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }
}

private struct CaptureCapsule: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(BurritoTheme.accent)
                        .frame(width: 30, height: 30)
                    BurritoIcon(name: "waveform", size: 13)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("New recording")
                        .font(.system(size: 13, weight: .init(450)))
                    Text("⌘N")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BurritoIcon(name: "arrow.up.right", size: 12)
                    .foregroundStyle(.tertiary)
            }
            .padding(9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BurritoTheme.softBorder)
        }
        .accessibilityHint("Opens recording options")
    }
}

private struct NoteListEmptyState: View {
    let isTrash: Bool
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            BurritoIcon(name: isTrash ? "trash" : isSearching ? "magnifyingglass" : "note.text", size: 22)
                .foregroundStyle(.tertiary)
            Text(isTrash ? "Trash is empty" : isSearching ? "Nothing found" : "A quiet start")
                .font(.headline)
            Text(isSearching ? "Try another word." : isTrash ? "Deleted notes will wait here." : "Your recordings will collect here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }
}

private struct WelcomeWorkspaceView: View {
    let start: () -> Void

    var body: some View {
        ZStack {
            BurritoTheme.paper.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BurritoTheme.accentSoft)
                        .frame(width: 86, height: 86)
                    BurritoIcon(name: "waveform.and.mic", size: 32)
                        .foregroundStyle(BurritoTheme.accent)
                }
                VStack(spacing: 8) {
                    Text("Capture it. Keep the good parts.")
                        .font(.system(size: 28, weight: .init(450)))
                    Text("Burrito records what you hear, then turns it into notes\nthat stay private on your Mac.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                BurritoButton("Start a recording", systemImage: "waveform", action: start)
                    .buttonStyle(BurritoActionButtonStyle(prominent: true))
                HStack(spacing: 8) {
                    BurritoPill(title: "Local", systemImage: "macbook")
                    BurritoPill(title: "Private", systemImage: "lock")
                    BurritoPill(title: "Editable", systemImage: "pencil")
                }
            }
            .padding(40)
        }
    }
}

private struct RecordingStatusView: View {
    let coordinator: AppCoordinator
    let stop: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            ActiveRecordingStage(
                elapsed: coordinator.elapsed,
                systemLevel: coordinator.activity.system,
                microphoneLevel: coordinator.activity.microphone
            )

            RecordingControlButton(
                isRecording: true,
                elapsed: coordinator.elapsed,
                systemLevel: coordinator.activity.system,
                microphoneLevel: coordinator.activity.microphone,
                action: stop
            )
            .padding(.bottom, 28)
        }
        .background(BurritoTheme.canvas)
    }
}

private struct ActiveRecordingStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let elapsed: TimeInterval
    let systemLevel: Double
    let microphoneLevel: Double

    var body: some View {
        ZStack {
            BurritoTheme.canvas

            VStack(spacing: 0) {
                if reduceMotion {
                    LottieView(animation: .named("Scooter-loader"))
                        .currentProgress(0.5)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 220)
                } else {
                    LottieView(animation: .named("Scooter-loader"))
                        .playing(loopMode: .loop)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 220)
                }

                Text("LISTENING · ON THIS MAC")
                    .font(.system(size: 9, weight: .init(450), design: .monospaced))
                    .tracking(1.35)
                    .foregroundStyle(BurritoTheme.accent.opacity(0.82))
                    .padding(.top, 2)

                LiveAudioWaveform(
                    systemLevel: systemLevel,
                    microphoneLevel: microphoneLevel
                )
                .padding(.top, 18)

                Text(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.system(size: 10, weight: .init(450), design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)
            }
            .offset(y: -34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording in progress")
        .accessibilityValue(
            "Elapsed \(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))"
        )
    }
}

private struct LiveAudioWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let systemLevel: Double
    let microphoneLevel: Double

    private let barCount = 41

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion
            )
        ) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                        .fill(BurritoTheme.accent)
                        .frame(width: 2.5, height: 62)
                        .scaleEffect(
                            x: 1,
                            y: barScale(at: index, phase: phase),
                            anchor: .center
                        )
                        .opacity(barOpacity(at: index))
                }
            }
            .frame(width: 268, height: 68)
        }
        .mask {
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .accessibilityHidden(true)
    }

    private func barScale(at index: Int, phase: TimeInterval) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / center
        let envelope = 0.25 + (0.75 * pow(1 - distance, 1.6))
        let sourceLevel = index.isMultiple(of: 2) ? systemLevel : microphoneLevel
        let energy = max(max(systemLevel, microphoneLevel) * 0.55, sourceLevel)
        let wave = reduceMotion
            ? 0.5
            : (sin((phase * 7.5) + (Double(index) * 0.68)) + 1) / 2
        return 0.08 + CGFloat(min(0.92, energy * envelope * (0.62 + (wave * 0.58))))
    }

    private func barOpacity(at index: Int) -> Double {
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / center
        return 0.28 + (0.72 * (1 - distance))
    }
}

private struct RecordingControlButton: View {
    let isRecording: Bool
    let elapsed: TimeInterval
    let systemLevel: Double
    let microphoneLevel: Double
    let action: () -> Void

    @State private var isHovered = false

    private var audioEnergy: Double {
        min(1, max(systemLevel, microphoneLevel))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(BurritoTheme.accent.opacity(0.16))
                            .scaleEffect(1 + (audioEnergy * 0.1))
                            .opacity(0.6 + (audioEnergy * 0.4))
                    }

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isRecording ? BurritoTheme.accent : BurritoTheme.accentSoft)

                    if isRecording {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    } else {
                        BurritoIcon(name: "waveform", size: 10)
                            .foregroundStyle(BurritoTheme.accent)
                    }
                }
                .frame(width: 24, height: 24)

                Text(isRecording ? "Stop" : "Record more")
                    .font(.system(size: 11, weight: .init(450)))
                    .foregroundStyle(.primary)

                if isRecording {
                    Spacer(minLength: 4)
                    Text(
                        Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond))
                    )
                    .font(.system(size: 9, weight: .init(450), design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: 132, height: 34)
            .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BurritoTheme.accentSoft)
                    .opacity(isHovered ? 0.34 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BurritoTheme.softBorder.opacity(0.85), lineWidth: 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RecordingControlButtonStyle())
        .offset(y: isHovered ? -1 : 0)
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .help(isRecording ? "Stop recording" : "Continue recording")
        .accessibilityLabel(isRecording ? "Stop recording" : "Continue recording")
        .accessibilityValue(
            isRecording
                ? "Elapsed \(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))"
                : "Not recording"
        )
    }
}

private struct RecordingControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ProcessingRail: View {
    let stage: ProcessingStage
    let isContinuation: Bool

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(BurritoTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .init(450)))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder) }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch stage {
        case .preparingAudio: "Finishing the recording"
        case .transcribing: "Preparing the final transcript"
        case .organizing: isContinuation ? "Adding the continuation" : "Organizing the transcript"
        case .generatingNotes: isContinuation ? "Writing the new note section" : "Writing your notes"
        }
    }

    private var detail: String {
        switch stage {
        case .preparingAudio: "Securing the captured audio."
        case .transcribing: "Building the transcript from the saved audio."
        case .organizing:
            isContinuation
                ? "Keeping the existing note and extending its transcript."
                : "Combining the captured audio into one transcript."
        case .generatingNotes: "Applying the selected note style."
        }
    }
}

private struct ActivityMeter: View {
    let label: String
    let value: Double

    var body: some View {
        ProgressView(value: value) {
            Text(label)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140)
    }
}

private struct RecordingSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let templates: [NoteTemplate]
    @Bindable var modelStore: ParakeetModelStore
    let calendarEvent: CalendarEventSnapshot?
    let openModels: () -> Void
    let start: (RecordingOptions) -> Void

    @AppStorage("defaultTemplateID") private var defaultTemplateID = BuiltInTemplate.summary.rawValue
    @AppStorage("transcriptionLanguage") private var language = "en-US"
    @AppStorage("recordingModeDefault") private var recordingModeRawValue =
        RecordingMode.listenAlong.rawValue
    @AppStorage("retainAudioDefault") private var retainsAudio = false
    @State private var templateID: UUID?
    @State private var openPicker: RecordingSetupPicker?
    @State private var languageQuery = ""

    private var selectedTemplate: NoteTemplate? {
        templates.first { $0.id == templateID }
            ?? templates.first { $0.builtInID == defaultTemplateID }
            ?? templates.first
    }

    private var effectiveTemplate: TemplateSnapshot? {
        selectedTemplate?.snapshot
    }

    private var effectiveLanguage: String {
        language
    }

    private var recordingMode: RecordingMode {
        get { RecordingMode(rawValue: recordingModeRawValue) ?? .listenAlong }
        nonmutating set { recordingModeRawValue = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(calendarEvent?.title ?? "New recording")
                        .font(.burritoDisplay(size: 30, weight: .init(400)))
                    Text(
                        calendarEvent == nil
                            ? "Choose what Burrito should listen for."
                            : "This event will guide the title and generated notes."
                    )
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BurritoButton("Cancel", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(BurritoIconButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            if let calendarEvent {
                HStack(spacing: 12) {
                    BurritoIcon(name: "calendar.badge.checkmark", size: 18)
                        .foregroundStyle(BurritoTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            calendarEvent.startDate.formatted(
                                .dateTime.weekday(.wide).month(.abbreviated).day()
                                    .hour().minute()
                            )
                        )
                        .font(.system(size: 13, weight: .init(450)))
                        Text(calendarEvent.calendarName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !calendarEvent.attendeeNames.isEmpty {
                        BurritoLabel(
                            "\(calendarEvent.attendeeNames.count)",
                            systemImage: "person.2"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(BurritoTheme.controlFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder.opacity(0.7))
                }
            }

            VStack(spacing: 0) {
                RecordingTemplatePicker(
                    templates: templates,
                    selection: $templateID,
                    selectedTemplate: selectedTemplate,
                    openPicker: $openPicker
                )
                .zIndex(2)
                Divider().padding(.leading, 12)
                RecordingLanguagePicker(
                    selection: $language,
                    openPicker: $openPicker
                )
                .zIndex(1)
                Divider().padding(.leading, 12)
                RecordingModePicker(selection: recordingModeBinding)
                Divider().padding(.leading, 12)
                BurritoToggleRow(
                    title: "Keep audio",
                    subtitle: "Retain recordings after transcription",
                    isOn: $retainsAudio
                )
            }
            .zIndex(2)
            .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BurritoTheme.softBorder.opacity(0.7))
            }

            RecordingTranscriptionRow(
                languageIdentifier: effectiveLanguage,
                modelStore: modelStore,
                openModels: openModels
            )
            .zIndex(1)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
                Spacer()
                BurritoButton("Start recording", systemImage: "waveform") {
                    guard let effectiveTemplate else { return }
                    start(
                        RecordingOptions(
                            template: effectiveTemplate,
                            languageIdentifier: effectiveLanguage,
                            mode: recordingMode,
                            retainsAudio: retainsAudio
                        )
                    )
                }
                .buttonStyle(BurritoActionButtonStyle(prominent: true))
                .disabled(effectiveTemplate == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(BurritoTheme.paper)
        .overlay {
            if openPicker != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.14)) {
                            openPicker = nil
                        }
                    }
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            recordingPickerOverlay
                .padding(.top, 132)
                .padding(.trailing, 26)
        }
        .onAppear {
            if templateID == nil {
                templateID = selectedTemplate?.id
            }
        }
        .onExitCommand {
            if openPicker != nil {
                openPicker = nil
            } else {
                dismiss()
            }
        }
    }

    private var recordingModeBinding: Binding<RecordingMode> {
        Binding(
            get: { recordingMode },
            set: { recordingMode = $0 }
        )
    }

    @ViewBuilder
    private var recordingPickerOverlay: some View {
        switch openPicker {
        case .template:
            RecordingDropdownSurface(title: "Note style") {
                ForEach(templates) { template in
                    BurritoPopoverRow(
                        title: template.name,
                        systemImage: template.symbol,
                        isSelected: selectedTemplate?.id == template.id
                    ) {
                        templateID = template.id
                        openPicker = nil
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
        case .language:
            RecordingLanguageMenu(
                selection: $language,
                query: $languageQuery
            ) {
                openPicker = nil
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
        case nil:
            EmptyView()
        }
    }
}

private struct RecordingModePicker: View {
    @Binding var selection: RecordingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio source")
                .font(.system(size: 12, weight: .init(450)))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(RecordingMode.allCases) { mode in
                    Button {
                        selection = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            BurritoIcon(name: mode.symbol, size: 15)
                                .foregroundStyle(
                                    selection == mode ? BurritoTheme.accent : .secondary
                                )
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.system(size: 13, weight: .init(450)))
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        selection == mode
                            ? BurritoTheme.accentSoft.opacity(0.6)
                            : BurritoTheme.controlFill,
                        in: Rectangle()
                    )
                    .overlay {
                        Rectangle()
                            .stroke(
                                selection == mode
                                    ? BurritoTheme.accent.opacity(0.65)
                                    : BurritoTheme.softBorder
                            )
                    }
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                }
            }
        }
        .padding(14)
    }
}

private enum RecordingSetupPicker {
    case template
    case language
}

private struct RecordingTemplatePicker: View {
    let templates: [NoteTemplate]
    @Binding var selection: UUID?
    let selectedTemplate: NoteTemplate?
    @Binding var openPicker: RecordingSetupPicker?

    var body: some View {
        Button {
            openPicker = openPicker == .template ? nil : .template
        } label: {
            HStack {
                Text("Note style")
                    .font(.system(size: 13, weight: .init(450)))
                Spacer()
                Text(selectedTemplate?.name ?? "Choose")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                BurritoIcon(name: "chevron.down", size: 8)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: openPicker == .template)
        .accessibilityLabel("Note style")
        .accessibilityValue(selectedTemplate?.name ?? "Not selected")
    }
}

private struct RecordingLanguagePicker: View {
    @Binding var selection: String
    @Binding var openPicker: RecordingSetupPicker?

    private var selectedLanguage: TranscriptionLanguage {
        TranscriptionLanguage.resolve(selection)
    }

    var body: some View {
        Button {
            openPicker = openPicker == .language ? nil : .language
        } label: {
            HStack {
                Text("Language")
                    .font(.system(size: 13, weight: .init(450)))
                Spacer()
                Text(selectedLanguage.compactTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                BurritoIcon(name: "chevron.down", size: 8)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: openPicker == .language)
        .accessibilityLabel("Transcription language")
        .accessibilityValue(selectedLanguage.title)
    }
}

private struct RecordingLanguageMenu: View {
    @Binding var selection: String
    @Binding var query: String
    let dismiss: () -> Void

    private var filteredLanguages: [TranscriptionLanguage] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return TranscriptionLanguage.supported }
        return TranscriptionLanguage.supported.filter {
            $0.title.localizedStandardContains(value)
        }
    }

    var body: some View {
        RecordingDropdownSurface(title: "Transcription language", width: 270) {
            HStack(spacing: 8) {
                BurritoIcon(name: "magnifyingglass", size: 11)
                    .foregroundStyle(.tertiary)
                TextField("Find a language", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                BurritoTheme.controlFill,
                in: Rectangle()
            )

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredLanguages) { language in
                        BurritoPopoverRow(
                            title: language.title,
                            systemImage: "character.bubble",
                            isSelected: selection == language.identifier
                        ) {
                            selection = language.identifier
                            query = ""
                            dismiss()
                        }
                    }
                }
            }
            .frame(height: 210)
            .scrollIndicators(.hidden)
            .hidesEnclosingScrollIndicators()
        }
    }
}

private struct RecordingDropdownSurface<Content: View>: View {
    let title: String
    var width: CGFloat = 240
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .init(450), design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
            VStack(spacing: 3) {
                content()
            }
        }
        .padding(8)
        .frame(width: width)
        .background(BurritoTheme.paper, in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(BurritoTheme.softBorder)
        }
        .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
    }
}

private struct RecordingTranscriptionRow: View {
    let languageIdentifier: String
    @Bindable var modelStore: ParakeetModelStore
    let openModels: () -> Void

    private var installedModel: ParakeetModelVariant? {
        ParakeetModelVariant
            .candidates(languageIdentifier: languageIdentifier)
            .first {
                if case .installed = modelStore.state(for: $0) {
                    return true
                }
                return false
            }
    }

    private var canInstallModel: Bool {
        !ParakeetModelVariant.candidates(languageIdentifier: languageIdentifier).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            BurritoIcon(name: installedModel == nil ? "apple.logo" : "waveform", size: 13)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(engineTitle)
                    .font(.system(size: 12, weight: .init(450)))
                Text(engineDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: openModels) {
                HStack(spacing: 5) {
                    Text("View models")
                    BurritoIcon(name: "chevron.right", size: 10)
                }
            }
                .font(.system(size: 11, weight: .init(450)))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
    }

    private var engineTitle: String {
        if let installedModel {
            return installedModel.displayName
        }
        if canInstallModel, installedModel == nil {
            return "Install a local model for better transcripts"
        }
        return "Apple Speech"
    }

    private var engineDetail: String {
        if installedModel != nil {
            return "Final pass after Stop · rebuilt directly from saved audio"
        }
        if canInstallModel, installedModel == nil {
            return "Optional · Apple Speech will continue to work"
        }
        if canInstallModel {
            return "Built in · find higher-accuracy options in Models"
        }
        return "Built in · no additional download needed"
    }
}

private struct TemplateChoiceCard: View {
    let template: NoteTemplate
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 11) {
                BurritoIcon(name: template.symbol, size: 15)
                    .foregroundStyle(isSelected ? BurritoTheme.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected ? BurritoTheme.accentSoft : BurritoTheme.controlFill,
                        in: Rectangle()
                    )
                Text(template.name)
                    .font(.system(size: 13, weight: .init(450)))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    ZStack {
                        Rectangle().fill(BurritoTheme.accent)
                        BurritoIcon(name: "checkmark", size: 8)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 17, height: 17)
                }
            }
            .padding(11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? BurritoTheme.accentSoft.opacity(0.55) : BurritoTheme.raised,
            in: Rectangle()
        )
        .overlay {
            Rectangle()
                .stroke(isSelected ? BurritoTheme.accent.opacity(0.6) : BurritoTheme.softBorder)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BurritoChoiceButton: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                ZStack {
                    Rectangle()
                        .stroke(isSelected ? BurritoTheme.accent : BurritoTheme.softBorder, lineWidth: 1.5)
                    if isSelected {
                        Rectangle()
                            .fill(BurritoTheme.accent)
                            .padding(3)
                    }
                }
                .frame(width: 15, height: 15)
                Text(title)
                    .font(.system(size: 12, weight: .init(450)))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? BurritoTheme.accentSoft.opacity(0.65) : BurritoTheme.raised,
            in: Rectangle()
        )
        .overlay {
            Rectangle()
                .stroke(isSelected ? BurritoTheme.accent.opacity(0.55) : BurritoTheme.softBorder)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let templates: [NoteTemplate]

    @State private var selectedTemplateID: UUID?
    @State private var showingEditor = false
    @State private var editingTemplateID: UUID?
    @State private var deletingTemplateID: UUID?

    private var selectedTemplate: NoteTemplate? {
        templates.first { $0.id == selectedTemplateID } ?? templates.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44)

            // Sleek Apple-Grade Header
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("Templates")
                            .font(.spline(size: 26, weight: 450))
                            .foregroundStyle(.primary)

                        Text("\(templates.count) available")
                            .font(.spline(size: 11, weight: 450, relativeTo: .caption))
                            .foregroundStyle(BurritoTheme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(BurritoTheme.accent.opacity(0.25))
                            }
                    }

                    Text("Shape how Burrito turns meeting transcripts into structured notes.")
                        .font(.spline(size: 13, weight: 400, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    editingTemplateID = nil
                    showingEditor = true
                } label: {
                    BurritoLabel("New Template", systemImage: "plus")
                }
                .buttonStyle(HomeToolbarButtonStyle())
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 20)

            // Main Split Studio Container
            HStack(spacing: 24) {
                // Left Master List
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("TEMPLATES")
                            .font(.spline(size: 9, weight: 450, relativeTo: .caption2))
                            .tracking(0.9)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(templates) { template in
                                TemplateListRow(
                                    template: template,
                                    isSelected: selectedTemplateID == template.id,
                                    select: {
                                        BurritoHaptics.trigger(.alignment)
                                        withAnimation(reduceMotion ? nil : .burritoSpring) {
                                            selectedTemplateID = template.id
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: 240)

                // Right Detail Studio Card
                if let template = selectedTemplate {
                    TemplatePromptDetail(
                        template: template,
                        edit: {
                            editingTemplateID = template.id
                            showingEditor = true
                        },
                        delete: template.isBuiltIn ? nil : {
                            deletingTemplateID = template.id
                        }
                    )
                } else {
                    BurritoContentUnavailable(
                        title: "No templates",
                        systemImage: "doc.text",
                        description: Text("Create a template to define a custom note format.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 32)
        }
        .background(BurritoTheme.canvas)
        .onAppear {
            selectedTemplateID = selectedTemplate?.id
        }
        .onChange(of: templates.map(\.id)) {
            if selectedTemplateID.flatMap({ id in templates.first { $0.id == id } }) == nil {
                selectedTemplateID = templates.first?.id
            }
        }
        .sheet(isPresented: $showingEditor) {
            TemplateEditorView(
                template: templates.first { $0.id == editingTemplateID }
            ) { name, symbol, instructions in
                if let template = templates.first(where: { $0.id == editingTemplateID }) {
                    template.name = name
                    template.symbol = symbol
                    template.instructions = instructions
                    selectedTemplateID = template.id
                } else {
                    let template = NoteTemplate(
                        name: name,
                        symbol: symbol,
                        instructions: instructions
                    )
                    modelContext.insert(template)
                    selectedTemplateID = template.id
                }
                try? modelContext.save()
                showingEditor = false
                editingTemplateID = nil
            }
        }
        .overlay {
            if let template = templates.first(where: { $0.id == deletingTemplateID }) {
                BurritoModalBackdrop {
                    BurritoMessageDialog(
                        title: "Delete \(template.name)?",
                        message: "This custom template will be permanently deleted. Existing notes will keep their saved template instructions.",
                        confirmTitle: "Delete Template",
                        isDestructive: true,
                        cancel: { deletingTemplateID = nil },
                        confirm: {
                            modelContext.delete(template)
                            try? modelContext.save()
                            deletingTemplateID = nil
                        }
                    )
                }
            }
        }
    }
}

private struct TemplateListRow: View {
    let template: NoteTemplate
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? BurritoTheme.accent : BurritoTheme.controlFill)
                        .frame(width: 32, height: 32)
                    BurritoIcon(name: template.symbol, size: 13)
                        .foregroundStyle(isSelected ? .white : BurritoTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.spline(size: 13, weight: 450))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    Text(template.isBuiltIn ? "Built in" : "Custom")
                        .font(.spline(size: 10, weight: 400, relativeTo: .caption2))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isSelected {
                    BurritoIcon(name: "checkmark", size: 10)
                        .foregroundStyle(BurritoTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(
                isSelected
                    ? BurritoTheme.raised
                    : (isHovered ? BurritoTheme.controlFill.opacity(0.6) : Color.clear),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BurritoTheme.softBorder)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TemplatePromptDetail: View {
    private enum Tab {
        case instructions
        case systemPrompt
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let template: NoteTemplate
    let edit: () -> Void
    let delete: (() -> Void)?

    @State private var activeTab: Tab = .instructions
    @State private var copiedText = false

    private var systemPrompt: String {
        GenerationPrompt.finalInstructions(template: template.snapshot)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BurritoTheme.accentSoft)
                        .frame(width: 44, height: 44)
                    BurritoIcon(name: template.symbol, size: 18)
                        .foregroundStyle(BurritoTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(template.name)
                            .font(.spline(size: 20, weight: 450))
                            .foregroundStyle(.primary)

                        Text(template.isBuiltIn ? "Built-in" : "Custom")
                            .font(.spline(size: 10, weight: 450, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }

                    Text("Used by Burrito AI model during note synthesis")
                        .font(.spline(size: 11, weight: 400, relativeTo: .caption))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if let delete {
                        BurritoButton("Delete", systemImage: "trash", action: delete)
                            .buttonStyle(HomeToolbarButtonStyle(destructive: true))
                    }
                    BurritoButton("Edit", systemImage: "pencil", action: edit)
                        .buttonStyle(HomeToolbarButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)

            HStack {
                HStack(spacing: 2) {
                    Button {
                        withAnimation(reduceMotion ? nil : .burritoSpring) {
                            activeTab = .instructions
                        }
                    } label: {
                        BurritoLabel("Instructions", systemImage: "doc.text")
                            .font(.spline(size: 12, weight: activeTab == .instructions ? 450 : 400))
                            .foregroundStyle(activeTab == .instructions ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(activeTab == .instructions ? BurritoTheme.controlFill : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(reduceMotion ? nil : .burritoSpring) {
                            activeTab = .systemPrompt
                        }
                    } label: {
                        BurritoLabel("Full System Prompt", systemImage: "terminal")
                            .font(.spline(size: 12, weight: activeTab == .systemPrompt ? 450 : 400))
                            .foregroundStyle(activeTab == .systemPrompt ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(activeTab == .systemPrompt ? BurritoTheme.controlFill : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(3)
                .background(BurritoTheme.controlFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        activeTab == .instructions ? template.instructions : systemPrompt,
                        forType: .string
                    )
                    copiedText = true
                    BurritoHaptics.trigger(.alignment)
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copiedText = false
                    }
                } label: {
                    BurritoLabel(copiedText ? "Copied" : "Copy", systemImage: copiedText ? "checkmark" : "doc.on.doc")
                        .font(.spline(size: 11, weight: 450))
                }
                .buttonStyle(HomeToolbarButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)

            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if activeTab == .instructions {
                        Text(template.instructions)
                            .font(.spline(size: 13, weight: 400))
                            .foregroundStyle(.primary.opacity(0.9))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                    } else {
                        Text(systemPrompt)
                            .font(.spline(size: 12, weight: 400))
                            .foregroundStyle(.secondary)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BurritoTheme.softBorder)
        }
    }
}

private struct MarkdownNoteContent: View {
    let markdown: String
    var openTranscript: ((UUID) -> Void)?
    var openMemory: ((MemoryCitation) -> Void)?

    private var document: MarkdownDocument {
        MarkdownDocument.parse(markdown)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if let id = TranscriptCitation.segmentID(from: url) {
                openTranscript?(id)
                return .handled
            }
            if let citation = MemoryCitation.resolve(url) {
                openMemory?(citation)
                return .handled
            }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownDocument.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level: level))
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 6 : 10)
        case .paragraph(let text):
            inlineText(text)
                .font(.spline(size: 14, weight: 400))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(5)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(BurritoTheme.accent)
                            .frame(width: 5, height: 5)
                        inlineText(item)
                            .font(.spline(size: 14, weight: 400))
                            .lineSpacing(4)
                    }
                }
            }
            .padding(.leading, 4)
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Text("\(index + 1)")
                            .font(.spline(size: 11, weight: 600))
                            .foregroundStyle(BurritoTheme.accent)
                            .frame(width: 21, height: 21)
                            .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        inlineText(item)
                            .font(.spline(size: 14, weight: 400))
                            .lineSpacing(4)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(BurritoTheme.accent)
                    .frame(width: 3)
                inlineText(text)
                    .font(.spline(size: 14, weight: 400).italic())
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 14)
            .background(BurritoTheme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.spline(size: 12.5, weight: 400))
                    .foregroundStyle(.primary.opacity(0.82))
                    .textSelection(.enabled)
                    .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BurritoTheme.softBorder)
            }
        case .divider:
            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)
                .padding(.vertical, 8)
        }
    }

    private func inlineText(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(
            markdown: source,
            options: options
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            .burritoDisplay(size: 28, weight: 450)
        case 2:
            .burritoDisplay(size: 21, weight: 450)
        default:
            .burritoDisplay(size: 16, weight: 450)
        }
    }
}

private struct NoteSourceLabel: View {
    let title: String
    let detail: String
    let systemImage: String
    var isHuman = false

    var body: some View {
        HStack(spacing: 8) {
            BurritoIcon(name: systemImage)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .init(450), design: .monospaced))
            Text(detail)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.system(size: 10, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(isHuman ? BurritoTheme.accent : Color.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordingNotepadView: View {
    @Binding var title: String
    @Binding var userNotes: String
    let elapsed: TimeInterval
    let systemLevel: Double
    let microphoneLevel: Double
    let recordingMode: RecordingMode

    @FocusState private var notesFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(BurritoTheme.accent)
                        .frame(width: 7, height: 7)
                    Text("RECORDING")
                        .font(.system(size: 10, weight: .init(450), design: .monospaced))
                }
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .monospacedDigit()
                BurritoLabel(
                    recordingMode == .meeting ? "CALL + MIC · ON DEVICE" : "MAC AUDIO · ON DEVICE",
                    systemImage: "lock.fill"
                )
                .font(.system(size: 9, weight: .init(450), design: .monospaced))
                .foregroundStyle(BurritoTheme.sage)
                Spacer()
                RecordingSourceLevel(
                    title: "MAC",
                    systemImage: "speaker.wave.2.fill",
                    level: systemLevel
                )
                RecordingSourceLevel(
                    title: "MIC",
                    systemImage: "mic.fill",
                    level: microphoneLevel
                )
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 820)
            .padding(.horizontal, 44)
            .padding(.top, 28)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                TextField("Untitled note", text: $title)
                    .textFieldStyle(.plain)
                    .font(.burritoDisplay(size: 34, weight: .init(400)))

                NoteSourceLabel(
                    title: "Your notes",
                    detail: "Markdown · guides what Burrito writes",
                    systemImage: "person.fill",
                    isHuman: true
                )

                ZStack(alignment: .topLeading) {
                    if userNotes.isEmpty {
                        Text("Write Markdown—fragments, questions, headings, and lists are enough.")
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $userNotes)
                        .font(.system(size: 15, design: .monospaced))
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .focused($notesFocused)
                        .accessibilityLabel("Your Markdown meeting notes")
                        .accessibilityHint(
                            "Markdown is rendered after recording and guides Burrito's generated result"
                        )
                }
                .padding(14)
                .background(BurritoTheme.raised, in: Rectangle())
                .overlay {
                    Rectangle()
                        .stroke(
                            notesFocused
                                ? BurritoTheme.accent.opacity(0.65)
                                : BurritoTheme.softBorder,
                            lineWidth: notesFocused ? 1.25 : 1
                        )
                }
            }
            .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 44)
            .padding(.top, 24)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            notesFocused = true
        }
    }
}

private struct RecordingSourceLevel: View {
    let title: String
    let systemImage: String
    let level: Double

    var body: some View {
        HStack(spacing: 5) {
            BurritoIcon(name: systemImage)
            Text(title)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(BurritoTheme.softBorder)
                    Rectangle()
                        .fill(BurritoTheme.accent)
                        .frame(width: proxy.size.width * min(1, max(0, level)))
                }
            }
            .frame(width: 34, height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) audio level")
        .accessibilityValue("\(Int(min(1, max(0, level)) * 100)) percent")
    }
}

struct MemoryChatMessage: Identifiable, Equatable {
    let id: UUID
    let isUser: Bool
    var text: String
    let timestamp: Date
    let errorMessage: String?
    let scopeTitle: String?
    let usedMeetingEvidence: Bool
    let searchedMeetings: Bool

    init(
        id: UUID = UUID(),
        isUser: Bool,
        text: String,
        timestamp: Date = Date(),
        errorMessage: String? = nil,
        scopeTitle: String? = nil,
        usedMeetingEvidence: Bool = false,
        searchedMeetings: Bool = false
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.errorMessage = errorMessage
        self.scopeTitle = scopeTitle
        self.usedMeetingEvidence = usedMeetingEvidence
        self.searchedMeetings = searchedMeetings
    }
}

@MainActor
@Observable
final class MemoryChatSession {
    var messages: [MemoryChatMessage] = []
    var draft = ""
    var isAnswering = false
    var copiedMessageID: UUID?
    var scopedDocumentID: UUID?
    var mentionSelectionIndex = 0
    @ObservationIgnored var answerTask: Task<Void, Never>?

    func clear() {
        answerTask?.cancel()
        answerTask = nil
        isAnswering = false
        messages.removeAll()
    }
}

@MainActor
final class MemoryChatSessionStore {
    let askBurrito = MemoryChatSession()
    private var noteSessions: [UUID: MemoryChatSession] = [:]

    func session(for noteID: UUID) -> MemoryChatSession {
        if let session = noteSessions[noteID] {
            return session
        }
        let session = MemoryChatSession()
        noteSessions[noteID] = session
        return session
    }
}

private struct MemoryChatView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var session: MemoryChatSession
    let documents: [MemoryDocument]
    var usesSingleMeetingContext = false
    let languageIdentifier: String
    let openCitation: (MemoryCitation) -> Void

    @FocusState private var questionFocused: Bool

    private var scopedDocument: MemoryDocument? {
        guard let scopedDocumentID = session.scopedDocumentID else { return nil }
        return documents.first { $0.noteID == scopedDocumentID }
    }

    private var canAsk: Bool {
        !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.isAnswering
            && highlightedMentionDocument == nil
    }

    private var mentionQuery: String? {
        guard scopedDocument == nil else { return nil }
        return MemoryMention.query(in: session.draft)
    }

    private var matchingMentionDocuments: [MemoryDocument] {
        guard let mentionQuery else { return [] }
        let candidates = documents.sorted { $0.updatedAt > $1.updatedAt }
        guard !mentionQuery.isEmpty else {
            return Array(candidates.prefix(6))
        }
        return Array(
            candidates
                .filter { $0.title.localizedStandardContains(mentionQuery) }
                .prefix(6)
        )
    }

    private var highlightedMentionDocument: MemoryDocument? {
        guard matchingMentionDocuments.indices.contains(session.mentionSelectionIndex) else {
            return nil
        }
        return matchingMentionDocuments[session.mentionSelectionIndex]
    }

    private var suggestedPrompts: [String] {
        guard !documents.isEmpty else {
            return [
                "Help me draft a concise project update.",
                "Explain a difficult idea in simple terms.",
                "Brainstorm five names for a new product.",
                "Turn my rough thoughts into an action plan."
            ]
        }
        return [
            "What were the key decisions made?",
            "List all action items and assignees.",
            "What were the main objections or concerns?",
            "Summarize the next steps and deadlines."
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            if usesSingleMeetingContext, !session.messages.isEmpty {
                HStack {
                    Spacer()
                    clearChatButton
                }
                .padding(.horizontal, 18)
                .frame(height: 44)
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if session.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 22) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(documents.isEmpty
                                        ? "Ask Burrito anything"
                                        : "Ask anything — or search your meetings")
                                        .font(.burritoDisplay(size: 22, weight: 450))
                                    Text(documents.isEmpty
                                        ? "Chat with your selected on-device model. Meeting search becomes available after you record a transcript."
                                        : "Burrito answers general questions and can retrieve cited passages from your local transcripts when needed.")
                                        .font(.spline(size: 13, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(4)
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("SUGGESTED QUESTIONS")
                                        .font(.spline(size: 9, weight: 450))
                                        .tracking(0.7)
                                        .foregroundStyle(.tertiary)

                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                        ForEach(suggestedPrompts, id: \.self) { prompt in
                                            Button {
                                                BurritoHaptics.trigger(.alignment)
                                                submitPrompt(prompt)
                                            } label: {
                                                HStack(spacing: 8) {
                                                    BurritoIcon(name: "text.bubble", size: 11)
                                                        .foregroundStyle(BurritoTheme.accent)
                                                    Text(prompt)
                                                        .font(.spline(size: 12, weight: .regular))
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.leading)
                                                    Spacer()
                                                    BurritoIcon(name: "arrow.up.right", size: 10)
                                                        .foregroundStyle(.tertiary)
                                                }
                                                .padding(12)
                                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                                .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 42)
                        } else {
                            if !usesSingleMeetingContext {
                                HStack {
                                    Spacer()
                                    clearChatButton
                                }
                            }

                            ForEach(session.messages) { msg in
                                if msg.isUser {
                                    userMessageBubble(msg)
                                        .id(msg.id)
                                } else if msg.text.isEmpty && msg.errorMessage == nil && session.isAnswering {
                                    assistantSkeletonCard
                                        .id(msg.id)
                                } else {
                                    assistantMessageCard(msg)
                                        .id(msg.id)
                                }
                            }

                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 38)
                    .padding(.top, 24)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .onChange(of: session.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: session.isAnswering) { _, answering in
                    if answering {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            VStack(spacing: 8) {
                if mentionQuery != nil {
                    mentionPicker
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HStack(spacing: 10) {
                    if let scopedDocument {
                        Button {
                            session.scopedDocumentID = nil
                            questionFocused = true
                        } label: {
                            HStack(spacing: 5) {
                                Text("@")
                                    .font(.spline(size: 11, weight: 450, relativeTo: .caption))
                                Text(scopedDocument.title)
                                    .lineLimit(1)
                                BurritoIcon(name: "xmark", size: 8)
                            }
                            .font(.spline(size: 11, weight: 450, relativeTo: .caption))
                            .foregroundStyle(BurritoTheme.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(BurritoTheme.accent.opacity(0.28))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Remove meeting scope")
                        .accessibilityLabel("Remove meeting scope: \(scopedDocument.title)")
                    }

                    TextField(
                        scopedDocument.map { "Ask about \($0.title)…" }
                            ?? "Ask anything — type @ to choose a meeting",
                        text: $session.draft
                    )
                    .textFieldStyle(.plain)
                    .font(.spline(size: 13, weight: .regular))
                    .focused($questionFocused)
                    .onSubmit(submitComposer)
                    .onKeyPress(.downArrow) {
                        guard mentionQuery != nil else { return .ignored }
                        moveMentionSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard mentionQuery != nil else { return .ignored }
                        moveMentionSelection(by: -1)
                        return .handled
                    }
                    .onChange(of: session.draft) { _, _ in
                        session.mentionSelectionIndex = 0
                    }

                    if session.isAnswering {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 4)
                    } else {
                        Button(action: ask) {
                            BurritoIcon(name: "arrow.up", size: 12)
                                .foregroundStyle(canAsk ? .white : Color.secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    canAsk ? BurritoTheme.accent : BurritoTheme.controlFill,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAsk)
                        .accessibilityLabel("Ask question")
                        .help("Send question")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BurritoTheme.softBorder)
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 38)
            .padding(.vertical, 18)
        }
        .background(BurritoTheme.canvas)
        .onAppear { questionFocused = true }
    }

    private var mentionPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CHOOSE A MEETING")
                    .font(.spline(size: 9, weight: 450, relativeTo: .caption2))
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("↑↓  RETURN")
                    .font(.spline(size: 9, weight: 450, relativeTo: .caption2))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)

            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)

            if matchingMentionDocuments.isEmpty {
                Text("No meeting matches “\(mentionQuery ?? "")”")
                    .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ForEach(
                    Array(matchingMentionDocuments.enumerated()),
                    id: \.element.noteID
                ) { index, document in
                    Button {
                        selectMention(document)
                    } label: {
                        HStack(spacing: 10) {
                            Text("@")
                                .font(.spline(size: 13, weight: 450))
                                .foregroundStyle(BurritoTheme.accent)
                                .frame(width: 18)
                            Text(document.title)
                                .font(.spline(size: 12, weight: 450, relativeTo: .callout))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(document.updatedAt, format: .dateTime.month(.abbreviated).day())
                                .font(.spline(size: 10, weight: .regular, relativeTo: .caption2))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            index == session.mentionSelectionIndex
                                ? BurritoTheme.accentSoft
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder)
        }
    }

    private var clearChatButton: some View {
        Button {
            BurritoHaptics.trigger(.alignment)
            withAnimation(reduceMotion ? nil : .burritoSpring) {
                session.clear()
            }
        } label: {
            BurritoLabel("Clear chat", systemImage: "trash")
                .font(.spline(size: 11, weight: 450))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    BurritoTheme.controlFill,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BurritoTheme.softBorder)
                }
        }
        .buttonStyle(.plain)
    }

    private func userMessageBubble(_ msg: MemoryChatMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    Text("YOU")
                        .font(.spline(size: 9, weight: 450))
                        .foregroundStyle(BurritoTheme.accent)
                    Text(msg.timestamp, format: .dateTime.hour().minute())
                        .font(.spline(size: 9, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let scopeTitle = msg.scopeTitle {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(.spline(size: 10, weight: 450))
                            Text(scopeTitle)
                                .font(.spline(size: 10, weight: 450))
                        }
                        .foregroundStyle(BurritoTheme.accent)
                    }
                    Text(msg.text)
                        .font(.spline(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .padding(14)
                .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BurritoTheme.accent.opacity(0.3))
                }
            }
        }
    }

    private func assistantMessageCard(_ msg: MemoryChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(BurritoTheme.accentSoft)
                        .frame(width: 22, height: 22)
                    BurritoIcon(name: "sparkles", size: 11)
                        .foregroundStyle(BurritoTheme.accent)
                }
                Text("Burrito AI")
                    .font(.spline(size: 11, weight: 450))
                    .foregroundStyle(.primary)

                Spacer()

                if msg.errorMessage == nil {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.text, forType: .string)
                        BurritoHaptics.trigger(.alignment)
                        withAnimation(reduceMotion ? nil : .burritoSpring) {
                            session.copiedMessageID = msg.id
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if session.copiedMessageID == msg.id {
                                session.copiedMessageID = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            BurritoIcon(name: session.copiedMessageID == msg.id ? "checkmark" : "doc.on.doc", size: 10)
                            Text(session.copiedMessageID == msg.id ? "Copied" : "Copy")
                                .font(.spline(size: 10, weight: 450))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = msg.errorMessage {
                BurritoLabel(error, systemImage: "exclamationmark.triangle")
                    .font(.spline(size: 11, weight: .regular))
                    .foregroundStyle(.red)
            } else {
                MarkdownNoteContent(
                    markdown: msg.text,
                    openMemory: openCitation
                )
            }
        }
        .padding(16)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BurritoTheme.softBorder)
        }
    }

    private var assistantSkeletonCard: some View {
        BurritoChatGenerationStatus()
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastID = session.messages.last?.id {
            withAnimation(reduceMotion ? nil : .burritoSpring) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func submitComposer() {
        if let highlightedMentionDocument {
            selectMention(highlightedMentionDocument)
            return
        }
        ask()
    }

    private func moveMentionSelection(by offset: Int) {
        guard !matchingMentionDocuments.isEmpty else { return }
        let count = matchingMentionDocuments.count
        session.mentionSelectionIndex = (session.mentionSelectionIndex + offset + count) % count
    }

    private func selectMention(_ document: MemoryDocument) {
        session.scopedDocumentID = document.noteID
        session.draft = MemoryMention.questionWithoutQuery(in: session.draft)
        session.mentionSelectionIndex = 0
        questionFocused = true
        BurritoHaptics.trigger(.alignment)
    }

    private func submitPrompt(_ prompt: String) {
        session.draft = prompt
        ask()
    }

    private func ask() {
        guard canAsk else { return }
        let submittedQuestion = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedScope = scopedDocument
        let conversation = session.messages
            .filter { $0.errorMessage == nil }
            .map {
                BurritoChatTurn(
                    role: $0.isUser ? .user : .assistant,
                    text: $0.text
                )
            }
        session.draft = ""
        session.scopedDocumentID = nil
        BurritoHaptics.trigger(.alignment)

        let userMsg = MemoryChatMessage(
            isUser: true,
            text: submittedQuestion,
            scopeTitle: submittedScope?.title
        )
        let assistantID = UUID()
        let assistantTimestamp = Date()
        let assistantPlaceholder = MemoryChatMessage(
            id: assistantID,
            isUser: false,
            text: "",
            timestamp: assistantTimestamp,
            scopeTitle: submittedScope?.title
        )
        withAnimation(reduceMotion ? nil : .burritoSpring) {
            session.messages.append(userMsg)
            session.messages.append(assistantPlaceholder)
        }
        let searchScope = submittedScope ?? (usesSingleMeetingContext ? documents.first : nil)
        let meetingSearchRequired = MeetingQueryIntent.requiresSearch(
            submittedQuestion,
            hasDefaultMeetingScope: usesSingleMeetingContext,
            hasExplicitMeetingScope: submittedScope != nil
        )
        session.isAnswering = true

        session.answerTask = Task {
            let result = await BurritoChatAnswerer.shared.answer(
                question: submittedQuestion,
                conversation: conversation,
                documents: documents,
                scopedDocument: searchScope,
                meetingSearchRequired: meetingSearchRequired,
                languageIdentifier: languageIdentifier,
                onTextUpdate: { partialText in
                    guard let index = session.messages.firstIndex(where: { $0.id == assistantID }) else {
                        return
                    }
                    session.messages[index].text = partialText
                }
            )

            guard !Task.isCancelled else { return }

            withAnimation(reduceMotion ? nil : .burritoSpring) {
                switch result {
                case .success(let response):
                    let botMsg = MemoryChatMessage(
                        id: assistantID,
                        isUser: false,
                        text: response.text,
                        timestamp: assistantTimestamp,
                        scopeTitle: submittedScope?.title,
                        usedMeetingEvidence: response.usedMeetingEvidence,
                        searchedMeetings: response.searchedMeetings
                    )
                    if let index = session.messages.firstIndex(where: { $0.id == assistantID }) {
                        session.messages[index] = botMsg
                    }
                case .failure(let error):
                    let botMsg = MemoryChatMessage(
                        id: assistantID,
                        isUser: false,
                        text: "Could not retrieve answer.",
                        timestamp: assistantTimestamp,
                        errorMessage: error.recoveryMessage,
                        scopeTitle: submittedScope?.title
                    )
                    if let index = session.messages.firstIndex(where: { $0.id == assistantID }) {
                        session.messages[index] = botMsg
                    }
                }
                session.isAnswering = false
                session.answerTask = nil
            }
            BurritoHaptics.trigger(.levelChange)
        }
    }
}

private struct BurritoChatGenerationStatus: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phraseIndex = 0

    private let phrases = ["Thinking…", "Cooking…", "Mulling…"]

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            ZStack(alignment: .leading) {
                Text(phrases[phraseIndex])
                    .id(phraseIndex)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 3)),
                            removal: .opacity.combined(with: .offset(y: -3))
                        )
                    )
            }
            .frame(width: 100, height: 22, alignment: .leading)
            .clipped()
        }
        .font(.spline(size: 13, weight: 450))
        .foregroundStyle(.secondary)
        .modifier(BurritoChatShimmer(enabled: !reduceMotion))
        .padding(.leading, 2)
        .padding(.vertical, 12)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1.7))
                } catch {
                    return
                }
                withAnimation(.easeInOut(duration: 0.28)) {
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Burrito is generating an answer")
    }
}

private struct BurritoChatShimmer: ViewModifier {
    let enabled: Bool

    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.primary.opacity(0.32),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: max(44, geometry.size.width * 0.42))
                    .offset(
                        x: enabled && isActive
                            ? geometry.size.width
                            : -geometry.size.width * 0.5
                    )
                }
                .allowsHitTesting(false)
                .mask(content)
            }
            .animation(
                enabled
                    ? .linear(duration: 1.55).repeatForever(autoreverses: false)
                    : nil,
                value: isActive
            )
            .onAppear {
                guard enabled else { return }
                isActive = true
            }
            .onChange(of: enabled) { _, enabled in
                isActive = enabled
            }
    }
}

private struct NoteProvenanceView: View {
    let userNotes: String
    let generatedNotes: String
    let openTranscript: (UUID) -> Void

    private var hasHumanNotes: Bool {
        !userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if hasHumanNotes {
                NoteSourceLabel(
                    title: "Your notes",
                    detail: "Written by you",
                    systemImage: "person.fill",
                    isHuman: true
                )
                MarkdownNoteContent(markdown: userNotes, openTranscript: openTranscript)
                    .padding(20)
                    .background(BurritoTheme.raised, in: Rectangle())
                    .overlay {
                        Rectangle().stroke(BurritoTheme.accent.opacity(0.22))
                    }

                Rectangle()
                    .fill(BurritoTheme.softBorder)
                    .frame(height: 1)
                    .padding(.vertical, 4)
            }

            NoteSourceLabel(
                title: "Burrito notes",
                detail: "Generated on this Mac",
                systemImage: "sparkles"
            )
            MarkdownNoteContent(markdown: generatedNotes, openTranscript: openTranscript)
        }
    }
}

private struct NoteEditingView: View {
    @Binding var userNotes: String
    @Binding var generatedNotes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoteSourceLabel(
                title: "Your notes",
                detail: "Used as guidance when regenerating",
                systemImage: "person.fill",
                isHuman: true
            )
            TextEditor(text: $userNotes)
                .font(.spline(size: 14, weight: .regular))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110, maxHeight: 190)
                .padding(12)
                .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.accent.opacity(0.28))
                }

            NoteSourceLabel(
                title: "Burrito notes",
                detail: "Generated, then editable by you",
                systemImage: "sparkles"
            )
            TextEditor(text: $generatedNotes)
                .font(.spline(size: 14, weight: .regular))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
                .padding(12)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder)
                }
        }
        .frame(maxWidth: 820, maxHeight: .infinity)
        .padding(.horizontal, 44)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HeaderSegmentTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BurritoIcon(name: systemImage, size: 13)
                .foregroundStyle(isSelected ? BurritoTheme.accent : Color.secondary)
                .frame(width: 34, height: 28)
                .background(
                    isSelected ? BurritoTheme.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(title)
    }
}

private struct MeetingContextPanel: View {
    let event: CalendarEventSnapshot
    let relatedNotes: [Note]
    let selectNote: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            BurritoIcon(name: "calendar.badge.checkmark", size: 11)
                .foregroundStyle(BurritoTheme.accent)
            Text(event.startDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.spline(size: 11, weight: 450, relativeTo: .caption))
                .foregroundStyle(.primary)
            Text("· \(event.startDate.formatted(.dateTime.hour().minute()))–\(event.endDate.formatted(.dateTime.hour().minute())) · \(event.calendarName)")
                .font(.spline(size: 11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(.secondary)

            if let meetingURL = event.meetingURL {
                Spacer(minLength: 4)
                BurritoButton("Join", systemImage: "video") {
                    NSWorkspace.shared.open(meetingURL)
                }
                .font(.spline(size: 10, weight: 450, relativeTo: .caption2))
                .buttonStyle(HomeToolbarButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(BurritoTheme.softBorder)
        }
    }
}

private struct NoteDetailView: View {
    private enum Tab {
        case notes
        case transcript
        case chat
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var note: Note
    @Bindable var chatSession: MemoryChatSession
    let externalCitedSegmentID: UUID?
    let relatedNotes: [Note]
    let coordinator: AppCoordinator
    let fileStore: LocalRecordingFileStore
    let folders: [Folder]
    let exportAction: () -> Void
    let backAction: () -> Void
    let selectRelatedNote: (UUID) -> Void
    let newRecordingAction: () -> Void

    @State private var selectedTab: Tab = .notes
    @State private var isEditingMarkdown = false
    @State private var showingFolderPopover = false
    @State private var showingMorePopover = false
    @State private var confirmingRegeneration = false
    @State private var didCopyNotes = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var player: AVAudioPlayer?
    @State private var citedSegmentID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Unified Top Header Bar (Back button, Left Segmented Tabs, Editable Title, Top Right Actions)
            if !isRecordingThisNote {
                HStack(spacing: 12) {
                    // Back Button
                    BurritoButton("Back to notes", systemImage: "chevron.left") {
                        backAction()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(BurritoIconButtonStyle())
                    .accessibilityHint("Returns to the notes library")

                    // Left-aligned Segmented Tab Bar (Notes, Transcript, Ask AI)
                    HStack(spacing: 2) {
                        HeaderSegmentTabButton(
                            title: "Notes",
                            systemImage: "doc.text",
                            isSelected: selectedTab == .notes
                        ) {
                            BurritoHaptics.trigger(.alignment)
                            withAnimation(reduceMotion ? nil : .burritoSpring) {
                                selectedTab = .notes
                            }
                        }

                        HeaderSegmentTabButton(
                            title: "Transcript",
                            systemImage: "waveform",
                            isSelected: selectedTab == .transcript
                        ) {
                            BurritoHaptics.trigger(.alignment)
                            withAnimation(reduceMotion ? nil : .burritoSpring) {
                                selectedTab = .transcript
                            }
                        }

                        HeaderSegmentTabButton(
                            title: "Ask AI",
                            systemImage: "sparkles",
                            isSelected: selectedTab == .chat
                        ) {
                            BurritoHaptics.trigger(.alignment)
                            withAnimation(reduceMotion ? nil : .burritoSpring) {
                                selectedTab = .chat
                            }
                        }
                    }
                    .padding(3)
                    .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BurritoTheme.softBorder)
                    }

                    if selectedTab != .chat {
                        // Meeting Title aligned directly on the left after tabs
                        TextField("Untitled note", text: titleBinding)
                            .textFieldStyle(.plain)
                            .font(.spline(size: 15, weight: 450))
                            .foregroundStyle(.primary)

                        Spacer()

                        // Right Controller Group
                        HStack(spacing: 8) {
                            if selectedTab == .notes {
                                Button {
                                    BurritoHaptics.trigger(.alignment)
                                    withAnimation(reduceMotion ? nil : .burritoSpring) {
                                        isEditingMarkdown.toggle()
                                    }
                                } label: {
                                    BurritoLabel(
                                        isEditingMarkdown ? "Done" : "Edit",
                                        systemImage: isEditingMarkdown ? "checkmark" : "pencil"
                                    )
                                    .font(.spline(size: 12, weight: 450))
                                }
                                .buttonStyle(HomeToolbarButtonStyle())
                                .help(isEditingMarkdown ? "Finish editing" : "Edit note")
                            }

                            Button {
                                copyMarkdown()
                            } label: {
                                BurritoIcon(name: didCopyNotes ? "checkmark" : "doc.on.doc")
                                    .contentTransition(.symbolEffect(.replace))
                                    .foregroundStyle(didCopyNotes ? Color.green : Color.primary)
                            }
                            .buttonStyle(BurritoIconButtonStyle())
                            .help(didCopyNotes ? "Copied" : "Copy notes")

                            Button {
                                exportAction()
                            } label: {
                                BurritoIcon(name: "square.and.arrow.up")
                            }
                            .buttonStyle(BurritoIconButtonStyle())
                            .help("Export Markdown")

                            // 3-Dot Options Button
                            Button {
                                showingMorePopover.toggle()
                            } label: {
                                BurritoIcon(name: "ellipsis")
                                    .rotationEffect(.degrees(90))
                            }
                            .buttonStyle(BurritoIconButtonStyle())
                            .accessibilityLabel("More options")
                            .popover(
                                isPresented: $showingMorePopover,
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .top
                            ) {
                                BurritoPopoverPanel {
                                    BurritoPopoverRow(
                                        title: note.folder.map { "Folder: \($0.name)" } ?? "Add to folder…",
                                        systemImage: "folder"
                                    ) {
                                        showingMorePopover = false
                                        showingFolderPopover = true
                                    }

                                    BurritoPopoverRow(
                                        title: "Generate again",
                                        systemImage: "arrow.clockwise"
                                    ) {
                                        showingMorePopover = false
                                        requestRegeneration()
                                    }

                                    BurritoPopoverDivider()

                                    ShareLink(item: note.exportedMarkdown) {
                                        BurritoPopoverRowLabel(
                                            title: "Share",
                                            systemImage: "paperplane"
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if let path = note.systemAudioRelativePath {
                                        BurritoPopoverRow(
                                            title: "Play system audio",
                                            systemImage: "play.fill"
                                        ) {
                                            play(fileStore.url(forRelativePath: path))
                                            showingMorePopover = false
                                        }
                                    }
                                    if let path = note.microphoneAudioRelativePath {
                                        BurritoPopoverRow(
                                            title: "Play microphone",
                                            systemImage: "mic.fill"
                                        ) {
                                            play(fileStore.url(forRelativePath: path))
                                            showingMorePopover = false
                                        }
                                    }
                                    if player?.isPlaying == true {
                                        BurritoPopoverRow(
                                            title: "Stop audio",
                                            systemImage: "stop.fill"
                                        ) {
                                            player?.stop()
                                            showingMorePopover = false
                                        }
                                    }
                                }
                            }
                            .popover(
                                isPresented: $showingFolderPopover,
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .top
                            ) {
                                folderPopoverContent
                            }
                        }
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(BurritoTheme.canvas)
            }

            // Sub-Header Metadata Strip (Hidden in Chat Tab for 100% clean canvas)
            if !isRecordingThisNote && selectedTab != .chat {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        BurritoIcon(name: "calendar", size: 11)
                            .foregroundStyle(.tertiary)
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.spline(size: 11, weight: 450))
                            .foregroundStyle(.secondary)
                    }

                    Text("·")
                        .font(.spline(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 6) {
                        BurritoIcon(name: "clock", size: 11)
                            .foregroundStyle(.tertiary)
                        Text(Duration.seconds(note.duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.spline(size: 11, weight: 450))
                            .foregroundStyle(.secondary)
                    }

                    Text("·")
                        .font(.spline(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 6) {
                        BurritoIcon(name: note.templateSnapshot.symbol, size: 11)
                            .foregroundStyle(.tertiary)
                        Text(note.templateSnapshot.name)
                            .font(.spline(size: 11, weight: 450))
                            .foregroundStyle(.secondary)
                    }

                    if let calendarEvent = note.calendarEvent {
                        Text("·")
                            .font(.spline(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 6) {
                            BurritoIcon(name: "calendar.badge.checkmark", size: 11)
                                .foregroundStyle(BurritoTheme.accent)
                            Text("\(calendarEvent.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \(calendarEvent.startDate.formatted(.dateTime.hour().minute()))–\(calendarEvent.endDate.formatted(.dateTime.hour().minute()))")
                                .font(.spline(size: 11, weight: 450))
                                .foregroundStyle(.secondary)
                        }

                        if let meetingURL = calendarEvent.meetingURL {
                            Button {
                                NSWorkspace.shared.open(meetingURL)
                            } label: {
                                HStack(spacing: 4) {
                                    BurritoIcon(name: "video.fill", size: 9)
                                    Text("Join")
                                        .font(.spline(size: 10, weight: 450))
                                }
                                .foregroundStyle(BurritoTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(BurritoTheme.accent.opacity(0.3))
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Join meeting video call")
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 44)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            // Full Height Content Body
            if isRecordingThisNote {
                RecordingNotepadView(
                    title: titleBinding,
                    userNotes: userNotesBinding,
                    elapsed: coordinator.elapsed,
                    systemLevel: coordinator.activity.system,
                    microphoneLevel: coordinator.activity.microphone,
                    recordingMode: note.recordingMode
                )
                .transition(.opacity)
            } else if selectedTab == .notes {
                if isEditingMarkdown {
                    NoteEditingView(
                        userNotes: userNotesBinding,
                        generatedNotes: notesBinding
                    )
                    .transition(.opacity)
                } else {
                    ScrollView {
                        NoteProvenanceView(
                            userNotes: note.userNotes,
                            generatedNotes: note.markdownBody,
                            openTranscript: { id in
                                citedSegmentID = id
                                selectedTab = .transcript
                            }
                        )
                        .frame(maxWidth: 820, alignment: .leading)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 24)
                        .hidesEnclosingScrollIndicators()
                    }
                    .scrollIndicators(.hidden)
                    .transition(.opacity)
                }
            } else if selectedTab == .transcript {
                TranscriptEditor(note: note, focusedSegmentID: citedSegmentID)
            } else {
                MemoryChatView(
                    session: chatSession,
                    documents: [
                        MemoryDocument(
                            noteID: note.id,
                            title: note.title,
                            updatedAt: note.updatedAt,
                            segments: note.transcriptSegments
                        ),
                    ],
                    usesSingleMeetingContext: true,
                    languageIdentifier: note.languageIdentifier
                ) { citation in
                    guard citation.noteID == note.id else { return }
                    citedSegmentID = citation.segmentID
                    selectedTab = .transcript
                }
            }
        }
        .background(BurritoTheme.canvas)
        .navigationTitle("")
        .onAppear {
            openExternalCitation()
        }
        .onChange(of: externalCitedSegmentID) {
            openExternalCitation()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if isRecordingThisNote {
                    RecordingControlButton(
                        isRecording: true,
                        elapsed: coordinator.elapsed,
                        systemLevel: coordinator.activity.system,
                        microphoneLevel: coordinator.activity.microphone
                    ) {
                        Task { await coordinator.stop(context: modelContext) }
                    }
                } else if let stage = note.processingStage {
                    ProcessingRail(
                        stage: stage,
                        isContinuation: !note.markdownBody.isEmpty
                    )
                } else {
                    if note.notesMayBeOutdated {
                        HStack {
                            BurritoIcon(name: "exclamationmark.triangle.fill")
                                .foregroundStyle(BurritoTheme.accent)
                            Text("The transcript changed. Generated notes may be outdated.")
                            Spacer()
                            Button("Regenerate") {
                                requestRegeneration()
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(BurritoTheme.accentSoft, in: Rectangle())
                    }

                    RecordingControlButton(
                        isRecording: false,
                        elapsed: 0,
                        systemLevel: 0,
                        microphoneLevel: 0,
                        action: newRecordingAction
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, 22)
        }
        .overlay(alignment: .center) {
            if confirmingRegeneration {
                BurritoModalBackdrop {
                    BurritoMessageDialog(
                        title: "Replace your edited notes?",
                        message: "Burrito will generate a fresh version. You can undo the replacement with Command-Z.",
                        confirmTitle: "Replace and generate",
                        isDestructive: true,
                        cancel: { confirmingRegeneration = false },
                        confirm: {
                            confirmingRegeneration = false
                            regenerate()
                        }
                    )
                }
            }
        }
    }

    private func openExternalCitation() {
        guard let externalCitedSegmentID else { return }
        citedSegmentID = externalCitedSegmentID
        selectedTab = .transcript
    }

    private var folderPopoverContent: some View {
        BurritoPopoverPanel(title: "Move to folder") {
            BurritoPopoverRow(
                title: "No folder",
                systemImage: "tray",
                isSelected: note.folder == nil
            ) {
                note.folder = nil
                showingFolderPopover = false
            }
            ForEach(folders) { folder in
                BurritoPopoverRow(
                    title: folder.name,
                    systemImage: "folder",
                    isSelected: note.folder?.id == folder.id
                ) {
                    note.folder = folder
                    showingFolderPopover = false
                }
            }
        }
    }

    private var isRecordingThisNote: Bool {
        coordinator.captureState.isRecording && coordinator.activeNoteID == note.id
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { note.title },
            set: {
                note.title = $0
                note.updatedAt = .now
            }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { note.markdownBody },
            set: {
                note.markdownBody = $0
                note.userEditedNotes = true
                note.updatedAt = .now
            }
        )
    }

    private var userNotesBinding: Binding<String> {
        Binding(
            get: { note.userNotes },
            set: {
                note.userNotes = $0
                note.updatedAt = .now
            }
        )
    }

    private func regenerate() {
        Task {
            await coordinator.generate(
                note: note,
                context: modelContext,
                undoManager: undoManager
            )
        }
    }

    private func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.exportedMarkdown, forType: .string)
        copyFeedbackTask?.cancel()
        withAnimation(.smooth(duration: 0.18)) {
            didCopyNotes = true
        }
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.18)) {
                    didCopyNotes = false
                }
            }
        }
    }

    private func requestRegeneration() {
        if note.userEditedNotes {
            confirmingRegeneration = true
        } else {
            regenerate()
        }
    }

    private func play(_ url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            NSSound.beep()
        }
    }
}

private struct EditorTabButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            BurritoHaptics.trigger(.alignment)
            select()
        } label: {
            VStack(spacing: 7) {
                Text(title)
                    .font(.spline(size: 13, weight: isSelected ? 450 : 400))
                    .foregroundStyle(isSelected ? .primary : (isHovered ? .primary : .secondary))
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                    if isSelected {
                        Rectangle()
                            .fill(BurritoTheme.accent)
                            .frame(height: 2)
                            .transition(.scale(scale: 0.8, anchor: .center).combined(with: .opacity))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .burritoSpring, value: isSelected)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovered
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    private let template: NoteTemplate?
    private let save: (String, String, String) -> Void

    @State private var name: String
    @State private var symbol: String
    @State private var instructions: String

    init(
        template: NoteTemplate?,
        save: @escaping (String, String, String) -> Void
    ) {
        self.template = template
        self.save = save
        _name = State(initialValue: template?.name ?? "")
        _symbol = State(initialValue: template?.symbol ?? "note.text")
        _instructions = State(initialValue: template?.instructions ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(template == nil ? "New template" : "Edit template")
                    .font(.burritoDisplay(size: 32, weight: .regular))
                Text("Describe exactly how Burrito should organize the transcript.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                BurritoSectionLabel(title: "Name")
                TextField("Meeting brief", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(BurritoTheme.controlFill, in: Rectangle())
                    .overlay {
                        Rectangle()
                            .stroke(BurritoTheme.softBorder)
                    }
            }

            VStack(alignment: .leading, spacing: 9) {
                BurritoSectionLabel(title: "Symbol")
                TemplateSymbolPicker(selection: $symbol)
            }

            VStack(alignment: .leading, spacing: 9) {
                BurritoSectionLabel(title: "Instructions")
                TextEditor(text: $instructions)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 190)
                    .background(BurritoTheme.controlFill, in: Rectangle())
                    .overlay {
                        Rectangle()
                            .stroke(BurritoTheme.softBorder)
                    }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    save(
                        name.trimmingCharacters(in: .whitespacesAndNewlines),
                        symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .buttonStyle(BurritoActionButtonStyle(prominent: true))
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 600)
        .background(BurritoTheme.paper)
    }
}

private struct TemplateSymbolPicker: View {
    @Binding var selection: String
    @State private var query = ""

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 70), spacing: 4),
        count: 6
    )

    private var symbols: [TemplateSymbolOption] {
        TemplateSymbolOption.matching(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BurritoIcon(name: selection, size: 15)
                    .foregroundStyle(BurritoTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(BurritoTheme.accentSoft, in: Rectangle())
                    .accessibilityHidden(true)

                Text(TemplateSymbolOption.title(for: selection))
                    .font(.system(size: 12, weight: 450))
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 7) {
                    BurritoIcon(name: "magnifyingglass", size: 10)
                        .foregroundStyle(.tertiary)
                    TextField("Search symbols", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            BurritoIcon(name: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear symbol search")
                    }
                }
                .padding(.horizontal, 9)
                .frame(width: 220, height: 30)
                .background(BurritoTheme.controlFill, in: Rectangle())
            }
            .padding(10)

            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(height: 1)

            ScrollView {
                if symbols.isEmpty {
                    VStack(spacing: 5) {
                        Text("No symbols found")
                            .font(.system(size: 12, weight: 450))
                        Text("Try a broader word such as work, study, or meeting.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(symbols) { option in
                            Button {
                                selection = option.systemName
                            } label: {
                                VStack(spacing: 5) {
                                    BurritoIcon(name: option.systemName, size: 15)
                                    Text(option.title)
                                        .font(.system(size: 9, weight: 450))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(
                                    selection == option.systemName
                                        ? BurritoTheme.accent
                                        : Color.secondary
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                selection == option.systemName
                                    ? BurritoTheme.accentSoft
                                    : Color.clear,
                                in: Rectangle()
                            )
                            .overlay {
                                if selection == option.systemName {
                                    Rectangle()
                                        .stroke(BurritoTheme.accent.opacity(0.45))
                                }
                            }
                            .help(option.title)
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(
                                selection == option.systemName ? .isSelected : []
                            )
                        }
                    }
                    .padding(6)
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 162)
        }
        .background(BurritoTheme.controlFill.opacity(0.55), in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(BurritoTheme.softBorder)
        }
    }
}

private struct TranscriptEditor: View {
    @Bindable var note: Note
    let focusedSegmentID: UUID?
    @State private var hoveredSegmentID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if note.transcriptSegments.isEmpty {
                VStack(spacing: 14) {
                    TranscriptSignalMark(tint: BurritoTheme.accent)
                        .frame(width: 34, height: 28)
                    VStack(spacing: 4) {
                        Text("The tape is quiet")
                            .font(.burritoDisplay(size: 18))
                        Text("Recorded words will gather here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 88)
                } else {
                    LazyVStack(spacing: 0) {
                    HStack(spacing: 18) {
                        HStack(spacing: 8) {
                            TranscriptSignalMark(tint: BurritoTheme.accent)
                                .frame(width: 26, height: 20)
                            Text("Conversation tape")
                                .font(.burritoDisplay(size: 15, weight: 450))
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            sourceKey(
                                title: note.recordingMode == .meeting ? "Person 2" : "Computer",
                                tint: BurritoTheme.accent
                            )
                            sourceKey(
                                title: note.recordingMode == .meeting ? "Person 1" : "You",
                                tint: BurritoTheme.sage
                            )
                        }
                        Text("\(note.transcriptSegments.count) passages")
                            .font(.system(size: 10, weight: 450))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.leading, 72)
                    .padding(.trailing, 10)
                    .padding(.bottom, 28)

                    ForEach(
                        Array(
                            Transcript.latestFirst(note.transcriptSegments)
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, segment in
                        HStack(alignment: .top, spacing: 0) {
                            Text(
                                Duration.seconds(segment.startTime)
                                    .formatted(.time(pattern: .minuteSecond))
                            )
                            .font(.system(size: 10, weight: 450, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(
                                hoveredSegmentID == segment.id ? .secondary : .tertiary
                            )
                            .frame(width: 54, alignment: .trailing)
                            .padding(.top, 3)

                            VStack(spacing: 8) {
                                TranscriptSignalMark(tint: sourceTint(for: segment.source))
                                    .frame(width: 30, height: 22)
                                if index < note.transcriptSegments.count - 1 {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    sourceTint(for: segment.source).opacity(0.34),
                                                    BurritoTheme.softBorder,
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 50)

                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 8) {
                                    TextField(
                                        sourceTitle(for: segment.source),
                                        text: speakerBinding(for: segment.id)
                                    )
                                        .textFieldStyle(.plain)
                                        .frame(maxWidth: 120)
                                        .font(.system(size: 10, weight: 450))
                                        .tracking(0.5)
                                        .foregroundStyle(sourceTint(for: segment.source))
                                        .help("Edit this passage’s speaker name")
                                    Text(durationLabel(for: segment.duration))
                                        .font(.system(size: 9, design: .monospaced))
                                        .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                }

                                TextField(
                                    "Transcript segment",
                                    text: binding(for: segment.id),
                                    axis: .vertical
                                )
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .lineLimit(1...10)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 1)
                            .padding(.bottom, 28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 5)
                        .background(
                            sourceTint(for: segment.source).opacity(
                                focusedSegmentID == segment.id
                                    ? 0.16
                                    : hoveredSegmentID == segment.id ? 0.055 : 0
                            ),
                            in: Rectangle()
                        )
                        .id(segment.id)
                        .animation(.easeOut(duration: 0.14), value: hoveredSegmentID)
                        .onHover { isHovered in
                            hoveredSegmentID = isHovered ? segment.id : nil
                        }
                    }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity)
                    .hidesEnclosingScrollIndicators()
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .onAppear { scrollToCitation(using: proxy) }
            .onChange(of: focusedSegmentID) { scrollToCitation(using: proxy) }
        }
    }

    private func scrollToCitation(using proxy: ScrollViewProxy) {
        guard let focusedSegmentID else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(focusedSegmentID, anchor: .center)
        }
    }

    private func sourceKey(title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(tint)
                .frame(width: 9, height: 3)
            Text(title)
                .font(.system(size: 9, weight: 450))
                .foregroundStyle(.tertiary)
        }
    }

    private func sourceTitle(for source: AudioSource) -> String {
        switch source {
        case .system: note.recordingMode == .meeting ? "Person 2" : "Computer"
        case .microphone: note.recordingMode == .meeting ? "Person 1" : "You"
        }
    }

    private func sourceTint(for source: AudioSource) -> Color {
        switch source {
        case .system: BurritoTheme.accent
        case .microphone: BurritoTheme.sage
        }
    }

    private func durationLabel(for duration: TimeInterval) -> String {
        let rounded = max(1, Int(duration.rounded()))
        return "\(rounded)s"
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                note.transcriptSegments.first(where: { $0.id == id })?.text ?? ""
            },
            set: { newValue in
                var segments = note.transcriptSegments
                guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
                segments[index].text = newValue
                note.replaceTranscript(with: segments, marksEdited: true)
            }
        )
    }

    private func speakerBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                note.transcriptSegments.first(where: { $0.id == id })?.speakerName ?? ""
            },
            set: { newValue in
                var segments = note.transcriptSegments
                guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                segments[index].speakerName = trimmed.isEmpty ? nil : trimmed
                note.replaceTranscript(with: segments, marksEdited: true)
            }
        )
    }
}

private struct TranscriptSignalMark: View {
    let tint: Color
    private let heights: [CGFloat] = [5, 11, 17, 9, 14, 6]

    var body: some View {
        HStack(alignment: .center, spacing: 1.7) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Rectangle()
                    .fill(tint)
                    .frame(width: 2, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
