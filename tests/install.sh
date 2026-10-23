#!/bin/sh
set -eu

root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/zshx-install-test.XXXXXX")
cleanup() {
  rm -rf "$tmp"
}
trap cleanup 0 HUP INT TERM

install_dir="$tmp/plugin files/zshx"
rc_file="$tmp/config/.zshrc"

ZSHX_INSTALL_DIR="$install_dir" ZSHX_RC_FILE="$rc_file" "$root/install.sh" >/dev/null
install_dir=$(CDPATH= cd "$install_dir" && pwd)
source_line="source \"$install_dir/zshx.plugin.zsh\""
test_zsh=${ZSH_BIN:-zsh}
[ -f "$install_dir/zshx.plugin.zsh" ] || exit 1
[ -f "$install_dir/zshx.zsh" ] || exit 1
[ -f "$install_dir/lib/zle.zsh" ] || exit 1
"$test_zsh" -fc 'source "$1" && [[ $_ZSHX_LOADED == 1 ]]' zsh "$install_dir/zshx.plugin.zsh"
grep -F -x "$source_line" "$rc_file" >/dev/null

ZSHX_INSTALL_DIR="$install_dir" ZSHX_RC_FILE="$rc_file" "$root/install.sh" >/dev/null
line_count=$(grep -F -x "$source_line" "$rc_file" | wc -l | tr -d ' ')
[ "$line_count" -eq 1 ] || {
  printf 'installer added %s source lines on a repeated run\n' "$line_count" >&2
  exit 1
}

no_rc_dir="$tmp/no-rc/plugin"
no_rc_file="$tmp/no-rc/config/.zshrc"
ZSHX_INSTALL_DIR="$no_rc_dir" ZSHX_RC_FILE="$no_rc_file" "$root/install.sh" --no-rc >/dev/null
[ -f "$no_rc_dir/zshx.plugin.zsh" ] || exit 1
[ ! -e "$no_rc_file" ] || {
  printf 'installer changed .zshrc despite --no-rc\n' >&2
  exit 1
}

printf 'installer: copy, idempotence, custom paths, and --no-rc passed\n'
