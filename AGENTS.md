# Rogue Poison

Rogue addon for WoW Forever, published on CurseForge as "Rogue Poison". The README says
what it does for players; this file is the workflow. It reads `WeaponSwapDB` from the
WeaponSwap addon (`../WeaponSwap`): keep working when that table is missing.

## After each change

1. `uv run tests/test_layout.py` must print `ALL OK` (`-v` prints each case). When a
   change adds a weapon source, a poison rule or a hide condition, add its case.
2. Commit it, without asking.
3. Copy `RoguePoison.lua` and `RoguePoison.toc` to
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\RoguePoison\`
   (and `Media\icon.tga` to its `Media\` when the icon changes).

The test runs the real `RoguePoison.lua` against a stubbed API, so it checks which
weapons the bar lists and what each button targets. Whether the game applies the poison
on the click is only known from a test in game.

## Release

`pwsh -File release.ps1 <version> <changelog.md>`, beta unless `-ReleaseType release`.
It runs the test, bumps the `.toc`, commits "Release X", tags, pushes, uploads the
`git archive` zip to CurseForge and copies the files into the game. Before running
anything heavy, check that the game is not running (see the global instructions).

## Debug log

Ask Rafael to type `/rpoison debug`, reproduce the problem and `/reload`, then read the
log yourself:
`C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\*\*\<character>\SavedVariables\RoguePoison.lua`.

## Client rules

What Forever allows (secure buttons only out of combat, reading weapon enchants, the
font string that rendered blank) is written in the comments of `RoguePoison.lua`, at the
top and next to the code that depends on it. Read them before changing the bar.
