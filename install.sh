#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./install.sh [--no-rc]

Copies zshx to ~/.zsh/plugins/zshx and adds a source line to the active
ZDOTDIR's .zshrc (or ~/.zshrc). Set ZSHX_INSTALL_DIR and ZSHX_RC_FILE to
override those paths. Use --no-rc to install files without editing .zshrc.
EOF
}

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
install_dir=${ZSHX_INSTALL_DIR:-${HOME:?HOME must be set}/.zsh/plugins/zshx}
rc_file=${ZSHX_RC_FILE:-${ZDOTDIR:-$HOME}/.zshrc}
zsh_bin=${ZSH_BIN:-zsh}
update_rc=1

while [ "$#" -gt 0 ]; do
  case $1 in
    --no-rc)
      update_rc=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'zshx installer: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ ! -f "$script_dir/zshx.plugin.zsh" ] || [ ! -f "$script_dir/zshx.zsh" ] || [ ! -d "$script_dir/lib" ]; then
  printf 'zshx installer: run this script from a complete zshx source directory\n' >&2
  exit 1
fi

if ! command -v "$zsh_bin" >/dev/null 2>&1; then
  printf 'zshx installer: zsh 5.9 or newer is required but executable was not found: %s\n' "$zsh_bin" >&2
  exit 1
fi
if ! "$zsh_bin" -fc 'autoload -Uz is-at-least && is-at-least 5.9 "$ZSH_VERSION"' >/dev/null 2>&1; then
  zsh_version=$("$zsh_bin" --version 2>/dev/null | awk '{print $2}')
  printf 'zshx installer: zsh 5.9 or newer is required (found %s)\n' "${zsh_version:-unknown}" >&2
  exit 1
fi

case $install_dir in
  *'"'*|*'$'*|*'`'*|*'\'*)
    printf 'zshx installer: install path cannot contain double quotes, $, backticks, or backslashes\n' >&2
    exit 1
    ;;
esac

mkdir -p "$install_dir/lib"
install_dir=$(CDPATH= cd "$install_dir" && pwd)
cp "$script_dir/zshx.plugin.zsh" "$script_dir/zshx.zsh" "$install_dir/"
cp "$script_dir"/lib/*.zsh "$install_dir/lib/"

source_line="source \"$install_dir/zshx.plugin.zsh\""
if [ "$update_rc" -eq 1 ]; then
  if [ -f "$rc_file" ] && grep -F -x "$source_line" "$rc_file" >/dev/null 2>&1; then
    printf 'zshx: already configured in %s\n' "$rc_file"
  else
    rc_dir=$(dirname "$rc_file")
    mkdir -p "$rc_dir"
    if [ -f "$rc_file" ]; then
      printf '\n# zshx\n%s\n' "$source_line" >> "$rc_file"
    else
      printf '# zshx\n%s\n' "$source_line" > "$rc_file"
    fi
    printf 'zshx: added source line to %s\n' "$rc_file"
  fi
fi

printf 'zshx: installed in %s\n' "$install_dir"
if [ "$update_rc" -eq 0 ]; then
  printf 'Add this to your .zshrc to enable it:\n%s\n' "$source_line"
fi
