local M = {}

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
