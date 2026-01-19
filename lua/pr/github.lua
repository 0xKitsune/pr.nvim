local M = {}
local async = require("pr.async")
local cache = require("pr.cache")

-- Memory cache for PR list
M.pr_cache = nil
M.current_user = nil
M.prefetch_in_progress = false

-- Prefetch PRs in background (call on nvim start)
function M.prefetch()
  if M.prefetch_in_progress then return end
  M.prefetch_in_progress = true
  
  -- Fetch user first (in parallel concept, but we need it for status)
  if not M.current_user then
    async.run("gh api user --jq .login", function(username, _)
      M.current_user = (username or ""):gsub("%s+", "")
    end)
  end
  
  -- Fetch full PR list with all details
  local cmd = "gh pr list --limit 100 --json number,title,author,reviewDecision,reviews,reviewRequests"
  async.run_json(cmd, function(prs, err)
    M.prefetch_in_progress = false
    if err or not prs then return end
    
    -- Compute review status for each PR (user might not be ready yet, that's ok)
    for _, pr in ipairs(prs) do
      pr.review_status = M.get_review_status(pr, M.current_user or "")
    end
    
    M.pr_cache = prs
  end)
end

function M.get_repo_info()
  local remote = vim.fn.system("git remote get-url origin 2>/dev/null"):gsub("%s+", "")
  if vim.v.shell_error ~= 0 then
    return nil, nil
  end

  local owner, repo = remote:match("github%.com[:/]([^/]+)/([^/%.]+)")
  if repo then
    repo = repo:gsub("%.git$", "")
  end
  return owner, repo
end

function M.list_prs(filter, callback, on_update)
  filter = filter or ""
  
  -- If we have cached data, show it immediately
  if M.pr_cache and #M.pr_cache > 0 and filter == "" then
    callback(M.pr_cache, nil)
    
    -- Refresh full data in background (skip fast load, we already have data)
    if on_update then
      M.fetch_full_prs(filter, on_update)
    end
    return
  end
  
  -- No cache - fetch fresh (fast first, then full update)
  M.fetch_fresh_prs(filter, function(prs)
    callback(prs, nil)
  end, on_update)
end

-- Full fetch only (used when cache already shown)
function M.fetch_full_prs(filter, on_update)
  if not M.current_user then
    async.run("gh api user --jq .login", function(username, _)
      M.current_user = (username or ""):gsub("%s+", "")
      M.fetch_full_prs(filter, on_update)
    end)
    return
  end
  
  local cmd = string.format("gh pr list --limit 100 --json number,title,author,reviewDecision,reviews,reviewRequests %s", filter)
  
  async.run_json(cmd, function(prs, err)
    if err or not prs then return end
    
    for _, pr in ipairs(prs) do
      pr.review_status = M.get_review_status(pr, M.current_user or "")
    end
    
    if filter == "" then
      M.pr_cache = prs
    end
    
    if on_update then
      on_update(prs)
    end
  end)
end

function M.fetch_fresh_prs(filter, callback, on_update)
  -- Ensure we have user info (parallel fetch)
  if not M.current_user then
    async.run("gh api user --jq .login", function(username, _)
      M.current_user = (username or ""):gsub("%s+", "")
    end)
  end
  
  -- Fast first load - basic info only
  local cmd_fast = string.format("gh pr list --limit 50 --json number,title,author %s", filter)
  
  async.run_json(cmd_fast, function(prs, err)
    if err or not prs then
      if callback then callback({}, nil) end
      return
    end
    
    -- Show immediately with empty status
    for _, pr in ipairs(prs) do
      pr.review_status = ""
    end
    
    if callback then
      callback(prs)
    end
    
    -- Now fetch full details in background
    local cmd_full = string.format("gh pr list --limit 100 --json number,title,author,reviewDecision,reviews,reviewRequests %s", filter)
    
    async.run_json(cmd_full, function(full_prs, full_err)
      if full_err or not full_prs then return end
      
      for _, pr in ipairs(full_prs) do
        pr.review_status = M.get_review_status(pr, M.current_user or "")
      end
      
      -- Update cache if no filter
      if filter == "" then
        M.pr_cache = full_prs
      end
      
      if on_update then
        on_update(full_prs)
      end
    end)
  end)
end

function M.get_review_status(pr, current_user)
  local decision = pr.reviewDecision or ""
  local reviews = pr.reviews or {}
  local review_requests = pr.reviewRequests or {}
  
  -- Check if current user has reviewed
  local your_review = nil
  local has_any_review = #reviews > 0
  for _, review in ipairs(reviews) do
    if review.author and review.author.login == current_user then
      your_review = review.state
    end
  end
  
  -- Check if current user is requested to review
  local you_requested = false
  for _, request in ipairs(review_requests) do
    if request.login == current_user then
      you_requested = true
      break
    end
  end
  
  local icon = ""
  local status_text = ""
  
  -- Overall status
  if decision == "APPROVED" then
    icon = "✓"
    status_text = "approved"
  elseif decision == "CHANGES_REQUESTED" then
    icon = "✗"
    status_text = "changes requested"
  elseif has_any_review then
    icon = "●"
  else
    icon = "○"
  end
  
  -- Build status parts (joined by comma)
  local status_parts = {}
  if status_text ~= "" then
    table.insert(status_parts, status_text)
  end
  if you_requested then
    table.insert(status_parts, "review requested")
  end
  
  -- Your review status (in parentheses)
  local your_part = ""
  if your_review then
    if your_review == "APPROVED" then
      your_part = "(approved by you)"
    elseif your_review == "CHANGES_REQUESTED" then
      your_part = "(changes requested by you)"
    elseif your_review == "COMMENTED" or your_review == "PENDING" then
      your_part = "(reviewed by you)"
    end
  end
  
  local result = icon
  if #status_parts > 0 then
    result = result .. " " .. table.concat(status_parts, ", ")
  end
  if your_part ~= "" then
    result = result .. " " .. your_part
  end
  
  return result
end

function M.get_pr(owner, repo, pr_number, callback)
  local cmd = string.format(
    "gh pr view %s --repo %s/%s --json number,title,body,author,files,comments,reviews,headRefName,baseRefName",
    pr_number, owner, repo
  )
  
  async.run_json(cmd, function(pr, err)
    if err then
      callback(nil, "Failed to fetch PR: " .. err)
      return
    end
    
    -- Get list of changed files
    local files_cmd = string.format("gh pr view %s --repo %s/%s --json files --jq '.files[].path'", pr_number, owner, repo)
    async.run(files_cmd, function(files_result, files_err)
      if not files_err and files_result then
        pr.files = vim.split(files_result, "\n", { trimempty = true })
      end
      callback(pr, nil)
    end)
  end)
end

function M.get_diff(owner, repo, pr_number, callback)
  -- Check cache first
  local cached = cache.get_diff(owner, repo, pr_number)
  if cached then
    if callback then
      callback(cached)
    end
    return cached
  end
  
  if callback then
    -- Async mode
    local cmd = string.format("gh pr diff %s --repo %s/%s", pr_number, owner, repo)
    async.run(cmd, function(result, err)
      if not err and result then
        cache.set_diff(owner, repo, pr_number, result)
      end
      callback(result)
    end)
  else
    -- Sync mode (fallback)
    local cmd = string.format("gh pr diff %s --repo %s/%s 2>&1", pr_number, owner, repo)
    local result = vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
      cache.set_diff(owner, repo, pr_number, result)
      return result
    end
    return nil
  end
end

function M.get_comments(owner, repo, pr_number, callback)
  local cmd = string.format("gh api repos/%s/%s/pulls/%s/comments", owner, repo, pr_number)
  
  if callback then
    async.run_json(cmd, function(comments, err)
      callback(comments, err)
    end)
  else
    local result = vim.fn.system(cmd .. " 2>&1")
    if vim.v.shell_error ~= 0 then
      return nil, "Failed to fetch comments"
    end
    local ok, comments = pcall(vim.json.decode, result)
    if not ok then
      return nil, "Failed to parse comments"
    end
    return comments, nil
  end
end

function M.add_comment(owner, repo, pr_number, path, line, body)
  -- Get the head commit SHA for this PR
  local sha_cmd = string.format("gh pr view %s --repo %s/%s --json headRefOid --jq .headRefOid", pr_number, owner, repo)
  local commit_id = vim.fn.system(sha_cmd):gsub("%s+", "")
  
  if vim.v.shell_error ~= 0 or commit_id == "" then
    return nil, "Failed to get commit SHA"
  end
  
  -- Use gh pr comment for simpler line comments, or create review comment
  local cmd = string.format(
    "gh api repos/%s/%s/pulls/%s/comments " ..
    "-f body=%q " ..
    "-f path=%q " ..
    "-f commit_id=%s " ..
    "-F line=%d " ..
    "-f side=RIGHT " ..
    "-f subject_type=line 2>&1",
    owner, repo, pr_number, body, path, commit_id, line
  )
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil, "Failed to add comment: " .. result
  end

  return true, nil
end

function M.add_suggestion(owner, repo, pr_number, path, start_line, end_line, suggestion)
  local body = string.format("```suggestion\n%s\n```", suggestion)
  return M.add_comment(owner, repo, pr_number, path, end_line, body)
end

function M.reply_to_comment(owner, repo, pr_number, comment_id, body)
  local cmd = string.format(
    "gh api repos/%s/%s/pulls/%s/comments/%s/replies -f body=%q 2>&1",
    owner, repo, pr_number, comment_id, body
  )
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil, "Failed to reply: " .. result
  end

  return true, nil
end

function M.submit_review(owner, repo, pr_number, event, body)
  -- gh pr review expects: --approve, --comment, --request-changes
  local event_flags = {
    approve = "--approve",
    comment = "--comment",
    request_changes = "--request-changes",
  }
  
  local flag = event_flags[event]
  if not flag then
    return nil, "Invalid review event: " .. event
  end
  
  local cmd = string.format("gh pr review %s --repo %s/%s %s", pr_number, owner, repo, flag)

  -- --comment requires a body
  if event == "comment" and (not body or body == "") then
    body = "Review submitted"
  end
  
  if body and body ~= "" then
    cmd = cmd .. string.format(" --body %q", body)
  end

  local result = vim.fn.system(cmd .. " 2>&1")

  if vim.v.shell_error ~= 0 then
    return nil, "Failed to submit review: " .. result
  end

  return true, nil
end

return M
