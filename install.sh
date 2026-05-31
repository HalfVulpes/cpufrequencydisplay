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
PATH_MARKER_BEGIN="# >>> freqdisp PATH >>>"
PATH_MARKER_END="# <<< freqdisp PATH <<<"
PATH_PROFILE_CANDIDATES=()
UPDATED_PATH_PROFILES=()


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


is_sourced() {
    [ "${BASH_SOURCE[0]}" != "$0" ]
}


shell_single_quote() {
    local value="$1"

    printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}


path_bin_assignment() {
    local default_assignment="FREQDISP_BIN_DIR=\"\$HOME/.local/bin\""

    if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
        printf '%s' "$default_assignment"
        return
    fi

    printf 'FREQDISP_BIN_DIR=%s' "$(shell_single_quote "$BIN_DIR")"
}


write_path_block() {
    local case_start="case \":\$PATH:\" in"
    local case_found="    *\":\$FREQDISP_BIN_DIR:\"*) ;;"
    local case_missing="    *) export PATH=\"\$FREQDISP_BIN_DIR:\$PATH\" ;;"

    printf '%s\n' "$PATH_MARKER_BEGIN"
    printf '%s\n' "# Added by the freqdisp installer; remove this block if you manage PATH elsewhere."
    path_bin_assignment
    printf '\n'
    printf '%s\n' "$case_start"
    printf '%s\n' "$case_found"
    printf '%s\n' "$case_missing"
    printf '%s\n' 'esac'
    printf '%s\n' 'unset FREQDISP_BIN_DIR'
    printf '%s\n' "$PATH_MARKER_END"
}


add_profile_candidate() {
    local candidate="$1"
    local existing

    [ -n "$candidate" ] || return

    for existing in "${PATH_PROFILE_CANDIDATES[@]}"; do
        [ "$existing" = "$candidate" ] && return
    done

    PATH_PROFILE_CANDIDATES+=("$candidate")
}


collect_path_profiles() {
    local shell_name="${SHELL:-}"

    PATH_PROFILE_CANDIDATES=()
    shell_name="${shell_name##*/}"

    case "$shell_name" in
        bash)
            add_profile_candidate "$HOME/.bashrc"
            add_profile_candidate "$HOME/.profile"
            ;;
        zsh)
            add_profile_candidate "$HOME/.zshrc"
            add_profile_candidate "$HOME/.zprofile"
            ;;
        *)
            add_profile_candidate "$HOME/.profile"
            ;;
    esac
}


profile_has_path_entry() {
    local profile="$1"
    local default_home_expr="\$HOME/.local/bin"
    local default_tilde_expr="~"

    default_tilde_expr="$default_tilde_expr/.local/bin"

    [ -f "$profile" ] || return 1

    grep -F "$PATH_MARKER_BEGIN" "$profile" >/dev/null 2>&1 && return 0
    grep -F "$BIN_DIR" "$profile" >/dev/null 2>&1 && return 0

    if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
        grep -F "$default_home_expr" "$profile" >/dev/null 2>&1 && return 0
        grep -F "$default_tilde_expr" "$profile" >/dev/null 2>&1 && return 0
    fi

    return 1
}


ensure_profile_path() {
    local profile="$1"
    local profile_dir

    profile_dir="$(dirname "$profile")"
    mkdir -p "$profile_dir"
    touch "$profile"

    if profile_has_path_entry "$profile"; then
        log "PATH already configured in: $profile"
        return
    fi

    {
        printf '\n'
        write_path_block
    } >> "$profile"

    UPDATED_PATH_PROFILES+=("$profile")
    log "Added $BIN_DIR to PATH in: $profile"
}


refresh_current_path() {
    case ":$PATH:" in
        *":$BIN_DIR:"*)
            log "Current PATH already includes: $BIN_DIR"
            ;;
        *)
            export PATH="$BIN_DIR:$PATH"
            if is_sourced; then
                log "Current shell PATH now includes: $BIN_DIR"
            else
                log "Current installer PATH now includes: $BIN_DIR"
            fi
            ;;
    esac
}


ensure_user_path() {
    local profile

    UPDATED_PATH_PROFILES=()

    if [ "${FREQDISP_SKIP_PATH_UPDATE:-}" = "1" ]; then
        log "Skipping PATH update because FREQDISP_SKIP_PATH_UPDATE=1"
        return
    fi

    collect_path_profiles
    for profile in "${PATH_PROFILE_CANDIDATES[@]}"; do
        ensure_profile_path "$profile"
    done

    refresh_current_path

    if [ "${#UPDATED_PATH_PROFILES[@]}" -gt 0 ]; then
        log "New terminals will load the updated PATH automatically."
    fi
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
    ensure_user_path

    log "Installed script: $TARGET_SCRIPT"
    log "Launcher: $TARGET_LINK"
    log "Config file: $INSTALL_DIR/.freqdisp.json"
    log "Version: $version"
    log "Run now: $TARGET_LINK"
    log "Run from PATH: $APP_NAME"
}


main "$@"
