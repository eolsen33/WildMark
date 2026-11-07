local ADDON, ns = ...

-- WildMark: find allies who need Mark of the Wild, arm one secure button with
-- the next one, and let a click or a key cast it. Addons cannot cast on their
-- own, so the button does the casting and this code only decides who is next.

local DEFAULTS = {
	renew = 180,       -- rebuff when fewer than this many seconds remain (0 = only when missing)
	gift = 3,          -- use Gift of the Wild when this many group members need it (0 = never)
	strangers = true,  -- include friendly players outside your group (needs friendly nameplates)
	autoHide = false,  -- hide the button while nobody needs the buff
	skipFor = 600,     -- a right-click skip lasts this many seconds
	locked = false,    -- hide the drag handle
	hidden = false,
	scale = 1,
}

ns.events = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	handlers[event] = handlers[event] or {}
	table.insert(handlers[event], fn)
	pcall(ns.events.RegisterEvent, ns.events, event)
end

ns.events:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

function ns.Print(...)
	DEFAULT_CHAT_FRAME:AddMessage("|cff3fc17fWildMark|r: " .. string.join(" ", tostringall(...)))
end

-- API shims: Forever has the modern C_* namespaces, older clients the globals.

function ns.SpellInfo(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if info then return info.name, info.iconID end
		return nil
	end
	if GetSpellInfo then
		local name, _, icon = GetSpellInfo(id)
		return name, icon
	end
end

function ns.Known(id)
	if IsPlayerSpell then return IsPlayerSpell(id) and true or false end
	if IsSpellKnown then return IsSpellKnown(id) and true or false end
	return false
end

-- True unless the game says the unit is definitely out of range.
function ns.InRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local r = C_Spell.IsSpellInRange(spell, unit)
		if r == nil then return true end
		return r == true or r == 1
	end
	if IsSpellInRange then
		local r = IsSpellInRange(spell, unit)
		if r == nil then return true end
		return r == 1
	end
	return true
end

function ns.ManaCost(id)
	local costs
	if C_Spell and C_Spell.GetSpellPowerCost then
		costs = C_Spell.GetSpellPowerCost(id)
	elseif GetSpellPowerCost then
		costs = GetSpellPowerCost(id)
	end
	if type(costs) ~= "table" then return nil end
	for _, c in ipairs(costs) do
		if c.type == 0 then return c.cost end
	end
	return nil
end

local unitBuff = _G.UnitBuff
if not unitBuff and C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
	unitBuff = function(unit, i)
		local a = C_UnitAuras.GetBuffDataByIndex(unit, i, "HELPFUL")
		if not a then return nil end
		return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit, nil, nil, a.spellId
	end
end
ns.UnitBuff = unitBuff or function() return nil end

ns.ItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount or function() return 0 end

-- Forever characters have a first and a last name; GetUnitName(unit, true)
-- returns both, UnitName only the first.
function ns.FullName(unit)
	local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
	if name then name = name:gsub("%-[^%-]*$", "") end
	return name
end

function ns.GetCVar(name)
	local f = (C_CVar and C_CVar.GetCVar) or GetCVar
	local ok, v = pcall(f, name)
	return ok and v or nil
end

function ns.SetCVar(name, value)
	local f = (C_CVar and C_CVar.SetCVar) or SetCVar
	return pcall(f, name, value)
end

-- Saved variables ------------------------------------------------------

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	WildMarkDB = WildMarkDB or {}
	WildMarkDB.settings = WildMarkDB.settings or {}
	for k, v in pairs(DEFAULTS) do
		if WildMarkDB.settings[k] == nil then WildMarkDB.settings[k] = v end
	end
	WildMarkDB.ignore = WildMarkDB.ignore or {}
	ns.db = WildMarkDB
	ns.settings = WildMarkDB.settings
end)

ns.On("PLAYER_LOGIN", function()
	local _, class = UnitClass("player")
	ns.isDruid = class == "DRUID"
	if not ns.isDruid then
		ns.Print("this character is not a druid, so WildMark is idle here.")
		return
	end
	ns.Build()
	ns.Refresh()
end)

-- Slash commands -------------------------------------------------------

local function seconds(n)
	n = tonumber(n)
	return n and math.max(0, math.floor(n))
end

local function onOff(v) return v and "|cff3fc17fon|r" or "|cffff5555off|r" end

local commands = {}

commands.help = function()
	ns.Print("commands")
	local lines = {
		"/wm - show or hide the button",
		"/wm ignore <name> | unignore <name> | ignores - never buff this player",
		"/wm clear - forget every right-click skip",
		"/wm renew <seconds> - rebuff when less than this remains (" .. ns.settings.renew .. ")",
		"/wm gift <n> - Gift of the Wild when n group members need it, 0 = never (" .. ns.settings.gift .. ")",
		"/wm strangers - include friendly players outside your group (" .. (ns.settings.strangers and "on" or "off") .. ")",
		"/wm plates - toggle friendly nameplates, which strangers need",
		"/wm autohide - hide the button when nobody needs the buff (" .. (ns.settings.autoHide and "on" or "off") .. ")",
		"/wm lock - hide or show the drag handle",
		"/wm scale <n> - button size (" .. ns.settings.scale .. ")",
		"/wm skipfor <seconds> - how long a right-click skip lasts (" .. ns.settings.skipFor .. ")",
		"/wm list - who needs the buff right now",
		"/wm reset - default settings and position",
	}
	for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
	DEFAULT_CHAT_FRAME:AddMessage("  Bind a key under Key Bindings > AddOns > WildMark. Right-click the button to skip the current player.")
end

commands.ignore = function(name)
	if not name or name == "" then return commands.help() end
	ns.db.ignore[name:lower()] = true
	ns.Print("ignoring " .. name)
	ns.Refresh()
end

commands.unignore = function(name)
	if not name or name == "" then return commands.help() end
	ns.db.ignore[name:lower()] = nil
	ns.Print("no longer ignoring " .. name)
	ns.Refresh()
end

commands.ignores = function()
	local list = {}
	for name in pairs(ns.db.ignore) do list[#list + 1] = name end
	table.sort(list)
	ns.Print(#list == 0 and "ignoring nobody" or ("ignoring: " .. table.concat(list, ", ")))
end

commands.clear = function()
	ns.skipped = {}
	ns.Print("skips cleared")
	ns.Refresh()
end

commands.renew = function(v)
	v = seconds(v)
	if not v then return commands.help() end
	ns.settings.renew = v
	ns.Print(v == 0 and "rebuffing only when the buff is missing" or ("rebuffing when under " .. v .. " seconds remain"))
	ns.Refresh()
end

commands.gift = function(v)
	v = seconds(v)
	if not v then return commands.help() end
	ns.settings.gift = v
	ns.Print(v == 0 and "Gift of the Wild off" or ("Gift of the Wild when " .. v .. " or more group members need it"))
	ns.Refresh()
end

commands.strangers = function()
	ns.settings.strangers = not ns.settings.strangers
	ns.Print("players outside your group", onOff(ns.settings.strangers))
	ns.Refresh()
end

commands.plates = function()
	local on = ns.GetCVar("nameplateShowFriends") == "1"
	if on then
		ns.SetCVar("nameplateShowFriends", "0")
	else
		ns.SetCVar("nameplateShowFriends", "1")
		ns.SetCVar("nameplateShowFriendlyPlayers", "1")
	end
	ns.Print("friendly nameplates", onOff(not on))
	ns.Refresh()
end

commands.autohide = function()
	ns.settings.autoHide = not ns.settings.autoHide
	ns.Print("auto-hide", onOff(ns.settings.autoHide))
	ns.Refresh()
end

commands.lock = function()
	ns.settings.locked = not ns.settings.locked
	ns.Print(ns.settings.locked and "locked: drag handle hidden" or "unlocked: drag the handle above the button")
	ns.Layout()
end

commands.scale = function(v)
	v = tonumber(v)
	if not v or v < 0.5 or v > 3 then return ns.Print("scale must be between 0.5 and 3") end
	ns.settings.scale = v
	ns.Layout()
end

commands.skipfor = function(v)
	v = seconds(v)
	if not v then return commands.help() end
	ns.settings.skipFor = v
	ns.Print("a right-click skip now lasts " .. v .. " seconds")
end

commands.list = function()
	local list, gift = ns.Scan()
	if #list == 0 then return ns.Print("nobody in range needs Mark of the Wild") end
	ns.Print(#list .. " need the buff" .. (gift and (", Gift of the Wild would cover " .. gift.count) or ""))
	for i, e in ipairs(list) do
		local left = e.left > 0 and string.format(" (%d min left)", math.ceil(e.left / 60)) or ""
		DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s  %s  %s%s", i, e.name or "?", e.unit, e.group and "group" or "nearby", left))
	end
end

commands.reset = function()
	for k, v in pairs(DEFAULTS) do ns.settings[k] = v end
	ns.settings.point = nil
	ns.Layout()
	ns.Print("settings and position reset")
	ns.Refresh()
end

SLASH_WILDMARK1, SLASH_WILDMARK2 = "/wm", "/wildmark"
SlashCmdList.WILDMARK = function(msg)
	if not ns.isDruid then return ns.Print("this character is not a druid.") end
	local cmd, rest = msg:match("^%s*(%S+)%s*(.-)%s*$")
	if not cmd then return ns.Toggle() end
	local fn = commands[cmd:lower()]
	if fn then fn(rest) else commands.help() end
end
