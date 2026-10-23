#!/usr/bin/env zsh

emulate -L zsh
setopt extendedglob multibyte

typeset -g _ZSHX_TEST_ROOT="${${(%):-%N}:A:h:h}"
source "$_ZSHX_TEST_ROOT/lib/config.zsh" || exit 1
source "$_ZSHX_TEST_ROOT/lib/highlighting.zsh" || exit 1
source "$_ZSHX_TEST_ROOT/lib/autosuggest.zsh" || exit 1
zmodload zsh/parameter || exit 1

typeset -gi _ZSHX_TEST_ASSERTIONS=0

_zshx_test_contains() {
  local haystack=$1 needle=$2 label=$3
  (( ++_ZSHX_TEST_ASSERTIONS ))
  if [[ $haystack != *"$needle"* ]]; then
    print -u2 -r -- "FAIL: $label (missing ${(qqq)needle})"
    print -u2 -r -- "  got: $haystack"
    return 1
  fi
}

_zshx_test_not_contains() {
  local haystack=$1 needle=$2 label=$3
  (( ++_ZSHX_TEST_ASSERTIONS ))
  if [[ $haystack == *"$needle"* ]]; then
    print -u2 -r -- "FAIL: $label (unexpected ${(qqq)needle})"
    return 1
  fi
}

_zshx_lex_buffer 'git status --short'
local regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" '0 3 fg=green memo=zshx-syntax' 'command token' || exit 1
_zshx_test_contains "$regions" '11 18 fg=cyan memo=zshx-syntax' 'option token' || exit 1

_zshx_lex_buffer 'zshx-command-that-does-not-exist-9f2c'
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" 'fg=red,bold memo=zshx-syntax' 'unknown command' || exit 1

_zshx_lex_buffer 'echo /tmp'
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" '5 9 fg=blue,underline memo=zshx-syntax' 'existing absolute path' || exit 1

_zshx_lex_buffer 'FOO=1 git --version'
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" '0 5 fg=cyan memo=zshx-syntax' 'assignment token' || exit 1
_zshx_test_contains "$regions" '6 9 fg=green memo=zshx-syntax' 'command after assignment' || exit 1

_zshx_lex_buffer 'if [[ -f README.md && "$HOME" == /tmp ]]; then echo ok; fi'
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" 'fg=yellow,bold memo=zshx-syntax' 'reserved words' || exit 1
_zshx_test_contains "$regions" 'fg=magenta memo=zshx-syntax' 'variable expansion' || exit 1
_zshx_test_contains "$regions" 'fg=white,bold memo=zshx-syntax' 'conditional operators' || exit 1
_zshx_test_not_contains "$regions" 'fg=red,bold memo=zshx-syntax' 'condition operands are not commands' || exit 1

_zshx_lex_buffer 'echo x | grep x 2>output'
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" 'fg=white,bold memo=zshx-syntax' 'pipeline and redirection operators' || exit 1
_zshx_test_contains "$regions" 'fg=blue,underline memo=zshx-syntax' 'redirection target' || exit 1
_zshx_test_not_contains "$regions" 'fg=red,bold memo=zshx-syntax' 'file descriptor before redirection' || exit 1

_zshx_lex_buffer $'echo "$HOME" $(git status)'
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" 'fg=green memo=zshx-syntax' 'quoted text' || exit 1
_zshx_test_contains "$regions" 'fg=magenta memo=zshx-syntax' 'variable and substitution' || exit 1

_zshx_lex_buffer "echo 'unfinished"
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" 'fg=red,underline memo=zshx-syntax' 'unclosed quote error' || exit 1

setopt interactivecomments
_zshx_lex_buffer 'echo ok # comment'
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" 'fg=8 memo=zshx-syntax' 'interactive comment' || exit 1

_zshx_lex_buffer "echo '猫'"
regions="${(j:\n:)_ZSHX_LEX_HIGHLIGHTS}"
_zshx_test_contains "$regions" '5 8 fg=green memo=zshx-syntax' 'UTF-8 character offsets' || exit 1

HISTSIZE=1000
print -s -- 'zshx-history-key [literal] suggestion tail'
_zshx_history_find 'zshx-history-key [literal]'
(( $? == 0 )) || { print -u2 -r -- 'FAIL: history strategy did not find a prefix'; exit 1; }
_zshx_test_contains "$_ZSHX_FOUND_SUGGESTION" 'zshx-history-key [literal] suggestion tail' 'history prefix matching is literal' || exit 1

_zshx_store_suggestion 'zshx-history-key' 'zshx-history-key suggestion'
BUFFER='zshx-history-key'
CURSOR=${#BUFFER}
KEYMAP=emacs
_zshx_set_postdisplay
(( $? == 0 )) || { print -u2 -r -- 'FAIL: POSTDISPLAY suffix calculation'; exit 1; }
_zshx_test_contains "$POSTDISPLAY" 'suggestion' 'suggestion suffix calculation' || exit 1

print -r -- "unit: $_ZSHX_TEST_ASSERTIONS assertions passed"

