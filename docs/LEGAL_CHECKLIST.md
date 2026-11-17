# Legal checklist before any commercial release

Status: **working checklist written by Claude on 2026-11-17. It is NOT legal advice.** Nothing here replaces a
lawyer who works in games and intellectual property. Facts below are from general knowledge up to mid-2026 and
rules change, so every item marked "verify" must be checked with a lawyer or the platform's current policy before
money changes hands. Nothing is sold and nothing is released today (the game is free to play and unreleased).

## 1. The source code license
- **Today:** the repository is public on GitHub with an all-rights-reserved `LICENSE` (commit "Add all-rights-reserved LICENSE"). People can read the code; nobody may copy or reuse it without permission. GitHub's terms let others view and fork a public repo on GitHub itself, which is normal.
- **Decide before release:** keep it proprietary (recommended while Dynasty Mode's paid features are planned), or open-source parts later. A change of license is easy toward more open, hard to take back.
- **Third-party code:** the game uses only Godot (MIT license) and its own code, no plugins. Keep a `THIRD_PARTY.md` when anything is added. A released build must carry Godot's license text (MIT requires the notice) and the licenses of Godot's own third-party components (Godot lists them in Help > Copyright, and the exported game should show them in a credits screen). *Action: add a Credits/Licenses screen before release.*
- **Contributor/author data:** commit history shows the author's name and email publicly. Decide whether that is acceptable (D-032 already notes it).

## 2. Names, places and brand (IP)
- **Original everywhere** (rule 9 in `CLAUDE.md`): teams, nicknames, player and staff names are generated; no real franchises, logos or league terms. Real cities and countries are used as places, which is normally fine.
- **Risks to check (verify):** (a) a generated team name or a generated person's name that equals a famous real team or athlete; (b) generated arena or sponsor names that match real companies (`data/generation/sponsors.json`); (c) trademarks on terms used in rules (the project already avoids league-branded terms; see D-020).
- **Action:** a one-time trademark search on the game title "Full Court" in the classes for software and games in the target countries; a lawyer review of the name lists in `data/generation/` (names, sponsors, nicknames) against real marks.
- Using real city names for fictional franchises can still collide with a real team that plays there. That is generally acceptable for a fictional name, but a lawyer should confirm for the markets you sell in.

## 3. Loot boxes and paid card packs (Dynasty Mode)
Dynasty Mode is planned as a card collection with "some paid features". Random paid packs are the highest legal risk in the plan.
- **What the rules look like (verify, they differ a lot and keep changing):** some countries treat paid random rewards as gambling or restrict them (Belgium has banned paid loot boxes and enforces it; the Netherlands has acted against them; other countries have investigated or regulated them). Several have disclosure rules. Apple and Google require the odds of paid random items to be shown before purchase. China requires published drop rates. The UK relies on industry self-regulation plus age-rating and consumer-protection law at the time of writing; the EU regulates through consumer-protection law and is considering more.
- **Recommended design (lowest risk):** no paid random packs. Sell things whose content is known at purchase (a specific card, a cosmetic, a convenience, a season pass with a visible reward list), and let packs be **earned** in play. The founder's rule "free-to-play, no pay-to-win" (CLAUDE.md) already points this way.
- **If paid random packs are kept anyway:** publish exact odds in game and in the store listing, add spending limits and age gating, make every item obtainable without payment, avoid a way to cash out or trade for real money (that moves it toward gambling), and block the feature in jurisdictions that ban it. Get a lawyer's written view per target country first.
- **Online and trading:** a real-money or cash-out market for cards must not exist. An in-game auction using only in-game currency still needs review.
- **Children:** if minors can play, consumer-protection and children's privacy rules apply (see section 5) and paid features need parental controls.

## 4. AI-generated art, audio and text
The founder plans to make art and audio with AI tools.
- **Copyright (verify):** in the United States the Copyright Office's position is that purely AI-generated material is not protected by copyright, while a human's creative selection, arrangement and edits can be. Other countries differ. Consequence: AI-only art may be copied by others, and you may not be able to enforce rights in it. Keep records of prompts, edits and human contribution.
- **Tool terms:** each AI tool's terms decide whether commercial use is allowed, who owns the output, and whether the tool may reuse your inputs. Read the exact current terms for every tool used, keep a copy (with date) of the version in force when each asset was made, and keep a file `ASSETS.md` listing each asset, the tool, the date and the license.
- **Training-data and lookalike risk:** output that resembles a real person, a real athlete, a trademark or a copyrighted character can infringe even if "generated". Do not prompt with real names or brands, and review outputs. For Dynasty's player portraits, avoid likenesses of real players.
- **Store disclosure:** Steam requires developers to disclose AI-generated content used in the game (and, for live-generated content, safeguards). Apple and Google have their own content rules. Disclose accurately; hiding it risks removal. (verify the current wording)
- **Voice and music:** avoid voice clones of real people and music "in the style of" a named artist; prefer tools whose terms grant commercial rights and give a license record.
- **Code:** AI-assisted code is fine for the game, but keep the licensing of anything pasted in clear. All code so far was written in a human-directed workflow with Claude Code; if outside investors or publishers ask, they may want a statement on that.

## 5. Privacy, accounts and online features
- **Today:** the game is offline. Saves and preferences stay on the player's computer; no data is sent anywhere. Nothing to disclose yet.
- **Before any online feature** (accounts, leaderboards, cloud saves, Dynasty trading, crash reports sent to a server): a privacy policy, a lawful basis and consent under GDPR/UK GDPR/CCPA where they apply, data-deletion on request, age checks (13 in the United States, up to 16 in parts of Europe), and a security review. A crash-report button must show the player what is sent.

## 6. Stores, ratings and consumer rules
- **Age rating:** the game has no violence; the paid-pack mechanic is what could raise a rating (some rating systems add a label for in-game purchases or random items). Fill in IARC/ESRB/PEGI questionnaires honestly.
- **Pricing and refunds:** each store has its own refund and price-display rules; EU consumer law has withdrawal rules for digital goods that must be handled in the purchase flow.
- **Taxes and company:** selling needs a legal entity or sole-proprietor registration, tax registration (VAT/sales tax through the store as merchant of record is the simplest route), and bank details. Ask an accountant.
- **Accessibility and localization laws:** some markets have accessibility requirements for digital products (for example the European Accessibility Act applies to certain e-commerce services from June 2025). Check whether a free offline game is in scope when selling.

## 7. Realistic order of work
1. Now (free, offline): keep rule 9 (original names), keep `LICENSE` as it is, start `ASSETS.md` and `THIRD_PARTY.md`.
2. Before showing the game publicly or to testers: Godot license notice in a Credits screen; decide the privacy position for crash logs.
3. Before art/audio is added: choose tools and archive their terms; start recording the human contribution.
4. Before Dynasty's design is final: lawyer meeting on loot boxes and country list; decide "no paid random packs" or the full odds-and-limits route.
5. Before release: trademark search for the title, name-list review, store disclosures, age rating, privacy policy, tax and entity set-up.

## Questions for the lawyer (copy this list)
1. Is the game title "Full Court" available as a trademark for games and software in the US, EU and UK?
2. Do any generated team nicknames, player names or sponsor names in `data/generation/` conflict with real marks or famous people?
3. Which of our target countries restrict paid random card packs, and what disclosures are mandatory elsewhere?
4. How should we document and own AI-assisted art and music so we can enforce our rights as far as the law allows?
5. Is a proprietary license with a public read-only repository acceptable, or should the repository be made private before release?
