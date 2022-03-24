require("plugins")
require("keybinds")
require("lang_support")
require("snippets")
require("setup/telescope")
require("setup/vimtest")
require("setup/floaterm")
require("setup/defx")
require("setup/lualine")
require("setup/autopairs")
require("setup/treesitter")
require("setup/completion")
require("setup/format")
require("setup/vimwiki")
require("setup/comment")
require("setup/rainbow")
require("setup/close_tag")
require("setup/nvim_tree")

-- ui configuration
vim.g.fillchars = "vim.g.fillchars" .. "vert:\\|"
vim.o.signcolumn = "yes"
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.o.listchars = "eol:$,tab:>-,space:_,lead:_,trail:_,extends:>,precedes:<,nbsp:&"
vim.o.hidden = true
vim.cmd([[ set nowrap ]])
vim.cmd([[ set clipboard=unnamed,unnamedplus ]])
vim.cmd([[ set foldmethod=indent ]])
vim.cmd([[ set foldlevel=20 ]])
vim.cmd([[ set foldnestmax=20 ]])
vim.cmd([[ set nofoldenable ]])
vim.cmd([[ set termguicolors ]])

-- indentation configuration
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.expandtab = true

-- colors configuration
vim.g.termguicolors = true
vim.g.background = "dark"
vim.g.t_8f = "ESC[38;2;%lu;%lu;%lum"
vim.g.t_8b = "ESC[48;2;%lu;%lu;%lum"

-- dracula_pro theme
vim.cmd([[ packadd! dracula_pro ]])
vim.cmd([[ let g:dracula_colorterm = 0 ]])
-- vim.cmd([[ autocmd ColorScheme dracula_pro* hi CursorLine cterm=underline term=underline ]])
vim.cmd([[ autocmd ColorScheme dracula_pro* hi Pmenu ctermfg=15 ctermbg=60 cterm=NONE guifg=#f8f8f2 guibg=#393649 gui=NONE ]])
vim.cmd([[ autocmd ColorScheme dracula_pro* hi PmenuSel ctermfg=16 ctermbg=86 cterm=bold guifg=#282a36 guibg=#8AFF80 gui=NONE ]])

vim.cmd([[ colorscheme dracula_pro ]])

vim.cmd([[ hi VertSplit guibg=NONE guifg=fg ]])

-- terminal configuration
vim.cmd([[ autocmd TermOpen * setlocal nonumber norelativenumber ]])
vim.cmd([[ autocmd BufEnter term://* setlocal nonumber norelativenumber ]])
vim.cmd([[ autocmd TermOpen * set bufhidden=hide ]])
