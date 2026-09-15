local geometry = require("review-comments.geometry")
local git = require("review-comments.git")
local storage = require("review-comments.storage")

local M = {}

local active
local autocmd_group = vim.api.nvim_create_augroup("ReviewCommentsEditor", { clear = false })

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR, { title = "review-comments.nvim" })
end

local function clear_stale_editor()
  if not active then
    return
  end
  if vim.api.nvim_buf_is_valid(active.buf) and vim.api.nvim_win_is_valid(active.win) then
    return
  end

  if vim.api.nvim_buf_is_valid(active.buf) then
    pcall(vim.api.nvim_buf_delete, active.buf, { force = true })
  end
  active = nil
end

local function close_editor(draft)
  active = nil

  if vim.api.nvim_win_is_valid(draft.win) then
    pcall(vim.api.nvim_win_close, draft.win, true)
  end
  if vim.api.nvim_buf_is_valid(draft.buf) then
    pcall(vim.api.nvim_buf_delete, draft.buf, { force = true })
  end
  if vim.api.nvim_win_is_valid(draft.source_win) then
    pcall(vim.api.nvim_set_current_win, draft.source_win)
  end
end

function M.save(buf)
  local draft = active
  if not draft or draft.buf ~= buf or not vim.api.nvim_buf_is_valid(buf) then
    notify("No draft comment is open")
    return false
  end

  local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if not body:match("%S") then
    notify("Comment must not be empty", vim.log.levels.WARN)
    return false
  end

  local path, err = storage.write(
    draft.root,
    draft.output_dir,
    draft.metadata,
    body
  )
  if not path then
    notify(err)
    return false
  end

  vim.bo[buf].modified = false
  close_editor(draft)
  if draft.on_saved then
    local ok, callback_err = pcall(draft.on_saved, {
      path = path,
      root = draft.root,
      source_buf = draft.source_buf,
    })
    if not ok then
      notify(string.format("Comment was saved but could not be displayed: %s", callback_err))
    end
  end
  notify(string.format("Draft comment saved to %s", path), vim.log.levels.INFO)
  return true, path
end

function M.open(opts)
  clear_stale_editor()
  if active then
    vim.api.nvim_set_current_win(active.win)
    notify("A draft comment is already open", vim.log.levels.INFO)
    return false
  end

  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()
  local source_name = vim.api.nvim_buf_get_name(source_buf)
  if source_name == "" then
    notify("Cannot draft a comment for an unnamed buffer")
    return false
  end

  local start_line = tonumber(opts.start_line)
  local end_line = tonumber(opts.end_line)
  local line_count = vim.api.nvim_buf_line_count(source_buf)
  if not start_line or not end_line then
    notify("Comment range is missing")
    return false
  end

  start_line = math.floor(start_line)
  end_line = math.floor(end_line)
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  if start_line < 1 or end_line > line_count then
    notify("Comment range is outside the source buffer")
    return false
  end

  local source_path = vim.fs.normalize(source_name)
  local root, root_err = git.root_for_file(source_path)
  if not root then
    notify(root_err)
    return false
  end

  local context = table.concat(
    vim.api.nvim_buf_get_lines(source_buf, start_line - 1, end_line, false),
    "\n"
  )
  local metadata = {
    file = source_path,
    range = {
      start_line = start_line,
      end_line = end_line,
    },
    context = context,
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, string.format("draft-comment://%d", buf))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"

  local window_config = geometry.window_config({
    source_win = source_win,
    start_line = start_line,
    end_line = end_line,
    max_height = 3,
    label = geometry.label(source_path, start_line, end_line),
  })
  local ok, win_or_err = pcall(vim.api.nvim_open_win, buf, true, window_config)
  if not ok then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    notify(string.format("Could not open comment editor: %s", win_or_err))
    return false
  end

  local win = win_or_err
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  active = {
    buf = buf,
    win = win,
    source_buf = source_buf,
    source_win = source_win,
    root = root,
    output_dir = opts.output_dir,
    metadata = metadata,
    on_saved = opts.on_saved,
  }

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    group = autocmd_group,
    callback = function(args)
      M.save(args.buf)
    end,
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

  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    M.save(buf)
  end, {
    buffer = buf,
    desc = "Save draft comment",
    silent = true,
  })

  vim.cmd("startinsert")
  return true
end

return M
