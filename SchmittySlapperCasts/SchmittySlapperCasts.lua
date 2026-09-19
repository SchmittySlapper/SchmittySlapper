-- Schmitty Slapper Casts: a row of icons showing the abilities you just used.
-- Player-only take on TrufiGCD. Each successful cast pushes a new icon in at
-- the anchor end; older icons slide along, then fade out after a hold time.
--
-- WoW: Forever runs the 12.x engine with secret values. Your own cast events
-- stay readable, but every value from the client is still treated as
-- possibly secret: nothing is compared before it has been checked, and every
-- C_Spell call is wrapped so a refused value skips the icon instead of erroring.

local ADDON_NAME = ...

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local DEFAULTS = {
  x         = 0,        -- offset from screen centre
  y         = -160,     -- just under the Schmitty Slapper Tracker arcs
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

local TEST_SPELLS = { 1752, 2098, 5171, 1766, 1776, 1784 } -- rogue: Sinister Strike, Eviscerate, Slice and Dice, Kick, Gouge, Stealth

local db
local parent
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
  f:EnableMouse(true)
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

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function ApplyLayout()
  parent:SetSize(db.count * db.size + (db.count - 1) * db.gap, db.size)
  parent:ClearAllPoints()
  parent:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
  for i = 1, #active do
    active[i]:SetSize(db.size, db.size)
    PlaceIcon(active[i])
  end
end

local function Init()
  SchmittySlapperCastsDB = SchmittySlapperCastsDB or {}
  db = SchmittySlapperCastsDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then
      if type(v) == "table" then
        db[k] = {}
        for kk, vv in pairs(v) do db[k][kk] = vv end
      else
        db[k] = v
      end
    end
  end

  parent = CreateFrame("Frame", "SchmittySlapperCastsFrame", UIParent)
  parent:SetFrameStrata("MEDIUM")
  ApplyLayout()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    Init()
    self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  else
    OnCastEvent(event, ...)
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Print(msg)
  print("|cff33ff99Schmitty Slapper Casts|r: " .. msg)
end

local function ResolveSpell(arg)
  local id = tonumber(arg)
  if id then return id end
  local ok, info = pcall(C_Spell.GetSpellInfo, arg)
  if ok and type(info) == "table" then return Plain(info.spellID) end
end

SLASH_SCHMITTYSLAPPERCASTS1 = "/ssc"
SLASH_SCHMITTYSLAPPERCASTS2 = "/casts"
SlashCmdList.SCHMITTYSLAPPERCASTS = function(msg)
  msg = msg or ""
  local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()

  if cmd == "test" then
    for i, id in ipairs(TEST_SPELLS) do
      C_Timer.After((i - 1) * 0.5, function() TryAdd(id, true) end)
    end
    Print("showing sample casts")
  elseif cmd == "size" or cmd == "count" or cmd == "gap" or cmd == "hold" then
    local n = tonumber(arg)
    local limits = { size = { 12, 128 }, count = { 1, 20 }, gap = { 0, 40 }, hold = { 1, 60 } }
    if n and n >= limits[cmd][1] and n <= limits[cmd][2] then db[cmd] = n end
    Print(cmd .. " " .. db[cmd])
    ApplyLayout()
  elseif cmd == "x" or cmd == "y" then
    local n = tonumber(arg)
    if n then db[cmd] = n end
    Print("offset x " .. db.x .. ", y " .. db.y)
    ApplyLayout()
  elseif cmd == "direction" then
    if arg == "left" or arg == "right" then db.direction = arg end
    Print("direction " .. db.direction .. " (newest icon at the " .. (db.direction == "left" and "right" or "left") .. " end)")
    ApplyLayout()
  elseif cmd == "ignore" then
    local id = ResolveSpell(arg)
    if not id then
      Print("usage: /ssc ignore <spell id or exact name>")
      return
    end
    db.ignore[id] = not db.ignore[id] or nil
    Print((db.ignore[id] and "now ignoring " or "no longer ignoring ") .. (SpellName(id) or "spell") .. " (" .. id .. ")")
  elseif cmd == "list" then
    local ids = {}
    for id in pairs(db.ignore) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then Print("ignoring nothing") return end
    Print("ignored:")
    for _, id in ipairs(ids) do
      print("  " .. (SpellName(id) or "unknown") .. " (" .. id .. ")")
    end
  elseif cmd == "reset" then
    for k, v in pairs(DEFAULTS) do
      if type(v) == "table" then
        db[k] = {}
        for kk, vv in pairs(v) do db[k][kk] = vv end
      else
        db[k] = v
      end
    end
    ApplyLayout()
    Print("settings reset")
  else
    Print("commands:")
    print("  /ssc test - show a few sample icons")
    print("  /ssc size 36 - icon size")
    print("  /ssc count 6 - how many icons stay on screen")
    print("  /ssc gap 4 - space between icons")
    print("  /ssc hold 4 - seconds before an icon fades")
    print("  /ssc direction right|left - which way older icons move")
    print("  /ssc x 0  and  /ssc y -160 - position from screen centre")
    print("  /ssc ignore <spell id or name> - hide a spell (again to undo); /ssc list shows them")
    print("  /ssc reset")
  end
end
