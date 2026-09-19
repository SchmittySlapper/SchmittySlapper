-- Blizzard's Edit Mode addon is load-on-demand on the WoW: Forever client.
-- LibEditMode hooks EditModeManagerFrame the moment its file runs, so make
-- sure the Blizzard addon is loaded first. Runs before the library in the TOC.
if not EditModeManagerFrame then
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if load then pcall(load, "Blizzard_EditMode") end
end
