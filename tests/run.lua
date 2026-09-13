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

local function markdown_parts(content)
  local json, body = content:match("^```json\n(.-)\n```\n\n(.*)$")
  if not json then
    fail("comment file does not have the expected Markdown structure")
  end
  return vim.json.decode(json), body
end

local function comment_files(root)
  local directory = vim.fs.joinpath(root, ".review-comments")
  local files = vim.fn.glob(vim.fs.joinpath(directory, "*.md"), false, true)
  table.sort(files)
  return files
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
  local storage = require("draft-comments.storage")
  local rendered = storage.render({
    file = "/tmp/source.lua",
    range = { start_line = 2, end_line = 3 },
    context = "local quoted = \"value\"\nreturn quoted",
  }, "Check the quoted value.")

  local metadata, body = markdown_parts(rendered)
  assert_equal(1, metadata.version)
  assert_equal("draft", metadata.status)
  assert_equal("/tmp/source.lua", metadata.file)
  assert_equal({ start_line = 2, end_line = 3 }, metadata.range)
  assert_equal("local quoted = \"value\"\nreturn quoted", metadata.context)
  assert_equal("Check the quoted value.\n", body)
end)

test("creates unique flat comment files", function()
  local storage = require("draft-comments.storage")
  local root = vim.fn.tempname()
  assert_equal(1, vim.fn.mkdir(root, "p"))
  local metadata = {
    file = "/tmp/source.lua",
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
  local root = create_repository()
  local source = vim.fs.joinpath(root, "server.lua")
  write_file(source, {
    "local function serve(request)",
    "  local method = request.method",
    "  return method",
    "end",
  })

  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local expected_source = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  require("draft-comments").setup({})
  vim.cmd("2,3DraftComment")

  local draft_buf = vim.api.nvim_get_current_buf()
  assert_equal("markdown", vim.bo[draft_buf].filetype)
  local window_config = vim.api.nvim_win_get_config(0)
  assert_equal(3, window_config.height)
  assert_equal("server.lua:2-3", border_text(window_config.title))
  vim.api.nvim_buf_set_lines(draft_buf, 0, -1, false, {
    "Include the request path.",
    "This needs enough context for debugging.",
  })
  vim.cmd("write")

  local files = comment_files(root)
  assert_equal(1, #files)
  local metadata, body = markdown_parts(read_file(files[1]))
  assert_equal(expected_source, metadata.file)
  assert_equal({ start_line = 2, end_line = 3 }, metadata.range)
  assert_equal("  local method = request.method\n  return method", metadata.context)
  assert_equal("Include the request path.\nThis needs enough context for debugging.\n", body)
  assert(not vim.api.nvim_buf_is_valid(draft_buf), "draft buffer must close after saving")

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
  local opened = require("draft-comments").draft({ start_line = 30, end_line = 30 })
  assert_equal(true, opened)

  local window_config = vim.api.nvim_win_get_config(0)
  assert_equal(3, window_config.height)
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
  local opened = require("draft-comments").draft({ start_line = 1, end_line = 1 })
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
  require("draft-comments").setup({})
  local opened = require("draft-comments").draft({ start_line = 1, end_line = 1 })
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
  local expected_source = vim.fs.normalize(vim.api.nvim_buf_get_name(0))

  local opened = require("draft-comments").draft({ start_line = 1, end_line = 1 })
  assert_equal(true, opened)
  local draft_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(draft_buf, 0, -1, false, { "Why did this value change?" })
  vim.cmd("write")

  local files = comment_files(root)
  assert_equal(1, #files)
  local metadata = markdown_parts(read_file(files[1]))
  assert_equal(expected_source, metadata.file)
  assert_equal("local value = 2", metadata.context)

  vim.cmd("only!")
  vim.fn.delete(root, "rf")
end)

test("registers the ranged command and manages the configured mapping", function()
  local plugin = require("draft-comments")
  plugin.setup({})
  assert_equal(2, vim.fn.exists(":DraftComment"))
  assert_equal(0, vim.fn.exists(":ReviewComment"))
  assert_equal(nil, vim.fn.maparg("<leader>dc", "x", false, true).lhs)

  plugin.setup({ keymap = "<leader>dc" })
  local mapping = vim.fn.maparg("<leader>dc", "x", false, true)
  assert_equal("Draft a comment for the selected lines", mapping.desc)

  plugin.setup({})
  assert_equal(nil, vim.fn.maparg("<leader>dc", "x", false, true).lhs)
end)

if failures > 0 then
  print(string.format("%d of %d tests failed", failures, tests))
  vim.cmd("cquit 1")
else
  print(string.format("all %d tests passed", tests))
  vim.cmd("quitall!")
end
