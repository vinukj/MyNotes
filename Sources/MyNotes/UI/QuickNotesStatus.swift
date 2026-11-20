import AppKit
import IOKit
import IOKit.pwr_mgt
import Observation

@MainActor
@Observable
final class QuickNotesStatus {
    private(set) var cpuUsage: Double?
    private(set) var memoryUsage: Double?
    private(set) var gpuUsage: Double?
    private(set) var preventsSleep = false
    private(set) var sleepPreventionDuration: TimeInterval = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previousCPUTicks: [UInt32]?
    @ObservationIgnored private var sleepAssertion: IOPMAssertionID = 0
    @ObservationIgnored private var displayAssertion: IOPMAssertionID = 0
    @ObservationIgnored private var sleepPreventionStartedAt: Date?
    @ObservationIgnored private var panelIsSampling = false

    func startSampling() {
        panelIsSampling = true
        sample()
        startTimerIfNeeded()
    }

    func stopSampling() {
        panelIsSampling = false
        previousCPUTicks = nil
        if !preventsSleep { stopTimer() }
    }

    func setPreventsSleep(_ enabled: Bool) {
        guard enabled else {
            releaseAssertions()
            preventsSleep = false
            sleepPreventionStartedAt = nil
            sleepPreventionDuration = 0
            if !panelIsSampling { stopTimer() }
            return
        }
        guard !preventsSleep else { return }

        var systemAssertion: IOPMAssertionID = 0
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MyNotes Coffee Toggle" as CFString,
            &systemAssertion
        )
        guard systemResult == kIOReturnSuccess else { return }

        var displayAssertion: IOPMAssertionID = 0
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MyNotes Coffee Toggle" as CFString,
            &displayAssertion
        )
        guard displayResult == kIOReturnSuccess else {
            IOPMAssertionRelease(systemAssertion)
            return
        }

        sleepAssertion = systemAssertion
        self.displayAssertion = displayAssertion
        sleepPreventionStartedAt = .now
        sleepPreventionDuration = 0
        preventsSleep = true
        startTimerIfNeeded()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer.tolerance = 0.3
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func releaseAssertions() {
        if sleepAssertion != 0 { IOPMAssertionRelease(sleepAssertion) }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
        sleepAssertion = 0
        displayAssertion = 0
    }

    private func sample() {
        if panelIsSampling {
            sampleCPU()
            sampleMemory()
            gpuUsage = Self.gpuUtilization()
        }
        if let sleepPreventionStartedAt {
            sleepPreventionDuration = Date.now.timeIntervalSince(sleepPreventionStartedAt)
        }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        if let previousCPUTicks {
            let deltas = zip(ticks, previousCPUTicks).map { $0 &- $1 }
            let total = deltas.reduce(UInt64(0)) { $0 + UInt64($1) }
            if total > 0 {
                cpuUsage = Double(deltas[0] &+ deltas[1] &+ deltas[3]) / Double(total) * 100
            }
        }
        previousCPUTicks = ticks
    }

    private func sampleMemory() {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, ProcessInfo.processInfo.physicalMemory > 0 else { return }
        let usedPages = UInt64(statistics.active_count) + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        memoryUsage = min(100, Double(usedBytes) / Double(ProcessInfo.processInfo.physicalMemory) * 100)
    }

    private static func gpuUtilization() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var values: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? NSDictionary,
               let statistics = dictionary["PerformanceStatistics"] as? NSDictionary,
               let utilization = statistics["Device Utilization %"] as? NSNumber {
                values.append(utilization.doubleValue)
            }
            service = IOIteratorNext(iterator)
        }
        // shortcut: private IOAccelerator telemetry varies by Mac/OS; use the mean of available devices, nil when absent.
        guard !values.isEmpty else { return nil }
        return min(100, max(0, values.reduce(0, +) / Double(values.count)))
    }
}
