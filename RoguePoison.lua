-- Rogue Poison: when a weapon you hold has no poison, a bar at the top of the screen
-- names the weapon and lists the poisons in your bags. Clicking one coats that weapon.
--
-- Addon code cannot use items, so each poison is a SecureActionButton: type "item" uses
-- the poison, and "target-slot" (16 main hand, 17 off hand) picks the weapon it goes on,
-- the same as "/use Instant Poison" followed by "/use 16" in a macro.
-- Secure buttons cannot be moved, shown or hidden in combat, so the bar is laid out only
-- out of combat and a state driver hides it while you fight.

local GetItemInfoInstant = GetItemInfoInstant or C_Item.GetItemInfoInstant
local GetItemCount = GetItemCount or C_Item.GetItemCount

-- Rogue poisons in the Forever item data (python -m kb search poison --kind item and
-- kb item <id>, 2026-11-18): each is "Classes: Rogue" with "Use: Coats a weapon with
-- poison". The bar shows them in this order.
local POISONS = {
  6947, 6949, 6950, 8926, 8927, 8928, -- Instant Poison I-VI
  2892, 2893, 8984, 8985, 20844,      -- Deadly Poison I-V
  10918, 10920, 10921, 10922,         -- Wound Poison I-IV
  3775, 3776,                         -- Crippling Poison I-II
  5237, 6951, 9186,                   -- Mind-numbing Poison I-III
  226374, 234444,                     -- Occult Poison I-II
  217345, 217346, 217347,             -- Sebacious, Numbing, Atrophic Poison
}
local MAX_BUTTONS = 12
local ICON, BUTTON, GAP, PAD, SIDE_GAP = 36, 32, 4, 10, 24
-- Instant Poison, the first one, requires level 20 (kb item 6947).
local POISON_LEVEL = 20

local HANDS = {
  { slot = 16, label = "Main hand" },
  { slot = 17, label = "Off hand" },
}

-- Debug log: /rpoison debug toggles it. Lines go only to RoguePoisonDB.log (cleared at
-- each login or /reload), which the game writes to
-- WTF\...\SavedVariables\RoguePoison.lua on /reload or logout.
local LOG_MAX = 1000
local function log(fmt, ...)
  if not (RoguePoisonDB and RoguePoisonDB.debug) then return end
  local line = format("%s %.2f [%s] " .. fmt, date("%H:%M:%S"), GetTime(),
    InCombatLockdown() and "combat" or "nocombat", ...)
  RoguePoisonDB.log = RoguePoisonDB.log or {}
  tinsert(RoguePoisonDB.log, line)
  while #RoguePoisonDB.log > LOG_MAX do tremove(RoguePoisonDB.log, 1) end
end

local function say(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Rogue Poison|r " .. msg)
end

-- Which hands have a poison: { [16] = bool, [17] = bool }, or nil when the game does not
-- let the addon read it. Forever hides some values from addons ("secret values", as with
-- UnitPower), so the read and the test are both guarded.
local lastReadError
local function poisoned()
  local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
  local err
  if not ok then
    err = "GetWeaponEnchantInfo failed: " .. tostring(hasMain)
  elseif issecretvalue and (issecretvalue(hasMain) or issecretvalue(hasOff)) then
    err = "GetWeaponEnchantInfo returned secret values"
  else
    local tested, state = pcall(function()
      return { [16] = hasMain and true or false, [17] = hasOff and true or false }
    end)
    if tested then
      lastReadError = nil
      return state
    end
    err = "testing GetWeaponEnchantInfo failed: " .. tostring(state)
  end
  if err ~= lastReadError then
    lastReadError = err
    log("%s", err)
  end
end

local WEAPON_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local function weaponIn(slot)
  local id = GetInventoryItemID("player", slot)
  if id and select(6, GetItemInfoInstant(id)) == WEAPON_CLASS then return id end
end

local function bagPoisons()
  local found = {}
  for _, id in ipairs(POISONS) do
    local n = GetItemCount(id)
    if n and n > 0 then tinsert(found, { id = id, count = n }) end
  end
  return found
end

-- Frames ---------------------------------------------------------------------------
-- One tooltip-style panel. Each weapon without poison is a row: its icon with a pulsing
-- red glow, its name in item-quality colour and the hand under it, then the poisons.

local bar = CreateFrame("Frame", "RoguePoisonBar", UIParent)
bar:SetSize(1, 1)
bar:SetPoint("TOP", UIParent, "TOP", 0, -90)
RegisterStateDriver(bar, "visibility", "[combat] hide; show")

local panel = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetPoint("TOP")
if panel.SetBackdrop then
  panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
  panel:SetBackdropBorderColor(0.6, 0.6, 0.6)
end
panel:Hide()

local separator = panel:CreateTexture(nil, "ARTWORK")
separator:SetColorTexture(0.6, 0.6, 0.6, 0.35)
separator:SetSize(1, ICON + 4)

-- Icon cropped to drop the built-in edge, inside a 1 px black frame.
local function makeIcon(parent, layer, size)
  local icon = parent:CreateTexture(nil, layer)
  icon:SetSize(size, size)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local edge = parent:CreateTexture(nil, "BACKGROUND")
  edge:SetColorTexture(0, 0, 0, 1)
  edge:SetPoint("TOPLEFT", icon, -1, 1)
  edge:SetPoint("BOTTOMRIGHT", icon, 1, -1)
  return icon
end

local function makeButton(row, slot)
  local b = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
  b:SetSize(BUTTON, BUTTON)
  -- Both, so the click goes off once whatever the "cast on key down" setting is.
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  b:SetAttribute("target-slot", slot)
  b.icon = makeIcon(b, "ARTWORK", BUTTON)
  b.icon:SetPoint("CENTER")
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:HookScript("OnClick", function(self, button, down)
    log("click item %s -> slot %d (%s, %s)", tostring(self.itemID), slot, tostring(button),
      down and "down" or "up")
  end)
  b:Hide()
  return b
end

local rows = {}
for i, hand in ipairs(HANDS) do
  local row = CreateFrame("Frame", nil, panel)
  row:SetHeight(ICON)
  row.weapon = makeIcon(row, "ARTWORK", ICON)
  row.weapon:SetPoint("LEFT")
  -- Textures take no mouse, so a plain frame over the icon shows the weapon's tooltip.
  local hover = CreateFrame("Frame", nil, row)
  hover:SetAllPoints(row.weapon)
  hover:EnableMouse(true)
  hover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetInventoryItem("player", hand.slot)
    GameTooltip:Show()
  end)
  hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local glow = row:CreateTexture(nil, "OVERLAY")
  glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(1, 0.15, 0.15)
  glow:SetSize(ICON * 1.8, ICON * 1.8)
  glow:SetPoint("CENTER", row.weapon)
  local pulse = glow:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(0.2)
  fade:SetToAlpha(1)
  fade:SetDuration(0.8)
  row:SetScript("OnShow", function() pulse:Play() end)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("TOPLEFT", row.weapon, "TOPRIGHT", 8, -3)
  row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.status:SetPoint("BOTTOMLEFT", row.weapon, "BOTTOMRIGHT", 8, 4)
  row.status:SetTextColor(1, 0.35, 0.35)

  row.buttons = {}
  for j = 1, MAX_BUTTONS do
    row.buttons[j] = makeButton(row, hand.slot)
  end
  row:Hide()
  rows[i] = row
end

-- Layout ---------------------------------------------------------------------------

local testMode = false
local lastKey

local function layout()
  if InCombatLockdown() then return end

  local state = poisoned()
  local poisons = bagPoisons()
  local isRogue = select(2, UnitClass("player")) == "ROGUE"
  local show = {}
  if state and isRogue and (#poisons > 0 or UnitLevel("player") >= POISON_LEVEL) then
    for i, hand in ipairs(HANDS) do
      local weapon = weaponIn(hand.slot)
      if weapon and (testMode or not state[hand.slot]) then
        tinsert(show, { row = rows[i], hand = hand, weapon = weapon })
      end
    end
  end

  -- Skip the rebuild when nothing changed (the ticker calls this every second).
  local parts = {}
  for _, s in ipairs(show) do tinsert(parts, s.hand.slot .. ":" .. s.weapon) end
  for _, p in ipairs(poisons) do tinsert(parts, p.id .. "x" .. p.count) end
  local key = table.concat(parts, ",")
  if key == lastKey then return end
  lastKey = key
  log("layout %s", key ~= "" and key or "(hidden)")

  for _, row in ipairs(rows) do row:Hide() end
  if #show == 0 then
    panel:Hide()
    return
  end

  -- Weapons side by side: each one is its icon, its texts, then its poisons.
  local n = math.min(#poisons, MAX_BUTTONS)
  local x = PAD + 2
  for idx, s in ipairs(show) do
    local row, slot = s.row, s.hand.slot
    row.weapon:SetTexture(GetInventoryItemTexture("player", slot)
      or select(5, GetItemInfoInstant(s.weapon)))
    local link = GetInventoryItemLink("player", slot)
    row.name:SetText(link and link:match("%[(.-)%]") or "")
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[GetInventoryItemQuality("player", slot) or 1]
    if color then row.name:SetTextColor(color.r, color.g, color.b) end
    row.status:SetText(s.hand.label .. (#poisons > 0 and ": no poison"
      or ": no poison, none in your bags"))
    local textWidth = math.max(row.name:GetStringWidth(), row.status:GetStringWidth())
    local buttonsX = ICON + 8 + textWidth + 12
    local width = n > 0 and (buttonsX + n * BUTTON + (n - 1) * GAP) or (ICON + 8 + textWidth)
    for j, b in ipairs(row.buttons) do
      local p = poisons[j]
      if p and j <= n then
        b.itemID = p.id
        b:SetAttribute("item", "item:" .. p.id)
        b.icon:SetTexture(select(5, GetItemInfoInstant(p.id)))
        b.count:SetText(p.count > 1 and p.count or "")
        b:ClearAllPoints()
        b:SetPoint("LEFT", row, "LEFT", buttonsX + (j - 1) * (BUTTON + GAP), 0)
        b:Show()
      else
        b:Hide()
      end
    end
    row:SetWidth(width)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -PAD)
    row:Show()
    x = x + width + SIDE_GAP
    -- A thin line between the two weapons.
    if idx == 1 then
      separator:ClearAllPoints()
      separator:SetPoint("TOP", panel, "TOPLEFT", x - SIDE_GAP / 2, -PAD + 2)
    end
  end
  separator:SetShown(#show > 1)
  panel:SetSize(x - SIDE_GAP + PAD + 2, ICON + 2 * PAD)
  panel:Show()
end

-- Events ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    RoguePoisonDB = RoguePoisonDB or {}
    RoguePoisonDB.log = {}
    log("login, interface %s", tostring(select(4, GetBuildInfo())))
    -- A poison wearing off fires no event every client sends, so check each second too.
    C_Timer.NewTicker(1, layout)
  end
  layout()
end)

SLASH_ROGUEPOISON1 = "/rpoison"
SlashCmdList.ROGUEPOISON = function(msg)
  msg = strlower(strtrim(msg or ""))
  if msg == "debug" then
    RoguePoisonDB.debug = not RoguePoisonDB.debug
    say("debug log " .. (RoguePoisonDB.debug and "on (/reload saves it)" or "off"))
  elseif msg == "test" then
    testMode = not testMode
    lastKey = nil
    layout()
    say("test mode " .. (testMode and "on: the bar shows even on poisoned weapons" or "off"))
  else
    local state = poisoned()
    if not state then
      say("cannot read your weapon enchants: " .. tostring(lastReadError))
    else
      for _, hand in ipairs(HANDS) do
        local w = weaponIn(hand.slot)
        say(format("%s: %s", hand.label,
          not w and "no weapon" or state[hand.slot] and "poisoned" or "no poison"))
      end
    end
    say("/rpoison test shows the bar on poisoned weapons too; /rpoison debug logs to SavedVariables.")
  end
end
