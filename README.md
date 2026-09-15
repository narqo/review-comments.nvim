# review-comments.nvim

Draft review comments from source buffers.

## Quick test

From this plugin directory, open a file from any Git repository:

```sh
nvim --cmd "set runtimepath+=$PWD" /path/to/git-repo/source.go
```

Then:

1. Select lines with visual line mode, for example `Vjj`.
2. Run `:AddComment` while the selection is active.
3. Enter the comment in the floating editor.
4. Press `<C-s>` or run `:write` to save and close.
5. The saved comment appears as right-aligned virtual text and is written under `<git-root>/.review-comments/`.

Use `:quit!` to cancel. The same workflow applies to the active pane of a native `:diffsplit`.

## Saved comments

The plugin loads comments when entering a source buffer. Each preview shows up to 40 characters from the first non-empty line.

Place the cursor inside a commented range and run:

```vim
:ViewComment
```

Reload comments created, changed, or removed externally with:

```vim
:RefreshComment
```

## Configuration

No mapping is installed by default. Add one through `setup()`:

```lua
require("review-comments").setup({
  output_dir = ".review-comments",
  keymap = "<leader>ac",
})
```

The plugin requires Neovim 0.10 or newer, Git, and a named file inside a Git working tree.

## Automated tests

```sh
make test
```

Each comment is stored as a separate Markdown file with raw JSON frontmatter containing a `draft` status, absolute source path, selected line range, and selected source text.
