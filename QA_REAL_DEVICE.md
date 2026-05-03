# Real Device QA Checklist

This checklist is for real-device readiness only. Keep the app calm and unchanged unless a setup or error state would otherwise be invisible.

## Device Setup

- Install a fresh build on a physical iPhone.
- Confirm notification permission prompt appears during onboarding or first launch.
- Test once with notifications allowed and once with notifications denied.
- Confirm quiet hours are set to `23:00-08:00` unless intentionally changed.
- Leave the app, lock the phone, and verify pending local notifications can appear while the app is backgrounded.

## Platform Readiness

- Notification permission:
  - Allowed: reminders with scheduled plans create pending local notifications.
  - Denied: event/time reminders remain saved and expose a `missingPermission` readiness reason internally.
- Background notification scheduling:
  - Create a normal reminder, background the app, and confirm a local notification appears near the planned time.
  - Tap Done and Maybe later actions from the notification.
- Morning first unlock heuristic:
  - Create a reminder such as `Sabah telefonu açınca meditasyon yap`.
  - Relaunch/foreground the app between quiet-hours end and 11:00.
  - Confirm the `morning_first_unlock` event can produce a scheduled plan once per day.
  - Confirm UI copy does not claim direct phone unlock detection; this is a morning foreground heuristic.
- App open trigger:
  - Create `Uygulamayı açınca su iç`.
  - Background and foreground the app.
  - Confirm the `app_open` event produces a scheduled plan and does not require a fake external signal.
- Charging trigger (real adapter — `IOSDeviceContextAdapter`):
  - `UIDevice.isBatteryMonitoringEnabled` is enabled at app launch.
  - Plug charger in while app is active or backgrounded — notification must fire within 10 seconds.
  - Unplug and re-plug within 1 hour — no second notification (cooldown active).
  - `.charging → .full` transition (already on charger) must NOT re-fire.
  - Force-quit app, plug charger — no notification (iOS limitation; document honestly).
- Geofence readiness:
  - Create `Eve varınca çöpleri çıkar`.
  - If Home is not defined or location permission is absent, confirm the reminder is saved with `missingLocationAlias` or `missingPermission`, not silently dropped.

## Manual Scenarios

### Create normal reminder

1. Add `Read a page`.
2. Save.
3. Confirm it appears in the list and has either a scheduled plan or a clear not-scheduled reason in DEBUG summary.

### Add button reachability

1. Add enough reminders to make the Today list scroll.
2. Confirm `Add a reminder` stays visible and tappable at the bottom.
3. Rotate through short and long reminder text.
4. Confirm the button does not jump as the list grows and remains above the home indicator.

### Many reminders scrolling

1. Create or seed 30+ reminders.
2. Scroll from top to bottom and back.
3. Confirm rows keep comfortable spacing, long text wraps, no row overlaps the sticky Add control, and the bottom-most reminder can be fully read.

### Edit reminder text

1. Tap an existing reminder row.
2. Change the reminder text.
3. Tap `Save`.
4. Confirm the same row updates in place and no duplicate reminder appears.
5. Confirm any pending notification for the old text is cancelled and a new plan exists where appropriate.

### Edit reminder kind

1. Tap a normal time-based reminder.
2. Change it to `When something happens`, choose Home/Work/Gym or type an event phrase.
3. Save.
4. Confirm the same reminder ID is updated, the old time notification is cancelled, and trigger/geofence readiness is shown.
5. Edit the same reminder back to `A reminder`.
6. Confirm trigger/geofence registration is removed if no other reminder uses it and the reminder schedules as time-based.

### Cancel edit

1. Tap a reminder row.
2. Change text, kind, cadence, or setup fields.
3. Tap `Cancel`.
4. Confirm the row remains unchanged and no new notification/geofence changes are made.

### Remove reminder

1. Swipe a reminder row to reveal `Remove`.
2. Tap `Remove`.
3. Confirm the row disappears, notification request is cancelled, trigger logs/history for that reminder are removed, and global rhythm data remains.

### Undo remove

1. Remove a reminder.
2. If the quiet `Removed · Undo` receipt appears, tap `Undo`.
3. Confirm the same reminder returns and is replanned/re-registered as needed.

### Keyboard and sheet behavior

1. Open Add Reminder and paste a long paragraph with emoji and Turkish characters.
2. Rapidly type, delete, paste, and clear the field.
3. Confirm the input remains visible, Save/Cancel remain reachable, content scrolls when tall, and no crash occurs.
4. Repeat while editing an existing reminder.

### Pending setup row

1. Create `Eve varınca çöpleri çıkar` without Home saved.
2. Confirm the Today row says `Needs Home location`.
3. Tap the row and confirm the edit sheet repeats the setup state with a route to Settings.
4. Return after setting Home and confirm the reminder becomes `Waiting for trigger`.

### Create Leave it to me reminder

1. Add `Drink water`.
2. Keep `Leave it to me`.
3. Save.
4. Confirm the planned window is morning or afternoon, outside quiet hours.

### Create Turkish event reminder

1. Add `Spor salonundan ayrılınca protein iç`.
2. Confirm the kind switches/suggests `When something happens`.
3. Save.
4. Confirm the trigger is `geofence_exit` with `gym` alias and either waits for setup or permission.

### Maybe later

1. Trigger or wait for an in-app nudge.
2. Tap `Maybe later`.
3. Confirm the reminder is not marked done and the next plan is delayed.

### Done

1. Tap Done on a reminder row or notification.
2. Confirm the reminder is marked done and future timing preference is positively updated.

### Delete reminder

1. Delete a reminder with a pending plan.
2. Confirm its notification request is cancelled and trigger/history/feedback references are removed.

### App relaunch

1. Create one time-based reminder and one event-based reminder.
2. Force quit and reopen.
3. Confirm reminders, rhythm profile, trigger definitions, pending plans, permission states, and last morning unlock date reload safely.

### Notification permission denied

1. Deny notification permission.
2. Create `Drink water`.
3. Confirm the reminder remains saved and internally reports `missingPermission` rather than crashing or pretending delivery is scheduled.

### Quiet hours

1. Set quiet hours to include the current time.
2. Create a reminder.
3. Confirm no notification is planned inside quiet hours; the plan should move to the next allowed window or report a clear reason.

---

## Charging Trigger (Real Device)

1. Create `Şarja takınca su iç`.
2. Ensure notification permission is granted.
3. Confirm the reminder is saved with `waitingForTrigger` status (not scheduled to a time window).
4. Plug the device into a charger while the app is open or backgrounded.
5. **Confirm a notification fires within 10 seconds.**
6. Unplug. Wait 30 seconds. Re-plug.
7. Confirm no second notification (1-hour cooldown active).
8. To test cooldown reset: wait 1 hour, then re-plug — notification should fire again.
9. Force-quit the app. Plug charger. Confirm NO notification (iOS limitation — document this).

---

## Location Alias Setup

1. Open Settings → Places.
2. Confirm Home, Work, Gym, and Gas Station each show either `Saved`, `Not set`, or `Location permission denied`.
3. For "Home": tap "Set current location" while physically at home.
4. If permission is denied, confirm the row says location permission is off/denied and fails gracefully.
5. If location fetch fails, confirm a short error appears and the app does not crash.
6. If Home was already saved, tap "Update current location" and confirm the saved state remains.
7. Confirm coordinates are saved and status shows "Saved".
8. Create `Eve varınca çöpleri çıkar`.
9. Confirm reminder status changes from `missingLocationAlias` to `waitingForTrigger` (or `scheduled`).

---

## Home Arrival Geofence

1. Set Home alias (see above).
2. Grant "Always" location permission when prompted.
3. Create `Eve varınca çöpleri çıkar`.
4. Walk or drive away from Home (>200 m beyond the 150 m radius).
5. Return to within the Home radius.
6. **Confirm notification fires within ~30 seconds of entering the region.**
7. Walk out and immediately return (within 1-hour cooldown) — no second notification.
8. Delete the reminder. Confirm the `JGR_GEOFENCE_home` region is unregistered (check via Xcode debug).
9. Force-quit and relaunch the app. Confirm the geofence region is re-registered.

---

## Home Exit Geofence

1. Set Home alias.
2. Create `Evden çıkınca anahtarı al`.
3. Confirm reminder is `waitingForTrigger`.
4. Leave the Home radius.
5. **Confirm notification fires.**

---

## Gym Exit Geofence

1. Set Gym alias at a physical gym (or any known location).
2. Create `Spor salonundan çıkınca protein iç`.
3. Leave the gym radius.
4. **Confirm notification fires.**

---

## Missing Alias (No Coordinates)

1. In Settings → Places, observe Home is "Not set".
2. Create `Eve varınca çöpleri çıkar`.
3. Confirm plan status is `missingLocationAlias`, not `scheduled` or `waitingForTrigger`.
4. Now set the Home alias.
5. Confirm the existing reminder's status updates to `waitingForTrigger`.

---

## Location Permission Denied

1. Deny location permission in iOS Settings.
2. Create `Eve varınca çöpleri çıkar` with Home alias set.
3. Confirm plan status is `missingPermission`.
4. Restore permission. Relaunch app.
5. Confirm plan status updates to `waitingForTrigger`.

---

## Delete Reminder — Geofence Cleanup

1. Create a location-based reminder (e.g., Home arrival).
2. Confirm the `JGR_GEOFENCE_home` region appears in Xcode's CLLocationManager monitor list.
3. Delete the reminder.
4. Confirm the region is removed (no other reminders reference Home).
5. If another reminder also uses Home, confirm the region is KEPT.

---

## App Relaunch — Full Reconciliation

1. Create one time-based reminder, one charging trigger reminder, and one Home arrival reminder.
2. Force-quit the app.
3. Reopen.
4. Confirm:
   - Time-based reminder has a scheduled plan.
   - Charging reminder has `waitingForTrigger` status.
   - Home arrival reminder has `waitingForTrigger` status (if alias + permission set).
   - Geofence region is re-registered.
   - Charging adapter has started (plug charger to verify).
   - No duplicate pending notification requests were created for the same reminder.
   - Permission prompts do not repeat unless initiated from setup/settings.

## Notification After Edit

1. Create a normal reminder with notifications allowed.
2. Edit its text and cadence.
3. Background the app.
4. Confirm the notification uses the edited reminder and the old pending request no longer appears.

## Geofence After Edit

1. Create a Home arrival reminder and confirm `JGR_GEOFENCE_home` is monitored.
2. Edit it to a Work arrival reminder.
3. Confirm Home monitoring is removed if no other reminder uses Home and Work monitoring is registered if Work is saved.
4. Edit it to a normal time-based reminder.
5. Confirm the geofence is unregistered if no remaining reminder references that alias.

---

## Unsupported Triggers (Document Only — No False Activation)

| Input | Expected behavior |
|-------|------------------|
| `Laptopu açınca raporu gönder` | Saved as `unsupported`, `needsClarification = true`. No fake activation. |
| `Spotify’ı açınca su iç` | Saved as `spotify_opened`, future integration/Shortcut required. No generic time fallback. |
| `Müzik çalınca esne` | Saved as `music_started`, future integration/Shortcut required. No generic time fallback. |
| `Kulaklığı takınca su iç` | Saved as `headphones_connected`, future adapter/Shortcut required. |
| `Arabaya binince annemi ara` | Saved as car Bluetooth/CarPlay context, future adapter/Shortcut required. |
| `Wi-Fi’ye bağlanınca notları gönder` | Saved as Wi-Fi context, future adapter/Shortcut required. |
| `Benzin alınca fişi sakla` | Saved as `geofence_enter` for `gas_station`; pending Gas Station alias if not set. |

## SwiftUI Render Purity Regression

1. Open Settings repeatedly on a fresh install with no aliases saved.
2. Confirm Home, Work, Gym, and Gas Station appear without a crash.
3. Navigate away and back several times.
4. Confirm the app does not append duplicate default aliases.
5. Confirm permission prompts only appear after tapping a setup button, never merely from rendering Settings.

---

## Maybe Later

1. Trigger or wait for an in-app nudge.
2. Tap `Maybe later`.
3. Confirm reminder not marked done, plan delayed by 2–8 hours.
4. Confirm "maybe later" receipt banner appears for ~12 seconds.

---

## Low-Confidence Trigger Handling

1. Create `Telefonu açınca bir şey yap` (device unlock — confidence 0.58).
2. Confirm the understanding engine keeps the trigger interpretation instead of silently converting it to a time-based reminder.
3. Confirm low confidence produces clarification, pending setup, unsupported fallback, or a non-scheduled state depending on the trigger.
