# Implementation Status — Just Gentle Reminders

Last updated: 2026-05-03

---

## 1. Fully Working

### Time-based reminders
- All time-based reminders schedule via `UNCalendarNotificationTrigger`.
- Daily/weekly/occasional cadences, quiet hours, adaptive time windows — all active.
- Midnight daily reset for repeating reminders.

### Morning first unlock
- Detects app foreground during morning window (after quiet hours end, before 11 AM).
- Fires `morningFirstUnlock` trigger event once per day.
- Routes through full trigger → plan → schedule chain.
- This is documented as a foreground heuristic, not direct phone unlock detection.

### App open
- Detects `UIApplication.didBecomeActiveNotification`.
- Fires `appOpen` trigger events through the same trigger → plan → schedule chain.
- Works while the app is launched/foregrounded; it does not claim third-party app-open detection.

### Notification actions
- "Done" marks reminder complete, records positive feedback.
- "Maybe Later" delays next nudge, records skip interaction.
- Opened (tap) records positive signal.
- Dismissed records ignored interaction.

### Notification permission flow
- Requested at app launch; re-prompted from Settings.
- Permission state persisted in `AppSettings.permissionStates`.
- Denied permission → reminders show `missingPermission` plan status.

### Charging trigger (`IOSDeviceContextAdapter`)
- `UIDevice.current.isBatteryMonitoringEnabled = true` on app launch.
- `UIDevice.batteryStateDidChangeNotification` observed.
- Only fires on TRANSITION into `.charging` or `.full` (not `.charging → .full`).
- Routes `TriggerEvent(type: .chargingStarted)` through `AppState.recordTriggerEvent`.
- Cooldown: 1 hour per reminder.
- **iOS limitation:** Only fires when the app is active or backgrounded (not terminated).

### Location geofencing (`IOSLocationTriggerAdapter`)
- `CLCircularRegion` registered per location alias (up to 20).
- `didEnterRegion` → `geofenceEnter` trigger event.
- `didExitRegion` → `geofenceExit` trigger event.
- Region monitoring persists across app restarts (iOS geofence persistence).
- Regions reconciled on launch, alias save, reminder add/delete.
- **Requires `Always` authorization** for background delivery.
- **With only `WhenInUse`:** geofences fire when app is foregrounded.

### Triggered notifications fire immediately
- When a trigger event matches a reminder, `NotificationPlanner` schedules the notification
  at `now + 5 seconds` (not at the next preferred time window).
- Quiet hours still respected: if currently quiet, fire shifts to next non-quiet window.
- Daily cap still respected.
- In-app banner is shown immediately via `checkForDueNudges()` call after trigger.

### Delete/cancel
- Cancels `UNNotificationRequest` for the reminder.
- Removes trigger event log, nudge history, and user feedback entries.
- Reconciles geofence regions (unregisters unused regions).

### App restart reconciliation
- Expired/unplanned reminders are replanned on launch.
- Location permission state is refreshed.
- Geofence regions are re-reconciled with current aliases and reminders.
- Charging adapter starts fresh with current battery state as baseline.

---

## 2. Working With Setup

### Home / Work / Gym / Gas Station / custom location aliases
- Settings → Places normalizes default aliases during settings decode/onAppear, not during SwiftUI rendering.
- Settings → Places → "Set current location" captures current GPS coordinate.
- After saving, `reconcileLocationTriggers()` replans pending reminders and registers geofences.
- A reminder like "Eve varınca çöpleri çıkar" shows `missingLocationAlias` until Home is set.
- A reminder like "Benzin alınca fişi sakla" becomes a `gas_station` arrival trigger and shows `missingLocationAlias` until Gas Station is set.

### Notification permission
- Must be granted for any reminder to fire.
- Shown in Settings if not yet granted.

### Location permission (`Always`)
- Requested at first launch.
- Without `Always`, geofences only fire while the app is foregrounded.
- Permission state stored and surfaced in `missingPermission` plan status.

---

## 3. Simulated / Testable Only

### `TriggerEventSimulator`
- `morningFirstUnlock()`, `chargingStarted()`, `carPlayConnected/Disconnected()` — test-only.
- Used in `ReminderEngineTests` for unit-level coverage without hardware.
- Real adapters exist in production; simulators remain valid for CI.

---

## 4. Requires Future Adapter / Integration

| Trigger | Reason | Fallback |
|---------|--------|---------|
| Spotify opened / music started | iOS cannot reliably detect arbitrary Spotify launch or arbitrary media start locally | Future integration or Shortcut/deep link |
| Headphones connected | Needs adapter/Shortcut integration for reliable device context | Shortcut or future adapter |
| Laptop open | iOS cannot detect laptop state without companion app or Bluetooth proximity | Companion app (macOS) or manual one-tap confirm |
| Car Bluetooth / CarPlay connected or disconnected | Needs CarPlay hardware or Bluetooth device pairing adapter | Shortcut or future adapter |
| Bluetooth connected/disconnected | Framework exists; needs specific device pairing UI | Pending |
| Calendar event ended | Requires EventKit permission + calendar adapter | Manual or Shortcuts |
| Workout ended | Requires HealthKit/Fitness integration | Manual |
| Wi-Fi connected | `NEHotspotHelper` (requires special entitlement) or `Network.framework` | Pending |

---

## 5. Known iOS Platform Limitations

| Limitation | Impact |
|-----------|--------|
| `batteryStateDidChangeNotification` not delivered to terminated app | Charging trigger only works when app is active or backgrounded |
| Geofence events not delivered to terminated app without `Always` permission | Background geofencing requires `Always` authorization |
| Maximum 20 monitored CLCircularRegion | With >20 geofence reminders, oldest/lowest-priority aliases are dropped |
| Geofence accuracy 50–200 m | May not fire precisely at boundary; acceptable for most use cases |
| `requestAlwaysAuthorization` shows two-step dialog on iOS 13+ | User may initially grant `WhenInUse` only; app handles this gracefully |
| Background app refresh can be disabled by user | May reduce reliability of geofence delivery |

---

## 6. Engineering Guardrails

SwiftUI render paths are intentionally side-effect free. `body`, render-time helper methods, and binding factories must not append aliases, save settings, reconcile geofences, request permissions, start adapters, or schedule/cancel notifications. Settings place aliases are normalized in decode/onAppear and updated only through explicit user actions.
