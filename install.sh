#!/bin/sh
set -eu

APP_NAME="freqdisp"
REPO_SLUG="HalfVulpes/cpufrequencydisplay"
DEFAULT_BRANCH="master"
HOME_DIR="${HOME:-}"

if [ -z "$HOME_DIR" ]; then
    printf '[%s] HOME is required.\n' "$APP_NAME"
    exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-$HOME_DIR/.local/share/$APP_NAME}"
BIN_DIR="${BIN_DIR:-$HOME_DIR/.local/bin}"
TARGET_SCRIPT="$INSTALL_DIR/$APP_NAME"
TARGET_LINK="$BIN_DIR/$APP_NAME"
TARGET_VERSION="$INSTALL_DIR/VERSION"
PATH_MARKER_BEGIN="# >>> freqdisp PATH >>>"
PATH_MARKER_END="# <<< freqdisp PATH <<<"
UPDATED_PATH_PROFILES=""
OS_NAME="unknown"
OS_FAMILY="unknown"


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


os_release_value() {
    [ -r /etc/os-release ] || return 1
    sed -n "s/^$1=//p" /etc/os-release | head -n 1 | sed 's/^"//; s/"$//'
}


detect_os() {
    OS_NAME="$(uname -s 2>/dev/null || printf 'unknown')"
    OS_FAMILY="unknown"

    case "$OS_NAME" in
        Linux)
            if have_cmd pveversion || [ -d /etc/pve ]; then
                OS_FAMILY="pve"
                return
            fi

            os_id="$(os_release_value ID 2>/dev/null || true)"
            os_like="$(os_release_value ID_LIKE 2>/dev/null || true)"
            case " $os_id $os_like " in
                *debian*|*ubuntu*|*linuxmint*)
                    OS_FAMILY="debian"
                    ;;
                *fedora*|*rhel*|*centos*)
                    OS_FAMILY="fedora"
                    ;;
                *)
                    OS_FAMILY="linux"
                    ;;
            esac
            ;;
        Darwin)
            OS_FAMILY="macos"
            ;;
        FreeBSD)
            OS_FAMILY="freebsd"
            ;;
    esac
}


dependency_hint() {
    case "$OS_FAMILY" in
        pve|debian)
            printf '\nInstall dependencies with: sudo apt-get update && sudo apt-get install -y python3 curl'
            ;;
        fedora)
            printf '\nInstall dependencies with: sudo dnf install -y python3 curl'
            ;;
        macos)
            if have_cmd brew; then
                printf '\nInstall Python with: brew install python'
            else
                printf '\nInstall Python 3 from python.org or Homebrew.'
            fi
            ;;
        freebsd)
            printf '\nInstall dependencies with: sudo pkg install -y python3 curl'
            ;;
    esac
}


require_python() {
    if ! have_cmd python3; then
        die "python3 is required.$(dependency_hint)"
    fi
}


require_downloader() {
    if have_cmd curl || have_cmd wget || have_cmd fetch; then
        return
    fi

    die "Need curl, wget, or fetch to download files.$(dependency_hint)"
}


download_to() {
    url="$1"
    dest="$2"

    if have_cmd curl; then
        curl -fsSL "$url" -o "$dest"
        return
    fi

    if have_cmd wget; then
        wget -qO "$dest" "$url"
        return
    fi

    if have_cmd fetch; then
        fetch -q -o "$dest" "$url"
        return
    fi

    die "Need curl, wget, or fetch to download files.$(dependency_hint)"
}


download_text() {
    url="$1"

    if have_cmd curl; then
        curl -fsSL "$url"
        return
    fi

    if have_cmd wget; then
        wget -qO- "$url"
        return
    fi

    if have_cmd fetch; then
        fetch -q -o - "$url"
        return
    fi

    die "Need curl, wget, or fetch to fetch metadata.$(dependency_hint)"
}


script_dir() {
    case "$0" in
        */*)
            CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd -P
            ;;
        *)
            pwd -P
            ;;
    esac
}


detect_local_source() {
    self_dir="$(script_dir || true)"
    if [ -n "$self_dir" ] && [ -f "$self_dir/freqdisp" ]; then
        printf '%s\n' "$self_dir"
    fi
}


get_local_version() {
    source_dir="$1"

    if [ -d "$source_dir/.git" ] && have_cmd git; then
        git -C "$source_dir" describe --tags --always --dirty 2>/dev/null || true
        return
    fi

    printf 'local\n'
}


get_remote_ref() {
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


shell_single_quote() {
    value="$1"
    printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}


csh_double_quote() {
    value="$1"
    printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g'
}


path_bin_assignment() {
    default_bin_dir="$HOME/.local/bin"

    if [ "$BIN_DIR" = "$default_bin_dir" ]; then
        printf '%s' 'FREQDISP_BIN_DIR="$HOME/.local/bin"'
        return
    fi

    printf 'FREQDISP_BIN_DIR=%s' "$(shell_single_quote "$BIN_DIR")"
}


write_sh_path_block() {
    printf '%s\n' "$PATH_MARKER_BEGIN"
    printf '%s\n' "# Added by the freqdisp installer; remove this block if you manage PATH elsewhere."
    path_bin_assignment
    printf '\n'
    printf '%s\n' 'case ":$PATH:" in'
    printf '%s\n' '    *":$FREQDISP_BIN_DIR:"*) ;;'
    printf '%s\n' '    *) export PATH="$FREQDISP_BIN_DIR:$PATH" ;;'
    printf '%s\n' 'esac'
    printf '%s\n' 'unset FREQDISP_BIN_DIR'
    printf '%s\n' "$PATH_MARKER_END"
}


write_csh_path_block() {
    default_bin_dir="$HOME/.local/bin"

    printf '%s\n' "$PATH_MARKER_BEGIN"
    printf '%s\n' "# Added by the freqdisp installer; remove this block if you manage PATH elsewhere."
    if [ "$BIN_DIR" = "$default_bin_dir" ]; then
        printf '%s\n' 'set freqdisp_bin_dir = "$HOME/.local/bin"'
    else
        printf 'set freqdisp_bin_dir = "%s"\n' "$(csh_double_quote "$BIN_DIR")"
    fi
    printf '%s\n' 'if ( ":$PATH:" !~ *":$freqdisp_bin_dir:"* ) then'
    printf '%s\n' '    setenv PATH "$freqdisp_bin_dir":"$PATH"'
    printf '%s\n' 'endif'
    printf '%s\n' 'unset freqdisp_bin_dir'
    printf '%s\n' "$PATH_MARKER_END"
}


profile_has_path_entry() {
    profile="$1"
    default_home_expr="\$HOME/.local/bin"
    default_tilde_expr="~/.local/bin"

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
    profile="$1"
    syntax="$2"
    profile_dir="$(dirname "$profile")"

    mkdir -p "$profile_dir"
    touch "$profile"

    if profile_has_path_entry "$profile"; then
        log "PATH already configured in: $profile"
        return
    fi

    {
        printf '\n'
        case "$syntax" in
            csh)
                write_csh_path_block
                ;;
            *)
                write_sh_path_block
                ;;
        esac
    } >> "$profile"

    UPDATED_PATH_PROFILES="${UPDATED_PATH_PROFILES}${profile}
"
    log "Added $BIN_DIR to PATH in: $profile"
}


collect_path_profiles() {
    shell_name="${SHELL:-}"
    shell_name="${shell_name##*/}"

    case "$shell_name" in
        bash)
            ensure_profile_path "$HOME/.bashrc" sh
            ensure_profile_path "$HOME/.profile" sh
            ;;
        zsh)
            ensure_profile_path "$HOME/.zshrc" sh
            ensure_profile_path "$HOME/.zprofile" sh
            ;;
        csh|tcsh)
            ensure_profile_path "$HOME/.cshrc" csh
            ;;
        fish)
            log "Fish shell detected; install completed without editing fish config."
            log "Run directly with: $TARGET_LINK"
            ;;
        *)
            ensure_profile_path "$HOME/.profile" sh
            ;;
    esac
}


refresh_current_path() {
    case ":$PATH:" in
        *":$BIN_DIR:"*)
            log "Current PATH already includes: $BIN_DIR"
            ;;
        *)
            PATH="$BIN_DIR:$PATH"
            export PATH
            log "Installer PATH now includes: $BIN_DIR"
            ;;
    esac
}


ensure_user_path() {
    UPDATED_PATH_PROFILES=""

    if [ "${FREQDISP_SKIP_PATH_UPDATE:-}" = "1" ]; then
        log "Skipping PATH update because FREQDISP_SKIP_PATH_UPDATE=1"
        return
    fi

    collect_path_profiles
    refresh_current_path

    if [ -n "$UPDATED_PATH_PROFILES" ]; then
        log "New terminals will load the updated PATH automatically."
    fi
}


install_from_file() {
    source_file="$1"
    tmp_file="$(mktemp "$INSTALL_DIR/.freqdisp.XXXXXX")"

    if cp "$source_file" "$tmp_file"; then
        chmod 0755 "$tmp_file"
        mv "$tmp_file" "$TARGET_SCRIPT"
        return
    fi

    rm -f "$tmp_file"
    die "Failed to install $source_file"
}


install_from_url() {
    source_url="$1"
    tmp_file="$(mktemp "$INSTALL_DIR/.freqdisp.XXXXXX")"

    if download_to "$source_url" "$tmp_file"; then
        chmod 0755 "$tmp_file"
        mv "$tmp_file" "$TARGET_SCRIPT"
        return
    fi

    rm -f "$tmp_file"
    die "Failed to download $source_url"
}


write_version() {
    version="$1"
    tmp_file="$(mktemp "$INSTALL_DIR/.VERSION.XXXXXX")"

    if printf '%s\n' "$version" > "$tmp_file"; then
        mv "$tmp_file" "$TARGET_VERSION"
        return
    fi

    rm -f "$tmp_file"
    die "Failed to write $TARGET_VERSION"
}


create_launcher() {
    if { [ -e "$TARGET_LINK" ] || [ -L "$TARGET_LINK" ]; } &&
        [ ! -L "$TARGET_LINK" ] &&
        [ ! -f "$TARGET_LINK" ]; then
        die "Refusing to replace non-file launcher path: $TARGET_LINK"
    fi

    rm -f "$TARGET_LINK"
    ln -s "$TARGET_SCRIPT" "$TARGET_LINK"
}


main() {
    detect_os
    log "Detected target: $OS_NAME/$OS_FAMILY"
    case "$OS_FAMILY" in
        pve|debian|fedora|macos|freebsd|linux)
            ;;
        *)
            log "Unsupported OS detected; installing anyway with generic settings."
            ;;
    esac

    require_python

    mkdir -p "$INSTALL_DIR" "$BIN_DIR"
    local_source="$(detect_local_source || true)"

    if [ -n "$local_source" ]; then
        install_from_file "$local_source/freqdisp"
        version="$(get_local_version "$local_source")"
        log "Installed from local checkout: $local_source"
    else
        require_downloader
        ref="$(get_remote_ref)"
        source_url="https://raw.githubusercontent.com/$REPO_SLUG/$ref/freqdisp"
        install_from_url "$source_url"
        version="$ref"
        log "Downloaded ref: $ref"
    fi

    write_version "$version"
    create_launcher
    ensure_user_path

    log "Installed script: $TARGET_SCRIPT"
    log "Launcher: $TARGET_LINK"
    log "Config file: $INSTALL_DIR/.freqdisp.json"
    log "Version: $version"
    log "Run now: $TARGET_LINK"
    log "Run from PATH: $APP_NAME"
}


main "$@"
