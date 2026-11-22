-- Dispatch: the calls of downed players (raised by the medical provider), seen by on-duty medics, sorted by
-- plan priority then age. A medic takes one (AckCall on the medical provider) and gets a GPS route; he can
-- drop it. The call itself belongs to the medical provider: its callClosed / up events remove ours.

TT = TT or {}
Dispatch = { calls = {} } -- [patientSource] = { id, patient, priority, tier, position, bucket, at, responder }

local MAX_LISTED = 40 -- rows sent to a client (keeps the net payload small)

local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

-- A clean { x, y, z } from anything, or nil (never NaN / inf: json.encode of those aborts the server).
local function point(p)
	if type(p) ~= 'table' or not finite(p.x) or not finite(p.y) or not finite(p.z) then return nil end
	return { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 }
end

-- Sorted array of the entries: priority, then oldest first.
local function sorted()
	local list = {}
	for _, entry in pairs(Dispatch.calls) do list[#list + 1] = entry end
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then return a.priority < b.priority end
		if a.at ~= b.at then return a.at < b.at end
		return a.patient < b.patient
	end)
	return list
end

-- The list as one medic's client sees it (no names; `mine` / `taken` for the row state).
local function viewFor(medic)
	local now, out = Db.now(), {}
	for i, entry in ipairs(sorted()) do
		if i > MAX_LISTED then break end
		out[#out + 1] = {
			patient = entry.patient, tier = entry.tier or false, priority = entry.priority,
			x = entry.position.x, y = entry.position.y, z = entry.position.z,
			age = math.max(0, now - entry.at), mine = entry.responder == medic, taken = entry.responder ~= nil,
		}
	end
	return out
end

-- Sends the refreshed list to every on-duty medic (or one).
function Dispatch.broadcast(only)
	local medics = only and { only } or TT.onDutyMedics()
	for _, medic in ipairs(medics) do
		pcall(TriggerClientEvent, 'opx_traumateam:dispatch', medic, viewFor(medic), false)
	end
end

-- Opens the medic menu (command, eye): on-duty medics only.
function Dispatch.open(medic)
	if not TT.isMedic(medic, true) then return TT.notify(medic, 'not_on_duty', 'error') end
	pcall(TriggerClientEvent, 'opx_traumateam:dispatch', medic, viewFor(medic), true)
end

local function setRoute(medic, position)
	if medic then pcall(TriggerClientEvent, 'opx_traumateam:route', medic, position or false) end
end

-- Adds (or refreshes) the entry of a medical call { id, source, position, bucket, at, responder? }.
local function add(source, call, quiet)
	local patient = TT.toSource(source)
	if not patient or type(call) ~= 'table' then return end
	local position = point(call.position)
	if not position then return end
	local sub, tier = Subs.ofPlayer(patient)
	local previous = Dispatch.calls[patient]
	local responder = TT.toSource(call.responder)
	if responder and not TT.isMedic(responder, true) then responder = nil end
	local at = TT.int(call.at)
	Dispatch.calls[patient] = {
		id = TT.int(call.id) or 0,
		patient = patient,
		priority = tier and (TT.int(tier.priority) or 1) or (TT.int(Config.uninsuredPriority) or 9),
		tier = sub and sub.tier or nil,
		position = position,
		bucket = TT.int(call.bucket) or 0,
		at = (at and at > 0) and at or Db.now(),
		responder = responder or (previous and previous.responder) or nil,
	}
	if quiet then return end
	for _, medic in ipairs(TT.onDutyMedics()) do
		if medic ~= patient then
			TT.notify(medic, 'call_new', 'warning', { tier = sub and sub.tier or false, x = position.x, y = position.y, z = position.z })
		end
	end
	Dispatch.broadcast()
end

-- Removes the entry of a patient; his responder loses the route.
function Dispatch.remove(patient, reason)
	local entry = Dispatch.calls[patient]
	if not entry then return end
	Dispatch.calls[patient] = nil
	if entry.responder then
		setRoute(entry.responder, nil)
		TT.notify(entry.responder, reason == 'up' and 'call_patient_up' or 'call_closed', 'info')
	end
	Dispatch.broadcast()
end

-- Gives a call back to the medical provider (ReleaseCall), so the next medic's AckCall is accepted. Best effort:
-- an older provider without ReleaseCall answers already_taken to the next medic, handled in Dispatch.take.
local function release(patient, medic)
	TT.callProvider('medical', 'ReleaseCall', patient, medic)
end

-- A medic takes a call: the medical provider records him as the responder and tells the patient.
function Dispatch.take(medic, patientValue)
	if not TT.isMedic(medic, true) then return TT.notify(medic, 'not_on_duty', 'error') end
	local patient = TT.toSource(patientValue)
	local entry = patient and Dispatch.calls[patient]
	if not entry then return TT.notify(medic, 'call_gone', 'error') end
	if entry.responder == medic then return setRoute(medic, entry.position) end
	if entry.responder then return TT.notify(medic, 'call_taken', 'error') end

	local called, ok, reason = TT.callProvider('medical', 'AckCall', patient, medic)
	if not called then return TT.notify(medic, 'no_medical_provider', 'error') end
	if ok ~= true then
		if reason == 'no_call' then
			Dispatch.calls[patient] = nil
			Dispatch.broadcast()
			return TT.notify(medic, 'call_gone', 'error')
		end
		if reason ~= 'already_taken' then return TT.notify(medic, 'failed', 'error', { reason = tostring(reason) }) end
		-- Taken there earlier by a medic who dropped it here: ours to give again; tell the patient ourselves.
		TT.notify(patient, 'unit_coming', 'info')
	end
	-- One call at a time per medic: the previous one goes back to the list.
	for otherPatient, other in pairs(Dispatch.calls) do
		if other ~= entry and other.responder == medic then
			other.responder = nil
			release(otherPatient, medic)
		end
	end
	entry.responder = medic
	setRoute(medic, entry.position)
	TT.notify(medic, 'call_took', 'success')
	Dispatch.broadcast()
end

-- A medic drops his call: back in the list for the others.
function Dispatch.drop(medic, patientValue)
	local patient = TT.toSource(patientValue)
	local entry = patient and Dispatch.calls[patient]
	if not entry or entry.responder ~= medic then return end
	entry.responder = nil
	release(patient, medic)
	setRoute(medic, nil)
	TT.notify(medic, 'call_dropped', 'info')
	Dispatch.broadcast()
end

-- A medic left the service, the job or the server: his call goes back to the list.
function Dispatch.releaseMedic(medic, quiet)
	local changed = false
	for patient, entry in pairs(Dispatch.calls) do
		if entry.responder == medic then
			entry.responder = nil
			changed = true
			release(patient, medic)
		end
	end
	if not quiet then
		setRoute(medic, nil)
		pcall(TriggerClientEvent, 'opx_traumateam:dispatch', medic, {}, false)
	end
	if changed then Dispatch.broadcast() end
end

-- Rebuilds the list from the medical provider (our start, its start): its GetCalls is the truth.
function Dispatch.resync()
	Dispatch.calls = {}
	local called, calls = TT.callProvider('medical', 'GetCalls')
	if called and type(calls) == 'table' then
		for _, call in ipairs(calls) do
			if type(call) == 'table' then add(call.source, call, true) end
		end
	end
	Dispatch.broadcast()
end

-- Exports shape: copies, sorted.
function Dispatch.public()
	local out = {}
	for i, entry in ipairs(sorted()) do
		out[i] = {
			id = entry.id, patient = entry.patient, priority = entry.priority, tier = entry.tier,
			position = { x = entry.position.x, y = entry.position.y, z = entry.position.z },
			bucket = entry.bucket, at = entry.at, responder = entry.responder,
		}
	end
	return out
end

-- Medical provider events (host bus) -------------------------------------------------------------

AddEventHandler('opx:medical:call', function(source, call) add(source, call, false) end)

AddEventHandler('opx:medical:callAck', function(source, responder)
	local patient, medic = TT.toSource(source), TT.toSource(responder)
	local entry = patient and Dispatch.calls[patient]
	if not entry or not medic or entry.responder == medic then return end
	-- Acknowledged by somebody else (another resource): keep the list right.
	if entry.responder then setRoute(entry.responder, nil) end
	entry.responder = TT.isMedic(medic, true) and medic or nil
	Dispatch.broadcast()
end)

AddEventHandler('opx:medical:callClosed', function(source)
	local patient = TT.toSource(source)
	if patient then Dispatch.remove(patient, 'closed') end
end)

AddEventHandler('opx:medical:up', function(source)
	local patient = TT.toSource(source)
	if patient then Dispatch.remove(patient, 'up') end
end)
