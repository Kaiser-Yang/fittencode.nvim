local M = {}

function M.setup()
  if vim.fn.has('nvim-0.10') == 0 then
    vim.api.nvim_echo({
      { 'fittencode.nvim requires Neovim >= 0.10.0 with support for inline virtual text.', 'ErrorMsg' },
    }, true, {})
    return
  end

  local Log = require('fittencode.log')
  local Sessions = require('fittencode.sessions')
  local Bindings = require('fittencode.bindings')
  local Tasks = require('fittencode.tasks')
  local Color = require('fittencode.color')

  Tasks.setup()
  Color.setup_highlight()
  Bindings.setup_autocmds()
  Bindings.setup_commands()
  Bindings.setup_keymaps()

  Sessions.load_last_session()
end

return M
