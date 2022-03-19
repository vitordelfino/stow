local handle_lsp_attach = require("util/handle_lsp_attach")
local nvim_lsp = require("lspconfig")

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.completion.completionItem.snippetSupport = true

nvim_lsp.gopls.setup{
  cmd = {'gopls', '--remote=auto'},
  filetypes = {'go', 'go.mod'},
  -- root_dir = root_patter("go.mod", ".git"),
  capabilities = capabilities,
  settings = {
    gopls = {
      experimentalPostfixCompletions = true,
      analyses = {
        unusedparams = true,
        shadow = true,
      },
      staticcheck = true
    },
  },

  on_attach = handle_lsp_attach,
}
