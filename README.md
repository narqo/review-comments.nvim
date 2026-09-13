# draft-comments.nvim

Draft review comments from source buffers.

## Quick test

From this plugin directory, open a file from any Git repository:

```sh
nvim --cmd "set runtimepath+=$PWD" /path/to/git-repo/source.go
```

Then:

1. Select lines with visual line mode, for example `Vjj`.
2. Run `:DraftComment` while the selection is active.
3. Enter the comment in the floating editor.
4. Press `<C-s>` or run `:write` to save and close.
5. Inspect `<git-root>/.review-comments/`.

Use `:quit!` to cancel.

The same workflow applies to the active pane of a native `:diffsplit`.

## Configuration

No mapping is installed by default. Add one through `setup()`:

```lua
require("draft-comments").setup({
  output_dir = ".review-comments",
  keymap = "<leader>dc",
})
```

The plugin requires Neovim 0.10 or newer, Git, and a named file inside a Git working tree.

## Automated tests

```sh
make test
```

Each comment is stored as a separate Markdown file containing JSON metadata with a `draft` status, absolute source path, selected line range, and selected source text.
