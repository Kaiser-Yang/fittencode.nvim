local fn = vim.fn
local api = vim.api
local uv = vim.uv

local Base = require('fittencode.base')
local Rest = require('fittencode.rest')

local M = {}

local function read_api_key(data)
  M.api_key = data:gsub('\n', '')
end

local function get_api_key_store_path()
  local dir = fn.stdpath('data') .. '/fittencode'
  local path = dir .. '/api_key'
  return root, path
end

local function read_local_api_key_file()
  local _, path = get_api_key_store_path()
  Base.read(path, read_api_key)
end

local function on_curl_signal_callback(signal, output)
  error(string.format('Curl throw signal: %d', signal))
end

local function write_api_key(api_key)
  local dir, path = get_api_key_store_path()
  Base.write(api_key, dir, path)
end

local function on_login_api_key_callback(exit_code, output)
  local fico_data = fn.json_decode(output)
  if fico_data.status_code == nil or fico_data.status_code ~= 0 then
    -- TODO: Handle errors
    return
  end
  if fico_data.data == nil or fico_data.data.fico_token == nil then
    -- TODO: Handle errors
    return
  end
  local api_key = fico_data.data.fico_token
  M.api_key = api_key
  write_api_key(api_key)
end

local function login_with_api_key(user_token)
  M.user_token = user_token

  local fico_url = 'https://codeuser.fittentech.cn:14443/get_ft_token'
  local fico_args = {
    '-s',
    '-H',
    'Authorization: Bearer ' .. user_token,
    fico_url,
  }
  Rest.send({
    cmd = 'curl',
    args = fico_args,
  }, on_login_api_key_callback, on_curl_signal_callback)
end

local function on_login_callback(exit_code, output)
  -- TODO: Handle exit_code
  local login_data = fn.json_decode(output)
  if login_data.code == nil or login_data.code ~= 200 then
    return
  end
  local api_key = login_data.data.token
  login_with_api_key(api_key)
end

function M.load_last_session()
  read_local_api_key_file()
end

function M.login(name, password)
  local login_url = 'https://codeuser.fittentech.cn:14443/login'
  local data = {
    username = name,
    password = password,
  }
  local json_data = fn.json_encode(data)
  local login_args = {
    '-s',
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    '-d',
    json_data,
    login_url,
  }
  Rest.send({
    cmd = 'curl',
    args = login_args,
  }, on_login_callback, on_curl_signal_callback)
end

function M.logout()
  local _, path = get_api_key_store_path()
  uv.fs_unlink(path, function(err)
    if err then
      -- TODO: Handle errors
    else
      M.user_token = nil
    end
  end)
end

local function calculate_needed_lines(virt_lines)
  local remaining_count = api.nvim_buf_line_count(0) - (fn.line('.') - 1)
  local virt_lines_count = vim.tbl_count(virt_lines)
  local needed_lines = virt_lines_count - remaining_count
  return needed_lines
end

local function on_completion_callback(exit_code, response)
  local completion_data = fn.json_decode(response)
  if completion_data.generated_text == nil then
    return
  end
  if M.namespace ~= nil then
    Base.hide(M.namespace, 0)
  else
    M.namespace = api.nvim_create_namespace('Fittencode')
  end

  M.complete_lines = {}

  local generated_text = fn.substitute(completion_data.generated_text, '<.endoftext.>', '', 'g')
  local lines = vim.split(generated_text, '\r')

  -- M.complete_lines = ''

  -- print('lines v')
  -- print(vim.inspect(lines))
  -- print('lines ^')
  local virt_lines = {}
  for _, line in ipairs(lines) do
    -- M.complete_lines = M.complete_lines.. line
    local parts = vim.split(line, '\n')
    for _, part in ipairs(parts) do
      table.insert(virt_lines, { { part, 'Comment' } })
      table.insert(M.complete_lines, part)
    end
  end

  -- virtual line not rendering if it's beyond the last line · Issue #20179 · neovim/neovim
  -- https://github.com/neovim/neovim/issues/20179
  local needed_lines = calculate_needed_lines(virt_lines)
  if needed_lines > 0 then
    for i = 1, needed_lines do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('O', true, false, true), 'n', true)
    end
  end

  local first_line = true
  for i, line in ipairs(virt_lines) do
    if first_line then
      first_line = false
      api.nvim_buf_set_extmark(0, M.namespace, fn.line('.') - 1, fn.col('.') - 1, {
        virt_text = line,
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
      })
    else
      local row = fn.line('.') - 2 + i
      if row < api.nvim_buf_line_count(0) then
        -- api.nvim_win_set_cursor(0, { row, 0 })
        api.nvim_buf_set_extmark(0, M.namespace, row, 0, {
          virt_text = line,
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
      end
    end
  end
end

local function on_completion_delete_tempfile_callback(path)
  uv.fs_unlink(path, function(err)
    if err then
      -- TODO: Handle errors
    else
      -- TODO:
    end
  end)
end

function M.completion_request()
  if M.api_key == nil or M.api_key == '' then
    return
  end

  local filename = api.nvim_buf_get_name(api.nvim_get_current_buf())
  if filename == nil or filename == '' then
    filename = 'NONAME'
  end
  local prefix_table = api.nvim_buf_get_text(0, 0, 0, fn.line('.') - 1, fn.col('.') - 1, {})
  local prefix = table.concat(prefix_table, '\n')
  local suffix_table = api.nvim_buf_get_text(0, fn.line('.') - 1, fn.col('.') - 1, fn.line('$') - 1, fn.col('$,$') - 1, {})
  local suffix = table.concat(suffix_table, '\n')

  local prompt = '!FCPREFIX!' .. prefix .. '!FCSUFFIX!' .. suffix .. '!FCMIDDLE!'
  local escaped_prompt = string.gsub(prompt, '"', '\\"')
  local params = {
    inputs = escaped_prompt,
    meta_datas = {
      filename = filename,
    },
  }
  local encoded_params = fn.json_encode(params)
  Base.write_temp_file(encoded_params, function(path)
    local server_addr = 'https://codeapi.fittentech.cn:13443/generate_one_stage/'
    local completion_args = {
      '-s',
      '-X',
      'POST',
      '-H',
      'Content-Type: application/json',
      '-d',
      '@' .. Base.to_native(path),
      server_addr .. M.api_key .. '?ide=vim&v=0.1.0',
    }
    Rest.send({
      cmd = 'curl',
      args = completion_args,
      data = path,
    }, on_completion_callback, on_curl_signal_callback, on_completion_delete_tempfile_callback)
  end)
end

function M.clear()
  Base.hide(M.namespace, 0)
end

local function local_fmt_clear()
  vim.bo.autoindent = false
  vim.bo.smartindent = false
  vim.bo.formatoptions = ''
  vim.bo.textwidth = 0
  -- vim.bo.backspace = 2
end

local function local_fmt_recover()
  vim.bo.autoindent = vim.o.autoindent
  vim.bo.smartindent = vim.o.smartindent
  vim.bo.formatoptions = vim.o.formatoptions
end

_G.__fittencode_commit_lines = function()
  print('__fittencode_commit_lines 1')
  -- print(vim.inspect(M.complete_lines))
  local_fmt_clear()

  local content = ''
  for i = 1, #M.complete_lines, 1 do
    local line = M.complete_lines[i]
    if string.len(line) == 0 then
      local keys = vim.api.nvim_replace_termcodes('<Space><Backspace><CR>', true, false, true)
      vim.api.nvim_feedkeys(keys, 'i', true)
    else
      api.nvim_feedkeys(line, 'i', false)
    end
    -- api.nvim_feedkeys(line .. '\n', 'i', false)
    -- content = content .. line
  end

  -- print(vim.inspect(content))
  -- local keys = vim.api.nvim_replace_termcodes(content, true, false, true)
  -- api.nvim_feedkeys(keys, 'i', false)

  local_fmt_recover()
  M.complete_lines = {}
  -- M.complete_lines = ''
  print('__fittencode_commit_lines 2')
end

function M.chaining_complete()
  -- if string.len(M.complete_lines) == 0 then
  --   return
  -- end

  if vim.tbl_count(M.complete_lines) == 0 then
    return
  end

  M.clear()
  local keys = vim.api.nvim_replace_termcodes('<Cmd>call v:lua.__fittencode_commit_lines()<CR>', true, false, true)
  api.nvim_feedkeys(keys, 'n', true)
end

return M
