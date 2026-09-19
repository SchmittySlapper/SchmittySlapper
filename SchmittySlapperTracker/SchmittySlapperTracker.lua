-- Schmitty Slapper Tracker: health/power arcs around the character.
-- A standalone port of the WeakAura "Status Bars - Health/Mana/Rage/Energy"
-- (https://wago.io/YH_XvKsqX). Layout, colors and timing come straight from
-- that aura's export.
--
-- WoW: Forever runs the 12.x engine, where the player's own health and power
-- are "secret" numbers: addons may hand them to native widgets but may not do
-- math, comparisons or even truth tests on them. So the fill is a StatusBar
-- (the client crops the arc texture itself) and the value text goes through
-- FontString:SetFormattedText. Nothing in this file touches a value directly.

local ADDON_NAME = ...

---------------------------------------------------------------------------
-- Constants lifted from the WeakAura
---------------------------------------------------------------------------
-- The WeakAura showed a crop of the PowerAuras "Aura3" texture (crop_x 4,
-- crop_y 0.75, user_x +/-0.33). ArcLeft/ArcRight are that exact window baked
-- into their own files so a StatusBar can fill the whole texture.
local TEXTURE_LEFT  = "Interface\\AddOns\\SchmittySlapperTracker\\Textures\\ArcLeft"
local TEXTURE_RIGHT = "Interface\\AddOns\\SchmittySlapperTracker\\Textures\\ArcRight"
local FONT          = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" -- "Friz Quadrata TT"
local FONT_SIZE     = 10
local BAR_W, BAR_H  = 56.4, 161.14285714286
local BAR_X         = 100      -- arc centre offset from the group centre
local TEXT_X        = 118      -- value text centre offset
local FADE_IN       = 0.25     -- WA "fade" animation preset; fade-out length is the `fade` setting

-- WA smoothed the fill in Lua; with secret values only the client can, so use
-- the native StatusBar interpolation when the client offers it.
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local HEALTH_FG = { 0, 1, 0, 0.5 }
local HEALTH_BG = { 0, 0.50196078431373, 0, 0.25 }
local POWER_COLORS = {
  [0] = { fg = { 0.13333333333333, 0.13333333333333, 1, 0.5 },
          bg = { 0.066666666666667, 0.066666666666667, 0.50196078431373, 0.25 } }, -- mana
  [1] = { fg = { 1, 0, 0, 0.5 }, bg = { 0.50196078431373, 0, 0, 0.25 } },           -- rage
  [3] = { fg = { 1, 1, 0, 0.5 }, bg = { 0.50196078431373, 0.50196078431373, 0, 0.25 } }, -- energy
}
local POWER_DEFAULT = { fg = { 1, 1, 1, 0.5 },
                        bg = { 0.50196078431373, 0.50196078431373, 0.50196078431373, 0.25 } }
local CLASS_POWER = { WARRIOR = 1, ROGUE = 3 } -- fallback if the power type itself is secret

local DEFAULTS = {
  combatOnly = true,   -- true: arcs only in combat. false: always while alive
  linger     = 3,      -- seconds the arcs stay up after combat ends (0 = hide at once)
  fade       = 1,      -- seconds the arcs take to fade out
  exact      = true,   -- true: "1234/5678", false: "57%"
  alwaysText = false,  -- false: values only on mouseover
  scale      = 1.25,   -- WA group scale
  x          = 0,      -- WA group offset from screen centre
  y          = -16,
}

local db
local parent, healthBar, powerBar
local bars = {}
local visible = false
local inCombat, isDead = false, false
local lingerUntil
local alpha, alphaTarget = 0, 0
local forceShowUntil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local issecret = rawget(_G, "issecretvalue")

-- Plain (non-secret) copy of a value, or nil. Only used for things we must
-- branch on: power type, combat and death flags. Never used on health/power.
local function Plain(v)
  if issecret and issecret(v) then return nil end
  return v
end

local function SetValueText(text, cur, max, percent)
  if db.exact then
    text:SetFormattedText("%d/%d", cur, max)
  else
    text:SetFormattedText("%.0f%%", percent)
  end
end

local function SetColors(bar, fg, bg)
  bar:SetStatusBarColor(fg[1], fg[2], fg[3], fg[4])
  bar.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
end

---------------------------------------------------------------------------
-- Fade driver (one OnUpdate on the parent, only while fading)
---------------------------------------------------------------------------
local function OnUpdate(self, dt)
  local step = dt / (alpha < alphaTarget and FADE_IN or math.max(db.fade, 0.05))
  if alpha < alphaTarget then
    alpha = math.min(alphaTarget, alpha + step)
  else
    alpha = math.max(alphaTarget, alpha - step)
  end
  self:SetAlpha(alpha)
  if alpha == alphaTarget then
    self:SetScript("OnUpdate", nil)
    if alpha == 0 then self:Hide() end
  end
end

---------------------------------------------------------------------------
-- Visibility: alive and (in combat, or always when combatOnly is off)
---------------------------------------------------------------------------
local function ShouldShow()
  if forceShowUntil and GetTime() < forceShowUntil then return true end
  if isDead then return false end
  if inCombat then return true end
  if lingerUntil and GetTime() < lingerUntil then return true end
  return not db.combatOnly
end

local UpdateHealth, UpdatePower

local function UpdateVisibility()
  local show = ShouldShow()
  if show == visible then return end
  visible = show
  alphaTarget = show and 1 or 0
  if show then
    -- WA reset its smoothing when a region was shown again: snap to current
    UpdateHealth(true)
    UpdatePower(true)
    parent:Show()
  end
  parent:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- Value updates (secret-safe: values only flow into widgets)
---------------------------------------------------------------------------
function UpdateHealth(snap)
  local cur, max = UnitHealth("player"), UnitHealthMax("player")
  healthBar:SetMinMaxValues(0, max)
  healthBar:SetValue(cur, (not snap and visible) and INTERP or nil)
  SetValueText(healthBar.text, cur, max, UnitHealthPercent("player"))
end

local function CurrentPowerType()
  local ptype = Plain(UnitPowerType("player"))
  if ptype == nil then
    local _, class = UnitClass("player")
    ptype = CLASS_POWER[class] or 0
  end
  return ptype
end

function UpdatePower(snap)
  local ptype = CurrentPowerType()
  if ptype ~= powerBar.ptype then
    powerBar.ptype = ptype
    local c = POWER_COLORS[ptype] or POWER_DEFAULT
    SetColors(powerBar, c.fg, c.bg)
  end
  local cur, max = UnitPower("player", ptype), UnitPowerMax("player", ptype)
  powerBar:SetMinMaxValues(0, max)
  powerBar:SetValue(cur, (not snap and visible) and INTERP or nil)
  SetValueText(powerBar.text, cur, max, UnitPowerPercent("player", ptype))
end

local function UpdateState()
  inCombat = Plain(InCombatLockdown()) and true or false
  local dead = Plain(UnitIsDeadOrGhost("player"))
  isDead = dead and true or false
end

local function UpdateAll()
  UpdateState()
  UpdateHealth()
  UpdatePower()
  UpdateVisibility()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function PrepareTexture(tex)
  tex:SetBlendMode("BLEND")
  tex:SetSnapToPixelGrid(false)
  tex:SetTexelSnappingBias(0)
end

local function CreateBar(name, xOffset, texture, textX)
  local f = CreateFrame("StatusBar", "SchmittySlapperTracker" .. name, parent)
  f:SetSize(BAR_W, BAR_H)
  f:SetPoint("CENTER", parent, "CENTER", xOffset, 0)
  f:SetOrientation("VERTICAL") -- WA "VERTICAL": fills from the bottom up
  f:SetMinMaxValues(0, 1)
  f:SetValue(1)
  f:EnableMouse(true)
  f:SetMouseClickEnabled(false) -- hover only; clicks and camera drags go through

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetTexture(texture)
  f.bg:SetAllPoints(f)
  PrepareTexture(f.bg)

  f:SetStatusBarTexture(texture, "ARTWORK")
  PrepareTexture(f:GetStatusBarTexture())

  local text = f:CreateFontString(nil, "OVERLAY")
  text:SetFont(FONT, FONT_SIZE, "OUTLINE")
  text:SetJustifyH("CENTER")
  text:SetTextColor(1, 1, 1, 1)
  text:SetPoint("CENTER", parent, "CENTER", textX, 0)
  text:SetAlpha(db.alwaysText and 1 or 0)
  f.text = text

  f:SetScript("OnEnter", function() text:SetAlpha(1) end)
  f:SetScript("OnLeave", function()
    if not db.alwaysText then text:SetAlpha(0) end
  end)

  bars[#bars + 1] = f
  return f
end

local function ApplyLayout()
  parent:SetScale(db.scale)
  parent:ClearAllPoints()
  parent:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
  for i = 1, #bars do
    bars[i].text:SetAlpha(db.alwaysText and 1 or 0)
  end
end

local function Init()
  SchmittySlapperTrackerDB = SchmittySlapperTrackerDB or {}
  db = SchmittySlapperTrackerDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end

  parent = CreateFrame("Frame", "SchmittySlapperTrackerFrame", UIParent)
  parent:SetSize(2, 2)
  parent:SetFrameStrata("MEDIUM")
  parent:SetAlpha(0)
  parent:Hide()

  healthBar = CreateBar("Health", -BAR_X, TEXTURE_LEFT,  -TEXT_X)
  powerBar  = CreateBar("Power",   BAR_X, TEXTURE_RIGHT,  TEXT_X)
  SetColors(healthBar, HEALTH_FG, HEALTH_BG)
  SetColors(powerBar, POWER_DEFAULT.fg, POWER_DEFAULT.bg)

  ApplyLayout()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    Init()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_DEAD")
    self:RegisterEvent("PLAYER_ALIVE")
    self:RegisterEvent("PLAYER_UNGHOST")
    self:RegisterUnitEvent("UNIT_HEALTH", "player")
    self:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    self:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    self:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    self:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    self:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
  elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
    UpdateHealth()
  elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
      or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
    UpdatePower()
  elseif event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    lingerUntil = nil
    UpdateVisibility()
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    if db.linger > 0 then
      lingerUntil = GetTime() + db.linger
      C_Timer.After(db.linger + 0.05, UpdateVisibility)
    end
    UpdateVisibility()
  elseif event == "PLAYER_DEAD" then
    isDead = true
    UpdateVisibility()
  elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    UpdateAll()
  else -- PLAYER_ENTERING_WORLD
    UpdateAll()
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Print(msg)
  print("|cff33ff99Schmitty Slapper Tracker|r: " .. msg)
end

local function OnOff(v) return v and "on" or "off" end

SLASH_SCHMITTYSLAPPERTRACKER1 = "/sst"
SLASH_SCHMITTYSLAPPERTRACKER2 = "/slapper"
SlashCmdList.SCHMITTYSLAPPERTRACKER = function(msg)
  msg = (msg or ""):lower()
  local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")

  if cmd == "combat" then
    if arg == "on" or arg == "off" then db.combatOnly = (arg == "on") end
    Print("only show in combat: " .. OnOff(db.combatOnly)
      .. (db.combatOnly and "" or " (arcs always shown while alive)"))
    UpdateVisibility()
  elseif cmd == "linger" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 600 then db.linger = n end
    Print("arcs stay " .. db.linger .. " seconds after combat ends")
    UpdateVisibility()
  elseif cmd == "fade" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 30 then db.fade = n end
    Print("arcs fade out over " .. db.fade .. " seconds")
  elseif cmd == "exact" then
    if arg == "on" or arg == "off" then db.exact = (arg == "on") end
    Print("exact values: " .. OnOff(db.exact) .. (db.exact and " (1234/5678)" or " (percent)"))
    UpdateHealth()
    UpdatePower()
  elseif cmd == "text" then
    if arg == "always" or arg == "mouseover" then db.alwaysText = (arg == "always") end
    Print("values shown: " .. (db.alwaysText and "always" or "on mouseover"))
    ApplyLayout()
  elseif cmd == "scale" then
    local n = tonumber(arg)
    if n and n > 0.2 and n < 5 then db.scale = n end
    Print("scale " .. db.scale)
    ApplyLayout()
  elseif cmd == "x" or cmd == "y" then
    local n = tonumber(arg)
    if n then db[cmd] = n end
    Print("offset x " .. db.x .. ", y " .. db.y)
    ApplyLayout()
  elseif cmd == "test" then
    forceShowUntil = GetTime() + 10
    UpdateAll()
    C_Timer.After(10.1, UpdateVisibility)
    Print("showing the arcs for 10 seconds")
  elseif cmd == "reset" then
    for k, v in pairs(DEFAULTS) do db[k] = v end
    ApplyLayout()
    UpdateAll()
    Print("settings reset")
  else
    Print("commands:")
    print("  /sst test - show the arcs for 10 seconds")
    print("  /sst combat on|off - only show in combat (off = always while alive)")
    print("  /sst linger 3 - seconds the arcs stay up after combat ends (0 = hide at once)")
    print("  /sst fade 1 - seconds the fade-out takes")
    print("  /sst exact on|off - exact values or percent")
    print("  /sst text mouseover|always - when the values show")
    print("  /sst scale 1.25 - size")
    print("  /sst x 0  and  /sst y -16 - position from screen centre")
    print("  /sst reset")
  end
end
