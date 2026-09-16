local git = require("review-comments.git")

local M = {}

local function path_key(path)
  local resolved = vim.uv.fs_realpath(path)
  return vim.fs.normalize(resolved or path)
end

local function is_absolute(path)
  return path:sub(1, 1) == "/"
    or path:match("^%a:[/\\]") ~= nil
    or path:match("^[/\\][/\\]") ~= nil
end

local function root_override()
  local value = vim.g.review_comments_root
  if value == nil then
    return nil
  end
  if type(value) ~= "string" or vim.trim(value) == "" then
    return nil, "g:review_comments_root must be a non-empty path"
  end

  local root = vim.fs.normalize(vim.trim(value))
  if not is_absolute(root) then
    return nil, "g:review_comments_root must be an absolute path"
  end
  local stat = vim.uv.fs_stat(root)
  if not stat or stat.type ~= "directory" then
    return nil, "g:review_comments_root must name an existing workspace root"
  end
  return path_key(root)
end

local function diff_entry(source_path)
  local quickfix = vim.fn.getqflist({ items = 1 })
  for _, item in ipairs(quickfix.items or {}) do
    local data = item.user_data
    if type(data) == "table" and data.diff and type(data.rel) == "string" then
      local left = type(data.left) == "string" and path_key(data.left) or nil
      local right = type(data.right) == "string" and path_key(data.right) or nil
      if source_path == left or source_path == right then
        return data
      end
    end
  end
end

function M.resolve(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil, "Cannot resolve an unnamed buffer"
  end

  local source_path = path_key(name)
  local configured_root, override_err = root_override()
  if override_err then
    return nil, override_err
  end

  local entry = diff_entry(source_path)
  if entry then
    local root = configured_root
    local root_err
    if not root then
      root, root_err = git.root_for_directory(vim.fn.getcwd())
    end
    if not root then
      return nil, root_err
    end

    local relative_file, relative_err = git.validate_relative_file(entry.rel)
    if not relative_file then
      return nil, relative_err
    end
    return {
      root = root,
      file = relative_file,
      physical_file = source_path,
      diff = true,
    }
  end

  local root = configured_root
  local root_err
  if not root then
    root, root_err = git.root_for_file(source_path)
  end
  if not root then
    return nil, root_err
  end
  local relative_file, relative_err = git.relative_file(root, source_path)
  if not relative_file then
    return nil, relative_err
  end
  return {
    root = root,
    file = relative_file,
    physical_file = source_path,
    diff = false,
  }
end

return M
