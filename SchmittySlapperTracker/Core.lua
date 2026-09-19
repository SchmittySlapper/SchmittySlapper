-- Schmitty Slapper Tracker: shared settings, Edit Mode wiring and the /sst command.
-- Two parts live in this addon: the health/power arcs (Arcs.lua) and the row
-- of abilities you just used (Casts.lua). Each part registers itself in
-- NS.modules and owns its own settings table inside SchmittySlapperTrackerDB.
--
-- Both parts are registered with Blizzard's HUD Edit Mode through LibEditMode:
-- open Edit Mode (Esc > Edit Mode, or /sst unlock) and they become selectable,
-- draggable frames with their own settings dialog and a corner grip that
-- rescales them. Positions are saved per Edit Mode layout.

local ADDON_NAME, NS = ...

NS.modules = {}
NS.order = { "arcs", "casts" }
NS.layoutName = "default"
NS.editing = false

local DEFAULTS = {
  scale = 1, -- master scale, multiplies each part's own scale
}

local db

function NS.Print(msg)
  print("|cff33ff99Schmitty Slapper|r: " .. msg)
end

function NS.MasterScale()
  return db and db.scale or 1
end

function NS.OnOff(v)
  return v and "on" or "off"
end

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

---------------------------------------------------------------------------
-- Edit Mode (LibEditMode), with a fallback when the client has no Edit Mode
---------------------------------------------------------------------------
local lib -- false once checked and unavailable

function NS.EditMode()
  if lib ~= nil then return lib or nil end
  local ok = EditModeManagerFrame and EditModeSystemSettingsDialog and LibStub
  local candidate = ok and LibStub("LibEditMode", true)
  if candidate and candidate.AddFrame and candidate.RegisterCallback then
    lib = candidate
  else
    lib = false
  end
  return lib or nil
end

-- Opens Blizzard's Edit Mode. Returns false when that is not possible.
function NS.OpenEditMode()
  if not NS.EditMode() then return false end
  if InCombatLockdown() then
    NS.Print("Edit Mode cannot open during combat")
    return true
  end
  if ShowUIPanel then ShowUIPanel(EditModeManagerFrame) else EditModeManagerFrame:Show() end
  return true
end

function NS.CloseEditMode()
  if not NS.EditMode() or not EditModeManagerFrame:IsShown() then return false end
  if HideUIPanel then HideUIPanel(EditModeManagerFrame) else EditModeManagerFrame:Hide() end
  return true
end

-- A grip in the bottom-right corner of a frame, shown only in Edit Mode.
-- Dragging it away from the frame's centre scales the frame up, towards
-- shrinks it. getScale/setScale read and write the part's own scale.
local grips = {}

function NS.AddResizeGrip(frame, getScale, setScale)
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(22, 22)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
  grip:SetFrameLevel(frame:GetFrameLevel() + 8)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:Hide()

  local startScale, startDist

  local function Distance()
    local cx, cy = GetCursorPosition()
    local fx, fy = frame:GetCenter()
    if not fx then return nil end
    local es = frame:GetEffectiveScale()
    fx, fy = fx * es, fy * es
    return math.sqrt((cx - fx) ^ 2 + (cy - fy) ^ 2)
  end

  grip:SetScript("OnMouseDown", function(self)
    startScale = getScale()
    startDist = Distance()
    if not startDist or startDist < 1 then startDist = nil return end
    self:SetScript("OnUpdate", function()
      local d = Distance()
      if not d then return end
      local s = startScale * d / startDist
      s = math.floor(math.max(0.4, math.min(3, s)) * 100 + 0.5) / 100
      if s ~= getScale() then setScale(s) end
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    startDist = nil
    if lib and lib.RefreshFrameSettings then pcall(lib.RefreshFrameSettings, lib, frame) end
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("Drag to resize")
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

  grips[#grips + 1] = grip
  return grip
end

local function SetEditing(on)
  NS.editing = on
  for _, g in ipairs(grips) do
    if on then g:Show() else g:Hide() end
  end
  for _, name in ipairs(NS.order) do
    NS.modules[name].OnEditMode(on)
  end
end

local function WireEditMode()
  local l = NS.EditMode()
  if not l then return end
  l:RegisterCallback("enter", function() SetEditing(true) end)
  l:RegisterCallback("exit", function() SetEditing(false) end)
  for _, name in ipairs(NS.order) do
    NS.modules[name].RegisterEditMode(l)
  end
  l:RegisterCallback("layout", function(layoutName)
    NS.layoutName = layoutName or "default"
    for _, name in ipairs(NS.order) do NS.modules[name].ApplyLayout() end
  end)
  if l:IsInEditMode() then SetEditing(true) end
end

---------------------------------------------------------------------------
-- Settings and start-up
---------------------------------------------------------------------------
-- Settings saved by the single-part version lived at the top level; move them
-- into the arcs table once.
local function Migrate()
  if db.arcs == nil then
    db.arcs = {}
    for _, k in ipairs({ "combatOnly", "linger", "fade", "exact", "alwaysText", "scale", "x", "y" }) do
      if db[k] ~= nil then
        db.arcs[k] = db[k]
        db[k] = nil
      end
    end
  end
  -- 1.2: the linger/fade defaults changed from 3/1 to 1/2. Saved values that
  -- still sit on the old defaults follow along; anything set by hand stays.
  if db.arcs.defaultsVersion == nil then
    if db.arcs.linger == 3 then db.arcs.linger = 1 end
    if db.arcs.fade == 1 then db.arcs.fade = 2 end
    db.arcs.defaultsVersion = 2
  end
end

local function Init()
  SchmittySlapperTrackerDB = SchmittySlapperTrackerDB or {}
  db = SchmittySlapperTrackerDB
  Migrate()
  CopyDefaults(db, DEFAULTS)
  for _, name in ipairs(NS.order) do
    local m = NS.modules[name]
    if type(db[name]) ~= "table" then db[name] = {} end
    CopyDefaults(db[name], m.DEFAULTS)
    m.Init(db[name])
  end
  WireEditMode()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
  if name ~= ADDON_NAME then return end
  self:UnregisterEvent("ADDON_LOADED")
  Init()
end)

---------------------------------------------------------------------------
-- /sst  (alias /slapper); /ssc goes straight to the casts part
---------------------------------------------------------------------------
local function Help()
  NS.Print("commands (also /slapper):")
  print("  /sst unlock - open HUD Edit Mode: drag the parts, use the corner grip to resize, click one for its settings")
  print("  /sst lock - close Edit Mode")
  print("  /sst test - show both parts for a moment")
  print("  /sst scale 1 - master size for both parts")
  print("  /sst reset - everything back to defaults")
  print("  /sst arcs ... - the health and power arcs:")
  NS.modules.arcs.Help("    /sst arcs")
  print("  /sst casts ... - the row of abilities you just used (or /ssc ...):")
  NS.modules.casts.Help("    /sst casts")
  print("  Arc commands also work without the word arcs, e.g. /sst combat off")
end

local function Dispatch(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()

  if cmd == "arcs" or cmd == "casts" then
    local sub, arg = rest:match("^(%S*)%s*(.-)$")
    if not NS.modules[cmd].Command(sub:lower(), arg) then Help() end
  elseif cmd == "test" then
    for _, name in ipairs(NS.order) do NS.modules[name].Test() end
  elseif cmd == "unlock" or cmd == "move" then
    if NS.OpenEditMode() then return end
    for _, name in ipairs(NS.order) do NS.modules[name].SetUnlocked(true) end
    NS.Print("both parts unlocked: drag the blue boxes, then /sst lock")
  elseif cmd == "lock" then
    if NS.CloseEditMode() then return end
    for _, name in ipairs(NS.order) do NS.modules[name].SetUnlocked(false) end
    NS.Print("both parts locked")
  elseif cmd == "scale" then
    local n = tonumber(rest)
    if n and n > 0.2 and n < 5 then db.scale = n end
    NS.Print("master scale " .. db.scale)
    for _, name in ipairs(NS.order) do NS.modules[name].ApplyLayout() end
  elseif cmd == "reset" then
    for k in pairs(db) do db[k] = nil end
    CopyDefaults(db, DEFAULTS)
    for _, name in ipairs(NS.order) do
      db[name] = {}
      CopyDefaults(db[name], NS.modules[name].DEFAULTS)
      NS.modules[name].Reset()
    end
    NS.Print("all settings reset")
  elseif cmd ~= "" and NS.modules.arcs.Command(cmd, rest) then
    return
  else
    Help()
  end
end

SLASH_SCHMITTYSLAPPERTRACKER1 = "/sst"
SLASH_SCHMITTYSLAPPERTRACKER2 = "/slapper"
SlashCmdList.SCHMITTYSLAPPERTRACKER = Dispatch

SLASH_SCHMITTYSLAPPERCASTS1 = "/ssc"
SLASH_SCHMITTYSLAPPERCASTS2 = "/casts"
SlashCmdList.SCHMITTYSLAPPERCASTS = function(msg)
  Dispatch("casts " .. (msg or ""))
end
