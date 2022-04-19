local carbon = require('carbon-now')

carbon.setup({
  open_cmd = "open",
  -- options = {
  --   theme = "Dracula Pro",
  --   font_family = "Jetbrains Mono",
  -- },
  options = {
    theme = "Dracula Pro",
    font_family = "JetBrains Mono",
    bg = "transparent",
  }
})

-- vim.keymap.set("v", "<leader>cn", function() require('carbon-now').create_snippet() end, { noremap = true, silent = true})
vim.api.nvim_set_keymap("v", "<leader>cn", ":CarbonNow <CR>", { noremap = true, silent = true})

