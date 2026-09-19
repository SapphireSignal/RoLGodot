# Visual references

Pictures of **Rise of Legions** (never Crystal Clash) used as a visual cross-check beside the snapshot and the
reference build (`docs/source-of-truth.md`, owner's decision 2026-09-19). The snapshot wins where they disagree; every
disagreement is listed below with what was found.

## Steam store screenshots (app 748940)
Full-size copies: `build/visual-references/<id>.jpg` (git-ignored; downloaded 2026-09-19 with the owner's OK).
They show an **older** version than the snapshot (navbar LEGIONS / FEEDBACK where the snapshot's client has CARD VENDOR
/ LEADERBOARDS, card costs in coins and crystals): good for the general look, the snapshot wins on details.
The store page as archived on 2020-11-07 (`web.archive.org/web/20201107223409/https://store.steampowered.com/app/748940`,
title "Rise of Legions on Steam"), seven weeks before the snapshot. Images:
`https://steamcdn-a.akamaihd.net/steam/apps/748940/<id>.1920x1080.jpg` (some are 1280x720).

| Id | Shows |
| --- | --- |
| `ss_bc270313840c4e8567b2c69721f0d9155c0e7013` | match, Single map near the red nexus: player HUD (resource panel, deck bar with a card hint, top panel, minimap), green units; also the README's teaser |
| `ss_ac5881085d1f3fa381589282469b78f627523ebb` | match at the blue nexus: build grid with green spawners, card hint over the deck |
| `ss_b5d442537195a62eb2a85d73520f6d53b458bf25` | match on the bridge lane next to the sea, a red tower firing |
| `ss_9fd14159574ddaedbb98a711aa328d90a4ad683c` | match, a big fight near a nexus; the top panel with red on the left (the player is red) |
| `ss_9e68b7cc24381af30e457ebf70df61a937bc7ab7` | a red nexus exploding (game end) with green units around it, no HUD |
| `ss_aed3b81b2e3b91b4ffe0497bcd95c6ace818006a` | match on the bridge lane: a spell with light beams, a blue tower |
| `ss_af6fbd74552b921d6712b49557e228a14e154919` | a blue nexus exploding, no HUD |
| `ss_bdef5f912631b86513d8492d693a10af32b32cf1` | lobby: deckbuilder (navbar PLAY / DECKBUILDER / LEGIONS / SHOP, FEEDBACK, currencies, player box; card grid, filter panel, deck row at the bottom, Done) |
| `ss_204e268ce1f6e602d1cea06050d121370a2a3dea` | lobby: a card's detail dialog (stats table, upgrade path, Ascend button) |
| `ss_508f443f7adcb29ddacee91ba737345c49403bf7` | lobby: LEGIONS tab, the Black legion's card tree (unlock path, locks) |

## Checked against the reference build
- `ss_bdef…` (deckbuilder): the reference build's deck editor (`build/original/captures/lobby_deck_edit.png`) has the
  same layout (card grid 3x3 with stats and ability line, filter panel with colors / types / tiers / sort / deck icon /
  name, deck row, Done). Differences: its ability names show a diamond glyph for spaces (Delphi 13 text path,
  `docs/original-build.md` "Open"); the navbar says CARD VENDOR where the screenshot says LEGIONS (older build or
  language string: to check in `Lang/`).

## Disagreements to settle
- Build grid: in the match screenshots the tiles look dark slate grey (with spawner statues on them); the reference
  build and the port draw them glowing cyan at the start of a sandbox game. Probably timing (tiles darken when their
  spawner fires, `TBuildGridManagerComponent`), to check in the reference build mid-match with spawners.
