local Jumppack = {}
local H = {}

function Jumppack.setup(config)
  config = H.setup_config(config)
  H.apply_config(config)
  H.create_autocommands()
  H.create_default_hl()
  H.setup_global_mappings(config)
end

Jumppack.config = {
  -- Keys for performing actions. See `:h Jumppack-actions`.
  mappings = {
    jump_back = '<C-o>',
    jump_forward = '<C-i>',

    choose = '<CR>',
    choose_in_split = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit = '<C-v>',

    stop = '<Esc>',

    toggle_preview = '<C-p>',
  },

  -- Window related options
  window = {
    -- Float window config (table or callable returning it)
    config = nil,
  },
}

function Jumppack.start(opts)
  H.cache = {}

  -- Handle jumplist-specific options
  if opts.jumplist_direction or opts.jumplist_distance then
    local direction = opts.jumplist_direction
    local distance = opts.jumplist_distance
    local jumplist_source = H.create_jumplist_source(direction, distance)
    if not jumplist_source then
      return -- No jumps available
    end
    opts = vim.tbl_extend('force', opts, { source = jumplist_source })
  end

  opts = H.validate_opts(opts)
  local instance = H.new(opts)
  H.instance = instance

  local items = H.expand_callable(opts.source.items)
  if vim.islist(items) then
    vim.schedule(function()
      Jumppack.set_items(items)
    end)
  end

  H.track_lost_focus(instance)
  return H.advance(instance)
end

function Jumppack.stop()
  if not Jumppack.is_active() then
    return
  end
  H.cache.is_force_stop_advance = true
  if H.cache.is_in_getcharstr then
    vim.api.nvim_feedkeys('\3', 't', true)
  end
end

function Jumppack.refresh()
  if not Jumppack.is_active() then
    return
  end
  H.update(H.instance, true)
end

function Jumppack.default_show(buf_id, items, opts)
  local default_icons = { directory = ' ', file = ' ', none = '  ' }
  opts = vim.tbl_deep_extend('force', { show_icons = true, icons = default_icons }, opts or {})

  -- Compute and set lines. Compute prefix based on the whole items to allow
  -- separate `text` and `path` table fields (preferring second one).
  local get_prefix_data = opts.show_icons and function(item)
    return H.get_icon(item, opts.icons)
  end or function()
    return { text = '' }
  end
  local prefix_data = vim.tbl_map(get_prefix_data, items)

  local lines = vim.tbl_map(H.item_to_string, items)
  local tab_spaces = string.rep(' ', vim.o.tabstop)
  lines = vim.tbl_map(function(l)
    return l:gsub('%z', '│'):gsub('[\r\n]', ' '):gsub('\t', tab_spaces)
  end, lines)

  local lines_to_show = {}
  for i, l in ipairs(lines) do
    lines_to_show[i] = prefix_data[i].text .. l
  end

  H.set_buflines(buf_id, lines_to_show)

  -- Extract match ranges
  local ns_id = H.ns_id.ranges
  H.clear_namespace(buf_id, ns_id)

  -- Highlight prefixes
  if not opts.show_icons then
    return
  end
  local icon_extmark_opts = { hl_mode = 'combine', priority = 200 }
  for i = 1, #prefix_data do
    icon_extmark_opts.hl_group = prefix_data[i].hl
    icon_extmark_opts.end_row, icon_extmark_opts.end_col = i - 1, prefix_data[i].text:len()
    H.set_extmark(buf_id, ns_id, i - 1, 0, icon_extmark_opts)
  end
end

function Jumppack.default_preview(buf_id, item, opts)
  opts = vim.tbl_deep_extend('force', { n_context_lines = 2 * vim.o.lines, line_position = 'center' }, opts or {})
  local item_data = H.parse_item(item)

  -- NOTE: ideally just setting target buffer to window would be enough, but it
  -- has side effects. See https://github.com/neovim/neovim/issues/24973 .
  -- Reading lines and applying custom styling is a passable alternative.
  local buf_id_source = item_data.buf_id

  -- Get lines from buffer ensuring it is loaded without important consequences
  local cache_eventignore = vim.o.eventignore
  vim.o.eventignore = 'BufEnter'
  vim.fn.bufload(buf_id_source)
  vim.o.eventignore = cache_eventignore
  local lines = vim.api.nvim_buf_get_lines(buf_id_source, 0, (item_data.lnum or 1) + opts.n_context_lines, false)

  item_data.filetype, item_data.line_position = vim.bo[buf_id_source].filetype, opts.line_position
  H.preview_set_lines(buf_id, lines, item_data)
end

function Jumppack.default_choose(item)
  vim.schedule(function()
    if item.direction == 'back' then
      vim.cmd(string.format([[execute "normal\! %d\<C-o>"]], item.distance))
    elseif item.direction == 'forward' then
      vim.cmd(string.format([[execute "normal\! %d\<C-i>"]], item.distance))
    elseif item.direction == 'current' then
      -- Already at current position, do nothing
      print('Already at current position')
    end
  end)
end

function Jumppack.get_opts()
  return vim.deepcopy((H.instance or {}).opts)
end

function Jumppack.get_state()
  if not Jumppack.is_active() then
    return
  end
  local instance = H.instance
  return vim.deepcopy({
    buffers = instance.buffers,
    windows = instance.windows,
    caret = instance.caret,
    is_busy = instance.is_busy,
  })
end

function Jumppack.set_items(items)
  if not vim.islist(items) then
    H.error('`items` should be an array.')
  end
  if not Jumppack.is_active() then
    return
  end
  H.set_items(H.instance, items)
end

function Jumppack.set_opts(opts)
  if not Jumppack.is_active() then
    return
  end
  local instance, cur_cwd = H.instance, H.instance.opts.source.cwd
  instance.opts = vim.tbl_deep_extend('force', instance.opts, opts or {})
  instance.action_keys = H.normalize_mappings(instance.opts.mappings)
  if cur_cwd ~= instance.opts.source.cwd then
    H.win_set_cwd(instance.windows.main, instance.opts.source.cwd)
  end
  H.update(instance, true)
end

function Jumppack.set_target_wingow(win_id)
  if not Jumppack.is_active() then
    return
  end
  if not H.is_valid_win(win_id) then
    H.error('`win_id` is not a valid window identifier.')
  end
  H.instance.windows.target = win_id
end

function Jumppack.is_active()
  return H.instance ~= nil
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(Jumppack.config)

-- Namespaces
H.ns_id = {
  headers = vim.api.nvim_create_namespace('JumppackHeaders'),
  preview = vim.api.nvim_create_namespace('JumppackPreview'),
  ranges = vim.api.nvim_create_namespace('JumppackRanges'),
}

-- Timers
H.timers = {
  focus = vim.loop.new_timer(),
  getcharstr = vim.loop.new_timer(),
}

H.instance = nil

-- General purpose cache
H.cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.jump_back', config.mappings.jump_back, 'string')
  H.check_type('mappings.jump_forward', config.mappings.jump_forward, 'string')
  H.check_type('mappings.choose', config.mappings.choose, 'string')
  H.check_type('mappings.choose_in_split', config.mappings.choose_in_split, 'string')
  H.check_type('mappings.choose_in_tabpage', config.mappings.choose_in_tabpage, 'string')
  H.check_type('mappings.choose_in_vsplit', config.mappings.choose_in_vsplit, 'string')
  H.check_type('mappings.stop', config.mappings.stop, 'string')
  H.check_type('mappings.toggle_preview', config.mappings.toggle_preview, 'string')

  H.check_type('window', config.window, 'table')
  local is_table_or_callable = function(x)
    return x == nil or type(x) == 'table' or vim.is_callable(x)
  end
  if not is_table_or_callable(config.window.config) then
    H.error('`window.config` should be table or callable, not ' .. type(config.window.config))
  end

  return config
end

function H.apply_config(config)
  Jumppack.config = config
end

function H.get_config(config)
  return vim.tbl_deep_extend('force', Jumppack.config, vim.b.minipick_config or {}, config or {})
end

function H.create_autocommands()
  local gr = vim.api.nvim_create_augroup('Jumppack', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', Jumppack.refresh, 'Refresh on resize')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

function H.create_default_hl()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('JumppackBorder', { link = 'FloatBorder' })
  hi('JumppackBorderText', { link = 'FloatTitle' })
  hi('JumppackCursor', { blend = 100, nocombine = true })
  hi('JumppackIconDirectory', { link = 'Directory' })
  hi('JumppackIconFile', { link = 'JumppackNormal' })
  hi('JumppackNormal', { link = 'NormalFloat' })
  hi('JumppackPreviewLine', { link = 'CursorLine' })
  hi('JumppackPreviewRegion', { link = 'IncSearch' })
  hi('JumppackMatchCurrent', { link = 'Visual' })
end

function H.setup_global_mappings(config)
  -- Set up global keymaps for jump navigation with count support
  vim.keymap.set('n', config.mappings.jump_back, function()
    Jumppack.start({ jumplist_direction = 'back', jumplist_distance = vim.v.count1 })
  end, { desc = 'Jump back', silent = true })

  vim.keymap.set('n', config.mappings.jump_forward, function()
    Jumppack.start({ jumplist_direction = 'forward', jumplist_distance = vim.v.count1 })
  end, { desc = 'Jump forward', silent = true })
end

function H.validate_opts(opts)
  opts = opts or {}
  if type(opts) ~= 'table' then
    H.error('Jumppack options should be table.')
  end

  opts = vim.deepcopy(H.get_config(opts))

  local validate_callable = function(x, x_name)
    if not vim.is_callable(x) then
      H.error(string.format('`%s` should be callable.', x_name))
    end
  end

  -- Source
  local source = opts.source

  local items = source.items or {}
  local is_valid_items = vim.islist(items) or vim.is_callable(items)
  if not is_valid_items then
    H.error('`source.items` should be array or callable.')
  end

  source.name = tostring(source.name or '<No name>')

  if type(source.cwd) == 'string' then
    source.cwd = H.full_path(source.cwd)
  end
  if source.cwd == nil then
    source.cwd = vim.fn.getcwd()
  end
  if vim.fn.isdirectory(source.cwd) == 0 then
    H.error('`source.cwd` should be a valid directory path.')
  end

  source.show = source.show or Jumppack.default_show
  validate_callable(source.show, 'source.show')

  source.preview = source.preview or Jumppack.default_preview
  validate_callable(source.preview, 'source.preview')

  source.choose = source.choose or Jumppack.default_choose
  validate_callable(source.choose, 'source.choose')

  -- Mappings
  for field, x in pairs(opts.mappings) do
    if type(field) ~= 'string' then
      H.error('`mappings` should have only string fields.')
    end
    if type(x) ~= 'string' then
      H.error(string.format('Mapping for action "%s" should be string.', field))
    end
  end

  -- Window
  local win_config = opts.window.config
  local is_valid_winconfig = win_config == nil or type(win_config) == 'table' or vim.is_callable(win_config)
  if not is_valid_winconfig then
    H.error('`window.config` should be table or callable.')
  end

  return opts
end

function H.new(opts)
  -- Create buffer
  local buf_id = H.new_buf()

  -- Create window
  local win_target = vim.api.nvim_get_current_win()
  local win_id = H.new_win(buf_id, opts.window.config, opts.source.cwd)

  -- Construct and return object
  local instance = {
    -- Permanent data about instance (should not change)
    opts = opts,

    -- Items to pick from
    items = nil,

    -- Associated Neovim objects
    buffers = { main = buf_id, preview = nil },
    windows = { main = win_id, target = win_target },

    -- Action keys which should be processed as described in mappings
    action_keys = H.normalize_mappings(opts.mappings),

    -- View data
    view_state = 'preview',
    visible_range = { from = nil, to = nil },
    current_ind = nil,
    shown_inds = {},
  }

  return instance
end

function H.advance(instance)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', { pattern = 'JumppackStart' })
  end)

  local is_aborted = false
  for _ = 1, 1000000 do
    if H.cache.is_force_stop_advance then
      break
    end
    H.update(instance)

    local char = H.getcharstr(10)
    if H.cache.is_force_stop_advance then
      break
    end

    is_aborted = char == nil
    if is_aborted then
      break
    end

    local cur_action = instance.action_keys[char] or {}
    is_aborted = cur_action.name == 'stop'

    if cur_action.func then
      local should_stop = cur_action.func(instance)
      if should_stop then
        break
      end
    end
  end

  local item
  if not is_aborted then
    item = H.get_current_item(instance)
  end
  H.cache.is_force_stop_advance = nil
  H.stop(instance)
  return item
end

function H.update(instance, update_window)
  if update_window then
    local config = H.compute_win_config(instance.opts.window.config)
    vim.api.nvim_win_set_config(instance.windows.main, config)
    H.set_current_ind(instance, instance.current_ind, true)
  end
  H.set_bordertext(instance)
  H.set_lines(instance)
  H.redraw()
end

function H.new_buf()
  local buf_id = H.create_scratch_buf('main')
  vim.bo[buf_id].filetype = 'minipick'
  return buf_id
end

function H.new_win(buf_id, win_config, cwd)
  -- Hide cursor while instance is active (to not be visible in the window)
  -- This mostly follows a hack from 'folke/noice.nvim'
  H.cache.guicursor = vim.o.guicursor
  vim.o.guicursor = 'a:JumppackCursor'

  -- Create window and focus on it
  local win_id = vim.api.nvim_open_win(buf_id, true, H.compute_win_config(win_config, true))

  -- Set window-local data
  vim.wo[win_id].foldenable = false
  vim.wo[win_id].foldmethod = 'manual'
  vim.wo[win_id].list = true
  vim.wo[win_id].listchars = 'extends:…'
  vim.wo[win_id].scrolloff = 0
  vim.wo[win_id].wrap = false
  H.win_update_hl(win_id, 'NormalFloat', 'JumppackNormal')
  H.win_update_hl(win_id, 'FloatBorder', 'JumppackBorder')
  vim.fn.clearmatches(win_id)

  -- Set window's local "current directory" for easier choose/preview/etc.
  H.win_set_cwd(nil, cwd)

  return win_id
end

function H.compute_win_config(win_config, is_for_open)
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local default_config = {
    relative = 'editor',
    anchor = 'SW',
    width = math.floor(0.618 * max_width),
    height = math.floor(0.618 * max_height),
    col = 0,
    row = max_height + (has_tabline and 1 or 0),
    border = (vim.fn.exists('+winborder') == 1 and vim.o.winborder ~= '') and vim.o.winborder or 'single',
    style = 'minimal',
    noautocmd = is_for_open,
    -- Use high enough value to be on top of built-in windows (pmenu, etc.)
    zindex = 251,
  }
  local config = vim.tbl_deep_extend('force', default_config, H.expand_callable(win_config) or {})

  -- Tweak config values to ensure they are proper
  if config.border == 'none' then
    config.border = { '', ' ', '', '', '', ' ', '', '' }
  end
  -- - Account for border
  config.height = math.min(config.height, max_height - 2)
  config.width = math.min(config.width, max_width - 2)

  return config
end

function H.track_lost_focus(instance)
  local track = vim.schedule_wrap(function()
    local is_cur_win = vim.api.nvim_get_current_win() == instance.windows.main
    local is_proper_focus = is_cur_win and (H.cache.is_in_getcharstr or vim.fn.mode() ~= 'n')
    if is_proper_focus then
      return
    end
    if H.cache.is_in_getcharstr then
      return vim.api.nvim_feedkeys('\3', 't', true)
    end
    H.stop(instance)
  end)
  H.timers.focus:start(1000, 1000, track)
end

function H.set_items(instance, items)
  instance.items = items

  if #items > 0 then
    -- Check for cached initial selection from jumplist instance
    local initial_ind = _G._jumplist_initial_selection or 1
    H.set_current_ind(instance, initial_ind)
    -- Clear the cache after using it
    _G._jumplist_initial_selection = nil
    -- Force update with the new index
    H.set_current_ind(instance, initial_ind, true)
    -- Show preview by default instead of main
    H.show_preview(instance)
  end

  H.update(instance)
end

function H.item_to_string(item)
  item = H.expand_callable(item)
  if type(item) == 'string' then
    return item
  end
  if type(item) == 'table' and type(item.text) == 'string' then
    return item.text
  end
  return vim.inspect(item, { newline = ' ', indent = '' })
end

function H.set_current_ind(instance, ind, force_update)
  if instance.items == nil or #instance.items == 0 then
    instance.current_ind, instance.visible_range = nil, {}
    return
  end

  -- Wrap index around edges
  local n_matches = #instance.items
  ind = (ind - 1) % n_matches + 1

  -- (Re)Compute visible range (centers current index if it is currently outside)
  local from, to = instance.visible_range.from, instance.visible_range.to
  local needs_update = from == nil or to == nil or not (from <= ind and ind <= to)
  if (force_update or needs_update) and H.is_valid_win(instance.windows.main) then
    local win_height = vim.api.nvim_win_get_height(instance.windows.main)
    to = math.min(n_matches, math.floor(ind + 0.5 * win_height))
    from = math.max(1, to - win_height + 1)
    to = from + math.min(win_height, n_matches) - 1
  end

  -- Set data
  instance.current_ind = ind
  instance.visible_range = { from = from, to = to }
end

function H.set_lines(instance)
  local buf_id, win_id = instance.buffers.main, instance.windows.main
  if not (H.is_valid_buf(buf_id) and H.is_valid_win(win_id)) then
    return
  end

  local visible_range = instance.visible_range
  if instance.items == nil or visible_range.from == nil or visible_range.to == nil then
    instance.shown_inds = {}
    instance.opts.source.show(buf_id, {})
    return
  end

  -- Construct target items
  local items_to_show, items, shown_inds = {}, instance.items, {}
  local cur_ind, cur_line = instance.current_ind, nil
  local from = visible_range.from
  local to = visible_range.to
  for i = from, to, (from <= to and 1 or -1) do
    table.insert(shown_inds, i)
    table.insert(items_to_show, items[i])
    if i == cur_ind then
      cur_line = #items_to_show
    end
  end

  -- Update visible lines accounting for "from_bottom" direction
  instance.shown_inds = shown_inds
  instance.opts.source.show(buf_id, items_to_show)

  local ns_id = H.ns_id.ranges
  H.clear_namespace(buf_id, ns_id)

  -- Update current item
  if cur_line > vim.api.nvim_buf_line_count(buf_id) then
    return
  end

  local cur_opts = { end_row = cur_line, end_col = 0, hl_eol = true, hl_group = 'JumppackMatchCurrent', priority = 201 }
  H.set_extmark(buf_id, ns_id, cur_line - 1, 0, cur_opts)
end

function H.normalize_mappings(mappings)
  local res = {}
  local add_to_res = function(char, data)
    local key = H.replace_termcodes(char)
    if key == nil or key == '' then
      return
    end
    res[key] = data
  end

  for name, char in pairs(mappings) do
    local data = { char = char, name = name, func = H.actions[name] }
    add_to_res(char, data)
  end

  return res
end

function H.set_bordertext(instance)
  local win_id = instance.windows.main
  if not H.is_valid_win(win_id) then
    return
  end

  -- Compute main text managing views separately and truncating from left
  local view_state, win_width = instance.view_state, vim.api.nvim_win_get_width(win_id)
  local config = {}

  local has_items = instance.items ~= nil
  if view_state == 'preview' and has_items and instance.current_ind then
    local current_item = instance.items[instance.current_ind]
    if current_item then
      local stritem_cur = H.item_to_string(current_item) or ''
      -- Sanitize title
      stritem_cur = stritem_cur:gsub('%z', '│'):gsub('%s', ' ')
      config = { title = { { H.fit_to_width(' ' .. stritem_cur .. ' ', win_width), 'JumppackBorderText' } } }
    end
  end

  -- Compute helper footer
  local nvim_has_window_footer = vim.fn.has('nvim-0.10') == 1
  if nvim_has_window_footer then
    config.footer, config.footer_pos = H.compute_footer(instance, win_id), 'left'
  end

  vim.api.nvim_win_set_config(win_id, config)
  vim.wo[win_id].list = true
end

function H.compute_footer(instance, win_id)
  local info = H.get_general_info(instance)
  local source_name = string.format(' %s ', info.source_name)
  local inds = string.format(' %s|%s', info.relative_current_ind, info.n_total)
  local win_width, source_width, inds_width =
    vim.api.nvim_win_get_width(win_id), vim.fn.strchars(source_name), vim.fn.strchars(inds)

  local footer = { { H.fit_to_width(source_name, win_width), 'JumppackBorderText' } }
  local n_spaces_between = win_width - (source_width + inds_width)
  if n_spaces_between > 0 then
    footer[2] = { H.win_get_bottom_border(win_id):rep(n_spaces_between), 'JumppackBorder' }
    footer[3] = { inds, 'JumppackBorderText' }
  end
  return footer
end

function H.stop(instance)
  vim.tbl_map(function(timer)
    pcall(vim.loop.timer_stop, timer)
  end, H.timers)

  -- Show cursor (work around `guicursor=''` actually leaving cursor hidden)
  if H.cache.guicursor == '' then
    vim.cmd('set guicursor=a: | redraw')
  end
  pcall(function()
    vim.o.guicursor = H.cache.guicursor
  end)

  if instance == nil then
    return
  end

  vim.api.nvim_exec_autocmds('User', { pattern = 'JumppackStop' })
  H.instance = nil

  H.set_curwin(instance.windows.target)
  pcall(vim.api.nvim_win_close, instance.windows.main, true)
  pcall(vim.api.nvim_buf_delete, instance.buffers.main, { force = true })
  instance.windows, instance.buffers = {}, {}
end

H.actions = {
  jump_back = function(instance, _)
    H.move_current(instance, 1)
  end,
  jump_forward = function(instance, _)
    H.move_current(instance, -1)
  end,

  choose = function(instance, _)
    return H.choose(instance, nil)
  end,
  choose_in_split = function(instance, _)
    return H.choose(instance, 'split')
  end,
  choose_in_tabpage = function(instance, _)
    return H.choose(instance, 'tab split')
  end,
  choose_in_vsplit = function(instance, _)
    return H.choose(instance, 'vsplit')
  end,

  toggle_preview = function(instance, _)
    if instance.view_state == 'preview' then
      return H.show_main(instance)
    end
    H.show_preview(instance)
  end,

  stop = function(_, _)
    return true
  end,
}

function H.choose(instance, pre_command)
  local cur_item = H.get_current_item(instance)
  if cur_item == nil then
    return true
  end

  local win_id_target = instance.windows.target
  if pre_command ~= nil and H.is_valid_win(win_id_target) then
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
      H.error('Error during choose:\n' .. res)
    end)
  end
  -- Error or returning nothing, `nil`, or `false` should lead to instance stop
  return not (ok and res)
end

function H.move_current(instance, by, to)
  if instance.items == nil then
    return
  end
  local n_matches = #instance.items
  if n_matches == 0 then
    return
  end

  if to == nil then
    -- Wrap around edges only if current index is at edge
    to = instance.current_ind
    if to == 1 and by < 0 then
      to = n_matches
    elseif to == n_matches and by > 0 then
      to = 1
    else
      to = to + by
    end
    to = math.min(math.max(to, 1), n_matches)
  end

  H.set_current_ind(instance, to)

  -- Update not main buffer(s)
  if instance.view_state == 'preview' then
    H.show_preview(instance)
  end
end

function H.get_current_item(instance)
  if instance.items == nil then
    return nil
  end
  return instance.items[instance.current_ind]
end

function H.show_main(instance)
  H.set_winbuf(instance.windows.main, instance.buffers.main)
  instance.view_state = 'main'
end

function H.get_general_info(instance)
  local has_items = instance.items ~= nil
  return {
    source_name = instance.opts.source.name or '---',
    source_cwd = vim.fn.fnamemodify(instance.opts.source.cwd, ':~') or '---',
    n_total = has_items and #instance.items or '-',
    relative_current_ind = has_items and instance.current_ind or '-',
  }
end

function H.show_preview(instance)
  local preview = instance.opts.source.preview
  local item = H.get_current_item(instance)
  if item == nil then
    return
  end

  local win_id, buf_id = instance.windows.main, H.create_scratch_buf('preview')
  vim.bo[buf_id].bufhidden = 'wipe'
  H.set_winbuf(win_id, buf_id)
  preview(buf_id, item)
  instance.buffers.preview = buf_id
  instance.view_state = 'preview'
end

-- Default show ---------------------------------------------------------------
function H.get_icon(x, icons)
  local item_data = H.parse_item(x)
  local path = item_data.path or item_data.text or ''
  local path_type = H.get_fs_type(path)
  if path_type == 'none' then
    return { text = icons.none, hl = 'JumppackNormal' }
  end

  if _G.MiniIcons ~= nil then
    local category = path_type == 'directory' and 'directory' or 'file'
    local icon, hl = _G.MiniIcons.get(category, path)
    return { text = icon .. ' ', hl = hl }
  end

  if path_type == 'directory' then
    return { text = icons.directory, hl = 'JumppackIconDirectory' }
  end
  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  if not has_devicons then
    return { text = icons.file, hl = 'JumppackIconFile' }
  end

  local icon, hl = devicons.get_icon(vim.fn.fnamemodify(path, ':t'), nil, { default = false })
  icon = type(icon) == 'string' and (icon .. ' ') or icons.file
  return { text = icon, hl = hl or 'JumppackIconFile' }
end

function H.show_with_icons(buf_id, items)
  Jumppack.default_show(buf_id, items, { show_icons = true })
end

-- Items helpers for default functions ----------------------------------------
function H.parse_item(item)
  -- Try parsing table item first
  if type(item) == 'table' then
    return H.parse_item_table(item)
  end

  -- Parse item's string representation
  local stritem = H.item_to_string(item)

  -- - Buffer
  local ok, numitem = pcall(tonumber, stritem)
  if ok and H.is_valid_buf(numitem) then
    return { type = 'buffer', buf_id = numitem }
  end

  -- File or Directory
  local path_type, path, lnum, col, rest = H.parse_path(stritem)
  if path_type ~= 'none' then
    return { type = path_type, path = path, lnum = lnum, col = col, text = rest }
  end

  return {}
end

function H.parse_item_table(item)
  -- Buffer
  local buf_id = item.bufnr or item.buf_id or item.buf
  if H.is_valid_buf(buf_id) then
    return {
      type = 'buffer',
      buf_id = buf_id,
      path = item.path or vim.api.nvim_buf_get_name(buf_id),
      lnum = item.lnum,
      end_lnum = item.end_lnum,
      col = item.col,
      end_col = item.end_col,
      text = item.text,
    }
  end

  -- File or Directory
  if type(item.path) == 'string' then
    local path_type = H.get_fs_type(item.path)
    if path_type == 'file' then
      return {
        type = path_type,
        path = item.path,
        lnum = item.lnum,
        end_lnum = item.end_lnum,
        col = item.col,
        end_col = item.end_col,
        text = item.text,
      }
    end

    if path_type == 'directory' then
      return { type = 'directory', path = item.path }
    end
  end

  return {}
end

function H.parse_path(x)
  if type(x) ~= 'string' or x == '' then
    return nil
  end
  -- Allow inputs like 'aa/bb', 'aa-5'. Also allow inputs for line/position
  -- separated by null character:
  -- - 'aa/bb\00010' (line 10).
  -- - 'aa/bb\00010\0005' (line 10, col 5).
  -- - 'aa/bb\00010\0005\000xx' (line 10, col 5, with "xx" description).
  local location_pattern = '()%z(%d+)%z?(%d*)%z?(.*)$'
  local from, lnum, col, rest = x:match(location_pattern)
  local path = x:sub(1, (from or 0) - 1)
  path = path:sub(1, 1) == '~' and ((vim.loop.os_homedir() or '~') .. path:sub(2)) or path

  -- Verify that path is real
  local path_type = H.get_fs_type(path)
  if path_type == 'none' and path ~= '' then
    local cwd = H.instance == nil and vim.fn.getcwd() or H.instance.opts.source.cwd
    path = string.format('%s/%s', cwd, path)
    path_type = H.get_fs_type(path)
  end

  return path_type, path, tonumber(lnum), tonumber(col), rest or ''
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

function H.preview_set_lines(buf_id, lines, extra)
  -- Lines
  H.set_buflines(buf_id, lines)

  -- Highlighting
  H.preview_highlight_region(buf_id, extra.lnum, extra.col, extra.end_lnum, extra.end_col)

  if H.preview_should_highlight(buf_id) then
    local ft = extra.filetype or vim.filetype.match({ buf = buf_id, filename = extra.path })
    local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
    lang = has_lang and lang or ft
    -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
    local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, lang, { error = false })
    has_parser = has_parser and parser ~= nil
    if has_parser then
      has_parser = pcall(vim.treesitter.start, buf_id, lang)
    end
    if not has_parser then
      vim.bo[buf_id].syntax = ft
    end
  end

  -- Cursor position and window view. Find window (and not use instance window)
  -- for "outside window preview" (preview and main are different) to work.
  local win_id = vim.fn.bufwinid(buf_id)
  if win_id == -1 then
    return
  end
  H.set_cursor(win_id, extra.lnum, extra.col)
  local pos_keys = ({ top = 'zt', center = 'zz', bottom = 'zb' })[extra.line_position] or 'zt'
  pcall(vim.api.nvim_win_call, win_id, function()
    vim.cmd('normal! ' .. pos_keys)
  end)
end

function H.preview_should_highlight(buf_id)
  -- Highlight if buffer size is not too big, both in total and per line
  local buf_size = vim.api.nvim_buf_call(buf_id, function()
    return vim.fn.line2byte(vim.fn.line('$') + 1)
  end)
  return buf_size <= 1000000 and buf_size <= 1000 * vim.api.nvim_buf_line_count(buf_id)
end

function H.preview_highlight_region(buf_id, lnum, col, end_lnum, end_col)
  -- Highlight line
  if lnum == nil then
    return
  end
  local hl_line_opts = { end_row = lnum, end_col = 0, hl_eol = true, hl_group = 'JumppackPreviewLine', priority = 201 }
  H.set_extmark(buf_id, H.ns_id.preview, lnum - 1, 0, hl_line_opts)

  -- Highlight position/region
  if col == nil then
    return
  end

  local ext_end_row, ext_end_col = lnum - 1, col
  if end_lnum ~= nil and end_col ~= nil then
    ext_end_row, ext_end_col = end_lnum - 1, end_col - 1
  end
  local bufline = vim.fn.getbufline(buf_id, ext_end_row + 1)[1]
  ext_end_col = H.get_next_char_bytecol(bufline, ext_end_col)

  local hl_region_opts = { end_row = ext_end_row, end_col = ext_end_col, priority = 202 }
  hl_region_opts.hl_group = 'JumppackPreviewRegion'
  H.set_extmark(buf_id, H.ns_id.preview, lnum - 1, col - 1, hl_region_opts)
end

-- Utilities ------------------------------------------------------------------
function H.error(msg)
  error('(jumppack) ' .. msg, 0)
end

function H.check_type(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then
    return
  end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

function H.set_buf_name(buf_id, name)
  vim.api.nvim_buf_set_name(buf_id, 'jumppack://' .. buf_id .. '/' .. name)
end

function H.notify(msg, level_name)
  vim.notify('(jumppack) ' .. msg, vim.log.levels[level_name])
end

function H.edit(path, win_id)
  if type(path) ~= 'string' then
    return
  end
  local b = vim.api.nvim_win_get_buf(win_id or 0)
  local try_mimic_buf_reuse = (vim.fn.bufname(b) == '' and vim.bo[b].buftype ~= 'quickfix' and not vim.bo[b].modified)
    and (#vim.fn.win_findbuf(b) == 1 and vim.deep_equal(vim.fn.getbufline(b, 1, '$'), { '' }))
  local buf_id = vim.fn.bufadd(vim.fn.fnamemodify(path, ':.'))
  -- Showing in window also loads. Use `pcall` to not error with swap messages.
  pcall(vim.api.nvim_win_set_buf, win_id or 0, buf_id)
  vim.bo[buf_id].buflisted = true
  if try_mimic_buf_reuse then
    pcall(vim.api.nvim_buf_delete, b, { unload = false })
  end
  return buf_id
end

function H.is_valid_buf(buf_id)
  return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id)
end

function H.is_valid_win(win_id)
  return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id)
end

function H.create_scratch_buf(name)
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(buf_id, name)
  vim.bo[buf_id].matchpairs = ''
  vim.b[buf_id].minicursorword_disable = true
  vim.b[buf_id].miniindentscope_disable = true
  return buf_id
end

function H.get_first_valid_normal_window()
  for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win_id).relative == '' then
      return win_id
    end
  end
end

function H.set_buflines(buf_id, lines)
  pcall(vim.api.nvim_buf_set_lines, buf_id, 0, -1, false, lines)
end

function H.set_winbuf(win_id, buf_id)
  vim.api.nvim_win_set_buf(win_id, buf_id)
end

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

H.redraw_scheduled = vim.schedule_wrap(H.redraw)

function H.getcharstr(delay_async)
  H.timers.getcharstr:start(0, delay_async, H.redraw_scheduled)
  H.cache.is_in_getcharstr = true
  local ok, char = pcall(vim.fn.getcharstr)
  H.cache.is_in_getcharstr = nil
  H.timers.getcharstr:stop()

  local main_win_id
  if H.instance ~= nil then
    main_win_id = H.instance.windows.main
  end
  local is_bad_mouse_click = vim.v.mouse_winid ~= 0 and vim.v.mouse_winid ~= main_win_id
  if not ok or char == '' or char == '\3' or is_bad_mouse_click then
    return
  end
  return char
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
  return vim.str_byteindex(line_str, utf_index)
end

function H.full_path(path)
  return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1'))
end

local function get_all_jumps()
  local jumps = vim.fn.getjumplist()
  local jumplist = jumps[1]
  local current = jumps[2]

  local all_jumps = {}
  local current_jump_index = nil

  -- Process all jumps in the jumplist
  for i = 1, #jumplist do
    local jump = jumplist[i]
    if jump.bufnr > 0 and vim.fn.buflisted(jump.bufnr) == 1 then
      local bufname = vim.fn.bufname(jump.bufnr)
      if bufname ~= '' then
        local filename = vim.fn.fnamemodify(bufname, ':.')
        local line_content = ''
        if vim.fn.bufloaded(jump.bufnr) == 1 then
          local lines = vim.fn.getbufline(jump.bufnr, jump.lnum)
          if #lines > 0 then
            line_content = vim.trim(lines[1])
          end
        end

        local jump_item = {
          bufnr = jump.bufnr,
          lnum = jump.lnum,
          col = jump.col + 1,
          jump_index = i,
          is_current = (i == current + 1),
        }

        -- Determine navigation direction and distance
        if i <= current then
          -- Older jump (go back with <C-o>)
          jump_item.direction = 'back'
          jump_item.distance = current - i + 1
          jump_item.text = string.format('← %d  %s:%d %s', jump_item.distance, filename, jump.lnum, line_content)
        elseif i == current + 1 then
          -- Current position
          jump_item.direction = 'current'
          jump_item.distance = 0
          jump_item.text = string.format('[CURRENT] %s:%d %s', filename, jump.lnum, line_content)
          current_jump_index = #all_jumps + 1
        else
          -- Newer jump (go forward with <C-i>)
          jump_item.direction = 'forward'
          jump_item.distance = i - current - 1
          jump_item.text = string.format('→ %d  %s:%d %s', jump_item.distance, filename, jump.lnum, line_content)
        end

        table.insert(all_jumps, jump_item)
      end
    end
  end

  -- Reverse the order so most recent jumps are at the top
  local reversed_jumps = {}
  for i = #all_jumps, 1, -1 do
    table.insert(reversed_jumps, all_jumps[i])
  end

  -- Update current_jump_index for the reversed list
  local reversed_current_index = nil
  if current_jump_index then
    reversed_current_index = #all_jumps - current_jump_index + 1
  end

  return reversed_jumps, reversed_current_index
end

-- Helper function to create jumplist source configuration
function H.create_jumplist_source(direction, distance)
  local all_jumps, _ = get_all_jumps()

  if #all_jumps == 0 then
    print('No jumps available')
    return nil
  end

  -- Calculate initial selection based on direction/distance
  local initial_selection = 1
  local found_target = false

  if direction then
    if distance then
      -- Find jump with specific distance
      for i, jump in ipairs(all_jumps) do
        local jump_distance = jump.distance and tonumber(jump.distance)
        if jump.direction == direction and jump_distance == distance then
          initial_selection = i
          found_target = true
          break
        end
      end

      -- If exact distance not found, fall back to distance 1
      if not found_target then
        for i, jump in ipairs(all_jumps) do
          local jump_distance = jump.distance and tonumber(jump.distance)
          if jump.direction == direction and jump_distance == 1 then
            initial_selection = i
            found_target = true
            break
          end
        end
      end
    else
      -- Find immediate jump (distance 1)
      for i, jump in ipairs(all_jumps) do
        if jump.direction == direction and jump.distance == 1 then
          initial_selection = i
          found_target = true
          break
        end
      end
    end

    -- If no target found in direction, try current position
    if not found_target and direction == 'forward' then
      for i, jump in ipairs(all_jumps) do
        if jump.direction == 'current' then
          initial_selection = i
          found_target = true
          break
        end
      end
    end
  end

  -- If still no target found, find current position
  if not found_target then
    for i, jump in ipairs(all_jumps) do
      if jump.direction == 'current' then
        initial_selection = i
        break
      end
    end
  end

  -- Store the initial selection
  _G._jumplist_initial_selection = initial_selection

  return {
    name = 'Jumplist',
    items = all_jumps,
    show = function(buf_id, items)
      Jumppack.default_show(buf_id, items, { show_icons = true })
    end,
    preview = function(buf_id, item, opts)
      if item and item.bufnr then
        local preview_opts = vim.tbl_extend('force', opts or {}, {
          line_position = 'center',
        })
        Jumppack.default_preview(buf_id, item, preview_opts)
      end
    end,
    choose = vim.schedule_wrap(function(item)
      if item.direction == 'back' then
        vim.cmd(string.format([[execute "normal\! %d\<C-o>"]], item.distance))
      elseif item.direction == 'forward' then
        vim.cmd(string.format([[execute "normal\! %d\<C-i>"]], item.distance))
      elseif item.direction == 'current' then
        -- Already at current position, do nothing
        print('Already at current position')
      end
    end),
  }
end

return Jumppack
