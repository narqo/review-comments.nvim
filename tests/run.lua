local failures = 0
local tests = 0

local function fail(message)
  error(message, 2)
end

local function assert_equal(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    fail(string.format(
      "%s\nexpected: %s\nactual:   %s",
      message or "values differ",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

local function assert_match(value, pattern, message)
  if not value:match(pattern) then
    fail(string.format("%s\nvalue: %s\npattern: %s", message or "pattern did not match", value, pattern))
  end
end

local function test(name, callback)
  tests = tests + 1
  local ok, err = xpcall(callback, debug.traceback)
  if ok then
    print("ok - " .. name)
  else
    failures = failures + 1
    print("not ok - " .. name)
    print(err)
  end
end

local function write_file(path, lines)
  local result = vim.fn.writefile(lines, path)
  assert_equal(0, result, "failed to write fixture")
end

local function read_file(path)
  local lines = vim.fn.readfile(path)
  return table.concat(lines, "\n") .. "\n"
end

local function write_content(path, content)
  local fd, open_err = vim.uv.fs_open(path, "w", 384)
  if not fd then
    fail(open_err)
  end
  local written, write_err = vim.uv.fs_write(fd, content, 0)
  vim.uv.fs_close(fd)
  if not written then
    fail(write_err)
  end
end

local function comment_parts(content)
  local comment, parse_err = require("review-comments.storage").parse(content)
  if not comment then
    fail(parse_err)
  end
  return comment.metadata, comment.body
end

local function comment_files(root)
  local directory = vim.fs.joinpath(root, ".review-comments")
  local files = vim.fn.glob(vim.fs.joinpath(directory, "*.md"), false, true)
  table.sort(files)
  return files
end

local function preview_extmarks(buf)
  return vim.api.nvim_buf_get_extmarks(
    buf,
    require("review-comments.comments").namespace(),
    0,
    -1,
    { details = true }
  )
end

local function border_text(value)
  if type(value) == "string" then
    return vim.trim(value)
  end
  if type(value) ~= "table" then
    return nil
  end

  local chunks = {}
  for _, chunk in ipairs(value) do
    table.insert(chunks, chunk[1])
  end
  return vim.trim(table.concat(chunks))
end

local function create_repository()
  local root = vim.fn.tempname()
  assert_equal(1, vim.fn.mkdir(root, "p"), "failed to create temporary repository")
  local result = vim.system({ "git", "init", "--quiet", root }, { text = true }):wait(3000)
  assert_equal(0, result.code, "failed to initialize temporary repository")
  return vim.fs.normalize(root)
end

local notifications = {}
vim.notify = function(message, level)
  table.insert(notifications, { message = message, level = level })
end

test("renders parseable JSON metadata and Markdown", function()
  local storage = require("review-comments.storage")
  local rendered = storage.render({
    file = "source.lua",
    range = { start_line = 2, end_line = 3 },
    context = "local quoted = \"value\"\nreturn quoted",
  }, "Check the quoted value.")

  assert_equal("{", rendered:sub(1, 1))
  assert_equal(nil, rendered:find("```json", 1, true))
  local metadata, body = comment_parts(rendered)
  assert_equal(1, metadata.version)
  assert_equal("draft", metadata.status)
  assert_equal("source.lua", metadata.file)
  assert_equal({ start_line = 2, end_line = 3 }, metadata.range)
  assert_equal("local quoted = \"value\"\nreturn quoted", metadata.context)
  assert_equal("Check the quoted value.\n", body)
end)

test("parses comment files and allows unknown metadata fields", function()
  local storage = require("review-comments.storage")
  local rendered = storage.render({
    file = "internal/source.lua",
    range = { start_line = 4, end_line = 4 },
    context = "return true",
  }, "Keep this return value.")
  rendered = rendered:gsub('  "status": "draft",', '  "status": "draft",\n  "unknown": true,')

  local comment, parse_err = storage.parse(rendered, "/tmp/comment.md")
  if not comment then
    fail(parse_err)
  end
  assert_equal("/tmp/comment.md", comment.path)
  assert_equal(true, comment.metadata.unknown)
  assert_equal("Keep this return value.\n", comment.body)

  local invalid, invalid_err = storage.parse("not a comment", "/tmp/bad.md")
  assert_equal(nil, invalid)
  assert_equal("missing JSON frontmatter", invalid_err)
end)

test("builds Unicode-safe comment previews", function()
  local comments = require("review-comments.comments")
  local long = string.rep("界", 41)
  local preview = comments.preview({ { body = "\n" .. long } })
  assert_equal(string.rep("界", 37) .. "...", preview)
  assert_equal(40, vim.fn.strchars(preview))

  preview = comments.preview({
    { body = "\n**first comment**" },
    { body = "second comment" },
  })
  assert_equal("**first comment** (+1 more)", preview)
end)

test("creates unique flat comment files", function()
  local storage = require("review-comments.storage")
  local root = vim.fn.tempname()
  assert_equal(1, vim.fn.mkdir(root, "p"))
  local metadata = {
    file = "source.lua",
    range = { start_line = 1, end_line = 1 },
    context = "return true",
  }

  local first, first_err = storage.write(root, ".review-comments", metadata, "First")
  if not first then
    fail(first_err)
  end
  local second, second_err = storage.write(root, ".review-comments", metadata, "Second")
  if not second then
    fail(second_err)
  end

  assert(first ~= second, "comment filenames must be unique")
  assert_match(vim.fs.basename(first), "^%d%d%d%d%-%d%d%-%d%dT%d%d%d%d%d%d%.%d%d%dZ%-%x%x%x%x%x%x%.md$")
  assert_equal(vim.fs.dirname(first), vim.fs.dirname(second))
  assert_equal(2, #vim.fn.glob(vim.fs.joinpath(root, ".review-comments", "*.md"), false, true))

  vim.fn.delete(root, "rf")
end)

test("saves a selected source range through the floating editor", function()
  local old_lines = vim.o.lines
  vim.o.lines = 60
  local root = create_repository()
  local source_dir = vim.fs.joinpath(root, "internal")
  local source = vim.fs.joinpath(source_dir, "server.lua")
  assert_equal(1, vim.fn.mkdir(source_dir, "p"))
  write_file(source, {
    "local function serve(request)",
    "  local method = request.method",
    "  return method",
    "end",
  })

  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local source_buf = vim.api.nvim_get_current_buf()
  require("review-comments").setup({})
  vim.cmd("2,3AddComment")

  local draft_buf = vim.api.nvim_get_current_buf()
  assert_equal("markdown", vim.bo[draft_buf].filetype)
  assert(vim.fn.maparg("<C-s>", "n", false, true).buffer ~= 1, "normal-mode <C-s> must not be buffer-local")
  assert(vim.fn.maparg("<C-s>", "i", false, true).buffer ~= 1, "insert-mode <C-s> must not be buffer-local")
  local window_config = vim.api.nvim_win_get_config(0)
  assert_equal(1, window_config.height)
  assert_equal("server.lua:2-3", border_text(window_config.title))
  vim.api.nvim_buf_set_lines(draft_buf, 0, -1, false, {
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
  })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = draft_buf })
  assert_equal(5, vim.api.nvim_win_get_config(0).height)

  vim.api.nvim_buf_set_lines(draft_buf, 0, -1, false, {
    "Include the request path.",
    "This needs enough context for debugging.",
  })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = draft_buf })
  assert_equal(2, vim.api.nvim_win_get_config(0).height)
  vim.cmd("w")

  local files = comment_files(root)
  assert_equal(1, #files)
  local metadata, body = comment_parts(read_file(files[1]))
  assert_equal(vim.fs.normalize("internal/server.lua"), metadata.file)
  assert_equal({ start_line = 2, end_line = 3 }, metadata.range)
  assert_equal("  local method = request.method\n  return method", metadata.context)
  assert_equal("Include the request path.\nThis needs enough context for debugging.\n", body)
  assert(not vim.api.nvim_buf_is_valid(draft_buf), "draft buffer must close after saving")

  local extmarks = preview_extmarks(source_buf)
  assert_equal(1, #extmarks)
  assert_equal(2, extmarks[1][2])
  assert_equal("eol", extmarks[1][4].virt_text_pos)
  assert_equal(" -- Include the request path.", extmarks[1][4].virt_text[1][1])

  vim.o.lines = old_lines
  vim.fn.delete(root, "rf")
end)

test("loads previews, refreshes external changes, and views overlapping comments", function()
  local storage = require("review-comments.storage")
  local root = create_repository()
  local source = vim.fs.joinpath(root, "reviewed.lua")
  local output_dir = vim.fs.joinpath(root, ".review-comments")
  write_file(source, { "local value = 1", "return value", "" })
  assert_equal(1, vim.fn.mkdir(output_dir, "p"))

  local first_body = "This comment is intentionally much longer than forty characters."
  local first_path = vim.fs.joinpath(output_dir, "2026-01-01T000000.000Z-000001.md")
  local second_path = vim.fs.joinpath(output_dir, "2026-01-01T000001.000Z-000002.md")
  write_content(first_path, storage.render({
    file = "reviewed.lua",
    range = { start_line = 1, end_line = 2 },
    context = "local value = 1\nreturn value",
  }, "\n" .. first_body))
  write_content(second_path, storage.render({
    file = "reviewed.lua",
    range = { start_line = 2, end_line = 2 },
    context = "return value",
  }, "Second comment."))
  write_content(vim.fs.joinpath(output_dir, "bad.md"), "invalid")

  require("review-comments").setup({})
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local source_buf = vim.api.nvim_get_current_buf()
  local extmarks = preview_extmarks(source_buf)
  assert_equal(1, #extmarks)
  assert_equal(1, extmarks[1][2])
  local expected = vim.fn.strcharpart(first_body, 0, 27) .. "... (+1 more)"
  assert_equal(" -- " .. expected, extmarks[1][4].virt_text[1][1])
  assert_equal(40, vim.fn.strchars(expected))

  local warned = false
  for _, notification in ipairs(notifications) do
    if notification.message:match("Ignored bad%.md:") then
      warned = true
      break
    end
  end
  assert(warned, "malformed comment file must produce a warning")

  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("ViewComment")
  local viewer_buf = vim.api.nvim_get_current_buf()
  assert_equal(false, vim.bo[viewer_buf].modifiable)
  assert_equal(true, vim.bo[viewer_buf].readonly)
  local viewed = table.concat(vim.api.nvim_buf_get_lines(viewer_buf, 0, -1, false), "\n")
  assert_match(viewed, "## Lines 1%-2")
  assert_match(viewed, first_body:gsub("([%.%-])", "%%%1"))
  assert_match(viewed, "## Lines 2")
  assert_match(viewed, "Second comment%.")
  assert_equal("reviewed.lua:1-2", border_text(
    vim.api.nvim_win_get_config(0).title or vim.api.nvim_win_get_config(0).footer
  ))
  vim.cmd("quit")

  vim.uv.fs_unlink(second_path)
  write_content(first_path, storage.render({
    file = "reviewed.lua",
    range = { start_line = 1, end_line = 2 },
    context = "local value = 1\nreturn value",
  }, "Updated externally."))
  vim.cmd("RefreshComment")
  extmarks = preview_extmarks(source_buf)
  assert_equal(1, #extmarks)
  assert_equal(" -- Updated externally.", extmarks[1][4].virt_text[1][1])

  vim.uv.fs_unlink(first_path)
  vim.uv.fs_unlink(vim.fs.joinpath(output_dir, "bad.md"))
  vim.cmd("RefreshComment")
  assert_equal(0, #preview_extmarks(source_buf))

  vim.fn.delete(root, "rf")
end)

test("places the label below an editor shown above the range", function()
  local root = create_repository()
  local source = vim.fs.joinpath(root, "bottom.lua")
  local lines = {}
  for line = 1, 40 do
    table.insert(lines, string.format("local value_%d = %d", line, line))
  end
  write_file(source, lines)

  vim.cmd("edit " .. vim.fn.fnameescape(source))
  vim.api.nvim_win_set_cursor(0, { 30, 0 })
  vim.cmd("normal! zb")
  local opened = require("review-comments").draft({ start_line = 30, end_line = 30 })
  assert_equal(true, opened)

  local window_config = vim.api.nvim_win_get_config(0)
  assert_equal(1, window_config.height)
  assert_equal(nil, border_text(window_config.title))
  assert_equal("bottom.lua:30", border_text(window_config.footer))

  vim.cmd("quit!")
  vim.fn.delete(root, "rf")
end)

test("rejects empty comments and cancels without writing", function()
  local root = create_repository()
  local source = vim.fs.joinpath(root, "source.lua")
  write_file(source, { "return true" })

  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local opened = require("review-comments").draft({ start_line = 1, end_line = 1 })
  assert_equal(true, opened)
  local draft_buf = vim.api.nvim_get_current_buf()

  vim.cmd("write")
  assert(vim.api.nvim_buf_is_valid(draft_buf), "empty draft must remain open")
  assert_equal(0, #comment_files(root))
  assert_equal("Comment must not be empty", notifications[#notifications].message)

  vim.api.nvim_buf_set_lines(draft_buf, 0, -1, false, { "Do not save this." })
  vim.cmd("quit!")
  assert_equal(0, #comment_files(root))

  vim.fn.delete(root, "rf")
end)

test("keeps the editor open when the output path is not writable", function()
  local root = create_repository()
  local source = vim.fs.joinpath(root, "source.lua")
  local output_path = vim.fs.joinpath(root, ".review-comments")
  write_file(source, { "return true" })
  write_file(output_path, { "not a directory" })

  vim.cmd("edit " .. vim.fn.fnameescape(source))
  require("review-comments").setup({})
  local opened = require("review-comments").draft({ start_line = 1, end_line = 1 })
  assert_equal(true, opened)
  local draft_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(draft_buf, 0, -1, false, { "This should remain open." })

  vim.cmd("write")
  assert(vim.api.nvim_buf_is_valid(draft_buf), "draft must remain open after a write failure")
  assert_match(notifications[#notifications].message, "^Could not create output directory:")
  assert_equal({ "not a directory" }, vim.fn.readfile(output_path))

  vim.cmd("quit!")
  vim.fn.delete(root, "rf")
end)

test("uses the active diffsplit pane as the source", function()
  local root = create_repository()
  local old_file = vim.fs.joinpath(root, "old.lua")
  local new_file = vim.fs.joinpath(root, "new.lua")
  write_file(old_file, { "local value = 1", "return value" })
  write_file(new_file, { "local value = 2", "return value" })

  vim.cmd("edit " .. vim.fn.fnameescape(old_file))
  vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(new_file))
  assert_equal("new.lua", vim.fs.basename(vim.api.nvim_buf_get_name(0)))

  local opened = require("review-comments").draft({ start_line = 1, end_line = 1 })
  assert_equal(true, opened)
  local draft_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(draft_buf, 0, -1, false, { "Why did this value change?" })
  vim.cmd("write")

  local files = comment_files(root)
  assert_equal(1, #files)
  local metadata = comment_parts(read_file(files[1]))
  assert_equal("new.lua", metadata.file)
  assert_equal("local value = 2", metadata.context)

  vim.cmd("only!")
  vim.fn.delete(root, "rf")
end)

test("registers the ranged command and manages the configured mapping", function()
  local plugin = require("review-comments")
  plugin.setup({})
  assert_equal(2, vim.fn.exists(":AddComment"))
  assert_equal(2, vim.fn.exists(":RefreshComment"))
  assert_equal(2, vim.fn.exists(":ViewComment"))
  assert_equal(0, vim.fn.exists(":DraftComment"))
  assert_equal(0, vim.fn.exists(":DraftCommentsRefresh"))
  assert_equal(0, vim.fn.exists(":DraftCommentView"))
  assert_equal(nil, vim.fn.maparg("<leader>ac", "x", false, true).lhs)

  plugin.setup({ keymap = "<leader>ac" })
  local mapping = vim.fn.maparg("<leader>ac", "x", false, true)
  assert_equal("Add a comment for the selected lines", mapping.desc)

  plugin.setup({})
  assert_equal(nil, vim.fn.maparg("<leader>ac", "x", false, true).lhs)
end)

if failures > 0 then
  print(string.format("%d of %d tests failed", failures, tests))
  vim.cmd("cquit 1")
else
  print(string.format("all %d tests passed", tests))
  vim.cmd("quitall!")
end
