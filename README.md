# pr.nvim

A Neovim plugin for reviewing GitHub pull requests without leaving your editor. View side-by-side diffs, add comments and code suggestions, navigate through existing comment threads, and submit reviews all from within Neovim.

The plugin integrates with Telescope for file and PR picking, persists your review progress across sessions and uses async loading to keep the UI responsive. Comments you add are stored locally until you submit your review, so you can close Neovim and pick up where you left off.

![demo](assets/demo.gif)

## Requirements

- Neovim >= 0.9
- [gh CLI](https://cli.github.com/)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for pickers)

## Installation

### lazy.nvim

```lua
{
  dir = "~/path/to/pr.nvim",  -- local path
  -- or use your repo:
  -- "your-username/pr.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim", -- optional
  },
  config = function()
    require("pr").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "your-username/pr.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("pr").setup()
  end,
}
```

### Manual

Clone the repository and add to your runtimepath:

```bash
git clone https://github.com/your-username/pr.nvim ~/.local/share/nvim/site/pack/plugins/start/pr.nvim
```

Then in your config:

```lua
require("pr").setup()
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:PR` | List open PRs (filter by title, author, number, or status like `approved`, `changes requested`, `review requested`) |
| `:PR 123` | Open PR #123 in current repo |
| `:PR owner/repo#123` | Open PR from any repo |
| `:PR @username` | List PRs by user |
| `:PR submit` | Submit review |
| `:PR close` | Exit review mode |

### Keybindings

In review mode:

| Key | Action |
|-----|--------|
| `f` | Open file picker |
| `F` | Toggle full file view (see entire file with changes highlighted) |
| `p` | Show PR info/description |
| `c` | Add comment at cursor (Ctrl+S or Enter in normal mode to submit) |
| `s` | Add suggestion (with code block) |
| `r` | Reply to thread |
| `e` | Edit pending comment |
| `d` | Delete pending comment |
| `Ctrl+]` / `gd` | Open actual file at cursor (enables LSP/go-to-definition) |
| `v` | Toggle file as reviewed |
| `S` | Submit review |
| `Enter` | Open comment at cursor |
| `q` | Close current file tab |
| `Q` | Close entire review |
| `?` | Show help |
| `n` / `N` | Next/prev change |
| `]f` / `[f` | Next/prev file |
| `]c` / `[c` | Next/prev comment |

In file picker: `Ctrl+v` toggles reviewed status.

In comment popup: `r` to reply, `e` to edit pending, `d` to delete pending, `Esc` to close.

## Workflow

1. `:PR` to open the PR picker
2. Select a PR to open file picker (with diff preview)
3. Select a file to view side-by-side diff
4. Auto-jumps to first change in file
5. Press `F` to toggle full file view (helpful for more context)
6. Navigate with `]f`/`[f` (files) and `]c`/`[c` (comments)
7. Press `c` to comment, `s` to suggest changes
8. Mark files reviewed with `v`
9. `S` to submit your review
10. `Q` to close (state is saved automatically)

## Programmatic API

The plugin exposes Lua functions for integration with AI tools like amp or claude:

```lua
-- Check if a PR review is active
local status = require("pr").get_status()
-- Returns: { active = true, pr_number = 123, owner = "...", repo = "...", files = {...} }

-- Add a comment programmatically
require("pr").add_comment({
  path = "src/main.lua",
  line = 42,
  body = "Consider using a constant here",
})

-- Add a code suggestion
require("pr").add_suggestion({
  path = "src/main.lua",
  line = 42,
  code = "local TIMEOUT = 30",
})

-- List pending comments
local pending = require("pr").list_pending_comments()

-- Submit the review
require("pr").submit_review({ event = "comment", body = "Some notes" })
-- event can be: "approve", "comment", "request_changes"
```

These functions can be called via Neovim's RPC or from the command line:
```bash
nvim --headless -c "lua require('pr').add_comment({path='src/foo.lua', line=10, body='Fix this'})" -c "qa"
```
