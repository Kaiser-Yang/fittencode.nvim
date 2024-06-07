local api = vim.api

local Config = require('fittencode.config')
local Log = require('fittencode.log')

local M = {}

function M:new(o)
  o = o or {}
  o.name = 'FittenCodePrompt/Default'
  o.priority = 1
  setmetatable(o, self)
  self.__index = self
  return o
end

function M:is_available(_)
  return true
end

function M:get_name()
  return self.name
end

function M:get_priority()
  return self.priority
end

---@class PromptContextDefault : PromptContext
---@field max_lines? number
---@field max_chars? number

---@param ctx PromptContextDefault
---@return Prompt?
function M:execute(ctx)
  if not api.nvim_buf_is_valid(ctx.buffer) or ctx.row == nil or ctx.col == nil then
    return
  end

  local count = 0
  local lines = api.nvim_buf_get_lines(ctx.buffer, 0, -1, false)
  vim.tbl_map(function(line)
    count = count + #line
  end, lines)
  if count > Config.options.prompt.max_characters then
    return
  end

  local filename = api.nvim_buf_get_name(ctx.buffer)
  if filename == nil or filename == '' then
    filename = 'NONAME'
  end

  local row = ctx.row
  local col = ctx.col
  ---@diagnostic disable-next-line: param-type-mismatch
  local curllen = string.len(api.nvim_buf_get_lines(ctx.buffer, row, row + 1, false)[1])
  local within_the_line = col ~= curllen
  ---@diagnostic disable-next-line: param-type-mismatch
  local prefix = table.concat(api.nvim_buf_get_text(ctx.buffer, 0, 0, row, col, {}), '\n')
  ---@diagnostic disable-next-line: param-type-mismatch
  local suffix = table.concat(api.nvim_buf_get_text(ctx.buffer, row, col, -1, -1, {}), '\n')

  return {
    name = self.name,
    priority = self.priority,
    filename = filename,
    prefix = prefix,
    suffix = suffix,
    within_the_line = within_the_line,
  }
end

return M
