import Foundation

/// The fleet's Captain's-console view: crew activity (including
/// headless mates BoilerMetrics' process scan can miss), pending Dispatches,
/// and the live docket (whose rows carry the dan-owned/needs-Dan tag every
/// needs-Dan surface in the app derives from). Read-only reuse of
/// `src/skybridge/console.py`'s existing pure functions via a `python3`
/// subprocess — no skybridge source is modified to get this data.
/// d298 rework: one live docket row, shaped for the Chart Room's Docket
/// panel columns (id / priority / text / Linear mapping / owner). `pri`
/// and `linearId` come from docket/annunciator's own canonical helpers —
/// NOT re-derived here — and `needsDan` is a tag computed against
/// `docket.dan_owned_open_items`'s own id set (the one owner-field filter
/// per d324/d327/d333), not a second independent "is this for Dan" check. This is
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
    let fleetCapacity: [String: [String]]
    let dispatchCount: Int
    let docketRows: [DocketRow]

    enum CodingKeys: String, CodingKey {
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

    /// Seats skybridge classes as DOWN or STALE — on the roster, but not
    /// answering. Counted in `crewCount` (they are still crew) and excluded
    /// from `handsCount` (they are not below).
    var downCount: Int {
        fleetCapacity["down"]?.count ?? 0
    }

    /// Hands actually below: the roster minus the seats that aren't
    /// answering. This — not `crewCount` — is what the menubar status line
    /// counts (#17, Dan's ruling).
    ///
    /// `crewCount` is the right number for the dropdown's "N crew" roster
    /// line and stays as it was; it was the wrong number for "N hands
    /// shovelling," which read "18 hands below" while every one of those 18
    /// was down or on standby and none were working. Standby headless mates
    /// DO count as hands — they're below and can take a turn; a down seat
    /// can't.
    var handsCount: Int {
        crewCount - downCount
    }

    var workingCount: Int {
        fleetCapacity["working"]?.count ?? 0
    }

    var headlessStandbyCount: Int {
        fleetCapacity["standby_headless"]?.count ?? 0
    }

    var blockedCount: Int {
        fleetCapacity["blocked"]?.count ?? 0
    }

    /// OPEN dan-owned docket items (d382): counted off `docketRows`' own
    /// `needsDan` tag — the bosun `dan_owned_open_items` classification
    /// computed server-side in the python bridge below — so the dropdown's
    /// hero row, the Chart Room's Docket panel, and the menubar dot all read
    /// ONE derivation of "needs Dan" and can never silently disagree.
    /// Clears only when the items actually close (docketRows is already
    /// filtered to non-resolved), unlike the d253 unseen-presentations
    /// badge, which clears on view.
    var needsDanOpenCount: Int {
        docketRows.filter(\.needsDan).count
    }

    var openDocketCount: Int {
        docketRows.count
    }
}

/// Why a console sample failed. Every one of these used to collapse into a
/// bare `nil`, which the app could not tell apart from "the first sample
/// hasn't landed yet" — so a hard `ImportError` against a skybridge module
/// retired months ago rendered as a permanent, reassuring "Reading the
/// fleet…" (#16). The associated text is operator-facing: it is the thing
/// that makes the NEXT drift self-diagnosing instead of silent.
enum FleetConsoleError: Error, Equatable {
    /// `python3` itself never started.
    case launchFailed(String)
    /// The script ran and exited non-zero — import errors, config-not-found,
    /// anything skybridge raises. `detail` is the last meaningful stderr
    /// line, which for a Python traceback is the exception line.
    case scriptFailed(status: Int32, detail: String)
    /// The script exited 0 but its JSON no longer matches `FleetSnapshot` —
    /// i.e. skybridge changed shape rather than breaking outright.
    case decodeFailed(String)
    /// The subprocess never exited and was killed. Without this case the
    /// poll loop would block forever inside one `sample()` — the dropdown
    /// frozen on its last state with nothing to report, which is the very
    /// failure mode #16 exists to eliminate, one layer down. Reachable in
    /// practice: skybridge's config discovery walks directories, and a
    /// `python3` blocked on a stalled mount or a held lock never returns.
    case timedOut(seconds: Int)

    /// One line, short enough for the dropdown. Deliberately names the
    /// underlying cause rather than a generic "fleet unavailable."
    var summary: String {
        switch self {
        case .launchFailed(let detail):
            return "python3 wouldn't start: \(detail)"
        case .scriptFailed(_, let detail) where !detail.isEmpty:
            return detail
        case .scriptFailed(let status, _):
            return "console script exited \(status)"
        case .decodeFailed(let detail):
            return "console output didn't parse: \(detail)"
        case .timedOut(let seconds):
            return "console read timed out after \(seconds)s"
        }
    }
}

enum FleetConsole {
    /// This machine's skybridge checkout + the pmview commission config it
    /// runs — hardcoded like `BoilerMetrics`' `/bin/ps` path, since this app
    /// is inherently tied to one operator's local fleet setup, not a
    /// generic install.
    private static let skybridgeSrc = "/Users/drz/Projects/skybridge/src/skybridge"
    /// Skybridge d145 moved deployment state out of the repo root into
    /// per-commission dirs; `pmview.json` at the root no longer exists.
    private static let pmviewConfig =
        "/Users/drz/Projects/skybridge/commissions/pmview/commission.json"

    private static let pythonScript = """
        import json, sys
        sys.path.insert(0, "\(skybridgeSrc)")
        from config import load_config
        from console import load_console_data, dispatch_lines, clean_marker
        # dan_owned_open_items moved bosun.py -> docket.py when skybridge
        # retired bosun (d501); it is the same function, same id set.
        from docket import load_items, item_sort_key, RESOLVED_STATUS, dan_owned_open_items
        from annunciator import docket_linear_id
        config = load_config("\(pmviewConfig)")
        data = load_console_data(config)
        needs_dan_ids = {item["id"] for item in dan_owned_open_items(config)}
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
            "fleet_capacity": data["fleet_capacity"],
            "dispatch_count": len(dispatch_lines(config)),
            "docket_rows": docket_rows,
        }))
        """

    /// Holds one pipe's bytes while a background queue drains it. A class so
    /// the escaping read closure mutates one shared buffer rather than a
    /// captured copy.
    private final class DataBox {
        var data = Data()
    }

    static func sample() -> Result<FleetSnapshot, FleetConsoleError> {
        switch runPython(pythonScript) {
        case .failure(let error):
            return .failure(error)
        case .success(let outData):
            return decodeSnapshot(outData)
        }
    }

    /// Internal for tests: lets schema drift be exercised with a payload
    /// rather than by mutating skybridge.
    static func decodeSnapshot(_ data: Data) -> Result<FleetSnapshot, FleetConsoleError> {
        do {
            return .success(try JSONDecoder().decode(FleetSnapshot.self, from: data))
        } catch {
            return .failure(.decodeFailed(decodeDetail(for: error)))
        }
    }

    /// Runs `script` under `python3` and returns its stdout. Split out of
    /// `sample()` (internal, not private) so the failure paths — which are
    /// the entire point of #16 — can be driven by tests with scripts that
    /// fail on purpose, rather than only by breaking skybridge for real.
    /// `timeout` is generous against the 5s poll cadence — it exists to stop
    /// a wedged interpreter from freezing the loop, not to police a slow one.
    static func runPython(_ script: String, timeout: Int = 10) -> Result<Data, FleetConsoleError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }

        // Both pipes must be drained CONCURRENTLY. stderr was previously an
        // unread `Pipe()` — worse than discarding it, because a child that
        // filled stderr's buffer would block on write while we blocked
        // reading stdout to EOF, and neither side could advance. A Python
        // traceback is small enough to have always fit, so the hang was
        // latent rather than observed; draining both closes it either way.
        //
        // Neither read happens on THIS thread, so the bounded wait below is
        // genuinely bounded — a read that never sees EOF can't outlast it.
        let outBox = DataBox()
        let errBox = DataBox()
        let io = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: io) {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global(qos: .utility).async(group: io) {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
        }

        if io.wait(timeout: .now() + .seconds(timeout)) == .timedOut {
            // SIGTERM closes the pipes, which releases both reads. Give that
            // a moment; if the child is ignoring signals, SIGKILL it so the
            // reader threads can't be stranded either.
            process.terminate()
            if io.wait(timeout: .now() + .seconds(2)) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = io.wait(timeout: .now() + .seconds(2))
            }
            return .failure(.timedOut(seconds: timeout))
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return .failure(.scriptFailed(
                status: process.terminationStatus,
                detail: lastMeaningfulLine(of: errBox.data)
            ))
        }
        let outData = outBox.data

        return .success(outData)
    }

    /// The last non-blank stderr line. For a Python traceback that is the
    /// exception line — `ModuleNotFoundError: No module named 'bosun'` —
    /// which is exactly the sentence that identifies the drift.
    static func lastMeaningfulLine(of data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        let line = text
            .split(whereSeparator: \.isNewline)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        // Long skybridge errors (ConfigNotFoundError prints a discovery
        // list) would otherwise blow out the 250pt dropdown.
        return line.count > 120 ? String(line.prefix(119)) + "…" : line
    }

    /// Names the offending key for the common `DecodingError` cases, so a
    /// schema drift points at the field that moved rather than at "bad JSON."
    private static func decodeDetail(for error: Error) -> String {
        guard let error = error as? DecodingError else {
            return error.localizedDescription
        }
        switch error {
        case .keyNotFound(let key, _):
            return "missing key '\(key.stringValue)'"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "wrong type at '\(path)'"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "\(error)"
        }
    }
}
