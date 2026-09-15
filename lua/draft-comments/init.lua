local comments = require("draft-comments.comments")
local editor = require("draft-comments.editor")

local M = {}

local defaults = {
  output_dir = ".review-comments",
  keymap = nil,
}

local config = vim.deepcopy(defaults)
local configured_keymap

local function normalize_output_dir(path)
  if type(path) ~= "string" or path == "" then
    error("draft-comments: output_dir must be a non-empty string")
  end
  if path:find("\0", 1, true) then
    error("draft-comments: output_dir must not contain NUL bytes")
  end

  local normalized = vim.fs.normalize(path)
  local absolute = normalized:sub(1, 1) == "/"
    or normalized:match("^%a:[/\\]") ~= nil
    or normalized:match("^[/\\][/\\]") ~= nil
  local escapes_root = normalized == ".." or normalized:match("^%.%.[/\\]") ~= nil

  if absolute or escapes_root then
    error("draft-comments: output_dir must stay inside the Git repository")
  end

  return normalized
end

function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("draft-comments: setup options must be a table")
  end
  if opts.keymap ~= nil and (type(opts.keymap) ~= "string" or opts.keymap == "") then
    error("draft-comments: keymap must be a non-empty string or nil")
  end

  local next_config = {
    output_dir = normalize_output_dir(opts.output_dir or defaults.output_dir),
    keymap = opts.keymap,
  }

  if configured_keymap and configured_keymap ~= next_config.keymap then
    pcall(vim.keymap.del, "x", configured_keymap)
  end

  comments.reset()
  config = next_config
  configured_keymap = config.keymap

  if config.keymap then
    vim.keymap.set("x", config.keymap, ":<C-u>'<,'>DraftComment<CR>", {
      desc = "Draft a comment for the selected lines",
      silent = true,
    })
  end
end

function M.draft(range)
  range = range or {}
  local output_dir = config.output_dir
  return editor.open({
    start_line = range.start_line,
    end_line = range.end_line,
    output_dir = output_dir,
    on_saved = function(event)
      comments.comment_saved(event, output_dir)
    end,
  })
end

function M.refresh()
  return comments.refresh_buffer(vim.api.nvim_get_current_buf(), config.output_dir)
end

function M.view()
  return comments.view_buffer(vim.api.nvim_get_current_buf(), config.output_dir)
end

function M._on_buf_enter(buf)
  comments.load_buffer(buf, config.output_dir)
end

return M
