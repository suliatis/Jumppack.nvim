-- Actions module
-- Handles user actions in the picker interface

local H = {}
H.utils = require('Jumppack.utils')
H.instance = require('Jumppack.instance')
H.filters = require('Jumppack.filters')
H.hide = require('Jumppack.hide')
H.display = require('Jumppack.display')

-- Action handlers
H.jump_back = function(instance, count)
  -- Navigate backwards in jump history with count support
  local move_count = count or 1
  H.instance.move_selection(instance, move_count) -- Positive = backward in time
end

H.jump_forward = function(instance, count)
  -- Navigate forwards in jump history with count support
  local move_count = -(count or 1)
  H.instance.move_selection(instance, move_count) -- Negative = forward in time
end

H.choose = function(instance, _)
  return H.choose_with_action(instance, nil)
end

H.choose_in_split = function(instance, _)
  return H.choose_with_action(instance, 'split')
end

H.choose_in_tabpage = function(instance, _)
  return H.choose_with_action(instance, 'tab split')
end

H.choose_in_vsplit = function(instance, _)
  return H.choose_with_action(instance, 'vsplit')
end

H.toggle_preview = function(instance, _)
  if instance.view_state == 'preview' then
    return H.display.render_list(instance)
  end
  H.display.render_preview(instance)
end

H.stop = function(instance, _)
  -- If count is being accumulated, clear it instead of closing picker
  if instance.pending_count ~= '' then
    instance.pending_count = ''
    if instance.count_timer then
      vim.fn.timer_stop(instance.count_timer)
      instance.count_timer = nil
    end
    H.display.render(instance)
    return false -- Don't close picker
  end
  return true -- Close picker
end

-- Filter actions
H.toggle_file_filter = function(instance, _)
  H.filters.toggle_file(instance.filters)
  H.instance.apply_filters_and_update(instance)
end

H.toggle_cwd_filter = function(instance, _)
  H.filters.toggle_cwd(instance.filters)
  H.instance.apply_filters_and_update(instance)
end

H.toggle_show_hidden = function(instance, _)
  H.filters.toggle_hidden(instance.filters)
  H.instance.apply_filters_and_update(instance)
end

H.reset_filters = function(instance, _)
  H.filters.reset(instance.filters)
  H.instance.apply_filters_and_update(instance)
end

-- Hide actions
H.toggle_hidden = function(instance, _)
  local cur_item = H.instance.get_selection(instance)
  if not cur_item then
    return
  end

  -- Toggle hide status in session storage
  local new_status = H.hide.toggle(cur_item)

  -- Re-mark all items with updated hidden status from storage
  -- This ensures both current items AND original_items reflect the change
  H.hide.mark_items(instance.items)
  if instance.original_items then
    H.hide.mark_items(instance.original_items)
  end

  -- Apply filters to update both list and preview views
  -- This will hide the item if show_hidden = false (default)
  H.instance.apply_filters_and_update(instance)

  -- After filtering, adjust selection if the current item was hidden and removed from view
  if new_status and not instance.filters.show_hidden and #instance.items > 0 then
    -- Ensure we have a valid current selection after filtering
    local current = instance.current or 1

    -- If current selection is beyond available items, adjust to last item
    if current > #instance.items then
      H.instance.set_selection(instance, #instance.items, true)
    elseif current < 1 then
      -- If no valid selection, select first item
      H.instance.set_selection(instance, 1, true)
    end

    -- Re-render to reflect changes
    H.display.render(instance)
  end
end

H.jump_to_top = function(instance, _)
  -- Jump to the first item in the jumplist (ignores count)
  H.instance.move_selection(instance, 0, 1)
end

H.jump_to_bottom = function(instance, _)
  -- Jump to the last item in the jumplist (ignores count)
  if instance.items and #instance.items > 0 then
    H.instance.move_selection(instance, 0, #instance.items)
  end
end

--Choose current item with optional pre-command
-- instance: Picker instance
-- pre_command: Command to execute before choosing
-- returns: True if should stop picker
function H.choose_with_action(instance, pre_command)
  -- Early validation - guard clause
  local cur_item = H.instance.get_selection(instance)
  if not cur_item then
    return true
  end

  local win_id_target = instance.windows.target
  if
    pre_command ~= nil
    and type(pre_command) == 'string'
    and pre_command ~= ''
    and H.utils.is_valid_win(win_id_target)
  then
    -- Work around Neovim not preserving cwd during `nvim_win_call`
    -- See: https://github.com/neovim/neovim/issues/32203
    local instance_cwd, global_cwd = vim.fn.getcwd(0), vim.fn.getcwd(-1, -1)
    vim.fn.chdir(global_cwd)
    vim.api.nvim_win_call(win_id_target, function()
      vim.cmd(pre_command)
      instance.windows.target = vim.api.nvim_get_current_win()
    end)
    vim.fn.chdir(instance_cwd)
  end

  local ok, res = pcall(instance.opts.source.choose, cur_item)
  -- Delay error to have time to hide instance window
  if not ok then
    vim.schedule(function()
      H.utils.error('choose_with_action(): Error during choose action:\n' .. res)
    end)
  end
  -- Error or returning nothing, `nil`, or `false` should lead to instance stop
  return not (ok and res)
end

return H
