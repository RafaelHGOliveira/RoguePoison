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
local BUTTON, GAP = 36, 4
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

local bar = CreateFrame("Frame", "RoguePoisonBar", UIParent)
bar:SetSize(1, 1)
bar:SetPoint("TOP", UIParent, "TOP", 0, -90)
RegisterStateDriver(bar, "visibility", "[combat] hide; show")

local function makeButton(block, slot)
  local b = CreateFrame("Button", nil, block, "SecureActionButtonTemplate")
  b:SetSize(BUTTON, BUTTON)
  -- Both, so the click goes off once whatever the "cast on key down" setting is.
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  b:SetAttribute("target-slot", slot)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
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

local blocks = {}
for i, hand in ipairs(HANDS) do
  local block = CreateFrame("Frame", nil, bar)
  block:SetHeight(26 + BUTTON + 8)
  local bg = block:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)
  block.text = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  block.text:SetPoint("TOP", 0, -6)
  block.text:SetTextColor(1, 0.3, 0.3)
  block.buttons = {}
  for j = 1, MAX_BUTTONS do
    block.buttons[j] = makeButton(block, hand.slot)
  end
  block:Hide()
  blocks[i] = block
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
        tinsert(show, { block = blocks[i], hand = hand, weapon = weapon })
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

  for _, block in ipairs(blocks) do block:Hide() end
  local y = 0
  for _, s in ipairs(show) do
    local block = s.block
    local icon = GetInventoryItemTexture("player", s.hand.slot) or select(5, GetItemInfoInstant(s.weapon))
    local name = GetInventoryItemLink("player", s.hand.slot)
    name = name and name:match("%[(.-)%]") or ""
    if #poisons > 0 then
      block.text:SetFormattedText("|T%s:16|t %s has no poison: %s", icon, s.hand.label, name)
    else
      block.text:SetFormattedText("|T%s:16|t %s has no poison, and none in your bags", icon,
        s.hand.label)
    end

    local n = math.min(#poisons, MAX_BUTTONS)
    local rowWidth = n * BUTTON + math.max(n - 1, 0) * GAP
    for j, b in ipairs(block.buttons) do
      local p = poisons[j]
      if p and j <= n then
        b.itemID = p.id
        b:SetAttribute("item", "item:" .. p.id)
        b.icon:SetTexture(select(5, GetItemInfoInstant(p.id)))
        b.count:SetText(p.count > 1 and p.count or "")
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", block, "TOP", -rowWidth / 2 + (j - 1) * (BUTTON + GAP), -26)
        b:Show()
      else
        b:Hide()
      end
    end

    block:SetHeight(n > 0 and (26 + BUTTON + 8) or 28)
    block:SetWidth(math.max(rowWidth, block.text:GetStringWidth()) + 24)
    block:ClearAllPoints()
    block:SetPoint("TOP", bar, "TOP", 0, y)
    block:Show()
    y = y - block:GetHeight() - 6
  end
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
