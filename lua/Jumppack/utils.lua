---@brief [[
--- Utility functions for Jumppack plugin.
--- This module provides general-purpose utilities with no dependencies on other H.* namespaces.
---@brief ]]

local H = {}

--Display error message
-- msg: Error message
function H.error(msg)
  error('(jumppack) ' .. msg, 0)
end

--Check value type and error if invalid
-- name: Parameter name
-- val: Value to check
-- ref: Expected type
-- allow_nil: Allow nil values
function H.check_type(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then
    return
  end
  H.error(string.format('check_type(): %s must be %s, got %s', name, ref, type(val)))
end

function H.set_buf_name(buf_id, name)
  vim.api.nvim_buf_set_name(buf_id, 'jumppack://' .. buf_id .. '/' .. name)
end

--Display notification message
-- msg: Message to display
-- level_name: Log level name
function H.notify(msg, level_name)
  vim.notify('(jumppack) ' .. msg, vim.log.levels[level_name])
end

--Check if buffer ID is valid
-- buf_id: Buffer ID
-- returns: True if valid
function H.is_valid_buf(buf_id)
  return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id)
end

--Check if window ID is valid
-- win_id: Window ID
-- returns: True if valid
function H.is_valid_win(win_id)
  return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id)
end

--Create scratch buffer
-- name: Buffer name
-- returns: Buffer ID
function H.create_scratch_buf(name)
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(buf_id, name)
  vim.bo[buf_id].matchpairs = ''
  vim.b[buf_id].minicursorword_disable = true
  vim.b[buf_id].miniindentscope_disable = true
  return buf_id
end

--- Safely set buffer lines (ignores errors from invalid buffers)
-- buf_id: Buffer id
-- lines: Lines to set
function H.set_buflines(buf_id, lines)
  pcall(vim.api.nvim_buf_set_lines, buf_id, 0, -1, false, lines)
end

--- Set window buffer
-- win_id: Window id
-- buf_id: Buffer id to set
function H.set_winbuf(win_id, buf_id)
  vim.api.nvim_win_set_buf(win_id, buf_id)
end

--- Safely set extmark (ignores errors from invalid buffers)
-- Arguments passed to nvim_buf_set_extmark
function H.set_extmark(...)
  pcall(vim.api.nvim_buf_set_extmark, ...)
end

function H.set_cursor(win_id, lnum, col)
  pcall(vim.api.nvim_win_set_cursor, win_id, { lnum or 1, (col or 1) - 1 })
end

function H.set_curwin(win_id)
  if not H.is_valid_win(win_id) then
    return
  end
  -- Explicitly preserve cursor to fix Neovim<=0.9 after choosing position in
  -- already shown buffer
  local cursor = vim.api.nvim_win_get_cursor(win_id)
  vim.api.nvim_set_current_win(win_id)
  H.set_cursor(win_id, cursor[1], cursor[2] + 1)
end

function H.clear_namespace(buf_id, ns_id)
  pcall(vim.api.nvim_buf_clear_namespace, buf_id, ns_id, 0, -1)
end

function H.replace_termcodes(x)
  if x == nil then
    return nil
  end
  return vim.api.nvim_replace_termcodes(x, true, true, true)
end

function H.expand_callable(x, ...)
  if vim.is_callable(x) then
    return x(...)
  end
  return x
end

function H.redraw()
  vim.cmd('redraw')
end

function H.win_update_hl(win_id, new_from, new_to)
  if not H.is_valid_win(win_id) then
    return
  end

  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local new_winhighlight, n_replace = vim.wo[win_id].winhighlight:gsub(replace_pattern, new_entry)
  if n_replace == 0 then
    new_winhighlight = new_winhighlight .. ',' .. new_entry
  end

  vim.wo[win_id].winhighlight = new_winhighlight
end

function H.fit_to_width(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

function H.win_get_bottom_border(win_id)
  local border = vim.api.nvim_win_get_config(win_id).border or {}
  local res = border[6]
  if type(res) == 'table' then
    res = res[1]
  end
  return res or ' '
end

function H.win_set_cwd(win_id, cwd)
  -- Avoid needlessly setting cwd as it has side effects (like for `:buffers`)
  if cwd == nil or vim.fn.getcwd(win_id or 0) == cwd then
    return
  end
  local f = function()
    vim.cmd('lcd ' .. vim.fn.fnameescape(cwd))
  end
  if win_id == nil or win_id == vim.api.nvim_get_current_win() then
    return f()
  end
  vim.api.nvim_win_call(win_id, f)
end

function H.get_next_char_bytecol(line_str, col)
  if type(line_str) ~= 'string' then
    return col
  end
  local utf_index = vim.str_utfindex(line_str, math.min(line_str:len(), col))
  ---@diagnostic disable-next-line: missing-parameter, param-type-mismatch
  return vim.str_byteindex(line_str, utf_index, true)
end

function H.full_path(path)
  return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1'))
end

function H.get_fs_type(path)
  if path == '' then
    return 'none'
  end
  if vim.fn.filereadable(path) == 1 then
    return 'file'
  end
  if vim.fn.isdirectory(path) == 1 then
    return 'directory'
  end
  return 'none'
end

-- Logging system
-- =======

local log = {}

-- Log level constants
local LOG_LEVELS = {
  trace = 1,
  debug = 2,
  info = 3,
  warn = 4,
  error = 5,
  off = 99,
}

-- Forward declaration for config
local Jumppack_config = nil

-- Initialize logging configuration
local function init_log_config()
  -- Check environment variable first, then fall back to config
  local env_level = vim.fn.getenv('JUMPPACK_LOG_LEVEL')
  if env_level == vim.NIL then
    env_level = nil
  end

  local level = env_level or (Jumppack_config and Jumppack_config.options.log_level) or 'off'
  level = level:lower()

  if not LOG_LEVELS[level] then
    level = 'off'
  end

  return {
    level = level,
    level_num = LOG_LEVELS[level],
    outfile = vim.fn.stdpath('state') .. '/jumppack.log',
  }
end

-- Format log message with source location
local function format_message(level_name, ...)
  local info = debug.getinfo(3, 'Sl')
  local source = info.source:sub(2) -- Remove '@' prefix
  local line = info.currentline

  -- Get filename only for cleaner logs
  local filename = vim.fn.fnamemodify(source, ':t')

  -- Build message from varargs
  local parts = {}
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    if type(v) == 'table' then
      v = vim.inspect(v)
    else
      v = tostring(v)
    end
    parts[#parts + 1] = v
  end
  local msg = table.concat(parts, ' ')

  -- Format: [LEVEL timestamp] file:line: message
  local timestamp = os.date('%H:%M:%S')
  return string.format('[%-5s %s] %s:%d: %s', level_name:upper(), timestamp, filename, line, msg)
end

-- Write log message to file
local function write_to_file(log_config, formatted_msg)
  -- Ensure log directory exists
  local log_dir = vim.fn.fnamemodify(log_config.outfile, ':h')
  if vim.fn.isdirectory(log_dir) == 0 then
    vim.fn.mkdir(log_dir, 'p')
  end

  -- Append to log file
  local file = io.open(log_config.outfile, 'a')
  if file then
    file:write(formatted_msg .. '\n')
    file:close()
  end
end

-- Log at specific level
local function log_at_level(level_name, level_num, ...)
  local log_config = init_log_config()

  -- Skip if logging is disabled or level is too low
  if level_num < log_config.level_num then
    return
  end

  local formatted_msg = format_message(level_name, ...)
  write_to_file(log_config, formatted_msg)
end

-- Public logging functions
function log.trace(...)
  log_at_level('trace', LOG_LEVELS.trace, ...)
end

function log.debug(...)
  log_at_level('debug', LOG_LEVELS.debug, ...)
end

function log.info(...)
  log_at_level('info', LOG_LEVELS.info, ...)
end

function log.warn(...)
  log_at_level('warn', LOG_LEVELS.warn, ...)
end

function log.error(...)
  log_at_level('error', LOG_LEVELS.error, ...)
end

-- Get logger instance
function H.get_logger()
  return log
end

-- Set config for logging
function H.set_config(config)
  Jumppack_config = config
end

-- Input handling with redraw scheduling
local redraw_scheduled = nil

function H.getcharstr(delay_async, cache, timer, active_instance)
  if not redraw_scheduled then
    redraw_scheduled = vim.schedule_wrap(H.redraw)
  end

  timer:start(0, delay_async, redraw_scheduled)
  cache.is_in_getcharstr = true
  local ok, char = pcall(vim.fn.getcharstr)
  cache.is_in_getcharstr = nil
  timer:stop()

  local main_win_id
  if active_instance ~= nil then
    main_win_id = active_instance.windows.main
  end
  local is_bad_mouse_click = vim.v.mouse_winid ~= 0 and vim.v.mouse_winid ~= main_win_id
  if not ok or char == '' or char == '\3' or is_bad_mouse_click then
    return
  end
  return char
end

return H
