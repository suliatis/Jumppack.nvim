local MiniDoc = require('mini.doc')
local output_path = vim.env.TEMP_DOC or 'doc/Jumppack.txt'
MiniDoc.generate({ 'lua/Jumppack.lua' }, output_path)
