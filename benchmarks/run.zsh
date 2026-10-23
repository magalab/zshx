#!/usr/bin/env zsh

emulate -L zsh
setopt extendedglob multibyte

typeset -g ZSHX_HIGHLIGHTING=1
typeset -g ZSHX_AUTOSUGGEST=0
source "${${(%):-%N}:A:h:h}/lib/config.zsh" || exit 1
source "${${(%):-%N}:A:h:h}/lib/highlighting.zsh" || exit 1
zmodload zsh/datetime || exit 1

local -i samples=${1:-101} length index
local -F 9 started finished elapsed
local buffer scratch
local -a lengths=(40 160 512 1024 1600)

print -r -- "zsh=${ZSH_VERSION}; platform=$(uname -sm); samples=$samples; statistic=tokenizer-microseconds"

for length in $lengths; do
  buffer=''
  while (( ${#buffer} < length )); do
    buffer+="echo \$HOME/file.txt | grep --long-option value; "
  done
  buffer=${buffer[1,length]}
  scratch=$(mktemp) || exit 1
  for (( index = 0; index < samples; ++index )); do
    started=$EPOCHREALTIME
    _zshx_lex_buffer "$buffer"
    finished=$EPOCHREALTIME
    elapsed=$(( (finished - started) * 1000000.0 ))
    print -r -- "$elapsed" >> "$scratch"
  done
  print -r -- "buffer=${length} chars (${samples} samples), tokenizer time in microseconds"
  sort -n "$scratch" | awk -v n="$samples" 'NR == int((n + 1) * 0.50) { p50=$1 } NR == int((n + 1) * 0.95) { p95=$1 } END { printf "  p50=%.1f p95=%.1f\n", p50, p95 }'
  command rm -f -- "$scratch"
done
