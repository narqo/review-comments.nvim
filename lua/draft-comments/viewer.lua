local float = require("draft-comments.float")

local M = {}

local active
local autocmd_group = vim.api.nvim_create_augroup("DraftCommentsViewer", { clear = false })

local function body_lines(body)
  local lines = vim.split(body, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

local function content_lines(comments)
  if #comments == 1 then
    return body_lines(comments[1].body)
  end

  local lines = {}
  for index, comment in ipairs(comments) do
    if index > 1 then
      table.insert(lines, "")
    end
    local range = comment.metadata.range
    local label = tostring(range.start_line)
    if range.start_line ~= range.end_line then
      label = string.format("%d-%d", range.start_line, range.end_line)
    end
    table.insert(lines, string.format("## Lines %s", label))
    table.insert(lines, "")
    vim.list_extend(lines, body_lines(comment.body))
  end
  return lines
end

local function close_viewer(viewer)
  active = nil
  if vim.api.nvim_win_is_valid(viewer.win) then
    pcall(vim.api.nvim_win_close, viewer.win, true)
  end
  if vim.api.nvim_buf_is_valid(viewer.buf) then
    pcall(vim.api.nvim_buf_delete, viewer.buf, { force = true })
  end
  if vim.api.nvim_win_is_valid(viewer.source_win) then
    pcall(vim.api.nvim_set_current_win, viewer.source_win)
  end
end

function M.open(opts)
  if active and vim.api.nvim_win_is_valid(active.win) then
    close_viewer(active)
  elseif active then
    active = nil
  end

  local lines = content_lines(opts.comments)
  local start_line = opts.comments[1].metadata.range.start_line
  local end_line = opts.comments[1].metadata.range.end_line
  for _, comment in ipairs(opts.comments) do
    start_line = math.min(start_line, comment.metadata.range.start_line)
    end_line = math.max(end_line, comment.metadata.range.end_line)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, string.format("draft-comment-view://%d", buf))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  local geometry = float.geometry({
    source_win = opts.source_win,
    start_line = opts.cursor_line,
    end_line = opts.cursor_line,
    max_height = math.min(math.max(#lines, 1), 12),
    label = float.label(opts.source_path, start_line, end_line),
  })
  local ok, win_or_err = pcall(vim.api.nvim_open_win, buf, true, geometry)
  if not ok then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return nil, string.format("Could not open comment viewer: %s", win_or_err)
  end

  local viewer = {
    buf = buf,
    win = win_or_err,
    source_win = opts.source_win,
  }
  active = viewer
  vim.wo[viewer.win].wrap = true
  vim.wo[viewer.win].linebreak = true

  vim.keymap.set("n", "q", function()
    if active and active.buf == buf then
      close_viewer(active)
    end
  end, {
    buffer = buf,
    desc = "Close draft comment viewer",
    silent = true,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    group = autocmd_group,
    once = true,
    callback = function(args)
      if active and active.buf == args.buf then
        active = nil
      end
    end,
  })

  return true
end

return M
