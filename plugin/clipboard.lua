-- clipboard: a history of what was copied in ranma, pasted back from a list.
--
-- leader ctrl+v opens the copies, newest first, with the text of the selected
-- one below the list. On it:
--   enter  paste it into the pane you were in, bracketed when the program
--          asked for that (with clipboard.enter = "copy": copy it again)
--   y      copy it again: the clipboard gets it, and it moves to the top
--   p      paste it, in y's place, when enter copies
--   d / D  forget it / forget them all (D asks first)
-- Palette (leader :): `clipboard` opens it, `clipboard-clear` forgets them all.
-- Another key: ranma.emit("clipboard_open") opens it.
--
-- What is kept, with the pane, its program and the time:
--   - every ranma.copy, from this plugin's own keys or any other plugin's
--     (history's y, openpath's copy the path, ...): it wraps ranma.copy;
--   - copy mode's yanks (leader [, leader /). ranma 0.1.0 tells a plugin
--     nothing of a yank (no hook, and mode_change never says "copy"), so a
--     timer looks at ranma.state().mode four times a second and, when copy
--     mode ends, reads the system clipboard back (wl-paste, xclip, xsel or
--     pbpaste, or the clipboard.reader command) and keeps it if it changed.
--     That is off while the terminal driving ranma came over SSH: the copy
--     went to that machine's clipboard, not this one's. The screen's status
--     says when yanks are not being kept, and why.
-- Not kept: links copied from hints (leader o), and what programs copy
-- themselves with OSC 52; ranma's own choose_buffer (leader V) has those.
-- A ranma with a `copy` hook ({ text, pane, source }) is heard instead, and
-- then every copy is kept and nothing is polled.
-- A copy is kept once when made twice in a row. One over clipboard.max_bytes
-- is not kept at all (a cut paste would be worse than none), and the oldest
-- go past clipboard.max_entries. The history is in ranma.store("clipboard"),
-- ON DISK, unlike choose_buffer's: a password yanked is written there until
-- it ages out, `d` forgets it, or clipboard-clear empties the history.
--
-- Options (settings panel, "clipboard" group): clipboard.max_entries,
-- clipboard.max_bytes, clipboard.enter, clipboard.reader.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Lua at run
-- time": ranma.copy, ranma.state; "Pane handles": paste; "Screens"; "Timers and processes").

ranma.option("clipboard.max_entries", {
  type = "int", min = 5, max = 500, step = 5, default = 50, slider = false,
  name = "Copies kept", desc = "How many copies the history keeps, newest first; older ones are forgotten.",
})
ranma.option("clipboard.max_bytes", {
  type = "int", min = 1024, max = 65536, step = 1024, default = 16384, slider = false,
  name = "Largest copy", desc = "A copy bigger than this many bytes is not kept.",
})
ranma.option("clipboard.enter", {
  type = "enum", choices = { "paste", "copy" }, default = "paste",
  name = "Enter", desc = "What enter does on a copy: paste it into the pane, or put it on the clipboard.",
})
ranma.option("clipboard.reader", {
  type = "string", default = "auto",
  name = "Clipboard reader",
  desc = "The command that prints the system clipboard, read when copy mode ends. auto: wl-paste, xclip, xsel or pbpaste; off: never read it.",
})

-- The whole store must stay under ranma's 1 MiB for a store.
local BUDGET = 768 * 1024
local POLL = 250
local PREVIEW = 80
local DETAIL_LINES = 40

local store = ranma.store("clipboard")
local raw_copy = ranma.copy

local function entries()
  return store:get("entries") or {}
end

-- A set the store refuses (past its 1 MiB, or text JSON cannot hold) keeps
-- the history as it was rather than failing the key that made the copy.
local function save(list)
  local ok, err = pcall(store.set, store, "entries", list)
  if not ok then ranma.notify("clipboard: history not saved: " .. tostring(err):match("[^\n]*")) end
end

-- Drop the oldest past the count and the byte budget.
local function trim(list)
  local max = ranma.get("clipboard.max_entries")
  local total, kept = 0, {}
  for _, e in ipairs(list) do
    total = total + #e.text
    if #kept >= max or total > BUDGET then break end
    kept[#kept + 1] = e
  end
  return kept
end

local function too_big(text)
  return #text > ranma.get("clipboard.max_bytes")
end

-- The text of the last copy, kept or read: what a clipboard read is compared
-- against, so leaving copy mode without yanking keeps nothing.
local last_seen = (entries()[1] or {}).text

-- Keep `text` as the newest copy, made in pane `pane_id` (or the focused one).
local function record(text, source, pane_id)
  if type(text) ~= "string" or text == "" then return end
  last_seen = text
  if too_big(text) then
    ranma.notify(("clipboard: a copy of %d bytes is over clipboard.max_bytes, not kept"):format(#text))
    return
  end
  local list = entries()
  if list[1] and list[1].text == text then return end
  local p = pane_id and ranma.pane(pane_id) or ranma.pane()
  local program = p and p:alive() and p:program() or nil
  local id = (store:get("next_id") or 1)
  store:set("next_id", id + 1)
  table.insert(list, 1, {
    id = id, text = text, source = source, time = os.time(),
    pane = p and p.id, title = p and p.title, program = program,
  })
  save(trim(list))
end

-- Text from the clipboard reader is what the terminal stored, which may add
-- a trailing newline a yank did not have; one is dropped, as wl-paste -n does.
local function chomp(s)
  return (s:gsub("\r?\n$", ""))
end

-- Whether a program is on PATH, looked for without starting a process.
local function have(cmd)
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    local f = io.open(dir .. "/" .. cmd, "r")
    if f then f:close(); return true end
  end
  return false
end

-- The command that prints the clipboard, or nil and why there is none.
local reader_cache
local function reader()
  local opt = ranma.get("clipboard.reader")
  if opt == "off" then return nil, "reader off" end
  if opt ~= "auto" then return opt end
  if reader_cache ~= nil then return reader_cache or nil, "no reader found" end
  local found = false
  if os.getenv("WAYLAND_DISPLAY") and have("wl-paste") then
    found = "wl-paste --no-newline --type text"
  elseif os.getenv("DISPLAY") and have("xclip") then
    found = "xclip -o -selection clipboard"
  elseif os.getenv("DISPLAY") and have("xsel") then
    found = "xsel --clipboard --output"
  elseif have("pbpaste") then
    found = "pbpaste"
  end
  reader_cache = found
  return found or nil, "no reader found"
end

-- Whether the terminal driving ranma came over SSH (none attached: no).
local function remote()
  local c = ranma.client()
  return c ~= nil and c.remote == true
end

-- Why copy mode's yanks are not being kept right now, or nil when they are.
local function blind()
  local cmd, why = reader()
  if not cmd then return why end
  if remote() then return "over SSH" end
  return nil
end

local function read_clipboard(fn)
  local cmd = reader()
  if not cmd or remote() then return end
  ranma.spawn(cmd, { timeout = 2, on_exit = function(r)
    if r.code == 0 and r.stdout then fn(chomp(r.stdout)) end
  end })
end

local has_event = pcall(ranma.on, "copy", function(ev)
  record(ev.text, ev.source or "copy", ev.pane)
end)

if not has_event then
  -- Every copy made from Lua passes here, whoever's plugin made it.
  ranma.copy = function(text)
    raw_copy(text)
    record(text, "lua")
  end

  -- Copy mode: the pane it was in, and the clipboard read back once it ends.
  local in_copy = nil
  ranma.every(POLL, function()
    local st = ranma.state()
    if st.mode == "copy" then
      if not in_copy then
        in_copy = st.focused
        read_clipboard(function(text) last_seen = text end)
      end
    elseif in_copy then
      local pane_id = in_copy
      in_copy = nil
      -- The yank goes to the terminal as OSC 52; give it a moment to land.
      ranma.defer(150, function()
        read_clipboard(function(text)
          if text ~= "" and text ~= last_seen then record(text, "copy mode", pane_id) end
        end)
      end)
    end
  end)
end

local function age(t)
  local s = os.time() - t
  if s < 60 then return "now" end
  if s < 3600 then return (s // 60) .. "m" end
  if s < 86400 then return (s // 3600) .. "h" end
  return (s // 86400) .. "d"
end

-- One line of a copy: line breaks as ↵, tabs as a space, other control
-- characters left out, cut with … (by character: it is UTF-8).
local function preview(text)
  local flat = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "↵"):gsub("\t", " "):gsub("[%c]", "")
  if utf8.len(flat) and utf8.len(flat) > PREVIEW then
    flat = flat:sub(1, (utf8.offset(flat, PREVIEW) or #flat + 1) - 1) .. "…"
  end
  return flat
end

local function size(text)
  local n = select(2, text:gsub("\n", "")) + 1
  if n > 1 then return n .. " lines" end
  return (utf8.len(text) or #text) .. " chars"
end

local state = { screen = nil, target = nil }

local function close()
  if state.screen then state.screen:close() end
  state.screen = nil
end

local function paste(text)
  local p = state.target and ranma.pane(state.target)
  if not (p and p:alive()) then
    raw_copy(text)
    return ranma.notify("clipboard: that pane is gone; copied instead")
  end
  close()
  p:paste(text)
end

-- Copy it again: the clipboard gets it, and it becomes the newest copy.
local function copy_again(i)
  local list = entries()
  local e = table.remove(list, i)
  if not e then return end
  e.time = os.time()
  table.insert(list, 1, e)
  save(list)
  last_seen = e.text
  raw_copy(e.text)
  ranma.notify("clipboard: copied")
end

local function index_of(id)
  for i, e in ipairs(entries()) do
    if tostring(e.id) == id then return i, e end
  end
end

local refresh, forget_all

local function body()
  local rows = {}
  for _, e in ipairs(entries()) do
    local lines = {}
    for line in (e.text .. "\n"):gmatch("(.-)\r?\n") do
      lines[#lines + 1] = line
      if #lines == DETAIL_LINES then break end
    end
    local where = e.program or e.title or ""
    if e.pane then where = where .. (where ~= "" and " · " or "") .. "pane " .. e.pane end
    local id = tostring(e.id)
    local function act(fn)
      return function()
        local i, it = index_of(id)
        if i then fn(i, it) end
      end
    end
    local do_paste = act(function(_, it) paste(it.text) end)
    local do_copy = act(function(i) copy_again(i); refresh() end)
    -- enter does what clipboard.enter says, and the other key does the other.
    local keys = ranma.get("clipboard.enter") == "copy"
        and { { "enter", "copy", do_copy }, { "p", "paste", do_paste } }
        or { { "enter", "paste", do_paste }, { "y", "copy", do_copy } }
    keys[#keys + 1] = { "d", "forget", act(function(i)
      local list = entries()
      table.remove(list, i)
      save(list)
      refresh()
    end), all = { "D", function() forget_all() end } }
    -- One line wraps in the preview; several show as lines, the first in view.
    local shown = #lines > 1 and { "log", lines = lines, at = 1 }
        or { "text", e.text, max = DETAIL_LINES // 4 }
    rows[#rows + 1] = {
      "row", id = id, name = preview(e.text), note = where,
      value = { age(e.time), "dim" },
      keys = keys,
      detail = {
        shown,
        { "facts", { "from", where ~= "" and where or "?" }, { "by", e.source or "?" },
          { "", size(e.text) }, { "", os.date("%H:%M %d %b", e.time) } },
      },
    }
  end
  return rows
end

-- Set once, as the screen opens: ranma 0.1.0's s:set cannot take a status
-- away again, and what it says does not change while the screen is up.
local function status()
  local why = (not has_event) and blind()
  if why then return { "yanks not kept: " .. why, "dim" } end
  return nil
end

local function count()
  local n = #entries()
  return n == 1 and "1 copy" or (n .. " copies")
end

refresh = function()
  if state.screen then state.screen:set { body = body(), count = count() } end
end

local function clear()
  save({})
  last_seen = nil
  refresh()
  ranma.notify("clipboard: history cleared")
end

-- Asked first: it cannot be undone.
forget_all = function()
  if not state.screen or #entries() == 0 then return end
  state.screen:ask {
    blocks = { { "text", "Forget all " .. count() .. "?", role = "urgent", strong = true } },
    keys = { { "y", "forget them", clear, role = "urgent" }, { "esc", "keep them" } },
  }
end

local function open()
  local p = ranma.pane()
  state.target = p and p.id
  state.screen = ranma.screen {
    title = "clipboard", chip = "CLIP", filter = "names", detail = 8, options = true,
    count = count(),
    status = status(),
    empty = "nothing copied yet",
    body = body(),
    card = {
      { "enter", "paste into the pane" },
      { "y", "copy again; to the top" },
      { "p", "paste, if enter copies" },
      { "d D", "forget it · all" },
    },
    on_close = function() state.screen = nil end,
  }
end

ranma.bind("ctrl+v", open, { desc = "clipboard", group = "plugins", exit = true })
-- For a key of your own: ranma.bind("C", function() ranma.emit("clipboard_open") end).
ranma.on("user:clipboard_open", function() open() end)
ranma.command("clipboard", open, { desc = "what was copied, to paste again" })
ranma.command("clipboard-clear", function()
  clear()
end, { desc = "forget the clipboard history" })
