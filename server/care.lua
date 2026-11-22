-- Care: revive a downed player or treat a living one, from the targeting eye. The server times it: it stores
-- the request, the client runs the progress bar (pacing only) and says done; the server checks the time that
-- passed and everything again, then acts and bills. The revive itself goes through the medical provider.

TT = TT or {}
Care = {}

local byMedic = {}   -- [medic] = { token, kind, target, startedAt, seconds, medicCid, targetCid }
local byPatient = {} -- [patient] = medic

local KINDS = { revive = true, treat = true }

local function settings(kind) return kind == 'revive' and Config.revive or Config.treat end

local function clear(medic)
	local session = byMedic[medic]
	if not session then return end
	byMedic[medic] = nil
	if byPatient[session.target] == medic then byPatient[session.target] = nil end
end

-- A session older than its length + 15 s was abandoned by the client: forgotten.
local function stale(session)
	return GetGameTimer() - session.startedAt > (session.seconds + 15) * 1000
end

-- Whether the patient is down (medical provider), else dead for the platform.
local function isDown(target)
	local called, down = TT.callProvider('medical', 'IsDown', target)
	if called and down == true then return true end
	return Open77.players.isDead(target) == true
end

-- Every check of a care, at the start and again when it ends. medicData, targetData | nil, reason.
local function check(medic, kind, target)
	local cfg = settings(kind)
	local medicData = TT.isMedic(medic, true)
	if not medicData then return nil, 'not_on_duty' end
	if Open77.players.isDead(medic) == true then return nil, 'medic_down' end
	if target == medic then return nil, 'invalid_target' end
	local targetData = TT.character(target)
	if not targetData then return nil, 'target_not_loaded' end
	local a, b = Open77.players.position(medic), Open77.players.position(target)
	if type(a) ~= 'table' or type(b) ~= 'table' or a.bucket ~= b.bucket then return nil, 'too_far' end
	local metres = Open77.players.distance(medic, target)
	if type(metres) ~= 'number' or metres > (tonumber(cfg.distance) or 3.0) + Config.serverSlack then
		return nil, 'too_far'
	end
	if kind == 'revive' then
		if not TT.provider('medical') then return nil, 'no_medical_provider' end
		if not isDown(target) then return nil, 'not_down' end
		if type(cfg.item) == 'string' and cfg.item ~= '' then
			local called, has = TT.callProvider('inventory', 'HasItem', medic, cfg.item, 1)
			if not called or has ~= true then return nil, 'no_item' end
		end
	elseif isDown(target) then
		return nil, 'target_down'
	end
	return medicData, targetData
end

-- Takes up to `amount` from the patient: bank first, then cash; never a debt. Returns what was taken.
local function charge(target, amount, reason)
	local paid = 0
	for _, account in ipairs({ 'bank', 'money' }) do
		local due = amount - paid
		if due <= 0 then break end
		local balance = TT.int(TT.core('GetMoney', target, account)) or 0
		local take = math.min(due, balance)
		if take > 0 and TT.core('RemoveMoney', target, account, take, reason) == true then paid = paid + take end
	end
	return paid
end

-- Step 1: the medic asks (eye option). Answers opx_traumateam:careGo with a token, or a refusal.
function Care.start(medic, kind, targetValue)
	if not KINDS[kind] then return end
	local target = TT.toSource(targetValue)
	if not target then return TT.notify(medic, 'invalid_target', 'error') end
	local own = byMedic[medic]
	if own and not stale(own) then return TT.notify(medic, 'busy', 'error') end
	clear(medic)
	local other = byPatient[target]
	if other and byMedic[other] and not stale(byMedic[other]) then return TT.notify(medic, 'patient_busy', 'error') end
	clear(other or 0)

	local medicData, targetData = check(medic, kind, target)
	if not medicData then return TT.notify(medic, targetData, 'error') end
	local cfg = settings(kind)
	local seconds = math.max(1, math.min(120, TT.int(cfg.seconds) or 5))
	local session = {
		token = math.random(1, 2147483647), kind = kind, target = target, startedAt = GetGameTimer(),
		seconds = seconds, medicCid = medicData.citizenId, targetCid = targetData.citizenId,
	}
	byMedic[medic], byPatient[target] = session, medic
	pcall(TriggerClientEvent, 'opx_traumateam:careGo', medic, session.token, kind, seconds,
		type(cfg.animation) == 'string' and cfg.animation or false)
end

-- The medic's bar was cancelled (or failed): nothing happens.
function Care.cancel(medic, token)
	local session = byMedic[medic]
	if session and session.token == token then clear(medic) end
end

-- Step 2: the bar ended. Time, identities and every check again, then the care and the bill.
function Care.done(medic, token)
	local session = byMedic[medic]
	if not session or session.token ~= token then return end
	clear(medic)
	if GetGameTimer() - session.startedAt < session.seconds * 1000 - 500 then
		return TT.notify(medic, 'too_fast', 'error')
	end
	local kind, target = session.kind, session.target
	local medicData, targetData = check(medic, kind, target)
	if not medicData then return TT.notify(medic, targetData, 'error') end
	if medicData.citizenId ~= session.medicCid or targetData.citizenId ~= session.targetCid then
		return TT.notify(medic, 'target_changed', 'error')
	end
	local cfg = settings(kind)
	local sub, tier = Subs.ofPlayer(target)

	if kind == 'revive' then
		local health = tier and tonumber(tier.reviveHealth) or tonumber(cfg.health) or 0.5
		health = math.max(0.05, math.min(1, health))
		local called, ok, reason = TT.callProvider('medical', 'Revive', target, { health = health, by = medic })
		if not called then return TT.notify(medic, 'no_medical_provider', 'error') end
		if ok ~= true then return TT.notify(medic, 'failed', 'error', { reason = tostring(reason) }) end
		if type(cfg.item) == 'string' and cfg.item ~= '' then
			local used, removed, why = TT.callProvider('inventory', 'RemoveItem', medic, cfg.item, 1)
			if not used or removed ~= true then
				print(('[opx_traumateam] %s not taken from medic %d: %s'):format(cfg.item, medic, tostring(why)))
			end
		end
	else
		local ok, reason = Open77.stats.restoreHealth(target)
		if ok ~= true then return TT.notify(medic, 'failed', 'error', { reason = tostring(reason) }) end
	end

	-- Bill: the plan covers a share of a revive (never a treatment); the patient pays the rest, what he has.
	local fee = math.max(0, TT.int(cfg.fee) or 0)
	local covered = 0
	if kind == 'revive' and tier then
		covered = math.floor(fee * math.max(0, math.min(1, tonumber(tier.reviveCoverage) or 0)))
	end
	local paid = 0
	if fee - covered > 0 then paid = charge(target, fee - covered, 'traumateam:' .. kind) end
	if paid > 0 then
		local ok, why = TT.core('AddSocietyMoney', Config.job, paid, 'traumateam:' .. kind)
		if ok ~= true then print(('[opx_traumateam] society not credited with %d: %s'):format(paid, tostring(why))) end
	end

	-- Revive only: the medic's bonus, from the society when it can afford it.
	local bonus = 0
	local wanted = kind == 'revive' and math.max(0, TT.int(cfg.medicBonus) or 0) or 0
	if wanted > 0 and (TT.int(TT.core('GetSocietyMoney', Config.job)) or 0) >= wanted then
		if TT.core('RemoveSocietyMoney', Config.job, wanted, 'traumateam:bonus') == true then
			if TT.core('AddMoney', medic, 'bank', wanted, 'traumateam:bonus') == true then
				bonus = wanted
			else
				TT.core('AddSocietyMoney', Config.job, wanted, 'traumateam:bonus (refund)')
			end
		end
	end

	TT.notify(medic, kind .. '_done_medic', 'success', { fee = fee, paid = paid, covered = covered, bonus = bonus })
	TT.notify(target, kind .. '_done_patient', 'info', { fee = fee, paid = paid, covered = covered, tier = sub and sub.tier or false })
	if kind == 'revive' then
		TriggerEvent('opx:traumateam:revived', medic, target, fee, covered)
	else
		TriggerEvent('opx:traumateam:treated', medic, target, fee)
	end
end

-- A player left (or switched character, or left the job): his sessions end.
function Care.forget(source)
	clear(source)
	local medic = byPatient[source]
	if medic then clear(medic) end
end
