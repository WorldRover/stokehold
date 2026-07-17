import Foundation

/// d336/d337: ONE filename-substring matcher for both directions — d336
/// (a docket row that names a presentation file becomes clickable, opening
/// it) and d337 (a presentation's detail pane shows "Referenced by:" the
/// docket rows whose text names it). Dumb substring match against each
/// file's already-stripped `displayName`, no new metadata schema — per the
/// docket's own instruction ("keep it dumb... one matcher, two consumers").
enum DocketFileLinking {
    /// The shared predicate both directions are built from.
    static func textReferences(_ text: String, _ file: PresentationFile) -> Bool {
        !file.displayName.isEmpty && text.localizedCaseInsensitiveContains(file.displayName)
    }

    /// d336: the first presentation file a docket row's text names, if any.
    /// "First" (not "all") because a row linking to more than one file at
    /// once has nowhere sensible to send a single tap — the docket's own
    /// convention (d335) is one short row naming one file.
    static func referencedFile(in text: String, files: [PresentationFile]) -> PresentationFile? {
        files.first { textReferences(text, $0) }
    }

    /// d337: every docket row whose text names this presentation file.
    static func docketRows(referencing file: PresentationFile, in rows: [DocketRow]) -> [DocketRow] {
        rows.filter { textReferences($0.text, file) }
    }
}
