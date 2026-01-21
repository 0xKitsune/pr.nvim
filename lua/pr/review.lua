local M = {}

M.current = nil
M.full_file_mode = true -- Toggle for showing full file vs diff-only

function M.open(pr_number, owner, repo)
  local github = require("pr.github")
  local cache = require("pr.cache")

  if not owner or not repo then
    owner, repo = github.get_repo_info()
  end

  if not owner or not repo then
    vim.notify("Could not detect repository. Use :PR owner/repo#number", vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format("Loading PR #%d...", pr_number), vim.log.levels.INFO)

  github.get_pr(owner, repo, pr_number, function(pr, err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    -- Restore saved review state if available
    local saved = cache.load_review(owner, repo, pr_number)

    M.current = {
      number = pr_number,
      owner = owner,
      repo = repo,
      pr = pr,
      files = pr.files or {},
      file_index = saved and saved.file_index or 0,
      reviewed = saved and saved.reviewed or {},
      pending_comments = saved and saved.pending_comments or {},
    }

    if saved then
      local pending_count = #(saved.pending_comments or {})
      local reviewed_count = 0
      for _ in pairs(saved.reviewed or {}) do reviewed_count = reviewed_count + 1 end
      
      if pending_count > 0 or reviewed_count > 0 then
        vim.notify(string.format("Restored: %d reviewed, %d pending", reviewed_count, pending_count), vim.log.levels.INFO)
      end
    end

    -- Pre-fetch diff in background
    github.get_diff(owner, repo, pr_number, function(_)
      -- Diff cached
    end)

    require("pr.threads").load(owner, repo, pr_number)

    -- Open file picker immediately
    require("pr.picker").list_files()
  end)
end

function M.open_file(file, force_refresh)
  if not M.current then return end

  local idx = M.get_file_index(file)
  if idx then
    M.current.file_index = idx
  end

  -- Check if already open in a tab (skip if forcing refresh for mode toggle)
  if not force_refresh then
    local existing_tab = M.find_existing_tab(file)
    if existing_tab then
      vim.api.nvim_set_current_tabpage(existing_tab)
      M.update_statusline()
      return
    end
  end

  -- Get the diff for this specific file
  local github = require("pr.github")
  local full_diff = github.get_diff(M.current.owner, M.current.repo, M.current.number)
  local file_diff = M.extract_file_diff(full_diff, file)

  if M.full_file_mode then
    -- Fetch full file content and show with diff highlights
    M.show_full_file(file, file_diff)
  else
    -- Create side-by-side diff view
    M.show_side_by_side(file, file_diff)
  end
end

function M.toggle_full_file_mode()
  M.full_file_mode = not M.full_file_mode
  local mode = M.full_file_mode and "Full file" or "Diff only"
  vim.notify("View mode: " .. mode, vim.log.levels.INFO)
  
  -- Refresh current file if one is open
  if M.current and M.current.file_index and M.current.file_index > 0 then
    local file = M.current.files[M.current.file_index]
    if file then
      -- Close current tab first
      M.close_file()
      -- Reopen with new mode
      M.open_file(file, true)
    end
  end
end

function M.show_full_file(file, diff)
  local github = require("pr.github")
  
  -- Parse diff to get changed line info
  local changed_lines = M.parse_diff_changes(diff)
  
  -- Fetch the HEAD (new) version of the file
  vim.notify("Loading full file...", vim.log.levels.INFO)
  github.get_file_content(M.current.owner, M.current.repo, M.current.pr.headRefName, file, function(content, err)
    if err or not content then
      vim.notify("Failed to fetch file: " .. (err or "unknown error"), vim.log.levels.ERROR)
      -- Fall back to diff view
      M.full_file_mode = false
      M.show_side_by_side(file, diff)
      return
    end
    
    vim.schedule(function()
      M.close_buffers()
      
      local lines = vim.split(content, "\n")
      
      -- Create buffer
      vim.cmd("tabnew")
      local buf = vim.api.nvim_get_current_buf()
      local buf_name = string.format("PR #%d FULL: %s", M.current.number, file)
      pcall(vim.api.nvim_buf_set_name, buf, buf_name)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      M.set_filetype_from_ext(buf, file)
      
      -- Apply diff highlights
      local ns = vim.api.nvim_create_namespace("pr_diff")
      for _, change in ipairs(changed_lines.added) do
        if change <= #lines then
          pcall(function()
            vim.api.nvim_buf_add_highlight(buf, ns, "DiffAdd", change - 1, 0, -1)
          end)
        end
      end
      for _, change in ipairs(changed_lines.modified) do
        if change <= #lines then
          pcall(function()
            vim.api.nvim_buf_add_highlight(buf, ns, "DiffChange", change - 1, 0, -1)
          end)
        end
      end
      
      -- Store highlights for navigation
      M.current_highlights = {}
      for _, line in ipairs(changed_lines.added) do
        table.insert(M.current_highlights, { line, "DiffAdd" })
      end
      for _, line in ipairs(changed_lines.modified) do
        table.insert(M.current_highlights, { line, "DiffChange" })
      end
      table.sort(M.current_highlights, function(a, b) return a[1] < b[1] end)
      
      -- Setup keymaps
      M.setup_keymaps(buf)
      
      -- Jump to first change
      if #M.current_highlights > 0 then
        pcall(vim.api.nvim_win_set_cursor, 0, { M.current_highlights[1][1], 0 })
        vim.cmd("normal! zz")
      end
      
      -- Show comments
      require("pr.threads").show_all_comments()
      
      -- Show file path
      M.show_file_path(file .. " (full file)")
      M.update_statusline()
    end)
  end)
end

function M.parse_diff_changes(diff)
  local added = {}
  local modified = {}
  
  if not diff then return { added = added, modified = modified } end
  
  local lines = vim.split(diff, "\n")
  local current_line = 0
  
  for _, line in ipairs(lines) do
    -- Parse hunk header: @@ -old_start,old_count +new_start,new_count @@
    local new_start = line:match("^@@ %-%d+,?%d* %+(%d+)")
    if new_start then
      current_line = tonumber(new_start) - 1
    elseif line:sub(1, 1) == "+" and not line:match("^%+%+%+") then
      current_line = current_line + 1
      table.insert(added, current_line)
    elseif line:sub(1, 1) == "-" and not line:match("^%-%-%-") then
      -- Deletion - next add at same position is a modification
      -- Don't increment line counter
    elseif line:sub(1, 1) == " " then
      current_line = current_line + 1
    end
  end
  
  return { added = added, modified = modified }
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

  -- Jump to first change
  M.jump_to_first_change(right_hl)

  -- Show comments on the right side
  require("pr.threads").show_all_comments()

  -- Show file path indicator
  M.show_file_path(file)

  -- Update statusline
  M.update_statusline()
end

function M.show_file_path(file)
  -- Close existing file path window
  M.close_file_path_win()
  
  -- Use winbar instead of floating window to avoid covering text
  local winbar_text = " 📁 " .. file .. " "
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("PR #%d+") then
      vim.wo[win].winbar = winbar_text
    end
  end
end

function M.close_file_path_win()
  -- Clear winbars from PR windows
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
      if ok then
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("PR #%d+") then
          pcall(function() vim.wo[win].winbar = "" end)
        end
      end
    end
  end
  
  -- Legacy cleanup for floating window (if any)
  if M.file_path_win and vim.api.nvim_win_is_valid(M.file_path_win) then
    vim.api.nvim_win_close(M.file_path_win, true)
  end
  if M.file_path_buf and vim.api.nvim_buf_is_valid(M.file_path_buf) then
    vim.api.nvim_buf_delete(M.file_path_buf, { force = true })
  end
  M.file_path_win = nil
  M.file_path_buf = nil
end

function M.jump_to_first_change(highlights)
  if not highlights or #highlights == 0 then return end
  
  -- Store highlights for n/N navigation
  M.current_highlights = highlights
  
  -- Find first added/changed line
  for _, hl in ipairs(highlights) do
    if hl[2] == "DiffAdd" then
      pcall(vim.api.nvim_win_set_cursor, 0, { hl[1], 0 })
      vim.cmd("normal! zz")
      return
    end
  end
  
  -- Fallback to first highlight
  pcall(vim.api.nvim_win_set_cursor, 0, { highlights[1][1], 0 })
  vim.cmd("normal! zz")
end

function M.get_change_blocks()
  if not M.current_highlights or #M.current_highlights == 0 then
    return {}
  end

  local blocks = {}
  local block_start = nil
  local prev_line = nil

  for _, hl in ipairs(M.current_highlights) do
    if hl[2] == "DiffAdd" or hl[2] == "DiffDelete" then
      if not block_start then
        block_start = hl[1]
      elseif hl[1] > prev_line + 1 then
        table.insert(blocks, block_start)
        block_start = hl[1]
      end
      prev_line = hl[1]
    end
  end

  if block_start then
    table.insert(blocks, block_start)
  end

  return blocks
end

function M.next_change()
  local blocks = M.get_change_blocks()
  if #blocks == 0 then
    vim.notify("No changes", vim.log.levels.INFO)
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  for _, block_line in ipairs(blocks) do
    if block_line > current_line then
      pcall(vim.api.nvim_win_set_cursor, 0, { block_line, 0 })
      vim.cmd("normal! zz")
      return
    end
  end

  -- Wrap to first block
  pcall(vim.api.nvim_win_set_cursor, 0, { blocks[1], 0 })
  vim.cmd("normal! zz")
end

function M.prev_change()
  local blocks = M.get_change_blocks()
  if #blocks == 0 then
    vim.notify("No changes", vim.log.levels.INFO)
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local prev_block = nil

  for _, block_line in ipairs(blocks) do
    if block_line >= current_line then
      break
    end
    prev_block = block_line
  end

  if prev_block then
    pcall(vim.api.nvim_win_set_cursor, 0, { prev_block, 0 })
    vim.cmd("normal! zz")
    return
  end

  -- Wrap to last block
  pcall(vim.api.nvim_win_set_cursor, 0, { blocks[#blocks], 0 })
  vim.cmd("normal! zz")
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
  vim.keymap.set("n", "v", function() M.toggle_reviewed() end, vim.tbl_extend("force", opts, { desc = "Toggle reviewed" }))
  vim.keymap.set("n", "<C-v>", function() M.toggle_reviewed() end, vim.tbl_extend("force", opts, { desc = "Toggle reviewed" }))
  vim.keymap.set("n", "S", function() M.submit() end, vim.tbl_extend("force", opts, { desc = "Submit review" }))
  vim.keymap.set("n", "q", function() M.close_file() end, vim.tbl_extend("force", opts, { desc = "Close file" }))
  vim.keymap.set("n", "Q", function() M.close() end, vim.tbl_extend("force", opts, { desc = "Close review" }))
  vim.keymap.set("n", "?", function() M.show_help() end, vim.tbl_extend("force", opts, { desc = "Show help" }))
  vim.keymap.set("n", "f", function() require("pr.picker").list_files() end, vim.tbl_extend("force", opts, { desc = "File picker" }))
  vim.keymap.set("n", "p", function() M.show_pr_info() end, vim.tbl_extend("force", opts, { desc = "PR info" }))
  vim.keymap.set("n", "<CR>", function() require("pr.threads").open_thread_at_cursor() end, vim.tbl_extend("force", opts, { desc = "Open comment" }))
  vim.keymap.set("n", "n", function() M.next_change() end, vim.tbl_extend("force", opts, { desc = "Next change" }))
  vim.keymap.set("n", "N", function() M.prev_change() end, vim.tbl_extend("force", opts, { desc = "Prev change" }))
  vim.keymap.set("n", "F", function() M.toggle_full_file_mode() end, vim.tbl_extend("force", opts, { desc = "Toggle full file view" }))
  vim.keymap.set("n", "gd", function() M.open_actual_file() end, vim.tbl_extend("force", opts, { desc = "Open actual file at cursor" }))
  vim.keymap.set("n", "go", function() M.open_actual_file() end, vim.tbl_extend("force", opts, { desc = "Open actual file at cursor" }))
  vim.keymap.set("n", "<C-]>", function() M.open_actual_file() end, vim.tbl_extend("force", opts, { desc = "Open actual file at cursor" }))
end

function M.get_file_index(file)
  if not M.current then return nil end
  for i, f in ipairs(M.current.files) do
    if f == file then return i end
  end
  return nil
end

function M.open_actual_file()
  if not M.current then
    vim.notify("No active PR review", vim.log.levels.WARN)
    return
  end
  
  local file = M.current.files[M.current.file_index]
  if not file then
    vim.notify("No file selected", vim.log.levels.WARN)
    return
  end
  
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  
  -- Check if file exists in the working directory
  local full_path = vim.fn.getcwd() .. "/" .. file
  if vim.fn.filereadable(full_path) == 0 then
    vim.notify("File not found locally: " .. file, vim.log.levels.WARN)
    return
  end
  
  -- Open in a new tab
  vim.cmd("tabnew " .. vim.fn.fnameescape(full_path))
  
  -- Jump to the line
  pcall(vim.api.nvim_win_set_cursor, 0, { cursor_line, 0 })
  vim.cmd("normal! zz")
  
  vim.notify("Opened: " .. file .. " (LSP available)", vim.log.levels.INFO)
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
      vim.notify("Unmarked: " .. file, vim.log.levels.INFO)
    else
      M.current.reviewed[file] = true
      vim.notify("Reviewed: " .. file, vim.log.levels.INFO)
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
      table.insert(indicators, "●")
    elseif i == M.current.file_index then
      table.insert(indicators, "◉")
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
    "──────────────────────────────────",
    "",
    "f           File picker",
    "F           Toggle full file view",
    "p           PR info/description",
    "c           Add comment (Ctrl+S submit)",
    "s           Add suggestion",
    "r           Reply to thread",
    "e           Edit pending comment",
    "d           Delete pending comment",
    "Ctrl+] / gd Open actual file (LSP works)",
    "v           Toggle file reviewed",
    "S           Submit review",
    "Enter       Open comment at cursor",
    "q           Close file tab",
    "Q           Close entire review",
    "n / N       Next/prev change",
    "]f / [f     Next/prev file",
    "]c / [c     Next/prev comment",
    "",
    "Press Esc to close",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false

  local width = 36
  local height = #help

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = vim.o.lines - height - 6,
    col = vim.o.columns - width - 4,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " ? ",
    title_pos = "center",
    focusable = false,
  })

  vim.wo[win].winhl = "Normal:TelescopePromptNormal,FloatBorder:TelescopePromptBorder"

  -- Close help with Esc or ?
  local function close_help()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "<Esc>", close_help, { buffer = 0 })
  vim.keymap.set("n", "?", close_help, { buffer = 0 })
end

function M.show_pr_info()
  if not M.current then
    vim.notify("No active PR review", vim.log.levels.WARN)
    return
  end

  local pr = M.current.pr
  local lines = {
    "# " .. (pr.title or "PR #" .. M.current.number),
    "",
    "**Author:** @" .. (pr.author and pr.author.login or "unknown"),
    "**Branch:** " .. (pr.headRefName or "?") .. " → " .. (pr.baseRefName or "?"),
    "**Files:** " .. #M.current.files,
    "",
    "---",
    "",
  }

  -- Add body/description (clean up carriage returns)
  if pr.body and pr.body ~= "" then
    local clean_body = pr.body:gsub("\r\n", "\n"):gsub("\r", "\n")
    for _, line in ipairs(vim.split(clean_body, "\n")) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "_No description provided._")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false

  local width = math.min(80, vim.o.columns - 10)
  local height = math.min(#lines + 2, vim.o.lines - 10)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " PR #" .. M.current.number .. " ",
    title_pos = "center",
    focusable = false,
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- Close with p or Esc (from original buffer)
  local function close_info()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "p", close_info, { buffer = 0 })
  vim.keymap.set("n", "<Esc>", close_info, { buffer = 0 })
end

function M.submit(event, body)
  if not M.current then
    vim.notify("No active PR review", vim.log.levels.WARN)
    return
  end

  if not event or not vim.tbl_contains({ "approve", "comment", "request_changes" }, event) then
    vim.ui.select({ "approve", "comment", "request_changes" }, { prompt = "Submit review as:" }, function(choice)
      if choice then
        -- Prompt for optional comment
        vim.ui.input({ prompt = "Comment (optional): " }, function(input)
          M.submit(choice, input)
        end)
      end
    end)
    return
  end

  local github = require("pr.github")
  
  -- Post pending comments
  local failed_comments = {}
  for _, comment in ipairs(M.current.pending_comments) do
    local ok, err = github.add_comment(
      M.current.owner, M.current.repo, M.current.number,
      comment.path, comment.line, comment.body, comment.start_line
    )
    if not ok then
      vim.notify("Failed to post comment: " .. (err or ""), vim.log.levels.ERROR)
      table.insert(failed_comments, comment)
    end
  end

  local ok, err = github.submit_review(M.current.owner, M.current.repo, M.current.number, event, body)
  if ok then
    vim.notify("Review submitted: " .. event, vim.log.levels.INFO)
    
    -- Clear saved state after successful submit
    require("pr.cache").clear_review(M.current.owner, M.current.repo, M.current.number)
    -- Keep failed comments for retry
    M.current.pending_comments = failed_comments
    M.current.reviewed = {}
    
    if #failed_comments > 0 then
      vim.notify(string.format("%d comments failed to post", #failed_comments), vim.log.levels.WARN)
    end
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
  
  -- Close file path indicator
  M.close_file_path_win()
  
  -- Save state
  require("pr.cache").save_review(M.current)
  
  -- Delete the current PR buffers in this tab
  local current_tab = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(current_tab)
  local bufs_to_delete = {}
  
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("PR #%d+") then
      table.insert(bufs_to_delete, buf)
    end
  end
  
  local tabcount = #vim.api.nvim_list_tabpages()
  if tabcount > 1 then
    vim.cmd("tabclose")
  else
    -- Last tab, just go back to a new buffer
    vim.cmd("enew")
  end
  
  -- Delete the buffers after closing tab
  for _, buf in ipairs(bufs_to_delete) do
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

function M.close()
  -- Close file path indicator
  M.close_file_path_win()
  
  -- Save review state before closing
  if M.current then
    require("pr.cache").save_review(M.current)
  end
  
  M.close_buffers()
  M.current = nil
  pcall(vim.cmd, "tabclose")
  vim.notify("PR review closed", vim.log.levels.INFO)
end

return M
