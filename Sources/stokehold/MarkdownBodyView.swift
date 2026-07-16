import SwiftUI

/// d253: native markdown rendering via `AttributedString(markdown:)` with
/// `.full` block-syntax parsing — verified concretely (not assumed, and
/// re-verified against a REAL presentations file, not just a synthetic
/// sample) that this Swift toolchain's `.full` interpretation produces
/// real block-level `PresentationIntent`s: header level, codeBlock,
/// thematicBreak, ordered/unordered list + listItem, blockQuote, and
/// tables (tableCell/tableRow/tableHeaderRow). This view walks those
/// blocks and applies styling per kind — the PRIMARY renderer per the
/// locked design; `chart_room.py`'s own dependency-free markdown-lite
/// parser (`render_markdown_lines`) is the named fallback for any
/// construct this doesn't cover, not built here since `.full` covers
/// every construct exercised in testing, INCLUDING tables (not explicitly
/// named in the locked design's "headers/code/rules" list, but present in
/// real presentations content and handled properly below rather than left
/// to render as broken, disconnected one-cell-per-line output).
private enum MarkdownBlockKind: Equatable {
    case heading(level: Int)
    case paragraph
    case codeBlock
    case thematicBreak
    case listItem(ordinal: Int?, depth: Int)
    case blockQuote
    case tableRow(isHeader: Bool)
    case other
}

private struct MarkdownBlock: Identifiable {
    let id: Int
    let kind: MarkdownBlockKind
    /// Used by every kind except `.tableRow`.
    let content: AttributedString
    /// Used only by `.tableRow` — cell text runs abut with no separator in
    /// the parsed AttributedString (the pipe syntax is stripped), so a
    /// table row is rendered as an HStack of per-cell Text views rather
    /// than one sliced range.
    let cells: [AttributedString]
}

/// A run's classification for grouping: table cells group by their ROW's
/// identity (so a whole row becomes one block), not the cell's own
/// identity (which would split every cell into its own disconnected
/// block — a real bug found testing against a real file with a table,
/// where every cell rendered as a separate line with no separator).
/// Everything else groups by its own innermost identity, as before.
///
/// Deliberately does NOT carry the cell ordinal — that's tracked
/// separately (`currentCellOrdinal` in `splitIntoBlocks`) specifically so
/// a per-cell change does NOT also look like a ROW boundary to the
/// Equatable comparison that drives the outer grouping loop. Including it
/// here was the actual bug on the first pass: `RunGroupKey` being
/// Equatable over `cellOrdinal` too made every cell change ALSO trigger a
/// row flush, defeating the row-grouping entirely.
private struct RunGroupKey: Equatable {
    let identity: Int
    let isTableCell: Bool
}

private func groupKey(for intent: PresentationIntent?) -> RunGroupKey? {
    guard let intent else { return nil }
    for component in intent.components {
        if case .tableRow = component.kind {
            return RunGroupKey(identity: component.identity, isTableCell: true)
        }
        if case .tableHeaderRow = component.kind {
            return RunGroupKey(identity: component.identity, isTableCell: true)
        }
    }
    return RunGroupKey(identity: intent.components.first?.identity ?? -1, isTableCell: false)
}

private func cellOrdinal(for intent: PresentationIntent?) -> Int? {
    guard let intent else { return nil }
    for component in intent.components {
        if case .tableCell(let ordinal) = component.kind {
            return ordinal
        }
    }
    return nil
}

private func nonTableKind(for intent: PresentationIntent) -> MarkdownBlockKind {
    var listDepth = 0
    for component in intent.components {
        switch component.kind {
        case .header(let level):
            return .heading(level: level)
        case .codeBlock:
            return .codeBlock
        case .thematicBreak:
            return .thematicBreak
        case .blockQuote:
            return .blockQuote
        case .listItem(let ordinal):
            // Depth = how many list-item wrappers this run sits inside —
            // a nested bullet carries TWO (listItem, unorderedList) pairs
            // in its component chain, a top-level one carries ONE. Not
            // full CommonMark indent fidelity, but distinguishes nesting
            // levels visually rather than flattening everything to one
            // bullet column.
            listDepth += 1
            if listDepth == 1 {
                return .listItem(ordinal: ordinal, depth: countListWrappers(intent))
            }
        default:
            continue
        }
    }
    return .paragraph
}

private func countListWrappers(_ intent: PresentationIntent) -> Int {
    intent.components.filter {
        if case .listItem = $0.kind { return true }
        return false
    }.count
}

private func isHeaderRow(_ intent: PresentationIntent?) -> Bool {
    intent?.components.contains { if case .tableHeaderRow = $0.kind { return true }; return false } ?? false
}

/// Groups the parsed `AttributedString`'s runs into visual blocks. Table
/// rows accumulate their cells separately (see `RunGroupKey`); every other
/// block is a contiguous character range sliced directly out of the
/// original AttributedString, which preserves inline bold/italic/code
/// spans within it for free.
private func splitIntoBlocks(_ attributed: AttributedString) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var blockCounter = 0

    var currentKey: RunGroupKey?
    var currentStart = attributed.startIndex
    var currentCells: [AttributedString] = []
    var currentCellStart = attributed.startIndex
    var currentCellOrdinal: Int?
    var currentRowIsHeader = false

    func flushNonTable(upTo end: AttributedString.Index) {
        guard currentStart < end else { return }
        let sub = attributed[currentStart..<end]
        let kind = sub.runs.first?.presentationIntent.map(nonTableKind(for:)) ?? .other
        blocks.append(MarkdownBlock(id: blockCounter, kind: kind, content: AttributedString(sub), cells: []))
        blockCounter += 1
    }

    func flushTableRow(upTo end: AttributedString.Index) {
        if let ordinal = currentCellOrdinal, ordinal >= 0, currentCellStart < end {
            currentCells.append(AttributedString(attributed[currentCellStart..<end]))
        }
        guard !currentCells.isEmpty else { return }
        blocks.append(MarkdownBlock(id: blockCounter, kind: .tableRow(isHeader: currentRowIsHeader), content: AttributedString(""), cells: currentCells))
        blockCounter += 1
        currentCells = []
    }

    for run in attributed.runs {
        let key = groupKey(for: run.presentationIntent)
        if key != currentKey {
            // Row (or non-table block) boundary — flush whatever was open,
            // using the STATE ACCUMULATED WHILE building it (currentRowIsHeader
            // was set when this row started, from ITS OWN first run — never
            // from whatever run comes next).
            if let prevKey = currentKey {
                if prevKey.isTableCell {
                    flushTableRow(upTo: run.range.lowerBound)
                } else {
                    flushNonTable(upTo: run.range.lowerBound)
                }
            }
            currentStart = run.range.lowerBound
            currentCellStart = run.range.lowerBound
            currentCellOrdinal = nil
            if key?.isTableCell == true {
                currentRowIsHeader = isHeaderRow(run.presentationIntent)
            }
        }
        if key?.isTableCell == true {
            let ordinal = cellOrdinal(for: run.presentationIntent)
            if ordinal != currentCellOrdinal {
                if let prevOrdinal = currentCellOrdinal, prevOrdinal >= 0, currentCellStart < run.range.lowerBound {
                    currentCells.append(AttributedString(attributed[currentCellStart..<run.range.lowerBound]))
                }
                currentCellStart = run.range.lowerBound
                currentCellOrdinal = ordinal
            }
        }
        currentKey = key
    }
    if let lastKey = currentKey {
        if lastKey.isTableCell {
            flushTableRow(upTo: attributed.endIndex)
        } else {
            flushNonTable(upTo: attributed.endIndex)
        }
    }
    return blocks
}

struct MarkdownBodyView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        guard let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full)) else {
            // Malformed/unparseable input still needs to show SOMETHING —
            // one big plain-paragraph block rather than a blank pane.
            return [MarkdownBlock(id: 0, kind: .paragraph, content: AttributedString(text), cells: [])]
        }
        return splitIntoBlocks(attributed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.content)
                .font(headingFont(for: level))
                .fontWeight(.bold)
                .padding(.top, level == 1 ? 6 : 2)
        case .codeBlock:
            Text(block.content)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)
        case .thematicBreak:
            Divider()
        case .listItem(_, let depth):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(block.content)
            }
            .padding(.leading, CGFloat(max(0, depth - 1)) * 16)
        case .blockQuote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 3)
                Text(block.content)
                    .foregroundStyle(.secondary)
            }
        case .tableRow(let isHeader):
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(block.cells.enumerated()), id: \.offset) { _, cell in
                    Text(cell)
                        .fontWeight(isHeader ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                if isHeader {
                    Divider()
                }
            }
        case .paragraph, .other:
            Text(block.content)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
}
