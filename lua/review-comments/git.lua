local M = {}

local function escapes_root(path)
  return path == ".." or path:match("^%.%.[/\\]") ~= nil
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

  if not relative or relative == "" or relative == "." or escapes_root(relative) then
    return nil, "Source file is outside the Git working tree"
  end
  return vim.fs.normalize(relative)
end

function M.root_for_file(path)
  if vim.fn.executable("git") ~= 1 then
    return nil, "Git executable not found"
  end

  local directory = vim.fs.dirname(path)
  if not directory or directory == "" then
    return nil, "Could not determine the source directory"
  end

  local result = vim.system({
    "git",
    "-C",
    directory,
    "rev-parse",
    "--show-toplevel",
  }, { text = true }):wait(3000)

  if result.code ~= 0 then
    return nil, "Source file is not inside a Git working tree"
  end

  local root = vim.trim(result.stdout or "")
  if root == "" then
    return nil, "Git returned an empty repository root"
  end

  return vim.fs.normalize(root)
end

return M
