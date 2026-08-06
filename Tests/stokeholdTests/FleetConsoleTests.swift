import XCTest
@testable import stokehold

/// #16 and #17, both surfaced by a real incident: `FleetConsole.sample()`
/// had been failing on every poll against current skybridge for an unknown
/// period, and nothing said so. Two independent breaks (`bosun.py` retired
/// in skybridge d501; `pmview.json` relocated in skybridge d145), each a
/// hard failure before the subprocess emitted a byte — and both invisible,
/// because every failure mode collapsed into `nil`, which the app could not
/// distinguish from "first sample still pending."
///
/// These tests pin the two properties that would have caught it: a failure
/// is reportable and carries its cause, and the count on the menubar means
/// what it says.
final class FleetConsoleTests: XCTestCase {

    // MARK: - #16: failures are distinguishable and self-describing

    /// The exact drift that was live in `main`. The value of the fix is not
    /// that the app notices, but that it can NAME the cause — this asserts
    /// the ModuleNotFoundError line survives all the way out of the
    /// subprocess to the operator-facing string.
    func testRetiredSkybridgeImportSurfacesAsNamedCause() {
        let result = FleetConsole.runPython("import bosun_module_that_was_retired")

        guard case .failure(let error) = result else {
            return XCTFail("a failing import must not read as success")
        }
        guard case .scriptFailed(let status, let detail) = error else {
            return XCTFail("expected scriptFailed, got \(error)")
        }
        XCTAssertNotEqual(status, 0)
        XCTAssertTrue(
            detail.contains("ModuleNotFoundError"),
            "the exception line is what identifies the drift; got: \(detail)"
        )
        // And it reaches the dropdown verbatim, not flattened to a generic.
        XCTAssertEqual(error.summary, detail)
    }

    /// A script that exits 0 but emits JSON of the wrong shape is skybridge
    /// changing shape rather than breaking outright — a distinct case, and
    /// one that names the field that moved.
    func testSchemaDriftReportsTheMissingKey() {
        let result = FleetConsole.decodeSnapshot(Data(#"{"dispatch_count": 3}"#.utf8))

        guard case .failure(.decodeFailed(let detail)) = result else {
            return XCTFail("expected decodeFailed, got \(result)")
        }
        // Exact, not `contains`: a looser assertion would also pass on a
        // dataCorrupted debugDescription that merely quoted the JSON, which
        // would mean the keyNotFound branch isn't the one firing at all.
        XCTAssertEqual(detail, "missing key 'fleet_capacity'")
    }

    /// The success path still works — a guard against "fixed" error handling
    /// that reports everything as broken.
    func testWellFormedOutputStillDecodes() {
        let json = #"""
        {"fleet_capacity": {"working": ["helm"], "down": []},
         "dispatch_count": 2, "docket_rows": []}
        """#
        guard case .success(let snapshot) = FleetConsole.decodeSnapshot(Data(json.utf8)) else {
            return XCTFail("valid payload must decode")
        }
        XCTAssertEqual(snapshot.workingCount, 1)
        XCTAssertEqual(snapshot.dispatchCount, 2)
    }

    /// Regression guard for the latent hang the #16 work closed: stderr was
    /// an unread `Pipe()`, so a child that filled stderr's buffer would
    /// block writing while we blocked reading stdout to EOF. 256 KB is well
    /// past the ~64 KB pipe buffer that made it deadlock. A Python traceback
    /// always fit, which is why this never bit in practice — but a chatty
    /// skybridge warning would have hung the poll loop, not just lost a
    /// message. If this test ever hangs rather than fails, that is the bug.
    func testLargeStderrDoesNotDeadlock() {
        let script = """
        import sys
        sys.stderr.write("x" * 262144 + "\\nFinalError: the real cause\\n")
        print('{"fleet_capacity": {}, "dispatch_count": 0, "docket_rows": []}')
        """
        let done = expectation(description: "subprocess completes without deadlocking")
        DispatchQueue.global().async {
            _ = FleetConsole.runPython(script)
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    /// A subprocess that never exits must be killed and REPORTED, not waited
    /// on forever. Without the bounded wait this blocks inside one
    /// `sample()`, the 5s poll loop stops iterating, and the dropdown
    /// freezes on its last state with nothing to say — reintroducing the
    /// silent failure #16 exists to eliminate, one layer down.
    func testWedgedSubprocessTimesOutRatherThanHangingThePollLoop() {
        let started = Date()
        let result = FleetConsole.runPython("import time; time.sleep(600)", timeout: 2)

        guard case .failure(let error) = result else {
            return XCTFail("a wedged interpreter must not read as success")
        }
        XCTAssertEqual(error, .timedOut(seconds: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(started), 30,
            "must return on the timeout, not on the child's own 600s sleep"
        )
        XCTAssertEqual(error.summary, "console read timed out after 2s")
    }

    /// The timeout must not fire on a process that IS finishing — a bound
    /// that trips early would turn every slow console read into a fault.
    func testSlowButCompletingScriptIsNotTimedOut() {
        let script = """
        import time
        time.sleep(1)
        print('{"fleet_capacity": {"working": ["helm"]}, "dispatch_count": 0, "docket_rows": []}')
        """
        guard case .success(let data) = FleetConsole.runPython(script, timeout: 15) else {
            return XCTFail("a script that completes within the bound must succeed")
        }
        guard case .success(let snapshot) = FleetConsole.decodeSnapshot(data) else {
            return XCTFail("output should decode")
        }
        XCTAssertEqual(snapshot.handsCount, 1)
    }

    /// Long skybridge errors (ConfigNotFoundError prints a whole discovery
    /// list) must not blow out the 250pt dropdown.
    func testOverlongCauseIsTruncatedForTheDropdown() {
        let long = String(repeating: "e", count: 400)
        let summary = FleetConsole.lastMeaningfulLine(of: Data(long.utf8))
        XCTAssertLessThanOrEqual(summary.count, 120)
        XCTAssertTrue(summary.hasSuffix("…"))
    }

    /// Python tracebacks end with the exception; trailing blank lines must
    /// not win.
    func testCauseIsTheExceptionLineNotTrailingWhitespace() {
        let traceback = """
        Traceback (most recent call last):
          File "<string>", line 7, in <module>
        ModuleNotFoundError: No module named 'bosun'


        """
        XCTAssertEqual(
            FleetConsole.lastMeaningfulLine(of: Data(traceback.utf8)),
            "ModuleNotFoundError: No module named 'bosun'"
        )
    }

    // MARK: - #16: cold start and broken are no longer the same string

    func testColdStartAndBrokenConsoleReadDifferently() {
        let reading = BoilerReading(
            cpuPercent: 20, ramPercent: 30, load1: 1,
            fleetCPUPercent: 5, fleetRAMPercent: 5
        )
        let coldStart = BlackGang.statusLine(for: reading, hands: nil, consoleFailed: false)
        let broken = BlackGang.statusLine(for: reading, hands: nil, consoleFailed: true)

        XCTAssertEqual(coldStart, "Reading the fleet…")
        XCTAssertNotEqual(
            broken, coldStart,
            "a console that has NEVER sampled must not masquerade as one still starting up — that is exactly how the bosun drift hid"
        )
    }

    // MARK: - #17: "N hands" counts hands below, not the roster

    /// The live state that prompted #17: 18 seats, 6 down, 12 headless on
    /// standby, none working. The menubar read "18 hands below."
    func testDownSeatsAreCrewButNotHands() {
        let snapshot = FleetSnapshot(
            fleetCapacity: [
                "available": [], "working": [], "waiting": [],
                "waiting_on_dan": [], "blocked": [],
                "down": ["helm", "mate1", "mate4", "mate5", "mate6", "mate48"],
                "standby_headless": (1...12).map { "headless\($0)" },
            ],
            dispatchCount: 8,
            docketRows: []
        )

        XCTAssertEqual(snapshot.crewCount, 18, "roster total is unchanged — the dropdown's 'N crew' line still means everyone signed on")
        XCTAssertEqual(snapshot.downCount, 6)
        XCTAssertEqual(snapshot.handsCount, 12, "down seats aren't below")
    }

    /// Standby headless mates ARE hands — they're below and can take a turn.
    /// This is the distinction that makes `handsCount` different from
    /// `workingCount`, and it was Dan's explicit ruling on #17.
    func testStandbyHeadlessCountsAsHands() {
        let snapshot = FleetSnapshot(
            fleetCapacity: ["working": ["helm"], "standby_headless": ["mach", "arch"]],
            dispatchCount: 0,
            docketRows: []
        )
        XCTAssertEqual(snapshot.handsCount, 3)
    }

    /// An all-down fleet reads as deserted rather than as a full crew.
    func testAllDownFleetReadsAsCrewAshore() {
        let snapshot = FleetSnapshot(
            fleetCapacity: ["down": ["helm", "mate1", "mate4"]],
            dispatchCount: 0,
            docketRows: []
        )
        XCTAssertEqual(snapshot.handsCount, 0)

        let idle = BoilerReading(
            cpuPercent: 3, ramPercent: 20, load1: 0.2,
            fleetCPUPercent: 0, fleetRAMPercent: 0
        )
        XCTAssertEqual(
            BlackGang.statusLine(for: idle, hands: snapshot.handsCount),
            "Cold boilers, crew ashore."
        )
    }

    /// A missing bucket is 0, not a crash — skybridge adding or dropping a
    /// bucket must not take the count with it.
    func testAbsentDownBucketIsZero() {
        let snapshot = FleetSnapshot(
            fleetCapacity: ["working": ["helm"]],
            dispatchCount: 0,
            docketRows: []
        )
        XCTAssertEqual(snapshot.downCount, 0)
        XCTAssertEqual(snapshot.handsCount, snapshot.crewCount)
    }
}
