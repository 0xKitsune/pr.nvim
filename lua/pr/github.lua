local M = {}

function M.get_repo_info()
  local remote = vim.fn.system("git remote get-url origin 2>/dev/null"):gsub("%s+", "")
  if vim.v.shell_error ~= 0 then
    return nil, nil
  end

  -- Parse GitHub URL (SSH or HTTPS)
  local owner, repo = remote:match("github%.com[:/]([^/]+)/([^/%.]+)")
  if repo then
    repo = repo:gsub("%.git$", "")
  end
  return owner, repo
end

function M.list_prs(filter)
  filter = filter or ""
  local cmd = string.format("gh pr list --json number,title,author,headRefName,state %s 2>&1", filter)
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil, "Failed to list PRs: " .. result
  end

  local ok, prs = pcall(vim.json.decode, result)
  if not ok then
    return nil, "Failed to parse PR list"
  end

  return prs, nil
end

function M.get_pr(owner, repo, pr_number)
  local cmd = string.format(
    "gh pr view %s --repo %s/%s --json number,title,body,author,files,comments,reviews,headRefName,baseRefName 2>&1",
    pr_number, owner, repo
  )
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil, "Failed to fetch PR: " .. result
  end

  local ok, pr = pcall(vim.json.decode, result)
  if not ok then
    return nil, "Failed to parse PR data"
  end

  -- Get list of changed files
  local files_cmd = string.format("gh pr view %s --repo %s/%s --json files --jq '.files[].path' 2>&1", pr_number, owner, repo)
  local files_result = vim.fn.system(files_cmd)
  if vim.v.shell_error == 0 then
    pr.files = vim.split(files_result, "\n", { trimempty = true })
  end

  return pr, nil
end

function M.get_diff(owner, repo, pr_number)
  local cmd = string.format("gh pr diff %s --repo %s/%s 2>&1", pr_number, owner, repo)
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return result
end

function M.get_comments(owner, repo, pr_number)
  local cmd = string.format(
    "gh api repos/%s/%s/pulls/%s/comments 2>&1",
    owner, repo, pr_number
  )
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil, "Failed to fetch comments"
  end

  local ok, comments = pcall(vim.json.decode, result)
  if not ok then
    return nil, "Failed to parse comments"
  end

  return comments, nil
end

function M.add_comment(owner, repo, pr_number, path, line, body)
  -- For review comments, we need to use the review API
  local cmd = string.format(
    "gh api repos/%s/%s/pulls/%s/comments -f body=%q -f path=%q -f line=%d -f side=RIGHT 2>&1",
    owner, repo, pr_number, body, path, line
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
  local event_map = {
    approve = "APPROVE",
    comment = "COMMENT",
    request_changes = "REQUEST_CHANGES",
  }

  local gh_event = event_map[event] or "COMMENT"
  local cmd = string.format("gh pr review %s --repo %s/%s --%s", pr_number, owner, repo, event:gsub("_", "-"))

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
