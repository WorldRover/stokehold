import Darwin
import Foundation

/// A single pressure reading: machine-wide load plus the AI fleet's ("black gang") share of it.
///
/// d229-followup (mate9's RC): `fleetCount` deliberately does NOT live here
/// any more. `sampleFleet()`'s machine-wide `ps` comm-match below counts ANY
/// process named claude/codex/gemini anywhere on the machine — confirmed
/// false-positiving on Dan's ChatGPT.app codex helper, a personal codex CLI
/// session, and Claude Code's own daemon, none of which are fleet seats.
/// The accurate "hands" count is `FleetSnapshot.crewCount`
/// (`FleetConsole.swift`, console.py-derived, includes headless mates this
/// `ps` scan can't distinguish from stray processes either way) — see
/// `BlackGang.statusLine`'s `hands` parameter and `StokeholdApp`'s call site.
/// `fleetCPUPercent`/`fleetRAMPercent` stay sourced from `sampleFleet()`
/// unchanged: machine-wide process load is legitimately what those measure,
/// this fix is scoped to the HAND COUNT only.
struct BoilerReading {
    let cpuPercent: Double
    let ramPercent: Double
    let load1: Double
    let fleetCPUPercent: Double
    let fleetRAMPercent: Double
}

enum BoilerMetrics {
    static func sample() -> BoilerReading {
        let cpu = sampleCPUPercent()
        let ram = sampleRAMPercent()
        let load1 = sampleLoad1()
        let fleet = sampleFleet()
        return BoilerReading(
            cpuPercent: cpu,
            ramPercent: ram,
            load1: load1,
            fleetCPUPercent: fleet.cpu,
            fleetRAMPercent: fleet.ramPercent
        )
    }

    // MARK: - CPU

    private static func sampleCPUPercent() -> Double {
        guard let first = cpuTicks() else { return 0 }
        Thread.sleep(forTimeInterval: 0.2)
        guard let second = cpuTicks() else { return 0 }

        let idleDelta = Double(second.idle &- first.idle)
        let totalDelta = Double(second.total &- first.total)
        guard totalDelta > 0 else { return 0 }
        let busy = 1.0 - (idleDelta / totalDelta)
        return max(0, min(100, busy * 100))
    }

    private struct CPUTicks {
        let idle: UInt32
        let total: UInt32
    }

    private static func cpuTicks() -> CPUTicks? {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuLoad) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = cpuLoad.cpu_ticks
        let user = ticks.0, system = ticks.1, idle = ticks.2, nice = ticks.3
        let total = user &+ system &+ idle &+ nice
        return CPUTicks(idle: idle, total: total)
    }

    // MARK: - RAM

    private static func sampleRAMPercent() -> Double {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_kernel_page_size)
        let used = UInt64(vmStats.active_count + vmStats.wire_count + vmStats.compressor_page_count) * pageSize

        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        guard totalMem > 0 else { return 0 }

        return max(0, min(100, Double(used) / Double(totalMem) * 100))
    }

    // MARK: - Load average

    private static func sampleLoad1() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        let n = getloadavg(&loads, 3)
        return n > 0 ? loads[0] : 0
    }

    // MARK: - Fleet ("the black gang")

    private static let fleetNames: Set<String> = ["claude", "codex", "gemini"]

    private static func sampleFleet() -> (count: Int, cpu: Double, ramPercent: Double) {
        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "comm,pcpu,rss"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return (0, 0, 0)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return (0, 0, 0) }

        var count = 0
        var cpuSum = 0.0
        var rssSumKB: UInt64 = 0

        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }
            let comm = String(parts[parts.count - 3])
            let name = (comm as NSString).lastPathComponent
            guard fleetNames.contains(name) else { continue }
            guard let pcpu = Double(parts[parts.count - 2]),
                  let rss = UInt64(parts[parts.count - 1]) else { continue }
            count += 1
            cpuSum += pcpu
            rssSumKB += rss
        }

        let ramPercent: Double
        if totalMem > 0 {
            ramPercent = Double(rssSumKB * 1024) / Double(totalMem) * 100
        } else {
            ramPercent = 0
        }

        return (count, cpuSum, max(0, min(100, ramPercent)))
    }
}
