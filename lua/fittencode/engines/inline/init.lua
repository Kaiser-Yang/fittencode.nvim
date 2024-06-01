local api = vim.api

local Base = require('fittencode.base')
local Config = require('fittencode.config')
local Color = require('fittencode.color')
local Lines = require('fittencode.views.lines')
local Log = require('fittencode.log')
local Model = require('fittencode.engines.inline.model')
local Sessions = require('fittencode.sessions')
local Status = require('fittencode.status')
local SuggestionsPreprocessing = require('fittencode.suggestions_preprocessing')
local TaskScheduler = require('fittencode.tasks')
local PromptProviders = require('fittencode.prompt_providers')

local schedule = Base.schedule

local SC = Status.C

local M = {}

---@class InlineModel
local model = nil

---@class TaskScheduler
local tasks = nil

---@type Status
local status = nil

function M.setup()
  model = Model:new()
  tasks = TaskScheduler:new()
  tasks:setup()
  status = Status:new({ tag = 'InlineEngine' })
end

local function suggestions_modify_enabled()
  if not M.is_inline_enabled() then
    return false
  end

  if not M.has_suggestions() then
    return false
  end

  return true
end

---@param task_id integer
---@param suggestions? Suggestions
---@return Suggestions?
local function process_suggestions(task_id, suggestions)
  local window = api.nvim_get_current_win()
  local buffer = api.nvim_win_get_buf(window)
  local row, col = Base.get_cursor(window)
  if not tasks:match_clean(task_id, row, col) then
    return
  end

  if not suggestions or #suggestions == 0 then
    return
  end

  return SuggestionsPreprocessing.run({
    window = window,
    buffer = buffer,
    suggestions = suggestions,
  })
end

---@param ss SuggestionsSegments
---@return RenderVirtTextOptions?
local function make_virt_opts(ss)
  if Config.options.inline_completion.accept_mode == 'commit' then
    return {
      lines = {
        ss.changes,
      }
    }
  elseif Config.options.inline_completion.accept_mode == 'stage' then
    return {
      lines = {
        ss.stage,
        ss.changes
      },
      hls = {
        { Color.FittenSuggestionStage, Color.FittenSuggestionStageSpacesLine },
        { Color.FittenSuggestion,      Color.FittenSuggestionSpacesLine },
      },
    }
  end
end

local function render_virt_text_segments(segments)
  if not segments then
    return
  end
  Lines.render_virt_text(make_virt_opts(segments))
end

local function apply_new_suggestions(task_id, row, col, suggestions)
  if suggestions then
    model:recalculate({
      task_id = task_id,
      row = row,
      col = col,
      suggestions = suggestions,
    })
    if suggestions_modify_enabled() then
      render_virt_text_segments(model:get_suggestions_segments())
    end
  end
end

---@param row integer
---@param col integer
---@param on_success? function
---@param on_error? function
local function _generate_one_stage(row, col, on_success, on_error)
  status:update(SC.GENERATING)

  local task_id = tasks:create(row, col)
  Sessions.request_generate_one_stage(task_id, PromptProviders.get_current_prompt_ctx(), function(id, _, suggestions)
    local processed = process_suggestions(id, suggestions)
    if processed then
      status:update(SC.SUGGESTIONS_READY)
      apply_new_suggestions(task_id, row, col, processed)
      schedule(on_success, processed)
    else
      status:update(SC.NO_MORE_SUGGESTIONS)
      schedule(on_success)
      Log.debug('No More Suggestions')
    end
  end, function()
    status:update(SC.ERROR)
    schedule(on_error)
  end)
end

---@type uv_timer_t
local generate_one_stage_timer = nil

---@param row integer
---@param col integer
---@param force? boolean
---@param delaytime? integer
---@param on_success? function
---@param on_error? function
function M.generate_one_stage(row, col, force, delaytime, on_success, on_error)
  if not force and model:cache_hit(row, col) and M.has_suggestions() then
    status:update(SC.SUGGESTIONS_READY)
    render_virt_text_segments(model:get_suggestions_segments())
    schedule(on_success, model:make_new_trim_commmited_suggestions())
    return
  else
    Log.debug('NO CACHE HIT')
  end

  if suggestions_modify_enabled() then
    Lines.clear_virt_text()
  end
  model:reset()

  if not Sessions.ready_for_generate() then
    Log.debug('Not ready for generate')
    schedule(on_error)
    return
  end

  if delaytime == nil then
    delaytime = Config.options.delay_completion.delaytime
  end
  Log.debug('Delay completion request for delaytime: {} ms', delaytime)

  Base.debounce(generate_one_stage_timer, function()
    _generate_one_stage(row, col, on_success, on_error)
  end, delaytime)
end

---@return boolean
function M.has_suggestions()
  return model:has_suggestions()
end

---@return SuggestionsCache
function M.get_suggestions()
  return model:get_suggestions()
end

local function generate_one_stage_at_cursor(on_success, on_error)
  M.reset()

  local row, col = Base.get_cursor()
  M.generate_one_stage(row, col, true, 0, on_success, on_error)
end

-- When manually triggering completion, if no suggestions are generated, a prompt will appear to the right of the cursor.
function M.triggering_completion()
  Log.debug('Triggering completion...')

  if not M.is_inline_enabled() then
    return
  end

  local prompt = ' (Currently no completion options available)'
  local fx = function()
    Lines.render_virt_text({
      lines = {
        { prompt }
      },
      hls = Color.FittenNoMoreSuggestion,
      hl_mode = 'replace',
      show_time = 2000,
    })
  end
  generate_one_stage_at_cursor(function(suggestions)
    if not suggestions then
      fx()
    end
  end, function()
    fx()
  end)
end

---@param fx? function
---@return any
local function ignoreevent_wrap(fx)
  -- Out-of-order execution about eventignore and CursorMoved.
  -- https://github.com/vim/vim/issues/8641
  local eventignore = vim.o.eventignore
  vim.o.eventignore = 'all'

  local ret = nil
  if fx then
    ret = fx()
  end

  vim.o.eventignore = eventignore
  return ret
end

local function set_text_event_filter(lines)
  local window = api.nvim_get_current_win()
  local buffer = api.nvim_win_get_buf(window)
  ignoreevent_wrap(function()
    local cusors = Lines.set_text({
      window = window,
      buffer = buffer,
      lines = lines,
    })
    if not cusors then
      return
    end
    model:update_triggered_cursor(unpack(cusors[2]))
  end)
end

local function _accept_impl(range, direction, mode)
  if not suggestions_modify_enabled() then
    return
  end
  mode = mode or Config.options.inline_completion.accept_mode
  if mode == 'commit' and direction == 'backward' then
    return
  end
  Lines.clear_virt_text()
  if mode == 'stage' and range == 'all' then
    set_text_event_filter(model:get_suggestions_segments().stage)
    model:sync_commit()
  else
    local updated = model:accept({
      mode = mode,
      range = range,
      direction = direction,
    })
    if not updated then
      return
    end
    if mode == 'commit' then
      set_text_event_filter(updated.commit)
    end
  end
  local segments = model:get_suggestions_segments()
  render_virt_text_segments(segments)
  if model:reached_end() then
    if mode == 'stage' then
      set_text_event_filter(segments.stage)
    end
    generate_one_stage_at_cursor()
  end
end

function M.accept_all_suggestions()
  _accept_impl('all', 'forward')
end

function M.accept_line()
  _accept_impl('line', 'forward')
end

function M.accept_word()
  _accept_impl('word', 'forward')
end

function M.accept_char()
  _accept_impl('char', 'forward')
end

function M.revoke_char()
  _accept_impl('char', 'backward')
end

function M.revoke_word()
  _accept_impl('word', 'backward')
end

function M.revoke_line()
  _accept_impl('line', 'backward')
end

function M.reset()
  status:update(SC.IDLE)
  if M.is_inline_enabled() then
    Lines.clear_virt_text()
  end
  model:reset()
  tasks:clear()
end

function M.advance()
  if not suggestions_modify_enabled() then
    return
  end
  if not model:cache_hit(Base.get_cursor()) then
    Lines.clear_virt_text()
    model:reset()
  end
end

---@return boolean
function M.is_inline_enabled()
  if Config.options.completion_mode ~= 'inline' then
    return false
  end
  if not Config.options.inline_completion.enable then
    return false
  end
  local filetype = vim.bo.filetype
  if vim.tbl_contains(Config.options.disable_specific_inline_completion.suffixes, filetype) then
    return false
  end
  return true
end

---@return boolean?
function M.lazy_inline_completion()
  if not suggestions_modify_enabled() then
    return
  end
  local window = api.nvim_get_current_win()
  local buffer = api.nvim_win_get_buf(window)
  local row, col = Base.get_cursor(window)
  local char = api.nvim_buf_get_text(buffer, row, col - 1, row, col + 1, {})[1]
  if model:is_advance(row, col, char) then
    Lines.clear_virt_text()
    model:accept({
      mode = 'commit',
      range = 'char',
      direction = 'forward',
    })
    model:update_triggered_cursor(row, col)
    render_virt_text_segments(model:get_suggestions_segments())
    if model:reached_end() then
      model:reset()
    end
  end
end

---@return integer
function M.get_status()
  return status:get_current()
end

return M
