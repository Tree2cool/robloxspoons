# Needs a human

`MANUAL-CHECKS.md` is authoritative; this file is only the index of what is outstanding. Entries are removed (or
struck through with the date) when the matching box in `MANUAL-CHECKS.md` is ticked.

| Raised | Gate | Detail | Where |
|--------|------|--------|-------|
| 2026-11-03 | ~~Creator Hub gate (owner-only): create the dev experience and record the ids~~ | **Closed 2026-11-03.** Both experiences exist; all three ids are in `Environments.luau` and `servePlaceIds` names the dev place. Machine-checked in `tests/project/project.spec.luau` | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | ~~Production Studio API access was ON~~ | **Fixed and verified 2026-11-03.** Found by M-04 check 2 (`WROTE`), toggle turned off, re-run now gives `REFUSED | 403 ... StudioAccessToApisNotAllowed`. One throwaway key was written to the live production `m04` store before the fix | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | Creator Hub gate (owner-only): M-04 check 3 | After the above is fixed: press Play in the production place and confirm the server refuses to boot on the PersistenceMode tripwire | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | Creator Hub gate (owner-only): Maximum Players = 10 on both places, and an 11th join refused | Place setting, not scriptable (`Players.MaxPlayers` is ReadOnly) | `MANUAL-CHECKS.md` M-05 |
| 2026-11-03 | ~~Studio verification pass: Rojo sync, require in a real server, live NaN rejection, gray-box map~~ | **Closed 2026-11-03.** All four signed off by the owner | `MANUAL-CHECKS.md` M-01, M-02, M-03, M-06 |
| 2026-11-03 | ~~First green GitHub Actions run~~ | **Closed 2026-11-03.** `ci.yml` is green on the remote: [run 6](https://github.com/Tree2cool/robloxspoons/actions/runs/41582812758), commit `3ea2af0`, all 14 verify steps green as separate steps. `actions/checkout@v7` resolves and the SHA-pinned `setup-rokit` installs the pinned toolchain | `MANUAL-CHECKS.md` header |
