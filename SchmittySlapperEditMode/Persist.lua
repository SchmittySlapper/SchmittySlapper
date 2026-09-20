-- Shared by the Schmitty Slapper addons.
--
-- The WoW: Forever beta client writes SavedVariables at logout but never reads
-- them back (a Blizzard bug, reproduced by several addon authors), so settings
-- would reset on every reload. Macros do survive reloads and cold starts, so
-- each addon mirrors its settings into a general macro whose body is a slash
-- command that restores them (for example "/sst restore Al=1;Af=2;..."), and
-- reads it back at login. Clicking the macro simply re-applies the settings.

SchmittySlapperPersist = SchmittySlapperPersist or {}
local P = SchmittySlapperPersist
P.version = 1

local MAX_BODY = 255  -- macro body limit
local ICON = 134400   -- question mark

local function Sanitize(s)
  return (tostring(s):gsub("[;=\n\r]", ""))
end

-- Flat table of key -> number | boolean | string into "k=v;k=v" (sorted keys).
function P.Encode(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if type(v) == "boolean" then
      v = v and "1" or "0"
    elseif type(v) == "number" then
      v = string.format("%.10g", v)
    else
      v = Sanitize(v)
    end
    if v ~= "" then parts[#parts + 1] = k .. "=" .. v end
  end
  return table.concat(parts, ";")
end

-- Back into a table of strings.
function P.Decode(payload)
  local t = {}
  for k, v in payload:gmatch("([^;=]+)=([^;]*)") do t[k] = v end
  return t
end

local function Chunks(payload, room)
  local chunks, cur = {}, ""
  for part in payload:gmatch("[^;]+") do
    if cur == "" then
      cur = part
    elseif #cur + 1 + #part <= room then
      cur = cur .. ";" .. part
    else
      chunks[#chunks + 1] = cur
      cur = part
    end
  end
  if cur ~= "" then chunks[#chunks + 1] = cur end
  return chunks
end

-- Writes the payload into macros <prefix>1, <prefix>2, ... (as many as needed).
-- Returns true, or false and a reason ("combat" means try again later).
function P.Write(prefix, command, payload)
  if InCombatLockdown() then return false, "combat" end
  local head = command .. " restore "
  local chunks = Chunks(payload, MAX_BODY - #head)
  for i, chunk in ipairs(chunks) do
    local name = prefix .. i
    local body = head .. chunk
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
      if (GetMacroBody(index) or "") ~= body then EditMacro(index, name, nil, body) end
    else
      local created = CreateMacro(name, ICON, body, false)
      if not created then return false, "no free macro slot" end
    end
  end
  local i = #chunks + 1
  while true do
    local index = GetMacroIndexByName(prefix .. i)
    if not index or index == 0 then break end
    DeleteMacro(index)
    i = i + 1
  end
  return true
end

-- Reads the payload back, or nil when there is no such macro.
function P.Read(prefix, command)
  local head = command .. " restore "
  local parts = {}
  local i = 1
  while true do
    local index = GetMacroIndexByName(prefix .. i)
    if not index or index == 0 then break end
    local body = GetMacroBody(index) or ""
    body = body:gsub("%s+$", "")
    if body:sub(1, #head) == head then parts[#parts + 1] = body:sub(#head + 1) end
    i = i + 1
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ";")
end
