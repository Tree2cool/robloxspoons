# Roblox documentation access — the Verification Debt is resolvable

**Found 2026-11-10, during Phase 04.1 planning.**

## What was believed

`CLAUDE.md` carries a standing Verification Debt: five Roblox documentation hosts
(`create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`,
`madstudioroblox.github.io`, `jsdotlua.github.io`) were DNS-blocked during research, so **every
Roblox platform claim in the research is unverified against primary docs**, and each phase's
research step must re-check the rows naming that phase without being able to resolve them.

## What is actually true

**Local DNS is blocked. The agent proxy is not.** `getent hosts create.roblox.com` fails, which is
why every `WebFetch` returns `ENOTFOUND` — and why the debt looked permanent. `curl` goes through
`$HTTPS_PROXY`, which resolves independently:

```
getent hosts create.roblox.com   -> fails
curl .../ColorCorrectionEffect.md -> 200, 10620 bytes, last_updated 2026-11-10T00:40:47Z
```

**So the debt is working debt, not a wall.** Platform claims can be verified from now on, and
should be, one phase at a time rather than in a sweep.

## How to fetch, and the trap

Use `scripts/dev/roblox-doc.sh`. Do not hand-roll a curl.

```
scripts/dev/roblox-doc.sh class Camera
scripts/dev/roblox-doc.sh datatype RaycastParams
scripts/dev/roblox-doc.sh enum ScreenOrientation
scripts/dev/roblox-doc.sh search "world to viewport"
```

**The trap it exists to stop: a wrong path returns HTTP 200 with a Next.js app shell, not a 404.**
It looks like a successful fetch and costs ~8-14 KB of markup in an agent's context. It caught the
author of this file *in the same session as writing the warning about it* — `RaycastParams` is a
**datatype**, not a class, and the class path returned 14,505 bytes of HTML. The script refuses
anything not starting with YAML frontmatter, so a bad path now fails loudly. When a path is
uncertain, `search` first rather than guessing.

## V-18, re-checked — the sharpest row against Phase 5

The claim on file: `RaycastParams.RespectCanCollide` **defaults to `false`**, the opposite of the
sight model Phase 3's validator used, so Phase 5's line-of-sight raycast must set it `true` or CI
and the live game disagree about what blocks sight. Recorded confidence: HIGH.

**Re-checked against the primary page (`last_updated: 2026-11-10T00:40:49Z`). The documented
behaviour is confirmed; the DEFAULT IS NOT DOCUMENTED.** The property's entry describes what
`true` does — use an intersected part's `CanCollide` in favour of its `CanQuery` — and states no
default. The constructor table lists only `instances`.

**This does not weaken the decision; it strengthens the reason.** Phase 5's D-03 sets
`RespectCanCollide` explicitly. The justification changes from "the default is wrong" to **"the
default is undocumented and therefore cannot be relied on"**, which is the better argument and
survives a future default change. The recorded HIGH confidence in "defaults to false" should be
**downgraded to UNVERIFIED** — it is not on the page, so wherever it came from, it was not this.

## What has not been re-checked

Everything else. This file records the ACCESS, plus the one row that was about to be written into
Phase 5's context as fact. The remaining rows (V-15, V-17, V-21, V-22, V-23, V-25, V-26, V-27,
V-30, V-34) stay as they are until the phase that needs them re-checks them, which is the process
`CLAUDE.md` already requires. Do not sweep them: a row re-checked without the phase's question in
hand tends to get the generically-true answer rather than the one that matters.
