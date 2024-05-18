local fn = vim.fn
local uv = vim.uv or vim.loop

local Base = require('fittencode.base')
local Config = require('fittencode.config')
local Path = require('fittencode.fs.path')

local M = {}

---@class LogOptions
---@field level? integer @one of the `vim.log.levels` values

local MODULE_NAME = 'fittencode.nvim'
local LOG_PATH = Path.to_native(fn.stdpath('log') .. '/fittencode' .. '/fittencode.log')

-- See `help vim.log.levels`
-- Refs: `neovim/runtime/lua/vim/_editor.lua`
--[[
  ```lua
  vim.log = {
    levels = {
      TRACE = 0,
      DEBUG = 1,
      INFO = 2,
      WARN = 3,
      ERROR = 4,
      OFF = 5,
    },
  }
  ```
]]
local levels = vim.deepcopy(vim.log.levels)

local first_log = true
local cpu = 0
local environ = 0
local print_module = false

local function level_name(x)
  return Base.tbl_key_by_value(levels, x, '????')
end

-- Log a message to a file.
---@param msg string @the message to log
local function log_file(msg)
  local f = io.open(LOG_PATH, 'a')
  if f then
    if first_log then
      local EDGE = string.rep('=', 80) .. '\n'
      f:write(EDGE)
      ---@type table<string,any>
      local mat = {}
      table.insert(mat, { 'Verbose logging started', os.date('%Y-%m-%d %H:%M:%S') })
      table.insert(mat, { 'Log level', level_name(Config.options.log.level) })
      table.insert(mat, { 'Calling process', uv.exepath() })
      table.insert(mat, { 'Neovim version', vim.inspect(Base.get_version()) })
      table.insert(mat, { 'Process ID', uv.os_getpid() })
      table.insert(mat, { 'Parent process ID', uv.os_getppid() })
      table.insert(mat, { 'OS', vim.inspect(uv.os_uname()) })
      if cpu ~= 0 then
        table.insert(mat, { 'CPU', vim.inspect(uv.cpu_info()) })
      end
      if environ ~= 0 then
        table.insert(mat, { 'Environment', vim.inspect(uv.os_environ()) })
      end
      for i in ipairs(mat) do
        f:write(string.format('%s: %s\n', mat[i][1], mat[i][2]))
      end
      f:write(EDGE)
      first_log = false
    end
    f:write(string.format('%s\n', msg))
    f:close()
  end
end

-- Expand a message with optional arguments.
---@param msg string|nil @can be a format string with {} placeholders
---@param... any @optional arguments to substitute into the message
---@return string
local function expand_msg(msg, ...)
  msg = msg or ''
  local count = 0
  msg, count = msg:gsub('{}', '%%s')
  if count == 0 and select('#', ...) == 0 then
    return msg
  end
  local args = vim.tbl_map(vim.inspect, { ... })
  if #args < count then
    for i = #args + 1, count do
      args[i] = vim.inspect(nil)
    end
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  msg = string.format(msg, unpack(args))
  return msg
end

-- Log a message with a given level.
---@param level integer @one of the `vim.log.levels` values
---@param msg string|nil @can be a format string with {} placeholders
local function do_log(level, msg)
  ---@type table<string,string>
  local mat = {}
  local ms = string.format('%03d', math.floor((uv.hrtime() / 1e6) % 1000))
  table.insert(mat, string.format('%5s', level_name(level)))
  table.insert(mat, os.date('%Y-%m-%d %H:%M:%S') .. '.' .. ms)
  if print_module then
    table.insert(mat, MODULE_NAME)
  end
  local tags = ''
  for i in ipairs(mat) do
    tags = tags .. string.format('[%s]', mat[i]) .. ' '
  end
  msg = tags .. msg
  log_file(msg)
end

local function size_over_limit()
  local size = fn.getfsize(LOG_PATH)
  return size > Config.options.log.max_size * 1024 * 1024
end

function M.setup()
  fn.mkdir(fn.fnamemodify(LOG_PATH, ':h'), 'p')
  if Config.options.log.new_file_on_startup or size_over_limit() then
    fn.delete(LOG_PATH)
  end
end

---@param level integer @one of the `vim.log.levels` values
function M.set_level(level)
  Config.options.log.level = level
end

---@param level integer @one of the `vim.log.levels` values
---@param msg string|nil @can be a format string with {} placeholders
function M.log(level, msg, ...)
  if level < Config.options.log.level or Config.options.log.level == levels.OFF then
    return
  end
  msg = expand_msg(msg, ...)
  do_log(level, msg)
end

-- Notify the user of a message.
-- Also logs the message if nescessary.
---@param level integer @one of the `vim.log.levels` values
---@param msg string|nil @can be a format string with {} placeholders
function M.notify(level, msg, ...)
  msg = expand_msg(msg, ...)
  vim.schedule(function()
    vim.notify(msg, level, { title = MODULE_NAME })
  end)
  M.log(level, msg)
end

function M.error(...)
  M.log(levels.ERROR, ...)
end

function M.e(...)
  M.notify(levels.ERROR, ...)
end

function M.warn(...)
  M.log(levels.WARN, ...)
end

function M.w(...)
  M.notify(levels.WARN, ...)
end

function M.info(...)
  M.log(levels.INFO, ...)
end

function M.i(...)
  M.notify(levels.INFO, ...)
end

function M.debug(...)
  M.log(levels.DEBUG, ...)
end

function M.d(...)
  M.notify(levels.DEBUG, ...)
end

function M.trace(...)
  M.log(levels.TRACE, ...)
end

function M.t(...)
  M.notify(levels.TRACE, ...)
end

return M
