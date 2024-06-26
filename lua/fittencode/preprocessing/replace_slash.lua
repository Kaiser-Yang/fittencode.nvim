---@param prefix? string[]
---@param lines? string[]
---@param opts? boolean
---@return string[]?
local function replace_slash(prefix, lines, opts)
  if not lines or #lines == 0 or not opts then
    return lines
  end
  local slash = {}
  for i, line in ipairs(lines) do
    line = line:gsub('\\"', '"')
    slash[#slash + 1] = line
  end
  return slash
end

return {
  run = replace_slash
}
