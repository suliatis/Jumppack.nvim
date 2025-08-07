---@brief [[Documentation generation script for Jumppack.nvim]]

-- This script generates Neovim help documentation from the annotated Lua source code
-- using mini.doc. It should be run from the project root directory.

local function setup_mini_doc()
  -- Try to find mini.doc or install it
  local has_mini_doc = pcall(require, 'mini.doc')

  if not has_mini_doc then
    -- Check if we can install mini.doc via package manager
    local mini_doc_path = vim.fn.stdpath('data') .. '/lazy/mini.nvim'

    if vim.fn.isdirectory(mini_doc_path) == 0 then
      -- Try to clone mini.nvim if not available
      print('Installing mini.nvim for documentation generation...')
      local cmd = string.format('git clone https://github.com/echasnovski/mini.nvim %s', mini_doc_path)
      if os.execute(cmd) ~= 0 then
        error('Failed to install mini.nvim. Please install it manually or use a package manager.')
      end
    end

    -- Add to runtime path
    vim.opt.runtimepath:prepend(mini_doc_path)

    -- Try to require again
    has_mini_doc = pcall(require, 'mini.doc')
    if not has_mini_doc then
      error('Could not load mini.doc even after installation attempt')
    end
  end

  return require('mini.doc')
end

local function generate_documentation()
  print('Starting documentation generation...')

  -- Setup mini.doc
  local MiniDoc = setup_mini_doc()

  -- Get output path
  local output_path = os.getenv('TEMP_DOC') or 'doc/jumppack.txt'
  print('Using output path: ' .. output_path)

  -- Configure mini.doc
  MiniDoc.setup({
    -- Input files (source code with annotations)
    input = { 'lua/Jumppack.lua' },

    -- Output file (help documentation)
    output = output_path,

    -- Configuration for documentation generation
    hooks = {
      -- Custom processing for better help file format
      write_pre = function(lines)
        -- Add proper help file header
        local header_lines = {
          '*jumppack.txt*    Enhanced jumplist navigation for Neovim',
          '',
          'JUMPPACK                                              *jumppack* *jumppack.nvim*',
          '',
          'Enhanced jumplist navigation interface with floating window preview.',
          'Navigate your jump history with visual feedback and flexible controls.',
          '',
          '==============================================================================',
          'CONTENTS                                               *jumppack-contents*',
          '',
          '1. Introduction ................... |jumppack-introduction|',
          '2. Setup .......................... |jumppack-setup|',
          '3. Configuration .................. |jumppack-configuration|',
          '4. Usage .......................... |jumppack-usage|',
          '5. API Functions .................. |jumppack-api|',
          '6. Navigation ..................... |jumppack-navigation|',
          '7. Display Options ................ |jumppack-display|',
          '8. Interface Management ........... |jumppack-interface-management|',
          '',
          '==============================================================================',
          'INTRODUCTION                                       *jumppack-introduction*',
          '',
          'Jumppack provides an enhanced navigation interface for Neovim\'s jumplist.',
          'The plugin creates a floating window interface that allows users to',
          'visualize and navigate their jump history with preview functionality.',
          '',
          'Features:',
          '  • Floating window interface for jump navigation',
          '  • Preview mode showing destination content',
          '  • Configurable key mappings and window appearance',
          '  • Filtering options (current working directory only)',
          '  • Edge wrapping for continuous navigation',
          '  • Icon support with file type detection',
          '',
          '==============================================================================',
          'SETUP                                                   *jumppack-setup*',
          '',
        }

        -- Prepend header to generated content
        for i = #header_lines, 1, -1 do
          table.insert(lines, 1, header_lines[i])
        end

        return lines
      end,

      -- Post-process to add proper help tags and formatting
      write_post = function(lines)
        -- Add footer
        local footer_lines = {
          '',
          '==============================================================================',
          'vim:tw=78:ts=8:ft=help:norl:',
        }

        for _, line in ipairs(footer_lines) do
          table.insert(lines, line)
        end

        return lines
      end,
    },

    -- Script path for processing
    script_path = 'scripts/docs_scripts.lua',
  })

  -- Generate the documentation
  print('Processing annotations and generating help file...')
  MiniDoc.generate()

  -- Handle temp doc case by moving file if needed
  local temp_doc = os.getenv('TEMP_DOC')
  local output_file = temp_doc or 'doc/jumppack.txt'

  if temp_doc and vim.fn.filereadable('doc/jumppack.txt') == 1 then
    -- Copy generated file to temp location, preserving exact format
    local lines = vim.fn.readfile('doc/jumppack.txt')
    -- Write without adding final newline to match original format
    vim.fn.writefile(lines, temp_doc, 'b')
  end

  print('Documentation generation completed successfully!')
  print('Generated: ' .. output_file)
  if vim.fn.filereadable(output_file) == 1 then
    local lines = vim.fn.readfile(output_file)
    print(string.format('Generated %d lines of documentation', #lines))

    -- Show first few lines as confirmation
    print('Preview of generated documentation:')
    for i = 1, math.min(5, #lines) do
      print('  ' .. lines[i])
    end
    if #lines > 5 then
      print('  ...')
    end
  else
    error('Output file was not created: ' .. output_file)
  end
end

local function main()
  -- Ensure we're in the right directory
  local jumppack_file = 'lua/Jumppack.lua'
  if vim.fn.filereadable(jumppack_file) == 0 then
    error('Could not find ' .. jumppack_file .. '. Please run from project root directory.')
  end

  -- Create doc directory if it doesn't exist
  local output_file = os.getenv('TEMP_DOC') or 'doc/jumppack.txt'
  local output_dir = vim.fn.fnamemodify(output_file, ':h')
  if vim.fn.isdirectory(output_dir) == 0 then
    vim.fn.mkdir(output_dir, 'p')
  end

  -- Generate documentation
  local success, err = pcall(generate_documentation)

  if not success then
    print('Error generating documentation: ' .. tostring(err))
    vim.cmd('cquit 1') -- Exit with error code 1
  else
    print('Documentation generation completed successfully')
    vim.cmd('qall!') -- Exit successfully
  end
end

-- Run the main function
main()
