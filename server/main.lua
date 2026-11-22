-- Entry: shared helpers (TT), the job registration, the station menu, client requests (validated,
-- rate-limited), exports, the command and the player life cycle.

TT = TT or {}

local CORE = 'opx_core'
local lastCall = {}  -- [source] = GetGameTimer() of his last accepted request
local uniformOn = {} -- [source] = { route, generation } while he wears the uniform we put on

-- Helpers ----------------------------------------------------------------------------------------

-- An integer from a number, or nil.
function TT.int(v) return type(v) == 'number' and math.tointeger(v) or nil end

-- A player id from anything (positive integer within uint32), or nil. Natives abort on anything else.
function TT.toSource(value)
	local id = tonumber(value)
	if not id or id ~= id or id < 1 or id > 0xFFFFFFFF or id % 1 ~= 0 then return nil end
	return math.tointeger(id)
end

-- An opx_core export: its results, or nil, 'core_unavailable' when it raised / is not running.
function TT.core(name, ...)
	local ok, a, b = pcall(Open77.exports.callSync, CORE, name, ...)
	if not ok then return nil, 'core_unavailable' end
	return a, b
end

-- The running resource of a provider slot (opx_core Config.providers), or nil.
function TT.provider(slot)
	local name = TT.core('GetProvider', slot)
	return type(name) == 'string' and name or nil
end

-- Calls an export of a provider: called (false when absent or raised), results...
function TT.callProvider(slot, name, ...)
	local provider = TT.provider(slot)
	if not provider then return false end
	local ok, a, b = pcall(Open77.exports.callSync, provider, name, ...)
	if not ok then
		print(('[opx_traumateam] %s:%s failed: %s'):format(provider, name, tostring(a)))
		return false
	end
	return true, a, b
end

-- PlayerData of a loaded character (not in the creator), or nil.
function TT.character(source)
	if not source then return nil end
	local data = TT.core('GetPlayer', source)
	if type(data) ~= 'table' or type(data.citizenId) ~= 'string' or data.isNew == true then return nil end
	return data
end

-- PlayerData of a loaded Trauma Team member (on duty when `onDuty`), or nil.
function TT.isMedic(source, onDuty)
	local data = TT.character(source)
	local job = data and data.job
	if type(job) ~= 'table' or job.name ~= Config.job then return nil end
	if onDuty and job.onDuty ~= true then return nil end
	return data
end

-- Every on-duty medic (sources).
function TT.onDutyMedics()
	local list = TT.core('GetPlayersByJob', Config.job, true)
	local out = {}
	if type(list) == 'table' then
		for _, id in ipairs(list) do
			local src = TT.toSource(id)
			if src then out[#out + 1] = src end
		end
	end
	return out
end

-- The index of the point of `list` the player stands at (server position + routing bucket), or nil.
function TT.atPoint(source, list)
	local pos = Open77.players.position(source)
	if type(pos) ~= 'table' or type(pos.x) ~= 'number' then return nil end
	for i, point in ipairs(list or {}) do
		local dx, dy = pos.x - point.x, pos.y - point.y
		local reach = (point.radius or 2.5) + Config.serverSlack
		if (point.bucket or 0) == pos.bucket and dx * dx + dy * dy <= reach * reach
			and math.abs(pos.z - point.z) <= Config.heightTolerance then
			return i
		end
	end
	return nil
end

-- Rate limit: false when the player asked again too soon.
function TT.allow(source)
	local now = GetGameTimer()
	local last = lastCall[source]
	if last and now - last < Config.rateLimitMs then return false end
	lastCall[source] = now
	return true
end

-- A locale key + params for the player's client, which translates it and shows it through opx_core Notify.
function TT.notify(source, key, kind, params)
	if not TT.toSource(source) then return end
	pcall(TriggerClientEvent, 'opx_traumateam:notify', source, key, kind or 'info', params or {})
end

-- Job ----------------------------------------------------------------------------------------------

local function localized(value)
	if type(value) == 'table' then return value[Config.locale] or value.en or select(2, next(value)) end
	return value
end

local function registerJob()
	local grades = {}
	for index, grade in pairs(Config.grades) do
		grades[index] = { name = grade.name, label = localized(grade.label), salary = grade.salary }
	end
	local ok, reason = TT.core('RegisterJob', Config.job, {
		label = localized(Config.jobLabel) or 'Trauma Team',
		type = Config.jobType or 'ems',
		defaultDuty = false,
		data = { bossGrade = Config.bossGrade },
		grades = grades,
	})
	if ok ~= true then print(('[opx_traumateam] job not registered: %s'):format(tostring(reason))) end
end

-- Uniform -------------------------------------------------------------------------------------------
-- Through the skin provider (opx_core Config.providers.skin: SetUniform / ClearUniform), which arbitrates the
-- platform's single temporary outfit; without one, open77_appearance setTemporaryOutfit directly.
-- uniformOn[source] = { route, generation }: the resource that put it on (the provider, or APPEARANCE) and its
-- VM, so the same one takes it off and its stop is noticed.

local APPEARANCE = 'open77_appearance'

-- Who dresses: the skin provider name, else APPEARANCE when it runs, else nil.
local function uniformRoute()
	local provider = TT.provider('skin')
	if provider then return provider end
	if GetResourceState(APPEARANCE) == 'running' then return APPEARANCE end
	return nil
end

local function generationOf(resource)
	local ok, generation = pcall(Open77.resource.generation, resource)
	return ok and generation or nil
end

local function clearUniform(source)
	local worn = uniformOn[source]
	if not worn then return end
	uniformOn[source] = nil
	-- Its VM is gone (stop / reload): it took the outfit with it.
	if GetResourceState(worn.route) ~= 'running' or generationOf(worn.route) ~= worn.generation then return end
	local name = worn.route == APPEARANCE and 'clearTemporaryOutfit' or 'ClearUniform'
	local ok, done, reason = pcall(Open77.exports.callSync, worn.route, name, source)
	if not ok or done ~= true then
		print(('[opx_traumateam] uniform of %d not cleared: %s'):format(source, tostring(ok and reason or done)))
	end
end

local function setUniform(source, wear)
	local data = TT.isMedic(source, true)
	if not data then return TT.notify(source, 'not_on_duty', 'error') end
	if not wear then
		clearUniform(source)
		return TT.notify(source, 'uniform_off', 'success')
	end
	local outfit = type(Config.uniform) == 'table' and Config.uniform[data.family] or nil
	local route = uniformRoute()
	if type(outfit) ~= 'table' or not route then
		return TT.notify(source, 'no_uniform', 'error')
	end
	-- One put on through the other route (the provider started / stopped meanwhile) comes off first.
	if uniformOn[source] and uniformOn[source].route ~= route then clearUniform(source) end
	local name = route == APPEARANCE and 'setTemporaryOutfit' or 'SetUniform'
	local ok, done, reason = pcall(Open77.exports.callSync, route, name, source, outfit)
	if not ok or done ~= true then
		return TT.notify(source, 'failed', 'error', { reason = tostring(ok and reason or done) })
	end
	uniformOn[source] = { route = route, generation = generationOf(route) }
	TT.notify(source, 'uniform_on', 'success')
end

-- The resource that dressed someone stopped: the outfit went with it, unless its new VM (hot reload) put it on.
AddEventHandler('onResourceStop', function(name)
	local current = generationOf(name)
	for src, worn in pairs(uniformOn) do
		if worn.route == name and (current == nil or current ~= worn.generation) then uniformOn[src] = nil end
	end
end)

-- Station / kiosk menu ------------------------------------------------------------------------------

-- What the station menu shows to this player: nil when he stands at no point.
local function stationState(source)
	local data = TT.character(source)
	if not data then return nil end
	local station = TT.atPoint(source, Config.stations)
	local kiosk = not station and TT.atPoint(source, Config.kiosks) or nil
	if not station and not kiosk then return nil end
	local point = station and Config.stations[station] or Config.kiosks[kiosk]
	local sub = Subs.get(data.citizenId)
	local state = {
		kind = station and 'station' or 'kiosk', label = tostring(point.label or ''),
		sub = sub and { tier = sub.tier, left = math.max(0, sub.expiresAt - Db.now()) } or false,
		employee = false,
	}
	if station and type(data.job) == 'table' and data.job.name == Config.job then
		state.employee = true
		state.onDuty = data.job.onDuty == true
		state.uniform = uniformOn[source] ~= nil
		state.hasUniform = type(Config.uniform) == 'table' and type(Config.uniform[data.family]) == 'table'
		local called, boss = TT.callProvider('society', 'IsBoss', source, Config.job)
		state.boss = called and boss == true
	end
	return state
end

-- Sends the refreshed state to an open station menu (no-op on the client when it is closed).
function TT.sendStation(source)
	local state = stationState(source)
	if state then pcall(TriggerClientEvent, 'opx_traumateam:station', source, state, false) end
end

local function openStation(source)
	if not TT.character(source) then return end
	local state = stationState(source)
	if not state then return TT.notify(source, 'not_at_point', 'error') end
	pcall(TriggerClientEvent, 'opx_traumateam:station', source, state, true)
end

-- Employee actions need the station (not a kiosk).
local function atStation(source)
	if TT.atPoint(source, Config.stations) then return true end
	TT.notify(source, 'not_at_point', 'error')
	return false
end

local function setDuty(source, onDuty)
	if type(onDuty) ~= 'boolean' or not atStation(source) then return end
	if not TT.isMedic(source, false) then return TT.notify(source, 'not_employee', 'error') end
	local ok, reason = TT.core('SetDuty', source, onDuty)
	if ok ~= true then return TT.notify(source, 'failed', 'error', { reason = tostring(reason) }) end
	TT.notify(source, onDuty and 'duty_on' or 'duty_off', 'success')
	TT.sendStation(source)
end

local function openBoss(source)
	if not atStation(source) then return end
	if not TT.isMedic(source, false) then return TT.notify(source, 'not_employee', 'error') end
	local called, ok, reason = TT.callProvider('society', 'OpenBossMenu', source, Config.job)
	if not called then return TT.notify(source, 'no_society_provider', 'error') end
	if ok ~= true then TT.notify(source, 'failed', 'error', { reason = tostring(reason) }) end
end

-- Client requests -----------------------------------------------------------------------------------

-- Every client request: a valid source, under the rate limit. Nothing waits, so the handler runs inline.
local function onRequest(name, handler)
	RegisterNetEvent(name, function(...)
		local src = TT.toSource(source)
		if not src or not TT.allow(src) then return end
		handler(src, ...)
	end)
end

onRequest('opx_traumateam:open', openStation)
onRequest('opx_traumateam:duty', setDuty)
onRequest('opx_traumateam:uniform', function(src, wear)
	if type(wear) == 'boolean' and atStation(src) then
		setUniform(src, wear)
		TT.sendStation(src)
	end
end)
onRequest('opx_traumateam:boss', openBoss)
onRequest('opx_traumateam:buy', function(src, tier) Subs.buy(src, tier) end)
onRequest('opx_traumateam:dispatchOpen', function(src) Dispatch.open(src) end)
onRequest('opx_traumateam:take', function(src, patient) Dispatch.take(src, patient) end)
onRequest('opx_traumateam:drop', function(src, patient) Dispatch.drop(src, patient) end)
onRequest('opx_traumateam:careStart', function(src, kind, target)
	if type(kind) == 'string' then Care.start(src, kind, target) end
end)
-- Ends of a care are not rate-limited (they follow a start by seconds), only checked against the token.
RegisterNetEvent('opx_traumateam:careDone', function(token)
	local src = TT.toSource(source)
	if src and TT.int(token) then Care.done(src, TT.int(token)) end
end)
RegisterNetEvent('opx_traumateam:careCancel', function(token)
	local src = TT.toSource(source)
	if src and TT.int(token) then Care.cancel(src, TT.int(token)) end
end)

-- Exports --------------------------------------------------------------------------------------------

-- SYNC: the active plan of a player (source) or a character (citizen id): { tier, label, expiresAt, priority } | nil.
exports('GetSubscription', function(sourceOrCitizenId)
	local citizenId = sourceOrCitizenId
	if type(sourceOrCitizenId) == 'number' then
		local data = TT.character(TT.toSource(sourceOrCitizenId))
		citizenId = data and data.citizenId
	end
	if type(citizenId) ~= 'string' then return nil end
	return Subs.public(Subs.get(citizenId))
end)

-- SYNC: the tiers (copies) in menu order: { name, label, price, days, priority, reviveCoverage, respawnCoverage, reviveHealth }[].
exports('GetTiers', function()
	local out = {}
	for _, name in ipairs(Config.tierOrder) do
		local tier = Config.tiers[name]
		if tier then
			out[#out + 1] = {
				name = name, label = tier.label, price = tier.price, days = tier.days, priority = tier.priority,
				reviveCoverage = tier.reviveCoverage, respawnCoverage = tier.respawnCoverage, reviveHealth = tier.reviveHealth,
			}
		end
	end
	return out
end)

-- SYNC: whether a player is a Trauma Team member on duty.
exports('IsOnDuty', function(source)
	return TT.isMedic(TT.toSource(source), true) ~= nil
end)

-- SYNC: the open calls, sorted: { id, patient, priority, tier, position, bucket, at, responder }[].
exports('GetDispatch', function() return Dispatch.public() end)

-- Command --------------------------------------------------------------------------------------------

if type(Config.command) == 'string' and Config.command ~= '' then
	RegisterCommand(Config.command, function(src)
		src = TT.toSource(src)
		if not src then return print('[opx_traumateam] use this command in game') end
		if TT.allow(src) then Dispatch.open(src) end
	end, false)
end

-- Command help shown in opx_chat when it runs (optional: nothing happens without it). Chat is not a
-- provider slot, so opx_chat is named here; its export only describes the command above.
local function publishCommandHelp()
	if type(Config.command) ~= 'string' or Config.command == '' or GetResourceState('opx_chat') ~= 'running' then return end
	pcall(Open77.exports.callSync, 'opx_chat', 'SetCommandHelp', Config.command,
		{ en = 'Trauma Team: open the medic menu (open calls).', fr = 'Trauma Team : ouvrir le menu médecin (appels en cours).' })
end

AddEventHandler('onResourceStart', function(name)
	if name == GetCurrentResourceName() or name == 'opx_chat' then publishCommandHelp() end
end)

-- Player life cycle ---------------------------------------------------------------------------------

-- quiet: the player is gone (nothing to send to his client).
local function forget(source, quiet)
	lastCall[source] = nil
	Care.forget(source)
	Dispatch.releaseMedic(source, quiet)
	Dispatch.remove(source, 'closed')
end

AddEventHandler('opx:playerLoaded', function(playerId, data)
	local src = TT.toSource(playerId)
	if not src then return end
	if Config.dutyOffOnLoad and type(data) == 'table' and type(data.job) == 'table'
		and data.job.name == Config.job and data.job.onDuty == true then
		TT.core('SetDuty', src, false)
	end
	if Db.ready then Subs.pushCoverage(src) end
end)

AddEventHandler('opx:playerUnloaded', function(playerId)
	local src = TT.toSource(playerId)
	if not src then return end
	clearUniform(src)
	forget(src, false)
end)

AddEventHandler('onPlayerDisconnected', function(playerId)
	local src = TT.toSource(playerId)
	if not src then return end
	uniformOn[src] = nil -- the skin provider / open77_appearance retires it on disconnect
	forget(src, true)
end)

AddEventHandler('opx:characterDeleted', function(_, citizenId) Subs.forgetCitizen(citizenId) end)

-- Duty and job changes (station, staff setduty / setjob, a boss firing him).
AddEventHandler('opx:jobChanged', function(playerId, job, previous)
	local src = TT.toSource(playerId)
	if not src or type(job) ~= 'table' or type(previous) ~= 'table' then return end
	local was = previous.name == Config.job and previous.onDuty == true
	local now = job.name == Config.job and job.onDuty == true
	if was == now then return end
	if not now then
		clearUniform(src)
		Care.forget(src)
		Dispatch.releaseMedic(src, false)
	else
		Dispatch.broadcast(src)
	end
	if job.name == Config.job or previous.name == Config.job then
		TriggerEvent('opx:traumateam:duty', src, now)
	end
end)

-- Start / providers ---------------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(name)
	if name == GetCurrentResourceName() or name == CORE then registerJob() end
	if name == GetCurrentResourceName() then return end
	-- Another resource started: when it is the medical provider, its coverage table and its calls are new.
	-- Asked a second later: a resource still starting is not "running" for GetProvider yet.
	SetTimeout(1000, function()
		if TT.provider('medical') ~= name then return end
		if Db.ready then
			for _, src in ipairs(TT.core('GetPlayers') or {}) do
				src = TT.toSource(src)
				if src then Subs.pushCoverage(src) end
			end
		end
		Dispatch.resync()
	end)
end)

-- Another resource stopped: when no medical provider runs any more, its calls are gone. (A hot reload of
-- the provider is caught by onResourceStart above, which resyncs.)
AddEventHandler('onResourceStop', function(name)
	if name == GetCurrentResourceName() then return end
	SetTimeout(1000, function()
		if next(Dispatch.calls) ~= nil and not TT.provider('medical') then Dispatch.resync() end
	end)
end)

-- Load the plans, then adopt the characters already loaded (hot reload, late start).
CreateThread(function()
	Db.start(function(rows)
		Subs.list = rows
		for _, src in ipairs(TT.core('GetPlayers') or {}) do
			src = TT.toSource(src)
			if src and TT.character(src) then Subs.pushCoverage(src) end
		end
		Dispatch.resync()
	end)
end)
