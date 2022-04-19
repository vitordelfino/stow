vim.cmd([[ let g:glow_binary_path = $HOME . "/bin" ]])
vim.cmd([[ let g:glow_border = "rounded" ]])
vim.cmd([[ let g:glow_use_pager = v:true ]])

vim.api.nvim_set_keymap("n", "<leader>g", ":Glow<CR>", {noremap = true, silent = true})
