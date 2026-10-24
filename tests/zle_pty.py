#!/usr/bin/env python3
"""Exercise ZLE behavior in real interactive zsh pseudo-terminals."""

import os
import pathlib
import pty
import select
import tempfile
import time


ROOT = pathlib.Path(__file__).resolve().parents[1]
ZSH = os.environ.get("ZSH_BIN", "/bin/zsh")


class ZshSession:
    def __init__(self, vi_mode=False):
        self.tempdir = tempfile.TemporaryDirectory(prefix="zshx-pty-")
        self.root = pathlib.Path(self.tempdir.name)
        self.log = self.root / "snapshots.log"
        self.hooks = self.root / "hooks.log"
        self.hooks_after_unload = self.root / "hooks-after-unload.log"
        self.probe = self.root / "probe.log"
        self.output = bytearray()
        self._write_zshrc(vi_mode)

        env = os.environ.copy()
        env["ZDOTDIR"] = str(self.root)
        env["TERM"] = "xterm-256color"
        env["HISTFILE"] = str(self.root / "history")
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execve(ZSH, [ZSH, "-i"], env)
        self.drain(1.2)
        self.assert_not_in_output("zshx: could not register")
        self.assert_not_in_output("parse error")
        if not self.hooks.exists():
            output = self.output.decode("utf-8", errors="replace")
            self.stop()
            raise AssertionError(f"interactive zsh did not initialize the test hooks: {output[-2000:]}")

    def _write_zshrc(self, vi_mode):
        vi_binding = "bindkey -v" if vi_mode else ":"
        startup = []
        module_path = os.environ.get("ZSHX_TEST_MODULE_PATH")
        function_path = os.environ.get("ZSHX_TEST_FUNCTION_PATH")
        if module_path:
            startup.append(f"module_path=({module_path!r} $module_path)")
        if function_path:
            startup.append(f"fpath=({function_path!r} $fpath)")
        startup_config = "\n".join(startup)
        zshrc = f'''HISTSIZE=1000
SAVEHIST=1000
HISTFILE={str(self.root / 'history')!r}
{startup_config}
print -s -- 'git status --short'
print -s -- 'go build ./...'
print -s -- 'vim ~/.zshrc'
print -s -- 'zshx-old-history-match tail'
for i in {{1..120}}; do print -s -- "zshx-noise-$i"; done
print -s -- 'vim ~/.zshrc'
{vi_binding}
_zshx_test_forward() {{ zle .forward-char; typeset -gi _ZSHX_TEST_FORWARD_COUNT=$((_ZSHX_TEST_FORWARD_COUNT + 1)); }}
zle -N forward-char _zshx_test_forward
source {str(ROOT / 'zshx.plugin.zsh')!r}
source {str(ROOT / 'zshx.plugin.zsh')!r}
PS1='ZSHX-PTY> '
_zshx_test_snapshot() {{ true; print -r -- "SNAP|$BUFFER|$POSTDISPLAY|$CURSOR|${{(j:;:)region_highlight}}" >> {str(self.log)!r} }}
_zshx_test_probe() {{ true; (( ${{+functions[_zshx_pre_redraw]}} )) && _zshx_pre_redraw; printf '%s\\n' "BUFFER=$BUFFER" "POSTDISPLAY=$POSTDISPLAY" "FORWARD=${{widgets[forward-char]}}" "SUGGESTION=$_ZSHX_SUGGESTION_TEXT" "AUTOSUGGEST=$ZSHX_AUTOSUGGEST HIGHLIGHTING=$ZSHX_HIGHLIGHTING" "REQUEST=$_ZSHX_REQUEST_BUFFER ID=$_ZSHX_REQUEST_ID FD=$_ZSHX_ASYNC_FD PID=$_ZSHX_ASYNC_PID" "HIGHLIGHTS=${{(j:;:)region_highlight}}" > {str(self.probe)!r} }}
_zshx_test_stale_result() {{ true; zle _zshx-async-result -- stale "$BUFFER" 'git stale-result' }}
zle -N zshx-test-stale-result _zshx_test_stale_result
_zshx_test_disable_suggestions() {{ true; zshx-disable-autosuggest }}
_zshx_test_enable_suggestions() {{ true; zshx-enable-autosuggest }}
_zshx_test_disable_highlighting() {{ true; zshx-disable-highlighting }}
_zshx_test_enable_highlighting() {{ true; zshx-enable-highlighting }}
zle -N zshx-test-disable-suggestions _zshx_test_disable_suggestions
zle -N zshx-test-enable-suggestions _zshx_test_enable_suggestions
zle -N zshx-test-disable-highlighting _zshx_test_disable_highlighting
zle -N zshx-test-enable-highlighting _zshx_test_enable_highlighting
_zshx_test_reload() {{ add-zle-hook-widget -d zle-line-pre-redraw _zshx_test_snapshot; source {str(ROOT / 'zshx.plugin.zsh')!r}; add-zle-hook-widget zle-line-pre-redraw _zshx_test_snapshot }}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget zle-line-pre-redraw _zshx_test_snapshot
add-zle-hook-widget -L > {str(self.hooks)!r}
bindkey '^X^W' zshx-accept-suggestion-word
bindkey '^X^V' zshx-test-probe
bindkey '^X^S' zshx-test-stale-result
bindkey '^X^D' zshx-test-disable-suggestions
bindkey '^X^E' zshx-test-enable-suggestions
bindkey '^X^H' zshx-test-disable-highlighting
bindkey '^X^L' zshx-test-enable-highlighting
zle -N zshx-test-probe _zshx_test_probe
'''
        (self.root / ".zshrc").write_text(zshrc, encoding="utf-8")

    def drain(self, seconds=0.1):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.fd], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                break
            try:
                chunk = os.read(self.fd, 8192)
            except OSError:
                break
            if not chunk:
                break
            self.output.extend(chunk)

    def send(self, data):
        if isinstance(data, str):
            data = data.encode("utf-8")
        os.write(self.fd, data)

    def snapshots(self):
        if not self.log.exists():
            return []
        result = []
        for line in self.log.read_text(encoding="utf-8").splitlines():
            fields = line.split("|", 4)
            if len(fields) == 5 and fields[0] == "SNAP":
                result.append({
                    "buffer": fields[1],
                    "postdisplay": fields[2],
                    "cursor": int(fields[3]),
                    "highlights": fields[4],
                })
        return result

    def probe_state(self):
        self.send(b"\x18\x16")
        self.drain(0.05)
        if not self.probe.exists():
            return {}
        result = {}
        for line in self.probe.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                result[key] = value
        return result

    def wait_probe(self, predicate, timeout=4.0, label="probe"):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.drain(0.05)
            state = self.probe_state()
            if predicate(state):
                return state
        raise AssertionError(f"timed out waiting for {label}; probe={self.probe_state()}")

    def wait_snapshot(self, predicate, start=0, timeout=4.0, label="snapshot"):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.drain(0.05)
            rows = self.snapshots()
            for index in range(start, len(rows)):
                if predicate(rows[index]):
                    return index, rows[index]
        raise AssertionError(f"timed out waiting for {label}; recent snapshots={self.snapshots()[-8:]}")

    def assert_not_in_output(self, text):
        output = self.output.decode("utf-8", errors="replace")
        if text in output:
            raise AssertionError(f"unexpected startup output {text!r}: {output[-1000:]}")

    def stop(self):
        try:
            os.write(self.fd, b"\x03exit\n")
            self.drain(0.2)
        except OSError:
            pass
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass
        self.tempdir.cleanup()


def test_emacs_mode():
    session = ZshSession()
    try:
        hook_text = session.hooks.read_text(encoding="utf-8")
        if hook_text.count("_zshx_pre_redraw") != 1:
            raise AssertionError(f"repeated source installed duplicate redraw hooks: {hook_text}")

        session.send("git")
        state = session.wait_probe(
            lambda item: item.get("BUFFER") == "git" and item.get("POSTDISPLAY") == " status --short",
            label="history suggestion",
        )
        if "memo=zshx-syntax" not in state.get("HIGHLIGHTS", "") or "memo=zshx-suggestion" not in state.get("HIGHLIGHTS", ""):
            raise AssertionError(f"syntax and suggestion regions were not both installed: {state}")
        if "status --short" not in session.output.decode("utf-8", errors="replace"):
            raise AssertionError("history suggestion was not rendered in the pseudo-terminal")

        session.send(b"\x18\x53")
        session.drain(0.1)
        state = session.probe_state()
        if state.get("SUGGESTION") != "git status --short" or "stale-result" in state.get("POSTDISPLAY", ""):
            raise AssertionError(f"stale asynchronous result replaced the current suggestion: {state}")

        session.send(b"\x18\x04")
        state = session.wait_probe(
            lambda item: item.get("AUTOSUGGEST") == "0 HIGHLIGHTING=1" and not item.get("POSTDISPLAY"),
            label="suggestions disabled independently",
        )
        if "memo=zshx-syntax" not in state.get("HIGHLIGHTS", "") or "memo=zshx-suggestion" in state.get("HIGHLIGHTS", ""):
            raise AssertionError(f"disabling suggestions affected syntax highlighting: {state}")

        session.send(b"\x18\x05")
        session.wait_probe(
            lambda item: item.get("AUTOSUGGEST") == "1 HIGHLIGHTING=1" and item.get("POSTDISPLAY") == " status --short",
            label="suggestions re-enabled",
        )

        session.send(b"\x18\x08")
        state = session.probe_state()
        if state.get("AUTOSUGGEST") != "1 HIGHLIGHTING=0" or "memo=zshx-syntax" in state.get("HIGHLIGHTS", "") or "memo=zshx-suggestion" not in state.get("HIGHLIGHTS", ""):
            raise AssertionError(f"disabling highlighting affected suggestions: {state}")

        session.send(b"\x18\x0c")
        state = session.probe_state()
        if state.get("AUTOSUGGEST") != "1 HIGHLIGHTING=1" or "memo=zshx-syntax" not in state.get("HIGHLIGHTS", ""):
            raise AssertionError(f"highlighting did not re-enable independently: {state}")

        start = len(session.snapshots())
        session.send(b"\x1b[D")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "git" and item["cursor"] == 2,
            start=start,
            label="cursor moved into the middle of the buffer",
        )
        state = session.probe_state()
        if state.get("POSTDISPLAY"):
            raise AssertionError(f"suggestion remained visible away from buffer end: {state}")

        start = len(session.snapshots())
        session.send(b"\x1b[C")
        session.wait_snapshot(
            lambda item: item["buffer"] == "git" and item["cursor"] == 3,
            start=start,
            label="cursor returned to buffer end",
        )
        state = session.probe_state()
        if state.get("POSTDISPLAY") != " status --short":
            raise AssertionError(f"suggestion was not restored at buffer end: {state}")

        session.send(b"\x1b[C")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "git status --short" and item["postdisplay"] == "",
            label="accept full suggestion with forward-char",
        )
        if row["cursor"] != len("git status --short"):
            raise AssertionError(f"full acceptance left cursor at the wrong position: {row}")

        session.send(b"\x03")
        session.drain(0.15)
        started = time.monotonic()
        start = len(session.snapshots())
        session.send("vim")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "vim" and item["postdisplay"] == " ~/.zshrc",
            start=start,
            label="recent-history suggestion for a command prefix",
        )
        session.send(" ~/.")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "vim ~/." and item["postdisplay"] == "zshrc",
            start=start,
            label="typing through a suggestion preserves its remaining suffix",
        )
        lookup_delay = time.monotonic() - started
        if lookup_delay > 0.25:
            raise AssertionError(f"recent history suggestion appeared too slowly ({lookup_delay:.3f}s): {row}")

        session.send(b"\x03")
        session.drain(0.15)
        session.send("zshx-old-history-match")
        state = session.wait_probe(
            lambda item: item.get("BUFFER") == "zshx-old-history-match" and item.get("POSTDISPLAY") == " tail",
            label="async fallback finds older history matches",
        )

        session.send(b"\x03")
        session.drain(0.15)
        session.send("go")
        session.wait_probe(
            lambda item: item.get("BUFFER") == "go" and item.get("POSTDISPLAY") == " build ./...",
            label="new suggestion after Ctrl-C",
        )

        session.send(b"\x18\x17")
        state = session.wait_probe(
            lambda item: item.get("BUFFER", "").startswith("go ") and item.get("POSTDISPLAY", "").startswith("build"),
            label="partial word acceptance",
        )
        if state["BUFFER"] + state["POSTDISPLAY"] != "go build ./...":
            raise AssertionError(f"partial acceptance lost or duplicated text: {state}")

        session.send(b"\x1b[C")
        session.wait_snapshot(
            lambda item: item["buffer"] == "go build ./..." and item["postdisplay"] == "",
            label="complete after partial acceptance",
        )

        session.send(b"\x03")
        session.drain(0.15)
        session.send("echo 猫")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "echo 猫" and "memo=zshx-syntax" in item["highlights"],
            label="UTF-8 buffer highlighting",
        )

        session.send(b"\x03")
        session.drain(0.15)
        session.send("zshx-unload\n")
        session.drain(0.4)
        session.send(f"add-zle-hook-widget -L > {str(session.hooks_after_unload)!r}\n")
        session.drain(0.2)
        remaining_hooks = session.hooks_after_unload.read_text(encoding="utf-8")
        if "_zshx_pre_redraw" in remaining_hooks or "_zshx_line_" in remaining_hooks:
            raise AssertionError(f"unload left zshx hooks registered: {remaining_hooks}")
        session.send("git")
        start = len(session.snapshots())
        session.send(b"\x18\x16")
        session.drain(0.2)
        probe = session.probe.read_text(encoding="utf-8")
        if "BUFFER=git" not in probe or "POSTDISPLAY=" not in probe:
            raise AssertionError(f"unload left stale ZLE display state: {probe}")
        if "FORWARD=user:_zshx_test_forward" not in probe:
            raise AssertionError(f"unload did not restore the user's widget: {probe}")
        if "memo=zshx-syntax" in probe or "memo=zshx-suggestion" in probe:
            raise AssertionError(f"unload left zshx highlight regions: {probe}")

        session.send(b"\x03")
        session.drain(0.15)
        session.send("_zshx_test_reload\n")
        session.drain(0.4)
        session.send("git")
        session.wait_probe(
            lambda item: item.get("BUFFER") == "git" and item.get("POSTDISPLAY") == " status --short",
            label="source again after unload",
        )
    finally:
        session.stop()


def test_vi_mode():
    session = ZshSession(vi_mode=True)
    try:
        session.send("git")
        session.wait_probe(
            lambda item: item.get("BUFFER") == "git" and item.get("POSTDISPLAY") == " status --short",
            label="vi insert mode suggestion",
        )
        session.send(b"\x18\x17")
        state = session.wait_probe(
            lambda item: item.get("BUFFER", "").startswith("git ") and item.get("POSTDISPLAY", ""),
            label="vi partial suggestion acceptance",
        )
        if state["BUFFER"] + state["POSTDISPLAY"] != "git status --short":
            raise AssertionError(f"vi partial acceptance lost or duplicated text: {state}")
        session.send(b"\x1bA")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "git status --short" and item["postdisplay"] == "",
            label="accept suggestion with vi-add-eol",
        )
        if row["cursor"] != len("git status --short"):
            raise AssertionError(f"vi acceptance left cursor at the wrong position: {row}")
    finally:
        session.stop()


def test_vi_command_mode():
    session = ZshSession(vi_mode=True)
    try:
        session.send("git")
        session.wait_probe(
            lambda item: item.get("BUFFER") == "git" and item.get("POSTDISPLAY") == " status --short",
            label="vi insert mode suggestion before command mode",
        )
        start = len(session.snapshots())
        session.send(b"\x1b")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "git" and item["cursor"] == 2,
            start=start,
            label="enter vi command mode at buffer end",
        )

        start = len(session.snapshots())
        session.send("l")
        _, row = session.wait_snapshot(
            lambda item: item["buffer"] == "git status --short",
            start=start,
            label="accept full suggestion with vi-forward-char",
        )
        if row["cursor"] != len("git status --short") - 1:
            raise AssertionError(f"vi command-mode acceptance left cursor at the wrong position: {row}")
    finally:
        session.stop()


if __name__ == "__main__":
    test_emacs_mode()
    test_vi_mode()
    test_vi_command_mode()
    print("pty: interactive emacs/vi acceptance, redraw, async and unload checks passed")

