#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/platform.sh
source "$SCRIPT_DIR/scripts/lib/platform.sh"

# Install Rokit if missing, then run update.sh and install the Rojo plugin.

if command -v rokit >/dev/null 2>&1; then
    echo "You've already installed rokit on your PC"
else
    REPO="rojo-rbx/rokit"
    GITHUB_API_URL="https://api.github.com/repos/${REPO}/releases/latest"

    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$OS" in
        darwin) OS="macos" ;;
        linux) OS="linux" ;;
        cygwin*|mingw*|msys*) OS="windows" ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|x86-64) ARCH="x86_64" ;;
        arm64|aarch64) ARCH="aarch64" ;;
        *)
            echo "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    RELEASE_JSON="$(curl -sSf -H "X-GitHub-Api-Version: 2022-11-28" "$GITHUB_API_URL")"
    TAG="$(github_release_tag "$RELEASE_JSON" || true)"

    if [[ -z "${TAG:-}" ]]; then
        echo "Failed to determine latest rokit release tag."
        exit 1
    fi

    VERSION="${TAG#v}"
    EXT=""
    BIN="rokit"
    if [[ "$OS" == "windows" ]]; then
        EXT=".exe"
        BIN="rokit.exe"
    fi

    ASSET="rokit-${VERSION}-${OS}-${ARCH}.zip"
    URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

    TMPDIR="$(mktemp -d)"
    cleanup() { rm -rf "$TMPDIR"; }
    trap cleanup EXIT

    echo "Downloading rokit from $URL..."
    curl -L -o "$TMPDIR/rokit.zip" "$URL"

    # Official release zips contain only rokit/rokit.exe at the archive root.
    unzip -o -q "$TMPDIR/rokit.zip" "$BIN" -d "$TMPDIR"

    if [[ ! -f "$TMPDIR/$BIN" ]]; then
        echo "Downloaded archive did not contain expected binary: $BIN"
        exit 1
    fi

    if [[ "$OS" != "windows" ]]; then
        chmod +x "$TMPDIR/$BIN"
    fi

    echo "Running rokit self-install..."
    "$TMPDIR/$BIN" self-install

    ensure_rokit_path_in_shell_rc
    export_rokit_path_for_session
fi

export_rokit_path_for_session
bash "$SCRIPT_DIR/update.sh"
export_rokit_path_for_session
rojo plugin install
