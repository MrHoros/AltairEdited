#!/bin/bash
# Updates Rokit tools, Wally packages, sourcemap, and generated types.

set -e
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Starting update..."
rokit install || true
rm -f wally.lock
wally install
rojo sourcemap default.project.json --output sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages/
bash "$SCRIPT_DIR/generate-reflex-types.sh"
bash "$SCRIPT_DIR/scaffold.sh" --install-completion
