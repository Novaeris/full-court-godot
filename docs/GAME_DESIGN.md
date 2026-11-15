# Game Design

## Vision
A deep basketball management simulation set in the real world's cities, with original franchises and players, in the spirit of Football Manager and Basketball GM: strategic decisions with real consequences, a living league that evolves for decades, and a business layer that makes the player run an organization, not just a roster.

Pillars: strategic depth, credible simulation (attributes truly drive outcomes), interlocking business and basketball systems, long-term replayability, clear information-dense UI.

## Modes
### Owner Mode (first)
Player owns a franchise and runs it as a business; delegates basketball work to hired GM/coaches while setting direction.
- Organization: hire/fire GM, coaches, executives; philosophy and expectations; evaluate performance.
- Finance: budgets, payroll, revenue/expense, debt/loans, forecasts, franchise valuation.
- Arena & facilities: ticket prices, attendance, renovations, concessions, merchandise.
- Commercial: sponsorships, partnerships, marketing, brand value.
- Basketball oversight: objectives, approve major moves, decide leadership changes.
- Legacy: franchise value and stability over decades.
Key tradeoff loop: winning raises attendance, sponsors, valuation; but payroll, facilities and operating costs erode profit.

### Dynasty Mode (later, likely premium)
Deep multi-decade management: rosters, contracts, cap, free agency, trades, drafts, scouting, development, tactics, chemistry, injuries, history, Hall of Fame. Uses the same core as Owner Mode with more direct permissions.

## Fictional universe
Original cities, teams, branding, arenas, conferences, rules, players, coaches, executives, rivalries and history. Procedurally generated but coherent. Stable IDs; history persists.

## Implemented design decisions (data model)
- Players have 28 attributes in four groups (offensive 10, defensive 6, physical 6, mental 6), 7 personality traits (loyalty, ambition, ego, money focus, professionalism, temperament, adaptability) and 8 tendencies (how often they shoot threes, drive, post up, etc.). All rated 0-100 and defined in data files so they can be rebalanced. These are first drafts to be tuned against the simulation.
- Each player also has a hidden growth profile: potential, peak age, development rate, volatility.
- Contracts are standalone agreements with per-season salary, guaranteed money, player/team options and bonuses; this is what Owner Mode finance and later cap rules will build on.
- A team's market comes from its city (population, economy); its building is a separate arena; its roster is a list of players it has active contracts with.

- Staff roles: General Manager, Head Coach, Assistant Coach, Scout, Medical Staff, Business Executive. Each person has 17 possible skills (coaching: offensive/defensive strategy, development, game management, motivation, discipline; front office: talent evaluation, negotiation, trade acumen, long-term planning; scouting: accuracy, regional knowledge; business: financial acumen, marketing, community relations; medical: injury prevention, rehabilitation), the same personality traits as players, and a philosophy (pace, three-point emphasis, defensive aggression, ball movement, youth focus, star reliance, risk tolerance). In Owner Mode the owner hires and fires these people; a team may have only one GM and one head coach.
- Staff have a reputation (0-100) that will drive salary demands and who accepts which job.

- The world: 124 real cities in 54 real countries across six areas (North America 51, Europe 31, Asia 18, South America 10, Africa 9, Oceania 5). Teams are original franchises (generated nicknames, colors, arenas) placed in those cities; players and staff are generated with names fitting their nationality. No real teams, players or logos are used.
- Customizable leagues: the user chooses the league name, the number of teams (2-100), which areas teams come from (one area, several, or anywhere) or an exact list of cities, whether to favor the biggest cities or a random mix, optional custom team nicknames, and how many conferences and divisions (at least 2 teams per division). Teams are grouped geographically: conferences split west to east, divisions split south to north, so a North America + Europe league gets Americas and Europe conferences. The default is 30 North American teams in 2 conferences of 3 divisions.
- Players are mostly from the team's own country (default 55%); the rest come from all countries weighted by basketball talent (the United States, France, Spain, Serbia, Nigeria and others supply the most).
- A typical generated team: 15 players (stars rated in the high 70s, bench in the 40s), average age about 26-27, payroll roughly $65M-$195M, and 10 staff.

## Simulation principles
- Attributes (offense, defense, physical, mental) must change outcomes; no decorative stats.
- Possession-based engine accounting for tendencies, roles, tactics, matchups, fatigue, injuries, home court, pace, variance.
- Outputs: scores, box scores, advanced stats, standings, leaders, careers, records.
- Statistically plausible, verified by large-scale automated simulation.

## Monetization (guardrails)
Free-to-play; premium Dynasty Mode, expansions, extra leagues, cosmetics are candidates. No pay-to-win, no predatory mechanics, nothing core behind a paywall. No infrastructure until justified.

## Open design questions (need founder input as they arise)
- League structure and size (teams, season length, playoff format).
- How much realism vs. approachability in the financial model.
- Real-time vs. sim-by-day pacing and presentation of games.
