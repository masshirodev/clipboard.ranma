# clipboard.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: a history of what was copied in ranma, with the pane and program it came from, pasted back into a pane or copied again from a list.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/clipboard.lua`:

```lua
return { "masshirodev/clipboard.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/clipboard.ranma ~/.config/ranma/pack/plugins/start/clipboard.ranma
```

Needs: For copy mode's yanks, a command that prints the system clipboard: `wl-paste` (Wayland), `xclip` or `xsel` (X11), `pbpaste` (macOS), or your own in `clipboard.reader`. Without one, only copies made through `ranma.copy` are kept, and the screen says so.

## What it does

```text
leader ctrl+v opens the copies, newest first, with the text of the selected
one below the list. On it:
  enter  paste it into the pane you were in, bracketed when the program
         asked for that (with clipboard.enter = "copy": copy it again)
  y      copy it again: the clipboard gets it, and it moves to the top
  p      paste it, in y's place, when enter copies
  d / D  forget it / forget them all (D asks first)
Palette (leader :): `clipboard` opens it, `clipboard-clear` forgets them all.
Another key: ranma.emit("clipboard_open") opens it.

What is kept, with the pane, its program and the time:
  - every ranma.copy, from this plugin's own keys or any other plugin's
    (history's y, openpath's copy the path, ...): it wraps ranma.copy;
  - copy mode's yanks (leader [, leader /). ranma 0.1.0 tells a plugin
    nothing of a yank (no hook, and mode_change never says "copy"), so a
    timer looks at ranma.state().mode four times a second and, when copy
    mode ends, reads the system clipboard back (wl-paste, xclip, xsel or
    pbpaste, or the clipboard.reader command) and keeps it if it changed.
    That is off while the terminal driving ranma came over SSH: the copy
    went to that machine's clipboard, not this one's. The screen's status
    says when yanks are not being kept, and why.
Not kept: links copied from hints (leader o), and what programs copy
themselves with OSC 52; ranma's own choose_buffer (leader V) has those.
A ranma with a `copy` hook ({ text, pane, source }) is heard instead, and
then every copy is kept and nothing is polled.
A copy is kept once when made twice in a row. One over clipboard.max_bytes
is not kept at all (a cut paste would be worse than none), and the oldest
go past clipboard.max_entries. The history is in ranma.store("clipboard"),
ON DISK, unlike choose_buffer's: a password yanked is written there until
it ages out, `d` forgets it, or clipboard-clear empties the history.

Options (settings panel, "clipboard" group): clipboard.max_entries,
clipboard.max_bytes, clipboard.enter, clipboard.reader.

ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Lua at run
time": ranma.copy, ranma.state; "Pane handles": paste; "Screens"; "Timers and processes").
```

## Binds and commands

| Key or command | Does |
| --- | --- |
| `leader ctrl+v` | Open the history (in the which-key hint's `plugins` group). |
| `:clipboard` | The same, from the palette. |
| `:clipboard-clear` | Forget every copy, without asking. |

`ranma.emit("clipboard_open")` opens it too, so another key is one line of `init.lua`:

```lua
ranma.unbind("ctrl+v")
ranma.bind("C", function() ranma.emit("clipboard_open") end, { desc = "clipboard", exit = true })
```

## Options

In ranma's settings panel under `clipboard`, or with hako's `opts` (`{ "masshirodev/clipboard.ranma", opts = { ... } }`), or `ranma.set { clipboard = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `clipboard.max_entries` | `50` | How many copies the history keeps, newest first; older ones are forgotten. |
| `clipboard.max_bytes` | `16384` | A copy bigger than this many bytes is not kept. |
| `clipboard.enter` | `"paste"` | What enter does on a copy: `paste` it into the pane, or `copy` it to the clipboard. |
| `clipboard.reader` | `"auto"` | The command that prints the system clipboard, read when copy mode ends. `auto`: wl-paste, xclip, xsel or pbpaste; `off`: never read it. |

## Privacy

The history is a file, `~/.local/state/ranma/store/clipboard.json`, and stays across restarts. ranma's own `choose_buffer` keeps copies in memory only, because a clipboard holds passwords. If you yank secrets, set `clipboard.max_entries` low, forget them with `d`, or use `clipboard-clear`.

## License

MIT or Apache-2.0, as ranma.
