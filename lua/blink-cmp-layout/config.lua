--- Defaults, and the resolution of the forms they may take.
---
--- `height` accepts a number or a function returning one, called with the pane
--- being placed against -- so a layout can follow whatever the window being
--- edited holds, rather than a value fixed at setup.

--- @alias blink-cmp-layout.Measure number | fun(pane: blink-cmp-layout.Pane): number | nil

--- @class blink-cmp-layout.Config
--- @field enabled boolean | fun(): boolean Checked every time a window is placed
--- @field max_width number Widest the menu and documentation window may be *together*, borders included; zero or less for no cap
--- @field gap number Rows held clear between the cursor line and the windows
--- @field height blink-cmp-layout.Measure Rows the menu and documentation window are held at
--- @field align 'text' | 'window' Left edge: past the gutter, or at the window's own edge
--- @field direction ('below' | 'above')[] Which side of the cursor the pair prefers while the signature help window is closed; while it is open, the pair instead follows whichever side the signature help window landed on
--- @field menu blink-cmp-layout.MenuConfig
--- @field documentation blink-cmp-layout.DocumentationConfig
--- @field signature blink-cmp-layout.SignatureConfig

--- @class blink-cmp-layout.MenuConfig
--- @field enabled boolean Placing the menu is what drives the rest; with this off nothing else is placed either
--- @field width number Share of the width the menu takes: a fraction of it when <= 1, else a column count

--- @class blink-cmp-layout.DocumentationConfig
--- @field enabled boolean When off, blink places the documentation window itself

--- @class blink-cmp-layout.SignatureConfig
--- @field enabled boolean When off, blink places the signature window itself
--- @field follow_cursor boolean Re-ask the server for signature help on every insert-mode cursor move

local M = {}

--- @type blink-cmp-layout.Config
M.defaults = {
  enabled = true,
  max_width = 120,
  gap = 8,
  height = function() return require('blink.cmp.config').completion.menu.max_height end,
  align = 'text',
  direction = { 'below', 'above' },
  menu = {
    enabled = true,
    width = 0.5,
  },
  documentation = {
    enabled = true,
  },
  signature = {
    enabled = true,
    follow_cursor = true,
  },
}

local function a_number(value, name)
  if type(value) ~= 'number' then
    error(("blink-cmp-layout: `%s` must be a number, got %s"):format(name, vim.inspect(value)))
  end
end

local function one_of(value, name, allowed)
  if not vim.tbl_contains(allowed, value) then
    error(("blink-cmp-layout: `%s` must be one of %s, got %s"):format(name, vim.inspect(allowed), vim.inspect(value)))
  end
end

--- @param opts? blink-cmp-layout.Config
--- @return blink-cmp-layout.Config
function M.extend(opts)
  local config = vim.tbl_deep_extend('force', M.defaults, opts or {})

  a_number(config.max_width, 'max_width')
  a_number(config.gap, 'gap')
  one_of(config.align, 'align', { 'text', 'window' })
  if type(config.direction) ~= 'table' or #config.direction == 0 then
    error('blink-cmp-layout: `direction` must be a non-empty list of "below" / "above"')
  end
  for _, direction in ipairs(config.direction) do
    one_of(direction, 'direction', { 'below', 'above' })
  end

  return config
end

--- Resolves either of the forms a measurement may take down to a number.
---
--- @param measure blink-cmp-layout.Measure
--- @param pane blink-cmp-layout.Pane
--- @return number | nil
function M.measure(measure, pane)
  if type(measure) == 'function' then measure = measure(pane) end
  if type(measure) ~= 'number' then return nil end
  return measure
end

return M
