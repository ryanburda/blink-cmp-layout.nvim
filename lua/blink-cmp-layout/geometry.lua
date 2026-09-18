--- The measuring half of the layout: where the editable area of a window is,
--- and which rows a float may take beside a given line.
---
--- Everything here is in editor-relative (0-indexed) coordinates, which is how
--- the floats are anchored -- `relative = 'editor'` -- so that they can be
--- placed against the window being edited rather than against the cursor.
---
--- Note that a float's `row` / `col` address its outer corner: the border is
--- drawn inside them, and blink's `get_height()` / `get_width()` count it,
--- while `set_height()` / `set_width()` take the inner content size.

--- @class blink-cmp-layout.Pane
--- @field row number Topmost editor row of the text area
--- @field col number Leftmost editor column of the text area
--- @field height number
--- @field width number

--- A run of free rows a window may be placed in, inclusive at both ends.
--- `anchor` says which end the window is held against, so it grows away from
--- whatever it was stacked onto.
--- @class blink-cmp-layout.Band
--- @field first number
--- @field last number
--- @field anchor 'top' | 'bottom'

local M = {}

--- The text area of the current window.
---
--- `getwininfo()` is what makes this exact: `nvim_win_get_height()` counts the
--- winbar as part of the window, so it would push everything one row down in
--- any window that has one, and `textoff` is exactly the gutter -- the
--- 'foldcolumn', 'signcolumn' and number column -- so starting past it leaves
--- the line numbers visible beside the windows. The right edge is unchanged:
--- the box is narrower by the same amount it was shifted.
---
--- @param align 'text' | 'window'
--- @return blink-cmp-layout.Pane
function M.pane(align)
  local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local gutter = align == 'text' and info.textoff or 0

  return {
    row = info.winrow - 1 + info.winbar,
    col = info.wincol - 1 + gutter,
    height = info.height,
    width = info.width - gutter,
  }
end

--- The rows held clear between the cursor line and the windows, clamped so the
--- roomier side of the cursor still has a row left for the window itself --
--- which matters when the gap follows a large 'scrolloff' (999, say, to keep
--- the cursor centered).
---
--- @param pane blink-cmp-layout.Pane
--- @param cursor number Cursor's 1-indexed screen line within the pane
--- @param wanted number | nil
--- @return number
function M.gap(pane, cursor, wanted)
  if not wanted or wanted <= 0 then return 0 end
  return math.min(wanted, math.max(math.max(pane.height - cursor, cursor - 1) - 1, 0))
end

--- The width the windows share: the pane, or the cap when the pane is wider.
---
--- @param pane blink-cmp-layout.Pane
--- @param max number | nil
--- @return number
function M.width(pane, max)
  if not max or max <= 0 then return pane.width end
  return math.min(pane.width, max)
end

--- The free rows on either side of the cursor line, once the gap is taken out.
--- Neither band includes the cursor line itself.
---
--- @param pane blink-cmp-layout.Pane
--- @param cursor number
--- @param gap number
--- @return table<'above' | 'below', blink-cmp-layout.Band>
function M.cursor_bands(pane, cursor, gap)
  local cursor_row = pane.row + cursor - 1

  return {
    above = { first = pane.row, last = cursor_row - gap - 1, anchor = 'bottom' },
    below = { first = cursor_row + gap + 1, last = pane.row + pane.height - 1, anchor = 'top' },
  }
end

--- @param band blink-cmp-layout.Band
--- @return number Rows the band holds; zero or less when it holds none
function M.room(band) return band.last - band.first + 1 end

--- Where a window of `height` rows sits in a band, kept inside the pane for the
--- case where even a shrunk-to-one-row window does not fit.
---
--- @param band blink-cmp-layout.Band
--- @param height number Outer height, border included
--- @param pane blink-cmp-layout.Pane
--- @return number
function M.row(band, height, pane)
  local row = band.anchor == 'bottom' and band.last - height + 1 or band.first
  return math.max(math.min(row, pane.row + pane.height - height), pane.row)
end

--- Picks a band for a window that wants `wanted` rows: the first one in
--- preference order that holds it outright, else the roomiest.
---
--- @param bands blink-cmp-layout.Band[] In order of preference
--- @param wanted number
--- @return blink-cmp-layout.Band | nil
function M.pick(bands, wanted)
  local fallback, fallback_room = nil, -math.huge

  for _, band in ipairs(bands) do
    local room = M.room(band)
    if room >= wanted then return band end
    if room > fallback_room then fallback, fallback_room = band, room end
  end

  return fallback
end

return M
