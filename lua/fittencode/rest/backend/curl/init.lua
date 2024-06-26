local fn = vim.fn

local Base = require('fittencode.base')
local FS = require('fittencode.fs')
local Rest = require('fittencode.rest.rest')
local Log = require('fittencode.log')
local Process = require('fittencode.concurrency.process')
local Promise = require('fittencode.concurrency.promise')

local schedule = Base.schedule

---@class RestCurlBackend : Rest
local M = Rest:new('RestCurlBackend')

local CURL = 'curl'
local TIMEOUT = 5 -- 5 seconds
local DEFAULT_ARGS = {
  '-s',
  '--connect-timeout',
  TIMEOUT,
  '--show-error',
  -- '-v', -- For debug purposes only
}
local EXIT_CODE_SUCCESS = 0

local function on_curl_exitcode(exit_code, response, error, on_success, on_error)
  if exit_code ~= EXIT_CODE_SUCCESS then
    ---@type string[]
    local formatted_error = vim.tbl_filter(function(s)
      return #s > 0
    end, vim.split(error, '\n'))
    Log.error('cURL failed with exit code: {}, error: {}', exit_code, formatted_error)
    schedule(on_error)
  else
    schedule(on_success, response)
  end
end

local function on_curl_signal(signal)
  Log.error('cURL failed due to signal: {}', signal)
end

local function _spawn(args, on_success, on_error, on_exit)
  Process.spawn({
    cmd = CURL,
    args = args,
  }, function(exit_code, response, error)
    on_curl_exitcode(exit_code, response, error, on_success, on_error)
  end, function(signal)
    on_curl_signal(signal)
    schedule(on_error)
  end, function()
    schedule(on_exit)
  end)
end

-- NOTE: This mutates dst!
local function merge_args(args, headers, extra_args)
  for _, v in ipairs(headers) do
    table.insert(args, '-H')
    table.insert(args, v)
  end
  vim.list_extend(args, extra_args)
end

function M:get(url, headers, data, on_success, on_error)
  local args = {
    url,
  }
  merge_args(args, headers, DEFAULT_ARGS)
  _spawn(args, on_success, on_error)
end

local function post_largedata(url, headers, encoded_data, on_success, on_error)
  Promise:new(function(resolve, reject)
    FS.write_temp_file(encoded_data, function(_, path)
      resolve(path)
    end, function(e_tmpfile)
      schedule(on_error, e_tmpfile)
    end)
  end):forward(function(path)
    local args = {
      '-X',
      'POST',
      '-d',
      '@' .. path,
      url,
    }
    merge_args(args, headers, DEFAULT_ARGS)
    _spawn(args, on_success, on_error, function()
      FS.delete(path)
    end)
  end)
end

function M:post(url, headers, data, on_success, on_error)
  local success, encoded_data = pcall(fn.json_encode, data)
  if not success then
    Log.error('Failed to encode data: {}', data)
    schedule(on_error)
    return
  end
  if #encoded_data > 200 then
    return post_largedata(url, headers, encoded_data, on_success, on_error)
  end
  local args = {
    '-X',
    'POST',
    '-d',
    encoded_data,
    url,
  }
  merge_args(args, headers, DEFAULT_ARGS)
  _spawn(args, on_success, on_error)
end

return M
