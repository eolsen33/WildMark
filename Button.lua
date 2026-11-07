local _, ns = ...

-- The visible button is a SecureActionButton. Out of combat we point it at
-- the next player who needs the buff; a click or the bound key casts.

local CLICK = "CLICK WildMarkButton:LeftButton"
BINDING_HEADER_WILDMARK = "WildMark"
_G["BINDING_NAME_" .. CLICK] = "Buff the next ally"
BINDING_NAME_WILDMARK_SKIP = "Skip the current ally"

local MARK_ICON = "Interface\\Icons\\Spell_Nature_Regeneration"
local GREY, GREEN, RED = "|cff9d9d9d", "|cff3fc17f", "|cffff5555"

local frame, grip, button, icon, text, sub
local queue, plan = {}, nil
local armed -- unit token the button currently casts on
local dirty, since, pendingArm = true, 0, false

local function colored(name, class)
	local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class]
	if c and name then
		local function byte(v) return math.floor(v * 255 + 0.5) end
		return string.format("|cff%02x%02x%02x%s|r", byte(c.r), byte(c.g), byte(c.b), name)
	end
	return name or "?"
end

local function keyText()
	local key = GetBindingKey(CLICK)
	if not key then return nil end
	return GetBindingText and GetBindingText(key) or key
end

local function arm(unit, spellName)
	if InCombatLockdown() then pendingArm = true return end
	pendingArm = false
	if unit == armed and unit ~= nil and button:GetAttribute("spell") == spellName then return end
	armed = unit
	if unit then
		button:SetAttribute("type1", "spell")
		button:SetAttribute("spell", spellName)
		button:SetAttribute("unit", unit)
	else
		button:SetAttribute("type1", nil)
		button:SetAttribute("unit", nil)
	end
end

local function idleHint()
	if ns.settings.strangers and not IsInGroup() and ns.GetCVar("nameplateShowFriends") ~= "1" then
		return "Friendly nameplates are off: /wm plates"
	end
	local key = keyText()
	return key and (key .. " buffs the next one") or "Set a key: Key Bindings > AddOns"
end

local function update()
	dirty, since = false, 0
	if not ns.isDruid or not frame then return end
	local list, giftPlan, motw = ns.Scan()
	queue, plan = list, giftPlan
	local s = ns.settings

	if not motw then
		arm(nil)
		icon:SetTexture(MARK_ICON)
		text:SetText(GREY .. "Mark of the Wild not learned|r")
		sub:SetText("")
		frame:SetShown(not s.hidden and not s.autoHide)
		return
	end

	local markName, markIcon = ns.SpellInfo(motw)
	local castId, castName, unit = motw, markName, nil
	if giftPlan then
		castId, unit = giftPlan.spell, giftPlan.unit
		castName = ns.SpellInfo(castId)
	elseif list[1] then
		unit = list[1].unit
	end
	arm(unit, castName)

	local inCombat = InCombatLockdown()
	if not unit then
		icon:SetTexture(markIcon or MARK_ICON)
		icon:SetDesaturated(true)
		text:SetText(GREEN .. "Everyone is marked|r")
		sub:SetText(GREY .. idleHint() .. "|r")
		frame:SetShown(not s.hidden and not s.autoHide)
		return
	end

	local _, castIcon = ns.SpellInfo(castId)
	icon:SetTexture(castIcon or MARK_ICON)
	icon:SetDesaturated(false)
	local e = list[1]
	if giftPlan then
		text:SetText(castName .. GREY .. " for " .. giftPlan.count .. " in group|r")
	else
		local more = #list - 1
		text:SetText(colored(e.name, e.class) .. (more > 0 and (GREY .. "  +" .. more .. "|r") or ""))
	end

	local line
	local cost = ns.ManaCost(castId)
	if cost and UnitPower("player", 0) < cost then
		line = RED .. "Not enough mana|r"
	elseif inCombat then
		line = RED .. "In combat: the target updates when it ends|r"
	elseif pendingArm then
		line = GREY .. "Updating...|r"
	else
		local key = keyText()
		line = GREY .. (key and ("Click or " .. key) or "Click") .. " to buff, right-click skips|r"
		if e.left and e.left > 0 and e.left < math.huge and not giftPlan then
			line = GREY .. string.format("%d min left. ", math.ceil(e.left / 60)) .. "|r" .. line
		end
	end
	sub:SetText(line)
	frame:SetShown(not s.hidden)
end

function ns.Refresh() dirty = true end

ns.events:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if (dirty and since >= 0.2) or since >= 1 then update() end
end)

function ns.Skip()
	local e = queue[1]
	if not e then return end
	ns.skipped[e.guid] = GetTime() + (ns.settings.skipFor or 600)
	ns.Print("skipping " .. (e.name or "?") .. " for " .. math.ceil((ns.settings.skipFor or 600) / 60) .. " min")
	ns.Refresh()
end

function WildMark_Skip() ns.Skip() end

function ns.Toggle()
	ns.settings.hidden = not ns.settings.hidden
	if not ns.settings.hidden then ns.settings.autoHide = false end
	ns.Print(ns.settings.hidden and "hidden. /wm brings it back." or "shown")
	ns.Refresh()
end

-- Layout ---------------------------------------------------------------

local function savePoint()
	local point, _, rel, x, y = frame:GetPoint()
	ns.settings.point = { point, rel, x, y }
end

function ns.Layout()
	if not frame then return end
	local s = ns.settings
	frame:SetScale(s.scale or 1)
	frame:ClearAllPoints()
	if s.point then
		frame:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
	grip:SetShown(not s.locked)
end

local function tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("WildMark")
	if #queue == 0 then
		GameTooltip:AddLine("Nobody in range needs Mark of the Wild.", 1, 1, 1)
	else
		GameTooltip:AddLine(#queue .. " need the buff:", 1, 1, 1)
		for i = 1, math.min(#queue, 12) do
			local e = queue[i]
			local where = e.group and "group" or "nearby"
			local left = (e.left > 0 and e.left < math.huge) and string.format(", %d min left", math.ceil(e.left / 60)) or ""
			GameTooltip:AddDoubleLine((i == 1 and "> " or "   ") .. colored(e.name, e.class), where .. left, 1, 1, 1, 0.7, 0.7, 0.7)
		end
		if #queue > 12 then GameTooltip:AddLine("  and " .. (#queue - 12) .. " more", 0.7, 0.7, 0.7) end
		if plan then GameTooltip:AddLine("Gift of the Wild covers " .. plan.count .. " of your group.", 0.4, 1, 0.6) end
	end
	GameTooltip:AddLine(" ")
	local key = keyText()
	GameTooltip:AddLine(GREY .. "Left-click" .. (key and (" or " .. key) or "") .. ":|r buff", 1, 1, 1)
	GameTooltip:AddLine(GREY .. "Right-click:|r skip this player for " .. math.ceil((ns.settings.skipFor or 600) / 60) .. " min", 1, 1, 1)
	GameTooltip:AddLine(GREY .. "/wm help|r for settings", 1, 1, 1)
	GameTooltip:Show()
end

function ns.Build()
	if frame then return end
	frame = CreateFrame("Frame", "WildMarkFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	frame:SetSize(236, 62)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.65)
		frame:SetBackdropBorderColor(0.45, 0.45, 0.45)
	end

	grip = CreateFrame("Frame", nil, frame)
	grip:SetPoint("TOPLEFT", 3, -3)
	grip:SetPoint("TOPRIGHT", -3, -3)
	grip:SetHeight(14)
	grip:EnableMouse(true)
	grip:RegisterForDrag("LeftButton")
	grip:SetScript("OnDragStart", function() frame:StartMoving() end)
	grip:SetScript("OnDragStop", function() frame:StopMovingOrSizing() savePoint() end)
	local title = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", 0, -1)
	title:SetText(GREY .. "WildMark  (drag)|r")
	local stripe = grip:CreateTexture(nil, "BACKGROUND")
	stripe:SetAllPoints()
	stripe:SetColorTexture(1, 1, 1, 0.04)

	button = CreateFrame("Button", "WildMarkButton", frame, "SecureActionButtonTemplate")
	button:SetPoint("TOPLEFT", 4, -17)
	button:SetPoint("BOTTOMRIGHT", -4, 4)
	button:SetAttribute("useOnKeyDown", false)
	button:RegisterForClicks("AnyDown", "AnyUp")
	local hl = button:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)

	icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(32, 32)
	icon:SetPoint("LEFT", 3, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetTexture(MARK_ICON)

	text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
	text:SetPoint("RIGHT", -4, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)

	sub = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
	sub:SetPoint("RIGHT", -4, 0)
	sub:SetJustifyH("LEFT")
	sub:SetWordWrap(false)

	button:SetScript("PostClick", function(_, mouse, down)
		if down then return end
		if mouse == "RightButton" then ns.Skip() else ns.Refresh() end
	end)
	button:SetScript("OnEnter", tooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	ns.Layout()

	for _, ev in ipairs({
		"UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
		"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
		"UNIT_POWER_UPDATE", "UPDATE_BINDINGS", "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA",
	}) do ns.On(ev, ns.Refresh) end
	ns.On("PLAYER_REGEN_ENABLED", update)
end
