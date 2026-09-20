-- Schmitty Slapper Tracker: the row of abilities you just used.
-- Player-only take on TrufiGCD. Each successful cast pushes a new icon in at
-- the anchor end; older icons slide along, then fade out after a hold time.
--
-- Your own cast events stay readable on WoW: Forever, but every value from
-- the client is still treated as possibly secret: nothing is compared before
-- it has been checked, and every C_Spell call is wrapped so a refused value
-- skips the icon instead of erroring.

local ADDON_NAME, NS = ...

local M = {}
NS.modules.casts = M

M.DEFAULTS = {
  enabled   = true,     -- /sst casts off hides the row and stops tracking
  tooltip   = true,     -- hovering an icon shows its spell tooltip
  scale     = 1,        -- size of the whole row (times the master scale)
  x         = 0,        -- default offset from screen centre
  y         = -160,     -- just under the arcs
  positions = {},       -- per Edit Mode layout: { point, x, y }
  size      = 36,       -- icon size in pixels
  gap       = 4,        -- space between icons
  count     = 6,        -- icons kept on screen
  hold      = 4,        -- seconds an icon stays before fading
  direction = "right",  -- newest icon at the left, older ones move right ("left" mirrors it)
  ignore    = {         -- TrufiGCD's defaults
    [6603] = true,      -- Attack
    [75]   = true,      -- Auto Shot
    [7384] = true,      -- Overpower
  },
}

local FADE_IN   = 0.15   -- seconds for a new icon to appear
local FADE_OUT  = 1.0    -- seconds to fade after the hold time
local DROP_OUT  = 0.3    -- seconds to fade an icon pushed past the row
local EASE      = 14     -- slide easing per second
local STALE     = 10     -- seconds after which a cast in progress is forgotten
local FALLBACK_ICON = 134400 -- question mark, test mode only
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local FONT  = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local TEST_SPELLS = { 1752, 2098, 5171, 1766, 1776, 1784 } -- rogue: Sinister Strike, Eviscerate, Slice and Dice, Kick, Gouge, Stealth

local db
local parent, mover
local editing = false
local pool, active = {}, {}    -- active: newest first
local casting, cancelled       -- cast in progress / cast that was cancelled
local lastName, lastID         -- last spell added, for the helper-cast filter

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local issecret = rawget(_G, "issecretvalue")

local function Plain(v)
  if issecret and issecret(v) then return nil end
  return v
end

local function SpellIcon(id)
  local ok, icon = pcall(C_Spell.GetSpellTexture, id)
  if ok then return Plain(icon) end
end

local function SpellName(id)
  local ok, name = pcall(C_Spell.GetSpellName, id)
  if ok then return Plain(name) end
end

local function Step()
  return db.size + db.gap
end

local function PlaceIcon(f)
  f:ClearAllPoints()
  if db.direction == "left" then
    f:SetPoint("RIGHT", parent, "RIGHT", -f.pos * Step(), 0)
  else
    f:SetPoint("LEFT", parent, "LEFT", f.pos * Step(), 0)
  end
end

---------------------------------------------------------------------------
-- Animation driver (one OnUpdate on the parent, only while icons are shown)
---------------------------------------------------------------------------
local function OnUpdate(self, dt)
  local now = GetTime()
  local k = math.min(1, dt * EASE)

  if casting and now - casting.time > STALE then casting = nil end

  local i = 1
  while i <= #active do
    local f = active[i]

    if f.pos ~= f.slot then
      f.pos = f.pos + (f.slot - f.pos) * k
      if math.abs(f.pos - f.slot) < 0.002 then f.pos = f.slot end
      PlaceIcon(f)
    end

    local age = now - f.born
    if f.dying then
      f.alpha = f.alpha - dt / DROP_OUT
    elseif age > db.hold then
      f.alpha = math.min(f.alpha, 1 - (age - db.hold) / FADE_OUT)
    else
      f.alpha = math.min(1, f.alpha + dt / FADE_IN)
    end

    if f.alpha <= 0 then
      f:Hide()
      table.remove(active, i)
      pool[#pool + 1] = f
      if casting and casting.frame == f then casting = nil end
      if cancelled and cancelled.frame == f then cancelled = nil end
    else
      f:SetAlpha(f.alpha)
      i = i + 1
    end
  end

  if #active == 0 then
    self:SetScript("OnUpdate", nil)
  end
end

local function Wake()
  parent:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function OnEnter(f)
  if not f.spellID then return end
  GameTooltip:SetOwner(f, "ANCHOR_TOP")
  local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, f.spellID)
  if ok then GameTooltip:Show() else GameTooltip:Hide() end
end

local function OnLeave()
  GameTooltip:Hide()
end

local function CreateIcon()
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(db.size, db.size)
  f:SetFrameLevel(parent:GetFrameLevel() + 1)
  f:EnableMouse(db.tooltip)
  f:SetMouseClickEnabled(false) -- tooltip on hover; clicks go through to the world

  f.border = f:CreateTexture(nil, "BACKGROUND")
  f.border:SetColorTexture(0, 0, 0, 0.8)
  f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
  f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints(f)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  f.cross = f:CreateTexture(nil, "OVERLAY")
  f.cross:SetAllPoints(f)
  f.cross:SetTexture(CROSS)
  f.cross:Hide()

  f:SetScript("OnEnter", OnEnter)
  f:SetScript("OnLeave", OnLeave)
  f:Hide()
  return f
end

local function AddIcon(spellID, icon)
  for i = 1, #active do
    active[i].slot = active[i].slot + 1
  end

  local f = table.remove(pool) or CreateIcon()
  f.spellID = spellID
  f.icon:SetTexture(icon)
  f.cross:Hide()
  f.slot, f.pos = 0, -1
  f.alpha, f.born, f.dying = 0, GetTime(), nil
  f:SetSize(db.size, db.size)
  f:EnableMouse(db.tooltip)
  f:SetMouseClickEnabled(false)
  f:SetAlpha(0)
  PlaceIcon(f)
  f:Show()
  table.insert(active, 1, f)

  for i = db.count + 1, #active do
    active[i].dying = true
  end

  Wake()
  return f
end

-- Adds an icon for a spell unless it is ignored, has no icon, or looks like a
-- helper cast (same name as the previous spell but a different ID).
local function TryAdd(spellID, allowFallback)
  if db.ignore[spellID] then return end
  local icon = SpellIcon(spellID)
  if not icon and allowFallback then icon = FALLBACK_ICON end
  if not icon then return end
  local name = SpellName(spellID)
  if name and name == lastName and spellID ~= lastID then return end
  lastName, lastID = name, spellID
  return AddIcon(spellID, icon)
end

local function ClearIcons()
  for i = #active, 1, -1 do
    active[i]:Hide()
    pool[#pool + 1] = active[i]
    active[i] = nil
  end
  casting, cancelled = nil, nil
  parent:SetScript("OnUpdate", nil)
end

---------------------------------------------------------------------------
-- Cast events (same rules TrufiGCD uses)
---------------------------------------------------------------------------
local function OnCastEvent(event, unit, castGUID, spellID)
  spellID = Plain(spellID)
  if not spellID then return end
  castGUID = Plain(castGUID)

  if event == "UNIT_SPELLCAST_START" then
    if not castGUID then return end -- no cast id: a helper cast, e.g. a druid form change
    local f = TryAdd(spellID)
    if f then casting = { guid = castGUID, id = spellID, name = lastName, frame = f, time = GetTime() } end

  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    local f = TryAdd(spellID)
    if f then casting = { guid = "channel", id = spellID, name = lastName, frame = f, time = GetTime() } end

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if cancelled and castGUID and cancelled.guid == castGUID then
      cancelled.frame.cross:Hide() -- it landed after all
      cancelled = nil
      return
    end
    if casting then
      if casting.id == spellID then
        if casting.guid ~= "channel" then casting = nil end -- the cast finished
      elseif SpellName(spellID) ~= casting.name then
        TryAdd(spellID) -- an instant used during a cast or channel
      end
    else
      TryAdd(spellID)
    end

  elseif event == "UNIT_SPELLCAST_STOP" then
    if not casting or casting.guid == "channel" then return end
    casting.frame.cross:Show() -- stopped without succeeding: cancelled
    cancelled = casting
    casting = nil

  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    casting = nil
  end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
  if db.enabled then OnCastEvent(event, ...) end
end)

---------------------------------------------------------------------------
-- Layout, drag-to-move
---------------------------------------------------------------------------
local function ApplyLayout()
  parent:SetScale(NS.MasterScale() * db.scale)
  parent:SetSize(db.count * db.size + (db.count - 1) * db.gap, db.size)
  parent:ClearAllPoints()
  local pos = db.positions[NS.layoutName] or db.positions.default
  if pos then
    parent:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
  else
    parent:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
  end
  NS.Log("apply casts " .. (pos and (pos.x .. "," .. pos.y) or "default") .. " layout=" .. tostring(NS.layoutName))
  for i = 1, #active do
    active[i]:SetSize(db.size, db.size)
    active[i]:EnableMouse(db.tooltip)
    active[i]:SetMouseClickEnabled(false)
    PlaceIcon(active[i])
  end
  for i = 1, #pool do
    pool[i]:EnableMouse(db.tooltip)
    pool[i]:SetMouseClickEnabled(false)
  end
end

-- Fallback drag-to-move for clients without Edit Mode.
local function SaveMoverPosition()
  NS.CapturePosition(parent, db, "casts mover")
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
    mover.label:SetFont(FONT, 11, "OUTLINE")
    mover.label:SetPoint("CENTER", mover, "CENTER", 0, 0)
    mover.label:SetText("Abilities: drag me, then /sst lock")
    mover:SetScript("OnDragStart", function() parent:StartMoving() end)
    mover:SetScript("OnDragStop", function()
      parent:StopMovingOrSizing()
      SaveMoverPosition()
    end)
    parent:SetMovable(true)
    parent:SetClampedToScreen(true)
  end
  if unlocked then
    mover:Show()
    parent:Show()
  else
    mover:Hide()
    if not db.enabled then parent:Hide() end
  end
end

---------------------------------------------------------------------------
-- Module interface used by Core.lua
---------------------------------------------------------------------------
function M.Init(moduleDb)
  db = moduleDb
  parent = CreateFrame("Frame", "SchmittySlapperCastsFrame", UIParent)
  parent:SetFrameStrata("MEDIUM")
  parent.editModeName = "Schmitty Slapper Abilities"
  ApplyLayout()
  if not db.enabled then parent:Hide() end

  events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
  events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
  events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
  events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
end

M.ApplyLayout = function() ApplyLayout() end
M.GetFrame = function() return parent end
M.Refresh = function() ApplyLayout() end
M.SetEnabled = function(on)
  db.enabled = on and true or false
  if db.enabled then
    parent:Show()
  else
    ClearIcons()
    if mover then mover:Hide() end
    if not editing then parent:Hide() end
  end
end
M.SavePosition = function(source)
  if parent then NS.CapturePosition(parent, db, "casts " .. (source or "")) end
end

function M.OnEditMode(on)
  editing = on
  if on then
    parent:Show()
  elseif not db.enabled then
    parent:Hide()
  end
end

function M.RegisterEditMode(lib)
  lib:AddFrame(parent, function()
    NS.CapturePosition(parent, db, "casts lib")
  end, { point = "CENTER", x = M.DEFAULTS.x, y = M.DEFAULTS.y }, "Schmitty Slapper Abilities")

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
      NS.CapturePosition(parent, db, "casts drag")
      ApplyLayout()
      self:ClearAllPoints()
      self:SetAllPoints(parent)
    end)
  end

  lib:AddFrameSettings(parent, {
    { kind = lib.SettingType.Slider, name = "Scale (%)", default = 100, minValue = 40, maxValue = 300, valueStep = 5,
      get = function() return math.floor(db.scale * 100 + 0.5) end,
      set = function(_, v) db.scale = v / 100 ApplyLayout() end },
    { kind = lib.SettingType.Slider, name = "Icon size", default = 36, minValue = 16, maxValue = 64, valueStep = 2,
      get = function() return db.size end,
      set = function(_, v) db.size = v ApplyLayout() end },
    { kind = lib.SettingType.Slider, name = "Icons kept", default = 6, minValue = 1, maxValue = 12, valueStep = 1,
      get = function() return db.count end,
      set = function(_, v) db.count = v ApplyLayout() end },
    { kind = lib.SettingType.Slider, name = "Spacing", default = 4, minValue = 0, maxValue = 20, valueStep = 1,
      get = function() return db.gap end,
      set = function(_, v) db.gap = v ApplyLayout() end },
    { kind = lib.SettingType.Slider, name = "Seconds before fading", default = 4, minValue = 1, maxValue = 15, valueStep = 1,
      get = function() return db.hold end,
      set = function(_, v) db.hold = v end },
    { kind = lib.SettingType.Dropdown, name = "Newest icon", default = "right",
      values = { { text = "On the left, older move right", value = "right" }, { text = "On the right, older move left", value = "left" } },
      get = function() return db.direction end,
      set = function(_, v) db.direction = v ApplyLayout() end },
    { kind = lib.SettingType.Checkbox, name = "Spell tooltips on hover", default = true,
      get = function() return db.tooltip end,
      set = function(_, v) db.tooltip = v and true or false ApplyLayout() end },
  })

  if lib.AddFrameSettingsButtons then
    lib:AddFrameSettingsButtons(parent, {
      { text = "Save position", click = function()
        NS.CapturePosition(parent, db, "ability row save button")
        NS.AnnounceSaved("ability row", db)
      end },
    })
  end
  NS.AddResizeGrip(parent, function() return db.scale end, function(s) db.scale = s ApplyLayout() end)
end

M.SetUnlocked = function(unlocked)
  if unlocked and not db.enabled then
    NS.Print("the ability row is off; /sst casts on turns it back on")
    return
  end
  SetUnlocked(unlocked)
end

function M.Test()
  if not db.enabled then return end
  for i, id in ipairs(TEST_SPELLS) do
    C_Timer.After((i - 1) * 0.5, function() TryAdd(id, true) end)
  end
end

function M.Reset()
  db = SchmittySlapperTrackerDB.casts
  if mover then mover:Hide() end
  ClearIcons()
  parent:Show()
  ApplyLayout()
end

local function ResolveSpell(arg)
  local id = tonumber(arg)
  if id then return id end
  local ok, info = pcall(C_Spell.GetSpellInfo, arg)
  if ok and type(info) == "table" then return Plain(info.spellID) end
end

function M.Help(prefix)
  print(prefix .. " on|off - show or hide the ability row completely")
  print(prefix .. " scale 1 - size of the whole row")
  print(prefix .. " tooltip on|off - spell tooltip when hovering an icon")
  print(prefix .. " size 36 / count 6 / gap 4 - icon size, how many, spacing")
  print(prefix .. " hold 4 - seconds before an icon fades")
  print(prefix .. " direction right|left - which way older icons move")
  print(prefix .. " x 0  and  y -160 - position from screen centre")
  print(prefix .. " ignore <spell id or name> - hide a spell (again to undo); list shows them")
  print(prefix .. " test - show a few sample icons")
end

-- Returns true when the command was one of ours.
function M.Command(cmd, arg)
  local P = NS.Print
  if cmd == "on" or cmd == "off" or cmd == "toggle" then
    if cmd == "toggle" then db.enabled = not db.enabled else db.enabled = (cmd == "on") end
    if db.enabled then
      parent:Show()
    else
      ClearIcons()
      if mover then mover:Hide() end
      if not editing then parent:Hide() end
    end
    P("ability row " .. NS.OnOff(db.enabled))
  elseif cmd == "unlock" or cmd == "move" then
    if NS.OpenEditMode() then return true end
    M.SetUnlocked(true)
    if db.enabled then P("ability row unlocked: drag the blue box, then /sst lock") end
  elseif cmd == "lock" then
    if NS.CloseEditMode() then return true end
    SetUnlocked(false)
    P("ability row locked")
  elseif cmd == "scale" then
    local n = tonumber(arg)
    if n and n > 0.2 and n < 5 then db.scale = n end
    P("ability row scale " .. db.scale)
    ApplyLayout()
  elseif cmd == "tooltip" then
    if arg == "on" or arg == "off" then db.tooltip = (arg == "on") end
    P("ability tooltips " .. NS.OnOff(db.tooltip))
    ApplyLayout()
  elseif cmd == "size" or cmd == "count" or cmd == "gap" or cmd == "hold" then
    local n = tonumber(arg)
    local limits = { size = { 12, 128 }, count = { 1, 20 }, gap = { 0, 40 }, hold = { 1, 60 } }
    if n and n >= limits[cmd][1] and n <= limits[cmd][2] then db[cmd] = n end
    P("ability row " .. cmd .. " " .. db[cmd])
    ApplyLayout()
  elseif cmd == "x" or cmd == "y" then
    local n = tonumber(arg)
    local pos = db.positions[NS.layoutName] or { point = "CENTER", x = db.x, y = db.y }
    if pos.point ~= "CENTER" then pos = { point = "CENTER", x = db.x, y = db.y } end
    if n then pos[cmd] = n end
    db.positions[NS.layoutName] = pos
    P("ability row offset x " .. pos.x .. ", y " .. pos.y)
    ApplyLayout()
  elseif cmd == "direction" then
    if arg == "left" or arg == "right" then db.direction = arg end
    P("ability row direction " .. db.direction .. " (newest icon at the " .. (db.direction == "left" and "right" or "left") .. " end)")
    ApplyLayout()
  elseif cmd == "ignore" then
    local id = ResolveSpell(arg)
    if not id then
      P("usage: /sst casts ignore <spell id or exact name>")
      return true
    end
    db.ignore[id] = not db.ignore[id] or nil
    P((db.ignore[id] and "now ignoring " or "no longer ignoring ") .. (SpellName(id) or "spell") .. " (" .. id .. ")")
  elseif cmd == "list" then
    local ids = {}
    for id in pairs(db.ignore) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then
      P("ignoring nothing")
      return true
    end
    P("ignored:")
    for _, id in ipairs(ids) do
      print("  " .. (SpellName(id) or "unknown") .. " (" .. id .. ")")
    end
  elseif cmd == "test" then
    M.Test()
    P(db.enabled and "showing sample casts" or "the ability row is off; /sst casts on first")
  else
    return false
  end
  return true
end
