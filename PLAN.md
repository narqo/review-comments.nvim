# Draft Comments Neovim Plugin Plan

## Goal

Build a small Lua plugin for drafting review comments from normal source buffers and native Neovim `:diffsplit` windows. Each comment is written to a generated Markdown file for consumption by an external reviewer.

The MVP only creates files. It does not load, display, edit, delete, resolve, or publish existing comments.

## User workflow

1. Open a named source file, optionally in a native `:diffsplit`.
2. Select one or more lines in visual mode.
3. Run `:'<,'>DraftComment` or a configured visual-mode mapping.
4. Enter the comment in a Markdown floating buffer anchored below the selection.
5. Save with `<C-s>` or `:write`.
6. The plugin creates the comment file and closes the floating window.

Use `:quit!` to cancel without creating a file.

The plugin will expose `:DraftComment` as a ranged command. It will not install a mapping by default. A suggested mapping is:

```lua
vim.keymap.set("x", "<leader>dc", ":<C-u>'<,'>DraftComment<CR>")
```

## Selection behavior

- Normalize all visual selections to complete lines.
- Record one-based, inclusive start and end line numbers.
- Store exactly the selected lines as the comment context.
- Join context lines with newline characters without adding surrounding lines.
- Use the active buffer when invoked from a `:diffsplit` window. No diff parsing or side tracking is required.
- Reject unnamed buffers.
- Reject buffers whose files are outside a Git working tree.

Files are assumed to remain static after comments are created. The MVP will not relocate stale line ranges.

## In-place editor

Create a temporary Markdown buffer in a floating window:

- Anchor it below the selected range in the active window.
- Place it above the range when there is insufficient space below.
- Constrain its dimensions to the active window, including narrow diff panes.
- Start in insert mode.
- Set the buffer to `filetype=markdown`.
- Use an `acwrite` buffer and handle `BufWriteCmd` so `:write` saves the draft rather than writing the temporary buffer.
- Map `<C-s>` in insert and normal modes to the same save operation.
- Reject an empty or whitespace-only comment and keep the editor open.
- Keep the editor open when directory creation or file writing fails.
- Close and wipe the temporary buffer after a successful save.

Only one draft editor should be active at a time. Attempting to create another comment while one is open should focus the existing editor or return a clear error.

## Repository and output directory

Determine the Git repository root from the selected buffer's absolute path. Use Git's reported top-level working-tree path so worktrees and nested repositories behave correctly.

Write files under:

```text
<git-root>/.review-comments/
```

Create the directory when it does not exist. Keep all comment files directly inside it; do not mirror source directories.

The plugin must not modify `.gitignore` or `.git/info/exclude`. Keeping `.review-comments/` untracked is the user's responsibility.

## Filename format

Create one file per comment using:

```text
<utc-iso-datetime>-<6-random-hex>.md
```

Use filesystem-safe ISO 8601 basic format with millisecond precision. Example:

```text
2026-03-04T162109.123Z-8f3a1c.md
```

Create files exclusively and retry with a new random suffix on collision. Never overwrite an existing comment file.

## File format

Each file is Markdown containing a fenced JSON metadata block followed by the comment body.

````markdown
```json
{
  "version": 1,
  "status": "draft",
  "file": "/Users/example/project/internal/server/server.go",
  "range": {
    "start_line": 42,
    "end_line": 47
  },
  "context": "func handleRequest(w http.ResponseWriter, r *http.Request) {\n    return serveRequest(w, r)\n}"
}
```

The error should include the request method and path.
````

Metadata fields:

- `version`: format version, initially `1`.
- `status`: fixed to `draft`; the MVP does not manage status transitions.
- `file`: normalized absolute path of the active source buffer.
- `range.start_line`: one-based inclusive first selected line.
- `range.end_line`: one-based inclusive last selected line.
- `context`: exact selected complete lines joined with `\n`.

Encode metadata with Neovim's JSON encoder so quotes, control characters, backslashes, and non-ASCII source text remain valid JSON. Preserve the comment body as entered, apart from ensuring a single blank line separates it from the metadata block and the generated file ends with a newline.

## Configuration

Provide a minimal setup function:

```lua
require("draft-comments").setup({
  output_dir = ".review-comments",
  keymap = nil,
})
```

- `output_dir` is interpreted relative to the Git repository root and must remain a relative path.
- `keymap`, when set, installs a visual-mode mapping for `:DraftComment`.
- Calling `setup()` is optional; defaults should work after the plugin is loaded.

Do not introduce external Lua dependencies.

## Errors

Report concise errors through `vim.notify` for:

- unnamed source buffer;
- source file outside a Git repository;
- invalid or empty range;
- empty comment;
- output directory creation failure;
- random filename generation failure;
- file collision after bounded retries;
- file open or write failure.

Errors before opening the editor should leave the source window unchanged. Save errors should preserve the draft text and keep the editor open.

## Suggested structure

```text
plugin/
  draft-comments.lua
lua/
  draft-comments/
    init.lua
    editor.lua
    storage.lua
    git.lua
```

Responsibilities:

- `plugin/draft-comments.lua`: register the ranged `:DraftComment` command.
- `init.lua`: configuration, command entry point, and public API.
- `editor.lua`: selection capture, floating editor lifecycle, save and cancel behavior.
- `storage.lua`: filename generation, JSON/Markdown rendering, exclusive file creation.
- `git.lua`: repository-root discovery and source-path validation.

## Implementation sequence

1. Add the plugin module, default configuration, and ranged command.
2. Capture and normalize visual line ranges from the active buffer.
3. Resolve the absolute source path and Git repository root.
4. Implement the anchored Markdown editor and cancellation behavior.
5. Implement metadata rendering and exclusive file creation.
6. Connect `<C-s>` and `BufWriteCmd` to save and close.
7. Add error handling for unsupported buffers, empty comments, and storage failures.
8. Add headless tests for pure formatting and storage logic, followed by functional editor tests.
9. Document installation, configuration, command usage, and the suggested mapping.

## Acceptance criteria

- A line selection in a normal source buffer creates one Markdown file under the repository's `.review-comments/` directory.
- A selection in either active pane of a native `:diffsplit` records that pane's absolute file path and line range.
- Output files use the UTC timestamp and random hexadecimal filename format.
- The output directory remains flat regardless of the source file's location.
- The fenced metadata block parses as JSON.
- Metadata contains the correct absolute file path, inclusive range, and exact selected lines.
- The Markdown body matches the entered comment.
- `<C-s>` and `:write` save exactly one file and close the editor.
- `:quit!` creates no file.
- Empty comments and write failures do not close the editor.
- Existing files are never overwritten.
- The plugin does not create mappings unless configured.

## Future work

Explicitly defer the following:

- loading comments from disk;
- inline markers or virtual text for existing comments;
- editing or deleting comments;
- comment status transitions and management;
- anchor relocation after source changes;
- parsing diff hunks or tracking old/new diff sides;
- GitHub or other review-service integration;
- publishing comments;
- modifying Git ignore configuration.
