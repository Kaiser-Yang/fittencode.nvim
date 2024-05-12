local api = vim.api

local Log = require('fittencode.log')
local Path = require('fittencode.fs.path')

local M = {}

local NAME = 'FittenCodePrompt/Actions'

function M:new(o)
  o = o or {}
  o.name = NAME
  o.priority = 100
  setmetatable(o, self)
  self.__index = self
  return o
end

function M:is_available(type)
  return type:match('^' .. NAME)
end

function M:get_name()
  return self.name
end

function M:get_priority()
  return self.priority
end

---@param ctx PromptContext
---@return Prompt?
function M:execute(ctx)
  if (not ctx.solved_prefix and not ctx.solved_content) and (not api.nvim_buf_is_valid(ctx.buffer) or ctx.range == nil) then
    return
  end

  local filename = ''
  if ctx.buffer then
    filename = Path.name(ctx.buffer)
  end

  local within_the_line = false
  local content = ''

  local prefix = ''
  if ctx.solved_prefix then
    prefix = ctx.solved_prefix
  else
    -- FIXME: Improve prompt construction! full content with line:col info?
    ---@diagnostic disable-next-line: param-type-mismatch
    if ctx.solved_content then
      content = ctx.solved_content
    else
      -- if ctx.range[1] == ctx.range[2] then
      -- content = api.nvim_buf_get_lines(ctx.buffer, ctx.range[1], ctx.range[1] + 1, false)[1]
      -- content = table.concat(api.nvim_buf_get_text(ctx.buffer, 0, 0, -1, -1, {}), '\n')
      content = table.concat(api.nvim_buf_get_text(ctx.buffer, ctx.range[1], 0, ctx.range[2], -1, {}), '\n')
    end
    local filetype = ctx.filetype or ''
    -- Log.debug('Action Filetype: {}', filetype)
    content = '```' .. filetype .. '\n' .. content .. '\n```'
    -- Log.debug('Action Content: {}', content)
    local language = ctx.action_opts.language or filetype
    -- Log.debug('Action Language: {}', language)
    local map_action_prompt = {
      StartChat = 'Answers the question above',
      DocumentCode = 'Document the code above',
      EditCode = ctx.prompt,
      ExplainCode = 'Explain the code above',
      FindBugs = 'Find bugs in the code above',
      GenerateUnitTest = function(opts)
        opts = opts or {}
        if opts.test_framework then
          return 'Generate a unit test for the code above with ' .. opts.test_framework
        end
        return 'Generate a unit test for the code above'
      end,
      ImplementFeatures = function(opts)
        opts = opts or {}
        local feature_type = opts.feature_type or 'code'
        return 'Implement the ' .. feature_type .. ' mentioned in the code above'
      end,
      ImproveCode = 'Improve the code above',
      RefactorCode = 'Refactor the code above',
    }
    local key = map_action_prompt[ctx.prompt_ty:sub(#NAME + 2)]
    local lang_suffix = #language > 0 and ' in ' .. language or ''
    local prompt = ctx.prompt or ((type(key) == 'function' and key(ctx.action_opts) or key) .. lang_suffix)
    -- Log.debug('Action Prompt: {}', prompt)
    prefix = content .. '\n`' .. 'Dear FittenCode, Please ' .. prompt .. ':\n'
  end
  local suffix = ''

  -- Log.debug('Action Prefix: {}', prefix)
  -- Log.debug('Action Suffix: {}', suffix)

  return {
    name = self.name,
    priority = self.priority,
    filename = filename,
    content = content,
    prefix = prefix,
    suffix = suffix,
    within_the_line = within_the_line,
  }
end

return M
