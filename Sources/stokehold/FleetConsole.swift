import Foundation

/// The fleet's Captain's-console view: missions, crew activity (including
/// headless mates BoilerMetrics' process scan can miss), pending Dispatches,
/// items needing Dan, and the review shelf. Read-only reuse of
/// `src/skybridge/console.py`'s existing pure functions via a `python3`
/// subprocess — no skybridge source is modified to get this data.
/// d298 rework: one live docket row, shaped for the Chart Room's Docket
/// panel columns (id / priority / text / Linear mapping / owner). `pri`
/// and `linearId` come from bosun/annunciator's own canonical helpers —
/// NOT re-derived here — and `needsDan` is a tag computed against
/// `bosun.current_needs_dan_items`'s own id set (the one classifier per
/// d324/d327), not a second independent "is this for Dan" check. This is
/// what lets the panel's Dan-only/all filter be a pure client-side toggle
/// on ONE poll result rather than two separately-derived lists that could
/// silently disagree.
struct DocketRow: Decodable, Identifiable {
    let id: String
    let pri: String
    let text: String
    let owner: String
    let linearId: String
    let needsDan: Bool

    enum CodingKeys: String, CodingKey {
        case id, pri, text, owner
        case linearId = "linear_id"
        case needsDan = "needs_dan"
    }
}

struct FleetSnapshot: Decodable {
    let missions: [String]
    let needsDan: [String]
    let reviewShelf: [String]
    let fleetCapacity: [String: [String]]
    let dispatchCount: Int
    let docketRows: [DocketRow]

    enum CodingKeys: String, CodingKey {
        case missions
        case needsDan = "needs_dan"
        case reviewShelf = "review_shelf"
        case fleetCapacity = "fleet_capacity"
        case dispatchCount = "dispatch_count"
        case docketRows = "docket_rows"
    }

    /// Crew count across every bucket `console.fleet_capacity` returns,
    /// including `standby_headless` — the count BoilerMetrics' `ps`-based
    /// scan can silently miss for a headless mate between turns.
    var crewCount: Int {
        fleetCapacity.values.reduce(0) { $0 + $1.count }
    }

    var headlessStandbyCount: Int {
        fleetCapacity["standby_headless"]?.count ?? 0
    }

    var blockedCount: Int {
        fleetCapacity["blocked"]?.count ?? 0
    }
}

enum FleetConsole {
    /// This machine's skybridge checkout + the pmview commission config it
    /// runs — hardcoded like `BoilerMetrics`' `/bin/ps` path, since this app
    /// is inherently tied to one operator's local fleet setup, not a
    /// generic install.
    private static let skybridgeSrc = "/Users/drz/Projects/skybridge/src/skybridge"
    private static let pmviewConfig = "/Users/drz/Projects/skybridge/pmview.json"

    private static let pythonScript = """
        import json, sys
        sys.path.insert(0, "\(skybridgeSrc)")
        from config import load_config
        from console import load_console_data, dispatch_lines, clean_marker
        from docket import load_items, item_sort_key, RESOLVED_STATUS
        from bosun import current_needs_dan_items
        from annunciator import docket_linear_id
        config = load_config("\(pmviewConfig)")
        data = load_console_data(config)
        needs_dan_ids = {item["id"] for item in current_needs_dan_items(config)}
        live_items = [
            item for item in load_items(config)
            if str(item.get("status") or "open").strip().lower() not in (RESOLVED_STATUS | {"archived"})
        ]
        docket_rows = [
            {
                "id": str(item.get("id") or "d?"),
                "pri": str(item.get("pri") or "M").upper(),
                "text": clean_marker(str(item.get("text") or "")),
                "owner": str(item.get("owner") or ""),
                "linear_id": docket_linear_id(item, config),
                "needs_dan": str(item.get("id") or "d?") in needs_dan_ids,
            }
            for item in sorted(live_items, key=item_sort_key)
        ]
        print(json.dumps({
            "missions": data["missions"],
            "needs_dan": data["needs_dan"],
            "review_shelf": data["review_shelf"],
            "fleet_capacity": data["fleet_capacity"],
            "dispatch_count": len(dispatch_lines(config)),
            "docket_rows": docket_rows,
        }))
        """

    static func sample() -> FleetSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", pythonScript]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        return try? JSONDecoder().decode(FleetSnapshot.self, from: data)
    }
}
