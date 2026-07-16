import Foundation

/// d253: one entry in the Chart Room feed — a file skybridge's
/// `presentations.present_file()` copied into the shared presentations
/// directory under a timestamp-prefixed name (`<epoch>-<original-name>`,
/// see `presentations.py`). Read directly off disk via FileManager, no
/// python bridge — unlike `FleetConsole`, this data IS the filesystem, not
/// something that needs skybridge's own Python to compute.
struct PresentationFile: Identifiable, Equatable {
    let url: URL
    let mtime: Date

    var id: String { url.path }

    /// Strips the `<epoch>-` sort prefix for display, mirroring
    /// `chart_room.py`'s own `display_name()` exactly (same regex shape:
    /// a leading run of digits + hyphen).
    var displayName: String {
        let name = url.lastPathComponent
        guard let dashIndex = name.firstIndex(of: "-") else { return name }
        let prefix = name[name.startIndex..<dashIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return name }
        return String(name[name.index(after: dashIndex)...])
    }

    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var isHTML: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }
}

/// d253: persists which presentations Dan has already opened, so the
/// menubar badge can show an UNSEEN count. Keyed by path+mtime (not path
/// alone) — `present_file`'s collision-avoidance naming means a given path
/// is normally write-once, but keying on mtime too means a file that
/// somehow gets replaced in place is treated as unseen again rather than
/// silently staying marked-seen against stale content.
enum SeenStore {
    private static let defaultsKey = "chartRoomSeenFiles"

    private static func seenKey(for file: PresentationFile) -> String {
        "\(file.url.path)#\(file.mtime.timeIntervalSince1970)"
    }

    static func isSeen(_ file: PresentationFile) -> Bool {
        let seen = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return seen.contains(seenKey(for: file))
    }

    static func markSeen(_ file: PresentationFile) {
        var seen = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        seen.insert(seenKey(for: file))
        UserDefaults.standard.set(Array(seen), forKey: defaultsKey)
    }
}

/// d300: "archived" is a DECISION (Dan is done with an item), deliberately
/// a SEPARATE store from `SeenStore`'s passive "he opened it" — conflating
/// the two would auto-archive anything merely glanced at, recreating the
/// exact complaint this feature exists to fix in reverse. A dedicated
/// per-item action (not a byproduct of viewing), a dedicated key.
///
/// Keyed path+mtime, the SAME scheme `SeenStore` uses, deliberately: a
/// regenerated doc (same path, refreshed content, new mtime — e.g. Dan
/// noted "d290 rev4, d235 chart-first, d302 final" as real recurring
/// examples) no longer matches its old archive key once its mtime
/// changes, so it naturally resurfaces as unarchived — no special-case
/// "was this content actually different" logic needed, the existing
/// keying scheme already gives the right behavior for free.
enum ArchiveStore {
    private static let defaultsKey = "chartRoomArchivedFiles"

    private static func archiveKey(for file: PresentationFile) -> String {
        "\(file.url.path)#\(file.mtime.timeIntervalSince1970)"
    }

    static func isArchived(_ file: PresentationFile) -> Bool {
        let archived = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return archived.contains(archiveKey(for: file))
    }

    static func setArchived(_ file: PresentationFile, archived: Bool) {
        var set = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        let key = archiveKey(for: file)
        if archived {
            set.insert(key)
        } else {
            set.remove(key)
        }
        UserDefaults.standard.set(Array(set), forKey: defaultsKey)
    }
}

/// d253: the Chart Room's data model — lists the presentations directory
/// on a timer poll, same idiom `BoilerModel`/`FleetConsole`'s own loops in
/// `StokeholdApp.swift` already use (no push mechanism exists anywhere in
/// this app; a poll interval matching `chart_room.py`'s own 2s choice is
/// the same tradeoff already accepted once, not a new one).
@MainActor
final class PresentationsModel: ObservableObject {
    @Published private(set) var files: [PresentationFile] = []
    @Published var selected: PresentationFile?
    @Published private(set) var unseenCount: Int = 0

    // Hardcoded like `FleetConsole`'s own `skybridgeSrc`/`pmviewConfig` —
    // this app is inherently tied to one operator's local fleet setup, not
    // a generic install. Resolved once by hand against the live
    // `presentations.presentations_dir(load_config(pmview.json))` value
    // rather than re-deriving it via a python subprocess on every poll.
    private static let directory = URL(fileURLWithPath: "/tmp/pmview/presentations")

    private var pollTask: Task<Void, Never>?

    init() {
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.refresh()
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    func refresh() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        )) ?? []
        let fresh = entries.compactMap { url -> PresentationFile? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate else { return nil }
            return PresentationFile(url: url, mtime: mtime)
        }
        // Sort key is the filename itself (the epoch prefix), newest-first —
        // mirrors `list_presentations()`'s own sort exactly, no separate
        // mtime-based ordering that could disagree with it.
        .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }

        files = fresh
        if selected == nil {
            // Prefer the newest ACTIVE (non-archived) file as the default
            // landing content — an all-archived newest item is an edge
            // case, but defaulting into archived content on first launch
            // would read oddly; fall back to the newest file overall only
            // if everything happens to be archived.
            selected = fresh.first { !ArchiveStore.isArchived($0) } ?? fresh.first
        } else if let current = selected, !fresh.contains(current) {
            // The selected file vanished from disk (rare, but don't leave a
            // dangling selection pointing at nothing) — fall back to newest.
            selected = fresh.first
        }
        recomputeUnseen()
    }

    func select(_ file: PresentationFile) {
        selected = file
        SeenStore.markSeen(file)
        recomputeUnseen()
    }

    /// d300: archiving is Dan's own manual decision (see `ArchiveStore`'s
    /// doc comment) — no automatic trigger anywhere calls this.
    func setArchived(_ file: PresentationFile, archived: Bool) {
        ArchiveStore.setArchived(file, archived: archived)
        // ArchiveStore's persistence lives in UserDefaults, outside this
        // object's own @Published storage — objectWillChange.send() is the
        // explicit signal SwiftUI needs to re-read ArchiveStore.isArchived
        // in the views that filter/badge on it.
        objectWillChange.send()
        recomputeUnseen()
    }

    private func recomputeUnseen() {
        // d300: an archived item no longer counts toward "needs your
        // attention" even if it was never formally marked seen (Dan can
        // decide something's obsolete from the title alone, without
        // opening it) — archiving is a STRONGER signal than seen, so it
        // subsumes it here rather than requiring both.
        unseenCount = files.reduce(0) { count, file in
            count + ((SeenStore.isSeen(file) || ArchiveStore.isArchived(file)) ? 0 : 1)
        }
    }
}
