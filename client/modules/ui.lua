-- The station menu (duty, uniform, management, subscriptions) and the medic menu (open calls), in opx_menu.
-- Shows and asks; the server decides (and checks the place again for every action).

local OPX = assert(require('@opx_core'))
local Menu = assert(require('@opx_menu'))

local Ui = {}

local T = OPX.Locale()
local station = nil   -- the open station menu, or nil
local stationState = nil
local dispatch = nil  -- the open medic menu, or nil
local calls = {}      -- last list sent by the server

-- Translated text; money params formatted the player's way, `tier` turned into its label.
local MONEY = { amount = true, fee = true, paid = true, covered = true, bonus = true, price = true }
function Ui.tierLabel(name)
	local tier = type(name) == 'string' and Config.tiers[name]
	return tier and tier.label or T('uninsured')
end

function Ui.text(key, params)
	local shown = {}
	for k, v in pairs(type(params) == 'table' and params or {}) do
		if MONEY[k] and type(v) == 'number' then shown[k] = OPX.FormatMoney(v)
		elseif k == 'tier' or k == 'old' then shown[k] = Ui.tierLabel(v)
		else shown[k] = v end
	end
	return T(key, shown)
end

-- Metres from the player to a point, or nil.
local function distanceTo(x, y, z)
	local px, py, pz = Open77.character.position()
	if type(px) ~= 'number' or type(x) ~= 'number' then return nil end
	local dx, dy, dz = px - x, py - y, pz - (tonumber(z) or pz)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- A server answer: locale key + kind + params. An unknown key reads as a generic failure.
function Ui.notify(key, kind, params)
	if type(key) ~= 'string' then return end
	params = type(params) == 'table' and params or {}
	if key == 'call_new' then
		local metres = distanceTo(params.x, params.y, params.z)
		params = { tier = params.tier, distance = metres and math.floor(metres + 0.5) or '?' }
	end
	local text = Ui.text(key, params)
	if text == key then text = Ui.text('failed', { reason = key }) end
	OPX.Notify(text, kind, nil, Ui.text('title'))
end

-- "2 d 4 h" / "3 h 12 min" / "8 min".
local function left(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if d > 0 then return Ui.text('time_dh', { d = d, h = h }) end
	if h > 0 then return Ui.text('time_hm', { h = h, m = m }) end
	return Ui.text('time_m', { m = math.max(1, m) })
end

local function percent(share) return math.floor((tonumber(share) or 0) * 100 + 0.5) end

-- Subscriptions -------------------------------------------------------------------------------------

local function subtitleOf(state)
	if type(state.sub) == 'table' then
		return Ui.text('sub_current', { tier = state.sub.tier, left = left(state.sub.left) })
	end
	return Ui.text('sub_none')
end

local function buy(name, state)
	local tier = Config.tiers[name]
	if not tier then return end
	local current = type(state.sub) == 'table' and state.sub.tier or nil
	local message
	if current == name then
		message = Ui.text('confirm_extend', { tier = name, price = tier.price, days = tier.days })
	elseif current then
		message = Ui.text('confirm_switch', { tier = name, price = tier.price, days = tier.days, old = current })
	else
		message = Ui.text('confirm_buy', { tier = name, price = tier.price, days = tier.days })
	end
	local yes = Menu.confirm({
		title = Ui.text('subscriptions'), message = message,
		confirmLabel = Ui.text('pay'), cancelLabel = Ui.text('cancel'),
	})
	if yes then TriggerServerEvent('opx_traumateam:buy', name) end
end

local function tierElements(state)
	local elements = {}
	local current = type(state.sub) == 'table' and state.sub.tier or nil
	for _, name in ipairs(Config.tierOrder) do
		local tier = Config.tiers[name]
		if tier then
			elements[#elements + 1] = {
				label = tier.label .. (current == name and (' · ' .. Ui.text('current')) or ''),
				value = name, icon = current == name and 'check' or 'star',
				rightLabel = OPX.FormatMoney(tier.price),
				description = Ui.text('tier_desc', {
					days = tier.days, revive = percent(tier.reviveCoverage), respawn = percent(tier.respawnCoverage),
					health = percent(tier.reviveHealth),
				}),
			}
		end
	end
	return elements
end

local subsMenu = nil
local function openSubscriptions(parent, state)
	subsMenu = Menu.open({
		id = 'opx_traumateam_subs', title = Ui.text('subscriptions'), subtitle = subtitleOf(state), parent = parent,
		elements = tierElements(state),
		onSelect = function(element) buy(element.value, stationState or state) end,
		onClose = function(menu) if subsMenu == menu then subsMenu = nil end end,
	})
end

-- Station ---------------------------------------------------------------------------------------------

local function stationElements(state)
	local elements = {
		{ label = Ui.text('subscriptions'), value = 'subs', icon = 'star', rightLabel = '>', description = Ui.text('subscriptions_desc') },
	}
	if state.employee then
		elements[#elements + 1] = { type = 'separator', label = Ui.text('title') }
		elements[#elements + 1] = {
			label = Ui.text(state.onDuty and 'duty_end' or 'duty_start'), value = 'duty', icon = 'power',
			rightLabel = Ui.text(state.onDuty and 'on_duty' or 'off_duty'),
		}
		if state.hasUniform then
			elements[#elements + 1] = {
				label = Ui.text(state.uniform and 'uniform_take_off' or 'uniform_put_on'), value = 'uniform', icon = 'person',
				disabled = not state.onDuty, description = not state.onDuty and Ui.text('need_duty') or nil,
			}
		end
		if state.boss then
			elements[#elements + 1] = { label = Ui.text('management'), value = 'boss', icon = 'group' }
		end
	end
	elements[#elements + 1] = { label = Ui.text('close'), value = 'close', icon = 'close' }
	return elements
end

function Ui.station(state, open)
	if type(state) ~= 'table' then return end
	stationState = state
	if not open then
		if Ui.isOpen() then
			station:setTitle(state.label, subtitleOf(state))
			station:setElements(stationElements(state), true)
		end
		if subsMenu and subsMenu:isOpen() then
			subsMenu:setTitle(Ui.text('subscriptions'), subtitleOf(state))
			subsMenu:setElements(tierElements(state), true)
		end
		return
	end
	station = Menu.open({
		id = 'opx_traumateam', title = state.label, subtitle = subtitleOf(state),
		elements = stationElements(state),
		onSelect = function(element, menu)
			local s = stationState or state
			if element.value == 'subs' then openSubscriptions(menu, s)
			elseif element.value == 'duty' then TriggerServerEvent('opx_traumateam:duty', not s.onDuty)
			elseif element.value == 'uniform' then TriggerServerEvent('opx_traumateam:uniform', not s.uniform)
			elseif element.value == 'boss' then menu:close(); TriggerServerEvent('opx_traumateam:boss')
			else menu:close() end
		end,
		onClose = function(menu) if station == menu then station = nil end end,
	})
end

function Ui.isOpen() return station ~= nil and station:isOpen() end

function Ui.close()
	if station then station:close() end
	station, subsMenu = nil, nil
end

-- Medic menu (open calls) -----------------------------------------------------------------------------

local function age(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return ('%02d:%02d'):format(math.min(99, seconds // 60), seconds % 60)
end

local function callElements()
	local elements = {}
	for _, call in ipairs(calls) do
		if type(call) == 'table' and math.tointeger(call.patient) then
			local metres = distanceTo(call.x, call.y, call.z)
			local tier = type(call.tier) == 'string' and Ui.tierLabel(call.tier):upper() or Ui.text('uninsured'):upper()
			local state = call.mine and Ui.text('call_mine') or call.taken and Ui.text('call_taken_short') or age(call.age)
			elements[#elements + 1] = {
				label = ('[%s] %s'):format(tier, metres and ('%d m'):format(math.floor(metres + 0.5)) or '?'),
				value = call.patient, icon = call.mine and 'location' or 'medical', rightLabel = state,
				disabled = call.taken and not call.mine or nil,
				description = Ui.text(call.mine and 'call_desc_mine' or 'call_desc', { age = age(call.age) }),
			}
		end
	end
	if #elements == 0 then elements[1] = { label = Ui.text('no_calls'), value = 'empty', disabled = true } end
	elements[#elements + 1] = { label = Ui.text('close'), value = 'close', icon = 'close' }
	return elements
end

local function find(patient)
	for _, call in ipairs(calls) do
		if call.patient == patient then return call end
	end
end

function Ui.dispatch(list, open)
	calls = type(list) == 'table' and list or {}
	if not open then
		if dispatch and dispatch:isOpen() then dispatch:setElements(callElements(), true) end
		return
	end
	dispatch = Menu.open({
		id = 'opx_traumateam_dispatch', title = Ui.text('dispatch'), subtitle = Ui.text('dispatch_sub'),
		elements = callElements(),
		onSelect = function(element, menu)
			if element.value == 'close' then return menu:close() end
			local call = find(element.value)
			if not call then return end
			if call.mine then
				local yes = Menu.confirm({ title = Ui.text('dispatch'), message = Ui.text('confirm_drop'),
					confirmLabel = Ui.text('drop'), cancelLabel = Ui.text('cancel') })
				if yes then TriggerServerEvent('opx_traumateam:drop', call.patient) end
			else
				TriggerServerEvent('opx_traumateam:take', call.patient)
			end
		end,
		onClose = function(menu) if dispatch == menu then dispatch = nil end end,
	})
end

function Ui.closeAll()
	Ui.close()
	if dispatch then dispatch:close() end
	dispatch = nil
end

return Ui
