local M = {}

M.current = nil

function M.open(pr_number, owner, repo)
  local github = require("pr.github")

  if not owner or not repo then
    owner, repo = github.get_repo_info()
  end

  if not owner or not repo then
    vim.notify("Could not detect repository. Use :PR owner/repo#number", vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format("Loading PR #%d...", pr_number), vim.log.levels.INFO)

  local pr, err = github.get_pr(owner, repo, pr_number)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  M.current = {
    number = pr_number,
    owner = owner,
    repo = repo,
    pr = pr,
    files = pr.files or {},
    file_index = 0,
    reviewed = {},
    pending_comments = {},
  }

  require("pr.threads").load(owner, repo, pr_number)

  -- Open file picker immediately
  require("pr.picker").list_files()
end

function M.open_file(file)
  if not M.current then return end

  local idx = M.get_file_index(file)
  if idx then
    M.current.file_index = idx
  end

  -- Check if already open in a tab
  local existing_tab = M.find_existing_tab(file)
  if existing_tab then
    vim.api.nvim_set_current_tabpage(existing_tab)
    M.update_statusline()
    return
  end

  -- Get the diff for this specific file
  local github = require("pr.github")
  local full_diff = github.get_diff(M.current.owner, M.current.repo, M.current.number)
  local file_diff = M.extract_file_diff(full_diff, file)

  -- Create side-by-side view
  M.show_side_by_side(file, file_diff)
end

function M.extract_file_diff(full_diff, file)
  if not full_diff then return "" end

  local lines = vim.split(full_diff, "\n")
  local result = {}
  local in_file = false

  for _, line in ipairs(lines) do
    if line:match("^diff %-%-git") then
      if line:match(file:gsub("%-", "%%-"):gsub("%.", "%%.") .. "$") or line:match("b/" .. file:gsub("%-", "%%-"):gsub("%.", "%.")) then
        in_file = true
      else
        in_file = false
      end
    end
    if in_file then
      table.insert(result, line)
    end
  end

  return table.concat(result, "\n")
end

function M.show_side_by_side(file, diff)
  -- Close existing review buffers
  M.close_buffers()

  local lines = vim.split(diff, "\n")
  local left_lines = {}   -- base (deletions)
  local right_lines = {}  -- head (additions)
  local left_hl = {}
  local right_hl = {}

  local line_left = 0
  local line_right = 0

  for _, line in ipairs(lines) do
    if line:match("^@@") then
      -- Skip hunk headers
    elseif line:sub(1, 1) == "-" and not line:match("^%-%-%-") then
      table.insert(left_lines, line:sub(2))
      line_left = line_left + 1
      table.insert(left_hl, { line_left, "DiffDelete" })
    elseif line:sub(1, 1) == "+" and not line:match("^%+%+%+") then
      table.insert(right_lines, line:sub(2))
      line_right = line_right + 1
      table.insert(right_hl, { line_right, "DiffAdd" })
    elseif line:sub(1, 1) == " " then
      table.insert(left_lines, line:sub(2))
      table.insert(right_lines, line:sub(2))
      line_left = line_left + 1
      line_right = line_right + 1
    elseif not line:match("^diff") and not line:match("^index") and not line:match("^%-%-%-") and not line:match("^%+%+%+") then
      table.insert(left_lines, line)
      table.insert(right_lines, line)
      line_left = line_left + 1
      line_right = line_right + 1
    end
  end

  -- Pad to equal length
  while #left_lines < #right_lines do
    table.insert(left_lines, "")
  end
  while #right_lines < #left_lines do
    table.insert(right_lines, "")
  end

  -- Create left buffer (base)
  vim.cmd("tabnew")
  local left_buf = vim.api.nvim_get_current_buf()
  local left_name = string.format("PR #%d BASE: %s", M.current.number, file)
  pcall(vim.api.nvim_buf_set_name, left_buf, left_name)
  vim.bo[left_buf].buftype = "nofile"
  vim.bo[left_buf].modifiable = true
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, left_lines)
  vim.bo[left_buf].modifiable = false
  M.apply_highlights(left_buf, left_hl)
  M.set_filetype_from_ext(left_buf, file)

  -- Create right buffer (head)
  vim.cmd("vsplit")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, right_buf)
  local right_name = string.format("PR #%d HEAD: %s", M.current.number, file)
  pcall(vim.api.nvim_buf_set_name, right_buf, right_name)
  vim.bo[right_buf].buftype = "nofile"
  vim.bo[right_buf].modifiable = true
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, right_lines)
  vim.bo[right_buf].modifiable = false
  M.apply_highlights(right_buf, right_hl)
  M.set_filetype_from_ext(right_buf, file)

  -- Sync scrolling
  vim.wo.scrollbind = true
  vim.cmd("wincmd h")
  vim.wo.scrollbind = true
  vim.cmd("wincmd l")

  -- Set up keymaps
  M.setup_keymaps(left_buf)
  M.setup_keymaps(right_buf)

  -- Update statusline
  M.update_statusline()
end

function M.apply_highlights(buf, highlights)
  local ns = vim.api.nvim_create_namespace("pr_diff")
  for _, hl in ipairs(highlights) do
    pcall(function()
      vim.api.nvim_buf_add_highlight(buf, ns, hl[2], hl[1] - 1, 0, -1)
    end)
  end
end

function M.set_filetype_from_ext(buf, file)
  local ext = file:match("%.([^%.]+)$")
  local ft_map = {
    lua = "lua", rs = "rust", ts = "typescript", js = "javascript",
    py = "python", go = "go", rb = "ruby", tsx = "typescriptreact",
    jsx = "javascriptreact", json = "json", yaml = "yaml", yml = "yaml",
    md = "markdown", sh = "bash", toml = "toml", sol = "solidity",
  }
  if ext and ft_map[ext] then
    vim.bo[buf].filetype = ft_map[ext]
  end
end

function M.setup_keymaps(buf)
  local opts = { buffer = buf, silent = true }
  local config = require("pr").config.keymaps

  vim.keymap.set("n", config.next_file, function() M.next_file() end, vim.tbl_extend("force", opts, { desc = "Next file" }))
  vim.keymap.set("n", config.prev_file, function() M.prev_file() end, vim.tbl_extend("force", opts, { desc = "Prev file" }))
  vim.keymap.set("n", config.next_comment, function() require("pr.threads").next() end, vim.tbl_extend("force", opts, { desc = "Next comment" }))
  vim.keymap.set("n", config.prev_comment, function() require("pr.threads").prev() end, vim.tbl_extend("force", opts, { desc = "Prev comment" }))
  vim.keymap.set("n", config.comment, function() require("pr.comments").add_comment() end, opts)
  vim.keymap.set("v", config.comment, function() require("pr.comments").add_comment() end, opts)
  vim.keymap.set("n", config.suggest, function() require("pr.comments").add_suggestion() end, opts)
  vim.keymap.set("v", config.suggest, function() require("pr.comments").add_suggestion() end, opts)
  vim.keymap.set("n", config.reply, function() require("pr.threads").reply() end, opts)
  vim.keymap.set("n", config.approve, function() M.submit("approve") end, opts)
  vim.keymap.set("n", "v", function() M.toggle_reviewed() end, vim.tbl_extend("force", opts, { desc = "Toggle reviewed" }))
  vim.keymap.set("n", "S", function() M.submit() end, vim.tbl_extend("force", opts, { desc = "Submit review" }))
  vim.keymap.set("n", "q", function() M.close_file() end, vim.tbl_extend("force", opts, { desc = "Close file" }))
  vim.keymap.set("n", "Q", function() M.close() end, vim.tbl_extend("force", opts, { desc = "Close review" }))
  vim.keymap.set("n", "?", function() M.show_help() end, vim.tbl_extend("force", opts, { desc = "Show help" }))
  vim.keymap.set("n", "f", function() require("pr.picker").list_files() end, vim.tbl_extend("force", opts, { desc = "File picker" }))
end

function M.get_file_index(file)
  if not M.current then return nil end
  for i, f in ipairs(M.current.files) do
    if f == file then return i end
  end
  return nil
end

function M.next_file()
  if not M.current or #M.current.files == 0 then return end
  M.current.file_index = (M.current.file_index % #M.current.files) + 1
  M.open_file(M.current.files[M.current.file_index])
end

function M.prev_file()
  if not M.current or #M.current.files == 0 then return end
  M.current.file_index = M.current.file_index - 1
  if M.current.file_index < 1 then
    M.current.file_index = #M.current.files
  end
  M.open_file(M.current.files[M.current.file_index])
end

function M.toggle_reviewed()
  if not M.current then return end
  local file = M.current.files[M.current.file_index]
  if file then
    if M.current.reviewed[file] then
      M.current.reviewed[file] = nil
      vim.notify("○ Unmarked: " .. file, vim.log.levels.INFO)
    else
      M.current.reviewed[file] = true
      vim.notify("✓ Marked as reviewed: " .. file, vim.log.levels.INFO)
    end
    M.update_statusline()
  end
end

function M.update_statusline()
  if not M.current then return end

  local reviewed_count = 0
  for _ in pairs(M.current.reviewed) do
    reviewed_count = reviewed_count + 1
  end

  local indicators = {}
  for i, file in ipairs(M.current.files) do
    if M.current.reviewed[file] then
      table.insert(indicators, "✓")
    elseif i == M.current.file_index then
      table.insert(indicators, "●")
    else
      table.insert(indicators, "○")
    end
  end

  local status = string.format(
    "PR #%d │ %s (%d/%d) │ %d pending │ %s",
    M.current.number,
    M.current.files[M.current.file_index] or "?",
    M.current.file_index,
    #M.current.files,
    #M.current.pending_comments,
    table.concat(indicators, "")
  )

  vim.notify(status, vim.log.levels.INFO)
end

function M.show_help()
  local help = {
    "PR Review Keybindings",
    "─────────────────────",
    "",
    "f         File picker",
    "]f / [f   Next/prev file",
    "]c / [c   Next/prev comment",
    "c         Add comment",
    "s         Add suggestion",
    "r         Reply to thread",
    "v         Toggle file reviewed",
    "a         Approve PR",
    "S         Submit review",
    "q         Close file tab",
    "Q         Close entire review",
    "",
    "Press Esc to close",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false

  local width = 30
  local height = #help

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = vim.o.lines - height - 4,
    col = vim.o.columns - width - 3,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })

  vim.wo[win].winhl = "Normal:TelescopePromptNormal,FloatBorder:TelescopePromptBorder"

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })

  vim.keymap.set("n", "?", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })
end

function M.submit(event)
  if not M.current then
    vim.notify("No active PR review", vim.log.levels.WARN)
    return
  end

  if not event or not vim.tbl_contains({ "approve", "comment", "request_changes" }, event) then
    vim.ui.select({ "approve", "comment", "request_changes" }, { prompt = "Submit review as:" }, function(choice)
      if choice then
        M.submit(choice)
      end
    end)
    return
  end

  local github = require("pr.github")

  for _, comment in ipairs(M.current.pending_comments) do
    local ok, err = github.add_comment(M.current.owner, M.current.repo, M.current.number, comment.path, comment.line, comment.body)
    if not ok then
      vim.notify("Failed to post comment: " .. (err or ""), vim.log.levels.ERROR)
    end
  end

  local ok, err = github.submit_review(M.current.owner, M.current.repo, M.current.number, event)
  if ok then
    vim.notify("✓ Review submitted: " .. event, vim.log.levels.INFO)
    M.current.pending_comments = {}
  else
    vim.notify("Failed to submit: " .. (err or ""), vim.log.levels.ERROR)
  end
end

function M.toggle_diff()
  require("pr.picker").list_files()
end

function M.close_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("PR #%d+") then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

function M.find_existing_buffer(name_pattern)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match(name_pattern) then
      return buf
    end
  end
  return nil
end

function M.find_existing_tab(file)
  if not M.current then return nil end
  local pattern = string.format("PR #%d.*%s$", M.current.number, file:gsub("%-", "%%-"):gsub("%.", "%%."))
  
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match(pattern) then
        return tabpage
      end
    end
  end
  return nil
end

function M.close_file()
  if not M.current then return end
  local tabcount = #vim.api.nvim_list_tabpages()
  if tabcount > 1 then
    vim.cmd("tabclose")
  else
    M.close()
  end
end

function M.close()
  M.close_buffers()
  M.current = nil
  pcall(vim.cmd, "tabclose")
  vim.notify("PR review closed", vim.log.levels.INFO)
end

return M
