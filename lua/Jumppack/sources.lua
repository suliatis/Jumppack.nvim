-- Jumplist processing module
-- Handles retrieving, processing, and creating jump items from Vim's jumplist

local H = {}

local Utils = require('Jumppack.utils')
local Hide = require('Jumppack.hide')

-- Forward declarations for injected dependencies
local Jumppack_config = nil

--Create jumplist source for picker
-- opts: Picker options
-- returns: Jumplist source or nil if no jumps
function H.create_source(opts)
  opts = vim.tbl_deep_extend('force', { offset = -1 }, opts)

  local log = Utils.get_logger()
  log.debug('create_source: requested offset=', opts.offset)

  local all_jumps = H.get_all(Jumppack_config)

  log.debug('create_source: found', #all_jumps, 'jumps')

  if #all_jumps == 0 then
    log.warn('create_source: no jumps available')
    return nil
  end

  local initial_selection = H.find_target_offset(all_jumps, opts.offset, Jumppack_config)

  log.debug('create_source: initial_selection=', initial_selection)

  -- Note: show, preview, choose functions are set by caller (init.lua)
  return {
    name = 'Jumplist',
    items = all_jumps,
    initial_selection = initial_selection,
  }
end

--Get all valid jumps from jumplist
-- config: Configuration
-- returns: List of valid jump items
function H.get_all(config)
  local jumps = vim.fn.getjumplist()
  local jumplist = jumps[1]
  local current = jumps[2]

  config = config or Jumppack_config
  local cwd_only = config.options and config.options.cwd_only
  local current_cwd = cwd_only and Utils.full_path(vim.fn.getcwd()) or nil

  local all_jumps = {}

  -- Process all jumps in the jumplist
  for i = 1, #jumplist do
    local jump = jumplist[i]
    if jump.bufnr > 0 and vim.fn.buflisted(jump.bufnr) == 1 then
      local jump_item = H.create_item(jump, i, current)
      if jump_item then
        -- Filter by cwd if cwd_only is enabled
        if cwd_only then
          local jump_path = Utils.full_path(jump_item.path)
          if vim.startswith(jump_path, current_cwd) then
            table.insert(all_jumps, jump_item)
          end
        else
          table.insert(all_jumps, jump_item)
        end
      end
    end
  end

  -- Reverse the order so most recent jumps are at the top
  local reversed_jumps = {}
  for i = #all_jumps, 1, -1 do
    table.insert(reversed_jumps, all_jumps[i])
  end

  -- Mark items with hide status
  Hide.mark_items(reversed_jumps)

  return reversed_jumps
end

--Create jump item from jumplist entry
-- jump: Vim jumplist entry
-- i: Jump index
-- current: Current position index
-- returns: Jump item or nil if invalid
function H.create_item(jump, i, current)
  local bufname = vim.fn.bufname(jump.bufnr)
  if bufname == '' then
    return nil
  end

  local jump_item = {
    bufnr = jump.bufnr,
    path = bufname,
    lnum = jump.lnum,
    col = jump.col + 1,
    jump_index = i,
    is_current = (i == current + 1),
  }

  -- Determine navigation offset
  if i <= current then
    -- Older jump (go back with <C-o>)
    jump_item.offset = -(current - i + 1)
  elseif i == current + 1 then
    -- Current position
    jump_item.offset = 0
  else
    -- Newer jump (go forward with <C-i>)
    jump_item.offset = i - current - 1
  end

  return jump_item
end

--Find best matching jump for target offset
-- jumps: Available jump items
-- target_offset: Target navigation offset
-- config: Configuration
-- returns: Index of best matching jump
function H.find_target_offset(jumps, target_offset, config)
  config = config or Jumppack_config
  local wrap_edges = config.options and config.options.wrap_edges

  local best_same_direction = nil
  local current_position = nil
  local min_backward = nil -- Most negative offset (furthest back)
  local max_forward = nil -- Most positive offset (furthest forward)

  for i, jump in ipairs(jumps) do
    -- Priority 1: Exact match
    if jump.offset == target_offset then
      return i
    end

    -- Track min/max offsets for wrapping
    if jump.offset < 0 and (not min_backward or jump.offset < jumps[min_backward].offset) then
      min_backward = i
    end
    if jump.offset > 0 and (not max_forward or jump.offset > jumps[max_forward].offset) then
      max_forward = i
    end

    -- Priority 2: Best match in same direction
    if target_offset ~= 0 and jump.offset ~= 0 then
      local same_direction = (target_offset > 0) == (jump.offset > 0)
      if same_direction then
        if
          not best_same_direction
          or (target_offset > 0 and jump.offset > jumps[best_same_direction].offset)
          or (target_offset < 0 and jump.offset < jumps[best_same_direction].offset)
        then
          best_same_direction = i
        end
      end
    end

    -- Priority 3: Current position
    if jump.offset == 0 then
      current_position = i
    end
  end

  -- Priority 4: Handle wrapping if enabled and no match found
  if wrap_edges and not best_same_direction then
    if target_offset > 0 and min_backward then
      -- Going forward but no forward jumps, wrap to furthest back
      return min_backward
    elseif target_offset < 0 and max_forward then
      -- Going backward but no backward jumps, wrap to furthest forward
      return max_forward
    end
  end

  return best_same_direction or current_position or 1
end

-- Dependency injection
function H.set_config(config)
  Jumppack_config = config
end

return H
