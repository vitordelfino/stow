local cmp = require("cmp")
local luasnip = require("luasnip")
local lspkind = require("lspkind")
local types = require("cmp.types")
local str = require("cmp.utils.str")

vim.o.completeopt = "menu,menuone,noselect"

cmp.setup({
    completion = { border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }, scrollbar = "║" },
	  documentation = {
		  border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
		  scrollbar = "║",
	  },
    formatting = {
      fields = {
			  cmp.ItemField.Abbr,
			  cmp.ItemField.Menu,
			  cmp.ItemField.Kind,
		  },
      format = lspkind.cmp_format({
          before = function (entry, vim_item)
            local word = entry:get_insert_text()
				    if entry.completion_item.insertTextFormat == types.lsp.InsertTextFormat.Snippet then
					    word = vim.lsp.util.parse_snippet(word)
				    end
				    word = str.oneline(word)

				    -- concatenates the string
				    -- local max = 50
				    -- if string.len(word) >= max then
				    -- 	local before = string.sub(word, 1, math.floor((max - 3) / 2))
				    -- 	word = before .. "..."
				    -- end

				    if
					    entry.completion_item.insertTextFormat == types.lsp.InsertTextFormat.Snippet
					    and string.sub(vim_item.abbr, -1, -1) == "~"
				    then
					    word = word .. "~"
				    end
				    vim_item.abbr = word

				    return vim_item
          end
      })
    },
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
    mapping = {
      ["<C-p>"] = cmp.mapping.select_prev_item(),
      ["<C-n>"] = cmp.mapping.select_next_item(),
      ["<C-d>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      ["<C-Space>"] = cmp.mapping.complete(),
      ["<C-e>"] = cmp.mapping.close(),
      ["<C-y>"] = cmp.mapping.confirm {
        behavior = cmp.ConfirmBehavior.Replace,
        select = true,
      },
      ["<S-Tab>"] = function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end,
    },
    sources = {
      { name = "nvim_lsp" },
      { name = "luasnip" }
    }
  })
