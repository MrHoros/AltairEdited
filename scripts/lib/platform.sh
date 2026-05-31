# Cross-platform helpers for shell scripts (PATH, GitHub release JSON).

ROKIT_PATH_LINE='export PATH=$PATH:~/.rokit/bin'

platform_is_darwin() {
    [[ "$(uname -s)" == "Darwin" ]]
}

platform_uses_zsh_rc() {
    if platform_is_darwin; then
        return 0
    fi
    case "${SHELL:-}" in
        */zsh) return 0 ;;
        *) return 1 ;;
    esac
}

append_line_to_file_if_missing() {
    local file="$1"
    local line="$2"

    if [[ -f "$file" ]]; then
        if ! grep -Fxq "$line" "$file"; then
            echo "$line" >> "$file"
        fi
    else
        echo "$line" > "$file"
    fi
}

export_rokit_path_for_session() {
    export PATH="${PATH:+$PATH:}$HOME/.rokit/bin"
}

ensure_rokit_path_in_shell_rc() {
    if platform_uses_zsh_rc; then
        append_line_to_file_if_missing "$HOME/.zshrc" "$ROKIT_PATH_LINE"
        append_line_to_file_if_missing "$HOME/.zprofile" "$ROKIT_PATH_LINE"
    else
        append_line_to_file_if_missing "$HOME/.bashrc" "$ROKIT_PATH_LINE"
    fi
}

github_release_tag() {
    local json="$1"
    local tag=""

    if command -v python3 >/dev/null 2>&1; then
        tag="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null || true)"
    fi

    if [[ -z "$tag" ]]; then
        tag="$(printf '%s' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    fi

    if [[ -z "$tag" ]]; then
        return 1
    fi

    printf '%s' "$tag"
}
