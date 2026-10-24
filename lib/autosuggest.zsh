typeset -g _ZSHX_SUGGESTION_BUFFER
typeset -g _ZSHX_SUGGESTION_TEXT
typeset -g _ZSHX_REQUEST_BUFFER
typeset -g _ZSHX_REQUEST_ID
typeset -g _ZSHX_ASYNC_PID
typeset -gi _ZSHX_REQUEST_SERIAL=0
typeset -gi _ZSHX_ASYNC_FD=-1

_zshx_history_find() {
  emulate -L zsh
  setopt multibyte
  zmodload zsh/parameter 2>/dev/null || return 1

  local query=$1 candidate
  local -i query_length=${#1} event=${HISTCMD:-0} scanned=0
  local -i scan_limit=${2:-${ZSHX_SUGGEST_HISTORY_LIMIT:-2000}}
  typeset -g _ZSHX_FOUND_SUGGESTION=''

  (( scan_limit > ZSHX_SUGGEST_HISTORY_LIMIT )) && scan_limit=$ZSHX_SUGGEST_HISTORY_LIMIT

  while (( event > 0 && scanned < scan_limit )); do
    candidate=${history[$event]-}
    if (( ${#candidate} > query_length )) && [[ ${candidate[1,$query_length]} == "$query" ]]; then
      _ZSHX_FOUND_SUGGESTION=$candidate
      return 0
    fi
    (( event--, scanned++ ))
  done
  return 1
}

_zshx_cursor_at_buffer_end() {
  if [[ $KEYMAP == vicmd ]]; then
    (( CURSOR == ${#BUFFER} - 1 ))
  else
    (( CURSOR == ${#BUFFER} ))
  fi
}

_zshx_close_async_request() {
  local fd=$_ZSHX_ASYNC_FD pid=$_ZSHX_ASYNC_PID

  if (( fd >= 0 )); then
    zle -F "$fd" 2>/dev/null
    exec {fd}<&-
  fi
  if [[ $pid == <-> ]] && (( pid > 0 )); then
    kill -TERM "$pid" 2>/dev/null
  fi

  _ZSHX_ASYNC_FD=-1
  _ZSHX_ASYNC_PID=''
  _ZSHX_REQUEST_BUFFER=''
}

_zshx_async_worker() {
  zmodload zsh/system 2>/dev/null || return 1
  print -r -- "$sysparams[pid]"
  _zshx_history_find "$2"
  print -r -n -- "$1"$'\n'
  print -r -n -- "$_ZSHX_FOUND_SUGGESTION"$'\0'
}

_zshx_async_request() {
  local query=$1 request_id
  _zshx_close_async_request
  (( ++_ZSHX_REQUEST_SERIAL ))
  request_id=$_ZSHX_REQUEST_SERIAL
  _ZSHX_REQUEST_ID=$request_id
  _ZSHX_REQUEST_BUFFER=$query

  zmodload zsh/system 2>/dev/null || return 1
  builtin exec {_ZSHX_ASYNC_FD}< <(_zshx_async_worker "$request_id" "$query")
  if ! read -r _ZSHX_ASYNC_PID <&$_ZSHX_ASYNC_FD; then
    _zshx_close_async_request
    return 1
  fi
  zle -F "$_ZSHX_ASYNC_FD" _zshx_async_response || {
    _zshx_close_async_request
    return 1
  }
}

_zshx_async_response() {
  emulate -L zsh
  local fd=$1 response_id='' suggestion=''
  local expected_id=$_ZSHX_REQUEST_ID expected_buffer=$_ZSHX_REQUEST_BUFFER
  local -i was_current=0

  [[ -n ${2-} && ${2-} != hup ]] && {
    zle -F "$fd" 2>/dev/null
    exec {fd}<&-
    (( fd == _ZSHX_ASYNC_FD )) && {
      _ZSHX_ASYNC_FD=-1
      _ZSHX_ASYNC_PID=''
      zle _zshx-async-result -- "$expected_id" "$expected_buffer" ''
    }
    return 0
  }

  IFS= read -r -u "$fd" response_id
  IFS= read -r -d '' -u "$fd" suggestion
  (( fd == _ZSHX_ASYNC_FD )) && was_current=1
  zle -F "$fd" 2>/dev/null
  exec {fd}<&-
  if (( was_current )); then
    _ZSHX_ASYNC_FD=-1
    _ZSHX_ASYNC_PID=''
    zle _zshx-async-result -- "$response_id" "$expected_buffer" "$suggestion"
  fi
  return 0
}

_zshx_async_result_widget() {
  true
  local response_id=$1 expected_buffer=$2 suggestion=$3
  if [[ $response_id == $_ZSHX_REQUEST_ID && $BUFFER == $expected_buffer && $ZSHX_AUTOSUGGEST == 1 ]] && _zshx_cursor_at_buffer_end; then
    _zshx_store_suggestion "$BUFFER" "$suggestion"
  fi
  _ZSHX_REQUEST_BUFFER=''
  zle -R
}

_zshx_store_suggestion() {
  local query=$1 suggestion=$2
  local -i query_length=${#1}
  _ZSHX_SUGGESTION_BUFFER=$query
  _ZSHX_SUGGESTION_TEXT=''

  if (( ${#suggestion} >= query_length )) && [[ ${suggestion[1,$query_length]} == "$query" ]]; then
    _ZSHX_SUGGESTION_TEXT=$suggestion
  fi
}

_zshx_set_postdisplay() {
  local suggestion=$_ZSHX_SUGGESTION_TEXT
  local -i buffer_length=${#BUFFER} start=$(( ${#BUFFER} + 1 )) end=${#_ZSHX_SUGGESTION_TEXT}
  POSTDISPLAY=''
  _zshx_cursor_at_buffer_end || return 0
  (( ${#suggestion} > buffer_length )) || return 0
  [[ ${suggestion[1,buffer_length]} == "$BUFFER" ]] || return 0
  POSTDISPLAY=${suggestion[$start,$end]}
}

_zshx_update_suggestion() {
  local strategy
  local -i use_history=0

  if [[ $ZSHX_AUTOSUGGEST != 1 ]]; then
    POSTDISPLAY=''
    _zshx_close_async_request
    return 0
  fi

  if (( ${#BUFFER} == 0 || ${#BUFFER} > ZSHX_BUFFER_MAX_SIZE )) || ! _zshx_cursor_at_buffer_end; then
    POSTDISPLAY=''
    if [[ $_ZSHX_REQUEST_BUFFER != $BUFFER ]]; then
      _zshx_close_async_request
    fi
    return 0
  fi

  for strategy in "${ZSHX_SUGGEST_STRATEGY[@]}"; do
    [[ $strategy == history ]] && use_history=1
  done
  if (( ! use_history )); then
    POSTDISPLAY=''
    _zshx_close_async_request
    return 0
  fi

  if [[ $_ZSHX_SUGGESTION_BUFFER == $BUFFER ]]; then
    _zshx_set_postdisplay
    return 0
  fi

  if [[ -n $_ZSHX_SUGGESTION_TEXT && $BUFFER == $_ZSHX_SUGGESTION_BUFFER* && $_ZSHX_SUGGESTION_TEXT == $BUFFER* ]]; then
    _ZSHX_SUGGESTION_BUFFER=$BUFFER
    _zshx_set_postdisplay
    return 0
  fi

  POSTDISPLAY=''
  [[ $_ZSHX_REQUEST_BUFFER == $BUFFER ]] && return 0

  if [[ $ZSHX_SUGGEST_ASYNC == 1 ]]; then
    _zshx_close_async_request
    if _zshx_history_find "$BUFFER" 100; then
      _zshx_store_suggestion "$BUFFER" "$_ZSHX_FOUND_SUGGESTION"
      _zshx_set_postdisplay
      return 0
    fi
    _zshx_async_request "$BUFFER"
  else
    _zshx_history_find "$BUFFER"
    _zshx_store_suggestion "$BUFFER" "$_ZSHX_FOUND_SUGGESTION"
    _zshx_set_postdisplay
  fi
}

_zshx_clear_suggestion_state() {
  POSTDISPLAY=''
  _zshx_close_async_request
  _ZSHX_SUGGESTION_BUFFER=''
  _ZSHX_SUGGESTION_TEXT=''
}

