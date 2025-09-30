#!/usr/bin/env lua

-- Format markdown tables in Lua doc comments
-- Usage: lua scripts/format_tables.lua [--check] <files...>

local check_mode = false
local files_to_process = {}

-- Parse command line arguments
for i = 1, #arg do
  if arg[i] == '--check' then
    check_mode = true
  else
    table.insert(files_to_process, arg[i])
  end
end

-- Find all .lua files in directories
local function find_lua_files(paths)
  local result = {}
  for _, path in ipairs(paths) do
    local handle = io.popen('find "' .. path .. '" -name "*.lua" -type f 2>/dev/null')
    if handle then
      for file in handle:lines() do
        table.insert(result, file)
      end
      handle:close()
    end
  end
  return result
end

-- Parse markdown table and calculate column widths
local function parse_table_line(line)
  -- Match doc comment table lines: "---|  content  |  content  |"
  local content = line:match('^%-%-%-%|(.*)%|%s*$')
  if not content then
    return nil
  end

  local cells = {}
  for cell in (content .. '|'):gmatch('([^|]*)%|') do
    -- Trim leading/trailing spaces
    local trimmed = cell:match('^%s*(.-)%s*$')
    table.insert(cells, trimmed)
  end

  return cells
end

-- Check if line is a separator row
local function is_separator_row(cells)
  if not cells then
    return false
  end
  for _, cell in ipairs(cells) do
    if not cell:match('^%-+$') then
      return false
    end
  end
  return true
end

-- Format table line with proper column widths
local function format_table_line(cells, widths)
  local parts = {}
  for i, cell in ipairs(cells) do
    local width = widths[i] or 0
    local is_sep = cell:match('^%-+$')

    if is_sep then
      -- Separator row: fill with dashes
      table.insert(parts, string.rep('-', width))
    else
      -- Regular row: left-align with padding
      local padding = width - #cell
      table.insert(parts, cell .. string.rep(' ', padding))
    end
  end

  return '---| ' .. table.concat(parts, ' | ') .. ' |'
end

-- Process a single file
local function process_file(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    io.stderr:write('Error: Cannot open file: ' .. filepath .. '\n')
    return false
  end

  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  local modified = false
  local output_lines = {}
  local i = 1

  while i <= #lines do
    local line = lines[i]
    local cells = parse_table_line(line)

    -- Check if this is the start of a table
    if cells then
      local table_lines = { { line = line, cells = cells } }
      local j = i + 1

      -- Collect all consecutive table lines
      while j <= #lines do
        local next_cells = parse_table_line(lines[j])
        if next_cells then
          table.insert(table_lines, { line = lines[j], cells = next_cells })
          j = j + 1
        else
          break
        end
      end

      -- Calculate max width for each column
      local num_cols = #table_lines[1].cells
      local widths = {}
      for col = 1, num_cols do
        widths[col] = 0
        for _, tline in ipairs(table_lines) do
          if tline.cells[col] then
            widths[col] = math.max(widths[col], #tline.cells[col])
          end
        end
      end

      -- Format all table lines
      for _, tline in ipairs(table_lines) do
        local formatted = format_table_line(tline.cells, widths)
        if formatted ~= tline.line then
          modified = true
        end
        table.insert(output_lines, formatted)
      end

      i = j
    else
      table.insert(output_lines, line)
      i = i + 1
    end
  end

  if check_mode then
    if modified then
      io.stderr:write('Error: Tables not formatted in: ' .. filepath .. '\n')
      return false
    end
  else
    if modified then
      local out_file = io.open(filepath, 'w')
      if not out_file then
        io.stderr:write('Error: Cannot write file: ' .. filepath .. '\n')
        return false
      end

      for _, line in ipairs(output_lines) do
        out_file:write(line .. '\n')
      end
      out_file:close()

      io.stdout:write('Formatted tables in: ' .. filepath .. '\n')
    end
  end

  return true
end

-- Main execution
if #files_to_process == 0 then
  io.stderr:write('Usage: lua format_tables.lua [--check] <files or directories...>\n')
  os.exit(1)
end

-- Expand directories to files
local all_files = {}
for _, path in ipairs(files_to_process) do
  local attr = io.popen('test -d "' .. path .. '" && echo dir || echo file'):read('*l')
  if attr == 'dir' then
    for _, file in ipairs(find_lua_files({ path })) do
      table.insert(all_files, file)
    end
  else
    table.insert(all_files, path)
  end
end

-- Process all files
local all_ok = true
for _, file in ipairs(all_files) do
  if not process_file(file) then
    all_ok = false
  end
end

if check_mode and not all_ok then
  io.stderr:write('\nRun "make format" to fix table formatting.\n')
  os.exit(1)
end

if not check_mode then
  io.stdout:write('Table formatting complete!\n')
end
