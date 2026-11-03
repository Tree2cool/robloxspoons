# Needs a human

`MANUAL-CHECKS.md` is authoritative; this file is only the index of what is outstanding. Entries are removed (or
struck through with the date) when the matching box in `MANUAL-CHECKS.md` is ticked.

| Raised | Gate | Detail | Where |
|--------|------|--------|-------|
| 2026-11-03 | Creator Hub gate (owner-only): new test experience, Studio API access ON in dev and OFF in production, record ids | Fill `Environments.luau` and `servePlaceIds` | `MANUAL-CHECKS.md` M-04, M-05 |
| 2026-11-03 | Studio verification pass: Rojo sync, require in a real server, live NaN rejection, gray-box map | Needs Roblox Studio | `MANUAL-CHECKS.md` M-01, M-02, M-03, M-06 |
| 2026-11-03 | First green GitHub Actions run | The build environment cannot push, so `ci.yml` has never run remotely. Push a branch, confirm `ci` is green, record the run URL here. Also confirm `actions/checkout@v7` exists (it could not be verified from the build container). | `MANUAL-CHECKS.md` header |
