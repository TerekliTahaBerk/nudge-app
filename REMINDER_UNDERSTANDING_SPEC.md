# Reminder Understanding Spec

## Architecture

Reminder understanding is local, deterministic, and privacy-first. `ReminderUnderstandingEngine.parse(...)` sanitizes input, runs the grammar layer, and returns a `ParsedReminderIntent` that is immediately persisted into `Reminder.schedule` and `Reminder.triggerDefinition`.

The grammar layer is split into small parsers:

- `TurkishNormalizer` and `EnglishNormalizer` normalize case, diacritics, punctuation, apostrophes, no-diacritic Turkish, and Turkish number words.
- `ReminderIntentGrammar` separates trigger, action, time, recurrence, place, and device/context clauses.
- `TimeExpressionParser` resolves relative offsets, relative days, weekdays, and approximate day windows.
- `RecurrenceParser` converts repeat language into `ReminderRecurrenceRule`.
- `PlaceExpressionParser` converts arrival/exit language into geofence trigger metadata.
- `DeviceContextExpressionParser` maps local device signals and unsupported contexts.

No cloud AI or external parsing service is used.

## Supported Time And Date Expressions

Turkish:

- `bugün`
- `yarın`
- `yarın sabah`
- `bu akşam`
- `akşama doğru`
- `öğleden sonra`
- `cuma günü`
- `gelecek cuma`
- `haftaya`
- `20 dakika sonra`
- `2 saat sonra`
- No-diacritic variants such as `bugun`, `yarin sabah`, `aksam`, `ogleden sonra`

English:

- `today`
- `tomorrow`
- `tomorrow morning`
- `tonight`
- `this evening`
- `Friday`
- `next Friday`
- `next week`
- `in 20 minutes`
- `in 2 hours`

Relative offsets resolve at parse time using the provided `now` value. Production uses `.now`; tests inject fixed dates.

## Recurrence Rules

Supported recurrence expressions:

- `her sabah`
- `her akşam`
- `iki günde bir`
- `haftada 3 kez`
- `ayda bir`
- `every morning`
- `every evening`
- `every other day`
- `3 times a week`
- `once a month`

Confident recurrence rules override default cadence. The planner uses the recurrence rule and preferred window directly instead of falling back to category defaults.

## Places And Context

Built-in and custom place aliases are first-class trigger subjects:

- Home: `eve gelince`, `eve varınca`, `evden çıkınca`
- Work/office: `işe gidince`, `işe varınca`, `işten çıkınca`, `ofise gidince`
- Gym: `spora gidince`, `spor salonuna gidince`, `spordan çıkınca`
- Custom categories: market, pharmacy/eczaneye, school/okul, office/ofis, cafe/kafe, doctor/doktor, hospital/hastane

Place metadata includes `normalizedAlias`, `displayAlias`, `placeCategory`, `sourcePhrase`, and `pendingLocationAlias`. If the location has not been saved, the reminder remains pending setup and is not converted to a generic time reminder.

Device/context support:

- App open: actionable local foreground trigger using app lifecycle events.
- Morning first unlock: modeled honestly as the first morning app foreground after quiet hours, not direct phone unlock detection.
- Charging started: actionable local trigger.
- Gas station/fuel stop: modeled as gas station arrival and remains pending until the `gas_station` alias is saved.
- Car enter/exit: understood as car Bluetooth/CarPlay context, future adapter or Shortcut setup required.
- Headphones connected: understood, future adapter or Shortcut setup required.
- Wi-Fi/home Wi-Fi connected: understood, future adapter or Shortcut setup required.
- Meeting ended: understood, requires future EventKit adapter and calendar permission before it can fire.
- Workout ended: understood, requires future fitness adapter and permission before it can fire.
- Spotify/music started: understood, but not locally actionable without a future integration or Shortcut setup.
- Laptop opened: unsupported without future companion setup.

## Scheduling Behavior

Grammar output directly controls behavior:

- `exactDate` schedules at that date/time.
- Relative offsets schedule at `now + offset`.
- `approximateWindow` strongly constrains the planner to that window and date.
- `recurrenceRule` controls recurring cadence.
- Confident trigger clauses force event-based reminders.
- Pending setup, missing permission, and unsupported contexts block time-based scheduling.

Every plan stores an explanation that reflects the grammar interpretation, such as “Scheduled in 20 minutes,” “Scheduled for tomorrow morning,” “Repeats every morning,” or “Laptop triggers need a future companion setup.”

## Conflict Handling

When multiple reminders want the same delivery window, the app resolves the conflict locally and deterministically. The priority score considers urgency words, parser confidence, due proximity, matching event-trigger relevance, recent fatigue, and learned rhythm preference.

Same-window behavior:

- Reminders due within the same 15-minute window compete.
- The highest-priority reminder keeps the earliest slot.
- Lower-priority reminders are staggered after it.
- Delayed reminders use the explanation “Delayed because another reminder was more timely.”

Same-trigger behavior:

- If several reminders match the same event, such as home arrival, gym exit, or charging started, the event is handled as one conflict group.
- One reminder is scheduled immediately.
- Remaining matching reminders are staggered instead of all firing at once.

Quiet hours precedence:

- Quiet-hours movement happens before conflict staggering.
- If multiple reminders resolve to the first non-quiet time, the same priority and stagger rules apply there.

Conflict stability:

- A delayed reminder stores its conflict group key, anchor reminder id, resolved fire date, resolved rank, and resolved-at timestamp.
- Later planner calls, repeated scheduling, or app relaunch reconciliation reuse the stored resolved slot for the same conflict group.
- Conflict handling must not create an infinite replan loop or keep pushing the same reminder later.

## Confidence And Ambiguity

Confidence is composable. It considers:

- Grammar structure match
- Clean action clause
- Known place alias
- Exact trigger verb
- Known time expression
- Known recurrence expression
- Unsupported context penalty
- Missing setup/permission penalty
- Ambiguous or low-confidence clause penalty

Tiers:

- High: normal execution.
- Medium: execution with lower confidence and wider time windows.
- Low: pending setup, unsupported fallback, or clarification; no silent scheduling.

## Examples

| Input | Interpretation | Behavior |
| --- | --- | --- |
| `20 dakika sonra ilacı al` | Relative time + action | Schedules about 20 minutes from now |
| `Yarın sabah su iç` | Tomorrow + morning window | Schedules tomorrow morning |
| `Her sabah su iç` | Daily recurrence + morning window | Recurring morning reminder |
| `Spordan çıkınca protein iç` | Gym exit trigger | Event-based, waits for gym exit setup/event |
| `Sarja takinca su ic` | Charging started trigger | Event-based local device trigger |
| `Uygulamayı açınca su iç` | App foreground trigger | Event-based local app lifecycle trigger |
| `Markete gidince süt al` | Market arrival trigger | Pending market alias, no time fallback |
| `Benzin alınca fişi sakla` | Gas station arrival trigger | Pending gas station alias, no time fallback |
| `Spotify’ı açınca su iç` | Spotify context | Future integration/Shortcut required, no time fallback |
| `Laptopu açınca raporu gönder` | Unsupported laptop context | Unsupported/pending companion setup, no schedule |
| `20 dakika sonra acil raporu gönder` + `20 dakika sonra su iç` | Same-window conflict | Urgent reminder goes first; water is staggered |
| Two home-arrival reminders | Same trigger conflict | One fires on arrival; the rest are staggered |
| Quiet-hours conflict | First non-quiet window conflict | Winner moves to first non-quiet time; others stagger |
| Repeated schedule/relaunch | Existing conflict metadata | Resolved stagger order is preserved |

## SwiftUI Render Purity

SwiftUI render paths must stay side-effect free. `body`, `@ViewBuilder` computed properties, and binding helpers used during rendering must not append aliases, save settings, reconcile geofences, start adapters, schedule/cancel notifications, or request permissions. Settings place aliases are normalized during settings decode and `SettingsView.onAppear`; row bindings only read/update existing aliases.
