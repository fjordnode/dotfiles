-- ===========================
--   Neovim Starter Config
-- ===========================

-- --- Load Lazy Lua --- --
require("config.lazy")

-- --- Basic Settings ---
vim.opt.number = true           -- Show absolute line number
vim.opt.tabstop = 4             -- Tab width (spaces displayed as 4)
vim.opt.shiftwidth = 4          -- Auto-indent size
vim.opt.expandtab = true        -- Convert tabs to spaces
vim.opt.smartindent = true      -- Auto-indent intelligently
vim.opt.mouse = "a"             -- Enable mouse support
vim.opt.ignorecase = true       -- Case-insensitive search
vim.opt.smartcase = true        -- ...unless uppercase is used
vim.opt.cursorline = true       -- Highlight current line

-- Auto-copy visual selections to clipboard
vim.keymap.set('v', 'y', '"+y', { desc = 'Yank to system clipboard' })
vim.keymap.set('v', 'Y', '"+Y', { desc = 'Yank line to system clipboard' })

-- Leader-based clipboard operations
vim.keymap.set({'n', 'v'}, '<leader>y', '"+y', { desc = 'Yank to clipboard' })
vim.keymap.set('n', '<leader>Y', '"+Y', { desc = 'Yank line to clipboard' })

-- Note: clipboard provider is set below using OSC 52
vim.keymap.set('v', '<LeftRelease>', '"+y<LeftRelease>', { desc = 'Copy mouse selection to clipboard' })
vim.keymap.set('v', '<2-LeftMouse>', '"+y<2-LeftMouse>', { desc = 'Copy double-click selection to clipboard' })

-- OSC 52 clipboard. Neovim writes the sequence through its active UI, allowing
-- SSH/Mosh and compatible terminals can forward it to the local clipboard.
local osc52 = require('vim.ui.clipboard.osc52')
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = osc52.copy('+'),
    ['*'] = osc52.copy('*'),
  },
  paste = {
    ['+'] = osc52.paste('+'),
    ['*'] = osc52.paste('*'),
  },
}

-- --- Visual Styling ---
-- Old styling (commented out)
-- vim.api.nvim_set_hl(0, "CursorLine", { bg = "#404040" }) -- Much more visible
-- vim.api.nvim_set_hl(0, "LineNr", { fg = "#FFA500" })   -- Normal line numbers
-- vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#FFB52E", bold = true }) -- Current line number

-- Match kitty's Catppuccin Mocha background (disabled for terminal color extraction)
-- vim.cmd("highlight Normal guibg=#1e1e2e")
-- vim.cmd("highlight NonText guibg=#1e1e2e")
-- vim.cmd("highlight SignColumn guibg=#1e1e2e")
-- vim.cmd("highlight LineNr guibg=#1e1e2e")
-- vim.api.nvim_set_hl(0, "CursorLine", { bg = "#313244" }) -- Darker than background
-- vim.api.nvim_set_hl(0, "LineNr", { fg = "#6c7086", bg = "#1e1e2e" })   -- Catppuccin overlay0
-- vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#F5C2E7", bold = true, bg = "#1e1e2e" }) -- Pink accent

-- Enable true colors for Catppuccin theme
vim.opt.termguicolors = true 

-- --- Norwegian Keyboard Remaps (Normal Mode) ---
vim.keymap.set('n', 'æ', '$')          -- End of line
vim.keymap.set('n', 'ø', '0')          -- Start of line
vim.keymap.set('n', '¨', '|')          -- Move to column
vim.keymap.set('n', '<A-~>', '~')      -- Swap case

-- --- Norwegian Keyboard Remaps (Insert Mode) ---
vim.keymap.set('i', '<A-4>', '$')      -- AltGr+4 fix
vim.keymap.set('i', '<A-7>', '{')
vim.keymap.set('i', '<A-0>', '}')
vim.keymap.set('i', '<A-¨>', '~')
vim.keymap.set('i', '<A-<>', '|')

-- --- Enhanced Delete/Cut Operations ---
-- Leader-based delete without yanking
vim.keymap.set({'n', 'v'}, '<leader>d', '"_d', { desc = 'Delete without yanking' })
vim.keymap.set('n', '<leader>dd', '"_dd', { desc = 'Delete line without yanking' })
vim.keymap.set({'n', 'v'}, '<leader>D', 'd', { desc = 'Cut (delete + yank)' })
vim.keymap.set('n', '<leader>r', 'V"+p', { desc = 'Replace line with clipboard' })

-- Character operations
vim.keymap.set('n', 'x', '"_x', { desc = 'Delete char without yanking' })
vim.keymap.set('v', 'x', '"_x', { desc = 'Delete selection without yanking' })
vim.keymap.set('n', 'X', 'x', { desc = 'Cut char (like traditional Vim)' })
vim.keymap.set('v', 'X', 'd', { desc = 'Cut selection (like traditional Vim)' })

-- --- Navigation Enhancements ---
-- Center after search/jump actions
vim.keymap.set('n', 'n', 'nzz')     -- next search result
vim.keymap.set('n', 'N', 'Nzz')     -- previous search result
vim.keymap.set('n', 'G', 'Gzz')     -- end of file
vim.keymap.set('n', '{', '{zz')     -- paragraph back
vim.keymap.set('n', '}', '}zz')     -- paragraph forward
-- More auto-centering
vim.keymap.set('n', '<C-d>', '<C-d>zz', { desc = 'Half page down + center' })
vim.keymap.set('n', '<C-u>', '<C-u>zz', { desc = 'Half page up + center' })
vim.keymap.set('n', '<C-f>', '<C-f>zz', { desc = 'Full page down + center' })
vim.keymap.set('n', '<C-b>', '<C-b>zz', { desc = 'Full page up + center' })

-- Center when jumping to marks
vim.keymap.set('n', "'", "'zz", { desc = 'Jump to mark + center' })
vim.keymap.set('n', '`', '`zz', { desc = 'Jump to mark exact + center' })

-- Center on line joins
vim.keymap.set('n', 'J', 'Jzz', { desc = 'Join lines + center' })
