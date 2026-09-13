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

function M.render(metadata, body)
  local lines = {
    "```json",
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
    "```",
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
