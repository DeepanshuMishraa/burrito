import AppKit
import AVFAudio
import Collaboration
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum SidebarSelection: Hashable {
    case all
    case favorites
    case trash
    case folder(UUID)
}

private enum NoteSort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case title

    var id: Self { self }
    var label: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .title: "Title"
        }
    }
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

    @State private var coordinator = AppCoordinator.live()
    @State private var permissions = PermissionAccess()
    @State private var calendarAccess = CalendarAccess()
    @State private var isSidebarVisible = true
    @State private var sidebarSelection: SidebarSelection? = .all
    @State private var selectedNoteID: UUID?
    @State private var searchText = ""
    @State private var sort: NoteSort = .newest
    @State private var recordingDestination: RecordingDestination?
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var confirmingEmptyTrash = false
    @AppStorage("permissionOnboardingCompleted") private var permissionOnboardingCompleted = false
    @FocusState private var searchFocused: Bool
    private let userProfile = MacUserProfile.current

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    private var visibleNotes: [Note] {
        let filtered = notes.filter { note in
            let isInSection = switch sidebarSelection ?? .all {
            case .all:
                note.deletedAt == nil
            case .favorites:
                note.deletedAt == nil && note.isFavorite
            case .trash:
                note.deletedAt != nil
            case .folder(let id):
                note.deletedAt == nil && note.folder?.id == id
            }
            let matchesSearch = searchText.isEmpty
                || note.title.localizedStandardContains(searchText)
                || note.markdownBody.localizedStandardContains(searchText)
                || Transcript.rendered(note.transcriptSegments).localizedStandardContains(searchText)
            return isInSection && matchesSearch
        }

        return filtered.sorted {
            switch sort {
            case .newest: $0.updatedAt > $1.updatedAt
            case .oldest: $0.updatedAt < $1.updatedAt
            case .title: $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
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
                PermissionGateView(permissions: permissions) {
                    permissionOnboardingCompleted = true
                }
            } else if let selectedNote {
                NoteDetailView(
                    note: selectedNote,
                    coordinator: coordinator,
                    fileStore: LocalRecordingFileStore(),
                    folders: folders,
                    exportAction: { exportMarkdown(selectedNote) },
                    backAction: { selectedNoteID = nil },
                    newRecordingAction: {
                        recordingDestination = .appendToNote(id: selectedNote.id)
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
        .sheet(item: $recordingDestination) { destination in
            RecordingSetupView(
                templates: templates,
                continuingNote: note(for: destination)
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
            if showingNewFolder {
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
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refresh()
                calendarAccess.refresh()
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .burritoFind)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .burritoExportMarkdown)) { _ in
            if let selectedNote { exportMarkdown(selectedNote) }
        }
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

            noteList
        }
        .animation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? nil
                : .easeInOut(duration: 0.2),
            value: isSidebarVisible
        )
        .background(BurritoTheme.canvas)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    isSidebarVisible = false
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(BurritoIconButtonStyle())
                .accessibilityLabel("Hide sidebar")
            }
            .frame(height: 52)
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                Text("⌘K")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

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
                        title: "Trash",
                        systemImage: "trash.fill",
                        count: notes.filter { $0.deletedAt != nil }.count,
                        isSelected: sidebarSelection == .trash
                    ) {
                        sidebarSelection = .trash
                    }

                    BurritoSectionLabel(title: "Folders")
                        .padding(.horizontal, 10)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                    ForEach(folders) { folder in
                        SidebarNavigationButton(
                            title: folder.name,
                            systemImage: "folder",
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

                    if sidebarSelection == .trash {
                        Button("Empty Trash", role: .destructive) {
                            confirmingEmptyTrash = true
                        }
                        .disabled(visibleNotes.isEmpty)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 8)
            }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button("New folder", systemImage: "folder.badge.plus") {
                        showingNewFolder = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(BurritoIconButtonStyle())
                    .accessibilityLabel("New folder")
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(BurritoIconButtonStyle())
                    .accessibilityLabel("Settings")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Rectangle()
                    .fill(BurritoTheme.softBorder)
                    .frame(height: 1)

                HStack(spacing: 10) {
                    Image(nsImage: userProfile.image ?? NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(userProfile.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
            }
            .foregroundStyle(.secondary)
        }
        .background(BurritoTheme.sidebar)
    }

    private var noteList: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if sidebarSelection == .all {
                        Text("Coming up")
                            .font(.system(size: 36, weight: .regular, design: .serif))
                            .padding(.bottom, 18)

                        CalendarCard(
                            calendarAccess: calendarAccess,
                            startRecording: { recordingDestination = .newNote },
                            openSettings: openCalendarSettings
                        )
                        .padding(.bottom, 30)
                    } else {
                        Text(sectionTitle)
                            .font(.system(size: 34, weight: .regular, design: .serif))
                            .padding(.bottom, 28)
                    }

                    if visibleNotes.isEmpty {
                        HomeEmptyState(
                            isTrash: sidebarSelection == .trash,
                            isSearching: !searchText.isEmpty
                        ) {
                            recordingDestination = .newNote
                        }
                    } else {
                        ForEach(noteDays, id: \.date) { group in
                            Text(group.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 20)
                                .padding(.bottom, 8)
                            ForEach(group.notes) { note in
                                Button {
                                    selectedNoteID = note.id
                                } label: {
                                    TimelineNoteRow(note: note)
                                }
                                .buttonStyle(.plain)
                                .draggable(note.id.uuidString)
                                .contextMenu {
                                    noteContextMenu(note)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.top, 72)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(NoteSort.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                Button("New recording", systemImage: "plus") {
                    recordingDestination = .newNote
                }
                .buttonStyle(BurritoActionButtonStyle(prominent: false))
            }
            .padding(14)
        }
        .overlay(alignment: .topLeading) {
            if !isSidebarVisible {
                Button {
                    isSidebarVisible = true
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(BurritoIconButtonStyle())
                .accessibilityLabel("Show sidebar")
                .padding(.leading, 100)
                .padding(.top, 14)
                .transition(.opacity)
            }
        }
        .background(BurritoTheme.canvas)
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
        case .trash: "Trash"
        case .folder(let id): folders.first(where: { $0.id == id })?.name ?? "Folder"
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
        } else {
            recordingDestination = selectedNote.map {
                .appendToNote(id: $0.id)
            } ?? .newNote
        }
    }

    private func note(for destination: RecordingDestination) -> Note? {
        guard case .appendToNote(let id) = destination else { return nil }
        return notes.first { $0.id == id }
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
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }

    private func exportMarkdown(_ note: Note) {
        let panel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        panel.nameFieldStringValue = "\(note.title).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try note.markdownBody.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

private struct PermissionGateView: View {
    @Bindable var permissions: PermissionAccess
    let continueAction: () -> Void

    var body: some View {
        ZStack {
            BurritoTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                BurritoSectionLabel(title: "Permissions")
                VStack(alignment: .leading, spacing: 14) {
                    Text("Allow Burrito to listen\nand take notes")
                        .font(.system(size: 42, weight: .regular, design: .serif))
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
                    PermissionRow(
                        title: "Turn recordings into text",
                        subtitle: "Speech Recognition",
                        systemImage: "text.bubble",
                        state: permissions.speechRecognition,
                        openSettings: {
                            permissions.openSettings(for: .speechRecognition)
                        }
                    ) {
                        Task { await permissions.requestSpeechRecognition() }
                    }
                }
                .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(BurritoTheme.softBorder)
                }

                HStack {
                    Text(permissions.allGranted ? "Everything stays on this Mac." : "Grant all three permissions to continue.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Continue", systemImage: "arrow.right", action: continueAction)
                        .buttonStyle(BurritoActionButtonStyle(prominent: true))
                        .disabled(!permissions.allGranted)
                }
            }
            .padding(50)
            .frame(width: 820)
            .background(BurritoTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(BurritoTheme.softBorder)
            }
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
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(state == .granted ? BurritoTheme.accent : .secondary)
                .frame(width: 36, height: 36)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(state == .denied ? "Access denied — open System Settings to allow \(subtitle)." : subtitle)
                    .font(.caption)
                .foregroundStyle(state == .denied ? Color.red : Color.secondary.opacity(0.7))
            }
            Spacer()
            if state == .granted {
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(BurritoTheme.accent)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 18, height: 18)
                    Text("Allowed")
                }
                .font(.system(size: 13, weight: .medium))
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color(nsColor: .textBackgroundColor) : .primary)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                prominent ? Color.primary : BurritoTheme.controlFill,
                in: Capsule()
            )
            .overlay {
                if !prominent {
                    Capsule().stroke(BurritoTheme.softBorder)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.34)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct BurritoDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(Color.red.opacity(0.78), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.34)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct BurritoIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
            .background(BurritoTheme.controlFill, in: Circle())
            .overlay { Circle().stroke(BurritoTheme.softBorder) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.34)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct BurritoInlineButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
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
                    .font(.system(size: 11, weight: .medium))
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

private struct BurritoPopoverRow: View {
    let title: String
    let systemImage: String
    var isSelected = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            BurritoPopoverRowLabel(
                title: title,
                systemImage: systemImage,
                isSelected: isSelected,
                isHovered: isHovered
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

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? BurritoTheme.accent : .secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: .regular))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BurritoTheme.accent)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .background(
            isHovered ? BurritoTheme.controlFill : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
    }
}

private struct BurritoPopoverDivider: View {
    var body: some View {
        Rectangle()
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
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Task { @MainActor [weak self] in
                self?.hideIndicators()
            }
        }

        func hideIndicators() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                    scrollView.autohidesScrollers = true
                    return
                }
                ancestor = view.superview
            }
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
                .background(BurritoTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
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
                    .font(.system(size: 28, weight: .regular, design: .serif))
                Text("Give this collection a short, useful name.")
                    .foregroundStyle(.secondary)
            }
            TextField("Project conversations", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
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
                    .font(.system(size: 28, weight: .regular, design: .serif))
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
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SidebarNavigationButton: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? BurritoTheme.controlFill : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CalendarCard: View {
    let calendarAccess: CalendarAccess
    let startRecording: () -> Void
    let openSettings: () -> Void

    private var today: Date { .now }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(today.formatted(.dateTime.day()))
                    .font(.system(size: 38, weight: .regular, design: .serif))
                Text(today.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 13, weight: .semibold))
                Text(today.formatted(.dateTime.weekday(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            .padding(22)

            Rectangle()
                .fill(BurritoTheme.softBorder)
                .frame(width: 1)

            Group {
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
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting Calendar…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .authorized:
                    if calendarAccess.upcomingEvents.isEmpty {
                        CalendarConnectionState(
                            symbol: "calendar.badge.clock",
                            title: "No upcoming events",
                            detail: "Your next seven days are clear.",
                            buttonTitle: nil,
                            action: {}
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(calendarAccess.upcomingEvents) { event in
                                UpcomingEventRow(event: event, startRecording: startRecording)
                                if event.id != calendarAccess.upcomingEvents.last?.id {
                                    Rectangle()
                                        .fill(BurritoTheme.softBorder)
                                        .frame(height: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
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
            .frame(maxWidth: .infinity, minHeight: 188)
        }
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(BurritoTheme.softBorder)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct CalendarConnectionState: View {
    let symbol: String
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct UpcomingEventRow: View {
    let event: UpcomingCalendarEvent
    let startRecording: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.startDate, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                if !Calendar.current.isDateInToday(event.startDate) {
                    Text(event.startDate, format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 58, alignment: .trailing)

            Capsule()
                .fill(BurritoTheme.accent)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(event.isAllDay ? "All day · \(event.calendarName)" : event.calendarName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Record", systemImage: "waveform", action: startRecording)
                .buttonStyle(BurritoActionButtonStyle(prominent: false))
        }
        .frame(minHeight: 58)
    }
}

private struct TimelineNoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: note.processingStage == nil ? "doc.text" : "ellipsis")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(BurritoTheme.accent)
                    }
                }
                Text(note.processingStage?.rawValue ?? note.templateSnapshot.name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(note.updatedAt, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 58)
        .contentShape(Rectangle())
    }
}

private struct HomeEmptyState: View {
    let isTrash: Bool
    let isSearching: Bool
    let start: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isTrash ? "trash" : isSearching ? "magnifyingglass" : "waveform.badge.plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text(isTrash ? "Trash is empty" : isSearching ? "No matching notes" : "Nothing captured yet")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                Text(isSearching ? "Try a different search." : isTrash ? "Deleted notes will appear here." : "Start a recording and Burrito will organize it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !isTrash && !isSearching {
                Button("New recording", systemImage: "plus", action: start)
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
                    Circle()
                        .fill(BurritoTheme.accent)
                        .frame(width: 30, height: 30)
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("New recording")
                        .font(.system(size: 13, weight: .semibold))
                    Text("⌘N")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
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
            Image(systemName: isTrash ? "trash" : isSearching ? "magnifyingglass" : "note.text")
                .font(.system(size: 22, weight: .light))
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
                    RoundedRectangle(cornerRadius: 20)
                        .fill(BurritoTheme.accentSoft)
                        .frame(width: 86, height: 86)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(BurritoTheme.accent)
                }
                VStack(spacing: 8) {
                    Text("Capture it. Keep the good parts.")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Burrito records what you hear, then turns it into notes\nthat stay private on your Mac.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                Button("Start a recording", systemImage: "waveform", action: start)
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

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool

    private var excerpt: String {
        let body = note.markdownBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            return body.replacingOccurrences(of: "#", with: "")
        }
        return note.transcriptSegments.first?.text ?? "Recording ready for your notes."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(note.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(BurritoTheme.accent)
                        .accessibilityLabel("Favorite")
                }
            }
            Text(excerpt)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .lineSpacing(2)
            HStack(spacing: 6) {
                if let stage = note.processingStage {
                    ProgressView()
                        .controlSize(.mini)
                    Text(stage.rawValue)
                } else {
                    Text(note.updatedAt, style: .date)
                    Text("•")
                    Text(Duration.seconds(note.duration).formatted(.time(pattern: .minuteSecond)))
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            if let message = note.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            isSelected ? BurritoTheme.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: BurritoTheme.cardRadius)
        )
        .contentShape(RoundedRectangle(cornerRadius: BurritoTheme.cardRadius))
    }
}

private struct RecordingStatusView: View {
    let coordinator: AppCoordinator
    let stop: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("New recording")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    BurritoPill(
                        title: Date.now.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "calendar"
                    )
                    BurritoPill(title: "Local", systemImage: "lock")
                }
                .padding(.top, 14)
                Text("Write notes")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 30)
                LiveTranscriptView(text: coordinator.liveTranscript)
                    .padding(.top, 20)
                Spacer(minLength: 80)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 72)
            .padding(.bottom, 130)
            .frame(maxWidth: .infinity)

            HStack {
                RecordingControlButton(
                    isRecording: true,
                    elapsed: coordinator.elapsed,
                    systemLevel: coordinator.activity.system,
                    microphoneLevel: coordinator.activity.microphone,
                    action: stop
                )
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 22)
        }
        .background(BurritoTheme.canvas)
    }
}

private struct RecordingControlButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isRecording: Bool
    let elapsed: TimeInterval
    let systemLevel: Double
    let microphoneLevel: Double
    let action: () -> Void

    @State private var isHovered = false
    @State private var readyPulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    activeControl
                        .transition(.scale(scale: 0.72).combined(with: .opacity))
                } else {
                    readyControl
                        .transition(.scale(scale: 0.72).combined(with: .opacity))
                }
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1)
        .shadow(
            color: isRecording
                ? Color.red.opacity(isHovered ? 0.28 : 0.18)
                : Color.black.opacity(isHovered ? 0.16 : 0.10),
            radius: isHovered ? 16 : 11,
            y: isHovered ? 7 : 4
        )
        .animation(.smooth(duration: 0.18), value: isHovered)
        .animation(.spring(response: 0.36, dampingFraction: 0.76), value: isRecording)
        .onHover { isHovered = $0 }
        .onAppear {
            guard !reduceMotion else { return }
            readyPulse = true
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .help(isRecording ? "Stop recording" : "Continue recording")
        .accessibilityLabel(isRecording ? "Stop recording" : "Continue recording")
        .accessibilityValue(
            isRecording
                ? "Elapsed \(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))"
                : "Not recording"
        )
    }

    private var readyControl: some View {
        ZStack {
            Circle()
                .fill(BurritoTheme.accent.opacity(0.13))
                .frame(width: 58, height: 58)
                .scaleEffect(readyPulse ? 1.08 : 0.96)
                .opacity(readyPulse ? 0.25 : 0.68)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: readyPulse
                )

            Circle()
                .fill(BurritoTheme.raised)
                .frame(width: 54, height: 54)
                .overlay {
                    Circle().stroke(BurritoTheme.softBorder)
                }

            Circle()
                .fill(BurritoTheme.accentSoft.opacity(isHovered ? 1 : 0.72))
                .frame(width: 38, height: 38)

            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(BurritoTheme.accent)
                        .frame(
                            width: 2.5,
                            height: readyBarHeight(at: index)
                        )
                }
            }
        }
    }

    private var activeControl: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion
            )
        ) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12 + (audioEnergy * 0.12)))
                    .frame(width: 62, height: 62)
                    .scaleEffect(1 + (audioEnergy * 0.10))

                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(
                            index.isMultiple(of: 3)
                                ? BurritoTheme.accent
                                : Color.red.opacity(0.58)
                        )
                        .frame(
                            width: 2,
                            height: activeRayHeight(
                                at: index,
                                phase: phase
                            )
                        )
                        .offset(y: -29)
                        .rotationEffect(.degrees(Double(index) * 30))
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BurritoTheme.accent, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle().stroke(.white.opacity(0.18))
                    }

                RoundedRectangle(cornerRadius: 3)
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            }
            .animation(.smooth(duration: 0.12), value: audioEnergy)
        }
    }

    private var audioEnergy: Double {
        min(1, max(systemLevel, microphoneLevel))
    }

    private func readyBarHeight(at index: Int) -> CGFloat {
        let heights: [CGFloat] = [7, 12, 18, 12, 7]
        let pulseScale = readyPulse && !reduceMotion
            ? 1 + (CGFloat(index.isMultiple(of: 2) ? 0.10 : -0.08))
            : 1
        return heights[index] * pulseScale
    }

    private func activeRayHeight(at index: Int, phase: TimeInterval) -> CGFloat {
        let wave = (sin((phase * 5) + Double(index) * 0.82) + 1) / 2
        let motion = reduceMotion ? 0.5 : wave
        let sourceLevel = index.isMultiple(of: 2) ? systemLevel : microphoneLevel
        let level = max(audioEnergy * 0.65, sourceLevel)
        return 3 + CGFloat((level * 7) + (motion * level * 3))
    }
}

private struct LiveTranscriptView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(BurritoTheme.accent)
                    .frame(width: 7, height: 7)
                Text("Listening now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BurritoTheme.accent)
            }
            Text(text.isEmpty ? "Speak or play audio. Words will appear here." : text)
                .font(.system(size: 15))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .lineSpacing(5)
                .textSelection(.enabled)
                .contentTransition(.interpolate)
                .animation(.smooth(duration: 0.2), value: text)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(BurritoTheme.accent.opacity(0.28))
        }
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
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Private on this Mac")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(BurritoTheme.raised, in: Capsule())
        .overlay { Capsule().stroke(BurritoTheme.softBorder) }
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
        case .transcribing: "Checking the live text against the saved audio."
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
    let continuingNote: Note?
    let start: (RecordingOptions) -> Void

    @AppStorage("defaultTemplateID") private var defaultTemplateID = BuiltInTemplate.summary.rawValue
    @AppStorage("transcriptionLanguage") private var language = "en-US"
    @AppStorage("microphoneDefault") private var includesMicrophone = false
    @AppStorage("retainAudioDefault") private var retainsAudio = false
    @State private var templateID: UUID?
    @State private var showingTemplateDetails = false

    private var selectedTemplate: NoteTemplate? {
        templates.first { $0.id == templateID }
            ?? templates.first { $0.builtInID == defaultTemplateID }
            ?? templates.first
    }

    private var effectiveTemplate: TemplateSnapshot? {
        continuingNote?.templateSnapshot ?? selectedTemplate?.snapshot
    }

    private var effectiveLanguage: String {
        continuingNote?.languageIdentifier ?? language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(continuingNote == nil ? "New recording" : "Continue recording")
                        .font(.system(size: 32, weight: .regular, design: .serif))
                    Text(
                        continuingNote == nil
                            ? "How should Burrito shape these notes?"
                            : "New audio and transcript will be added to this note."
                    )
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(BurritoIconButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            if let continuingNote {
                VStack(alignment: .leading, spacing: 8) {
                    BurritoSectionLabel(title: "Extending")
                    Text(continuingNote.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(
                        "\(continuingNote.templateSnapshot.name) · \(continuingNote.languageIdentifier)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    BurritoSectionLabel(title: "Note style")
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(templates) { template in
                            TemplateChoiceCard(
                                template: template,
                                isSelected: selectedTemplate?.id == template.id
                            ) {
                                templateID = template.id
                            }
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                if continuingNote == nil {
                    VStack(alignment: .leading, spacing: 9) {
                        BurritoSectionLabel(title: "Language")
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 8),
                                count: 3
                            ),
                            spacing: 8
                        ) {
                            ForEach(languageOptions, id: \.identifier) { option in
                                BurritoChoiceButton(
                                    title: option.title,
                                    isSelected: language == option.identifier
                                ) {
                                    language = option.identifier
                                }
                            }
                        }
                    }
                    .padding(14)
                    Divider().padding(.leading, 12)
                }
                BurritoToggleRow(
                    title: "Include microphone",
                    subtitle: "Capture your voice as a separate track",
                    isOn: $includesMicrophone
                )
                Divider().padding(.leading, 12)
                BurritoToggleRow(
                    title: "Keep audio",
                    subtitle: "Retain recordings after transcription",
                    isOn: $retainsAudio
                )
            }
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))

            HStack {
                if continuingNote == nil {
                    Button("Template details", systemImage: "text.document") {
                        showingTemplateDetails = true
                    }
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
                }
                Spacer()
                Button("Start recording", systemImage: "waveform") {
                    guard let effectiveTemplate else { return }
                    start(
                        RecordingOptions(
                            template: effectiveTemplate,
                            languageIdentifier: effectiveLanguage,
                            includesMicrophone: includesMicrophone,
                            retainsAudio: retainsAudio
                        )
                    )
                }
                .buttonStyle(BurritoActionButtonStyle(prominent: true))
                .disabled(effectiveTemplate == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(BurritoTheme.paper)
        .onAppear {
            if templateID == nil {
                templateID = selectedTemplate?.id
            }
        }
        .sheet(isPresented: $showingTemplateDetails) {
            TemplateDetailsView(
                templates: templates,
                selectedTemplateID: $templateID
            )
        }
    }

    private var languageOptions: [(identifier: String, title: String)] {
        [
            ("en-US", "English US"),
            ("en-GB", "English UK"),
            ("hi-IN", "Hindi"),
            ("es-ES", "Spanish"),
            ("fr-FR", "French"),
            ("de-DE", "German"),
        ]
    }
}

private struct TemplateChoiceCard: View {
    let template: NoteTemplate
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 11) {
                Image(systemName: template.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? BurritoTheme.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected ? BurritoTheme.accentSoft : BurritoTheme.controlFill,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                Text(template.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    ZStack {
                        Circle().fill(BurritoTheme.accent)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
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
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
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
                    Circle()
                        .stroke(isSelected ? BurritoTheme.accent : BurritoTheme.softBorder, lineWidth: 1.5)
                    if isSelected {
                        Circle()
                            .fill(BurritoTheme.accent)
                            .padding(3)
                    }
                }
                .frame(width: 15, height: 15)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
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
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? BurritoTheme.accent.opacity(0.55) : BurritoTheme.softBorder)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BurritoToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? BurritoTheme.accent : BurritoTheme.controlFill)
                        .frame(width: 38, height: 22)
                    Circle()
                        .fill(isOn ? Color.white : Color.secondary)
                        .frame(width: 16, height: 16)
                        .padding(3)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct TemplateDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let templates: [NoteTemplate]
    @Binding var selectedTemplateID: UUID?

    @State private var showingEditor = false
    @State private var editingTemplateID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Template details")
                        .font(.system(size: 32, weight: .regular, design: .serif))
                    Text("Templates are instructions Burrito follows when it writes your note.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(BurritoActionButtonStyle(prominent: true))
            }
            .padding(28)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(templates) { template in
                        TemplatePromptCard(
                            template: template,
                            isSelected: selectedTemplateID == template.id,
                            select: { selectedTemplateID = template.id },
                            edit: template.isBuiltIn ? nil : {
                                editingTemplateID = template.id
                                showingEditor = true
                            }
                        )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            }

            HStack {
                Button("New template", systemImage: "plus") {
                    editingTemplateID = nil
                    showingEditor = true
                }
                .buttonStyle(BurritoActionButtonStyle(prominent: false))
                Spacer()
                Text("\(templates.count) templates")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(22)
        }
        .frame(width: 720, height: 620)
        .background(BurritoTheme.paper)
        .sheet(isPresented: $showingEditor) {
            TemplateEditorView(
                template: templates.first { $0.id == editingTemplateID }
            ) { name, symbol, instructions in
                if let template = templates.first(where: { $0.id == editingTemplateID }),
                   !template.isBuiltIn {
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
    }
}

private struct TemplatePromptCard: View {
    let template: NoteTemplate
    let isSelected: Bool
    let select: () -> Void
    let edit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: template.symbol)
                    .foregroundStyle(isSelected ? BurritoTheme.accent : .secondary)
                    .frame(width: 34, height: 34)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(template.isBuiltIn ? "Built in" : "Custom")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let edit {
                    Button("Edit", action: edit)
                        .buttonStyle(BurritoActionButtonStyle(prominent: false))
                }
                Button(isSelected ? "Selected" : "Use template", action: select)
                    .buttonStyle(BurritoActionButtonStyle(prominent: isSelected))
            }
            Text(template.instructions)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding(18)
        .background(BurritoTheme.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? BurritoTheme.accent.opacity(0.55) : BurritoTheme.softBorder)
        }
    }
}

private struct MarkdownNoteContent: View {
    let markdown: String

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
                .font(.system(size: 15))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(5)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Circle()
                            .fill(BurritoTheme.accent)
                            .frame(width: 5, height: 5)
                        inlineText(item)
                            .font(.system(size: 15))
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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BurritoTheme.accent)
                            .frame(width: 21, height: 21)
                            .background(BurritoTheme.accentSoft, in: Circle())
                        inlineText(item)
                            .font(.system(size: 15))
                            .lineSpacing(4)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(BurritoTheme.accent)
                    .frame(width: 3)
                inlineText(text)
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 14)
            .background(BurritoTheme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.82))
                    .textSelection(.enabled)
                    .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
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
            .system(size: 28, weight: .semibold, design: .serif)
        case 2:
            .system(size: 21, weight: .semibold, design: .serif)
        default:
            .system(size: 16, weight: .semibold)
        }
    }
}

private struct NoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Bindable var note: Note
    let coordinator: AppCoordinator
    let fileStore: LocalRecordingFileStore
    let folders: [Folder]
    let exportAction: () -> Void
    let backAction: () -> Void
    let newRecordingAction: () -> Void

    @State private var selectedTab = 0
    @State private var isEditingMarkdown = false
    @State private var showingFolderPopover = false
    @State private var showingMorePopover = false
    @State private var confirmingRegeneration = false
    @State private var didCopyNotes = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var player: AVAudioPlayer?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Untitled note", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    BurritoPill(
                        title: note.updatedAt.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "calendar"
                    )
                    BurritoPill(
                        title: Duration.seconds(note.duration).formatted(.time(pattern: .minuteSecond)),
                        systemImage: "clock"
                    )
                    BurritoPill(
                        title: note.templateSnapshot.name,
                        systemImage: note.templateSnapshot.symbol
                    )
                    BurritoInlineButton(
                        title: note.folder?.name ?? "Add to folder",
                        systemImage: "folder"
                    ) {
                        showingFolderPopover.toggle()
                    }
                    .popover(
                        isPresented: $showingFolderPopover,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
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
                    BurritoInlineButton(
                        title: "Generate again",
                        systemImage: "arrow.clockwise"
                    ) {
                        requestRegeneration()
                    }
                    .disabled(note.transcriptSegments.isEmpty || note.processingStage != nil)
                }

                HStack(spacing: 20) {
                    EditorTabButton(title: "Notes", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    EditorTabButton(title: "Transcript", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    Spacer()
                    if selectedTab == 0, !isRecordingThisNote {
                        BurritoInlineButton(
                            title: isEditingMarkdown ? "Done" : "Edit",
                            systemImage: isEditingMarkdown ? "checkmark" : "pencil"
                        ) {
                            withAnimation(.smooth(duration: 0.2)) {
                                isEditingMarkdown.toggle()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 72)
            .frame(maxWidth: .infinity)

            if isRecordingThisNote {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !note.markdownBody.isEmpty {
                            MarkdownNoteContent(markdown: note.markdownBody)
                        }
                        LiveTranscriptView(text: coordinator.liveTranscript)
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 28)
                    .hidesEnclosingScrollIndicators()
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
            } else if selectedTab == 0 {
                if isEditingMarkdown {
                    TextEditor(text: notesBinding)
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .lineSpacing(5)
                        .frame(maxWidth: 820)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                } else {
                    ScrollView {
                        MarkdownNoteContent(markdown: note.markdownBody)
                            .frame(maxWidth: 820, alignment: .leading)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 30)
                            .hidesEnclosingScrollIndicators()
                    }
                    .scrollIndicators(.hidden)
                    .transition(.opacity)
                }
            } else {
                TranscriptEditor(note: note)
            }
        }
        .background(BurritoTheme.canvas)
        .navigationTitle("")
        .overlay(alignment: .top) {
            HStack {
                Button("Back to notes", systemImage: "chevron.left") {
                    backAction()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(BurritoIconButtonStyle())
                .accessibilityHint("Returns to the notes library")
                Spacer()
                Button {
                    copyMarkdown()
                } label: {
                    Image(systemName: didCopyNotes ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(didCopyNotes ? Color.green : Color.primary)
                }
                .buttonStyle(BurritoIconButtonStyle())
                .accessibilityLabel(didCopyNotes ? "Notes copied" : "Copy notes")
                .help(didCopyNotes ? "Copied" : "Copy notes")
                Button {
                    exportAction()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(BurritoIconButtonStyle())
                .accessibilityLabel("Export Markdown")
                .help("Export Markdown")
                Button {
                    showingMorePopover.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                }
                .buttonStyle(BurritoIconButtonStyle())
                .accessibilityLabel("More actions")
                .popover(
                    isPresented: $showingMorePopover,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    BurritoPopoverPanel {
                        ShareLink(item: note.markdownBody) {
                            BurritoPopoverRowLabel(
                                title: "Share",
                                systemImage: "paperplane"
                            )
                        }
                        .buttonStyle(.plain)
                        if let path = note.systemAudioRelativePath {
                            BurritoPopoverDivider()
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
            }
            .padding(14)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if isRecordingThisNote {
                    HStack {
                        RecordingControlButton(
                            isRecording: true,
                            elapsed: coordinator.elapsed,
                            systemLevel: coordinator.activity.system,
                            microphoneLevel: coordinator.activity.microphone
                        ) {
                            Task { await coordinator.stop(context: modelContext) }
                        }
                        Spacer()
                    }
                } else if let stage = note.processingStage {
                    ProcessingRail(
                        stage: stage,
                        isContinuation: !note.markdownBody.isEmpty
                    )
                } else {
                    if note.notesMayBeOutdated {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
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
                        .background(BurritoTheme.accentSoft, in: Capsule())
                    }

                    HStack {
                        RecordingControlButton(
                            isRecording: false,
                            elapsed: 0,
                            systemLevel: 0,
                            microphoneLevel: 0,
                            action: newRecordingAction
                        )
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 22)
        }
        .overlay {
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
        NSPasteboard.general.setString(note.markdownBody, forType: .string)
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
    let title: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Capsule()
                    .fill(isSelected ? BurritoTheme.accent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 32, weight: .regular, design: .serif))
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
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(BurritoTheme.softBorder)
                    }
            }

            VStack(alignment: .leading, spacing: 9) {
                BurritoSectionLabel(title: "Symbol")
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .foregroundStyle(BurritoTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(BurritoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                    TextField("SF Symbol name", text: $symbol)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(BurritoTheme.softBorder)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                BurritoSectionLabel(title: "Instructions")
                TextEditor(text: $instructions)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 190)
                    .background(BurritoTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
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

private struct TranscriptEditor: View {
    @Bindable var note: Note
    @State private var hoveredSegmentID: UUID?

    var body: some View {
        ScrollView {
            if note.transcriptSegments.isEmpty {
                VStack(spacing: 14) {
                    TranscriptSignalMark(tint: BurritoTheme.accent)
                        .frame(width: 34, height: 28)
                    VStack(spacing: 4) {
                        Text("The tape is quiet")
                            .font(.system(size: 18, design: .serif))
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
                                .font(.system(size: 15, weight: .medium, design: .serif))
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            sourceKey(title: "Computer", tint: BurritoTheme.accent)
                            sourceKey(title: "You", tint: BurritoTheme.sage)
                        }
                        Text("\(note.transcriptSegments.count) passages")
                            .font(.system(size: 10, weight: .medium))
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
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                                    Text(sourceTitle(for: segment.source))
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(0.5)
                                        .textCase(.uppercase)
                                        .foregroundStyle(sourceTint(for: segment.source))
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
                                hoveredSegmentID == segment.id ? 0.055 : 0
                            ),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
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
    }

    private func sourceKey(title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(tint)
                .frame(width: 9, height: 3)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private func sourceTitle(for source: AudioSource) -> String {
        switch source {
        case .system: "Computer"
        case .microphone: "You"
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
}

private struct TranscriptSignalMark: View {
    let tint: Color
    private let heights: [CGFloat] = [5, 11, 17, 9, 14, 6]

    var body: some View {
        HStack(alignment: .center, spacing: 1.7) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(tint)
                    .frame(width: 2, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
