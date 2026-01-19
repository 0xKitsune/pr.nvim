# pr.nvim

Review GitHub pull requests directly in Neovim.

## Features

- Browse and open PRs from any repo
- Add comments on specific lines
- Add code suggestions
- Navigate and reply to comment threads
- Submit reviews and approve, comment or request changes
- Telescope integration

## Requirements

- Neovim >= 0.9
- [gh CLI](https://cli.github.com/)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for pickers)

## Installation

### lazy.nvim

```lua
{
  "your-username/pr.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim", -- optional
  },
  config = function()
    require("pr").setup()
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
| `:PR files` | List changed files |
| `:PR close` | Exit review mode |

### Keybindings (in review mode)

| Key | Action |
|-----|--------|
| `f` | File picker |
| `]f` / `[f` | Next/prev file |
| `]c` / `[c` | Next/prev comment |
| `c` | Add comment |
| `s` | Add suggestion |
| `r` | Reply to thread |
| `v` | Toggle file as reviewed |
| `a` | Approve PR |
| `S` | Submit review |
| `q` | Close file tab |
| `Q` | Close entire review |
| `?` | Show help |

### File picker

| Key | Action |
|-----|--------|
| `<CR>` | Open file diff |
| `<C-v>` | Toggle reviewed status |

## Workflow

1. `:PR` to open the PR picker
2. Select a PR to open file picker
3. Select a file to view side-by-side diff
4. Navigate with `]f`/`[f` (files) and `]c`/`[c` (comments)
5. Press `c` to comment, `s` to suggest changes
6. `S` to submit your review
