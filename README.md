# pr.nvim

A Neovim plugin for reviewing GitHub pull requests without leaving your editor. View side-by-side diffs, add comments and code suggestions, navigate through existing comment threads, and submit reviews—all from within Neovim.

The plugin integrates with Telescope for file and PR picking, persists your review progress across sessions, and uses async loading to keep the UI responsive. Comments you add are stored locally until you submit your review, so you can close Neovim and pick up where you left off.

## Requirements

- Neovim >= 0.9
- [gh CLI](https://cli.github.com/) (authenticated)
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
| `:PR` | List open PRs (telescope picker) |
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
| `c` | Add comment at cursor |
| `s` | Add suggestion (with code block) |
| `r` | Reply to thread |
| `v` | Toggle file as reviewed |
| `S` | Submit review |
| `Enter` | Open comment at cursor |
| `q` | Close current file tab |
| `Q` | Close entire review |
| `?` | Show help |
| `]f` / `[f` | Next/prev file |
| `]c` / `[c` | Next/prev comment |

In file picker: `Ctrl+v` toggles reviewed status.

In comment popup: `r` to reply, `d` to delete pending comments, `Esc` to close.

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

## License

MIT
