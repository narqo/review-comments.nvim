local git = require("draft-comments.git")
local storage = require("draft-comments.storage")
local viewer = require("draft-comments.viewer")

local M = {}

local namespace = vim.api.nvim_create_namespace("draft-comments-previews")
local indexes = {}
local attachments = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR, { title = "draft-comments.nvim" })
end

local function index_key(root, output_dir)
  return root .. "\0" .. output_dir
end

local function path_key(path)
  local resolved = vim.uv.fs_realpath(path)
  return vim.fs.normalize(resolved or path)
end

local function first_nonempty_line(body)
  for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
    if line:match("%S") then
      return line
    end
  end
  return ""
end

local function truncate(text, limit)
  local length = vim.fn.strchars(text)
  if length <= limit then
    return text
  end
  if limit <= 3 then
    return vim.fn.strcharpart("...", 0, math.max(0, limit))
  end
  return vim.fn.strcharpart(text, 0, limit - 3) .. "..."
end

function M.preview(comments)
  local suffix = ""
  if #comments > 1 then
    suffix = string.format(" (+%d more)", #comments - 1)
  end

  local available = 40 - vim.fn.strchars(suffix)
  if available <= 0 then
    return truncate(suffix, 40)
  end
  return truncate(first_nonempty_line(comments[1].body), available) .. suffix
end

local function scan(root, output_dir)
  local comments, errors = storage.scan(root, output_dir)
  local by_file = {}
  for _, comment in ipairs(comments) do
    local key = path_key(comment.metadata.file)
    by_file[key] = by_file[key] or {}
    table.insert(by_file[key], comment)
  end

  local key = index_key(root, output_dir)
  indexes[key] = {
    root = root,
    output_dir = output_dir,
    comments = comments,
    by_file = by_file,
  }

  for _, scan_error in ipairs(errors) do
    notify(string.format(
      "Ignored %s: %s",
      vim.fs.basename(scan_error.path),
      scan_error.error
    ), vim.log.levels.WARN)
  end

  return indexes[key]
end

local function render(buf, index, source_path)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

  local comments = index.by_file[path_key(source_path)] or {}
  local line_count = vim.api.nvim_buf_line_count(buf)
  local by_end_line = {}
  for _, comment in ipairs(comments) do
    local end_line = comment.metadata.range.end_line
    if end_line <= line_count then
      by_end_line[end_line] = by_end_line[end_line] or {}
      table.insert(by_end_line[end_line], comment)
    end
  end

  local lines = vim.tbl_keys(by_end_line)
  table.sort(lines)
  for _, line in ipairs(lines) do
    vim.api.nvim_buf_set_extmark(buf, namespace, line - 1, 0, {
      virt_text = { { M.preview(by_end_line[line]), "Comment" } },
      virt_text_pos = "right_align",
      hl_mode = "combine",
      priority = 100,
    })
  end
end

local function source_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function attach(buf, output_dir, opts)
  opts = opts or {}
  if not source_buffer(buf) then
    return nil, "Buffer is not a named source buffer"
  end

  local source_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  local root, root_err = git.root_for_file(source_path)
  if not root then
    if opts.notify then
      notify(root_err)
    end
    return nil, root_err
  end

  local key = index_key(root, output_dir)
  local index = indexes[key]
  if opts.force or not index then
    index = scan(root, output_dir)
  end

  attachments[buf] = {
    key = key,
    root = root,
    output_dir = output_dir,
    source_path = source_path,
  }
  render(buf, index, source_path)
  return index
end

function M.load_buffer(buf, output_dir)
  return attach(buf, output_dir)
end

function M.refresh_buffer(buf, output_dir)
  return attach(buf, output_dir, { force = true, notify = true })
end

function M.comment_saved(event, output_dir)
  local key = index_key(event.root, output_dir)
  local index = scan(event.root, output_dir)

  if source_buffer(event.source_buf) then
    local source_path = vim.fs.normalize(vim.api.nvim_buf_get_name(event.source_buf))
    attachments[event.source_buf] = {
      key = key,
      root = event.root,
      output_dir = output_dir,
      source_path = source_path,
    }
  end

  for buf, attachment in pairs(attachments) do
    if attachment.key == key then
      if source_buffer(buf) then
        render(buf, index, attachment.source_path)
      else
        attachments[buf] = nil
      end
    end
  end
end

function M.view_buffer(buf, output_dir)
  local index, err = attach(buf, output_dir, { notify = true })
  if not index then
    return false, err
  end

  local attachment = attachments[buf]
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local matching = {}
  for _, comment in ipairs(index.by_file[path_key(attachment.source_path)] or {}) do
    local range = comment.metadata.range
    if range.start_line <= cursor_line and cursor_line <= range.end_line then
      table.insert(matching, comment)
    end
  end

  if #matching == 0 then
    notify("No draft comment covers the cursor line", vim.log.levels.INFO)
    return false
  end

  local opened, view_err = viewer.open({
    comments = matching,
    source_path = attachment.source_path,
    source_win = vim.api.nvim_get_current_win(),
    cursor_line = cursor_line,
  })
  if not opened then
    notify(view_err)
    return false, view_err
  end
  return true
end

function M.reset()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, namespace, 0, -1)
    end
  end
  indexes = {}
  attachments = {}
end

function M.namespace()
  return namespace
end

return M
