//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import IOKit
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.showSystemMonitor] {
                            SystemMonitorBadgeView()
                        }
                        if Defaults[.showMessagesIcon] {
                            Button(action: {
                                NSWorkspace.shared.open(URL(string: "messages://")!)
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "message.fill")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showBatteryIndicator] {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

struct SystemMonitorBadgeView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.cyan)
                Text(String(format: "%.0f%%", monitor.cpuUsage))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            HStack(spacing: 3) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.purple)
                Text(String(format: "%.0f%%", monitor.gpuUsage))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

@MainActor
final class SystemMonitorManager: ObservableObject {
    static let shared = SystemMonitorManager()

    @Published var cpuUsage: Double = 0.0
    @Published var gpuUsage: Double = 0.0

    private var previousCPUInfo: host_cpu_load_info?
    private var timer: Timer?

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        updateStats()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStats()
            }
        }
    }

    func updateStats() {
        updateCPU()
        updateGPU()
    }

    private func updateCPU() {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return }

        if let prev = previousCPUInfo {
            let user = Double(cpuInfo.cpu_ticks.0 - prev.cpu_ticks.0)
            let system = Double(cpuInfo.cpu_ticks.1 - prev.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2 - prev.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3 - prev.cpu_ticks.3)
            let total = user + system + idle + nice
            if total > 0 {
                self.cpuUsage = min(100.0, max(0.0, ((user + system + nice) / total) * 100.0))
            }
        }
        previousCPUInfo = cpuInfo
    }

    private func updateGPU() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                if let gpuCoreUtilization = perfStats["Device Utilization %"] as? Int {
                    self.gpuUsage = Double(gpuCoreUtilization)
                    IOObjectRelease(service)
                    return
                } else if let gpuCoreUtilization = perfStats["GPU Core Utilization"] as? Double {
                    self.gpuUsage = gpuCoreUtilization * 100.0
                    IOObjectRelease(service)
                    return
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
