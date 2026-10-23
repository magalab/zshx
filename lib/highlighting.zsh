typeset -ga _ZSHX_LEX_HIGHLIGHTS
typeset -ga _ZSHX_CACHED_HIGHLIGHTS
typeset -g _ZSHX_CACHED_BUFFER

_zshx_emit_range() {
  local start=$1 end=$2 category=$3 style
  (( end >= start )) || return 0
  style=${ZSHX_HIGHLIGHT_STYLES[$category]-}
  [[ -n $style && $style != none ]] || return 0
  _ZSHX_LEX_HIGHLIGHTS+=("$((start - 1)) $end $style memo=zshx-syntax")
}

_zshx_variable_end() {
  local text=$1
  local -i start=$2 length=${#1} cursor
  local next

  next=${text[$((start + 1))]-}
  if [[ $next == '{' ]]; then
    local -i depth=1
    cursor=$((start + 2))
    while (( cursor <= length )); do
      case ${text[$cursor]} in
        '\\') (( cursor += 2 )); continue ;;
        '{') (( depth += 1 )) ;;
        '}')
          (( depth -= 1 ))
          if (( depth == 0 )); then
            REPLY=$cursor
            return 0
          fi
          ;;
      esac
      (( cursor++ ))
    done
    REPLY=$length
    return 0
  fi

  case $next in
    '!'|'#'|'$'|'@'|'*'|'?'|'-') REPLY=$((start + 1)); return 0 ;;
  esac

  if [[ $next == [[:alpha:]_] ]]; then
    cursor=$((start + 1))
    while (( cursor < length )) && [[ ${text[$((cursor + 1))]} == [[:alnum:]_] ]]; do
      (( cursor++ ))
    done
    REPLY=$cursor
    return 0
  fi

  REPLY=$start
}

_zshx_substitution_end() {
  local text=$1
  local -i start=$2 length=${#1} cursor depth=1
  local quote=''
  local char

  # start points at '$'; arithmetic expansion opens with two parentheses.
  cursor=$((start + 2))
  [[ ${text[$cursor]} == '(' ]] && { depth=2; (( cursor++ )); }

  while (( cursor <= length )); do
    char=${text[$cursor]}
    if [[ -n $quote ]]; then
      if [[ $char == '\\' && $quote != "'" ]]; then
        (( cursor += 2 ))
        continue
      elif [[ $char == $quote ]]; then
        quote=''
      fi
    else
      case $char in
        '\\') (( cursor += 2 )); continue ;;
        "'"|'"'|'`') quote=$char ;;
        '(') (( depth++ )) ;;
        ')')
          (( depth-- ))
          if (( depth == 0 )); then
            REPLY=$cursor
            return 0
          fi
          ;;
      esac
    fi
    (( cursor++ ))
  done

  REPLY=$length
}

_zshx_lex_buffer() {
  local comments_enabled=$options[interactivecomments]
  emulate -L zsh
  setopt extendedglob multibyte

  local text=$1 char next token word category operator quote='' range=''
  local -a quote_ranges variable_ranges substitution_ranges
  local -i length=${#1} cursor token_start token_end quote_start end command_pending=1 conditional=0
  local -i redirection_target=0 simple_word=1
  local -i previous_was_word=0

  _ZSHX_LEX_HIGHLIGHTS=()

  while (( cursor < length )); do
    (( cursor++ ))
    char=${text[$cursor]}

    if [[ $char == [[:space:]] ]]; then
      if [[ $char == $'\n' ]]; then
        command_pending=1
      fi
      previous_was_word=0
      continue
    fi

    if [[ $char == '#' && $comments_enabled == on ]] && (( ! previous_was_word )); then
      token_start=$cursor
      while (( cursor < length )) && [[ ${text[$((cursor + 1))]} != $'\n' ]]; do
        (( cursor++ ))
      done
      _zshx_emit_range $token_start $cursor comment
      previous_was_word=0
      continue
    fi

    case $char in
      '|'|'&'|';'|'<'|'>')
        token_start=$cursor
        operator=$char
        next=${text[$((cursor + 1))]-}
        if [[ $char == '|' && ( $next == '|' || $next == '&' ) ]]; then
          operator+=$next
          (( cursor++ ))
        elif [[ $char == '&' && ( $next == '&' || $next == '!' || $next == '|' ) ]]; then
          operator+=$next
          (( cursor++ ))
        elif [[ $char == ';' && ( $next == ';' || $next == '&' ) ]]; then
          operator+=$next
          (( cursor++ ))
          if [[ $operator == ';;&' ]]; then
            (( cursor++ ))
          elif [[ $operator == ';&' && ${text[$((cursor + 1))]} == ';' ]]; then
            operator+=';'
            (( cursor++ ))
          fi
        elif [[ $char == '<' && ( $next == '<' || $next == '>' || $next == '&' ) ]]; then
          operator+=$next
          (( cursor++ ))
          if [[ $operator == '<<' && ${text[$((cursor + 1))]} == '<' ]]; then
            operator+='<'
            (( cursor++ ))
          elif [[ $operator == '<<' && ${text[$((cursor + 1))]} == '-' ]]; then
            operator+='-'
            (( cursor++ ))
          fi
        elif [[ $char == '>' && ( $next == '>' || $next == '|' || $next == '&' || $next == '!' ) ]]; then
          operator+=$next
          (( cursor++ ))
        fi

        _zshx_emit_range $token_start $cursor operator
        case $operator in
          '<'|'>'|'<<'|'<<-'|'<<<'|'>>'|'>>|'|'>&'|'<&'|'<>'|'>|'|'>!')
            (( conditional )) || redirection_target=1
            ;;
          '|'|'||'|'|&'|'&'|'&&'|'&!'|'&|'|';'|';;'|';&'|';;&')
            (( conditional )) || command_pending=1
            redirection_target=0
            ;;
        esac
        previous_was_word=0
        continue
        ;;
      '('|'{'|')'|'}')
        _zshx_emit_range $cursor $cursor operator
        if [[ $char == '(' || $char == '{' || $char == ')' || $char == '}' ]]; then
          command_pending=1
        fi
        previous_was_word=0
        continue
        ;;
    esac

    token_start=$cursor
    token=''
    quote=''
    quote_start=0
    simple_word=1
    quote_ranges=()
    variable_ranges=()
    substitution_ranges=()

    while (( cursor <= length )); do
      char=${text[$cursor]}

      if [[ -n $quote ]]; then
        if [[ $quote == "'" ]]; then
          if [[ $char == "'" ]]; then
            quote_ranges+=("$quote_start $cursor string")
            quote=''
            quote_start=0
          fi
          (( cursor++ ))
          continue
        fi

        if [[ $char == '\\' ]]; then
          (( cursor += 2 ))
          continue
        fi
        if [[ $char == $quote ]]; then
          quote_ranges+=("$quote_start $cursor string")
          quote=''
          quote_start=0
          (( cursor++ ))
          continue
        fi
        if [[ $quote == '"' && $char == '$' ]]; then
          next=${text[$((cursor + 1))]-}
          if [[ $next == '(' ]]; then
            _zshx_substitution_end "$text" $cursor
            end=$REPLY
            substitution_ranges+=("$cursor $end substitution")
            cursor=$((end + 1))
            continue
          fi
          _zshx_variable_end "$text" $cursor
          end=$REPLY
          if (( end > cursor )); then
            variable_ranges+=("$cursor $end variable")
            cursor=$((end + 1))
            continue
          fi
        fi
        (( cursor++ ))
        continue
      fi

      if [[ $char == [[:space:]] || $char == '|' || $char == '&' || $char == ';' || $char == '<' || $char == '>' || $char == '(' || $char == ')' || $char == '{' || $char == '}' ]]; then
        break
      fi

      if [[ $char == "'" || $char == '"' ]]; then
        simple_word=0
        quote=$char
        quote_start=$cursor
        (( cursor++ ))
        continue
      fi

      if [[ $char == '\\' ]]; then
        simple_word=0
        (( cursor += 2 ))
        continue
      fi

      if [[ $char == '$' ]]; then
        simple_word=0
        next=${text[$((cursor + 1))]-}
        if [[ $next == '(' ]]; then
          _zshx_substitution_end "$text" $cursor
          end=$REPLY
          substitution_ranges+=("$cursor $end substitution")
          cursor=$((end + 1))
          continue
        fi
        _zshx_variable_end "$text" $cursor
        end=$REPLY
        if (( end > cursor )); then
          variable_ranges+=("$cursor $end variable")
          cursor=$((end + 1))
          continue
        fi
      fi

      if [[ $char == '`' ]]; then
        simple_word=0
        end=$((cursor + 1))
        while (( end <= length )) && [[ ${text[$end]} != '`' ]]; do
          [[ ${text[$end]} == '\\' ]] && (( end++ ))
          (( end++ ))
        done
        (( end > length )) && end=$length
        substitution_ranges+=("$cursor $end substitution")
        cursor=$((end + 1))
        continue
      fi

      (( cursor++ ))
    done

    (( cursor > length )) && token_end=$length || token_end=$((cursor - 1))
    (( token_end < token_start )) && token_end=$token_start
    token=${text[$token_start,$token_end]}

    if (( redirection_target )); then
      category=path
      redirection_target=0
    elif (( simple_word )) && [[ $token == <-> ]] && { [[ ${text[$((token_end + 1))]-} == '<' ]] || [[ ${text[$((token_end + 1))]-} == '>' ]]; }; then
      category=''
    elif (( simple_word )) && [[ $token == '[[' ]]; then
      category=reserved
      conditional=1
      command_pending=0
    elif (( simple_word )) && [[ $token == ']]' ]]; then
      category=reserved
      conditional=0
      command_pending=0
    elif (( conditional )); then
      case $token in
        -n|-z|-e|-f|-d|-r|-w|-x|-s|-o|-v|-eq|-ne|-lt|-le|-gt|-ge|-nt|-ot|-ef|'='|'=='|'!='|'=~')
          category=operator
          ;;
        *) category='' ;;
      esac
    elif (( simple_word )) && [[ $token == [A-Za-z_][A-Za-z0-9_]#=* ]]; then
      category=assignment
    elif (( command_pending )) && (( simple_word )); then
      case $token in
        if|then|else|elif|fi|for|while|until|do|done|case|esac|select|repeat|coproc|function|time|!)
          category=reserved
          case $token in
            fi|done|esac|']]') command_pending=0 ;;
            *) command_pending=1 ;;
          esac
          ;;
        command|builtin|exec|noglob|nocorrect|sudo|doas|env|nohup|nice)
          category=reserved
          command_pending=1
          ;;
        *)
          if whence -w -- "$token" >/dev/null 2>&1; then
            category=command
          else
            category=unknown
          fi
          command_pending=0
          ;;
      esac
    elif [[ $token == -?* ]]; then
      category=option
    elif [[ $token == */* && -e $token ]]; then
      category=path
    else
      category=''
    fi

    _zshx_emit_range $token_start $token_end $category
    for range in "${quote_ranges[@]}"; do
      _zshx_emit_range ${range%% *} ${${range#* }%% *} string
    done
    for range in "${substitution_ranges[@]}"; do
      _zshx_emit_range ${range%% *} ${${range#* }%% *} substitution
    done
    for range in "${variable_ranges[@]}"; do
      _zshx_emit_range ${range%% *} ${${range#* }%% *} variable
    done
    if [[ -n $quote ]]; then
      _zshx_emit_range $token_start $token_end error
    fi

    previous_was_word=1
    cursor=$token_end
  done
}

_zshx_apply_syntax_highlights() {
  local region
  if [[ $ZSHX_HIGHLIGHTING == 1 ]] && (( ${#BUFFER} <= ZSHX_HIGHLIGHT_MAX_BUFFER )); then
    if [[ $_ZSHX_CACHED_BUFFER != $BUFFER ]]; then
      _zshx_lex_buffer "$BUFFER"
      _ZSHX_CACHED_BUFFER=$BUFFER
      _ZSHX_CACHED_HIGHLIGHTS=("${_ZSHX_LEX_HIGHLIGHTS[@]}")
    fi
    for region in "${_ZSHX_CACHED_HIGHLIGHTS[@]}"; do
      region_highlight+=("$region")
    done
  else
    _ZSHX_CACHED_BUFFER=''
    _ZSHX_CACHED_HIGHLIGHTS=()
  fi
}

