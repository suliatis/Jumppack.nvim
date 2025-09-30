---@brief [[
--- Hide system for Jumppack plugin.
--- Manages persistent hiding of jump entries using Vim global variables.
--- This module has no dependencies on other H.* namespaces.
---@brief ]]

local H = {}

--Get hidden items from global variable (session-persistent)
-- Returns existing hidden items or empty table if none exist.
-- This function is read-only and never modifies the global variable.
-- Deserializes newline-separated string to table (Vim sessions only save strings/numbers).
-- returns: Hidden items keyed by path:lnum:col
function H.load()
  local str = vim.g.Jumppack_hidden_items or ''
  if str == '' then
    return {}
  end

  local hidden = {}
  for _, key in ipairs(vim.split(str, '\n', { plain = true, trimempty = true })) do
    hidden[key] = true
  end
  return hidden
end

--Save hidden items to global variable (session-persistent)
-- This is the ONLY function that writes to the global variable.
-- The global variable is automatically saved/restored by :mksession when
-- 'globals' is in sessionoptions.
-- Serializes table to newline-separated string (Vim sessions only save strings/numbers).
-- hidden: Hidden items keyed by path:lnum:col
function H.save(hidden)
  local keys = vim.tbl_keys(hidden)
  vim.g.Jumppack_hidden_items = table.concat(keys, '\n')
end

--Get hide key for jump item
-- item: Jump item
-- returns: Hide key
function H.get_key(item)
  return item.path .. ':' .. item.lnum .. ':' .. item.col
end

--Check if item is hidden
-- item: Jump item
-- returns: True if hidden
function H.is_hidden(item)
  local hidden = H.load()
  local key = H.get_key(item)
  local is_hidden = hidden[key] == true
  return is_hidden
end

--Toggle hide status for item
-- item: Jump item
-- returns: New hide status
function H.toggle(item)
  local hidden = H.load()
  local key = H.get_key(item)

  local new_state
  if hidden[key] then
    hidden[key] = nil
    new_state = false
  else
    hidden[key] = true
    new_state = true
  end

  H.save(hidden)
  return new_state
end

--Mark items with their hide status
-- items: Jump items
-- returns: Items with hide status marked
function H.mark_items(items)
  if not items then
    return items
  end

  local hidden = H.load()

  for _, item in ipairs(items) do
    local key = H.get_key(item)
    item.hidden = hidden[key] == true
  end

  return items
end

return H
