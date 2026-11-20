# Dynasty Mode: draft design for the founder to correct (M7)

Status: **DRAFT written by Claude on 2026-11-17 using recommended answers. No code exists and none will be written until the founder approves or changes this and the legal questions below are settled.** The founder defined the idea (decision D-029): a card-collecting game inspired by NBA 2K MyTeam, with static hand-made players, some paid features, the only mode on mobile (D-030), and a ban on pay-to-win (project rules).

## The idea in one paragraph
You collect player cards (each is a hand-made, original player with fixed ratings and a rarity), build a five-man lineup plus bench under a budget rule, and play matches against AI lineups and other players' lineups, using the existing game simulation. You earn cards, coins and rewards by playing, completing collections and challenges. Paid features exist but never give a stronger card than a free player can get.

## Recommended answers
1. **How are cards obtained?** Recommended: by playing (match rewards, challenges, collection rewards, a daily login track), by exchanging duplicate cards for coins, and by an in-game market using only in-game coins. **No paid random packs** (see `docs/LEGAL_CHECKLIST.md`, section 3).
2. **What is paid?** Recommended: cosmetics (arenas, court designs, uniforms, card frames), a convenience pass (more lineup slots, faster collection tracking, no ads if ads ever exist) and a season pass with a *visible* reward list whose best items are also earnable for free over a longer time. No card or stat advantage is sold.
3. **How are matches played?** Recommended: the existing simulation with the lineup's tactics set before the game (pace, three-point emphasis, aggression: the sim already has these) and substitution rules; a match takes seconds, so mobile sessions are short. Live control during a game can come later.
4. **Balance rule against pay-to-win:** Recommended: a lineup "salary cap" in card points so stacking the best cards is impossible, and matchmaking by lineup strength. The game must run the whole pyramid for free players.
5. **Online:** Recommended phases: (1) fully offline vs AI, no accounts; (2) asynchronous play (your lineup defends, others attack it), which needs a server but no real-time play; (3) rankings and seasons. Accounts, a server and anti-cheat are a large separate project and need the privacy work in the legal checklist first.
6. **Card set:** the founder supplies the players. Recommended format: one data file per card family (name, position, appearance reference, attributes using the existing attribute catalog, tendencies, rarity, a short story). We already have the attribute and rating system, so cards are data, not code.
7. **Progression of cards:** Recommended: cards level up with use within a cap (no stat above the card's rarity ceiling); duplicates fuel upgrades.
8. **Mobile:** touch layouts (large buttons, portrait lineup builder), an Android build first (no Apple account needed to start), then iOS. Performance: the simulation core is headless and light (about 12 ms a game on a PC).

## What can be reused
Player attributes, ratings and the game simulation; team tactics; box scores and statistics; the save system; the UI theme and tutorial pattern; data-driven definitions.

## What must be new
- Card and collection data model (card definitions, owned cards with level and duplicates, currencies) with its own save section.
- Lineup builder and match flow screens designed for touch.
- Rewards, challenges, a market, a store and a pass system (data-driven).
- Matchmaking and, later, online services and moderation.
- A real store integration for the paid features (Google/Apple billing) and the legal paperwork.

## Proposed build order
1. Card data model and a starter set (about 30 cards) in the founder's format; collection screen.
2. Lineup builder with the point cap; one AI match using the simulation; rewards.
3. Challenges, daily tracks and the coin market (offline).
4. Mobile layouts and an Android build.
5. Paid features (cosmetics and a pass) after the legal review.
6. Online: asynchronous play, rankings.
Rough size: XL+ (months), mostly content, UI and online.

## Blocking questions (must be answered before design is final)
- Do you accept "no paid random packs" (recommended) or want them anyway (then odds disclosure, limits and a lawyer per country come first)?
- The first card set: how many players, what rarities, who supplies names, art and ratings, and which AI tool/licence?
- Online at launch, or offline first?
- The price model for paid features, and which platforms to launch on first.

## Content pipeline (D-042)
Dynasty cards and players are delivered as versioned content releases (see docs/ARCHITECTURE.md "Content publishing"), authored in Creator Studio and read by the game without a new build. Cards keep a stable `card_id`; owned cards are stored by id only.
