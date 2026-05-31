#!/usr/bin/env bash
# Keeps sourcemap.json in sync while files change (macOS: fswatch, Windows: PowerShell).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

refresh_sourcemap() {
    echo "[$(date '+%H:%M:%S')] Regenerating sourcemap.json..."
    rojo sourcemap default.project.json --output sourcemap.json
    echo "[$(date '+%H:%M:%S')] sourcemap.json updated."
}

if [[ ! -f default.project.json ]]; then
    echo "default.project.json not found in repo root." >&2
    exit 1
fi

case "$(uname -s)" in
    Darwin)
        if ! command -v fswatch >/dev/null 2>&1; then
            echo "fswatch is required on macOS. Install it with: brew install fswatch" >&2
            exit 1
        fi

        echo "Watching src/ and *.project.json (fswatch). Press Ctrl+C to stop."

        shopt -s nullglob
        watch_paths=( -r src )
        for project_file in *.project.json; do
            watch_paths+=( "$project_file" )
        done
        shopt -u nullglob

        fswatch -l 0.3 -o "${watch_paths[@]}" | while read -r _; do
            refresh_sourcemap
        done
        ;;
    MINGW*|MSYS*|CYGWIN*)
        exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./watch-sourcemap.ps1
        ;;
    *)
        echo "Automatic sourcemap watching is not supported on this platform." >&2
        echo "Use bash refresh-sourcemap.sh or bash update.sh instead." >&2
        exit 1
        ;;
esac
