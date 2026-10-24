# zshx

zshx combines lightweight command-line syntax highlighting with responsive history suggestions in one ZLE lifecycle. It supports **zsh 5.9 and newer** and has no runtime dependency beyond zsh.

The highlighter covers common interactive syntax; it is not a replacement for zsh's parser or a copy of fast-syntax-highlighting. Suggestions use literal prefixes from shell history. Completion suggestions are not included.

## Install

From the zshx directory, run:

```zsh
./install.sh
```

The installer requires zsh 5.9 or newer, copies zshx to `~/.zsh/plugins/zshx`, and adds a source line to `${ZDOTDIR:-$HOME}/.zshrc`. It is safe to run again; it updates the installed files without adding a duplicate source line. Restart the shell or run `source ~/.zshrc` afterward.

To install elsewhere, or to install files without editing `.zshrc`:

```sh
ZSHX_INSTALL_DIR="$HOME/.config/zshx" ./install.sh
./install.sh --no-rc
```

When using `--no-rc`, add the printed source command to your `.zshrc` yourself. For a manual install, place the project directory somewhere stable and source `zshx.plugin.zsh` directly.

Loading the plugin enables syntax highlighting and history suggestions by default. Recent history is checked inline for prompt feedback; when there is no recent match, a cancellable asynchronous lookup searches further back. As you type through a displayed suggestion, zshx keeps the remaining suffix visible without looking up history again. No feature switches or strategy settings are required. To customize styles or limits, set only the values you want to change before sourcing the plugin:

```zsh
typeset -gA ZSHX_HIGHLIGHT_STYLES
ZSHX_HIGHLIGHT_STYLES[command]='fg=blue,bold'

source "$HOME/.zsh/plugins/zshx/zshx.plugin.zsh"
```

All settings are optional and existing `ZSHX_*` values are preserved. The default strategy is `history`; unsupported strategy names do not activate another backend.

## Accept suggestions

By default, the plugin wraps the standard forward/end widgets. Moving right at the end of the input accepts the full suggestion; forward-word accepts one word. Original builtin or user-defined widget behavior is retained when there is no suggestion. zshx does not install key bindings.

To bind dedicated keys, for example:

```zsh
bindkey '^X^A' zshx-accept-suggestion
bindkey '^X^W' zshx-accept-suggestion-word
bindkey '^X^]' zshx-clear-suggestion
```

The command widgets `zshx-enable-autosuggest`, `zshx-disable-autosuggest`, and `zshx-toggle-autosuggest` can also be bound. Equivalent shell functions are available outside ZLE. Highlighting can be controlled with `zshx-enable-highlighting` and `zshx-disable-highlighting`.

## Supported behavior and limits

- Highlighting: common commands, unknown commands, reserved words, options, assignments, existing paths, quoted text, variables, command substitutions, comments when `interactivecomments` is enabled, operators, and unfinished quotes.
- Suggestions: the most recent history entry that starts with the current buffer. The newest 100 events are checked inline; older matches are found asynchronously, up to `ZSHX_SUGGEST_HISTORY_LIMIT`.
- Suggestions are displayed after the editable buffer with `POSTDISPLAY`. They are hidden when the cursor is away from the buffer end, the buffer is empty, or it exceeds the configured length limit.
- Syntax highlighting is skipped above `ZSHX_HIGHLIGHT_MAX_BUFFER` (512 characters by default) to bound redraw work; raise the value if longer buffers matter more than input latency.
- Suggestions are not written into `BUFFER` unless accepted. Completion-based suggestions, upstream configuration aliases, command-specific chromas, and complete shell grammar parsing are out of scope.
- Other plugins may also own ZLE hooks, widgets, and highlight regions. zshx removes only its own tagged highlight regions and restores wrapped widgets on unload. Compatibility is documented only for combinations actually exercised.

To remove zshx in the current shell, run `zshx-unload`. You can source the plugin again afterward.

## Development checks

Run the core checks with the zsh version you want to validate:

```zsh
zsh tests/unit.zsh
sh tests/install.sh
ZSH_BIN=zsh python3 tests/zle_pty.py
```

`tests/zle_pty.py` starts an interactive zsh in a pseudo-terminal and checks history display, stale async responses, independent feature switches, emacs/vi insert/command acceptance, cursor movement, UTF-8 input, and hook/widget cleanup on unload/reload. `benchmarks/run.zsh` reports tokenizer p50/p95 for representative input lengths. The GitHub Actions workflow is configured for macOS system zsh and current Homebrew zsh; local results should include the actual `zsh --version` output.

## Design and license

Original zshx code is MIT licensed; see [`LICENSE`](LICENSE). No upstream source files are included; the plugin is implemented independently and has no runtime dependency beyond zsh.
