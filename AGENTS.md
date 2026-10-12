# AGENTS.md

clipboard.ranma is a ranma plugin in Lua: `plugin/clipboard.lua` is all of it, and
its header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Keep it working on the latest ranma release, which is what CI loads. Use
  only API that release has (`git show <tag>:assets/ranma.d.lua` in ranma).
  `s:set` there cannot clear a status with `false`, so the status is set once,
  as the screen opens.
- Copy mode's yanks are seen by polling `ranma.state().mode` and reading the
  system clipboard back, because ranma tells a plugin nothing of a yank. A
  core `copy` hook (`{ text, pane, source }`) is picked up by the
  `pcall(ranma.on, "copy", ...)` at load and replaces both the poll and the
  `ranma.copy` wrapper; keep that branch when changing either.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- Test behaviour in a private server (its own `RANMA_CONFIG_DIR`,
  `XDG_RUNTIME_DIR`, `XDG_STATE_HOME`, with `RANMA_SOCKET RANMA RANMA_PANE TMUX`
  unset) inside a private `tmux -L`, never in your own ranma. A private tmux
  with `set-clipboard on` catches the OSC 52, and `clipboard.reader =
  "tmux -L <sock> show-buffer"` reads it back without touching the desktop's
  clipboard.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
