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
  macroMirror = true, -- keep settings in a macro, since Forever never reads saved variables back
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

-- Saves a frame's current spot as a CENTER offset from the middle of the
-- screen, in the frame's own scale, under the active Edit Mode layout and as
-- the last known position. Called after drags, when Edit Mode closes, and at
-- logout or reload, so a move can never be lost.
-- Troubleshooting trail kept in the saved settings (last 60 lines): /sst log
function NS.Log(msg)
  if not db then return end
  db.log = db.log or {}
  table.insert(db.log, date("%H:%M:%S") .. " " .. msg)
  while #db.log > 60 do table.remove(db.log, 1) end
end

-- A frame's centre as an offset from the middle of the screen, in its own scale.
function NS.Offset(frame)
  local px, py = frame:GetCenter()
  if not px then return nil end
  local ux, uy = UIParent:GetCenter()
  local ps, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
  return math.floor((px * ps - ux * us) / ps + 0.5), math.floor((py * ps - uy * us) / ps + 0.5)
end

function NS.Centers()
  local parts = {}
  for _, name in ipairs(NS.order) do
    local f = NS.modules[name].GetFrame and NS.modules[name].GetFrame()
    local x, y
    if f then x, y = NS.Offset(f) end
    parts[#parts + 1] = name .. "=" .. (x and (x .. "," .. y) or "?")
  end
  return table.concat(parts, " ")
end

function NS.CapturePosition(frame, moduleDb, source)
  local x, y = NS.Offset(frame)
  if not x then return end
  local pos = { point = "CENTER", x = x, y = y }
  moduleDb.positions[NS.layoutName or "default"] = pos
  moduleDb.positions.default = pos
  NS.Log("capture " .. (source or "?") .. " -> " .. x .. "," .. y)
end

function NS.AnnounceSaved(label, moduleDb)
  local pos = moduleDb.positions.default
  if pos then NS.Print(label .. " position saved: x " .. pos.x .. ", y " .. pos.y) end
end

-- The Edit Mode library lives in a separate load-on-demand addon
-- (SchmittySlapperEditMode) so nothing else gets loaded in the middle of this
-- addon's own load: doing that left the saved settings unread at login.
-- Called from ADDON_LOADED, after the saved settings are in.
function NS.LoadEditModeLibs()
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if not load then return end
  local had = EditModeManagerFrame ~= nil
  if not had then pcall(load, "Blizzard_EditMode") end
  local ok, loaded = pcall(load, "SchmittySlapperEditMode")
  NS.Log("edit mode preloaded: " .. tostring(had) .. "; library addon loaded: " .. tostring(ok and loaded))
end

function NS.SaveAllPositions(source)
  for _, name in ipairs(NS.order) do
    local m = NS.modules[name]
    if m.SavePosition then m.SavePosition(source) end
  end
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
  -- Blizzard hides the Edit Mode window during login too; only a real
  -- editing session should end with a position capture.
  if on == NS.editing then return end
  NS.editing = on
  if on then
    -- restore saved spots first, in case something moved the frames since login
    for _, name in ipairs(NS.order) do NS.modules[name].ApplyLayout() end
    NS.Log("edit mode opened; " .. NS.Centers())
  else
    NS.Log("edit mode closed; " .. NS.Centers())
  end
  for _, g in ipairs(grips) do
    if on then g:Show() else g:Hide() end
  end
  for _, name in ipairs(NS.order) do
    NS.modules[name].OnEditMode(on)
  end
  if not on then NS.SaveAllPositions("exit") end
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

---------------------------------------------------------------------------
-- Options panel: Esc > Options > AddOns > Schmitty Slapper Tracker (or /sst)
---------------------------------------------------------------------------
local category

local function CreateOptionsPanel()
  if not Settings or not Settings.RegisterVerticalLayoutCategory or not Settings.RegisterProxySetting
      or not Settings.CreateControlTextContainer or not CreateSettingsButtonInitializer then
    return
  end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("Schmitty Slapper Tracker")
  local B, N, S = Settings.VarType.Boolean, Settings.VarType.Number, Settings.VarType.String
  local arcs, casts = NS.modules.arcs, NS.modules.casts
  local A, C = db.arcs, db.casts

  local function Header(text)
    if CreateSettingsListSectionHeaderInitializer then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
  end

  local function Checkbox(var, tbl, defaults, key, name, tooltip, after)
    Settings.CreateCheckbox(category,
      Settings.RegisterProxySetting(category, "SST_" .. var, B, name, defaults[key] and true or false,
        function() return tbl[key] end,
        function(v)
          tbl[key] = v and true or false
          if after then after(tbl[key]) end
        end),
      tooltip)
  end

  -- factor: the stored value times this is what the slider shows (100 for percent)
  local function Slider(var, tbl, defaults, key, name, minV, maxV, step, fmt, tooltip, after, factor)
    local opts = Settings.CreateSliderOptions(minV, maxV, step)
    opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
    local default = factor and math.floor(defaults[key] * factor + 0.5) or defaults[key]
    Settings.CreateSlider(category,
      Settings.RegisterProxySetting(category, "SST_" .. var, N, name, default,
        function()
          if factor then return math.floor(tbl[key] * factor + 0.5) end
          return tbl[key]
        end,
        function(v)
          tbl[key] = factor and (v / factor) or v
          if after then after() end
        end),
      opts, tooltip)
  end

  local pct = function(v) return v .. "%" end
  local secs = function(v) return ("%.1f s"):format(v) end
  local plain = function(v) return v end
  local master = { scale = 1 }
  local function Everything() for _, n in ipairs(NS.order) do NS.modules[n].ApplyLayout() end end

  Header("Both parts")
  Slider("MASTER", db, master, "scale", "Master size", 40, 300, 5, pct, "Size of both parts together.", Everything, 100)
  layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Open Edit Mode", function()
    if not NS.OpenEditMode() then
      for _, n in ipairs(NS.order) do NS.modules[n].SetUnlocked(true) end
    end
  end, "Move and resize both parts in HUD Edit Mode.", true))
  layout:AddInitializer(CreateSettingsButtonInitializer("Preview", "Show both parts", function()
    for _, n in ipairs(NS.order) do NS.modules[n].Test() end
  end, "Shows the arcs and a few sample ability icons for a moment.", true))

  Header("Health and power arcs")
  Checkbox("ARCS_ENABLED", A, arcs.DEFAULTS, "enabled", "Show the arcs", "Turn the arcs off entirely.", arcs.SetEnabled)
  Checkbox("ARCS_COMBAT", A, arcs.DEFAULTS, "combatOnly", "Only in combat", "Off: the arcs stay up whenever you are alive.", arcs.Refresh)
  Checkbox("ARCS_HEAL", A, arcs.DEFAULTS, "showOnHeal", "Also show while healing", "The arcs come up while you eat or bandage out of combat, then linger and fade.", arcs.Refresh)
  Slider("ARCS_LINGER", A, arcs.DEFAULTS, "linger", "Stay after combat (seconds)", 0, 15, 0.5, secs, "How long the arcs stay after combat ends before they start fading. 0 fades at once.")
  Slider("ARCS_FADE", A, arcs.DEFAULTS, "fade", "Fade out (seconds)", 0, 5, 0.5, secs, "How long the fade-out takes.")
  Checkbox("ARCS_EXACT", A, arcs.DEFAULTS, "exact", "Exact values (off = percent)", "How the hover values read.", arcs.Refresh)
  Checkbox("ARCS_TEXT", A, arcs.DEFAULTS, "alwaysText", "Always show values", "Values stay visible beside the arcs instead of on hover only.", arcs.ApplyLayout)
  Slider("ARCS_SCALE", A, arcs.DEFAULTS, "scale", "Arcs size", 40, 300, 5, pct, "Size of the arcs alone. 125% is the WeakAura size.", arcs.ApplyLayout, 100)

  Header("Ability row")
  Checkbox("CASTS_ENABLED", C, casts.DEFAULTS, "enabled", "Show the ability row", "Turn the row off entirely.", casts.SetEnabled)
  Checkbox("CASTS_TOOLTIP", C, casts.DEFAULTS, "tooltip", "Spell tooltips on hover", "Off also stops the icons catching the mouse.", casts.ApplyLayout)
  Slider("CASTS_SCALE", C, casts.DEFAULTS, "scale", "Row size", 40, 300, 5, pct, "Size of the whole row.", casts.ApplyLayout, 100)
  Slider("CASTS_SIZE", C, casts.DEFAULTS, "size", "Icon size", 16, 64, 2, plain, "Icon size in pixels.", casts.ApplyLayout)
  Slider("CASTS_COUNT", C, casts.DEFAULTS, "count", "Icons kept", 1, 12, 1, plain, "How many icons stay on screen.", casts.ApplyLayout)
  Slider("CASTS_GAP", C, casts.DEFAULTS, "gap", "Spacing", 0, 20, 1, plain, "Space between icons.", casts.ApplyLayout)
  Slider("CASTS_HOLD", C, casts.DEFAULTS, "hold", "Seconds before fading", 1, 15, 1, secs, "How long an icon stays before it fades.")
  local function DirOptions()
    local c = Settings.CreateControlTextContainer()
    c:Add("right", "Newest on the left, older move right")
    c:Add("left", "Newest on the right, older move left")
    return c:GetData()
  end
  Settings.CreateDropdown(category,
    Settings.RegisterProxySetting(category, "SST_CASTS_DIR", S, "Direction", "right",
      function() return C.direction end,
      function(v) C.direction = v casts.ApplyLayout() end),
    DirOptions, "Which way older icons move.")

  Settings.RegisterAddOnCategory(category)
end

local function OpenOptions()
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Settings persistence on WoW: Forever. The beta client never reads its own
-- SavedVariables back (Blizzard bug), so settings are mirrored into a general
-- macro named SSTsave1 (body: "/sst restore ...") and restored from it at
-- login. Goes quiet on its own if the game ever loads saved variables again.
---------------------------------------------------------------------------
local MACRO_PREFIX, MACRO_CMD = "SSTsave", "/sst"
local lastPayload, pendingSync, restored, warnedMacro, ticker

local function Snapshot()
  local A, C = db.arcs, db.casts
  local t = {
    S = db.scale,
    Ae = A.enabled, Ac = A.combatOnly, Ah = A.showOnHeal, Al = A.linger, Af = A.fade,
    Ax = A.exact, At = A.alwaysText, As = A.scale,
    Ce = C.enabled, Ct = C.tooltip, Cs = C.scale, Cz = C.size, Cn = C.count, Cg = C.gap,
    Ch = C.hold, Cd = C.direction,
  }
  local ap = A.positions.default
  if ap then t.AX, t.AY = ap.x, ap.y end
  local cp = C.positions.default
  if cp then t.CX, t.CY = cp.x, cp.y end
  local ids = {}
  for id in pairs(C.ignore) do ids[#ids + 1] = id end
  table.sort(ids)
  t.Ci = table.concat(ids, ".")
  return t
end

local function ApplySnapshot(t)
  local A, C = db.arcs, db.casts
  local function num(k, tbl, key) local v = tonumber(t[k]) if v then tbl[key] = v end end
  local function bool(k, tbl, key) if t[k] == "1" then tbl[key] = true elseif t[k] == "0" then tbl[key] = false end end
  local function str(k, tbl, key) if t[k] and t[k] ~= "" then tbl[key] = t[k] end end
  num("S", db, "scale")
  bool("Ae", A, "enabled") bool("Ac", A, "combatOnly") bool("Ah", A, "showOnHeal")
  num("Al", A, "linger") num("Af", A, "fade") bool("Ax", A, "exact") bool("At", A, "alwaysText") num("As", A, "scale")
  if tonumber(t.AX) and tonumber(t.AY) then A.positions.default = { point = "CENTER", x = tonumber(t.AX), y = tonumber(t.AY) } end
  bool("Ce", C, "enabled") bool("Ct", C, "tooltip") num("Cs", C, "scale") num("Cz", C, "size") num("Cn", C, "count")
  num("Cg", C, "gap") num("Ch", C, "hold") str("Cd", C, "direction")
  if tonumber(t.CX) and tonumber(t.CY) then C.positions.default = { point = "CENTER", x = tonumber(t.CX), y = tonumber(t.CY) } end
  if t.Ci then
    C.ignore = {}
    for id in t.Ci:gmatch("[^.]+") do if tonumber(id) then C.ignore[tonumber(id)] = true end end
  end
end

local function ApplyAll()
  for _, n in ipairs(NS.order) do NS.modules[n].ApplyLayout() end
  NS.modules.arcs.Refresh()
  NS.modules.casts.SetEnabled(db.casts.enabled)
end

local function SyncToMacro(force)
  local P = SchmittySlapperPersist
  if not P or not db or db.macroMirror == false or NS.svLoaded then return end
  if InCombatLockdown() then pendingSync = true return end
  local payload = P.Encode(Snapshot())
  if payload == lastPayload and not force then return end
  local ok, why = P.Write(MACRO_PREFIX, MACRO_CMD, payload)
  if ok then
    lastPayload = payload
    pendingSync = nil
    db.stamp = time()
    NS.Log("settings mirrored to macro")
  elseif why == "combat" then
    pendingSync = true
  elseif not warnedMacro then
    warnedMacro = true
    NS.Print("could not save settings into a macro (" .. tostring(why) .. "). Free a slot in the General macros tab.")
  end
end

local function RestoreFromMacro()
  local P = SchmittySlapperPersist
  if restored or not P or NS.svLoaded or db.macroMirror == false then return end
  local payload = P.Read(MACRO_PREFIX, MACRO_CMD)
  if not payload then
    if GetNumMacros and GetNumMacros() > 0 then restored = true end -- macros are in and there is none of ours
    return
  end
  restored = true
  ApplySnapshot(P.Decode(payload))
  lastPayload = payload
  ApplyAll()
  NS.Log("settings restored from macro; " .. NS.Centers())
end

local function StartMirror()
  if ticker or not C_Timer or not C_Timer.NewTicker then return end
  ticker = C_Timer.NewTicker(5, function() SyncToMacro() end)
end

local function Init()
  SchmittySlapperTrackerDB = SchmittySlapperTrackerDB or {}
  db = SchmittySlapperTrackerDB
  NS.svLoaded = db.stamp ~= nil
  NS.Log("saved variables loaded by the game: " .. tostring(NS.svLoaded))
  Migrate()
  CopyDefaults(db, DEFAULTS)
  for _, name in ipairs(NS.order) do
    local m = NS.modules[name]
    if type(db[name]) ~= "table" then db[name] = {} end
    CopyDefaults(db[name], m.DEFAULTS)
    m.Init(db[name])
  end
  NS.LoadEditModeLibs()
  WireEditMode()
  CreateOptionsPanel()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGOUT" then
    NS.SaveAllPositions("logout")
    SyncToMacro(true)
    return
  elseif event == "UPDATE_MACROS" then
    RestoreFromMacro()
    return
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingSync then SyncToMacro() end
    return
  elseif event == "PLAYER_ENTERING_WORLD" then
    for _, n in ipairs(NS.order) do NS.modules[n].ApplyLayout() end
    NS.Log("entering world, re-applied; " .. NS.Centers())
    RestoreFromMacro()
    StartMirror()
    C_Timer.After(2, function()
      for _, n in ipairs(NS.order) do NS.modules[n].ApplyLayout() end
      NS.Log("2s after entering world; " .. NS.Centers())
    end)
    return
  end
  if name ~= ADDON_NAME then return end
  self:UnregisterEvent("ADDON_LOADED")
  Init()
  self:RegisterEvent("PLAYER_LOGOUT")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("UPDATE_MACROS")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  NS.Log("loaded; " .. NS.Centers())
end)

---------------------------------------------------------------------------
-- /sst  (alias /slapper); /ssc goes straight to the casts part
---------------------------------------------------------------------------
local function Help()
  NS.Print("commands (also /slapper):")
  print("  /sst - open the options panel (Esc > Options > AddOns > Schmitty Slapper Tracker)")
  print("  /sst unlock - open HUD Edit Mode: drag the parts, use the corner grip to resize, click one for its settings")
  print("  /sst lock - close Edit Mode")
  print("  /sst test - show both parts for a moment")
  print("  /sst scale 1 - master size for both parts")
  print("  /sst save - save the current positions of both parts right now")
  print("  /sst reset - everything back to defaults")
  print("  /sst macro on|off - keep settings in a macro named SSTsave1 (Forever never reads saved variables back)")
  print("  /sst where - print saved and current positions (for troubleshooting)")
  print("  /sst log - print the position trail; /sst log clear")
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
  elseif cmd == "save" then
    NS.SaveAllPositions("command")
    NS.AnnounceSaved("arcs", db.arcs)
    NS.AnnounceSaved("ability row", db.casts)
  elseif cmd == "reset" then
    NS.Log("RESET by command")
    for k in pairs(db) do db[k] = nil end
    CopyDefaults(db, DEFAULTS)
    for _, name in ipairs(NS.order) do
      db[name] = {}
      CopyDefaults(db[name], NS.modules[name].DEFAULTS)
      NS.modules[name].Reset()
    end
    NS.Print("all settings reset")
  elseif cmd == "" or cmd == "options" or cmd == "config" then
    if not OpenOptions() then Help() end
  elseif cmd == "restore" then
    if rest ~= "" and SchmittySlapperPersist then
      ApplySnapshot(SchmittySlapperPersist.Decode(rest))
      ApplyAll()
      NS.Print("settings restored")
    end
  elseif cmd == "macro" then
    if rest == "on" or rest == "off" then db.macroMirror = (rest == "on") end
    NS.Print("settings macro mirror " .. NS.OnOff(db.macroMirror ~= false) .. " (macro SSTsave1 in the General tab; leave it alone)")
    if db.macroMirror ~= false then SyncToMacro(true) end
  elseif cmd == "where" then
    for _, name in ipairs(NS.order) do
      local m = NS.modules[name]
      local f = m.GetFrame and m.GetFrame()
      local pos = db[name].positions[NS.layoutName] or db[name].positions.default
      local saved = pos and ("saved x " .. pos.x .. ", y " .. pos.y) or "nothing saved (default spot)"
      local now = "?"
      if f then
        local px, py = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if px then
          local ps, us = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
          now = math.floor((px * ps - ux * us) / ps + 0.5) .. ", " .. math.floor((py * ps - uy * us) / ps + 0.5)
        end
      end
      NS.Print(name .. ": " .. saved .. "; on screen now x, y " .. now .. " (layout " .. tostring(NS.layoutName) .. ")")
    end
  elseif cmd == "log" then
    if rest == "clear" then
      db.log = {}
      NS.Print("log cleared")
      return
    end
    NS.Print("position log:")
    for _, line in ipairs(db.log or {}) do print("  " .. line) end
  elseif cmd == "help" then
    Help()
  elseif NS.modules.arcs.Command(cmd, rest) then
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
