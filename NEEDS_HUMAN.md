# Needs a human

`MANUAL-CHECKS.md` is authoritative; this file is only the index of what is outstanding. Entries are removed (or
struck through with the date) when the matching box in `MANUAL-CHECKS.md` is ticked.

| Raised | Gate | Detail | Where |
|--------|------|--------|-------|
| 2026-11-03 | ~~Creator Hub gate (owner-only): create the dev experience and record the ids~~ | **Closed 2026-11-03.** Both experiences exist; all three ids are in `Environments.luau` and `servePlaceIds` names the dev place. Machine-checked in `tests/project/project.spec.luau` | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | Creator Hub gate (owner-only): three command-bar checks | Dev DataStore write must succeed; the same write in production must fail with `StudioAccessToApisNotAllowed` (turn API access OFF for `SPOONS [BETA]` if it succeeds); pressing Play in production must refuse to boot | `MANUAL-CHECKS.md` M-04 |
| 2026-11-03 | Creator Hub gate (owner-only): Maximum Players = 10 on both places, and an 11th join refused | Place setting, not scriptable (`Players.MaxPlayers` is ReadOnly) | `MANUAL-CHECKS.md` M-05 |
| 2026-11-03 | ~~Studio verification pass: Rojo sync, require in a real server, live NaN rejection, gray-box map~~ | **Closed 2026-11-03.** All four signed off by the owner | `MANUAL-CHECKS.md` M-01, M-02, M-03, M-06 |
| 2026-11-03 | First green GitHub Actions run | The build environment cannot push, so `ci.yml` has never run remotely. Push a branch, confirm `ci` is green, record the run URL here. Also confirm `actions/checkout@v7` exists (it could not be verified from the build container). | `MANUAL-CHECKS.md` header |
