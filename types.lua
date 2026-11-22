---@meta

-- opx_traumateam server exports and events. Not loaded by the manifest (LuaLS annotations only).
-- A replacement Trauma Team resource keeps these names and shapes. Every export is SYNCHRONOUS (answers from
-- memory, never waits): exports.opx_traumateam:Name(...) or Open77.exports.callSync('opx_traumateam', ...).

---@alias OpxTraumaTier 'silver' | 'gold' | 'platinum' | string keys of Config.tiers

---@class OpxTraumaSubscription
---@field tier OpxTraumaTier
---@field label string Config.tiers[tier].label
---@field expiresAt integer unix seconds
---@field priority integer lower = higher in the dispatch list

---@class OpxTraumaTierInfo
---@field name OpxTraumaTier
---@field label string
---@field price integer
---@field days integer
---@field priority integer
---@field reviveCoverage number 0..1 share of the revive fee paid by the plan
---@field respawnCoverage number 0..1 share of the hospital bill (handed to the medical provider as coverage)
---@field reviveHealth number 0..1 health after a Trauma Team revive

---@class OpxTraumaCall
---@field id integer the medical provider's call id
---@field patient integer server id of the downed player
---@field priority integer tier priority, or Config.uninsuredPriority
---@field tier OpxTraumaTier|nil
---@field position {x: number, y: number, z: number}
---@field bucket integer
---@field at integer unix seconds of the call
---@field responder integer|nil server id of the medic who took it

---@class OpxTraumaTeamExports
local opx_traumateam = {}

--- SYNC. The active plan of a player (server id) or of any character (citizen id), or nil.
---@param sourceOrCitizenId integer|string
---@return OpxTraumaSubscription|nil
function opx_traumateam.GetSubscription(sourceOrCitizenId) end

--- SYNC. The plans in menu order (copies of Config.tiers).
---@return OpxTraumaTierInfo[]
function opx_traumateam.GetTiers() end

--- SYNC. Whether a player is a Trauma Team member on duty.
---@param source integer
---@return boolean
function opx_traumateam.IsOnDuty(source) end

--- SYNC. The open calls, sorted by priority then age (copies).
---@return OpxTraumaCall[]
function opx_traumateam.GetDispatch() end

-- Server host events (AddEventHandler):
-- TriggerEvent('opx:traumateam:subscribed', source, tier, expiresAt)    a plan bought or extended
-- TriggerEvent('opx:traumateam:revived', medic, patient, fee, covered)  a Trauma Team revive (fee before cover)
-- TriggerEvent('opx:traumateam:treated', medic, patient, fee)           a treatment
-- TriggerEvent('opx:traumateam:duty', source, onDuty)                   a member's service started / ended (any path)
---@alias OpxTraumaSubscribedEvent fun(source: integer, tier: OpxTraumaTier, expiresAt: integer)
---@alias OpxTraumaRevivedEvent fun(medic: integer, patient: integer, fee: integer, covered: integer)
---@alias OpxTraumaTreatedEvent fun(medic: integer, patient: integer, fee: integer)
---@alias OpxTraumaDutyEvent fun(source: integer, onDuty: boolean)

-- Job: registered with opx_core at start and whenever opx_core starts:
-- RegisterJob('traumateam', { label, type = 'ems', defaultDuty = false, data = { bossGrade }, grades }).
-- Table opx_traumateam_subscriptions (citizen_id PK, tier, expires_at unix s, updated_at), created at start,
-- loaded whole; expired rows deleted at start and every minute; a deleted character's row goes with opx:characterDeleted.
-- Money: subscription = bank if it holds the whole price, else cash, to the traumateam society. Revive / treat bill =
-- fee minus floor(fee * reviveCoverage) (revive only), bank then cash, never a debt; the medic's revive bonus is paid
-- from the society when it can afford it. Reasons: traumateam:subscription:<tier>, :revive, :treat, :bonus.
-- Uses: medical provider IsDown, Revive, SetCoverage, GetCalls, AckCall + opx:medical:call/callAck/callClosed/up;
-- society IsBoss, OpenBossMenu; progress Start; target addPlayer, addSelf; inventory HasItem, RemoveItem
-- (only with Config.revive.item); skin SetUniform / ClearUniform (uniform; without a skin provider,
-- open77_appearance setTemporaryOutfit / clearTemporaryOutfit).
-- Internal net events (not a contract): client -> server opx_traumateam:open, :duty, :uniform, :boss, :buy,
-- :dispatchOpen, :take, :drop, :careStart, :careDone, :careCancel; server -> client :station, :dispatch, :route,
-- :careGo, :notify.
