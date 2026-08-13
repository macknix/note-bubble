import SwiftUI

/// Which board you are on, and the way to every other one.
///
/// It is the first thing in the bar's second row, ahead of the breadcrumb, because
/// it is the outermost part of the same answer: workspace, then the trail of
/// bubbles inside it. Clicking opens the list; the dots beside it are the swipe's
/// affordance — see `WorkspaceDots`.
struct WorkspaceChip: View {
    @ObservedObject var store: BubbleStore
    @ObservedObject var panelState: PanelState
    /// Deleting a board with notes on it asks first, and the sheet has to be drawn
    /// over the whole panel — so the decision is handed up to `RootView`.
    let onRequestDelete: (Workspace) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    /// The board **on screen**, which during a drag may be one being previewed
    /// rather than the one the store is on. The chip names what you can see.
    private var workspace: Workspace {
        panelState.previewWorkspace.flatMap { id in store.workspaces.first { $0.id == id } }
            ?? store.currentWorkspace
    }
    private var isRenaming: Bool { store.renamingWorkspaceID == workspace.id }

    var body: some View {
        Group {
            if isRenaming {
                nameField
            } else {
                menu
            }
        }
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
    }

    // MARK: - Reading

    private var menu: some View {
        Menu {
            Section("Workspaces") {
                ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, item in
                    Button {
                        withAnimation(Motion.reflow) { store.selectWorkspace(at: index) }
                    } label: {
                        // A tick would be the native idiom, but a SwiftUI menu has no
                        // checked state — the marker does the same job.
                        Text(index == store.currentIndex ? "● \(item.displayName)" : item.displayName)
                    }
                }
            }
            Divider()
            Button("New workspace") { withAnimation(Motion.reflow) { _ = store.addWorkspace() } }
            Button("Rename “\(workspace.displayName)”") { store.renamingWorkspaceID = workspace.id }
            if store.hasMultipleWorkspaces {
                Divider()
                Button("Delete “\(workspace.displayName)”", role: .destructive) {
                    onRequestDelete(workspace)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.55)
                Text(workspace.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Long board names must not push the breadcrumb or the dots off
                    // the row — the bar's width budget is the tightest thing here.
                    .frame(maxWidth: 120, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .black))
                    .opacity(0.45)
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(.white.opacity(0.09))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .allowsHitTesting(false)
            }
            // Same trap as the bar buttons: without this only the glyphs and glyph
            // strokes are clickable, since the capsule behind them takes no hits.
            .contentShape(Capsule())
        }
        // `.button` + `.plain` is the combination that draws the label as written.
        // `.borderlessButton` throws it away and renders its own text — the chip
        // came out unstyled, at the wrong size, with no capsule behind it.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Workspace — two-finger swipe to switch")
    }

    // MARK: - Naming

    /// Written on commit rather than per keystroke, unlike a note.
    ///
    /// A note's text *is* its content and there is nothing to lose by writing it
    /// through; a board's name is a label with a fallback, and live-writing it would
    /// flicker the chip through "Untitled" the moment you cleared the field to
    /// retype it.
    private var nameField: some View {
        TextField("Name this workspace", text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(width: 130)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(.white.opacity(0.16))
                    .overlay(Capsule().strokeBorder(BarStyle.candyPink.opacity(0.6), lineWidth: 1))
            }
            .onAppear {
                draft = workspace.name
                focused = true
            }
            .onSubmit(commit)
            .onKeyPress(keys: [.escape]) { _ in
                store.renamingWorkspaceID = nil
                return .handled
            }
            // Clicking away is the other way to finish, exactly as it is for a tile.
            .onChange(of: focused) { _, hasFocus in
                if !hasFocus { commit() }
            }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // An emptied name leaves the old one alone — and if the board was never
        // named or written in, dropping the rename discards it outright.
        if !trimmed.isEmpty { store.renameWorkspace(workspace.id, to: trimmed) }
        store.renamingWorkspaceID = nil
    }
}
