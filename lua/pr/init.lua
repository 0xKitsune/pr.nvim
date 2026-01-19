local M = {}

M.config = {
  provider = "github", -- "github" | "gitlab"
  keymaps = {
    comment = "c",
    suggest = "s",
    reply = "r",
    next_file = "]f",
    prev_file = "[f",
    next_comment = "]c",
    prev_comment = "[c",
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  require("pr.commands").setup()
  
  -- Prefetch PR list in background so it's ready when user opens picker
  vim.defer_fn(function()
    require("pr.github").prefetch()
  end, 100)
end

return M
