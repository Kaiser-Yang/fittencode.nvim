local M = {}

---@param opts? FittenCodeOptions
function M.setup(opts)
  if vim.fn.has('nvim-0.8.0') == 0 then
    local msg = 'fittencode.nvim requires Neovim >= 0.8.0.'
    vim.api.nvim_err_writeln(msg)
    return
  end

  local Config = require('fittencode.config')
  Config.setup(opts)

  require('fittencode.log').setup()
  require('fittencode.rest.manager').setup()
  require('fittencode.engines').setup()
  require('fittencode.sessions').setup()
  require('fittencode.prompt_providers').setup()
  require('fittencode.color').setup_highlight()
  local Bindings = require('fittencode.bindings')
  Bindings.setup_commands()

  if Config.options.completion_mode == 'inline' then
    Bindings.setup_autocmds()
    Bindings.setup_keyfilters()
    if Config.options.use_default_keymaps then
      Bindings.setup_keymaps()
    end
  elseif Config.options.completion_mode == 'source' then
    require('fittencode.sources').setup()
  end

  require('fittencode.sessions').load_last_session()
end

setmetatable(M, {
  __index = function(_, k)
    return function(...)
      return require('fittencode.api').api[k](...)
    end
  end,
})

return M
