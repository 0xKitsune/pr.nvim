local M = {}

function M.add_comment()
  M._open_comment_window(false)
end

function M.add_suggestion()
  M._open_comment_window(true)
end

function M._open_comment_window(with_suggestion)
  local review = require("pr.review")
  if not review.current then
    vim.notify("No active PR review. Run :PR <number> first", vim.log.levels.WARN)
    return
  end

  local mode = vim.fn.mode()
  local start_line = vim.api.nvim_win_get_cursor(0)[1]
  local end_line = start_line
  local selected_lines = {}

  if mode == "v" or mode == "V" then
    vim.cmd('normal! "vy')
    start_line = vim.fn.line("'<")
    end_line = vim.fn.line("'>")
    selected_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  elseif with_suggestion then
    selected_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  end

  local file = M.get_current_file()
  if not file then
    vim.notify("Could not determine file path", vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = ""

  -- Pre-fill content with header
  local comment_type = with_suggestion and "Suggestion" or "Comment"
  local initial_lines = {
    string.format("── %s ──────────────────────────────", comment_type),
    string.format("File: %s", file),
    string.format("Line: %d", start_line),
    "────────────────────────────────────────",
    "",
  }
  
  if with_suggestion then
    table.insert(initial_lines, "```suggestion")
    for _, line in ipairs(selected_lines) do
      table.insert(initial_lines, line)
    end
    table.insert(initial_lines, "```")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)

  local width = math.floor(vim.o.columns * 0.5)
  local height = math.max(#initial_lines + 2, 8)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Enter: submit | Esc: cancel ",
    title_pos = "center",
  })

  -- Position cursor at the top for typing comment
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("startinsert")

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.api.nvim_win_close(win, true)
    
    -- Skip header lines (first 4 lines are header + separator)
    local content_lines = {}
    for i = 5, #lines do
      table.insert(content_lines, lines[i])
    end
    local body = table.concat(content_lines, "\n")

    if body:gsub("%s", "") ~= "" then
      table.insert(review.current.pending_comments, {
        path = file,
        line = end_line,
        body = body,
      })
      local label = with_suggestion and "Suggestion" or "Comment"
      vim.notify(string.format("%s queued (%d pending)", label, #review.current.pending_comments), vim.log.levels.INFO)
      M.show_virtual_comment(start_line, body:sub(1, 30))
      
      -- Refresh comment display
      require("pr.threads").show_all_comments()
    end
  end

  local function cancel()
    vim.api.nvim_win_close(win, true)
  end

  -- Enter to submit (both normal and insert mode)
  vim.keymap.set("n", "<CR>", submit, { buffer = buf })
  vim.keymap.set("i", "<CR>", function()
    vim.cmd("stopinsert")
    submit()
  end, { buffer = buf })

  -- Escape to cancel (both modes)
  vim.keymap.set("n", "<Esc>", cancel, { buffer = buf })
  vim.keymap.set("i", "<Esc>", function()
    vim.cmd("stopinsert")
    cancel()
  end, { buffer = buf })

  vim.keymap.set("n", "q", cancel, { buffer = buf })
end

function M.get_current_file()
  local review = require("pr.review")
  if not review.current then return nil end

  local bufname = vim.api.nvim_buf_get_name(0)

  local file = bufname:match("PR #%d+ [A-Z]+: (.+)$")
  if file then
    return file
  end

  if review.current.file_index and review.current.file_index > 0 then
    return review.current.files[review.current.file_index]
  end

  return nil
end

function M.show_virtual_comment(line, preview)
  -- Find the HEAD (right) buffer
  local right_buf = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("PR #%d+ HEAD:") then
      right_buf = buf
      break
    end
  end
  
  if not right_buf then return end
  
  local ns = vim.api.nvim_create_namespace("pr_pending_comments")
  pcall(function()
    vim.api.nvim_buf_set_extmark(right_buf, ns, line - 1, 0, {
      sign_text = "💬",
      sign_hl_group = "Comment",
    })
  end)
end

return M
