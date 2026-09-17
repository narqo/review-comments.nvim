# review-comments.nvim

Draft code review comments from inside [Neovim](https://neovim.io/).

![Add new comment](./doc/add-comment.png)

## Quick test

From this plugin directory, open a file from any Git repository:

```sh
nvim --cmd "set runtimepath+=$PWD" /path/to/git-repo/source.go
```

## Usage

1. Select lines with visual line mode, for example `Vjj`.
2. Run `:AddComment` while the selection is active.
3. Enter the comment in the floating editor.
4. Run `:write` or `:w` to save and close.
5. The saved comment appears as virtual text after the source line and is written under `<git-root>/.review-comments/`.

For `jj diffedit`, the plugin needs the logical file path from `nvim.difftool` to resolve the Git root from Neovim's working directory:

```toml
[merge-tools.nvim]
edit-args = [
  "--cmd",
  "let g:review_comments_root = trim(system('jj root'))",
  "--cmd",
  "packadd nvim.difftool",
  "-d",
  "$left",
  "$right",
]
```

`g:review_comments_root` must be an absolute path to the workspace root. It overrides automatic root detection.

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

## Addressing comments

The agent skill at `.agents/skills/review-comment-inbox/SKILL.md` allows coding agents to inspect, address, test, and remove resolved comments.

In [pi](https://pi.dev/), start it explicitly with:

```text
/skill:review-comment-inbox
```

## Configuration

No mapping is installed by default. Add one through `setup()`:

```lua
require("review-comments").setup({
  output_dir = ".review-comments",
  keymap = "<leader>ac",
})
```

Each comment is a separate Markdown file with JSON frontmatter.

The plugin requires Neovim 0.10 or newer, Git, and a named file inside a Git working tree.

## Automated tests

```sh
make test
```

