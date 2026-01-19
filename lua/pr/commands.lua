local M = {}

function M.setup()
  vim.api.nvim_create_user_command("PR", function(opts)
    local args = vim.split(opts.args, " ", { trimempty = true })
    local subcmd = args[1]

    if not subcmd or subcmd == "" then
      require("pr.picker").list_prs()
    elseif subcmd:match("^%d+$") then
      require("pr.review").open(tonumber(subcmd))
    elseif subcmd:match("^@") then
      require("pr.picker").list_prs({ author = subcmd:sub(2) })
    elseif subcmd:match("/.*#%d+$") then
      local owner, repo, num = subcmd:match("([^/]+)/([^#]+)#(%d+)")
      require("pr.review").open(tonumber(num), owner, repo)
    elseif subcmd == "comment" then
      require("pr.comments").add_comment()
    elseif subcmd == "suggest" then
      require("pr.comments").add_suggestion()
    elseif subcmd == "reply" then
      require("pr.threads").reply()
    elseif subcmd == "threads" then
      require("pr.picker").list_threads()
    elseif subcmd == "submit" then
      require("pr.review").submit(args[2])
    elseif subcmd == "diff" then
      require("pr.review").toggle_diff()
    elseif subcmd == "files" then
      require("pr.picker").list_files()
    elseif subcmd == "close" then
      require("pr.review").close()
    else
      vim.notify("Unknown PR command: " .. subcmd, vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    desc = "PR review commands",
    complete = function(_, cmdline, _)
      local subcmds = { "comment", "suggest", "reply", "threads", "submit", "diff", "files", "close" }
      local args = vim.split(cmdline, " ", { trimempty = true })
      if #args <= 2 then
        return vim.tbl_filter(function(s)
          return s:find(args[2] or "", 1, true) == 1
        end, subcmds)
      end
      if args[2] == "submit" then
        return { "approve", "comment", "request_changes" }
      end
      return {}
    end,
  })
end

return M
