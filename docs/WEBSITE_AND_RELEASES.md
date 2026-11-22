# Website and releases (founder decision 2026-11-22)

The old browser game and its website live in a separate repository (`Novaeris/Full-Court`: a Next.js app on Render with its own
Supabase project). **It is not touched by this project and is not used by the game.** The founder is making a NEW Supabase project for
this game and will handle the domain later.

## The site (`site/`)
A plain static site (HTML and CSS, no build step, no dependencies): a home page with the three modes and a Windows download button, and a
draft privacy page. The download button points to `https://github.com/Novaeris/full-court-godot/releases/latest`, which works once a
release exists. The privacy page is a **draft that a lawyer must review** before online accounts open (`LEGAL_CHECKLIST.md` section 5).

To publish it later (not done yet, nothing is hosted): GitHub Pages (Settings, Pages, deploy from the `site` folder via a workflow) or
Cloudflare Pages (build output directory `site`, no build command). Both are free for a site this size. Then point the domain at it.
Test locally by opening `site/index.html` in a browser.

## Releases (`tools/publish_release.ps1`)
1. Commit everything on `main`.
2. `./tools/publish_release.ps1` does a dry run: builds `builds/FullCourt-<version>-windows.zip`, prints the release notes and the SHA-256.
3. `./tools/publish_release.ps1 -Publish` creates the public GitHub Release `v<version>` of THIS repository with the zip attached.
Raise `GAME_VERSION` in `src/core/version.gd` for each release. Claude does not run the `-Publish` step on its own: it is public.

## Windows warning
An unsigned build shows Windows SmartScreen's "unknown publisher" screen. A code-signing certificate removes it (roughly $10 to 30 a
month through a managed signing service, or $100+ a year for a certificate). Not needed for early testers; revisit before a public launch.

## Not done
No hosting, no domain, no release published, no Mac build, no download counter. The Android and iOS builds are for Dynasty only (D-030)
and are not part of this page.
