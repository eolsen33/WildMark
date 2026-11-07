# WildMark

A World of Warcraft Forever addon for druids. It watches the players around you, finds the ones without Mark of the Wild, and arms one button with the next of them. Click the button, or press the key you bind to it, and the buff goes out. Click again for the next one.

- **Who.** Your target first, then your group (you included), then friendly players standing nearby. Nearby strangers come from their nameplates, so friendly nameplates need to be on (`/wm plates`).
- **Gift of the Wild.** When three or more of your group need the buff and you carry the reagent, the button casts Gift instead. `/wm gift 0` turns that off.
- **Rebuffing.** Anyone under three minutes left counts as needing it (`/wm renew 0` for missing-only).
- **Skips.** Right-click skips the current player for ten minutes. `/wm ignore <name>` skips someone for good.

Bind the key under Key Bindings > AddOns > WildMark. `/wm` hides or shows the button, `/wm help` lists the rest.

Addons cannot cast spells on their own, so the button is a secure action button: it only changes who it points at while you are out of combat.

## Releasing

1. Bump `## Version` in `WildMark.toc` and note the changes in the commit.
2. `git tag v0.1.0 && git push origin main --tags`
3. The GitHub Action packages the addon and uploads it to CurseForge. The tag's commit message is the changelog.

Needs the `CF_API_KEY` repository secret (a CurseForge Upload API token) and `## X-Curse-Project-ID` in the TOC.
