if (( ${+_ZSHX_LOADED} )); then
  return 0
fi

autoload -Uz is-at-least
if ! is-at-least 5.9 "$ZSH_VERSION"; then
  print -u2 -r -- "zshx: zsh 5.9 or newer is required (found $ZSH_VERSION)"
  return 1
fi

typeset -g ZSHX_PLUGIN_DIR="${${(%):-%N}:A:h}"
source "$ZSHX_PLUGIN_DIR/lib/config.zsh" || return 1
source "$ZSHX_PLUGIN_DIR/lib/highlighting.zsh" || return 1
source "$ZSHX_PLUGIN_DIR/lib/autosuggest.zsh" || return 1
source "$ZSHX_PLUGIN_DIR/lib/zle.zsh" || return 1

zshx-enable-highlighting() {
  ZSHX_HIGHLIGHTING=1
  _ZSHX_CACHED_BUFFER=''
}

zshx-disable-highlighting() {
  ZSHX_HIGHLIGHTING=0
  _ZSHX_CACHED_BUFFER=''
}

zshx-enable-autosuggest() {
  ZSHX_AUTOSUGGEST=1
  _ZSHX_SUGGESTION_BUFFER=''
  _ZSHX_SUGGESTION_TEXT=''
}

zshx-disable-autosuggest() {
  ZSHX_AUTOSUGGEST=0
  _zshx_clear_suggestion_state
}

if [[ -o interactive && -o zle ]]; then
  if ! zmodload zsh/parameter zsh/zleparameter zsh/system 2>/dev/null; then
    print -u2 -r -- 'zshx: required zsh modules could not be loaded; plugin was not initialized'
    return 1
  fi

  autoload -Uz add-zle-hook-widget
  if ! (( ${+functions[add-zle-hook-widget]} )); then
    print -u2 -r -- 'zshx: add-zle-hook-widget is unavailable; plugin was not initialized'
    return 1
  fi

  if ! _zshx_install_widgets || ! _zshx_register_hooks; then
    print -u2 -r -- 'zshx: could not register ZLE widgets or hooks; plugin was not initialized'
    zshx-unload
    return 1
  fi
fi

typeset -g _ZSHX_LOADED=1

