--- blink-cmp-layout.nvim
---
--- Lays out blink.cmp's completion, documentation and signature windows so they
--- stay clear of the line being edited, instead of following the cursor and
--- covering it.
---
--- Must be set up *after* `require('blink.cmp').setup()`: blink builds its
--- windows from the merged config the first time they are required, and this
--- plugin requires them as soon as it is set up.

local settings = require('blink-cmp-layout.config')
local windows = require('blink-cmp-layout.windows')

local M = {}

--- @type blink-cmp-layout.Config
M.config = settings.defaults

--- Keeps the signature help window up for as long as the cursor is inside a
--- call. blink only re-asks the server while it already holds a signature
--- context, and it drops that context whenever a request comes back empty, so
--- one empty answer -- moving past the closing paren, say -- leaves the window
--- shut until a trigger character or a fresh InsertEnter starts a new context.
--- Asking on every insert-mode cursor move makes it recover on its own: blink
--- cancels the in-flight request each time, and closes the window whenever the
--- server has nothing to say about the position.
local function follow_cursor()
  local group = vim.api.nvim_create_augroup('BlinkCmpLayoutSignature', { clear = true })

  local config = M.config.signature
  if not (config.enabled and config.follow_cursor) then return end
  if not require('blink.cmp.config').signature.enabled then return end

  vim.api.nvim_create_autocmd('CursorMovedI', {
    group = group,
    desc = 'blink-cmp-layout: keep signature help up while the cursor is inside a call',
    callback = function() require('blink.cmp.signature.trigger').show() end,
  })
end

--- @param opts? blink-cmp-layout.Config
function M.setup(opts)
  M.config = settings.extend(opts)

  windows.install(function() return M.config end)
  follow_cursor()
end

return M
