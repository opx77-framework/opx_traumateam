# opx_traumateam

The Trauma Team job: service and uniform at a station, calls from downed players, revive and treat, and Silver / Gold / Platinum subscriptions (7 days, no auto-renewal).

## Install
- Needs: `opx_core`, `opx_menu`, `opx_dialog`. Load after them, preferably after `opx_medical`, `opx_society`, `opx_progress`, `opx_target` (optional; without the medical provider there are no calls and no revive, without target no eye options).
- Creates its table at start (MySQL, same database as opx_core).
- Give the job: `setjob <id> traumateam <grade>`.
- The station and kiosk points were not walked: check them in game.

## In game
- `E` at the station (Vik's clinic): subscriptions; members also get service, uniform and management (boss grade).
- `E` at the kiosk (Kabuki Market): subscriptions only.
- `/tt` or the eye on yourself (on duty): list the open calls; Enter takes or drops one (GPS route).
- Eye on another player (on duty): Revive a downed player (8 s) or Treat a living one (4 s). The patient is billed, his plan covers part of a revive.

## Config
`config.lua`: `locale` (job labels, set it like opx_core's), `grades`, `revive` / `treat` fees, `tiers`. Everything else is commented in the file.

## For developers
- `GetSubscription(sourceOrCitizenId)` → `{ tier, label, expiresAt, priority }` or nil
- `GetTiers()` → plans in menu order
- `IsOnDuty(source)` → boolean
- `GetDispatch()` → open calls, best plan first, then oldest
- Events: `opx:traumateam:subscribed`, `:revived`, `:treated`, `:duty` (see `types.lua`).
- A replacement keeps the job name `traumateam` (type `ems`), these exports and events. Full contract: `types.lua`.
