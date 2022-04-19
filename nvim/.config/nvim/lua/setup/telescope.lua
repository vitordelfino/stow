local telly = require("telescope")
local actions = require("telescope.actions")

vim.api.nvim_set_keymap("n", "<leader>,", ":Telescope buffers disable_devicons=false theme=get_dropdown<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>.", ":Telescope find_files disable_devicons=false theme=get_dropdown<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>m", ":Telescope live_grep disable_devicons=false theme=get_dropdown<CR>", { noremap = true, silent = true })

telly.setup({
    extensions = {
      ["ui-select"] = {
        require("telescope.themes").get_cursor(),
      }
    },
    pickers = {
      find_files = {
        hidden = false,
      },
      buffers = {
        mappings = {
          i = {
            ["<c-d>"] = actions.delete_buffer,
          },
        },
      },
    },
    defaults = {
      vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case"
      },
      color_devicons = true,
      prompt_prefix = " 🔍 ",
      selection_caret = "❯ ",
      entry_prefix = "  ",
      initial_mode = "insert",
      selection_strategy = "reset",
      sorting_strategy = "descending",
      layout_strategy = "horizontal",
      layout_config = {
        horizontal = {
          mirror = false,
        },
        vertical = {
          mirror = false,
        },
      },
      file_sorter =  require("telescope.sorters").get_fuzzy_file,
      file_ignore_patterns = {"node_modules/.", "dist/.", "coverage/.", ".git/."},
      generic_sorter =  require("telescope.sorters").get_generic_fuzzy_sorter,
      winblend = 0,
      border = {},
      borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
      use_less = true,
      path_display = {},
      set_env = { ['COLORTERM'] = 'truecolor' }, -- default = nil,
      file_previewer = require("telescope.previewers").vim_buffer_cat.new,
      grep_previewer = require("telescope.previewers").vim_buffer_vimgrep.new,
      qflist_previewer = require("telescope.previewers").vim_buffer_qflist.new,

      -- Developer configurations: Not meant for general override
      buffer_previewer_maker = require("telescope.previewers").buffer_previewer_maker
    }
  })
require("telescope").load_extension("ui-select")
