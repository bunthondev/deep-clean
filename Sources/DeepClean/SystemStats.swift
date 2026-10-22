import Foundation
import IOKit
import IOKit.ps

/// One reading of CPU, memory and battery. Cheap to take; the view model samples every 2 s.
struct SystemSnapshot: Sendable {
    var cpuPercent: Double = 0           // 0...100 across all cores
    var cpuName = ""
    var cores = 0
    var memoryUsed: Int64 = 0            // app + wired + compressed, like Activity Monitor
    var memoryTotal: Int64 = 0
    var memoryPressure = "normal"        // normal / warning / critical
    var hasBattery = false
    var batteryPercent = 0
    var charging = false
    var onAC = false
    var minutesRemaining: Int? = nil     // to empty (on battery) or to full (charging)
    var healthPercent: Int? = nil        // max capacity vs design capacity
    var cycleCount: Int? = nil
    var batteryTemperatureC: Double? = nil
}

final class SystemSampler: @unchecked Sendable {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    let cpuName: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }()
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let memoryTotal = Int64(ProcessInfo.processInfo.physicalMemory)

    func sample() -> SystemSnapshot {
        var s = SystemSnapshot()
        s.cpuName = cpuName
        s.cores = cores
        s.memoryTotal = memoryTotal
        s.cpuPercent = cpu()
        (s.memoryUsed, s.memoryPressure) = memory()
        battery(into: &s)
        return s
    }

    // MARK: CPU (delta of host ticks between two samples)

    private func cpu() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return 0 }
        return Double(busy - last.busy) / Double(total - last.total) * 100
    }

    // MARK: Memory

    private func memory() -> (Int64, String) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var used: Int64 = 0
        if result == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        }
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let pressure = level >= 4 ? "critical" : level >= 2 ? "warning" : "normal"
        return (used, pressure)
    }

    // MARK: Battery

    private func battery(into s: inout SystemSnapshot) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            s.hasBattery = true
            s.batteryPercent = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            s.charging = d[kIOPSIsChargingKey] as? Bool ?? false
            s.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let toEmpty = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = d[kIOPSTimeToFullChargeKey] as? Int ?? -1
            if s.charging, toFull > 0 { s.minutesRemaining = toFull }
            else if !s.onAC, toEmpty > 0 { s.minutesRemaining = toEmpty }
            break
        }
        guard s.hasBattery else { return }

        // Health and cycles from the battery driver in the IORegistry.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        func top(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        // Recent macOS keeps the mAh figures in a nested "BatteryData" dictionary; older ones at top level.
        let data = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] ?? [:]
        func prop(_ key: String) -> Int? { (data[key] as? Int) ?? top(key) }

        s.cycleCount = prop("CycleCount")
        // System Settings "Maximum Capacity" is NominalChargeCapacity / DesignCapacity.
        if let design = prop("DesignCapacity"), design > 0,
           let max = prop("NominalChargeCapacity") ?? prop("AppleRawMaxCapacity") ?? prop("FullChargeCapacity") {
            s.healthPercent = Int((Double(max) / Double(design) * 100).rounded())
        }
        if let t = prop("Temperature") ?? top("VirtualTemperature") { s.batteryTemperatureC = Double(t) / 100 }
    }
}
