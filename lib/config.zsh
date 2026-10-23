# Public configuration is read before the plugin initializes, so preserve any
# values the user has already set.

(( ${+ZSHX_HIGHLIGHTING} )) || typeset -g ZSHX_HIGHLIGHTING=1
(( ${+ZSHX_AUTOSUGGEST} )) || typeset -g ZSHX_AUTOSUGGEST=1
(( ${+ZSHX_SUGGEST_ASYNC} )) || typeset -g ZSHX_SUGGEST_ASYNC=1
(( ${+ZSHX_BUFFER_MAX_SIZE} )) || typeset -gi ZSHX_BUFFER_MAX_SIZE=4000
(( ${+ZSHX_HIGHLIGHT_MAX_BUFFER} )) || typeset -gi ZSHX_HIGHLIGHT_MAX_BUFFER=512
(( ${+ZSHX_SUGGEST_HISTORY_LIMIT} )) || typeset -gi ZSHX_SUGGEST_HISTORY_LIMIT=2000

if (( ! ${+ZSHX_SUGGEST_STRATEGY} )); then
  typeset -ga ZSHX_SUGGEST_STRATEGY=(history)
else
  typeset -ga ZSHX_SUGGEST_STRATEGY
fi

if (( ! ${+ZSHX_ACCEPT_WIDGETS} )); then
  typeset -ga ZSHX_ACCEPT_WIDGETS=(forward-char end-of-line vi-forward-char vi-end-of-line vi-add-eol)
else
  typeset -ga ZSHX_ACCEPT_WIDGETS
fi

if (( ! ${+ZSHX_PARTIAL_ACCEPT_WIDGETS} )); then
  typeset -ga ZSHX_PARTIAL_ACCEPT_WIDGETS=(forward-word emacs-forward-word vi-forward-word vi-forward-word-end)
else
  typeset -ga ZSHX_PARTIAL_ACCEPT_WIDGETS
fi

typeset -gA ZSHX_HIGHLIGHT_STYLES
(( ${+ZSHX_HIGHLIGHT_STYLES[command]} )) || ZSHX_HIGHLIGHT_STYLES[command]='fg=green'
(( ${+ZSHX_HIGHLIGHT_STYLES[unknown]} )) || ZSHX_HIGHLIGHT_STYLES[unknown]='fg=red,bold'
(( ${+ZSHX_HIGHLIGHT_STYLES[reserved]} )) || ZSHX_HIGHLIGHT_STYLES[reserved]='fg=yellow,bold'
(( ${+ZSHX_HIGHLIGHT_STYLES[option]} )) || ZSHX_HIGHLIGHT_STYLES[option]='fg=cyan'
(( ${+ZSHX_HIGHLIGHT_STYLES[assignment]} )) || ZSHX_HIGHLIGHT_STYLES[assignment]='fg=cyan'
(( ${+ZSHX_HIGHLIGHT_STYLES[path]} )) || ZSHX_HIGHLIGHT_STYLES[path]='fg=blue,underline'
(( ${+ZSHX_HIGHLIGHT_STYLES[string]} )) || ZSHX_HIGHLIGHT_STYLES[string]='fg=green'
(( ${+ZSHX_HIGHLIGHT_STYLES[variable]} )) || ZSHX_HIGHLIGHT_STYLES[variable]='fg=magenta'
(( ${+ZSHX_HIGHLIGHT_STYLES[substitution]} )) || ZSHX_HIGHLIGHT_STYLES[substitution]='fg=magenta'
(( ${+ZSHX_HIGHLIGHT_STYLES[comment]} )) || ZSHX_HIGHLIGHT_STYLES[comment]='fg=8'
(( ${+ZSHX_HIGHLIGHT_STYLES[operator]} )) || ZSHX_HIGHLIGHT_STYLES[operator]='fg=white,bold'
(( ${+ZSHX_HIGHLIGHT_STYLES[error]} )) || ZSHX_HIGHLIGHT_STYLES[error]='fg=red,underline'
(( ${+ZSHX_SUGGEST_HIGHLIGHT_STYLE} )) || typeset -g ZSHX_SUGGEST_HIGHLIGHT_STYLE='fg=8'

