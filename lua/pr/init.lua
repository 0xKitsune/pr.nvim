local M = {}

M.config = {
  provider = "github", -- "github" | "gitlab"
  keymaps = {
    comment = "c",
    suggest = "s",
    reply = "r",
    approve = "a",
    next_file = "]f",
    prev_file = "[f",
    next_comment = "]c",
    prev_comment = "[c",
    close = "q",
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  require("pr.commands").setup()
end

return M
