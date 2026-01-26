local M = {}

M.version = "0.1.0"

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
  
  -- Save review state when Neovim exits
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      local review = require("pr.review")
      if review.current then
        require("pr.cache").save_review(review.current)
      end
    end,
  })
end

-- Public API for external tools (amp, claude, etc.)
-- These functions can be called via nvim --headless or RPC

-- Get current review status
function M.get_status()
  local review = require("pr.review")
  if not review.current then
    return { active = false }
  end
  return {
    active = true,
    pr_number = review.current.number,
    owner = review.current.owner,
    repo = review.current.repo,
    files = review.current.files,
    current_file = review.current.files[review.current.file_index],
    pending_comments = #review.current.pending_comments,
  }
end

-- Add a comment to the current PR review
-- Usage: require("pr").add_comment({ path = "src/foo.lua", line = 10, body = "Fix this" })
function M.add_comment(opts)
  local review = require("pr.review")
  if not review.current then
    return { success = false, error = "No active PR review" }
  end
  
  if not opts.path or not opts.line or not opts.body then
    return { success = false, error = "Missing required fields: path, line, body" }
  end
  
  table.insert(review.current.pending_comments, {
    path = opts.path,
    line = opts.line,
    start_line = opts.start_line,
    body = opts.body,
  })
  
  -- Refresh display if visible
  pcall(function() require("pr.threads").show_all_comments() end)
  
  return { 
    success = true, 
    pending_count = #review.current.pending_comments 
  }
end

-- Add a suggestion to the current PR review
function M.add_suggestion(opts)
  if not opts.code then
    return { success = false, error = "Missing required field: code" }
  end
  opts.body = string.format("```suggestion\n%s\n```", opts.code)
  return M.add_comment(opts)
end

-- List pending comments
function M.list_pending_comments()
  local review = require("pr.review")
  if not review.current then
    return { success = false, error = "No active PR review" }
  end
  return {
    success = true,
    comments = review.current.pending_comments,
  }
end

-- Submit the review
-- Usage: require("pr").submit_review({ event = "comment", body = "LGTM" })
function M.submit_review(opts)
  local review = require("pr.review")
  if not review.current then
    return { success = false, error = "No active PR review" }
  end
  
  opts = opts or {}
  local event = opts.event or "comment"
  local body = opts.body or ""
  
  if not vim.tbl_contains({ "approve", "comment", "request_changes" }, event) then
    return { success = false, error = "Invalid event. Use: approve, comment, request_changes" }
  end
  
  review.submit(event, body)
  return { success = true }
end

-- Open a PR for review (can be called headlessly)
function M.open_pr(pr_number, owner, repo)
  require("pr.review").open(pr_number, owner, repo)
  return { success = true }
end

return M
