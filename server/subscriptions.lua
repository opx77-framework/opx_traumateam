-- Subscriptions: Silver / Gold / Platinum plans, bought at a station or a kiosk, 7 real days each, no
-- auto-renewal. Memory is the authority ({ [citizenId] = { tier, expiresAt, updatedAt } }); every change is
-- written at once (Db) and pushed to the medical provider as the character's coverage (SetCoverage).

TT = TT or {}
Subs = { list = {} }

-- The active plan of a citizen id (expired = none): the record, or nil.
function Subs.get(citizenId)
	local sub = type(citizenId) == 'string' and Subs.list[citizenId] or nil
	if not sub or sub.expiresAt <= Db.now() or not Config.tiers[sub.tier] then return nil end
	return sub
end

-- The plan of a loaded player, with its tier definition: sub, tier | nil.
function Subs.ofPlayer(source)
	local data = TT.character(source)
	local sub = data and Subs.get(data.citizenId)
	if not sub then return nil end
	return sub, Config.tiers[sub.tier]
end

-- The public shape: { tier, label, expiresAt, priority } or nil.
function Subs.public(sub)
	if not sub then return nil end
	local tier = Config.tiers[sub.tier]
	return { tier = sub.tier, label = tier.label, expiresAt = sub.expiresAt, priority = tier.priority }
end

-- Tells the medical provider what the plan of a loaded player covers (nil = nothing). Owned by this
-- resource's generation there, so a restart pushes it again (main.lua).
function Subs.pushCoverage(source)
	local sub, tier = Subs.ofPlayer(source)
	local coverage = nil
	if sub then
		coverage = {
			respawnFee = math.max(0, math.min(1, tonumber(tier.respawnCoverage) or 0)),
			label = ('Trauma Team ' .. tostring(tier.label)):sub(1, 32),
		}
	end
	local called, ok, reason = TT.callProvider('medical', 'SetCoverage', source, coverage)
	if called and ok ~= true and coverage then
		print(('[opx_traumateam] coverage of player %d refused: %s'):format(source, tostring(reason)))
	end
end

-- Buys `tierName` for a loaded player standing at a station or a kiosk. Notifies him either way.
function Subs.buy(source, tierName)
	local tier = type(tierName) == 'string' and Config.tiers[tierName] or nil
	if not tier then return TT.notify(source, 'invalid_tier', 'error') end
	local data = TT.character(source)
	if not data then return end
	if not TT.atPoint(source, Config.stations) and not TT.atPoint(source, Config.kiosks) then
		return TT.notify(source, 'not_at_point', 'error')
	end
	if not Db.ready then return TT.notify(source, 'not_ready', 'error') end
	local price = TT.int(tier.price) or 0
	local period = math.max(1, TT.int(tier.days) or 7) * 86400
	local now = Db.now()
	if now <= 0 then return TT.notify(source, 'not_ready', 'error') end

	local current = Subs.get(data.citizenId)
	local expiresAt
	if current and current.tier == tierName then
		-- Same plan: one more period after the current end, at most maxPrepaidPeriods ahead.
		expiresAt = current.expiresAt + period
		if expiresAt - now > math.max(1, TT.int(Config.maxPrepaidPeriods) or 1) * period then
			return TT.notify(source, 'max_prepaid', 'error')
		end
	else
		-- New plan, or another one: starts now, the rest of the old one is lost (the client confirm says so).
		expiresAt = now + period
	end

	-- Payment: the bank when it holds the whole price, else cash.
	if price > 0 then
		local account = nil
		if TT.core('HasMoney', source, 'bank', price) == true then account = 'bank'
		elseif TT.core('HasMoney', source, 'money', price) == true then account = 'money' end
		if not account then return TT.notify(source, 'insufficient_funds', 'error', { amount = price }) end
		local ok, why = TT.core('RemoveMoney', source, account, price, 'traumateam:subscription:' .. tierName)
		if ok ~= true then return TT.notify(source, 'failed', 'error', { reason = tostring(why) }) end
		local credited, refused = TT.core('AddSocietyMoney', Config.job, price, 'traumateam:subscription:' .. tierName)
		if credited ~= true then
			print(('[opx_traumateam] society not credited with %d: %s'):format(price, tostring(refused)))
		end
	end

	local sub = { tier = tierName, expiresAt = expiresAt, updatedAt = now }
	Subs.list[data.citizenId] = sub
	Db.save(data.citizenId, sub)
	Subs.pushCoverage(source)
	TT.notify(source, 'sub_bought', 'success', { tier = tierName, amount = price, days = math.floor((expiresAt - now) / 86400) })
	TriggerEvent('opx:traumateam:subscribed', source, tierName, expiresAt)
	TT.sendStation(source)
end

-- A deleted character takes his plan with him.
function Subs.forgetCitizen(citizenId)
	if type(citizenId) ~= 'string' or not Subs.list[citizenId] then return end
	Subs.list[citizenId] = nil
	Db.delete(citizenId)
end

-- One-minute loop: expired plans are dropped, their holder told once (when he is online).
CreateThread(function()
	while true do
		Wait(60000)
		local now = Db.now()
		if Db.ready and now > 0 then
			local expired = {}
			for citizenId, sub in pairs(Subs.list) do
				if sub.expiresAt <= now then expired[#expired + 1] = citizenId end
			end
			for _, citizenId in ipairs(expired) do
				local tierName = Subs.list[citizenId].tier
				Subs.list[citizenId] = nil
				Db.delete(citizenId)
				local data = TT.core('GetPlayerByCitizenId', citizenId)
				local source = type(data) == 'table' and TT.toSource(data.source) or nil
				if source then
					Subs.pushCoverage(source)
					TT.notify(source, 'sub_expired', 'warning', { tier = tierName })
				end
			end
		end
	end
end)
