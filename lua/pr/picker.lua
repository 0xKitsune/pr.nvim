local M = {}

function M.list_prs(opts)
  opts = opts or {}
  local github = require("pr.github")

  local filter = ""
  if opts.author then
    filter = "--author " .. opts.author
  end

  vim.notify("Loading PRs...", vim.log.levels.INFO)

  github.list_prs(filter, function(prs, err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    if not prs or #prs == 0 then
      vim.notify("No open PRs found", vim.log.levels.INFO)
      return
    end

    local ok, _ = pcall(require, "telescope.pickers")
    if ok then
      M._telescope_prs(prs)
    else
      M._select_prs(prs)
    end
  end)
end

function M._select_prs(prs)
  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, string.format("#%d %s (%s)", pr.number, pr.title, pr.author.login))
  end

  vim.ui.select(items, { prompt = "Select PR:" }, function(_, idx)
    if idx then
      require("pr.review").open(prs[idx].number)
    end
  end)
end

function M._telescope_prs(prs)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local themes = require("telescope.themes")

  local opts = themes.get_dropdown({
    layout_config = {
      width = 0.7,
      height = 0.6,
    },
    previewer = false,
  })

  opts.sorting_strategy = "ascending"
  opts.layout_config.prompt_position = "top"

  pickers.new(opts, {
    prompt_title = "Pull Requests",
    finder = finders.new_table({
      results = prs,
      entry_maker = function(pr)
        local status = pr.review_status or ""
        local display = string.format("#%-4d %-45s @%-15s %s", 
          pr.number, 
          pr.title:sub(1, 45), 
          pr.author.login,
          status
        )
        return {
          value = pr,
          display = display,
          ordinal = pr.title .. " " .. pr.author.login .. " " .. pr.number,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        require("pr.review").open(selection.value.number)
      end)
      return true
    end,
  }):find()
end

function M.list_files()
  local review = require("pr.review")
  if not review.current then
    vim.notify("No active PR review", vim.log.levels.WARN)
    return
  end

  local files = review.current.files or {}
  if #files == 0 then
    vim.notify("No changed files", vim.log.levels.INFO)
    return
  end

  local ok, _ = pcall(require, "telescope.pickers")
  if ok then
    M._telescope_files(files, review.current)
  else
    M._select_files(files, review.current)
  end
end

function M._select_files(files, current)
  local items = {}
  for _, file in ipairs(files) do
    local status = current.reviewed[file] and "✓" or " "
    table.insert(items, string.format("[%s] %s", status, file))
  end

  vim.ui.select(items, { prompt = "Changed files:" }, function(_, idx)
    if idx then
      require("pr.review").open_file(files[idx])
    end
  end)
end

function M._telescope_files(files, current)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")
  local previewers = require("telescope.previewers")

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 3 },
      { remaining = true },
    },
  })

  -- Cache the full diff
  local github = require("pr.github")
  local full_diff = github.get_diff(current.owner, current.repo, current.number)

  local function extract_file_diff(file)
    if not full_diff then return {} end
    local lines = vim.split(full_diff, "\n")
    local result = {}
    local in_file = false

    for _, line in ipairs(lines) do
      if line:match("^diff %-%-git") then
        if line:match(file:gsub("%-", "%%-"):gsub("%.", "%%.")) then
          in_file = true
        else
          if in_file then break end
          in_file = false
        end
      end
      if in_file and not line:match("^diff %-%-git") and not line:match("^index ") then
        table.insert(result, line)
      end
    end
    return result
  end

  pickers.new({
    layout_strategy = "horizontal",
    layout_config = {
      width = 0.85,
      height = 0.8,
      preview_width = 0.55,
      prompt_position = "top",
    },
    sorting_strategy = "ascending",
  }, {
    prompt_title = string.format("PR #%d Files (%d)", current.number, #files),
    finder = finders.new_table({
      results = files,
      entry_maker = function(file)
        local status = current.reviewed[file] and "●" or "○"
        return {
          value = file,
          display = function()
            return displayer({
              { status, current.reviewed[file] and "DiagnosticOk" or "Comment" },
              file,
            })
          end,
          ordinal = file,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Diff",
      define_preview = function(self, entry)
        local diff_lines = extract_file_diff(entry.value)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, diff_lines)
        vim.bo[self.state.bufnr].filetype = "diff"
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        require("pr.review").open_file(selection.value)
      end)

      local function toggle_reviewed()
        local selection = action_state.get_selected_entry()
        if not selection then return end
        
        local selected_file = selection.value
        
        if current.reviewed[selected_file] then
          current.reviewed[selected_file] = nil
        else
          current.reviewed[selected_file] = true
        end
        
        -- Find index of current selection
        local selected_idx = 1
        for i, f in ipairs(files) do
          if f == selected_file then
            selected_idx = i
            break
          end
        end
        
        local picker = action_state.get_current_picker(prompt_bufnr)
        picker:refresh(finders.new_table({
          results = files,
          entry_maker = function(file)
            local status = current.reviewed[file] and "●" or "○"
            return {
              value = file,
              display = function()
                return displayer({
                  { status, current.reviewed[file] and "DiagnosticOk" or "Comment" },
                  file,
                })
              end,
              ordinal = file,
            }
          end,
        }), { reset_prompt = false })
        
        -- Restore selection to same file
        vim.defer_fn(function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          if current_picker then
            current_picker:set_selection(selected_idx - 1)
          end
        end, 10)
      end

      map("i", "<C-v>", toggle_reviewed)
      map("n", "<C-v>", toggle_reviewed)
      map("n", "v", toggle_reviewed)

      return true
    end,
  }):find()
end

function M.list_threads()
  local threads = require("pr.threads").threads
  if #threads == 0 then
    vim.notify("No comment threads", vim.log.levels.INFO)
    return
  end

  local ok, _ = pcall(require, "telescope.pickers")
  if ok then
    M._telescope_threads(threads)
  else
    M._select_threads(threads)
  end
end

function M._select_threads(threads)
  local items = {}
  for _, t in ipairs(threads) do
    table.insert(items, string.format("%s:%d - @%s: %s", t.path or "?", t.line or 0, t.author, (t.body or ""):sub(1, 40)))
  end

  vim.ui.select(items, { prompt = "Comment threads:" }, function(_, idx)
    if idx then
      require("pr.threads").goto_thread(idx)
    end
  end)
end

function M._telescope_threads(threads)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Comment Threads",
    finder = finders.new_table({
      results = threads,
      entry_maker = function(t)
        return {
          value = t,
          display = string.format("%s:%d @%s: %s", t.path or "?", t.line or 0, t.author, (t.body or ""):sub(1, 40)),
          ordinal = (t.path or "") .. " " .. (t.body or "") .. " " .. t.author,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = require("telescope.previewers").new_buffer_previewer({
      title = "Comment",
      define_preview = function(self, entry)
        local lines = {
          "📍 " .. (entry.value.path or "?") .. ":" .. (entry.value.line or 0),
          "👤 @" .. entry.value.author,
          "",
        }
        for _, line in ipairs(vim.split(entry.value.body or "", "\n")) do
          table.insert(lines, line)
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = "markdown"
      end,
    }),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        require("pr.threads").goto_thread_by_id(selection.value.id)
      end)
      return true
    end,
  }):find()
end

return M
