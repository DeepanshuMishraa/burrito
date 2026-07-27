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
    @State private var showingRecordingSetup = false
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
            } else if coordinator.captureState.isRecording {
                RecordingStatusView(coordinator: coordinator) {
                    Task { await coordinator.stop(context: modelContext) }
                }
            } else if let selectedNote {
                NoteDetailView(
                    note: selectedNote,
                    coordinator: coordinator,
                    fileStore: LocalRecordingFileStore(),
                    folders: folders,
                    exportAction: { exportMarkdown(selectedNote) },
                    backAction: { selectedNoteID = nil },
                    newRecordingAction: { showingRecordingSetup = true }
                )
            } else {
                home
            }
        }
        .frame(minWidth: 1_020, minHeight: 640)
        .tint(BurritoTheme.accent)
        .sheet(isPresented: $showingRecordingSetup) {
            RecordingSetupView(templates: templates) { options in
                showingRecordingSetup = false
                Task {
                    await coordinator.start(options: options, context: modelContext)
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
            showingRecordingSetup = true
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
                            startRecording: { showingRecordingSetup = true },
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
                            showingRecordingSetup = true
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
                    showingRecordingSetup = true
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
            showingRecordingSetup = true
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
                Spacer()
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 72)
            .padding(.bottom, 130)
            .frame(maxWidth: .infinity)

            ListeningRail(
                elapsed: coordinator.elapsed,
                systemLevel: coordinator.activity.system,
                microphoneLevel: coordinator.activity.microphone,
                stop: stop
            )
            .padding(.horizontal, 40)
            .padding(.bottom, 22)
        }
        .background(BurritoTheme.canvas)
    }
}

private struct ListeningRail: View {
    let elapsed: TimeInterval
    let systemLevel: Double
    let microphoneLevel: Double
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(BurritoTheme.accent)
                            .frame(
                                width: 4,
                                height: 10 + CGFloat(index % 3) * 6
                                    + CGFloat(max(systemLevel, microphoneLevel) * 8)
                            )
                    }
                }
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.system(size: 13, design: .monospaced))
                    .monospacedDigit()
                Button("Stop", systemImage: "stop.fill", action: stop)
                    .labelStyle(.iconOnly)
                    .buttonStyle(BurritoIconButtonStyle())
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(BurritoTheme.raised, in: Capsule())
            .overlay { Capsule().stroke(BurritoTheme.softBorder) }

            HStack {
                Text("Listening to system audio")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Transcribes after stop", systemImage: "text.document")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .frame(height: 58)
            .background(BurritoTheme.raised, in: Capsule())
            .overlay { Capsule().stroke(BurritoTheme.softBorder) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording")
        .accessibilityValue(
            Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond))
        )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("New recording")
                        .font(.system(size: 32, weight: .regular, design: .serif))
                    Text("How should Burrito shape these notes?")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(BurritoIconButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

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

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    BurritoSectionLabel(title: "Language")
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
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
                Button("Template details", systemImage: "text.document") {
                    showingTemplateDetails = true
                }
                .buttonStyle(BurritoActionButtonStyle(prominent: false))
                Spacer()
                Button("Start recording", systemImage: "waveform") {
                    guard let selectedTemplate else { return }
                    start(
                        RecordingOptions(
                            template: selectedTemplate.snapshot,
                            languageIdentifier: language,
                            includesMicrophone: includesMicrophone,
                            retainsAudio: retainsAudio
                        )
                    )
                }
                .buttonStyle(BurritoActionButtonStyle(prominent: true))
                .disabled(selectedTemplate == nil)
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
    @State private var confirmingRegeneration = false
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
                    Menu {
                        Button("No Folder") { note.folder = nil }
                        Divider()
                        ForEach(folders) { folder in
                            Button {
                                note.folder = folder
                            } label: {
                                if note.folder?.id == folder.id {
                                    Label(folder.name, systemImage: "checkmark")
                                } else {
                                    Text(folder.name)
                                }
                            }
                        }
                    } label: {
                        Label(note.folder?.name ?? "Add to folder", systemImage: "folder")
                    }
                    .menuStyle(.borderlessButton)
                    Button("Generate again", systemImage: "arrow.clockwise") {
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
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 72)
            .frame(maxWidth: .infinity)

            if let stage = note.processingStage {
                ProcessingView(stage: stage)
            } else if selectedTab == 0 {
                TextEditor(text: notesBinding)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .lineSpacing(5)
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
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
                Button("Favorite", systemImage: note.isFavorite ? "star.fill" : "star") {
                    note.isFavorite.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(BurritoIconButtonStyle())
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Copy Markdown", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.markdownBody, forType: .string)
                    }
                    Button("Export Markdown…", systemImage: "square.and.arrow.up") {
                        exportAction()
                    }
                    ShareLink(item: note.markdownBody) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    if let path = note.systemAudioRelativePath {
                        Button("Play System Audio", systemImage: "play.fill") {
                            play(fileStore.url(forRelativePath: path))
                        }
                    }
                    if let path = note.microphoneAudioRelativePath {
                        Button("Play Microphone Audio", systemImage: "mic.fill") {
                            play(fileStore.url(forRelativePath: path))
                        }
                    }
                    if player?.isPlaying == true {
                        Button("Stop Audio", systemImage: "stop.fill") {
                            player?.stop()
                        }
                    }
                }
            }
            .padding(14)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
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

                ReadyRail(
                    hasAudio: note.systemAudioRelativePath != nil || note.microphoneAudioRelativePath != nil,
                    newRecording: newRecordingAction,
                    copy: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.markdownBody, forType: .string)
                    },
                    export: exportAction
                )
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

private struct ReadyRail: View {
    let hasAudio: Bool
    let newRecording: () -> Void
    let copy: () -> Void
    let export: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: newRecording) {
                HStack(spacing: 9) {
                    Image(systemName: "waveform")
                        .foregroundStyle(BurritoTheme.accent)
                    Text("New recording")
                }
                .padding(.horizontal, 18)
                .frame(height: 58)
            }
            .buttonStyle(.plain)
            .background(BurritoTheme.raised, in: Capsule())
            .overlay { Capsule().stroke(BurritoTheme.softBorder) }

            HStack(spacing: 16) {
                Label(
                    hasAudio ? "Audio kept locally" : "Transcript saved locally",
                    systemImage: hasAudio ? "waveform" : "lock"
                )
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                Spacer()
                Button("Copy notes", systemImage: "doc.on.doc", action: copy)
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
                Button("Export", systemImage: "square.and.arrow.up", action: export)
                    .buttonStyle(BurritoActionButtonStyle(prominent: false))
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(BurritoTheme.raised, in: Capsule())
            .overlay { Capsule().stroke(BurritoTheme.softBorder) }
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

private struct ProcessingView: View {
    let stage: ProcessingStage

    private var stageIndex: Int {
        ProcessingStage.allCases.firstIndex(of: stage) ?? 0
    }

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(BurritoTheme.accentSoft)
                    .frame(width: 76, height: 76)
                Image(systemName: "text.document")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(BurritoTheme.accent)
            }
            VStack(spacing: 6) {
                Text(stage.rawValue)
                    .font(.system(size: 24, weight: .semibold))
                Text("Working privately on this Mac.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                ForEach(Array(ProcessingStage.allCases.enumerated()), id: \.element) { index, value in
                    VStack(spacing: 7) {
                        Capsule()
                            .fill(index <= stageIndex ? BurritoTheme.accent : BurritoTheme.controlFill)
                            .frame(width: 58, height: 4)
                        Text(shortName(for: value))
                            .font(.caption2)
                            .foregroundStyle(index == stageIndex ? .primary : .tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortName(for stage: ProcessingStage) -> String {
        switch stage {
        case .preparingAudio: "Prepare"
        case .transcribing: "Transcribe"
        case .organizing: "Organize"
        case .generatingNotes: "Write"
        }
    }
}

private struct TranscriptEditor: View {
    @Bindable var note: Note

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(note.transcriptSegments) { segment in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(Duration.seconds(segment.startTime).formatted(.time(pattern: .minuteSecond)))
                                .monospacedDigit()
                            Text(segment.source.rawValue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(BurritoTheme.controlFill, in: Capsule())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .trailing)

                        TextField("Transcript segment", text: binding(for: segment.id), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .lineLimit(1...8)
                    }
                    .padding(.vertical, 14)
                    if segment.id != note.transcriptSegments.last?.id {
                        Divider().padding(.leading, 108)
                    }
                }
            }
            .frame(maxWidth: BurritoTheme.editorWidth)
            .padding(.horizontal, 30)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
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
