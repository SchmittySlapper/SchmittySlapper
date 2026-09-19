-- Schmitty Slapper Grave: tracks the Undead racial "Touch of the Grave".
-- When it procs: play a sound you pick, flash the amount it healed, keep totals.
--
-- WoW: Forever runs the 12.x engine. The combat log is closed to addons and
-- combat text returns are secret, so this works from two events instead:
--   * UNIT_SPELLCAST_SUCCEEDED for the player: the proc itself (spell 127802,
--     matched by name too in case the ID differs on this client)
--   * UNIT_COMBAT for the player with event "HEAL": the amount, handed straight
--     to a FontString so it displays even if the client marks it secret.
-- If the amount is a plain number, session and lifetime totals are kept.

local ADDON_NAME, NS = ...

local SPELL_NAME = "Touch of the Grave"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local SOUND_DIR = "Interface\\AddOns\\SchmittySlapperGrave\\Sounds\\"
local HEAL_WINDOW = 0.6   -- seconds after the proc in which a heal is taken as its amount
local EARLY_WINDOW = 0.25 -- a heal that arrived just before the proc event
local SOUND_THROTTLE = 0.5

-- Built-in choices. The SOUNDKIT table gives the id on modern clients; the
-- number is a fallback for when it is missing.
local SOUNDS = {
  -- The lightsaber clip is Details! damage meter's sound_jedi1.ogg (the one the wago.io/vQxxFptvP
  -- aura plays). It is not redistributed here: it plays from this addon's Sounds folder if you put it
  -- there, otherwise straight from an installed Details!.
  { key = "lightsaber",  label = "Lightsaber",         file = "sound_jedi1.ogg", alt = "Interface\\AddOns\\Details\\sounds\\sound_jedi1.ogg" },
  { key = "raidwarning", label = "Raid warning",       kit = "RAID_WARNING",                 id = 8959 },
  { key = "readycheck",  label = "Ready check",        kit = "READY_CHECK",                  id = 8960 },
  { key = "levelup",     label = "Level up",           kit = "LEVEL_UP",                     id = 888 },
  { key = "alarm",       label = "Alarm clock",        kit = "ALARM_CLOCK_WARNING_3",        id = 12889 },
  { key = "bosswhisper", label = "Boss whisper",       kit = "UI_RAID_BOSS_WHISPER_WARNING", id = 37666 },
  { key = "pvpqueue",    label = "PvP queue pop",      kit = "PVP_THROUGH_QUEUE",            id = 8459 },
  { key = "whisper",     label = "Whisper",            kit = "TELL_MESSAGE",                 id = 3081 },
  { key = "auction",     label = "Auction house open", kit = "AUCTION_WINDOW_OPEN",          id = 5856 },
  { key = "mapping",     label = "Map ping",           kit = "MAP_PING",                     id = 3175 },
  { key = "menu",        label = "Menu open",          kit = "IG_MAINMENU_OPEN",             id = 850 },
  { key = "none",        label = "No sound" },
}

local DEFAULTS = {
  enabled   = true,
  sound     = "lightsaber",  -- a key above, "file:Name.ogg" from the Sounds folder, or "lsm:Name"
  channel   = "Master",      -- Master, SFX, Music, Ambience, Dialog
  showText  = true,
  showLabel = true,          -- the words Touch of the Grave above the amount
  showAmount = true,         -- the +23 line
  showSession = true,        -- the session totals line
  showLifetime = false,      -- a lifetime totals line under it
  statProcs = true,          -- what the totals lines include
  statHealed = true,
  statBest = true,
  hold      = 3,             -- seconds the text stays before fading
  scale     = 1,
  detect    = "auto",        -- auto: cast event + heal event + combat log line. Or spell / heal / chat alone
  spellIDs  = { [127802] = true },
  x         = 0,
  y         = 180,
  positions = {},            -- per Edit Mode layout: { point, x, y }
  stats     = { count = 0, total = 0, best = 0 },
  customFiles = {},          -- files you picked with /ssg sound file, listed in the options panel
  debug     = false,
}

local db
local frame, mover, grip
local editing = false
local session = { count = 0, total = 0, best = 0, plain = true }
local pendingUntil, lastHealTime, lastHealAmount, lastSound = nil, nil, nil, 0
local alpha, alphaTarget, fadeAt = 0, 0, nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local issecret = rawget(_G, "issecretvalue")

local function Plain(v)
  if issecret and issecret(v) then return nil end
  return v
end

local function Safe(v)
  if issecret and issecret(v) then return "(secret)" end
  return tostring(v)
end

local function Print(msg)
  print("|cff33ff99Schmitty Slapper Grave|r: " .. msg)
end

local function Debug(...)
  if not db or not db.debug then return end
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = Safe((select(i, ...))) end
  print("|cff888888SSG debug:|r " .. table.concat(parts, " "))
end

local function Comma(n)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  return tostring(n)
end

local function OnOff(v) return v and "on" or "off" end

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
local function SoundEntry(key)
  for _, s in ipairs(SOUNDS) do
    if s.key == key then return s end
  end
end

local function LSM()
  return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function SoundLabel(choice)
  choice = choice or db.sound
  local file = choice:match("^file:(.+)$")
  if file then return "file " .. file end
  local lsm = choice:match("^lsm:(.+)$")
  if lsm then return lsm .. " (SharedMedia)" end
  local e = SoundEntry(choice)
  return e and e.label or choice
end

local function PlayChoice(choice)
  choice = choice or db.sound
  if choice == "none" then return true end
  local file = choice:match("^file:(.+)$")
  if file then return PlaySoundFile(SOUND_DIR .. file, db.channel) end
  local lsm = choice:match("^lsm:(.+)$")
  if lsm then
    local lib = LSM()
    local path = lib and lib:Fetch("sound", lsm, true)
    if path then return PlaySoundFile(path, db.channel) end
    return false
  end
  local e = SoundEntry(choice)
  if not e then return false end
  if e.file then
    local played = PlaySoundFile(SOUND_DIR .. e.file, db.channel)
    if not played and e.alt then played = PlaySoundFile(e.alt, db.channel) end
    return played
  end
  local id = (SOUNDKIT and e.kit and SOUNDKIT[e.kit]) or e.id
  return PlaySound(id, db.channel)
end

local warnedSound
local function PlayProcSound()
  local now = GetTime()
  if now - lastSound < SOUND_THROTTLE then return end
  lastSound = now
  if db.sound == "none" then return end
  local played = PlayChoice()
  if not played then
    PlayChoice("raidwarning")
    if not warnedSound then
      warnedSound = true
      Print("the sound " .. SoundLabel() .. " could not be played, so the raid warning was used instead. A sound file added while the game was running needs a full game restart.")
    end
  end
end

local function SoundChoices()
  local list = {}
  for _, s in ipairs(SOUNDS) do list[#list + 1] = { text = s.label, value = s.key } end
  local lib = LSM()
  if lib then
    for _, name in ipairs(lib:List("sound")) do
      list[#list + 1] = { text = name .. " (SharedMedia)", value = "lsm:" .. name }
    end
  end
  return list
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function OnUpdate(self, dt)
  if fadeAt and GetTime() >= fadeAt then
    alphaTarget = 0
    fadeAt = nil
  end
  if alpha ~= alphaTarget then
    local step = dt / (alpha < alphaTarget and 0.1 or 0.5)
    if alpha < alphaTarget then
      alpha = math.min(alphaTarget, alpha + step)
    else
      alpha = math.max(alphaTarget, alpha - step)
    end
    self:SetAlpha(alpha)
  end
  if alpha == alphaTarget and not fadeAt then
    self:SetScript("OnUpdate", nil)
    if alpha == 0 and not editing then self:Hide() end
  end
end

local function Flash()
  if editing then return end
  alphaTarget = 1
  fadeAt = GetTime() + db.hold
  frame:Show()
  frame:SetScript("OnUpdate", OnUpdate)
end

local function StatsText(prefix, st, plain)
  local parts = {}
  if db.statProcs then parts[#parts + 1] = (st.count or 0) .. " procs" end
  if plain then
    if db.statHealed then parts[#parts + 1] = Comma(st.total or 0) .. " healed" end
    if db.statBest then parts[#parts + 1] = "best " .. Comma(st.best or 0) end
  end
  if #parts == 0 then return "" end
  return prefix .. ": " .. table.concat(parts, ", ")
end

-- Stack the visible lines top-down and size the frame to fit them.
local function LayoutLines()
  local prev, height = nil, 4
  for _, key in ipairs({ "label", "amount", "totals", "lifetime" }) do
    local fs = frame[key]
    fs:ClearAllPoints()
    if fs.shown then
      if prev then fs:SetPoint("TOP", prev, "BOTTOM", 0, -2) else fs:SetPoint("TOP", frame, "TOP", 0, -2) end
      fs:Show()
      height = height + fs:GetStringHeight() + 2
      prev = fs
    else
      fs:Hide()
    end
  end
  frame:SetHeight(math.max(height, 20))
end

local function UpdateLines()
  if not frame then return end
  frame.label.shown = db.showLabel
  frame.amount.shown = db.showAmount
  local sessionText = (session.count > 0 and db.showSession) and StatsText("Session", session, session.plain) or ""
  local lifeText = db.showLifetime and StatsText("Lifetime", db.stats, session.plain) or ""
  frame.totals:SetText(sessionText)
  frame.lifetime:SetText(lifeText)
  frame.totals.shown = sessionText ~= ""
  frame.lifetime.shown = lifeText ~= ""
  LayoutLines()
end

local function UpdateTotals()
  UpdateLines()
end

local function ShowProc(amount)
  if amount == nil then
    frame.amount:SetText("")
  else
    local a = Plain(amount)
    if a then
      frame.amount:SetText("+" .. Comma(a))
    else
      frame.amount:SetFormattedText("+%d", amount) -- secret-safe: the widget formats it
    end
  end
  UpdateTotals()
  if db.showText then Flash() end
end

local function RecordAmount(amount)
  local a = Plain(amount)
  if a then
    session.total = session.total + a
    if a > session.best then session.best = a end
    db.stats.total = (db.stats.total or 0) + a
    if a > (db.stats.best or 0) then db.stats.best = a end
  else
    session.plain = false
  end
end

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------
local function IsGraveSpell(spellID)
  if db.spellIDs[spellID] then return true end
  local ok, name = pcall(C_Spell.GetSpellName, spellID)
  return ok and Plain(name) == SPELL_NAME
end

-- Several sources can report the same proc. The first one within half a
-- second counts it; the others may only add the amount if it is still missing.
local lastProcTime, lastProcHadAmount = 0, false

local function Proc(amount, source)
  local now = GetTime()
  if now - lastProcTime < 0.5 then
    if amount ~= nil and not lastProcHadAmount then
      lastProcHadAmount = true
      RecordAmount(amount)
      ShowProc(amount)
      Debug("amount added by", source, amount)
    end
    return
  end
  lastProcTime = now
  lastProcHadAmount = amount ~= nil
  session.count = session.count + 1
  db.stats.count = (db.stats.count or 0) + 1
  if amount ~= nil then RecordAmount(amount) end
  PlayProcSound()
  ShowProc(amount)
  Debug("proc by", source, amount)
end

local function Active(source)
  return db.detect == "auto" or db.detect == source
end

-- Source 1: the proc's own cast event (does not seem to fire on Forever, kept
-- in case a later build sends it)
local function OnCast(spellID)
  if not Active("spell") then return end
  spellID = Plain(spellID)
  if not spellID or not IsGraveSpell(spellID) then return end
  if lastHealTime and GetTime() - lastHealTime < EARLY_WINDOW then
    local amount = lastHealAmount
    lastHealTime, lastHealAmount = nil, nil
    Proc(amount, "cast")
  else
    pendingUntil = GetTime() + HEAL_WINDOW
    Proc(nil, "cast")
  end
end

-- Self-heals that are not the proc: bandages are channels, potions and
-- healthstones are casts. Heals during or right after those are ignored.
local suppressUntil, channeling = 0, false

local function NoteSelfHealCast(spellID)
  spellID = Plain(spellID)
  if not spellID then return end
  local ok, name = pcall(C_Spell.GetSpellName, spellID)
  name = ok and Plain(name)
  if name and (name:find("Potion") or name:find("Healthstone") or name:find("Bandage") or name:find("First Aid")) then
    suppressUntil = GetTime() + 2
  end
end

-- Source 2, the one that works on Forever: a heal on the player (UNIT_COMBAT).
-- Touch of the Grave hits the target with Shadow damage in the same instant it
-- heals you, and a rogue deals no other Shadow damage, so a Shadow hit on the
-- target just before the heal confirms it. If the client hides the school of
-- the hit, any heal in combat that is not a bandage or potion counts.
local lastShadowHit, schoolSeen = 0, false

local function OnTargetHit(school)
  school = Plain(school)
  if school == nil then return end
  schoolSeen = true
  if school == 32 then lastShadowHit = GetTime() end
end

local function OnHeal(amount)
  local now = GetTime()
  if pendingUntil and now < pendingUntil then
    pendingUntil = nil
    Proc(amount, "heal")
    return
  end
  if not Active("heal") then
    lastHealTime, lastHealAmount = now, amount
    return
  end
  if channeling or now < suppressUntil then
    Debug("heal ignored: bandage or potion")
    return
  end
  if db.detect == "auto" then
    if schoolSeen then
      if now - lastShadowHit > 0.3 then
        Debug("heal ignored: no Shadow hit on the target just before it")
        return
      end
    elseif not InCombatLockdown() then
      Debug("heal ignored: out of combat")
      return
    end
  end
  Proc(amount, "heal")
end

-- Source 3: the combat log line. On restricted clients Blizzard delivers it as
-- a protected |K string that cannot be read; debug mode says so when that
-- happens. Kept for clients where the text is plain.
local function StripCodes(msg)
  local t = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
  t = t:gsub("|H.-|h", "")
  t = t:gsub("|h", "")
  t = t:gsub("|r", "")
  return t
end

local lastLine, lastLineTime, lastKWarn = nil, 0, 0

local function OnChatLine(msg)
  if not db.enabled or not Active("chat") then return end
  if issecret and issecret(msg) then
    Debug("combat log line is secret, cannot read it")
    return
  end
  if type(msg) ~= "string" then return end
  if msg == lastLine and GetTime() - lastLineTime < 0.3 then return end
  lastLine, lastLineTime = msg, GetTime()
  if msg:find("|K", 1, true) then
    if db.debug and GetTime() - lastKWarn > 5 then
      lastKWarn = GetTime()
      Debug("combat log lines are protected |K strings on this client; the heal event is used instead")
    end
    return
  end
  if not msg:find(SPELL_NAME, 1, true) then return end
  local t = StripCodes(msg)
  local amount = t:match("healed%s+%S+%s+(%d[%d,]*)") or t:match("heals%s+%S+%s+for%s+(%d[%d,]*)")
  Debug("combat log line:", t, "amount:", amount)
  if not amount then return end
  amount = tonumber((amount:gsub(",", "")))
  if amount then Proc(amount, "chat") end
end

local hookedFrames = {}
local function HookCombatLog()
  local function Hook(f)
    if f and not hookedFrames[f] and f.AddMessage then
      hookedFrames[f] = true
      hooksecurefunc(f, "AddMessage", function(_, msg) OnChatLine(msg) end)
    end
  end
  Hook(COMBATLOG)
  for i = 1, (NUM_CHAT_WINDOWS or 10) do Hook(_G["ChatFrame" .. i]) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, unit, a2, a3, a4, a5)
  if event == "PLAYER_ENTERING_WORLD" then
    HookCombatLog()
    return
  end
  if not db.enabled then return end
  if event == "COMBAT_LOG_MESSAGE" then
    OnChatLine(unit) -- the first payload value is the message text
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    Debug("cast", a3)
    NoteSelfHealCast(a3)
    OnCast(a3)
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    channeling = true
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    channeling = false
    suppressUntil = GetTime() + 0.5
  elseif event == "UNIT_COMBAT" then
    Debug("combat", unit, a2, a3, a4, a5)
    local kind = Plain(a2)
    if unit == "target" then
      if kind == "WOUND" then OnTargetHit(a5) end
    elseif kind == "HEAL" then
      OnHeal(a4)
    elseif kind == nil then
      Debug("combat event type is secret")
    end
  end
end)

---------------------------------------------------------------------------
-- Frame, layout, Edit Mode
---------------------------------------------------------------------------
local function ApplyLayout()
  frame:SetScale(db.scale)
  frame:ClearAllPoints()
  local pos = db.positions[NS.layoutName or "default"]
  if pos then
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
  end
end

local function CreateDisplay()
  frame = CreateFrame("Frame", "SchmittySlapperGraveFrame", UIParent)
  frame:SetSize(300, 70)
  frame:SetFrameStrata("HIGH")
  frame:SetAlpha(0)
  frame:Hide()
  frame.editModeName = "Schmitty Slapper Grave"

  frame.label = frame:CreateFontString(nil, "OVERLAY")
  frame.label:SetFont(FONT, 14, "OUTLINE")
  frame.label:SetPoint("TOP", frame, "TOP", 0, -2)
  frame.label:SetTextColor(0.6, 1, 0.6)
  frame.label:SetText(SPELL_NAME)

  frame.amount = frame:CreateFontString(nil, "OVERLAY")
  frame.amount:SetFont(FONT, 30, "OUTLINE")
  frame.amount:SetPoint("TOP", frame.label, "BOTTOM", 0, -2)
  frame.amount:SetTextColor(0.3, 1, 0.3)

  frame.totals = frame:CreateFontString(nil, "OVERLAY")
  frame.totals:SetFont(FONT, 11, "OUTLINE")
  frame.totals:SetPoint("BOTTOM", frame, "BOTTOM", 0, 2)
  frame.totals:SetTextColor(0.9, 0.9, 0.9)

  frame.lifetime = frame:CreateFontString(nil, "OVERLAY")
  frame.lifetime:SetFont(FONT, 11, "OUTLINE")
  frame.lifetime:SetTextColor(0.75, 0.75, 0.75)
end

-- Sample content while positioning
local function ShowSample()
  frame.amount:SetText("+" .. Comma(123))
  UpdateLines()
  if session.count == 0 and db.showSession then
    frame.totals:SetText(StatsText("Session", { count = 4, total = 512, best = 160 }, true))
    frame.totals.shown = frame.totals:GetText() ~= ""
    LayoutLines()
  end
end

local function SetEditing(on)
  editing = on
  if on then
    ShowSample()
    fadeAt = nil
    alpha, alphaTarget = 1, 1
    frame:SetAlpha(1)
    frame:Show()
    if grip then grip:Show() end
  else
    if grip then grip:Hide() end
    UpdateTotals()
    alpha, alphaTarget = 0, 0
    frame:SetAlpha(0)
    frame:Hide()
  end
end

local lib
local function EditMode()
  if lib ~= nil then return lib or nil end
  local ok = EditModeManagerFrame and EditModeSystemSettingsDialog and LibStub
  local c = ok and LibStub("LibEditMode", true)
  lib = (c and c.AddFrame and c.RegisterCallback) and c or false
  return lib or nil
end

local function OpenEditMode()
  if not EditMode() then return false end
  if InCombatLockdown() then Print("Edit Mode cannot open during combat") return true end
  if ShowUIPanel then ShowUIPanel(EditModeManagerFrame) else EditModeManagerFrame:Show() end
  return true
end

local function CloseEditMode()
  if not EditMode() or not EditModeManagerFrame:IsShown() then return false end
  if HideUIPanel then HideUIPanel(EditModeManagerFrame) else EditModeManagerFrame:Hide() end
  return true
end

local function AddResizeGrip()
  grip = CreateFrame("Button", nil, frame)
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
    return math.sqrt((cx - fx * es) ^ 2 + (cy - fy * es) ^ 2)
  end
  grip:SetScript("OnMouseDown", function(self)
    startScale, startDist = db.scale, Distance()
    if not startDist or startDist < 1 then startDist = nil return end
    self:SetScript("OnUpdate", function()
      local d = Distance()
      if not d then return end
      local s = math.floor(math.max(0.4, math.min(3, startScale * d / startDist)) * 100 + 0.5) / 100
      if s ~= db.scale then db.scale = s ApplyLayout() end
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    if lib and lib.RefreshFrameSettings then pcall(lib.RefreshFrameSettings, lib, frame) end
  end)
end

local function WireEditMode()
  local l = EditMode()
  if not l then return end
  l:RegisterCallback("enter", function() SetEditing(true) end)
  l:RegisterCallback("exit", function() SetEditing(false) end)
  l:AddFrame(frame, function(_, layoutName, point, x, y)
    db.positions[layoutName or "default"] = { point = point, x = x, y = y }
  end, { point = "CENTER", x = DEFAULTS.x, y = DEFAULTS.y }, "Schmitty Slapper Grave")
  local selection = l.frameSelections and l.frameSelections[frame]
  if selection then selection:SetFrameLevel(frame:GetFrameLevel() + 5) end
  l:AddFrameSettings(frame, {
    { kind = l.SettingType.Checkbox, name = "Enabled", default = true,
      get = function() return db.enabled end,
      set = function(_, v) db.enabled = v and true or false end },
    { kind = l.SettingType.Dropdown, name = "Sound", default = "lightsaber", values = SoundChoices,
      get = function() return db.sound end,
      set = function(_, v) db.sound = v PlayChoice(v) end },
    { kind = l.SettingType.Dropdown, name = "Sound channel", default = "Master",
      values = { { text = "Master", value = "Master" }, { text = "Sound effects", value = "SFX" }, { text = "Music", value = "Music" }, { text = "Ambience", value = "Ambience" }, { text = "Dialog", value = "Dialog" } },
      get = function() return db.channel end,
      set = function(_, v) db.channel = v end },
    { kind = l.SettingType.Checkbox, name = "Show healed amount on screen", default = true,
      get = function() return db.showText end,
      set = function(_, v) db.showText = v and true or false end },
    { kind = l.SettingType.Checkbox, name = "Show spell name", default = true,
      get = function() return db.showLabel end,
      set = function(_, v) db.showLabel = v and true or false UpdateLines() end },
    { kind = l.SettingType.Checkbox, name = "Show session totals", default = true,
      get = function() return db.showSession end,
      set = function(_, v) db.showSession = v and true or false UpdateLines() end },
    { kind = l.SettingType.Checkbox, name = "Show lifetime totals", default = false,
      get = function() return db.showLifetime end,
      set = function(_, v) db.showLifetime = v and true or false UpdateLines() end },
    { kind = l.SettingType.Slider, name = "Seconds on screen", default = 3, minValue = 1, maxValue = 10, valueStep = 0.5,
      get = function() return db.hold end,
      set = function(_, v) db.hold = v end },
    { kind = l.SettingType.Slider, name = "Scale (%)", default = 100, minValue = 40, maxValue = 300, valueStep = 5,
      get = function() return math.floor(db.scale * 100 + 0.5) end,
      set = function(_, v) db.scale = v / 100 ApplyLayout() end },
    { kind = l.SettingType.Dropdown, name = "Detect the proc by", default = "auto",
      values = { { text = "Everything (normal)", value = "auto" }, { text = "Combat log line only", value = "chat" }, { text = "Cast event only", value = "spell" }, { text = "Any heal you receive", value = "heal" } },
      get = function() return db.detect end,
      set = function(_, v) db.detect = v end },
  })
  if l.AddFrameSettingsButtons then
    l:AddFrameSettingsButtons(frame, {
      { text = "Test sound", click = function() PlayChoice() end },
      { text = "Reset totals", click = function() db.stats = { count = 0, total = 0, best = 0 } session = { count = 0, total = 0, best = 0, plain = true } UpdateTotals() end },
    })
  end
  AddResizeGrip()
  l:RegisterCallback("layout", function(layoutName)
    NS.layoutName = layoutName or "default"
    ApplyLayout()
  end)
  if l:IsInEditMode() then SetEditing(true) end
end

-- Fallback drag box for clients without Edit Mode
local function SetUnlocked(unlocked)
  if not mover then
    mover = CreateFrame("Frame", nil, frame)
    mover:SetAllPoints(frame)
    mover:SetFrameLevel(frame:GetFrameLevel() + 10)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(0, 0.6, 1, 0.25)
    mover:SetScript("OnDragStart", function() frame:StartMoving() end)
    mover:SetScript("OnDragStop", function()
      frame:StopMovingOrSizing()
      local px, py = frame:GetCenter()
      local ux, uy = UIParent:GetCenter()
      local ps, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
      db.positions[NS.layoutName or "default"] = {
        point = "CENTER",
        x = math.floor((px * ps - ux * us) / ps + 0.5),
        y = math.floor((py * ps - uy * us) / ps + 0.5),
      }
      ApplyLayout()
    end)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
  end
  if unlocked then mover:Show() else mover:Hide() end
  SetEditing(unlocked)
end

---------------------------------------------------------------------------
-- Options panel: Esc > Options > AddOns > Schmitty Slapper Grave (or /ssg)
---------------------------------------------------------------------------
local category

local function ResetTotals()
  db.stats = { count = 0, total = 0, best = 0 }
  session = { count = 0, total = 0, best = 0, plain = true }
  UpdateTotals()
end

local function RememberFile(name)
  for _, f in ipairs(db.customFiles) do
    if f == name then return end
  end
  table.insert(db.customFiles, name)
end

local function SoundOptions()
  local container = Settings.CreateControlTextContainer()
  for _, c in ipairs(SoundChoices()) do container:Add(c.value, c.text) end
  for _, f in ipairs(db.customFiles) do container:Add("file:" .. f, f .. " (Sounds folder)") end
  return container:GetData()
end

local function CreateOptionsPanel()
  if not Settings or not Settings.RegisterVerticalLayoutCategory or not Settings.RegisterProxySetting
      or not Settings.CreateControlTextContainer or not CreateSettingsButtonInitializer then
    return
  end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("Schmitty Slapper Grave")
  local B, N, S = Settings.VarType.Boolean, Settings.VarType.Number, Settings.VarType.String

  local function Proxy(var, vtype, name, default, get, set)
    return Settings.RegisterProxySetting(category, "SSG_" .. var, vtype, name, default, get, set)
  end

  Settings.CreateCheckbox(category,
    Proxy("ENABLED", B, "Enabled", true, function() return db.enabled end, function(v) db.enabled = v and true or false end),
    "Play the sound and show the text when Touch of the Grave procs.")

  Settings.CreateDropdown(category,
    Proxy("SOUND", S, "Sound", "lightsaber", function() return db.sound end, function(v) db.sound = v PlayChoice(v) end),
    SoundOptions,
    "The sound to play on a proc. Picking one plays it once. Your own files go in the addon's Sounds folder (restart the game after adding them); /ssg sound file Name.ogg adds one to this list.")

  layout:AddInitializer(CreateSettingsButtonInitializer("Test", "Play sound", function() PlayChoice() end, "Plays the selected sound.", true))

  local function ChannelOptions()
    local c = Settings.CreateControlTextContainer()
    c:Add("Master", "Master")
    c:Add("SFX", "Sound effects")
    c:Add("Music", "Music")
    c:Add("Ambience", "Ambience")
    c:Add("Dialog", "Dialog")
    return c:GetData()
  end
  Settings.CreateDropdown(category,
    Proxy("CHANNEL", S, "Sound channel", "Master", function() return db.channel end, function(v) db.channel = v end),
    ChannelOptions, "Which volume slider the sound follows. Master plays even when sound effects are turned down.")

  Settings.CreateCheckbox(category,
    Proxy("TEXT", B, "Show text on screen", true, function() return db.showText end, function(v) db.showText = v and true or false end),
    "Flash the text when it procs. The lines below choose what is in it.")
  local function Toggle(var, key, name, default, tooltip)
    Settings.CreateCheckbox(category,
      Proxy(var, B, name, default, function() return db[key] end, function(v) db[key] = v and true or false UpdateLines() end), tooltip)
  end
  Toggle("LABEL", "showLabel", "Show spell name", true, "The words Touch of the Grave above the amount.")
  Toggle("AMOUNT", "showAmount", "Show healed amount", true, "The +23 line.")
  Toggle("SESSION", "showSession", "Show session totals", true, "Totals since you logged in.")
  Toggle("LIFETIME", "showLifetime", "Show lifetime totals", false, "Totals kept across sessions.")
  Toggle("STATPROCS", "statProcs", "Totals include: proc count", true, "How many times it procced.")
  Toggle("STATHEALED", "statHealed", "Totals include: healed", true, "Total health healed.")
  Toggle("STATBEST", "statBest", "Totals include: best", true, "The biggest single heal.")

  local hold = Settings.CreateSliderOptions(1, 10, 0.5)
  hold:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return ("%.1f s"):format(v) end)
  Settings.CreateSlider(category,
    Proxy("HOLD", N, "Seconds on screen", 3, function() return db.hold end, function(v) db.hold = v end),
    hold, "How long the text stays before fading.")

  local scale = Settings.CreateSliderOptions(40, 300, 5)
  scale:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return v .. "%" end)
  Settings.CreateSlider(category,
    Proxy("SCALE", N, "Text size", 100, function() return math.floor(db.scale * 100 + 0.5) end, function(v) db.scale = v / 100 ApplyLayout() end),
    scale, "Size of the on-screen text.")

  local function DetectOptions()
    local c = Settings.CreateControlTextContainer()
    c:Add("auto", "Everything (normal)")
    c:Add("chat", "Combat log line only")
    c:Add("spell", "Cast event only")
    c:Add("heal", "Any heal you receive")
    return c:GetData()
  end
  Settings.CreateDropdown(category,
    Proxy("DETECT", S, "Detect the proc by", "auto", function() return db.detect end, function(v) db.detect = v end),
    DetectOptions, "Switch to the fallback if procs happen but the addon stays quiet.")

  layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Open Edit Mode", function()
    if not OpenEditMode() then SetUnlocked(true) end
  end, "Move and resize the text in HUD Edit Mode.", true))
  layout:AddInitializer(CreateSettingsButtonInitializer("Try it", "Fake a proc", function() Proc(math.random(60, 200)) end, "Plays the sound and shows the text as if it procced.", true))
  layout:AddInitializer(CreateSettingsButtonInitializer("Totals", "Reset totals", ResetTotals, "Clears session and lifetime totals.", true))

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
-- Start-up
---------------------------------------------------------------------------
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

local function Init()
  SchmittySlapperGraveDB = SchmittySlapperGraveDB or {}
  db = SchmittySlapperGraveDB
  -- Lightsaber became the default sound; a save still on the first default follows.
  if db.defaultsVersion == nil then
    if db.sound == "raidwarning" then db.sound = "lightsaber" end
    db.defaultsVersion = 2
  end
  if (db.defaultsVersion or 0) < 3 then
    if db.detect == "spell" then db.detect = "auto" end
    db.defaultsVersion = 3
  end
  CopyDefaults(db, DEFAULTS)
  NS.layoutName = "default"

  CreateDisplay()
  ApplyLayout()
  UpdateLines()
  WireEditMode()
  CreateOptionsPanel()

  events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  events:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
  events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
  events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  pcall(events.RegisterEvent, events, "COMBAT_LOG_MESSAGE")
  HookCombatLog()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
  if name ~= ADDON_NAME then return end
  self:UnregisterEvent("ADDON_LOADED")
  Init()
end)

---------------------------------------------------------------------------
-- /ssg
---------------------------------------------------------------------------
local function Help()
  Print("commands (also /grave):")
  print("  /ssg - open the options panel (Esc > Options > AddOns > Schmitty Slapper Grave)")
  print("  /ssg on|off - turn the tracker on or off")
  print("  /ssg sound list - show the sounds you can pick")
  print("  /ssg sound <name> - pick a sound, e.g. /ssg sound readycheck")
  print("  /ssg sound file <Name.ogg> - a file you put in the addon's Sounds folder (restart the game after adding)")
  print("  /ssg sound test - play the current sound")
  print("  /ssg channel Master|SFX - which volume slider it follows")
  print("  /ssg text on|off - show the healed amount on screen")
  print("  /ssg hold 3 - seconds the text stays")
  print("  /ssg scale 1 - size of the text")
  print("  /ssg unlock / /ssg lock - open or close HUD Edit Mode to move and resize it")
  print("  /ssg show label|amount|session|lifetime|procs|healed|best on|off - what the text shows")
  print("  /ssg detect auto|chat|spell|heal - how the proc is spotted (auto = all of them)")
  print("  /ssg spell <id> - add or remove a spell id to watch; /ssg spell list")
  print("  /ssg stats - session and lifetime totals; /ssg resetstats")
  print("  /ssg test - fake a proc")
  print("  /ssg debug on|off - print the raw events in chat")
end

SLASH_SCHMITTYSLAPPERGRAVE1 = "/ssg"
SLASH_SCHMITTYSLAPPERGRAVE2 = "/grave"
SlashCmdList.SCHMITTYSLAPPERGRAVE = function(msg)
  msg = msg or ""
  local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()

  if cmd == "on" or cmd == "off" then
    db.enabled = (cmd == "on")
    Print("tracker " .. OnOff(db.enabled))
  elseif cmd == "sound" then
    local sub, rest = arg:match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    if sub == "list" or sub == "" then
      Print("sounds (current: " .. SoundLabel() .. "):")
      for _, c in ipairs(SoundChoices()) do print("  " .. c.value .. " - " .. c.text) end
      print("  file <Name.ogg> - a file in Interface\\AddOns\\SchmittySlapperGrave\\Sounds")
    elseif sub == "test" then
      if not PlayChoice() then Print("that sound could not be played: " .. SoundLabel()) end
    elseif sub == "file" and rest ~= "" then
      db.sound = "file:" .. rest
      RememberFile(rest)
      if not PlayChoice() then Print("file not found or not loaded yet (restart the game after adding files): " .. rest) else Print("sound: " .. SoundLabel()) end
    elseif SoundEntry(sub) or sub:match("^lsm:") then
      db.sound = sub
      PlayChoice()
      Print("sound: " .. SoundLabel())
    else
      Print("unknown sound; /ssg sound list")
    end
  elseif cmd == "channel" then
    local c = arg:match("^%S+")
    local valid = { Master = true, SFX = true, Music = true, Ambience = true, Dialog = true }
    if c and valid[c] then db.channel = c end
    Print("sound channel " .. db.channel)
  elseif cmd == "text" then
    if arg == "on" or arg == "off" then db.showText = (arg == "on") end
    Print("on-screen text " .. OnOff(db.showText))
  elseif cmd == "hold" then
    local n = tonumber(arg)
    if n and n >= 0.5 and n <= 30 then db.hold = n end
    Print("text stays " .. db.hold .. " seconds")
  elseif cmd == "scale" then
    local n = tonumber(arg)
    if n and n > 0.2 and n < 5 then db.scale = n end
    Print("scale " .. db.scale)
    ApplyLayout()
  elseif cmd == "unlock" or cmd == "move" then
    if not OpenEditMode() then
      SetUnlocked(true)
      Print("unlocked: drag the blue box, then /ssg lock")
    end
  elseif cmd == "lock" then
    if not CloseEditMode() then
      SetUnlocked(false)
      Print("locked")
    end
  elseif cmd == "x" or cmd == "y" then
    local n = tonumber(arg)
    local key = NS.layoutName or "default"
    local pos = db.positions[key] or { point = "CENTER", x = db.x, y = db.y }
    if pos.point ~= "CENTER" then pos = { point = "CENTER", x = db.x, y = db.y } end
    if n then pos[cmd] = n end
    db.positions[key] = pos
    Print("offset x " .. pos.x .. ", y " .. pos.y)
    ApplyLayout()
  elseif cmd == "show" then
    local part, state = arg:match("^(%S*)%s*(%S*)")
    local keys = { label = "showLabel", amount = "showAmount", session = "showSession", lifetime = "showLifetime", procs = "statProcs", healed = "statHealed", best = "statBest" }
    local key = keys[part]
    if not key then
      Print("usage: /ssg show label|amount|session|lifetime|procs|healed|best on|off")
      return
    end
    if state == "on" or state == "off" then db[key] = (state == "on") end
    UpdateLines()
    Print(part .. " " .. OnOff(db[key]))
  elseif cmd == "detect" then
    if arg == "auto" or arg == "spell" or arg == "heal" or arg == "chat" then db.detect = arg end
    Print("detecting the proc by: " .. db.detect .. " (auto = cast event, heal event and combat log line together)")
  elseif cmd == "spell" then
    if arg == "list" or arg == "" then
      local ids = {}
      for id in pairs(db.spellIDs) do ids[#ids + 1] = id end
      table.sort(ids)
      Print("watching spell ids: " .. table.concat(ids, ", ") .. " (plus anything named " .. SPELL_NAME .. ")")
    else
      local id = tonumber(arg)
      if not id then Print("usage: /ssg spell <id>") return end
      db.spellIDs[id] = not db.spellIDs[id] or nil
      Print((db.spellIDs[id] and "now watching " or "no longer watching ") .. id)
    end
  elseif cmd == "stats" then
    local s, l = session, db.stats
    if session.plain then
      Print(("session: %d procs, %s healed, best %s"):format(s.count, Comma(s.total), Comma(s.best)))
      Print(("lifetime: %d procs, %s healed, best %s"):format(l.count or 0, Comma(l.total or 0), Comma(l.best or 0)))
    else
      Print(("session: %d procs (amounts are hidden by the game, so no totals)"):format(s.count))
      Print(("lifetime: %d procs"):format(l.count or 0))
    end
  elseif cmd == "resetstats" then
    ResetTotals()
    Print("totals reset")
  elseif cmd == "test" then
    Proc(math.random(60, 200))
    Print("fake proc")
  elseif cmd == "debug" then
    if arg == "on" or arg == "off" then db.debug = (arg == "on") end
    Print("debug " .. OnOff(db.debug) .. (db.debug and " (raw cast and combat events print in chat)" or ""))
  elseif cmd == "" or cmd == "config" or cmd == "options" then
    if not OpenOptions() then Help() end
  else
    Help()
  end
end
