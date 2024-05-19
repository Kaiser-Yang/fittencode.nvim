local api = vim.api

local Base = require('fittencode.base')
local Log = require('fittencode.log')

---@class Chat
---@field win? integer
---@field buffer? integer
---@field text string[]
---@field show function
---@field commit function
---@field is_repeated function
local M = {}

function M:new()
  local o = {
    text = {}
  }
  self.__index = self
  return setmetatable(o, self)
end

function M:show()
  if self.win == nil then
    if not self.buffer then
      self.buffer = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(self.buffer, 'FittenCodeChat')
    end

    vim.cmd('topleft vsplit')
    vim.cmd('vertical resize ' .. 40)
    self.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.win, self.buffer)

    api.nvim_set_option_value('filetype', 'markdown', { buf = self.buffer })
    api.nvim_set_option_value('modifiable', false, { buf = self.buffer })
    api.nvim_set_option_value('wrap', true, { win = self.win })
    api.nvim_set_option_value('linebreak', true, { win = self.win })
    api.nvim_set_option_value('cursorline', true, { win = self.win })
    api.nvim_set_option_value('spell', false, { win = self.win })
    api.nvim_set_option_value('number', false, { win = self.win })
    api.nvim_set_option_value('relativenumber', false, { win = self.win })
    api.nvim_set_option_value('conceallevel', 3, { win = self.win })

    Base.map('n', 'q', function()
      self:close()
    end, { buffer = self.buffer })

    if #self.text > 0 then
      -- api.nvim_set_option_value('modifiable', true, { buf = self.buffer })
      -- api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.text)
      api.nvim_win_set_cursor(self.win, { #self.text, 0 })
      -- api.nvim_set_option_value('modifiable', false, { buf = self.buffer })
    end
  end
end

function M:close()
  if self.win == nil then
    return
  end
  if api.nvim_win_is_valid(self.win) then
    api.nvim_win_close(self.win, true)
  end
  self.win = nil
  -- api.nvim_buf_delete(self.buffer, { force = true })
  -- self.buffer = nil
end

local stack = {}

local function push_stack(x)
  if #stack == 0 then
    table.insert(stack, x)
  else
    table.remove(stack)
  end
end

---@class ChatCommitOptions
---@field text? string|string[]
---@field linebreak? boolean
---@field force? boolean
---@field fenced_code? boolean

local function set_lines(self, lines)
  if self.buffer then
    api.nvim_set_option_value('modifiable', true, { buf = self.buffer })
    if #self.text == 0 then
      api.nvim_buf_set_lines(self.buffer, 0, -1, false, lines)
    else
      api.nvim_buf_set_lines(self.buffer, -1, -1, false, lines)
    end
    api.nvim_set_option_value('modifiable', false, { buf = self.buffer })
  end
  table.move(lines, 1, #lines, #self.text + 1, self.text)

  if api.nvim_win_is_valid(self.win) then
    api.nvim_win_set_cursor(self.win, { #self.text, 0 })
  end
end

---@param opts? ChatCommitOptions|string
function M:commit(opts)
  if not opts then
    return
  end

  if type(opts) == 'string' then
    opts = { text = opts }
  end

  local text = opts.text
  local linebreak = opts.linebreak
  local force = opts.force
  local fenced_code = opts.fenced_code

  local lines = nil
  if type(text) == 'string' then
    lines = vim.split(text, '\n')
  elseif type(text) == 'table' then
    lines = text
  else
    return
  end
  vim.tbl_map(function(x)
    if x:match('^```') then
      push_stack(x)
    end
  end, lines)
  if #stack > 0 then
    if not force then
      linebreak = false
    end
    if fenced_code then
      table.insert(lines, 1, '```')
    end
  end
  if linebreak and #self.text > 0 and #lines > 0 then
    if lines[1] ~= '' and not string.match(lines[1], '^```') and self.text[#self.text] ~= '' and not string.match(self.text[#self.text], '^```') then
      table.insert(lines, 1, '')
    end
  end
  set_lines(self, lines)
end

local function _sub_match(s, pattern)
  if s == pattern then
    return true
  end
  local rs = string.reverse(s)
  local rp = string.reverse(pattern)
  local i = 1
  while i <= #rs and i <= #rp do
    if rs:sub(i, i) ~= rp:sub(i, i) then
      break
    end
    i = i + 1
  end
  if i > #rs * 0.8 or i > #rp * 0.8 then
    return true
  end
  return false
end

function M:is_repeated(lines)
  -- TODO: improve this
  -- return _sub_match(self.text[#self.text], lines[1])
  return false
end

---@return string[]
function M:get_text()
  return self.text
end

---@return boolean
function M:has_text()
  return #self.text > 0
end

return M
