# Manual quality and accessibility audit (Phase 7)

Date: 2026-11-21. The automated tests cannot judge taste, comfort or legal status. This file separates **what was done by looking or measuring** from
**what a person still has to do**. Nothing below is marked done unless it was actually done in this session. The session had no speakers, microphone,
gamepad, screen reader or physical phone, and no lawyer.

## Audio (17 built sounds)

| Check | Status |
|---|---|
| Listen to all 17 sounds; volume balance, harshness, repetition | **OUTSTANDING** (needs ears and speakers). A tool that renders each sound to a WAV for a person to play would help; not built. |
| Sounds exist, are deterministic, never clip, right length and key | Automated (`test_audio.gd`, `test_live_audio.gd`). |
| Mute and independent volume (Master, UI, SFX, Music) | Automated for the settings and buses; **not heard**. |
| Reduced motion and skipped animations stay quiet | Automated (a skipped reveal plays no sting); **not heard**. |
| On a phone | The emulator run had audio disabled (`-no-audio`): **not tested**. |

## Input and accessibility

| Check | Status |
|---|---|
| Keyboard reach of every enabled button and card | Automated (Phase 12) and the new focus-style check for the theme (Button, CheckBox, OptionButton, LineEdit, SpinBox must have a non-empty focus style, `test_release_fixes.gd`). |
| Focus order and visible focus | Order not reviewed by a person. Focus *style* verified present; contrast verified (Phase 12). A person should Tab through Dynasty, Owner and Career once. **OUTSTANDING.** |
| Game controller | **Not tested** (no gamepad). |
| Screen reader | **Not tested.** Cards carry accessible text; Godot's screen-reader support on Windows and Android needs a real pass with NVDA/TalkBack. |
| Text scaling | Three sizes now laid out in real viewports for every Dynasty screen, all Owner tabs and the menus (screen matrix): no clipped control. Looked at on the emulator at Normal only. |
| Contrast | Automated (every text colour on every surface, rarity colours on cards). |

## Graphics and animation

| Check | Status |
|---|---|
| Card foil and rarity effects, pack reveal pacing, post-game look | Screenshots exist for every size (`docs/validation/ui/final`); **pacing and feel need a person watching a real window**. |
| Portrait consistency | Same resolver everywhere (D-050); not re-reviewed. |
| Motion reduction | Automated. |
| Frame times | **Not measured.** Build times only. The emulator was a software/host-translated GPU: its speed means nothing for phones. |
| Owner tabs | Reviewed by looking at all 13 (`OWNER_PRESENTATION_AUDIT.md`). |

## Legal and licensing (inventory, NOT clearance)

| Asset | Source | Licence | Status |
|---|---|---|---|
| Inter variable font | github.com/google/fonts `ofl/inter` | SIL OFL 1.1, text shipped in the package (`assets/fonts/OFL-Inter.txt`) | Licence file now included in exports. |
| Barlow Condensed (3 weights) | github.com/google/fonts | SIL OFL 1.1 (`OFL-BarlowCondensed.txt`) | Licence file included in exports. |
| Lucide icons 0.469.0 (33 used of 65 files) | unpkg `lucide-static` | ISC (`assets/icons/lucide/LICENSE.txt`) | Licence file included in exports. |
| App icon `assets/icons/app_icon.svg` | Made for this project in this milestone | Original (no third-party material) | Fine; a designer may want to replace it. |
| Sounds | Built by the game from recipes (`data/ui/audio.json`) | None needed; `assets/audio` does not exist; a test enforces a SOURCES entry for any added file | Fine. |
| Godot engine | MIT; third-party component notices in Help > Copyright | The About screen shows the engine licences (earlier phase) | Check the notice is complete before release. |
| Player, team, staff names (Owner/Career generated, Dynasty Founding Series) | Invented | None | **Needs lawyer review** for collisions with real people and marks (`LEGAL_CHECKLIST.md` section 2). The 40 Founding Series names were chosen to avoid known real players but were not searched against any database. |
| Team names use real cities with invented nicknames (Savannah Mariners etc.) | Invented | | Lawyer should confirm none matches a real club in any target market. |
| Game title "Full Court" | | | Trademark search not done. |
| Paid random packs | | | Dynasty has published odds, guarantees and pity but **no purchase with real money exists**; the loot-box law review in `LEGAL_CHECKLIST.md` section 3 is still required before any monetization. |

**No legal clearance is claimed.** Everything marked "needs lawyer review" stays an open release blocker.
