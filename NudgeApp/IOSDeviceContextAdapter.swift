import UIKit

// MARK: - Protocol

protocol DeviceContextAdapter {
    func start(onEvent: @escaping (TriggerEvent) -> Void)
    func stop()
}

// MARK: - IOSDeviceContextAdapter
// Observes UIDevice battery state changes and emits TriggerEvents.
// Only fires on a TRANSITION into .charging/.full — not on .charging → .full.
// iOS limitation: batteryStateDidChangeNotification is not delivered to a
// fully terminated app. The adapter works when the app is active or backgrounded.

final class IOSDeviceContextAdapter: DeviceContextAdapter {

    private var onEvent: ((TriggerEvent) -> Void)?
    private var previousBatteryState: UIDevice.BatteryState = .unknown
    private var observer: NSObjectProtocol?

    func start(onEvent: @escaping (TriggerEvent) -> Void) {
        self.onEvent = onEvent
        UIDevice.current.isBatteryMonitoringEnabled = true
        previousBatteryState = UIDevice.current.batteryState

        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleBatteryStateChange()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        UIDevice.current.isBatteryMonitoringEnabled = false
        onEvent = nil
    }

    private func handleBatteryStateChange() {
        let current = UIDevice.current.batteryState
        defer { previousBatteryState = current }

        // Fire only on transition INTO charging/full (not .charging → .full).
        guard previousBatteryState != .charging && previousBatteryState != .full else { return }
        guard current == .charging || current == .full else { return }

        onEvent?(TriggerEvent(
            type: .chargingStarted,
            subject: TriggerType.chargingStarted.rawValue,
            confidence: 1.0
        ))
    }
}
