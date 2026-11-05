# Phase 4 — Verification Debt re-check (orchestrator pass, 2026-11-05)

> Written by the autonomous orchestrator BEFORE plan-phase research, because it changes what
> that research is able to do. **This is a partial pass, not the full one.** The roadmap's
> standing rule still applies: the phase researcher must work the V-rows naming Phase 4 and
> record what was confirmed or changed.

## THE HEADLINE: the blocked documentation hosts are reachable again

Every Roblox platform claim in this project has been carried as unverified since project init
because five documentation hosts were DNS-blocked. **Three of them now answer 200 from this
container:**

| Host | Status 2026-11-05 |
|------|-------------------|
| `create.roblox.com` | **200** — and serves machine-readable Markdown |
| `devforum.roblox.com` | **200** (root; individual threads not yet exercised) |
| `robloxapi.github.io` | **200** (root; not yet exercised) |
| `madstudioroblox.github.io` | not re-tested in this pass |
| `jsdotlua.github.io` | not re-tested in this pass |

Phase 3's note recorded `create.roblox.com` as reachable "only via `curl` on `.md` URLs, with
`WebFetch` failing". That is now understated — there is a documented machine interface:

- **Append `.md` to any docs URL** to get Markdown instead of the HTML app.
  `https://create.roblox.com/docs/reference/engine/enums/ScreenInsets.md`
- **`/docs/llms.txt`** — full documentation index (187 KB), with a "For Code Agents: Start Here"
  table at the top.
- **`/docs/reference/engine/llms.txt`** — Engine API index specifically.
- **`/docs/api/search?q=<question>`** — JSON search endpoint returning title/url/summary/type.
  This is the cheapest way to locate the right page.
- Pages carry a `last_updated` field in frontmatter (currently `2026-11-04`), so staleness is
  checkable rather than assumed.

**Cost warning for whoever uses this:** a wrong docs path returns **HTTP 200-shaped HTML**, not a
clean 404 body — a mistyped URL dumps the entire Next.js app shell (tens of KB of script tags)
into context. Always request the `.md` form, and filter on `content_type: text/markdown` before
printing. Locate pages via the search endpoint rather than guessing paths.

## V-24 — `ScreenInsets` enum values and behaviour: **VERIFIED**

Source: `https://create.roblox.com/docs/reference/engine/enums/ScreenInsets.md`
(`last_updated: 2026-11-04T22:23:21Z`). Previously "STACK/PITFALLS, MEDIUM-HIGH (snippets)".

| Name | Value | Meaning |
|------|-------|---------|
| `None` | 0 | No insets. May be obscured by notches/cutouts. Documentation says use it **only** for a `ScreenGui` holding non-interactive content such as background images. |
| `DeviceSafeInsets` | 1 | Clear of **device** cutouts (camera notch) but **NOT** of Roblox core UI such as the top bar buttons. |
| `CoreUISafeInsets` | 2 | `DeviceSafeInsets` plus Roblox core UI. Documentation explicitly recommends this "for any `ScreenGui` that contains interactive and/or important UI elements such as buttons and status messages". |
| `TopbarSafeInsets` | 3 | `DeviceSafeInsets` plus core UI, but **dynamic** and limited to the space inside the top bar area, outside `CoreUISafeInsets`. Pairs with `GuiService.TopbarInset` for the absolute unobstructed top-bar rect. |

Insets are relative to the **fullscreen area** — the rect encompassing all visible pixels.

**Direct consequence for UX-03 and for the UI-SPEC:** the card table's hand, the tappable left
pile and every transient status cue are interactive/important UI, so the governing `ScreenGui`
should be **`CoreUISafeInsets`**, not `DeviceSafeInsets`. That is now a documented
recommendation rather than an inference. `GuiService.TopbarInset` is available if anything ever
needs to sit in the top bar strip.

## Still open after this pass — for the phase researcher

- **V-25** (48 px minimum touch target) — NOT verified here. The project uses 48 px as its own
  floor (UX-01); the 44 px figure in research remains an unattributed third-party guideline.
  Worth searching `/docs/api/search` for Roblox's own guidance before claiming either number.
- **V-26** (`require(PlayerScripts.PlayerModule):GetControls():Disable()` still works) — NOT
  verified. The cross-platform guide does not mention it and the search endpoint surfaced only
  adjacent enums (`DevComputerMovementMode`, `ControlMode`, `PlayerScripts`). This one is
  **load-bearing for UX-02** and for D-29 (controls hide per player while seated, and must come
  back the instant a finisher stands up), so it deserves a real answer, and a Studio check if the
  docs stay silent.
- **V-27** (`ContextActionService` mobile button behaviour, `GuiService.SelectedObject` for
  gamepad) — not attempted.
- **V-12** (same-remote ordering guarantee for `RemoteEvent`; cross-remote NOT guaranteed) and
  **V-13** (signal deferred vs immediate default) — not attempted. V-12 matters here: the card
  shell publishes engine events outward, and ordering assumptions across remotes would be unsafe.
- **V-34** (rate-limit numbers, LOW confidence) and **V-35** (whether the bot reaction-time
  distribution represents humans) — V-35 cannot be closed by documentation at all; it needs a
  real playtest, and it is the open half of D-13's justification for sitting at the 8.0 s ceiling.

## Recommendation

Do NOT upgrade any row not listed as VERIFIED above. But the standing rule's premise has
changed: primary sources are now fetchable, so rows that were carried purely for lack of access
can and should be properly closed — starting with V-26, which this phase actually depends on.
