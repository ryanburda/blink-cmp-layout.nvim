--- Defaults, and the resolution of the option forms they may take.
---
--- Every measurement below accepts a number, the name of a vim option to read
--- it from, or a function returning either -- so a layout can follow whatever
--- the buffer being edited is set to, rather than a value fixed at startup.

--- @alias blink-cmp-layout.Measure number | string | fun(pane: blink-cmp-layout.Pane): number | string | nil

--- @class blink-cmp-layout.Config
--- @field enabled boolean | fun(): boolean Checked every time a window is placed
--- @field max_width blink-cmp-layout.Measure Widest the menu and documentation window may be *together*, borders included
--- @field gap blink-cmp-layout.Measure Rows held clear between the cursor line and the windows
--- @field height blink-cmp-layout.Measure Rows the menu and documentation window are held at
--- @field align 'text' | 'window' Left edge: past the gutter, or at the window's own edge
--- @field direction ('below' | 'above')[] Which side of the cursor the pair prefers
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
--- @field placement 'near' | 'far' Which edge of the menu it stacks onto: the one facing the cursor, or away from it
--- @field direction ('above' | 'below')[] Which side of the cursor it prefers while the menu is closed
--- @field follow_cursor boolean Re-ask the server for signature help on every insert-mode cursor move

local M = {}

--- @type blink-cmp-layout.Config
M.defaults = {
  enabled = true,
  max_width = 'colorcolumn',
  gap = 'scrolloff',
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
    placement = 'near',
    direction = { 'above', 'below' },
    follow_cursor = true,
  },
}

local function one_of(value, name, allowed)
  if not vim.tbl_contains(allowed, value) then
    error(("blink-cmp-layout: `%s` must be one of %s, got %s"):format(name, vim.inspect(allowed), vim.inspect(value)))
  end
end

--- @param opts? blink-cmp-layout.Config
--- @return blink-cmp-layout.Config
function M.extend(opts)
  local config = vim.tbl_deep_extend('force', M.defaults, opts or {})

  one_of(config.align, 'align', { 'text', 'window' })
  one_of(config.signature.placement, 'signature.placement', { 'near', 'far' })
  if type(config.direction) ~= 'table' or #config.direction == 0 then
    error('blink-cmp-layout: `direction` must be a non-empty list of "below" / "above"')
  end
  for _, direction in ipairs(config.direction) do
    one_of(direction, 'direction', { 'below', 'above' })
  end
  for _, direction in ipairs(config.signature.direction) do
    one_of(direction, 'signature.direction', { 'below', 'above' })
  end

  return config
end

--- Reads a vim option as a number, in the scope it belongs to, so that a
--- window- or buffer-local value wins over the global one.
---
--- 'colorcolumn' gets special treatment: it holds a comma separated list whose
--- entries may be `+n` / `-n`, relative to 'textwidth'. Only the first entry is
--- used, and a relative entry with no 'textwidth' set has no value at all.
---
--- @param name string
--- @return number | nil
function M.option(name)
  local ok, info = pcall(vim.api.nvim_get_option_info2, name, {})
  if not ok then return nil end

  local scope = info.scope == 'win' and { win = 0 } or info.scope == 'buf' and { buf = 0 } or {}
  local value = vim.api.nvim_get_option_value(name, scope)

  if type(value) == 'number' then return value end
  if type(value) ~= 'string' then return nil end

  local entry = vim.split(value, ',')[1] or ''
  local offset = entry:match('^[+-]%d+$')
  if not offset then return tonumber(entry) end

  local textwidth = vim.bo.textwidth
  return textwidth > 0 and textwidth + tonumber(offset) or nil
end

--- Resolves any of the forms a measurement may take down to a number.
---
--- @param measure blink-cmp-layout.Measure
--- @param pane blink-cmp-layout.Pane
--- @return number | nil
function M.measure(measure, pane)
  if type(measure) == 'function' then measure = measure(pane) end
  if type(measure) == 'string' then measure = M.option(measure) end
  if type(measure) ~= 'number' then return nil end
  return measure
end

return M
