import SwiftUI

/// d253: the Chart Room reading window — a `NavigationSplitView` gives
/// sidebar + scrollable detail BUILT IN, with zero hand-coordination
/// between them (unlike the terminal Chart Room's curses app, or the
/// rejected two-tmux-pane hybrid option, which both have to hand-build
/// that coordination). Content lives in its own `Window` scene
/// (`StokeholdApp.swift`), not the `MenuBarExtra` popover — a real reading
/// surface doesn't belong squeezed into a transient dropdown.
///
/// d298: a PINNED, synthetic "Docket" row lives above the presentations
/// list — Dan's ask ("just add to the docket and it shows up on my
/// list"). Its content is `console.needs_dan_items()` (the function that
/// actually renders the console's own Needs-Dan section — verified by
/// reading render_console() directly, NOT bosun.current_needs_dan_items,
/// which is a differently-scoped function feeding the supervisor prompt,
/// not this display), consumed via the EXISTING FleetConsole python
/// bridge — `FleetSnapshot.needsDan` already carries exactly this signal
/// today (feeding `FleetSummaryView`'s dropdown row), so no new
/// subprocess call or python script was needed for this feature at all.
///
/// d300: the feed is append-only, so a REVIEWED doc used to look
/// identical to an unreviewed one in the sidebar — implying action that
/// was already done. Active (non-archived) files render below the pinned
/// Docket row; archiving (a per-item, Dan-only DECISION — see
/// `ArchiveStore`'s doc comment) moves a file into a collapsible
/// "Archived" section at the bottom, never deleted, always reachable.
struct ChartRoomView: View {
    @ObservedObject var model: PresentationsModel
    /// Sourced from `BoilerModel.fleet?.needsDan` — the SAME FleetConsole
    /// poll the menubar dropdown's Fleet section already reads (5s
    /// cadence), not a second independent subprocess-polling loop. Two
    /// pollers hitting the same python subprocess on two different timers
    /// would risk exactly the "one signal, many DERIVATIONS" bug class
    /// this feature is explicitly built to avoid, even sourced from the
    /// same underlying function — one poll loop, one in-memory value, two
    /// UI surfaces reading it.
    let needsDanItems: [String]

    private static let docketTag = "__docket__"
    @State private var selectedTag: String?
    @State private var archivedSectionExpanded = false

    private var activeFiles: [PresentationFile] {
        model.files.filter { !ArchiveStore.isArchived($0) }
    }

    private var archivedFiles: [PresentationFile] {
        model.files.filter { ArchiveStore.isArchived($0) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 700, minHeight: 450)
        // Bug fix: without this, openWindow(id:) creates the window but
        // never brings it (or the app) forward — see
        // ChartRoomWindowActivator's own doc comment for the full story.
        .background(ChartRoomWindowActivator())
    }

    private var sidebar: some View {
        List(selection: $selectedTag) {
            // Pinned unconditionally — a Dan-facing "what needs me" surface
            // must be visible even with zero presentations in the feed yet.
            docketRow
            if !activeFiles.isEmpty {
                Section {
                    ForEach(activeFiles) { file in
                        fileRow(file, archived: false)
                    }
                }
            }
            if !archivedFiles.isEmpty {
                DisclosureGroup(isExpanded: $archivedSectionExpanded) {
                    ForEach(archivedFiles) { file in
                        fileRow(file, archived: true)
                    }
                } label: {
                    Text("Archived (\(archivedFiles.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: selectedTag) { newTag in
            guard let newTag, newTag != Self.docketTag,
                  let file = model.files.first(where: { $0.id == newTag }) else { return }
            model.select(file)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
    }

    private var docketRow: some View {
        HStack {
            Image(systemName: "list.bullet.clipboard")
            Text("Docket")
            Spacer()
            if !needsDanItems.isEmpty {
                Text("\(needsDanItems.count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.orange))
            }
        }
        .tag(Self.docketTag)
    }

    private func fileRow(_ file: PresentationFile, archived: Bool) -> some View {
        HStack {
            Text(file.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(archived ? .secondary : .primary)
            Spacer()
            if !archived, !SeenStore.isSeen(file) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            }
        }
        .tag(file.id)
        .contextMenu {
            Button(archived ? "Unarchive" : "Archive") {
                model.setArchived(file, archived: !archived)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No presentations yet")
                .foregroundStyle(.secondary)
            Text("skybridge present <file>")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        if selectedTag == Self.docketTag {
            docketDetail
        } else if let tag = selectedTag, let file = model.files.first(where: { $0.id == tag }) {
            fileDetail(file)
        } else if let file = model.selected {
            // Initial state: PresentationsModel auto-selects the newest
            // ACTIVE file before the sidebar's own selection binding has
            // fired once — falls through to it so the detail pane isn't
            // blank on first launch.
            fileDetail(file)
        } else {
            emptyState
        }
    }

    private var docketDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if needsDanItems.isEmpty {
                    Text("Nothing open for Dan right now.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    // d298: needs-dan items are already-formatted display
                    // strings from console.needs_dan_items() itself (e.g.
                    // "d298 — CHART ROOM ... · action: decide or approve"),
                    // not structured data — a plain native List of rows is
                    // the natural fit, not markdown. Each item is already
                    // exactly the ONE line console.py itself renders under
                    // "Needs-Dan"; reformatting it into markdown just to
                    // feed MarkdownBodyView's block-parser would be
                    // re-deriving presentation from presentation for no
                    // benefit — there's no heading/list/table structure
                    // here to gain from that machinery.
                    ForEach(Array(needsDanItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.orange)
                                .padding(.top, 6)
                            Text(item)
                                // d303: docket rows carry docket ids, commit
                                // SHAs, URLs — same copy need as the reader.
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Docket — Needs Dan")
    }

    private func fileDetail(_ file: PresentationFile) -> some View {
        let isArchived = ArchiveStore.isArchived(file)
        return Group {
            if file.isHTML {
                HTMLPreviewView(url: file.url)
            } else {
                ScrollView {
                    contentBody(for: file)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(file.displayName)
        .toolbar {
            ToolbarItem {
                Button {
                    model.setArchived(file, archived: !isArchived)
                } label: {
                    Label(isArchived ? "Unarchive" : "Archive", systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
                }
            }
        }
    }

    @ViewBuilder
    private func contentBody(for file: PresentationFile) -> some View {
        let text = (try? String(contentsOf: file.url, encoding: .utf8)) ?? "(unreadable file)"
        if file.isMarkdown {
            MarkdownBodyView(text: text)
        } else {
            // d303: MarkdownBodyView owns its own .textSelection internally;
            // this non-markdown fallback needs the same modifier directly,
            // or a raw log/text file would be the one thing in the reader
            // Dan couldn't copy from.
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
