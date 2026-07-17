import AppKit
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
    /// Sourced from `BoilerModel.fleet?.docketRows` — the SAME FleetConsole
    /// poll the menubar dropdown's Fleet section already reads (5s
    /// cadence), not a second independent subprocess-polling loop. Two
    /// pollers hitting the same python subprocess on two different timers
    /// would risk exactly the "one signal, many DERIVATIONS" bug class
    /// this feature is explicitly built to avoid, even sourced from the
    /// same underlying function — one poll loop, one in-memory value, two
    /// UI surfaces reading it. Each row already carries its own `needsDan`
    /// tag (computed server-side against bosun's canonical classifier, see
    /// `DocketRow`'s doc comment) — the Dan/All filter below is a pure
    /// client-side toggle over ONE list, not two separately-polled ones.
    let docketRows: [DocketRow]

    private static let docketTag = "__docket__"
    @State private var selectedTag: String?
    @State private var archivedSectionExpanded = false
    /// d298 rework: default Dan-only, matching the panel's original pinned
    /// behavior — "All" is an opt-in broader view, not the default noise.
    @State private var showAllDocket = false
    /// d355: which docket rows are tap-expanded to full text. Collapsed by
    /// default (single-line truncated, matching the panel's original
    /// density); tap toggles a row in/out, independent of d336's link-out
    /// tap target (the icon), so expanding and opening-a-file never fight
    /// on the same gesture.
    @State private var expandedDocketRowIDs: Set<String> = []
    @State private var hoveredFileTagRowID: String?
    @State private var hoveredLinearID: String?

    private var visibleDocketRows: [DocketRow] {
        showAllDocket ? docketRows : docketRows.filter(\.needsDan)
    }

    private var needsDanCount: Int {
        docketRows.filter(\.needsDan).count
    }

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
            if needsDanCount > 0 {
                Text("\(needsDanCount)")
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
            Text(sidebarLabel(for: file))
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

    // d346: Dan hit two generations of one doc rendering as the IDENTICAL
    // sidebar label (the epoch-prefix strip collapses "1784224462-d294-..."
    // and a later "d294-..." to the same displayName) — read the stale one
    // twice, unable to tell them apart. Defense-in-depth alongside the
    // write-side warn in `skybridge present` (skybridge/presentations.py):
    // this catches a collision regardless of how it got on disk. Checked
    // against the FULL file list (not just the active or archived subset),
    // since a collision between one of each is exactly as confusing.
    private static let sidebarLabelDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private func sidebarLabel(for file: PresentationFile) -> String {
        let collides = model.files.contains { $0.id != file.id && $0.displayName == file.displayName }
        guard collides else { return file.displayName }
        return "\(file.displayName) · \(Self.sidebarLabelDateFormatter.string(from: file.mtime))"
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
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $showAllDocket) {
                Text("Dan").tag(false)
                Text("All").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if visibleDocketRows.isEmpty {
                Text(showAllDocket ? "Docket is empty." : "Nothing open for Dan right now.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                // d298 rework: shaped like the docket itself — id | priority
                // | text | Linear mapping | owner, single-line rows — not
                // the flat "id — text" strings the panel started with.
                // Structured `DocketRow`s from the FleetConsole bridge, not
                // a re-parse of console's formatted display strings.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleDocketRows) { row in
                            docketRowView(row)
                            Divider()
                        }
                    }
                }
            }
        }
        .navigationTitle("Docket")
    }

    /// Module-internal (not `private`) so `PreviewRenderer` can compose a
    /// standalone docket-panel screenshot from the REAL row view —
    /// `NavigationSplitView`, segmented `Picker`, and `LazyVStack` all
    /// refuse to lay out under an offscreen `ImageRenderer`, so design
    /// renders rebuild the panel eagerly from these rows instead. Outside
    /// a live hierarchy the row renders in its `@State` defaults
    /// (collapsed, unhovered).
    func docketRowView(_ row: DocketRow) -> some View {
        // d336: a row whose text names a presentation file becomes
        // clickable — one tap from "what needs me" to "the thing to read".
        // Dumb filename-substring match (DocketFileLinking), no new schema.
        let linkedFile = DocketFileLinking.referencedFile(in: row.text, files: model.files)
        // d355: single-line truncation gave no way to read a long row's
        // full text — it just overflowed off the right edge. Tap toggles
        // this row's own expand state (vertical growth, wraps, pushes
        // rows below down); the link-out affordance is its own Button so
        // it keeps its own tap target instead of fighting the row's.
        let isExpanded = expandedDocketRowIDs.contains(row.id)
        return HStack(alignment: .top, spacing: 8) {
            Button {
                toggleDocketRow(row.id)
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
            priorityGlyph(for: row.pri)
            Text(row.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            docketText(row.text, isExpanded: isExpanded)
            Spacer(minLength: 8)
            if let linkedFile {
                fileTag(for: linkedFile, rowID: row.id)
            }
            if !row.linearId.isEmpty {
                linearTag(row.linearId)
            }
            if !row.owner.isEmpty {
                Text(displayOwner(row.owner))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleDocketRow(row.id)
        }
    }

    @ViewBuilder
    private func docketText(_ text: String, isExpanded: Bool) -> some View {
        // d303 + d355: collapsed text must still expand when clicked; enabled
        // selection wins the click on macOS, so copy/selection lives in the
        // expanded reading state.
        if isExpanded {
            Text(text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: false)
                .textSelection(.disabled)
        }
    }

    private func toggleDocketRow(_ rowID: String) {
        if expandedDocketRowIDs.contains(rowID) {
            expandedDocketRowIDs.remove(rowID)
        } else {
            expandedDocketRowIDs.insert(rowID)
        }
    }

    private func priorityGlyph(for pri: String) -> some View {
        let glyph = normalizedPriority(pri)
        let color: Color = {
            switch normalizedPriorityCode(pri) {
            case "U": return .red
            case "H": return .orange
            case "L", "P": return .secondary
            default: return .yellow
            }
        }()
        return Text(glyph)
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.bold)
            .foregroundStyle(color)
            .frame(width: 28, alignment: .leading)
            .accessibilityLabel("Priority \(glyph)")
    }

    private func normalizedPriority(_ pri: String) -> String {
        switch normalizedPriorityCode(pri) {
        case "U": return "███"
        case "H": return "▰▰▰"
        case "L": return "▰▱▱"
        case "P": return "▱▱▱"
        default: return "▰▰▱"
        }
    }

    private func normalizedPriorityCode(_ pri: String) -> String {
        switch pri.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "U", "H", "L", "P": return pri.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        default: return "M"
        }
    }

    private func fileTag(for file: PresentationFile, rowID: String) -> some View {
        let isHovered = hoveredFileTagRowID == rowID
        return Button {
            selectedTag = file.id
        } label: {
            Text(file.url.lastPathComponent)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.teal)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.teal.opacity(isHovered ? 0.22 : 0.12)))
                .overlay(Capsule().stroke(Color.teal.opacity(isHovered ? 0.65 : 0.25)))
        }
        .buttonStyle(.plain)
        .help("Open \(file.url.lastPathComponent)")
        .onHover { hovering in
            hoveredFileTagRowID = hovering ? rowID : nil
        }
    }

    private func linearTag(_ linearID: String) -> some View {
        let isHovered = hoveredLinearID == linearID
        return Button {
            openLinearIssue(linearID)
        } label: {
            Text(linearID)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.blue.opacity(isHovered ? 0.22 : 0.12)))
                .overlay(Capsule().stroke(Color.blue.opacity(isHovered ? 0.65 : 0.25)))
        }
        .buttonStyle(.plain)
        .help("Open \(linearID) in Linear")
        .onHover { hovering in
            hoveredLinearID = hovering ? linearID : nil
        }
    }

    private func openLinearIssue(_ linearID: String) {
        if let appURL = URL(string: "linear://issue/\(linearID)"),
           NSWorkspace.shared.open(appURL) {
            return
        }
        if let webURL = URL(string: "https://linear.app/deepwell-it/issue/\(linearID)") {
            NSWorkspace.shared.open(webURL)
        }
    }

    private func displayOwner(_ owner: String) -> String {
        let trimmed = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "dan": return "Dan"
        default: return trimmed
        }
    }

    private func fileDetail(_ file: PresentationFile) -> some View {
        let isArchived = ArchiveStore.isArchived(file)
        // d337: reverse of d336 — which docket rows' text names THIS file.
        // Render-time only, never written into the .md (files stay clean,
        // backlinks never go stale, the [AI-assisted] trailer stays last).
        let referencingRows = DocketFileLinking.docketRows(referencing: file, in: docketRows)
        return VStack(alignment: .leading, spacing: 0) {
            if !referencingRows.isEmpty {
                backlinkHeader(referencingRows)
                Divider()
            }
            Group {
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

    private func backlinkHeader(_ rows: [DocketRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Referenced by:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            ForEach(rows) { row in
                docketBacklinkRow(row)
                Divider()
            }
        }
    }

    private func docketBacklinkRow(_ row: DocketRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            priorityGlyph(for: row.pri)
            Button(row.id) {
                // d337: "each id tappable to its docket detail" — jumps
                // to the pinned Docket panel in All mode so the referenced
                // row is guaranteed visible even if it's not owner=dan.
                showAllDocket = true
                selectedTag = Self.docketTag
            }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.blue)
            .frame(width: 34, alignment: .leading)
            Text(row.text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if !row.linearId.isEmpty {
                linearTag(row.linearId)
            }
            if !row.owner.isEmpty {
                Text(displayOwner(row.owner))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
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
