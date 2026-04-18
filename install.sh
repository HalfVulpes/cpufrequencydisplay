#!/usr/bin/env bash
set -euo pipefail

APP_NAME="freqdisp"
REPO_SLUG="HalfVulpes/cpufrequencydisplay"
DEFAULT_BRANCH="master"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/$APP_NAME}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
TARGET_SCRIPT="$INSTALL_DIR/$APP_NAME"
TARGET_LINK="$BIN_DIR/$APP_NAME"
TARGET_VERSION="$INSTALL_DIR/VERSION"


log() {
    printf '[%s] %s\n' "$APP_NAME" "$*"
}


die() {
    log "$*"
    exit 1
}


have_cmd() {
    command -v "$1" >/dev/null 2>&1
}


download_to() {
    local url="$1"
    local dest="$2"

    if have_cmd curl; then
        curl -fsSL "$url" -o "$dest"
        return
    fi

    if have_cmd wget; then
        wget -qO "$dest" "$url"
        return
    fi

    die "Need curl or wget to download files."
}


download_text() {
    local url="$1"

    if have_cmd curl; then
        curl -fsSL "$url"
        return
    fi

    if have_cmd wget; then
        wget -qO- "$url"
        return
    fi

    die "Need curl or wget to fetch metadata."
}


detect_local_source() {
    local self_dir

    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$self_dir/freqdisp" ]; then
        printf '%s\n' "$self_dir"
    fi
}


get_local_version() {
    local source_dir="$1"

    if [ -d "$source_dir/.git" ] && have_cmd git; then
        git -C "$source_dir" describe --tags --always --dirty 2>/dev/null || true
        return
    fi

    printf 'local\n'
}


get_remote_ref() {
    local tag
    local tag_json

    if [ -n "${FREQDISP_REF:-}" ]; then
        printf '%s\n' "$FREQDISP_REF"
        return
    fi

    tag_json="$(download_text "https://api.github.com/repos/$REPO_SLUG/tags?per_page=1" 2>/dev/null || true)"
    tag="$(printf '%s\n' "$tag_json" | sed -n 's/.*"name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

    if [ -n "$tag" ]; then
        printf '%s\n' "$tag"
        return
    fi

    printf '%s\n' "$DEFAULT_BRANCH"
}


main() {
    local local_source=""
    local version=""
    local ref=""
    local source_url=""

    have_cmd python3 || die "python3 is required."

    mkdir -p "$INSTALL_DIR" "$BIN_DIR"
    local_source="$(detect_local_source || true)"

    if [ -n "$local_source" ]; then
        cp "$local_source/freqdisp" "$TARGET_SCRIPT"
        chmod +x "$TARGET_SCRIPT"
        version="$(get_local_version "$local_source")"
        log "Installed from local checkout: $local_source"
    else
        ref="$(get_remote_ref)"
        source_url="https://raw.githubusercontent.com/$REPO_SLUG/$ref/freqdisp"
        download_to "$source_url" "$TARGET_SCRIPT"
        chmod +x "$TARGET_SCRIPT"
        version="$ref"
        log "Downloaded ref: $ref"
    fi

    printf '%s\n' "$version" > "$TARGET_VERSION"
    ln -sfn "$TARGET_SCRIPT" "$TARGET_LINK"

    log "Installed script: $TARGET_SCRIPT"
    log "Launcher: $TARGET_LINK"
    log "Config file: $INSTALL_DIR/.freqdisp.json"
    log "Version: $version"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            log "Add $BIN_DIR to PATH if you want to launch '$APP_NAME' without the full path."
            ;;
    esac

    log "Run: $TARGET_LINK"
}


main "$@"
