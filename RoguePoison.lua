-- Rogue Poison: when a weapon has no poison, a bar at the top of the screen names the
-- weapon and lists the poisons in your bags. Clicking one coats that weapon. It watches
-- the main and off hand, and, with WeaponSwap, the dagger or sword waiting in the bags.
--
-- Addon code cannot use items, so each poison is a SecureActionButton: type "item" uses
-- the poison, then "target-slot" (16 main hand, 17 off hand), or "target-bag" plus
-- "target-slot" for a weapon in the bags, picks the weapon it goes on. That is the macro
-- "/use Instant Poison" followed by "/use 16".
-- Secure buttons cannot be moved, shown or hidden in combat, so the bar is laid out only
-- out of combat and a state driver hides it while you fight.

local GetItemInfoInstant = GetItemInfoInstant or C_Item.GetItemInfoInstant
local GetItemCount = GetItemCount or C_Item.GetItemCount
local Container = C_Container or _G

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
local MAX_ROWS = 4 -- main hand, off hand, WeaponSwap's dagger and sword
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

-- Weapons in the bags ----------------------------------------------------------------
-- GetWeaponEnchantInfo only covers what you hold. For a weapon in the bags, the poison
-- shows in its tooltip as a green line ending in the time left, e.g.
-- "Instant Poison II (29 min)", so a hidden tooltip is read line by line.

local scanner = CreateFrame("GameTooltip", "RoguePoisonScanner", nil, "GameTooltipTemplate")

local function bagItemPoison(bag, slot)
  scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanner:ClearLines()
  scanner:SetBagItem(bag, slot)
  for i = 2, scanner:NumLines() do
    local line = _G["RoguePoisonScannerTextLeft" .. i]
    local text = line and line:GetText()
    if text and text:find("%(%d+ %a+%)") then
      local r, g = line:GetTextColor()
      if g > 0.9 and r < 0.2 then return text end
    end
  end
end

local function findInBags(id)
  if not id then return end -- an empty bag slot also has a nil item id
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for i = 1, Container.GetContainerNumSlots(bag) do
      if Container.GetContainerItemID(bag, i) == id then return bag, i end
    end
  end
end

-- The dagger and sword saved in WeaponSwap (its per-character WeaponSwapDB), when one of
-- them sits in the bags. With two copies of the sword, the one in the off hand is
-- already watched as the off hand; the copy in the bags is the one found here.
local function swapWeapons()
  local found = {}
  local ws = WeaponSwapDB
  if type(ws) ~= "table" then return found end
  for _, role in ipairs({ "dagger", "sword" }) do
    local id = ws[role]
    local bag, slot = findInBags(id)
    if bag then
      local line = bagItemPoison(bag, slot)
      tinsert(found, {
        label = (role == "dagger" and "Dagger" or "Sword") .. " in bags",
        bag = bag, slot = slot, weapon = id, poisoned = line ~= nil, line = line,
      })
    end
  end
  return found
end

-- Frames ---------------------------------------------------------------------------
-- One tooltip-style panel. Each weapon without poison is a row: its icon with a pulsing
-- red glow, its name in item-quality colour and where it is under it, then the poisons.

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

local separators = {}
for i = 1, MAX_ROWS - 1 do
  local line = panel:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.6, 0.6, 0.6, 0.35)
  line:SetSize(1, ICON + 4)
  line:Hide()
  separators[i] = line
end

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

local function makeButton(row)
  local b = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
  b:SetSize(BUTTON, BUTTON)
  -- Both, so the click goes off once whatever the "cast on key down" setting is.
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
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
    log("click item %s -> bag %s slot %s (%s, %s)", tostring(self.itemID),
      tostring(self:GetAttribute("target-bag")), tostring(self:GetAttribute("target-slot")),
      tostring(button), down and "down" or "up")
  end)
  b:Hide()
  return b
end

local rows = {}
for i = 1, MAX_ROWS do
  local row = CreateFrame("Frame", nil, panel)
  row:SetHeight(ICON)
  row.weapon = makeIcon(row, "ARTWORK", ICON)
  row.weapon:SetPoint("LEFT")
  -- Textures take no mouse, so a plain frame over the icon shows the weapon's tooltip.
  local hover = CreateFrame("Frame", nil, row)
  hover:SetAllPoints(row.weapon)
  hover:EnableMouse(true)
  hover:SetScript("OnEnter", function(self)
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if e.bag then
      GameTooltip:SetBagItem(e.bag, e.slot)
    else
      GameTooltip:SetInventoryItem("player", e.slot)
    end
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
    row.buttons[j] = makeButton(row)
  end
  row:Hide()
  rows[i] = row
end

-- Layout ---------------------------------------------------------------------------

local testMode = false
local lastKey

-- Every weapon to watch: { label, slot, bag (nil when equipped), weapon, poisoned }.
local function watched(state)
  local list = {}
  for _, hand in ipairs(HANDS) do
    local weapon = weaponIn(hand.slot)
    if weapon then
      tinsert(list, { label = hand.label, slot = hand.slot, weapon = weapon,
        poisoned = state[hand.slot] })
    end
  end
  for _, e in ipairs(swapWeapons()) do tinsert(list, e) end
  return list
end

local function layout()
  if InCombatLockdown() then return end

  local state = poisoned()
  local poisons = bagPoisons()
  local isRogue = select(2, UnitClass("player")) == "ROGUE"
  local show = {}
  if state and isRogue and (#poisons > 0 or UnitLevel("player") >= POISON_LEVEL) then
    for _, e in ipairs(watched(state)) do
      if testMode or not e.poisoned then tinsert(show, e) end
    end
  end

  -- Skip the rebuild when nothing changed (the ticker calls this every second).
  local parts = {}
  for _, e in ipairs(show) do
    tinsert(parts, (e.bag and (e.bag .. "/") or "") .. e.slot .. ":" .. e.weapon)
  end
  for _, p in ipairs(poisons) do tinsert(parts, p.id .. "x" .. p.count) end
  local key = table.concat(parts, ",")
  if key == lastKey then return end
  lastKey = key
  log("layout %s", key ~= "" and key or "(hidden)")

  for _, row in ipairs(rows) do
    row:Hide()
    row.entry = nil
  end
  for _, line in ipairs(separators) do line:Hide() end
  if #show == 0 then
    panel:Hide()
    return
  end

  -- Weapons side by side: each one is its icon, its texts, then its poisons.
  local n = math.min(#poisons, MAX_BUTTONS)
  local x = PAD + 2
  for idx, e in ipairs(show) do
    local row = rows[idx]
    if not row then break end
    row.entry = e
    local link, icon
    if e.bag then
      link = Container.GetContainerItemLink(e.bag, e.slot)
      icon = select(5, GetItemInfoInstant(e.weapon))
    else
      link = GetInventoryItemLink("player", e.slot)
      icon = GetInventoryItemTexture("player", e.slot) or select(5, GetItemInfoInstant(e.weapon))
    end
    row.weapon:SetTexture(icon)
    -- The link carries the quality colour; drop only the hyperlink and the brackets.
    row.name:SetText(link and (link:gsub("|H.-|h%[(.-)%]|h", "%1")) or "")
    row.status:SetText(e.label .. (#poisons > 0 and ": no poison"
      or ": no poison, none in your bags"))
    if e.bag then
      log("%s %d/%d tooltip poison line: %s", e.label, e.bag, e.slot, tostring(e.line))
    end

    local textWidth = math.max(row.name:GetStringWidth(), row.status:GetStringWidth())
    local buttonsX = ICON + 8 + textWidth + 12
    local width = n > 0 and (buttonsX + n * BUTTON + (n - 1) * GAP) or (ICON + 8 + textWidth)
    for j, b in ipairs(row.buttons) do
      local p = poisons[j]
      if p and j <= n then
        b.itemID = p.id
        b:SetAttribute("item", "item:" .. p.id)
        b:SetAttribute("target-bag", e.bag)
        b:SetAttribute("target-slot", e.slot)
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
    -- A thin line before the next weapon.
    if show[idx + 1] and separators[idx] then
      separators[idx]:ClearAllPoints()
      separators[idx]:SetPoint("TOP", panel, "TOPLEFT", x - SIDE_GAP / 2, -PAD + 2)
      separators[idx]:Show()
    end
  end
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
    log("login, interface %s, WeaponSwap %s", tostring(select(4, GetBuildInfo())),
      type(WeaponSwapDB) == "table" and "found" or "not found")
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
        if not weaponIn(hand.slot) then say(hand.label .. ": no weapon") end
      end
      for _, e in ipairs(watched(state)) do
        say(format("%s: %s", e.label, e.line or (e.poisoned and "poisoned" or "no poison")))
      end
    end
    say("/rpoison test shows the bar on poisoned weapons too; /rpoison debug logs to SavedVariables.")
  end
end
