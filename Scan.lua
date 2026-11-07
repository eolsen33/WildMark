local _, ns = ...

-- Who needs Mark of the Wild, in the order to buff them: your target first,
-- then your group (you included), then friendly players on nameplates.

ns.MOTW = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }
ns.GIFT = { 21849, 21850 }
local GIFT_REAGENT = { [21849] = 17021, [21850] = 17026 } -- Wild Berries, Wild Thornroot

ns.skipped = {} -- guid -> GetTime() when the skip ends

local names = {}
local function buffNames()
	names.motw = names.motw or ns.SpellInfo(1126)
	names.gift = names.gift or ns.SpellInfo(21849)
	return names.motw, names.gift
end

local function bestKnown(list)
	local best
	for _, id in ipairs(list) do
		if ns.Known(id) then best = id end
	end
	return best
end

-- Highest known rank of Mark and of Gift (nil when not learned).
function ns.Spells()
	return bestKnown(ns.MOTW), bestKnown(ns.GIFT)
end

-- Seconds of Mark/Gift left on the unit: 0 when missing, math.huge when permanent.
local function remaining(unit)
	local motw, gift = buffNames()
	for i = 1, 40 do
		local name, _, _, _, _, expires = ns.UnitBuff(unit, i)
		if not name then break end
		if name == motw or name == gift then
			if not expires or expires == 0 then return math.huge end
			return math.max(0, expires - GetTime())
		end
	end
	return 0
end

local function ignored(unit)
	local ig = ns.db and ns.db.ignore
	if not ig then return false end
	local full, first = ns.FullName(unit), UnitName(unit)
	return (full and ig[full:lower()]) or (first and ig[first:lower()]) or false
end

local function skipped(unit)
	local guid = UnitGUID(unit)
	local until_ = guid and ns.skipped[guid]
	if not until_ then return false end
	if until_ > GetTime() then return true end
	ns.skipped[guid] = nil
	return false
end

-- Could we cast the buff on this unit right now?
local function eligible(unit, spellName)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
	if not UnitIsFriend("player", unit) or not UnitCanAssist("player", unit) then return false end
	if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then return false end
	if not UnitIsVisible(unit) then return false end
	if ignored(unit) or skipped(unit) then return false end
	return ns.InRange(spellName, unit)
end

local function needs(left)
	if left == math.huge then return false end
	return left < math.max(ns.settings.renew or 0, 1)
end

function ns.InGroup(unit)
	return UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit) or false
end

-- Raid subgroup of a unit (Gift of the Wild only reaches the target's party).
function ns.Subgroup(unit)
	if not IsInRaid() then return 1 end
	for i = 1, GetNumGroupMembers() do
		if UnitIsUnit(unit, "raid" .. i) then
			local sub = select(3, GetRaidRosterInfo(i))
			return sub or 1
		end
	end
	return 1
end

local function groupUnits()
	local out = {}
	local n = GetNumGroupMembers()
	if IsInRaid() then
		for i = 1, n do out[#out + 1] = "raid" .. i end
	else
		out[1] = "player"
		for i = 1, n - 1 do out[#out + 1] = "party" .. i end
	end
	return out
end

local function plateUnits()
	local out = {}
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return out end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then out[#out + 1] = unit end
	end
	return out
end

-- Returns the ordered list of people who need the buff, a Gift of the Wild
-- plan when one makes sense, and the Mark spell id (nil when not learned).
function ns.Scan()
	local motw, gift = ns.Spells()
	if not motw then return {}, nil, nil end
	local spellName = ns.SpellInfo(motw)

	local list, seen = {}, {}
	local function consider(unit)
		local guid = UnitExists(unit) and UnitGUID(unit)
		if not guid or seen[guid] then return end
		if not eligible(unit, spellName) then return end
		seen[guid] = true
		local left = remaining(unit)
		if needs(left) then
			local _, class = UnitClass(unit)
			list[#list + 1] = {
				unit = unit, guid = guid, name = ns.FullName(unit), class = class,
				group = ns.InGroup(unit), left = left,
			}
		end
	end

	-- The target goes first, under its group token when it has one, so the
	-- button keeps pointing at the same person if the target changes.
	local group = groupUnits()
	local targetToken = UnitExists("target") and "target" or nil
	for _, u in ipairs(group) do
		if targetToken and UnitIsUnit(u, "target") then targetToken = u end
	end
	if targetToken then consider(targetToken) end
	for _, u in ipairs(group) do consider(u) end
	if ns.settings.strangers then
		for _, u in ipairs(plateUnits()) do consider(u) end
		consider("mouseover")
	end

	local plan
	local want = ns.settings.gift or 0
	if gift and want > 0 and IsInGroup() then
		local reagent = GIFT_REAGENT[gift]
		if not reagent or ns.ItemCount(reagent) > 0 then
			local count, first = {}, {}
			for _, e in ipairs(list) do
				if e.group then
					local sub = ns.Subgroup(e.unit)
					count[sub] = (count[sub] or 0) + 1
					first[sub] = first[sub] or e
				end
			end
			local bestSub, bestN = nil, 0
			for sub, n in pairs(count) do
				if n > bestN then bestSub, bestN = sub, n end
			end
			if bestN >= want then
				plan = { unit = first[bestSub].unit, count = bestN, spell = gift, reagent = reagent }
			end
		end
	end

	return list, plan, motw
end
