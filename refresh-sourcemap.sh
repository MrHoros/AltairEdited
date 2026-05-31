#!/usr/bin/env bash
# Regenerates sourcemap.json for editor / luau-lsp resolution.

set -euo pipefail

rojo sourcemap default.project.json --output sourcemap.json
