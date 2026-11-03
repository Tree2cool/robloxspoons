# Spoons

A Roblox multiplayer party game: the card game Spoons split into a real-time card scramble and a hide-and-seek hunt.
The full design, rules and decisions live in `.planning/PROJECT.md`; the working agreement is in `CLAUDE.md`.

## Setup

Install [Rokit](https://github.com/rojo-rbx/rokit), then from a fresh clone:

```sh
rokit install                      # rojo, stylua, selene, luau-lsp, lune at the versions pinned in rokit.toml
lune setup                         # Lune type definitions (.luaurc aliases)
sh scripts/dev/setup-hooks.sh      # pre-commit: stylua + selene on staged Luau files
```

Rokit puts tools in `$HOME/.rokit/bin`. If a shell or a GUI git client cannot find them, add it to `PATH`:

```sh
export PATH="$HOME/.rokit/bin:$PATH"
```

## Daily commands

```sh
lune run tests/run.luau --filter <area>                        # quick, filtered test run
lune run scripts/verify.luau                                    # the whole CI chain, in order, then the manual-check list
lune run scripts/verify.luau --list                             # print the chain without running it
rojo serve                                                      # live sync into Studio
rojo build default.project.json -o build/spoons.rbxl            # build the place (mkdir -p build first)
```

## What a green run does not cover

Six checks need Roblox Studio or the Creator Hub and are listed, with steps, in `MANUAL-CHECKS.md`.
`NEEDS_HUMAN.md` indexes what is outstanding.
