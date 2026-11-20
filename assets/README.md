# Bundled third-party assets

Every asset here has a licence that allows use in a commercial game. Nothing is added without its licence text next to it
(`docs/LEGAL_CHECKLIST.md`, section 4). Audio is not bundled yet (decided in Phase 11 of `docs/UI_POLISH_PLAN.md`).

| Folder | What | Source | Licence |
|---|---|---|---|
| `fonts/Inter-Variable.ttf` | Inter (body text, variable weight) | github.com/google/fonts, `ofl/inter` | SIL Open Font License 1.1 (`fonts/OFL-Inter.txt`) |
| `fonts/BarlowCondensed-*.ttf` | Barlow Condensed Medium, SemiBold, Bold (headings, big numbers) | github.com/google/fonts, `ofl/barlowcondensed` | SIL Open Font License 1.1 (`fonts/OFL-BarlowCondensed.txt`) |
| `icons/lucide/*.svg` | Lucide icons, version 0.469.0 | unpkg.com/lucide-static@0.469.0 | ISC (`icons/lucide/LICENSE.txt`) |

Lucide icons were changed in one way: `currentColor` was replaced by `#FFFFFF`, so the game can tint each icon with a theme
colour (Godot does not support `currentColor`). Add an icon by copying it from the same Lucide version and applying the same replacement.
