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

  local initial_lines = {}
  if with_suggestion then
    table.insert(initial_lines, "```suggestion")
    for _, line in ipairs(selected_lines) do
      table.insert(initial_lines, line)
    end
    table.insert(initial_lines, "```")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)

  local width = math.floor(vim.o.columns * 0.5)
  local height = math.max(#initial_lines + 3, 5)

  local title = with_suggestion
    and string.format(" Suggestion %s:%d ", file, start_line)
    or string.format(" Comment %s:%d ", file, start_line)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  -- Enable word wrap
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- Position cursor appropriately
  if with_suggestion then
    -- For suggestions, put cursor after ```suggestion line
    vim.api.nvim_win_set_cursor(win, { 2, 0 })
  else
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end
  vim.cmd("startinsert")

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.api.nvim_win_close(win, true)
    
    local body = table.concat(lines, "\n")

    if body:gsub("%s", "") ~= "" then
      -- Translate buffer line numbers to actual file line numbers
      local actual_end_line = end_line
      local actual_start_line = start_line
      
      if review.current.line_maps and review.current.line_maps[file] then
        local line_map = review.current.line_maps[file].right
        if line_map then
          actual_end_line = line_map[end_line]
          actual_start_line = line_map[start_line]
          
          if not actual_end_line then
            -- This line doesn't exist in HEAD (deleted line) - cannot comment on it
            -- Try to find nearest valid line in HEAD
            local nearest_line = nil
            local min_dist = math.huge
            for display_ln, file_ln in pairs(line_map) do
              local dist = math.abs(display_ln - end_line)
              if dist < min_dist then
                min_dist = dist
                nearest_line = file_ln
              end
            end
            
            if nearest_line and min_dist <= 3 then
              actual_end_line = nearest_line
              actual_start_line = nearest_line
              vim.notify(string.format("Line %d is deleted - commenting on nearest line %d", end_line, nearest_line), vim.log.levels.INFO)
            else
              vim.notify("Cannot comment on deleted lines - move to a line that exists in the new version", vim.log.levels.ERROR)
              return
            end
          end
        end
      else
        vim.notify("Line map not available - try reopening the file", vim.log.levels.WARN)
      end
      
      table.insert(review.current.pending_comments, {
        path = file,
        line = actual_end_line,
        start_line = actual_start_line,
        body = body,
      })
      local label = with_suggestion and "Suggestion" or "Comment"
      vim.notify(string.format("%s queued (%d pending)", label, #review.current.pending_comments), vim.log.levels.INFO)
      
      -- Refresh comment display
      require("pr.threads").show_all_comments()
    end
  end

  local function cancel()
    vim.api.nvim_win_close(win, true)
  end

  -- Enter submits (in both modes)
  vim.keymap.set("n", "<CR>", submit, { buffer = buf })
  vim.keymap.set("i", "<CR>", function()
    vim.cmd("stopinsert")
    submit()
  end, { buffer = buf })
  
  -- Ctrl+Enter for newline (multiline comments)
  vim.keymap.set("i", "<C-CR>", function()
    vim.api.nvim_put({ "", "" }, "c", true, true)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], 0 })
  end, { buffer = buf })
  
  -- Also support Ctrl+s to submit
  vim.keymap.set("n", "<C-s>", submit, { buffer = buf })
  vim.keymap.set("i", "<C-s>", function()
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

function M.show_virtual_comment(file_line, preview)
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
  
  -- Convert file line to display line using reverse map
  local review = require("pr.review")
  local current_file = review.current and review.current.files[review.current.file_index]
  local line_maps = review.current and review.current.line_maps and review.current.line_maps[current_file]
  local reverse_map = line_maps and line_maps.right_reverse
  
  local display_line = file_line
  if reverse_map and reverse_map[file_line] then
    display_line = reverse_map[file_line]
  end
  
  local ns = vim.api.nvim_create_namespace("pr_pending_comments")
  pcall(function()
    vim.api.nvim_buf_set_extmark(right_buf, ns, display_line - 1, 0, {
      sign_text = "💬",
      sign_hl_group = "Comment",
    })
  end)
end

return M
