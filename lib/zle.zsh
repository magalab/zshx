typeset -gA _ZSHX_WIDGET_ACTIONS
typeset -gA _ZSHX_WIDGET_ORIGINAL_TYPE
typeset -gA _ZSHX_WIDGET_ORIGINAL_FUNCTION
typeset -gi _ZSHX_IN_ISEARCH=0

_zshx_invoke_original_widget() {
  local widget=$1 function_name
  shift

  case ${_ZSHX_WIDGET_ORIGINAL_TYPE[$widget]-} in
    builtin) zle ".$widget" "$@" ;;
    user)
      function_name=${_ZSHX_WIDGET_ORIGINAL_FUNCTION[$widget]-}
      [[ -n $function_name ]] || return 0
      "$function_name" "$@"
      ;;
    *) return 0 ;;
  esac
}

_zshx_install_widget() {
  local widget=$1 action=$2 implementation
  [[ -n $widget && $widget != *[[:space:]]* ]] || return 1
  implementation=${widgets[$widget]-}
  [[ -n $implementation ]] || return 0
  [[ $implementation == user:_zshx_widget_dispatch ]] && return 0

  case $implementation in
    builtin)
      _ZSHX_WIDGET_ORIGINAL_TYPE[$widget]=builtin
      _ZSHX_WIDGET_ORIGINAL_FUNCTION[$widget]=''
      ;;
    user:*)
      _ZSHX_WIDGET_ORIGINAL_TYPE[$widget]=user
      _ZSHX_WIDGET_ORIGINAL_FUNCTION[$widget]=${implementation#user:}
      ;;
    *) return 0 ;;
  esac

  _ZSHX_WIDGET_ACTIONS[$widget]=$action
  zle -N -- "$widget" _zshx_widget_dispatch
}

_zshx_install_widgets() {
  zmodload zsh/zleparameter 2>/dev/null || return 1

  local widget
  for widget in "${ZSHX_ACCEPT_WIDGETS[@]}"; do
    _zshx_install_widget "$widget" accept || return 1
  done
  for widget in "${ZSHX_PARTIAL_ACCEPT_WIDGETS[@]}"; do
    if [[ -n ${_ZSHX_WIDGET_ACTIONS[$widget]-} ]]; then
      print -u2 -r -- "zshx: widget '$widget' appears in both accept lists; keeping full acceptance"
      continue
    fi
    _zshx_install_widget "$widget" partial || return 1
  done
  _zshx_install_widget accept-line clear || return 1

  zle -N zshx-accept-suggestion _zshx_accept_suggestion_widget
  zle -N zshx-accept-suggestion-word _zshx_accept_suggestion_word_widget
  zle -N zshx-clear-suggestion _zshx_clear_suggestion_widget
  zle -N zshx-disable-autosuggest _zshx_disable_autosuggest_widget
  zle -N zshx-enable-autosuggest _zshx_enable_autosuggest_widget
  zle -N zshx-toggle-autosuggest _zshx_toggle_autosuggest_widget
  zle -N _zshx-async-result _zshx_async_result_widget
}

_zshx_accept_full() {
  local widget=$1
  shift

  if [[ -z $POSTDISPLAY && $_ZSHX_SUGGESTION_BUFFER == $BUFFER ]] && _zshx_cursor_at_buffer_end; then
    _zshx_set_postdisplay
  fi
  if [[ -z $POSTDISPLAY ]] || ! _zshx_cursor_at_buffer_end; then
    [[ -n $widget ]] && _zshx_invoke_original_widget "$widget" "$@"
    return $?
  fi

  local -i original_length=${#BUFFER} retval=0
  BUFFER+=$POSTDISPLAY
  POSTDISPLAY=''
  _zshx_close_async_request
  _ZSHX_SUGGESTION_BUFFER=''
  _ZSHX_SUGGESTION_TEXT=''
  if [[ $KEYMAP == vicmd ]]; then
    CURSOR=$((original_length - 1))
  else
    CURSOR=$original_length
  fi

  if [[ -n $widget ]]; then
    _zshx_invoke_original_widget "$widget" "$@"
    retval=$?
  fi

  if [[ $KEYMAP == vicmd ]]; then
    CURSOR=$((${#BUFFER} - 1))
  else
    CURSOR=${#BUFFER}
  fi
  return $retval
}

_zshx_accept_partial() {
  local widget=$1
  shift

  if [[ -z $POSTDISPLAY && $_ZSHX_SUGGESTION_BUFFER == $BUFFER ]] && _zshx_cursor_at_buffer_end; then
    _zshx_set_postdisplay
  fi
  if [[ -z $POSTDISPLAY ]] || ! _zshx_cursor_at_buffer_end; then
    _zshx_invoke_original_widget "$widget" "$@"
    return $?
  fi

  local original_buffer=$BUFFER original_postdisplay=$POSTDISPLAY combined_buffer
  local -i original_length=${#BUFFER} cursor_location retval=0
  BUFFER+=$POSTDISPLAY
  POSTDISPLAY=''
  _zshx_invoke_original_widget "$widget" "$@"
  retval=$?

  cursor_location=$CURSOR
  [[ $KEYMAP == vicmd ]] && (( cursor_location++ ))
  if (( cursor_location > original_length )); then
    combined_buffer=$BUFFER
    BUFFER=${combined_buffer[1,$cursor_location]}
    POSTDISPLAY=${combined_buffer[$((cursor_location + 1)),$#combined_buffer]}
    _ZSHX_SUGGESTION_BUFFER=$BUFFER
    _ZSHX_SUGGESTION_TEXT=$combined_buffer
    _zshx_close_async_request
    if [[ $KEYMAP == vicmd ]]; then
      CURSOR=$((cursor_location - 1))
    else
      CURSOR=$cursor_location
    fi
  else
    BUFFER=$original_buffer
    POSTDISPLAY=$original_postdisplay
  fi
  return $retval
}

_zshx_widget_dispatch() {
  true
  local widget=$WIDGET action=${_ZSHX_WIDGET_ACTIONS[$WIDGET]-}

  case $action in
    accept) _zshx_accept_full "$widget" "$@"; return $? ;;
    partial) _zshx_accept_partial "$widget" "$@"; return $? ;;
    clear)
      POSTDISPLAY=''
      _zshx_close_async_request
      _zshx_invoke_original_widget "$widget" "$@"
      return $?
      ;;
  esac

  _zshx_invoke_original_widget "$widget" "$@"
}

_zshx_accept_suggestion_widget() {
  true
  _zshx_accept_full '' "$@"
}

_zshx_accept_suggestion_word_widget() {
  true
  local widget=forward-word
  [[ $KEYMAP == vicmd || $KEYMAP == viins ]] && widget=vi-forward-word
  [[ -n ${_ZSHX_WIDGET_ACTIONS[$widget]-} ]] || widget=forward-word
  _zshx_accept_partial "$widget" "$@"
}

_zshx_clear_suggestion_widget() {
  true
  POSTDISPLAY=''
  _zshx_close_async_request
  _ZSHX_SUGGESTION_BUFFER=$BUFFER
  _ZSHX_SUGGESTION_TEXT=''
}

_zshx_disable_autosuggest_widget() {
  true
  ZSHX_AUTOSUGGEST=0
  _zshx_clear_suggestion_state
}

_zshx_enable_autosuggest_widget() {
  true
  ZSHX_AUTOSUGGEST=1
  _ZSHX_SUGGESTION_BUFFER=''
  _ZSHX_SUGGESTION_TEXT=''
}

_zshx_toggle_autosuggest_widget() {
  true
  if [[ $ZSHX_AUTOSUGGEST == 1 ]]; then
    _zshx_disable_autosuggest_widget
  else
    _zshx_enable_autosuggest_widget
  fi
}

_zshx_pre_redraw() {
  true
  local region

  if (( _ZSHX_IN_ISEARCH )); then
    region_highlight=("${(@)region_highlight:#*memo=zshx-syntax}")
    region_highlight=("${(@)region_highlight:#*memo=zshx-suggestion}")
    POSTDISPLAY=''
    return 0
  fi

  region_highlight=("${(@)region_highlight:#*memo=zshx-syntax}")
  region_highlight=("${(@)region_highlight:#*memo=zshx-suggestion}")
  _zshx_apply_syntax_highlights || true
  _zshx_update_suggestion || true

  if [[ -n $POSTDISPLAY && -n $ZSHX_SUGGEST_HIGHLIGHT_STYLE && $ZSHX_SUGGEST_HIGHLIGHT_STYLE != none ]]; then
    region_highlight+=("${#BUFFER} $((${#BUFFER} + ${#POSTDISPLAY})) $ZSHX_SUGGEST_HIGHLIGHT_STYLE memo=zshx-suggestion")
  fi
  return 0
}

_zshx_line_init() {
  true
  _zshx_clear_suggestion_state
  _ZSHX_CACHED_BUFFER=''
  region_highlight=("${(@)region_highlight:#*memo=zshx-syntax}")
  region_highlight=("${(@)region_highlight:#*memo=zshx-suggestion}")
  return 0
}

_zshx_line_finish() {
  true
  _zshx_clear_suggestion_state
  _ZSHX_CACHED_BUFFER=''
  region_highlight=("${(@)region_highlight:#*memo=zshx-syntax}")
  region_highlight=("${(@)region_highlight:#*memo=zshx-suggestion}")
  return 0
}

_zshx_history_line_set() {
  true
  _zshx_clear_suggestion_state
  _ZSHX_CACHED_BUFFER=''
  return 0
}

_zshx_isearch_update() {
  true
  _ZSHX_IN_ISEARCH=1
  POSTDISPLAY=''
  region_highlight=("${(@)region_highlight:#*memo=zshx-syntax}")
  region_highlight=("${(@)region_highlight:#*memo=zshx-suggestion}")
  return 0
}

_zshx_isearch_exit() {
  true
  _ZSHX_IN_ISEARCH=0
  _ZSHX_CACHED_BUFFER=''
  return 0
}

_zshx_register_hooks() {
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget zle-line-pre-redraw _zshx_pre_redraw || return 1
  add-zle-hook-widget zle-line-init _zshx_line_init || return 1
  add-zle-hook-widget zle-line-finish _zshx_line_finish || return 1
  add-zle-hook-widget zle-history-line-set _zshx_history_line_set || return 1
  add-zle-hook-widget zle-isearch-update _zshx_isearch_update || return 1
  add-zle-hook-widget zle-isearch-exit _zshx_isearch_exit || return 1
}

zshx-unload() {
  local widget
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget -d zle-line-pre-redraw _zshx_pre_redraw 2>/dev/null
  add-zle-hook-widget -d zle-line-init _zshx_line_init 2>/dev/null
  add-zle-hook-widget -d zle-line-finish _zshx_line_finish 2>/dev/null
  add-zle-hook-widget -d zle-history-line-set _zshx_history_line_set 2>/dev/null
  add-zle-hook-widget -d zle-isearch-update _zshx_isearch_update 2>/dev/null
  add-zle-hook-widget -d zle-isearch-exit _zshx_isearch_exit 2>/dev/null

  _zshx_close_async_request
  for widget in "${(@k)_ZSHX_WIDGET_ACTIONS}"; do
    [[ ${widgets[$widget]-} == user:_zshx_widget_dispatch ]] || continue
    if [[ ${_ZSHX_WIDGET_ORIGINAL_TYPE[$widget]} == builtin ]]; then
      zle -A ".$widget" "$widget" 2>/dev/null
    else
      zle -N "$widget" "${_ZSHX_WIDGET_ORIGINAL_FUNCTION[$widget]}" 2>/dev/null
    fi
  done
  for widget in zshx-accept-suggestion zshx-accept-suggestion-word zshx-clear-suggestion \
    zshx-disable-autosuggest zshx-enable-autosuggest zshx-toggle-autosuggest _zshx-async-result; do
    zle -D "$widget" 2>/dev/null
  done

  unset _ZSHX_LOADED _ZSHX_WIDGET_ACTIONS _ZSHX_WIDGET_ORIGINAL_TYPE _ZSHX_WIDGET_ORIGINAL_FUNCTION
  unset _ZSHX_SUGGESTION_BUFFER _ZSHX_SUGGESTION_TEXT _ZSHX_REQUEST_BUFFER _ZSHX_REQUEST_ID
  unset _ZSHX_ASYNC_PID _ZSHX_REQUEST_SERIAL _ZSHX_ASYNC_FD
  unset _ZSHX_CACHED_BUFFER _ZSHX_CACHED_HIGHLIGHTS _ZSHX_LEX_HIGHLIGHTS _ZSHX_IN_ISEARCH
  unset ZSHX_PLUGIN_DIR
  unfunction _zshx_invoke_original_widget _zshx_install_widget _zshx_install_widgets \
    _zshx_accept_full _zshx_accept_partial _zshx_widget_dispatch \
    _zshx_accept_suggestion_widget _zshx_accept_suggestion_word_widget \
    _zshx_clear_suggestion_widget _zshx_disable_autosuggest_widget \
    _zshx_enable_autosuggest_widget _zshx_toggle_autosuggest_widget \
    _zshx_async_result_widget \
    _zshx_pre_redraw _zshx_line_init _zshx_line_finish _zshx_history_line_set \
    _zshx_isearch_update _zshx_isearch_exit _zshx_register_hooks \
    _zshx_apply_syntax_highlights _zshx_lex_buffer _zshx_emit_range \
    _zshx_variable_end _zshx_substitution_end _zshx_history_find \
    _zshx_cursor_at_buffer_end _zshx_close_async_request _zshx_async_worker \
    _zshx_async_request _zshx_async_response _zshx_store_suggestion \
    _zshx_set_postdisplay _zshx_update_suggestion _zshx_clear_suggestion_state 2>/dev/null
  unfunction zshx-enable-highlighting zshx-disable-highlighting \
    zshx-enable-autosuggest zshx-disable-autosuggest 2>/dev/null
}

