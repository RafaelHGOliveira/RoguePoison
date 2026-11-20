# /// script
# requires-python = ">=3.10"
# dependencies = ["lupa"]
# ///
"""Loads RoguePoison.lua against a stubbed WoW API and checks which weapons the bar shows
and what each poison button targets. Run: uv run tests/test_layout.py [-v]

It checks what the addon does, not what the game does with it: whether a secure button
with target-bag applies the poison still needs a test in game.
"""
import pathlib
import sys

try:
    from lupa import lua51 as L
except ImportError:
    import lupa as L

ADDON = pathlib.Path(__file__).resolve().parent.parent / "RoguePoison.lua"
VERBOSE = "-v" in sys.argv
DAGGER, SWORD, SWORD2 = 100, 200, 201
INSTANT, DEADLY = 6947, 2892

STUBS = r"""
format, tinsert, tremove, strlower = string.format, table.insert, table.remove, string.lower
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
date = os.date
function GetTime() return 0 end
function GetBuildInfo() return "1.60.1", "0", "", 16001 end
NUM_BAG_SLOTS = 4
state = { bags = {}, inv = {}, counts = {}, tooltips = {}, combat = false,
  class = "ROGUE", level = 30, mh = false, oh = false, enchantError = nil }
chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) tinsert(chat, m) end }
function InCombatLockdown() return state.combat end
function UnitClass() return "Rogue", state.class end
function UnitLevel() return state.level end
function GetWeaponEnchantInfo()
  if state.enchantError then error(state.enchantError) end
  return state.mh, 0, 0, 0, state.oh
end
WEAPONS = { [100] = true, [200] = true, [201] = true }
function GetItemInfoInstant(id) return id, nil, nil, nil, "icon" .. id, WEAPONS[id] and 2 or 0 end
function GetItemCount(id) return state.counts[id] or 0 end
function GetItemInfo(id) return "item" .. id end
local function link(id) return id and ("|cffffffff|Hitem:" .. id .. "|h[item" .. id .. "]|h|r") end
function GetInventoryItemID(_, slot) return state.inv[slot] end
function GetInventoryItemLink(_, slot) return link(state.inv[slot]) end
function GetInventoryItemTexture(_, slot) return state.inv[slot] and "icon" .. state.inv[slot] end
function GetInventoryItemQuality() return 2 end
C_Container = {
  GetContainerNumSlots = function() return 16 end,
  GetContainerItemID = function(bag, i) return state.bags[bag .. " " .. i] end,
  GetContainerItemLink = function(bag, i) return link(state.bags[bag .. " " .. i]) end,
  GetContainerItemInfo = function() return { quality = 2 } end,
}
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.1, g = 1, b = 0.1 } }
C_Timer = { NewTicker = function() end }
function RegisterStateDriver() end
SlashCmdList = {}

-- Frames: Show/Hide, attributes and scripts are recorded; any other method is a no-op.
frames = {}
local M = {}
local function noop() end
local meta = { __index = function(_, k) return M[k] or noop end }
local function newFrame(parent, template)
  local f = setmetatable({ attr = {}, scripts = {}, shown = true, parent = parent, template = template }, meta)
  tinsert(frames, f)
  return f
end
function M:Show() self.shown = true end
function M:Hide() self.shown = false end
function M:IsShown() return self.shown end
function M:SetAttribute(k, v) self.attr[k] = v end
function M:GetAttribute(k) return self.attr[k] end
function M:SetScript(what, fn) self.scripts[what] = fn end
function M:CreateTexture() return newFrame(self) end
function M:CreateFontString() return newFrame(self) end
function M:CreateAnimationGroup() return newFrame(self) end
function M:CreateAnimation() return newFrame(self) end
function M:GetStringWidth() return 80 end
function M:SetText(t) self.text = t end
function M:SetFormattedText(fmt, ...) self.text = format(fmt, ...) end
function M:GetText() return self.text end
function M:GetTextColor() return self.r, self.g, self.b end
function M:ClearLines() self.lines = 1 end
function M:NumLines() return self.lines or 1 end
-- The scanner tooltip: line 1 is the item name, then the lines in state.tooltips.
function M:SetBagItem(bag, slot)
  local lines = state.tooltips[bag .. " " .. slot] or {}
  self.lines = 1 + #lines
  for i, l in ipairs(lines) do
    local fs = newFrame(self)
    fs.text, fs.r, fs.g, fs.b = l[1], l[2], l[3], l[4]
    _G["RoguePoisonScannerTextLeft" .. (i + 1)] = fs
  end
end
UIParent, WorldFrame = newFrame(), newFrame()
function CreateFrame(_, name, parent, template)
  local f = newFrame(parent, template)
  if name then _G[name] = f end
  return f
end

-- Shown, and every parent up the chain shown too.
function visible(f)
  while f do
    if not rawget(f, "shown") then return false end
    f = rawget(f, "parent")
  end
  return true
end

-- The panel (the bar's only child frame) is shown.
function panelShown()
  for _, f in ipairs(frames) do
    if rawget(f, "parent") == RoguePoisonBar then return visible(f) end
  end
end

-- Visible poison buttons: "bag/slot:item" (bag "-" for an equipped weapon).
function visibleButtons()
  local out = {}
  for _, f in ipairs(frames) do
    if rawget(f, "template") == "SecureActionButtonTemplate" and visible(f) then
      tinsert(out, (f.attr["target-bag"] or "-") .. "/" .. f.attr["target-slot"] .. ":" .. f.attr.item)
    end
  end
  table.sort(out)
  return table.concat(out, " ")
end
function visibleTexts()
  local out = {}
  for _, f in ipairs(frames) do
    local text = rawget(f, "text")
    if type(text) == "string" and visible(f) and text:find("no poison") then
      tinsert(out, (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " / ")))
    end
  end
  return out
end
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
g = lua.globals()
g.RoguePoisonDB = lua.table_from({"debug": True})
lua.execute(ADDON.read_text(encoding="utf-8"))
handler = next(f.scripts["OnEvent"] for f in g.frames.values() if f.scripts["OnEvent"])
handler(None, "PLAYER_LOGIN")

GREEN, WHITE = (0.1, 1.0, 0.1), (1.0, 1.0, 1.0)


def setup(inv=None, bags=None, counts=None, tooltips=None, mh=False, oh=False, ws=None,
          cls="ROGUE", level=30, combat=False, enchant_error=None):
    st = g.state
    st.inv = lua.table_from(inv or {})
    st.bags = lua.table_from(bags or {})
    st.counts = lua.table_from(counts or {})
    st.tooltips = lua.table_from({k: lua.table_from([lua.table_from(l) for l in v])
                                  for k, v in (tooltips or {}).items()})
    st.mh, st.oh, st["class"], st.level, st.combat = mh, oh, cls, level, combat
    st.enchantError = enchant_error
    g.WeaponSwapDB = lua.table_from(ws) if ws else None
    handler(None, "BAG_UPDATE_DELAYED")


def bar():
    return g.panelShown(), g.visibleButtons(), list(g.visibleTexts().values())


def check(title, expect_shown, expect_buttons="", expect_texts=None):
    shown, buttons, texts = bar()
    if VERBOSE:
        print("=" * 8, title, "\n  shown:", shown, "\n  buttons:", buttons, "\n  texts:", texts)
    assert shown == expect_shown, (title, shown)
    assert buttons == expect_buttons, (title, buttons)
    if expect_texts is not None:
        assert texts == expect_texts, (title, texts)


POISONS = {INSTANT: 5, DEADLY: 1}
WS = {"dagger": DAGGER, "sword": SWORD}

setup(inv={16: SWORD, 17: SWORD2}, bags={"0 7": DAGGER}, counts=POISONS, oh=True, ws=WS)
check("main hand bare, off hand poisoned, WeaponSwap dagger bare in the bags", True,
      "-/16:item:2892 -/16:item:6947 0/7:item:2892 0/7:item:6947",
      ["item200 / Main hand: no poison", "item100 / Dagger in bags: no poison"])

setup(inv={16: SWORD, 17: SWORD2}, bags={"0 7": DAGGER}, counts=POISONS, mh=True, oh=True, ws=WS,
      tooltips={"0 7": [("Binds when picked up", *WHITE), ("Instant Poison II (29 min)", *GREEN)]})
check("everything poisoned, bag dagger by its green tooltip line", False)

setup(inv={16: SWORD, 17: SWORD2}, bags={"0 7": DAGGER}, counts=POISONS, mh=True, oh=True, ws=WS,
      tooltips={"0 7": [("Durability 40 / 40 (100 min)", *WHITE)]})
check("a white line with a time in brackets is not a poison", True,
      "0/7:item:2892 0/7:item:6947", ["item100 / Dagger in bags: no poison"])

setup(inv={16: SWORD, 17: DAGGER}, counts=POISONS, ws=WS)
check("WeaponSwap hand-swap setup: sword and dagger equipped, nothing in the bags", True,
      "-/16:item:2892 -/16:item:6947 -/17:item:2892 -/17:item:6947")

setup(inv={16: SWORD}, counts=POISONS, cls="WARRIOR")
check("not a rogue", False)

setup(inv={16: SWORD}, level=10)
check("level 10 and no poisons", False)

setup(inv={16: SWORD}, level=20)
check("level 20 and no poisons: the bar says so, no buttons", True, "",
      ["item200 / Main hand: no poison, none in your bags"])

setup(inv={16: SWORD}, counts=POISONS)
check("before combat", True, "-/16:item:2892 -/16:item:6947")
setup(inv={16: SWORD}, counts=POISONS, mh=True, combat=True)
check("in combat the layout is frozen (secure buttons)", True, "-/16:item:2892 -/16:item:6947")
setup(inv={16: SWORD}, counts=POISONS, mh=True)
check("after combat it catches up", False)

setup(inv={16: SWORD}, counts=POISONS, enchant_error="attempt to compare a secret number value")
check("GetWeaponEnchantInfo errors: no bar", False)
g.chat = lua.table()
g.SlashCmdList.ROGUEPOISON("")
assert "cannot read your weapon enchants" in g.chat[1], g.chat[1]

print("ALL OK")
