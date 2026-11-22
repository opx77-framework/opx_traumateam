resource "opx_traumateam"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

-- OPX//77 Trauma Team: the `traumateam` job (grades, duty, uniform), calls from downed players (dispatch),
-- revive and treat in the targeting eye, and Silver / Gold / Platinum subscriptions (table
-- opx_traumateam_subscriptions). The downed state, the calls and the revive itself belong to the `medical`
-- provider (opx_core Config.providers.medical); the boss menu to the `society` provider; the bar to the
-- `progress` provider; the eye options to the `target` provider. None of them is a manifest dependency:
-- every one is asked at runtime and the job degrades when one is absent.
-- opx_menu and opx_dialog are dependencies because require('@...') only loads a declared, running one.
dependencies {
    "opx_core",
    "opx_menu",
    "opx_dialog",
}

permissions {
    "database.access",      -- server: opx_traumateam_subscriptions (schema, load at start, writes)
    "network.events",       -- both: requests to the server, answers to the client
    "players.life.read",    -- server: Open77.players.isDead (medic alive, patient down / alive)
    "players.stats.apply",  -- server: Open77.stats.restoreHealth (treat)
    "players.damage.apply", -- older spelling of players.stats.apply, still checked by some builds
    "input.actions",        -- client: RegisterKeyMapping / Open77.input.keyFor (the station key)
    "ui.vanilla.map",       -- client: Open77.blips (stations, kiosks, the route to a call)
    "http.request", -- server: Open77.http.get (update check, Config.versionCheck)
}

shared_script "config.lua"

-- No `require` on the server: the files share globals (TT, Db, Subs, Dispatch, Care), loaded in this order.
server_scripts {
    "server/db.lua",
    "server/subscriptions.lua",
    "server/dispatch.lua",
    "server/care.lua",
    "server/main.lua",
    "server/version.lua",
}

client_script "client/main.lua"

files {
    "client/modules/*.lua",
    "locales/*.json",
}
