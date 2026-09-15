local uv = vim.uv

local M = {}

local max_collision_retries = 10

local function timestamp()
  local seconds, microseconds = uv.gettimeofday()
  if not seconds then
    return nil, "could not read the current time"
  end

  local formatted = os.date("!%Y-%m-%dT%H%M%S", seconds)
  if not formatted then
    return nil, "could not format the current time"
  end

  return string.format("%s.%03dZ", formatted, math.floor(microseconds / 1000))
end

local function random_hex()
  local ok, bytes, err = pcall(uv.random, 3)
  if not ok then
    return nil, tostring(bytes)
  end
  if not bytes then
    return nil, err or "unknown random generator error"
  end

  local encoded = bytes:gsub(".", function(byte)
    return string.format("%02x", string.byte(byte))
  end)
  return encoded
end

local function ensure_directory(path)
  local stat, stat_err = uv.fs_stat(path)
  if stat then
    if stat.type ~= "directory" then
      return nil, string.format("output path is not a directory: %s", path)
    end
    return true
  end

  local ok, mkdir_result = pcall(vim.fn.mkdir, path, "p")
  if not ok then
    return nil, tostring(mkdir_result)
  end

  stat, stat_err = uv.fs_stat(path)
  if not stat or stat.type ~= "directory" then
    return nil, stat_err or string.format("could not create directory: %s", path)
  end

  return true
end

local function write_exclusive(path, content)
  local fd, open_err, open_code = uv.fs_open(path, "wx", 384)
  if not fd then
    return nil, open_err, open_code
  end

  local offset = 0
  while offset < #content do
    local written, write_err = uv.fs_write(fd, content:sub(offset + 1), offset)
    if not written then
      uv.fs_close(fd)
      uv.fs_unlink(path)
      return nil, write_err or "unknown write error"
    end
    if written == 0 then
      uv.fs_close(fd)
      uv.fs_unlink(path)
      return nil, "write returned zero bytes"
    end
    offset = offset + written
  end

  local closed, close_err = uv.fs_close(fd)
  if not closed then
    uv.fs_unlink(path)
    return nil, close_err or "unknown close error"
  end

  return true
end

local function read_file(path)
  local stat, stat_err = uv.fs_stat(path)
  if not stat then
    return nil, stat_err or "could not stat file"
  end

  local fd, open_err = uv.fs_open(path, "r", 0)
  if not fd then
    return nil, open_err
  end

  local content, read_err = uv.fs_read(fd, stat.size, 0)
  local _, close_err = uv.fs_close(fd)
  if not content then
    return nil, read_err or "could not read file"
  end
  if close_err then
    return nil, close_err
  end
  return content
end

local function is_absolute(path)
  return path:sub(1, 1) == "/"
    or path:match("^%a:[/\\]") ~= nil
    or path:match("^[/\\][/\\]") ~= nil
end

local function valid_line(value)
  return type(value) == "number" and value >= 1 and value == math.floor(value)
end

local function escapes_root(path)
  return path == ".." or path:match("^%.%.[/\\]") ~= nil
end

function M.resolve_file(root, path)
  if is_absolute(path) then
    return vim.fs.normalize(path)
  end
  return vim.fs.normalize(vim.fs.joinpath(root, path))
end

local function split_frontmatter(content)
  if content:sub(1, 1) ~= "{" then
    return nil
  end

  local depth = 0
  local in_string = false
  local escaped = false
  for index = 1, #content do
    local byte = content:sub(index, index)
    if in_string then
      if escaped then
        escaped = false
      elseif byte == "\\" then
        escaped = true
      elseif byte == '"' then
        in_string = false
      end
    elseif byte == '"' then
      in_string = true
    elseif byte == "{" then
      depth = depth + 1
    elseif byte == "}" then
      depth = depth - 1
      if depth == 0 then
        if content:sub(index + 1, index + 2) ~= "\n\n" then
          return nil
        end
        return content:sub(1, index), content:sub(index + 3)
      end
    end
  end
end

function M.parse(content, path)
  if type(content) ~= "string" then
    return nil, "content is not a string"
  end

  content = content:gsub("\r\n", "\n")
  local encoded, body = split_frontmatter(content)
  if not encoded then
    encoded, body = content:match("^```json[ \t]*\n(.-)\n```[ \t]*\n\n(.*)$")
  end
  if not encoded then
    return nil, "missing JSON frontmatter"
  end

  local ok, metadata = pcall(vim.json.decode, encoded)
  if not ok or type(metadata) ~= "table" then
    return nil, "invalid JSON metadata"
  end
  if metadata.version ~= 1 then
    return nil, string.format("unsupported metadata version: %s", tostring(metadata.version))
  end
  if metadata.status ~= "draft" then
    return nil, string.format("unsupported comment status: %s", tostring(metadata.status))
  end
  if type(metadata.file) ~= "string" or metadata.file == "" then
    return nil, "metadata file must be a non-empty path"
  end
  metadata.file = vim.fs.normalize(metadata.file)
  if not is_absolute(metadata.file) and escapes_root(metadata.file) then
    return nil, "metadata file must stay inside the repository root"
  end
  if type(metadata.range) ~= "table"
    or not valid_line(metadata.range.start_line)
    or not valid_line(metadata.range.end_line)
    or metadata.range.start_line > metadata.range.end_line
  then
    return nil, "metadata range is invalid"
  end
  if type(metadata.context) ~= "string" then
    return nil, "metadata context is not a string"
  end
  if not body:match("%S") then
    return nil, "comment body is empty"
  end

  return {
    path = path,
    metadata = metadata,
    body = body,
  }
end

function M.scan(root, output_dir)
  local directory = vim.fs.joinpath(root, output_dir)
  local handle, scan_err, scan_code = uv.fs_scandir(directory)
  if not handle then
    if scan_code == "ENOENT" then
      return {}, {}
    end
    return {}, { { path = directory, error = scan_err or "could not scan directory" } }
  end

  local paths = {}
  while true do
    local name, entry_type = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if name:match("%.md$") and (entry_type == "file" or entry_type == nil) then
      table.insert(paths, vim.fs.joinpath(directory, name))
    end
  end
  table.sort(paths)

  local comments = {}
  local errors = {}
  for _, comment_path in ipairs(paths) do
    local content, read_err = read_file(comment_path)
    if not content then
      table.insert(errors, { path = comment_path, error = read_err })
    else
      local comment, parse_err = M.parse(content, comment_path)
      if comment then
        table.insert(comments, comment)
      else
        table.insert(errors, { path = comment_path, error = parse_err })
      end
    end
  end

  return comments, errors
end

function M.render(metadata, body)
  local lines = {
    "{",
    '  "version": 1,',
    '  "status": "draft",',
    string.format('  "file": %s,', vim.json.encode(metadata.file)),
    '  "range": {',
    string.format('    "start_line": %d,', metadata.range.start_line),
    string.format('    "end_line": %d', metadata.range.end_line),
    "  },",
    string.format('  "context": %s', vim.json.encode(metadata.context)),
    "}",
    "",
  }

  local content = table.concat(lines, "\n") .. "\n" .. body
  if content:sub(-1) ~= "\n" then
    content = content .. "\n"
  end
  return content
end

function M.write(root, output_dir, metadata, body)
  local directory = vim.fs.joinpath(root, output_dir)
  local ok, dir_err = ensure_directory(directory)
  if not ok then
    return nil, string.format("Could not create output directory: %s", dir_err)
  end

  local created_at, time_err = timestamp()
  if not created_at then
    return nil, string.format("Could not generate filename: %s", time_err)
  end

  local content = M.render(metadata, body)
  for _ = 1, max_collision_retries do
    local suffix, random_err = random_hex()
    if not suffix then
      return nil, string.format("Could not generate filename: %s", random_err)
    end

    local path = vim.fs.joinpath(directory, string.format("%s-%s.md", created_at, suffix))
    local written, write_err, write_code = write_exclusive(path, content)
    if written then
      return path
    end
    if write_code ~= "EEXIST" then
      return nil, string.format("Could not write comment: %s", write_err)
    end
  end

  return nil, "Could not create a unique comment filename"
end

return M
