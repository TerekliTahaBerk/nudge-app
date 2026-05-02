import Foundation
import CoreLocation

// MARK: - Protocol

protocol LocationTriggerAdapter: AnyObject {
    var onTriggerEvent: ((TriggerEvent) -> Void)? { get set }
    var onPermissionChange: ((PermissionStatus) -> Void)? { get set }
    var currentAuthorizationStatus: PermissionStatus { get }
    func requestPermission()
    func reconcile(aliases: [LocationAlias], reminders: [Reminder])
}

// MARK: - IOSLocationTriggerAdapter
// Manages CLCircularRegion monitoring for named location aliases.
// Region identifier format: "JGR_GEOFENCE_<aliasname>"
//
// iOS requirements:
// - .authorizedAlways is needed for background geofence delivery.
// - .authorizedWhenInUse only delivers geofence events while the app is foregrounded.
// - iOS limits monitored regions to 20; reconcile() takes the first 20 candidates.
// - Geofences survive app restart: iOS re-delivers pending region events on next launch.

final class IOSLocationTriggerAdapter: NSObject, LocationTriggerAdapter {

    var onTriggerEvent: ((TriggerEvent) -> Void)?
    var onPermissionChange: ((PermissionStatus) -> Void)?

    private let manager = CLLocationManager()
    private let regionPrefix = "JGR_GEOFENCE_"
    private let maxRegions = 20

    override init() {
        super.init()
        manager.delegate = self
    }

    var currentAuthorizationStatus: PermissionStatus {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied, .restricted:                    return .denied
        default:                                      return .unknown
        }
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    // Idempotent reconciliation. Safe to call on every reminder add/remove/launch.
    func reconcile(aliases: [LocationAlias], reminders: [Reminder]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else { return }

        // Only aliases actively referenced by geofence trigger reminders need a region.
        let usedAliasNames = Set(
            reminders.compactMap { $0.triggerDefinition?.condition.locationAlias }
        )

        // Only register aliases that have coordinates.
        let candidates = aliases.filter {
            $0.latitude != nil && $0.longitude != nil && usedAliasNames.contains($0.name)
        }

        let desiredIDs = Set(candidates.prefix(maxRegions).map { regionPrefix + $0.name.lowercased() })

        // Remove stale regions no longer needed.
        for region in manager.monitoredRegions.compactMap({ $0 as? CLCircularRegion })
            where !desiredIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }

        // Register new regions (skip if already monitored — idempotent).
        let existingIDs = Set(manager.monitoredRegions.compactMap { ($0 as? CLCircularRegion)?.identifier })
        for alias in candidates.prefix(maxRegions) {
            let regionID = regionPrefix + alias.name.lowercased()
            guard !existingIDs.contains(regionID) else { continue }
            guard let lat = alias.latitude, let lon = alias.longitude else { continue }

            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                radius: alias.radiusMeters,
                identifier: regionID
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func aliasName(from regionIdentifier: String) -> String {
        String(regionIdentifier.dropFirst(regionPrefix.count))
    }
}

// MARK: - CLLocationManagerDelegate

extension IOSLocationTriggerAdapter: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onPermissionChange?(currentAuthorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let r = region as? CLCircularRegion,
              r.identifier.hasPrefix(regionPrefix) else { return }
        onTriggerEvent?(TriggerEvent(
            type: .geofenceEnter,
            subject: aliasName(from: r.identifier),
            confidence: 1.0
        ))
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let r = region as? CLCircularRegion,
              r.identifier.hasPrefix(regionPrefix) else { return }
        onTriggerEvent?(TriggerEvent(
            type: .geofenceExit,
            subject: aliasName(from: r.identifier),
            confidence: 1.0
        ))
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        DebugLog.trigger("Geofence monitoring failed for \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DebugLog.trigger("Location manager error: \(error.localizedDescription)")
    }
}
