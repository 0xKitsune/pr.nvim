# pr.nvim

Review GitHub pull requests directly in Neovim.

## Features

- 🔍 Browse and open PRs from any repo
- 📝 Add comments on specific lines
- 💡 Add code suggestions
- 💬 Navigate and reply to comment threads
- ✅ Submit reviews (approve, comment, request changes)
- 🔭 Telescope integration

## Requirements

- Neovim >= 0.9
- [gh CLI](https://cli.github.com/) (authenticated)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for pickers)

## Installation

### lazy.nvim

```lua
{
  "sekiro/pr.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim", -- optional
  },
  config = function()
    require("pr").setup({
      provider = "github",
      keymaps = {
        comment = "c",
        suggest = "s",
        reply = "r",
        approve = "a",
        next_file = "]f",
        prev_file = "[f",
        next_comment = "]c",
        prev_comment = "[c",
        close = "q",
      },
    })
  end,
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:PR` | List open PRs (telescope picker) |
| `:PR 123` | Open PR #123 in current repo |
| `:PR owner/repo#123` | Open PR from any repo |
| `:PR @username` | List PRs by user |
| `:PR comment` | Add comment at cursor |
| `:PR suggest` | Add code suggestion |
| `:PR reply` | Reply to current thread |
| `:PR threads` | List all comment threads |
| `:PR submit` | Submit review |
| `:PR diff` | Toggle diff view |
| `:PR files` | List changed files |
| `:PR close` | Exit review mode |

### Review Mode Keymaps

When reviewing a PR, these keymaps are active:

| Key | Action |
|-----|--------|
| `c` | Add comment |
| `s` | Add suggestion |
| `r` | Reply to thread |
| `a` | Approve PR |
| `]f` | Next file |
| `[f` | Previous file |
| `]c` | Next comment |
| `[c` | Previous comment |
| `q` | Close review |

## Workflow

1. `:PR` to open the PR picker
2. Select a PR to open it in diff view
3. Navigate with `]f`/`[f` (files) and `]c`/`[c` (comments)
4. Press `c` to comment, `s` to suggest changes
5. `:PR submit` to submit your review

## TODO

- [ ] GitLab support
- [ ] Inline diff view per file
- [ ] Resolve/unresolve threads
- [ ] Create new PRs
- [ ] Checkout PR branch
