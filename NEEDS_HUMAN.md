# Needs a human

`MANUAL-CHECKS.md` is authoritative; this file is only the index of what is outstanding. Entries are removed (or
struck through with the date) when the matching box in `MANUAL-CHECKS.md` is ticked.

| Raised | Gate | Detail | Where |
|--------|------|--------|-------|
| 2026-11-03 | ~~Creator Hub gate (owner-only): create the dev experience and record the ids~~ | **Closed 2026-11-03.** Both experiences exist; all three ids are in `Environments.luau` and `servePlaceIds` names the dev place. Machine-checked in `tests/project/project.spec.luau` | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | ~~Production Studio API access was ON~~ | **Fixed and verified 2026-11-03.** Found by M-04 check 2 (`WROTE`), toggle turned off, re-run now gives `REFUSED | 403 ... StudioAccessToApisNotAllowed`. One throwaway key was written to the live production `m04` store before the fix | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | **DEFERRED, do at first real deploy** — M-04 check 3, the boot tripwire | Press Play in `SPOONS [BETA]` and confirm the server refuses to boot (`Refusing real persistence: ... 10774453248`). Deferred because seeing it fire needs a publish over the live production place for a *secondary* control; the logic is unit-tested and the primary control (API access OFF) is verified | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | **DEFERRED, do at first 10-player playtest** — M-05 11th join | Confirm the 11th join is refused and the server stays at 10. Needs ten simultaneous real clients. The cap setting itself is confirmed on both places | `MANUAL-CHECKS.md` M-05 |
| 2026-11-03 | ~~Studio verification pass: Rojo sync, require in a real server, live NaN rejection, gray-box map~~ | **Closed 2026-11-03.** All four signed off by the owner | `MANUAL-CHECKS.md` M-01, M-02, M-03, M-06 |
| 2026-11-03 | ~~First green GitHub Actions run~~ | **Closed 2026-11-03.** `ci.yml` is green on the remote: [run 6](https://github.com/Tree2cool/robloxspoons/actions/runs/41582812758), commit `3ea2af0`, all 14 verify steps green as separate steps. `actions/checkout@v7` resolves and the SHA-pinned `setup-rokit` installs the pinned toolchain | `MANUAL-CHECKS.md` header |
| 2026-11-05 | Landscape lock: set supported orientation to landscape only in the Creator Dashboard, on both places | Human-only Dashboard setting (D-28) | `MANUAL-CHECKS.md` M-15 |
| 2026-11-05 | Pin `Workspace.PlayerScriptsUseInputActionSystem` explicitly (default `Disabled` for Phase 4) | Left at `Default` it flips the player scripts in early 2027 with no commit; re-run M-11 under `Enabled` before launch | `MANUAL-CHECKS.md` M-15 |
| 2026-11-05 | Audio asset ids for the completion sting, own draw and own pass | Empty id = silent, never an error (D-33) | `MANUAL-CHECKS.md` M-16 |
| 2026-11-05 | Suit-pip 4-cell sprite upload, only if the font glyphs fail on a phone | CARD-19; non-blocking, pips ship with a marked placeholder | `MANUAL-CHECKS.md` M-16 |
