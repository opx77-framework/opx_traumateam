-- Subscriptions in opx_traumateam's own MySQL table. Loaded whole at start (expired rows deleted first), then
-- the memory is the authority: every change is written right away in callback form (never yields, so the
-- exports stay synchronous). Nothing is left to flush at stop.

Db = { ready = false }

local SCHEMA = [[CREATE TABLE IF NOT EXISTS opx_traumateam_subscriptions (
	citizen_id VARCHAR(32) NOT NULL PRIMARY KEY,
	tier VARCHAR(16) NOT NULL,
	expires_at BIGINT NOT NULL,
	updated_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

-- Unix seconds as an integer (0 when the clock cannot answer).
function Db.now()
	local ok, t = pcall(Open77.time.unix)
	t = ok and tonumber(t) or nil
	if not t or t ~= t or t == math.huge or t == -math.huge or t < 0 then return 0 end
	return math.tointeger(math.floor(t)) or 0
end

-- One statement in callback form; a refusal or a failure is logged.
local function run(sql, params, what)
	if not Db.ready then
		print(('[opx_traumateam] %s not written: database not ready'):format(what))
		return
	end
	local ok, refused, reason = pcall(Open77.database.update, sql, params, function(_, failure)
		if failure then print(('[opx_traumateam] %s failed: %s'):format(what, tostring(failure))) end
	end)
	-- A refusal (false, reason) also reaches the callback above; only a raise needs its own line.
	if not ok then print(('[opx_traumateam] %s refused: %s'):format(what, tostring(refused or reason))) end
end

-- Writes one plan { tier, expiresAt, updatedAt } of a character.
function Db.save(citizenId, sub)
	if type(citizenId) ~= 'string' or type(sub) ~= 'table' then return end
	run([[INSERT INTO opx_traumateam_subscriptions (citizen_id, tier, expires_at, updated_at) VALUES (?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE tier = VALUES(tier), expires_at = VALUES(expires_at), updated_at = VALUES(updated_at)]],
		{ citizenId:sub(1, 32), tostring(sub.tier):sub(1, 16), sub.expiresAt, sub.updatedAt }, 'subscription write')
end

function Db.delete(citizenId)
	if type(citizenId) ~= 'string' then return end
	run('DELETE FROM opx_traumateam_subscriptions WHERE citizen_id = ?', { citizenId:sub(1, 32) }, 'subscription delete')
end

-- Schema, purge of the expired rows, then every row: done(rows) with rows = { [citizenId] = { tier, expiresAt,
-- updatedAt } } (unknown tiers kept out). Waits 1.5 s first: after a hot reload, the previous VM's last
-- writes were just sent.
function Db.start(done)
	if type(Open77.database) ~= 'table' then
		return print('[opx_traumateam] no database bridge: subscriptions disabled (enable the database, database.access)')
	end
	local queued, reason = Open77.database.ready(function()
		Open77.database.update(SCHEMA, {}, function(_, failure)
			if failure then return print(('[opx_traumateam] schema failed: %s'):format(tostring(failure))) end
			Open77.database.update('DELETE FROM opx_traumateam_subscriptions WHERE expires_at <= ?', { Db.now() },
				function()
					Open77.database.query('SELECT citizen_id, tier, expires_at, updated_at FROM opx_traumateam_subscriptions',
						{}, function(rows, why)
							if why or type(rows) ~= 'table' then
								return print(('[opx_traumateam] subscriptions not loaded: %s'):format(tostring(why)))
							end
							local out = {}
							for _, row in ipairs(rows) do
								local expiresAt = math.tointeger(tonumber(row.expires_at) or 0)
								if type(row.citizen_id) == 'string' and Config.tiers[row.tier] and expiresAt then
									out[row.citizen_id] = {
										tier = row.tier, expiresAt = expiresAt,
										updatedAt = math.tointeger(tonumber(row.updated_at) or 0) or 0,
									}
								end
							end
							Db.ready = true
							done(out)
						end)
				end)
		end)
	end)
	if not queued then print(('[opx_traumateam] database unavailable: %s'):format(tostring(reason))) end
end
