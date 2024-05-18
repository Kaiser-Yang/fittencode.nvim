local M = {}

---@class FittenCodeOptions
M.options = {
  -- Same options as `fittentech.fitten-code` in vscode
  action = {
    document_code = {
      -- Show "Fitten Code - Document Code" in the editor context menu, when you right-click on the code.
      show_in_editor_context_menu = true,
    },
    edit_code = {
      -- Show "Fitten Code - Edit Code" in the editor context menu, when you right-click on the code.
      show_in_editor_context_menu = true,
    },
    explain_code = {
      -- Show "Fitten Code - Explain Code" in the editor context menu, when you right-click on the code.
      show_in_editor_context_menu = true,
    },
    find_bugs = {
      -- Show "Fitten Code - Find Bugs" in the editor context menu, when you right-click on the code.
      show_in_editor_context_menu = true,
    },
    generate_unit_test = {
      -- Show "Fitten Code - Generate UnitTest" in the editor context menu, when you right-click on the code.
      show_in_editor_context_menu = true,
    },
    start_chat = {
      -- Show "Fitten Code - Start Chat" in the editor context menu, when you right-click on the code.
      show_in_editor_context_menu = true,
    },
  },
  disable_specific_inline_completion = {
    -- Disable auto-completion for some specific file suffixes by entering them below
    -- For example, `suffixes = {'lua', 'cpp'}`
    suffixes = {},
  },
  inline_completion = {
    -- Enable inline code completion.
    ---@type boolean
    enable = true,
    -- Disable auto completion when the cursor is within the line.
    ---@type boolean
    disable_completion_within_the_line = false,
    -- Disable auto completion when pressing Backspace or Delete.
    ---@type boolean
    disable_completion_when_delete = false,
  },
  delay_completion = {
    -- Delay time for inline completion (in milliseconds).
    ---@type integer
    delaytime = 0,
  },
  -- Enable/Disable the default keymaps in inline completion.
  use_default_keymaps = true,
  -- Setting for source completion.
  ---@class SourceCompletionOptions
  source_completion = {
    -- Enable source completion.
    enable = true,
    -- Completion engines available:
    -- * 'cmp' > https://github.com/hrsh7th/nvim-cmp
    -- * 'coc' > https://github.com/neoclide/coc.nvim
    -- * 'ycm' > https://github.com/ycm-core/YouCompleteMe
    -- * 'omni' > Neovim builtin ommifunc
    engine = 'cmp',
    disable_specific_source_completion = {
      -- Disable completion for some specific file suffixes by entering them below
      -- For example, `suffixes = {'lua', 'cpp'}`
      suffixes = {},
    },
  },
  -- Set the mode of the completion.
  -- Available options:
  -- - 'inline' (VSCode style inline completion)
  -- - 'source' (integrates into other completion plugins)
  completion_mode = 'inline',
  rest = {
    -- Rest backend to use. Available options:
    -- * 'curl'
    -- * 'libcurl'
    -- * 'libuv'
    backend = 'curl',
  },
  syntax_highlighting = {
    -- Use the Neovim Theme colors for syntax highlighting in the diff viewer.
    use_neovim_colors = false,
  },
  ---@class LogOptions
  log = {
    -- Log level.
    level = vim.log.levels.WARN,
    -- Max log file size in MB, default is 10MB
    max_size = 10,
    -- Create new log file on startup, for debugging purposes.
    new_file_on_startup = false,
    -- TODO: Aynchronous logging.
    async = true,
  },
}

-- Private options
M.internal = {
  virtual_text = {
    inline = vim.fn.has('nvim-0.10') == 1,
  },
}

---@param opts? FittenCodeOptions
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.options, opts or {})
end

return M
