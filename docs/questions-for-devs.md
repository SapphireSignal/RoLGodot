# Questions for the original developers

The snapshot (`reference/rise-of-legions` @ `96d5b8e4`) has the whole game client and game server, so every match
rule, number, unit, map and effect comes from the source. What it lacks is the closed **master server**: the backend
behind the menus. The client code (`BaseConflict.Api.*.pas`) shows the shape of the data it received, but not the
values. These questions ask only for those values. Answers are recorded here and, with the owner's approval, count as
a documented supplement to the source of truth (`docs/source-of-truth.md`), marked as developer-provided.

**The single most useful answer:** an export of the master server's database or its configuration tables for the last
version before Crystal Clash (cards, shop, quests, levels, scenarios, leagues). That answers nearly everything below
at once. Failing that, the questions one by one, most important first.

## 1. Cards and collection (`RCardConstants`, `RCard`, `TApiCardRequirement*`)
1. The card constants: `card_max_tier`, `card_level_per_tier`, `card_level_table`, `card_experience_value_table`,
   `card_upgrade_gold_cost`, `card_gold_value_table`, `card_gold_legendary_multiplier`.
2. Per card: `starting_tier` and the skins each card had (`RCardSkin`: uid, name).
3. Which cards a new account owned, and the starter decks offered (`starterdeck_chosen`).
4. Card unlock requirements (`CARDREQUIREMENT_PLAYERLEVEL` / `_CARDUNLOCKED` / `_GAMEEVENT`): which cards, which level
   or event, `use_times`.
5. How card experience was earned after a match (per card, per game), and how "ascension progress" worked.

## 2. Player level and rewards (`RProfileConstants`, `RLevelUpReward`)
6. `player_max_level`, the `player_level_table` (experience per level) and every level-up reward (`reaching_level`,
   reward contents, `additional_text`).
7. Player experience per match: win / loss amounts per scenario, the first-win-of-the-day bonus and its reset time,
   the daily reward, and how premium changed these (`experience_premium`).

## 3. Scenarios, leagues, ranking (`RScenario`, `RScenarioInstance`, `RMatchmakingRanking`)
8. The scenario list as the server served it: identifier, enabled, slots / teams, difficulty levels (tier, mutators),
   ranked, `minimum_playerlevel`, `deck_required`.
9. Deck constraints per scenario instance (limit tier, max tier, card colors).
10. Ranked play: ranks and leagues, stars per rank (`stars_to_climb`), stars won / lost per game, any protection rules.

## 4. Currencies and shop (`RCurrency`, `TApiShopItem*`, `ROffer`)
11. The currencies (uids, names: gold, crystals/premium, the per-color currencies of `RColorCurrencyEntry`).
12. The full shop: every item (kind, card / skin / icon / amount, purchase limits) and its offers (costs, which were
    real money, time limits).
13. Loot boxes, draft boxes and loot lists: contents and odds per `type_identifier` and league.
14. Deck slots: how many at start, cost of more. Premium account: what it gave.

## 5. Quests (`RQuest`, `RQuestData`)
15. Every quest: identifier, type (tutorial / daily / weekly / event), task (`custom_task_data`), `target_count`,
    reward, rerollable; how many daily quests at once, `max_rerolls`, reset times.

## 6. Smaller things
16. Profile icons available and how each was unlocked.
17. The dashboard / news texts the client showed (`client_dashboard_headline`, `client_dashboard_text`), if a final
    version exists.
18. Tutorial videos (`RTutorialVideo`): titles, order, and whether the videos themselves can be shared.
19. Leaderboards: what "points" were and how they were computed.

## Answers
(none yet)
