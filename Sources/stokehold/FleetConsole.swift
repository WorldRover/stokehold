import Foundation

/// The fleet's Captain's-console view: missions, crew activity (including
/// headless mates BoilerMetrics' process scan can miss), pending Dispatches,
/// items needing Dan, and the review shelf. Read-only reuse of
/// `src/skybridge/console.py`'s existing pure functions via a `python3`
/// subprocess — no skybridge source is modified to get this data.
struct FleetSnapshot: Decodable {
    let missions: [String]
    let needsDan: [String]
    let reviewShelf: [String]
    let fleetCapacity: [String: [String]]
    let dispatchCount: Int

    enum CodingKeys: String, CodingKey {
        case missions
        case needsDan = "needs_dan"
        case reviewShelf = "review_shelf"
        case fleetCapacity = "fleet_capacity"
        case dispatchCount = "dispatch_count"
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
        from console import load_console_data, dispatch_lines
        config = load_config("\(pmviewConfig)")
        data = load_console_data(config)
        print(json.dumps({
            "missions": data["missions"],
            "needs_dan": data["needs_dan"],
            "review_shelf": data["review_shelf"],
            "fleet_capacity": data["fleet_capacity"],
            "dispatch_count": len(dispatch_lines(config)),
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
