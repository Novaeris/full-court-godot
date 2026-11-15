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

- The world: 154 real cities in 83 real countries across seven areas (North America 55, Europe 45, Asia 19, Africa 15, South America 10, Middle East 5, Oceania 5). Countries are named as they call themselves (Russia, Türkiye, Taiwan, Hong Kong, Israel, Iran, Kosovo, Côte d'Ivoire...). Teams are original franchises (generated nicknames, colors, arenas) placed in those cities; players and staff are generated with names fitting their nationality. No real teams, players or logos are used.
- Customizable leagues: the user chooses the league name, 4-64 teams (more can be added later by expansion, up to 100 in a save), which areas teams come from (one, several, or anywhere) or an exact list of cities, whether to favor the biggest cities or a random mix, and conferences and divisions. Divisions must be EQUAL in size (3-8 teams; a 4-8 team league may be one division), so some team counts (11, 13, 17, 19, 22, 23, 26, 29, 31...) are not possible and the tool lists the sizes that work. Teams are grouped geographically: conferences split west to east, divisions south to north. The default is 30 North American teams, 2 conferences x 3 divisions of 5.
- Team names: the user can type a nickname and abbreviation for any team, or let the generator choose (a "generate a name" helper exists for single teams).
- League rules (chosen at creation, suggested automatically from the league size):
  - Schedule: games against each division opponent (recommended 2-3), other-division conference opponent (1-2) and other-conference opponent (1-2). Season length follows from the structure. Example, 30 teams: 4 division + 10 conference + 15 other-conference opponents, so 2/1/1 = 33 games, 3/2/2 = 62 games; ~82 games needs wider values such as 4/3/2 (76) or 3/2/3 (77). Small leagues need wider values to reach a 40+ game season. A fair home/away split (within one game for every team) is always possible; see the matchup planner.
  - Playoffs: qualification by division leaders (every division winner gets in and takes the top seeds, the rest of the spots go to the best records) or pure seeding (best records, no division guarantee); bracket per conference (conference champions then meet) or one league-wide bracket; any number of qualifying teams (top seeds get byes if it is not a power of two); best of 1, 3, 5 or 7 chosen per round.
  - Salary cap, default "soft cap with a hard limit": free agents need cap space; over the cap a team can only re-sign its own players, use one mid-level exception, and sign minimum contracts; payroll above the tax line is taxed at 150%; no team can ever exceed the hard limit (135% of the cap), so no one can sign everyone. Also maximum salary (30% of the cap), contract length (5 years) and raises (8%/year), roster limits (13-15). Alternatives: a strict hard cap, or no cap with a luxury tax.
- Players are mostly from the team's own country (default 65%); the rest come from all countries weighted by basketball talent (the United States, France, Spain, Serbia, Nigeria and others supply the most).
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
