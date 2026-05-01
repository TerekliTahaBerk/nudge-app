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
  - Confirm the simulated `morning_first_unlock` event can produce a scheduled plan once per day.
- Charging trigger:
  - `charging_started` is currently supported through `TriggerEventSimulator` / future adapter input only.
  - Do not claim hardware charging detection in UI until a reliable adapter is added.
- Geofence readiness:
  - Create `Eve varınca çöpleri çıkar`.
  - If Home is not defined or location permission is absent, confirm the reminder is saved with `missingLocationAlias` or `missingPermission`, not silently dropped.

## Manual Scenarios

### Create normal reminder

1. Add `Read a page`.
2. Save.
3. Confirm it appears in the list and has either a scheduled plan or a clear not-scheduled reason in DEBUG summary.

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
