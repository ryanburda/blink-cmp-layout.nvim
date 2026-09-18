--- The placing half of the layout: replacements for the `update_position`
--- functions of blink's three floats.
---
--- blink exposes no options for any of this, so the functions are replaced on
--- the module tables. Every caller looks them up at call time, so replacing
--- them here covers all of them, and the originals stay available for the
--- cases this plugin does not handle -- the cmdline completion menu above all,
--- which is anchored to the command line rather than to a window.

local settings = require('blink-cmp-layout.config')
local geometry = require('blink-cmp-layout.geometry')

local M = {}

--- @type fun(): blink-cmp-layout.Config
local get_config

local menu, docs, signature
local default = {}
local installed = false

--- The pane the menu last placed itself against. The other two windows reuse
--- it rather than measuring again, both so that all three agree and because
--- they may be repositioned (on scroll, say) at a moment when the current
--- window is not the one being edited.
--- @type blink-cmp-layout.Pane | nil
local pane

--- The cmdline completion menu is anchored to the command line, not to a
--- window, so it is always left to blink.
local function managed(config)
  if vim.api.nvim_get_mode().mode == 'c' then return false end

  local enabled = config.enabled
  if type(enabled) == 'function' then enabled = enabled() end
  return enabled ~= false
end

--- The width the menu and the documentation window share, borders included.
local function box_width(config)
  return geometry.width(pane, settings.measure(config.max_width, pane))
end

local function place_menu()
  local config = get_config()
  if not managed(config) or not config.menu.enabled then return default.menu() end

  local win = menu.win
  if not win:is_open() then return end

  pane = geometry.pane(config.align)
  local border = win:get_border_size()

  -- a width taken from the pane, rather than blink's fit-to-content and
  -- fit-to-the-space-around-the-cursor sizing
  local share = config.menu.width
  local width = share <= 1 and math.floor(box_width(config) * share) or math.min(share, box_width(config))
  win:set_width(math.max(math.floor(width) - border.horizontal, 1))

  local cursor = vim.fn.winline()
  local gap = geometry.gap(pane, cursor, settings.measure(config.gap, pane))
  local bands = geometry.cursor_bands(pane, cursor, gap)

  local height = settings.measure(config.height, pane)
    or require('blink.cmp.config').completion.menu.max_height

  -- the preferred side of the cursor, unless the window does not fit there
  local preferred = {}
  for _, direction in ipairs(config.direction) do
    table.insert(preferred, bands[direction])
  end
  local band = geometry.pick(preferred, height + border.vertical)

  -- shrink rather than cover the cursor line when that side is shallow; a
  -- window too short for even one row leaves the menu overlapping, as there is
  -- nowhere else for it to go
  win:set_height(math.max(math.min(height, geometry.room(band) - border.vertical), 1))

  win:set_win_config({
    relative = 'editor',
    row = geometry.row(band, win:get_height(), pane),
    col = pane.col,
  })

  -- repositions the documentation and signature windows against the menu
  menu.position_update_emitter:emit()
end

local function place_docs()
  local config = get_config()
  -- blink places the documentation window relative to the menu window itself,
  -- so its own placement follows the menu wherever this plugin put it
  if not managed(config) or not config.menu.enabled or not config.documentation.enabled then
    return default.docs()
  end

  local win = docs.win
  if not win:is_open() or not menu.win:is_open() or pane == nil then return end

  local menu_config = vim.api.nvim_win_get_config(menu.win:get_win())
  local border = win:get_border_size()
  local col = menu_config.col + menu.win:get_width()

  -- rather than render a sliver, give up if the menu leaves no room
  local width_left = pane.col + box_width(config) - col
  if width_left <= border.horizontal + 1 then return win:close() end

  win:set_width(width_left - border.horizontal)

  -- matching the menu's height lets it share the menu's row outright,
  -- whichever side of the cursor the menu settled on
  win:set_height(math.max(menu.win:get_height() - border.vertical, 1))

  win:set_win_config({ relative = 'editor', row = menu_config.row, col = col })
end

--- The bands the signature window may take, in order of preference: stacked
--- onto the menu when it is open, or beside the cursor when it is not.
local function signature_bands(config, box, cursor, gap)
  local cursor_row = box.row + cursor - 1

  if not menu.win:is_open() then
    local bands = geometry.cursor_bands(box, cursor, gap)
    local preferred = {}
    for _, direction in ipairs(config.signature.direction) do
      table.insert(preferred, bands[direction])
    end
    return preferred
  end

  local menu_config = vim.api.nvim_win_get_config(menu.win:get_win())
  local first = menu_config.row
  local last = first + menu.win:get_height() - 1
  local box_last = box.row + box.height - 1
  local menu_below = first > cursor_row

  -- The edge of the menu that faces the cursor is the gap, which holds no
  -- text; the far edge is whatever is left of the pane beyond the menu. Either
  -- way the window ends up stacked against the menu, so it is on screen
  -- whenever the menu is, and neither band includes the cursor line itself.
  local near = menu_below and { first = cursor_row + 1, last = first - 1, anchor = 'bottom' }
    or { first = last + 1, last = cursor_row - 1, anchor = 'top' }
  local far = menu_below and { first = last + 1, last = box_last, anchor = 'top' }
    or { first = box.row, last = first - 1, anchor = 'bottom' }

  if config.signature.placement == 'far' then return { far, near } end
  return { near, far }
end

local function place_signature()
  local config = get_config()

  -- the signature window is placed against the menu, so a menu left to blink
  -- takes the signature window with it
  if not managed(config) or not config.signature.enabled or not config.menu.enabled then
    -- blink's own placement asserts the menu is window-relative, which a menu
    -- this plugin placed is not, so such a menu leaves the signature window
    -- where it is rather than crashing on the assert
    local menu_config = menu.win:is_open() and vim.api.nvim_win_get_config(menu.win:get_win())
    if menu_config and menu_config.relative ~= 'win' then return end
    return default.signature()
  end

  local win = signature.win
  if not win:is_open() then return end

  -- while the menu is open the two must agree on a pane, as they are placed
  -- against each other
  local box = (menu.win:is_open() and pane) or geometry.pane(config.align)
  local border = win:get_border_size()

  -- Same cap as the menu, and applied the same way: to the whole window,
  -- border included. blink's own `signature.window.max_width` is a plain
  -- number, fixed at setup, so the live value is written into the window's
  -- config before it sizes itself -- that way the text wraps to the cap and
  -- the height it settles on accounts for the wrapping.
  local max_width = geometry.width(box, settings.measure(config.max_width, box))
  win.config.max_width = math.max(max_width - border.horizontal, 1)
  win:update_size()

  local cursor = vim.fn.winline()
  local gap = geometry.gap(box, cursor, settings.measure(config.gap, box))
  local bands = signature_bands(config, box, cursor, gap)

  for _, band in ipairs(bands) do
    -- anything shallower than this renders as a sliver, so try the next
    if geometry.room(band) > border.vertical then
      win:set_height(math.max(math.min(win:get_height(), geometry.room(band)) - border.vertical, 1))
      return win:set_win_config({
        relative = 'editor',
        row = geometry.row(band, win:get_height(), box),
        col = box.col,
      })
    end
  end

  -- nowhere to put it
  win:close()
end

--- @param config_provider fun(): blink-cmp-layout.Config
function M.install(config_provider)
  get_config = config_provider
  if installed then return end
  installed = true

  menu = require('blink.cmp.completion.windows.menu')
  docs = require('blink.cmp.completion.windows.documentation')

  default.menu = menu.update_position
  default.docs = docs.update_position

  menu.update_position = place_menu
  docs.update_position = place_docs

  if not require('blink.cmp.config').signature.enabled then return end

  signature = require('blink.cmp.signature.window')
  default.signature = signature.update_position
  signature.update_position = place_signature

  local config = get_config()
  if config.menu.enabled and not config.signature.enabled then
    vim.notify(
      'blink-cmp-layout: `signature.enabled = false` leaves the signature window unplaced while '
        .. 'the menu is managed, as blink requires a window-relative menu; disable `menu.enabled` '
        .. 'here, or `signature.enabled` in blink.cmp',
      vim.log.levels.WARN
    )
  end
end

return M
