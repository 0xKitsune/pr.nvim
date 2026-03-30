local M = {}

M.threads = {}
M.current_index = 0

function M.load(owner, repo, pr_number)
  local github = require("pr.github")
  
  github.get_comments(owner, repo, pr_number, function(comments, err)
    if err then
      vim.notify(err, vim.log.levels.WARN)
      return
    end

    M.threads = {}
    for _, comment in ipairs(comments or {}) do
      table.insert(M.threads, {
        id = comment.id,
        path = comment.path,
        line = comment.line or comment.original_line,
        body = comment.body,
        author = comment.user and comment.user.login or "unknown",
        created_at = comment.created_at,
        in_reply_to = comment.in_reply_to_id,
      })
    end

    M.current_index = 0
    M.file_thread_index = 0

    if #M.threads > 0 then
      vim.notify(string.format("Loaded %d comments", #M.threads), vim.log.levels.INFO)
      -- Try to show comments if buffer exists
      M.show_all_comments()
    end
  end)
end

function M.show_all_comments()
  local review = require("pr.review")
  if not review.current then return end
  
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
  
  local ns = vim.api.nvim_create_namespace("pr_threads")
  vim.api.nvim_buf_clear_namespace(right_buf, ns, 0, -1)

  -- Get current file and its line maps
  local current_file = review.current.files[review.current.file_index]
  local line_maps = review.current.line_maps and review.current.line_maps[current_file]
  local reverse_map = line_maps and line_maps.right_reverse

  -- Show all comments (API + pending)
  local file_threads = M.get_current_file_threads()
  
  for _, thread in ipairs(file_threads) do
    if thread.line then
      -- Convert file line to display line using reverse map
      local display_line = thread.line
      if reverse_map and reverse_map[thread.line] then
        display_line = reverse_map[thread.line]
      end
      
      pcall(function()
        vim.api.nvim_buf_set_extmark(right_buf, ns, display_line - 1, 0, {
          sign_text = thread.pending and "📝" or "💬",
          sign_hl_group = thread.pending and "DiagnosticWarn" or "DiagnosticInfo",
        })
      end)
    end
  end
end

function M.get_thread_at_cursor()
  local display_line = vim.api.nvim_win_get_cursor(0)[1]
  local file_threads = M.get_current_file_threads()
  
  -- Get reverse map to convert file lines to display lines for comparison
  local review = require("pr.review")
  local current_file = review.current and review.current.files[review.current.file_index]
  local line_maps = review.current and review.current.line_maps and review.current.line_maps[current_file]
  local reverse_map = line_maps and line_maps.right_reverse
  
  for _, thread in ipairs(file_threads) do
    if thread.line then
      local thread_display_line = thread.line
      if reverse_map and reverse_map[thread.line] then
        thread_display_line = reverse_map[thread.line]
      end
      if thread_display_line == display_line then
        return thread
      end
    end
  end
  return nil
end

function M.open_thread_at_cursor()
  local thread = M.get_thread_at_cursor()
  if thread then
    M.show_thread_popup(thread)
  else
    local file_threads = M.get_current_file_threads()
    if #file_threads > 0 then
      -- Get reverse map to show display lines (not file lines)
      local review = require("pr.review")
      local current_file = review.current and review.current.files[review.current.file_index]
      local line_maps = review.current and review.current.line_maps and review.current.line_maps[current_file]
      local reverse_map = line_maps and line_maps.right_reverse
      
      local lines = {}
      for _, t in ipairs(file_threads) do
        local display_line = t.line
        if reverse_map and reverse_map[t.line] then
          display_line = reverse_map[t.line]
        end
        table.insert(lines, tostring(display_line))
      end
      vim.notify("No comment on this line. Comments on lines: " .. table.concat(lines, ", "), vim.log.levels.INFO)
    else
      vim.notify("No comments in this file", vim.log.levels.INFO)
    end
  end
end

function M.get_current_file_threads()
  local review = require("pr.review")
  if not review.current then return {} end
  
  local current_file = review.current.files[review.current.file_index]
  if not current_file then return {} end
  
  local file_threads = {}
  
  -- Add API threads
  for _, thread in ipairs(M.threads) do
    if thread.path == current_file then
      table.insert(file_threads, thread)
    end
  end
  
  -- Add pending comments
  for _, comment in ipairs(review.current.pending_comments or {}) do
    if comment.path == current_file then
      table.insert(file_threads, {
        id = "pending_" .. comment.line,
        path = comment.path,
        line = comment.line,
        body = comment.body,
        author = "you (pending)",
        pending = true,
      })
    end
  end
  
  return file_threads
end

function M.next()
  local file_threads = M.get_current_file_threads()
  if #file_threads == 0 then
    vim.notify("No comments in this file", vim.log.levels.INFO)
    return
  end
  
  M.file_thread_index = ((M.file_thread_index or 0) % #file_threads) + 1
  local thread = file_threads[M.file_thread_index]
  M.jump_to_line(thread.line)
  M.show_thread_popup(thread)
end

function M.prev()
  local file_threads = M.get_current_file_threads()
  if #file_threads == 0 then
    vim.notify("No comments in this file", vim.log.levels.INFO)
    return
  end
  
  M.file_thread_index = (M.file_thread_index or 1) - 1
  if M.file_thread_index < 1 then
    M.file_thread_index = #file_threads
  end
  local thread = file_threads[M.file_thread_index]
  M.jump_to_line(thread.line)
  M.show_thread_popup(thread)
end

function M.jump_to_line(file_line)
  if not file_line then return end
  
  -- Convert file line to display line using reverse map
  local review = require("pr.review")
  local current_file = review.current and review.current.files[review.current.file_index]
  local line_maps = review.current and review.current.line_maps and review.current.line_maps[current_file]
  local reverse_map = line_maps and line_maps.right_reverse
  
  local display_line = file_line
  if reverse_map and reverse_map[file_line] then
    display_line = reverse_map[file_line]
  end
  
  pcall(vim.api.nvim_win_set_cursor, 0, { display_line, 0 })
end

function M.goto_thread(index)
  local thread = M.threads[index]
  if not thread then return end

  vim.notify(string.format("[%d/%d] %s:%d - @%s: %s",
    index, #M.threads, thread.path or "?", thread.line or 0,
    thread.author, thread.body:sub(1, 50)
  ), vim.log.levels.INFO)

  -- TODO: Jump to file and line if not in diff view
  M.show_thread_popup(thread)
end

function M.goto_thread_by_id(id)
  for i, thread in ipairs(M.threads) do
    if thread.id == id then
      M.current_index = i
      M.goto_thread(i)
      return
    end
  end
end

-- Collect all comments in a thread (root + replies)
function M.get_thread_chain(thread)
  local chain = { thread }
  
  -- Find the root comment ID for this thread
  local root_id = thread.in_reply_to or thread.id
  
  -- Collect all replies to the same root
  for _, t in ipairs(M.threads) do
    if t.id ~= thread.id then
      if t.in_reply_to == root_id or t.id == root_id or t.in_reply_to == thread.id then
        -- Avoid duplicates
        local already = false
        for _, existing in ipairs(chain) do
          if existing.id == t.id then already = true; break end
        end
        if not already then
          table.insert(chain, t)
        end
      end
    end
  end
  
  -- Sort by id (chronological for API comments)
  table.sort(chain, function(a, b)
    return tostring(a.id) < tostring(b.id)
  end)
  
  return chain
end

function M.show_thread_popup(thread)
  -- Show full thread conversation, not just single comment
  local chain = M.get_thread_chain(thread)
  
  local lines = {}
  for i, comment in ipairs(chain) do
    local author = comment.author or "unknown"
    if comment.pending then author = "you (pending)" end
    table.insert(lines, "**@" .. author .. ":**")
    for _, line in ipairs(vim.split(comment.body or "", "\n")) do
      table.insert(lines, line)
    end
    if i < #chain then
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"

  local width = math.floor(vim.o.columns * 0.5)
  local height = math.min(#lines + 2, 20)

  local author = thread.author or "unknown"
  if thread.pending then
    author = "you (pending)"
  end
  local title = string.format(" @%s %s:%d ", author, thread.path or "?", thread.line or 0)

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

  -- Enable word wrap for readability
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- Close on q or Esc
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })

  -- Reply with r
  vim.keymap.set("n", "r", function()
    vim.api.nvim_win_close(win, true)
    M.reply(thread.id)
  end, { buffer = buf })
  
  -- Delete pending comment with d, edit with e
  if thread.pending then
    vim.keymap.set("n", "d", function()
      vim.api.nvim_win_close(win, true)
      M.delete_pending(thread.line)
    end, { buffer = buf })
    
    vim.keymap.set("n", "e", function()
      vim.api.nvim_win_close(win, true)
      M.edit_pending(thread.line)
    end, { buffer = buf })
  else
    -- Delete committed comment (only if it's yours)
    local github = require("pr.github")
    if thread.author == github.current_user then
      vim.keymap.set("n", "d", function()
        vim.ui.select({ "Yes", "No" }, { prompt = "Delete this comment?" }, function(choice)
          if choice == "Yes" then
            vim.api.nvim_win_close(win, true)
            M.delete_committed(thread)
          end
        end)
      end, { buffer = buf })
    end
  end
end

function M.delete_committed(thread)
  local review = require("pr.review")
  local github = require("pr.github")
  
  if not review.current then return end
  
  local ok, err = github.delete_comment(review.current.owner, review.current.repo, thread.id)
  if ok then
    vim.notify("Comment deleted", vim.log.levels.INFO)
    -- Remove from local threads
    for i, t in ipairs(M.threads) do
      if t.id == thread.id then
        table.remove(M.threads, i)
        break
      end
    end
    M.show_all_comments()
  else
    vim.notify(err or "Failed to delete comment", vim.log.levels.ERROR)
  end
end

function M.delete_pending(line)
  local review = require("pr.review")
  if not review.current then return end
  
  local current_file = review.current.files[review.current.file_index]
  
  for i, comment in ipairs(review.current.pending_comments) do
    if comment.path == current_file and comment.line == line then
      table.remove(review.current.pending_comments, i)
      vim.notify("Deleted pending comment", vim.log.levels.INFO)
      M.show_all_comments()
      return
    end
  end
end

function M.edit_pending(line)
  local review = require("pr.review")
  if not review.current then return end
  
  local current_file = review.current.files[review.current.file_index]
  
  for _, comment in ipairs(review.current.pending_comments) do
    if comment.path == current_file and comment.line == line then
      -- Capture reference to the comment we're editing
      local target_comment = comment
      
      -- Open edit window with existing content
      local lines = vim.split(target_comment.body, "\n")
      
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].buftype = "nofile"
      
      local width = math.floor(vim.o.columns * 0.5)
      local height = math.max(#lines + 3, 5)
      
      local title = string.format(" Edit comment %s:%d ", target_comment.path, target_comment.line)
      
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
      
      vim.wo[win].wrap = true
      vim.wo[win].linebreak = true
      
      local function save()
        local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local new_body = table.concat(new_lines, "\n")
        vim.api.nvim_win_close(win, true)
        
        if new_body:gsub("%s", "") ~= "" then
          target_comment.body = new_body
          vim.notify("Comment updated", vim.log.levels.INFO)
          M.show_all_comments()
        else
          -- Empty = delete; find current index at deletion time
          for j, c in ipairs(review.current.pending_comments) do
            if c == target_comment then
              table.remove(review.current.pending_comments, j)
              break
            end
          end
          vim.notify("Comment deleted (empty)", vim.log.levels.INFO)
          M.show_all_comments()
        end
      end
      
      local function cancel()
        vim.api.nvim_win_close(win, true)
      end
      
      vim.keymap.set("n", "<CR>", save, { buffer = buf })
      vim.keymap.set("n", "<C-s>", save, { buffer = buf })
      vim.keymap.set("i", "<C-s>", function()
        vim.cmd("stopinsert")
        save()
      end, { buffer = buf })
      vim.keymap.set("n", "<Esc>", cancel, { buffer = buf })
      vim.keymap.set("i", "<Esc>", function()
        vim.cmd("stopinsert")
        cancel()
      end, { buffer = buf })
      vim.keymap.set("n", "q", cancel, { buffer = buf })
      
      return
    end
  end
end

function M.reply(thread_id)
  local review = require("pr.review")
  if not review.current then
    vim.notify("No active PR review", vim.log.levels.WARN)
    return
  end

  thread_id = thread_id or (M.threads[M.current_index] and M.threads[M.current_index].id)
  if not thread_id then
    vim.notify("No thread selected", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Reply: " }, function(body)
    if not body or body == "" then return end

    local github = require("pr.github")
    local ok, err = github.reply_to_comment(
      review.current.owner,
      review.current.repo,
      review.current.number,
      thread_id,
      body
    )

    if ok then
      vim.notify("Reply posted", vim.log.levels.INFO)
      M.load(review.current.owner, review.current.repo, review.current.number)
    else
      vim.notify(err or "Failed to post reply", vim.log.levels.ERROR)
    end
  end)
end

return M
