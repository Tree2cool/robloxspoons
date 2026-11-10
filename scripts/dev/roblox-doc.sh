#!/usr/bin/env bash
# Fetch a Roblox docs page as markdown, or fail loudly.
#
# WHY THIS EXISTS. The five Roblox doc hosts are DNS-blocked in the build container, so every
# WebFetch returns ENOTFOUND and the project recorded a standing "Verification Debt": every Roblox
# platform claim unverified. That was half true. Local DNS is blocked; the agent proxy resolves
# independently, so `curl` reaches them. Discovered 2026-11-10.
#
# The trap this wraps: a WRONG PATH RETURNS HTTP 200 with a Next.js app shell, not a 404. Reading
# one into an agent's context costs ~8 KB of markup and looks like a successful fetch. This script
# refuses anything that is not real markdown, so a bad path fails instead of lying.
#
# Usage:
#   scripts/dev/roblox-doc.sh class Camera
#   scripts/dev/roblox-doc.sh datatype RaycastParams
#   scripts/dev/roblox-doc.sh enum ScreenOrientation
#   scripts/dev/roblox-doc.sh search "world to viewport"
#   scripts/dev/roblox-doc.sh url https://create.roblox.com/docs/ui/frames.md
set -uo pipefail

kind="${1:-}"
name="${2:-}"
base="https://create.roblox.com/docs"

case "$kind" in
	class)    url="$base/reference/engine/classes/$name.md" ;;
	datatype) url="$base/reference/engine/datatypes/$name.md" ;;
	enum)     url="$base/reference/engine/enums/$name.md" ;;
	global)   url="$base/reference/engine/libraries/$name.md" ;;
	url)      url="$name" ;;
	search)
		# Find the real path instead of guessing one. Guessing is what returns the app shell.
		curl -sS --max-time 20 "$base/api/search?q=$(printf '%s' "$name" | sed 's/ /%20/g')" \
			| head -c 4000
		echo
		exit 0
		;;
	*)
		echo "usage: $0 {class|datatype|enum|global|url|search} <name>" >&2
		exit 2
		;;
esac

body="$(curl -sS --max-time 25 "$url" 2>&1)"

# Real pages open with YAML frontmatter. An app shell opens with <!DOCTYPE html>.
if [ "${body:0:3}" != "---" ]; then
	echo "NOT A DOCS PAGE: $url" >&2
	echo "Got ${#body} bytes starting: $(printf '%s' "${body:0:60}")" >&2
	echo "A wrong path returns 200 with an app shell. Try: $0 search \"$name\"" >&2
	exit 1
fi

printf '%s\n' "$body"
