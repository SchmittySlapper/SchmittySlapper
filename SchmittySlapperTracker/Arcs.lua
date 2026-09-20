-- Schmitty Slapper Tracker: the health and power arcs.
-- A standalone port of the WeakAura "Status Bars - Health/Mana/Rage/Energy"
-- (https://wago.io/YH_XvKsqX). Layout, colors and timing come straight from
-- that aura's export.
--
-- WoW: Forever runs the 12.x engine, where the player's own health and power
-- are "secret" numbers: addons may hand them to native widgets but may not do
-- math, comparisons or even truth tests on them. So the fill is a StatusBar
-- (the client crops the arc texture itself) and the value text goes through
-- FontString:SetFormattedText. Nothing in this file touches a value directly.

local ADDON_NAME, NS = ...

local M = {}
NS.modules.arcs = M

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
local FRAME_W       = 2 * (BAR_X + BAR_W / 2) -- footprint of both arcs, used by Edit Mode
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

M.DEFAULTS = {
  enabled    = true,   -- /sst arcs off hides the arcs completely
  combatOnly = true,   -- true: arcs only in combat. false: always while alive
  showOnHeal = true,   -- also come up while being healed out of combat (food, bandages)
  linger     = 1,      -- seconds the arcs stay up after combat ends (0 = hide at once)
  fade       = 2,      -- seconds the arcs take to fade out
  exact      = true,   -- true: "1234/5678", false: "57%"
  alwaysText = false,  -- false: values only on mouseover
  scale      = 1.25,   -- WA group scale (times the master scale)
  x          = 0,      -- default offset from screen centre
  y          = -16,
  positions  = {},     -- per Edit Mode layout: { point, x, y }
}

local db
local parent, healthBar, powerBar, mover
local bars = {}
local visible = false
local editing = false
local inCombat, isDead = false, false
local lingerUntil, healShowUntil
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
-- Visibility: enabled, alive and (in combat, lingering, or always)
---------------------------------------------------------------------------
local function ShouldShow()
  if not db.enabled then return false end
  if editing then return true end
  if mover and mover:IsShown() then return true end
  if forceShowUntil and GetTime() < forceShowUntil then return true end
  if isDead then return false end
  if inCombat then return true end
  if healShowUntil and GetTime() < healShowUntil then return true end
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
  f:SetFrameLevel(parent:GetFrameLevel() + 1)
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
  parent:SetScale(NS.MasterScale() * db.scale)
  parent:ClearAllPoints()
  local pos = db.positions[NS.layoutName] or db.positions.default
  if pos then
    parent:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
  else
    parent:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
  end
  NS.Log("apply arcs " .. (pos and (pos.x .. "," .. pos.y) or "default") .. " layout=" .. tostring(NS.layoutName))
  for i = 1, #bars do
    bars[i].text:SetAlpha(db.alwaysText and 1 or 0)
  end
end

-- Fallback drag-to-move for clients without Edit Mode: a blue box over the
-- arcs while unlocked; the spot is saved as a CENTER offset.
local function SaveMoverPosition()
  NS.CapturePosition(parent, db, "arcs mover")
  ApplyLayout()
end

local function SetUnlocked(unlocked)
  if not mover then
    mover = CreateFrame("Frame", nil, parent)
    mover:SetAllPoints(parent)
    mover:SetFrameLevel(parent:GetFrameLevel() + 10)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(0, 0.6, 1, 0.25)
    mover.label = mover:CreateFontString(nil, "OVERLAY")
    mover.label:SetFont(FONT, 12, "OUTLINE")
    mover.label:SetPoint("CENTER", mover, "CENTER", 0, 0)
    mover.label:SetText("Arcs: drag me, then /sst lock")
    mover:SetScript("OnDragStart", function() parent:StartMoving() end)
    mover:SetScript("OnDragStop", function()
      parent:StopMovingOrSizing()
      SaveMoverPosition()
    end)
    parent:SetMovable(true)
    parent:SetClampedToScreen(true)
  end
  if unlocked then mover:Show() else mover:Hide() end
  UpdateVisibility()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, unit, kind)
  if not db.enabled then return end
  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
    UpdateHealth()
  elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
      or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
    UpdatePower()
  elseif event == "UNIT_COMBAT" then
    -- a heal landing on us out of combat (food, bandage, someone else): show
    -- the arcs, keep them while the ticks keep coming, then linger and fade
    if db.showOnHeal and not inCombat and Plain(kind) == "HEAL" then
      local hold = math.max(db.linger, 2.5)
      healShowUntil = GetTime() + hold
      C_Timer.After(hold + 0.05, UpdateVisibility)
      UpdateVisibility()
    end
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
  else -- PLAYER_ENTERING_WORLD, PLAYER_ALIVE, PLAYER_UNGHOST
    UpdateAll()
  end
end)

---------------------------------------------------------------------------
-- Module interface used by Core.lua
---------------------------------------------------------------------------
function M.Init(moduleDb)
  db = moduleDb

  parent = CreateFrame("Frame", "SchmittySlapperTrackerFrame", UIParent)
  parent:SetSize(FRAME_W, BAR_H)
  parent:SetFrameStrata("MEDIUM")
  parent:SetAlpha(0)
  parent:Hide()
  parent.editModeName = "Schmitty Slapper Arcs"

  healthBar = CreateBar("Health", -BAR_X, TEXTURE_LEFT,  -TEXT_X)
  powerBar  = CreateBar("Power",   BAR_X, TEXTURE_RIGHT,  TEXT_X)
  SetColors(healthBar, HEALTH_FG, HEALTH_BG)
  SetColors(powerBar, POWER_DEFAULT.fg, POWER_DEFAULT.bg)

  ApplyLayout()

  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("PLAYER_REGEN_DISABLED")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:RegisterEvent("PLAYER_DEAD")
  events:RegisterEvent("PLAYER_ALIVE")
  events:RegisterEvent("PLAYER_UNGHOST")
  events:RegisterUnitEvent("UNIT_HEALTH", "player")
  events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
  events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
  events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
  events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
  events:RegisterUnitEvent("UNIT_COMBAT", "player")
end

M.ApplyLayout = function() ApplyLayout() end
M.GetFrame = function() return parent end
M.Refresh = function() UpdateAll() end
M.SetEnabled = function(on)
  db.enabled = on and true or false
  if db.enabled then UpdateAll() else UpdateVisibility() end
end
M.SavePosition = function(source)
  if parent then NS.CapturePosition(parent, db, "arcs " .. (source or "")) end
end

function M.OnEditMode(on)
  editing = on
  UpdateVisibility()
end

function M.RegisterEditMode(lib)
  lib:AddFrame(parent, function()
    NS.CapturePosition(parent, db, "arcs lib")
  end, { point = "CENTER", x = M.DEFAULTS.x, y = M.DEFAULTS.y }, "Schmitty Slapper Arcs")

  local selection = lib.frameSelections and lib.frameSelections[parent]
  if selection then
    selection:SetFrameLevel(parent:GetFrameLevel() + 5)
    -- Drive the drag ourselves: move the real frame, then save where it landed.
    selection:RegisterForDrag("LeftButton")
    selection:SetScript("OnDragStart", function()
      if InCombatLockdown() then return end
      parent:SetMovable(true)
      parent:StartMoving()
    end)
    selection:SetScript("OnDragStop", function(self)
      parent:StopMovingOrSizing()
      NS.CapturePosition(parent, db, "arcs drag")
      ApplyLayout()
      self:ClearAllPoints()
      self:SetAllPoints(parent)
    end)
  end

  lib:AddFrameSettings(parent, {
    { kind = lib.SettingType.Slider, name = "Scale (%)", default = 125, minValue = 40, maxValue = 300, valueStep = 5,
      get = function() return math.floor(db.scale * 100 + 0.5) end,
      set = function(_, v) db.scale = v / 100 ApplyLayout() end },
    { kind = lib.SettingType.Checkbox, name = "Only in combat", default = true,
      get = function() return db.combatOnly end,
      set = function(_, v) db.combatOnly = v and true or false UpdateVisibility() end },
    { kind = lib.SettingType.Checkbox, name = "Also show while healing", default = true,
      get = function() return db.showOnHeal end,
      set = function(_, v) db.showOnHeal = v and true or false end },
    { kind = lib.SettingType.Slider, name = "Stay after combat (seconds)", default = 1, minValue = 0, maxValue = 15, valueStep = 1,
      get = function() return db.linger end,
      set = function(_, v) db.linger = v end },
    { kind = lib.SettingType.Slider, name = "Fade out (seconds)", default = 2, minValue = 0, maxValue = 5, valueStep = 0.5,
      get = function() return db.fade end,
      set = function(_, v) db.fade = v end },
    { kind = lib.SettingType.Checkbox, name = "Exact values (off = percent)", default = true,
      get = function() return db.exact end,
      set = function(_, v) db.exact = v and true or false UpdateHealth() UpdatePower() end },
    { kind = lib.SettingType.Checkbox, name = "Always show values", default = false,
      get = function() return db.alwaysText end,
      set = function(_, v) db.alwaysText = v and true or false ApplyLayout() end },
  })

  if lib.AddFrameSettingsButtons then
    lib:AddFrameSettingsButtons(parent, {
      { text = "Save position", click = function()
        NS.CapturePosition(parent, db, "arcs save button")
        NS.AnnounceSaved("arcs", db)
      end },
    })
  end
  NS.AddResizeGrip(parent, function() return db.scale end, function(s) db.scale = s ApplyLayout() end)
end

M.SetUnlocked = function(unlocked)
  if unlocked and not db.enabled then
    NS.Print("the arcs are off; /sst arcs on turns them back on")
    return
  end
  SetUnlocked(unlocked)
end

function M.Test()
  if not db.enabled then return end
  forceShowUntil = GetTime() + 10
  UpdateAll()
  C_Timer.After(10.1, UpdateVisibility)
end

function M.Reset()
  db = SchmittySlapperTrackerDB.arcs
  if mover then mover:Hide() end
  ApplyLayout()
  UpdateAll()
end

function M.Help(prefix)
  print(prefix .. " on|off - show or hide the arcs completely")
  print(prefix .. " scale 1.25 - size of the arcs")
  print(prefix .. " combat on|off - only show in combat (off = always while alive)")
  print(prefix .. " heal on|off - also show while being healed out of combat (food, bandages)")
  print(prefix .. " linger 1 - seconds the arcs stay up after combat ends (0 = at once)")
  print(prefix .. " fade 2 - seconds the fade-out takes")
  print(prefix .. " exact on|off - exact values or percent")
  print(prefix .. " text mouseover|always - when the values show")
  print(prefix .. " x 0  and  y -16 - position from screen centre")
  print(prefix .. " test - show the arcs for 10 seconds")
end

-- Returns true when the command was one of ours.
function M.Command(cmd, arg)
  local P = NS.Print
  if cmd == "on" or cmd == "off" or cmd == "toggle" then
    if cmd == "toggle" then db.enabled = not db.enabled else db.enabled = (cmd == "on") end
    if db.enabled then UpdateAll() else UpdateVisibility() end
    P("arcs " .. NS.OnOff(db.enabled))
  elseif cmd == "unlock" or cmd == "move" then
    if NS.OpenEditMode() then return true end
    M.SetUnlocked(true)
    if db.enabled then P("arcs unlocked: drag the blue box, then /sst lock") end
  elseif cmd == "lock" then
    if NS.CloseEditMode() then return true end
    SetUnlocked(false)
    P("arcs locked")
  elseif cmd == "scale" then
    local n = tonumber(arg)
    if n and n > 0.2 and n < 5 then db.scale = n end
    P("arcs scale " .. db.scale)
    ApplyLayout()
  elseif cmd == "combat" then
    if arg == "on" or arg == "off" then db.combatOnly = (arg == "on") end
    P("arcs only in combat: " .. NS.OnOff(db.combatOnly) .. (db.combatOnly and "" or " (always shown while alive)"))
    UpdateVisibility()
  elseif cmd == "heal" then
    if arg == "on" or arg == "off" then db.showOnHeal = (arg == "on") end
    P("arcs also show while healing: " .. NS.OnOff(db.showOnHeal))
  elseif cmd == "linger" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 600 then db.linger = n end
    P("arcs stay " .. db.linger .. " seconds after combat ends")
    UpdateVisibility()
  elseif cmd == "fade" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 30 then db.fade = n end
    P("arcs fade out over " .. db.fade .. " seconds")
  elseif cmd == "exact" then
    if arg == "on" or arg == "off" then db.exact = (arg == "on") end
    P("exact values: " .. NS.OnOff(db.exact) .. (db.exact and " (1234/5678)" or " (percent)"))
    UpdateHealth()
    UpdatePower()
  elseif cmd == "text" then
    if arg == "always" or arg == "mouseover" then db.alwaysText = (arg == "always") end
    P("arc values shown: " .. (db.alwaysText and "always" or "on mouseover"))
    ApplyLayout()
  elseif cmd == "x" or cmd == "y" then
    local n = tonumber(arg)
    local pos = db.positions[NS.layoutName] or { point = "CENTER", x = db.x, y = db.y }
    if pos.point ~= "CENTER" then pos = { point = "CENTER", x = db.x, y = db.y } end
    if n then pos[cmd] = n end
    db.positions[NS.layoutName] = pos
    P("arcs offset x " .. pos.x .. ", y " .. pos.y)
    ApplyLayout()
  elseif cmd == "test" then
    M.Test()
    P(db.enabled and "showing the arcs for 10 seconds" or "the arcs are off; /sst arcs on first")
  else
    return false
  end
  return true
end
