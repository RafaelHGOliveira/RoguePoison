# Rogue Poison

A rogue addon for [WoW Forever](https://www.wowhead.com/forever). When a weapon you
hold has no poison, a bar at the top of the screen says which one and shows the
poisons in your bags. Click a poison and it goes on that weapon.

```
┌──────────────────────────────────────────┬────────────────────────────────────────────────┐
│ [icon] Meteor Shard       [Inst] [Dead]  │  [icon] Vileblood Scimitar       [Inst] [Dead] │
│        Main hand: no poison              │         Off hand: no poison                    │
└──────────────────────────────────────────┴────────────────────────────────────────────────┘
```

The weapons sit side by side. Each one shows its icon with a pulsing red glow, its name
in its quality colour, and the poisons next to it. A click on a poison next to the main
hand always coats the main hand. The number on a button is how many you carry. Hover a
poison or the weapon icon for its tooltip.

## When it shows

- You are a rogue, and either you carry a poison or you are level 20 or higher
  (Instant Poison's level). Below that, with no poisons, it stays out of the way.
- A main-hand or off-hand weapon has no poison. An off-hand item that is not a weapon
  is ignored.
- With [WeaponSwap](https://www.curseforge.com/wow/addons/rogue-weaponswap) installed,
  the dagger or sword it saved is waiting in your bags with no poison. Its row reads
  "Dagger in bags" or "Sword in bags", and a click coats that weapon in the bags, so it
  is poisoned when WeaponSwap puts it in your hand.
- You are out of combat. The game does not let an addon show, hide or change click
  buttons in combat, so the bar hides when a fight starts and comes back when it ends.

## Install

Copy the `RoguePoison` folder to
`World of Warcraft\_forever_\Interface\AddOns\RoguePoison`, then log in or `/reload`.

## Commands

| Command | |
|---|---|
| `/rpoison` | say which weapons have a poison |
| `/rpoison test` | show the bar on poisoned weapons too, to see it or replace a poison |
| `/rpoison debug` | turn the debug log on or off |

## How it works

Addon code cannot use items. Each poison is a secure action button set to use that
poison (`item:<id>`) on one equipment slot (`target-slot` 16 or 17). That is what the
macro `/use Instant Poison` followed by `/use 16` does. The addon only lays the buttons
out, out of combat; the click itself is the game's own code.

Whether a weapon is poisoned comes from `GetWeaponEnchantInfo`. Forever hides some
values from addons (`UnitPower` is one), so if this one is hidden too, `/rpoison`
says so and the bar stays hidden. That call only covers what you hold; for a weapon in
the bags, the addon reads its tooltip and looks for the poison's green line with the
time left, such as "Instant Poison II (29 min)". A poison button for a weapon in the
bags sets `target-bag` and `target-slot` to that bag slot.

The poisons it knows are listed by item id at the top of `RoguePoison.lua`: Instant,
Deadly, Wound, Crippling, Mind-numbing and Occult in every rank, plus Sebacious, Numbing
and Atrophic Poison.

## Debug log

With the debug log on, Rogue Poison records each change to the bar, each click and any
error reading the weapon enchants. After a `/reload`, it is in
`WTF\Account\<account>\<realm>\<character>\SavedVariables\RoguePoison.lua`.

## License

MIT. See [LICENSE](LICENSE).
