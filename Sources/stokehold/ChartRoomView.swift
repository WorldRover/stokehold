import SwiftUI

/// d253: the Chart Room reading window — a `NavigationSplitView` gives
/// sidebar + scrollable detail BUILT IN, with zero hand-coordination
/// between them (unlike the terminal Chart Room's curses app, or the
/// rejected two-tmux-pane hybrid option, which both have to hand-build
/// that coordination). Content lives in its own `Window` scene
/// (`StokeholdApp.swift`), not the `MenuBarExtra` popover — a real reading
/// surface doesn't belong squeezed into a transient dropdown.
struct ChartRoomView: View {
    @ObservedObject var model: PresentationsModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 700, minHeight: 450)
    }

    private var sidebar: some View {
        Group {
            if model.files.isEmpty {
                emptyState
            } else {
                List(model.files, selection: selectionBinding) { file in
                    HStack {
                        Text(file.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !SeenStore.isSeen(file) {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .tag(file.id)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selected?.id },
            set: { newID in
                guard let newID, let file = model.files.first(where: { $0.id == newID }) else { return }
                model.select(file)
            }
        )
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
        if let file = model.selected {
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
            .navigationTitle(file.displayName)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func contentBody(for file: PresentationFile) -> some View {
        let text = (try? String(contentsOf: file.url, encoding: .utf8)) ?? "(unreadable file)"
        if file.isMarkdown {
            MarkdownBodyView(text: text)
        } else {
            Text(text)
                .font(.system(.body, design: .monospaced))
        }
    }
}
