# pr.nvim

Review GitHub pull requests directly in Neovim.

## Features

- Browse and open PRs from any repo
- Side-by-side diff view with syntax highlighting
- Add comments and code suggestions
- Navigate and reply to comment threads
- Submit reviews (approve, comment, request changes)
- Telescope integration with diff preview
- Persistent review state (close and resume later)
- Async loading for fast performance

## Requirements

- Neovim >= 0.9
- [gh CLI](https://cli.github.com/) (authenticated)
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
| `f` | Open file picker |
| `]f` / `[f` | Next/prev file |
| `]c` / `[c` | Next/prev comment in file |
| `c` | Add comment at cursor |
| `s` | Add suggestion (with code block) |
| `r` | Reply to thread |
| `Enter` | Open comment at cursor |
| `v` | Toggle file as reviewed |
| `S` | Submit review (approve/comment/request changes) |
| `q` | Close current file tab |
| `Q` | Close entire review |
| `?` | Show help |

### File picker

| Key | Action |
|-----|--------|
| `Enter` | Open file diff |
| `Ctrl+v` | Toggle reviewed status |

### Comment/thread popup

| Key | Action |
|-----|--------|
| `r` | Reply to thread |
| `d` | Delete pending comment (pending only) |
| `Esc` / `q` | Close popup |

### Comment input

| Key | Action |
|-----|--------|
| `Enter` | Submit comment |
| `Esc` | Cancel |

## Workflow

1. `:PR` to open the PR picker
2. Select a PR to open file picker (with diff preview)
3. Select a file to view side-by-side diff
4. Auto-jumps to first change in file
5. Navigate with `]f`/`[f` (files) and `]c`/`[c` (comments)
6. Press `c` to comment, `s` to suggest changes
7. Mark files reviewed with `v`
8. `S` to submit your review
9. `Q` to close (state is saved automatically)

## Comment indicators

- 💬 (blue) - Existing comment from GitHub
- 💬 (yellow) - Pending comment (not yet submitted)

## Persistence

Your review progress is automatically saved when you close:
- Which files you've marked as reviewed
- Pending comments not yet submitted
- Current file position

Resume anytime by opening the same PR again.

## Configuration

```lua
require("pr").setup({
  provider = "github",  -- only github supported currently
  keymaps = {
    comment = "c",
    suggest = "s",
    reply = "r",
    next_file = "]f",
    prev_file = "[f",
    next_comment = "]c",
    prev_comment = "[c",
  },
})
```
