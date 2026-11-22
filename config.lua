Config = {}

-- Language of the job and grade labels registered in opx_core ('en' or 'fr'). Set it like opx_core's
-- Config.locale: the server cannot read locales/*.json, so these two labels are chosen here.
Config.locale = 'en'

-- Job name registered in opx_core (a contract with other resources: keep 'traumateam'). Its type is 'ems',
-- which makes on-duty holders the responders counted by the medical provider.
Config.job = 'traumateam'
Config.jobType = 'ems'
Config.jobLabel = { en = 'Trauma Team', fr = 'Trauma Team' }

-- Grades from 0 up: name (id), label (en / fr), salary per paycheck (opx_core Config.paycheck).
-- bossGrade: the grade that gets "Management" (boss menu of the society provider) at the station.
Config.grades = {
	[0] = { name = 'recruit', label = { en = 'Recruit', fr = 'Recrue' }, salary = 60 },
	[1] = { name = 'paramedic', label = { en = 'Paramedic', fr = 'Ambulancier' }, salary = 90 },
	[2] = { name = 'doctor', label = { en = 'Doctor', fr = 'Médecin' }, salary = 120 },
	[3] = { name = 'chief', label = { en = 'Chief', fr = 'Chef' }, salary = 150 },
}
Config.bossGrade = 3

-- true: a character always starts his session off duty (he clocks in at a station).
Config.dutyOffOnLoad = true

-- Stations: duty, uniform, boss menu (employees) and subscriptions (everyone). radius in metres (horizontal),
-- bucket = routing bucket. Point next to the official Vik's clinic spawn: walk it in game and adjust.
Config.stations = {
	{ label = "Trauma Team - Vik's Clinic", x = -1546.0, y = 1236.0, z = 11.6, radius = 2.5, bucket = 0 },
}

-- Kiosks: subscriptions only. Point from the official rp pack (Kabuki Market).
Config.kiosks = {
	{ label = 'Trauma Team kiosk - Kabuki Market', x = -1223.91, y = 1989.45, z = 7.98, radius = 2.5, bucket = 0 },
}

-- Vertical tolerance (metres): the configured z is approximate.
Config.heightTolerance = 4.0

-- Extra metres the server accepts on top of a radius or a care distance (its position snapshot can lag).
Config.serverSlack = 2.0

-- Default key used at a station or kiosk (players can rebind it: Settings > Key bindings).
Config.key = 'E'

-- Uniform: a temporary outfit per body family (slots Head, Face, InnerChest, OuterChest, Legs, Feet, Outfit;
-- a value is an item record or false to hide the slot), put on by the skin provider (SetUniform; without one,
-- open77_appearance setTemporaryOutfit directly). false = no uniform row.
-- The saved look is never written; taking it off (or ending the service) brings it back.
Config.uniform = {
	male = { Outfit = 'Items.Trauma_Team_Outfit' },
	female = { Outfit = 'Items.Trauma_Team_Outfit' },
}

-- Revive a downed player (eye option on players, medic on duty).
--   fee: billed to the patient (bank first, then cash; what he has, never a debt), share covered by his plan
--   seconds: length of the action; distance: metres between medic and patient; health: fraction after it
--   (a plan's reviveHealth wins); medicBonus: paid from the society to the medic's bank when it can afford it
--   animation: open77_animations profile; item: an opx_inventory item the medic uses up (false = none)
Config.revive = { fee = 300, seconds = 8, distance = 3.0, health = 0.5, medicBonus = 100, animation = 'examine', item = false }

-- Treat a living player: health back to full. Never covered by a plan.
Config.treat = { fee = 100, seconds = 4, distance = 3.0, animation = 'examine' }

-- Subscriptions, 7 real days each. priority: lower = higher in the medics' call list.
-- reviveCoverage: share of the revive fee paid by the plan; respawnCoverage: share of the hospital bill
-- (medical provider); reviveHealth: health fraction after a Trauma Team revive.
Config.tiers = {
	silver = { label = 'Silver', price = 1000, days = 7, priority = 3, reviveCoverage = 0.5, respawnCoverage = 0.5, reviveHealth = 0.5 },
	gold = { label = 'Gold', price = 2500, days = 7, priority = 2, reviveCoverage = 1.0, respawnCoverage = 1.0, reviveHealth = 0.75 },
	platinum = { label = 'Platinum', price = 6000, days = 7, priority = 1, reviveCoverage = 1.0, respawnCoverage = 1.0, reviveHealth = 1.0 },
}
-- Order of the tiers in the menu.
Config.tierOrder = { 'silver', 'gold', 'platinum' }

-- Priority of a call from somebody without a plan.
Config.uninsuredPriority = 9

-- How many periods of the same plan can be paid ahead (the current one included).
Config.maxPrepaidPeriods = 4

-- Command that opens the medic menu (the open calls). false = no command (the eye on yourself still works).
Config.command = 'tt'

-- Stations and kiosks on the map (Open77.blips) while a character is loaded.
Config.blips = true

-- Minimum milliseconds between two requests of one player (anything faster is ignored).
Config.rateLimitMs = 500

-- Update check at start: compares this version with the one published on GitHub and prints a line in the
-- server console when an update is out. Needs outbound HTTP in server.jsonc ("http": "enabled": true, with
-- "raw.githubusercontent.com" in "allowedHosts"). false = no request.
Config.versionCheck = true
