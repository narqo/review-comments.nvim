local M = {}

local function escapes_root(path)
  return path == ".." or path:match("^%.%.[/\\]") ~= nil
end

function M.validate_relative_file(path)
  if type(path) ~= "string" or path == "" then
    return nil, "Source path is missing"
  end

  local normalized = vim.fs.normalize(path)
  local absolute = normalized:sub(1, 1) == "/"
    or normalized:match("^%a:[/\\]") ~= nil
    or normalized:match("^[/\\][/\\]") ~= nil
  if absolute or normalized == "." or escapes_root(normalized) then
    return nil, "Source path must stay inside the Git working tree"
  end
  return normalized
end

function M.relative_file(root, path)
  local relative
  if vim.fs.relpath then
    relative = vim.fs.relpath(root, path)
  else
    local normalized_root = vim.fs.normalize(root):gsub("\\", "/"):gsub("/+$", "")
    local normalized_path = vim.fs.normalize(path):gsub("\\", "/")
    local prefix = normalized_root .. "/"
    if normalized_path:sub(1, #prefix) == prefix then
      relative = normalized_path:sub(#prefix + 1)
    end
  end

  local validated = relative and M.validate_relative_file(relative) or nil
  if not validated then
    return nil, "Source file is outside the Git working tree"
  end
  return validated
end

function M.root_for_directory(directory)
  if vim.fn.executable("git") ~= 1 then
    return nil, "Git executable not found"
  end
  if type(directory) ~= "string" or directory == "" then
    return nil, "Could not determine the working directory"
  end

  local result = vim.system({
    "git",
    "-C",
    directory,
    "rev-parse",
    "--show-toplevel",
  }, { text = true }):wait(3000)

  if result.code ~= 0 then
    return nil, "Directory is not inside a Git working tree"
  end

  local root = vim.trim(result.stdout or "")
  if root == "" then
    return nil, "Git returned an empty repository root"
  end

  return vim.fs.normalize(root)
end

function M.root_for_file(path)
  local directory = vim.fs.dirname(path)
  if not directory or directory == "" then
    return nil, "Could not determine the source directory"
  end

  local root, root_err = M.root_for_directory(directory)
  if not root and root_err == "Directory is not inside a Git working tree" then
    return nil, "Source file is not inside a Git working tree"
  end
  return root, root_err
end

return M
