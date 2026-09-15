local M = {}

function M.label(source_path, start_line, end_line)
  local range = tostring(start_line)
  if start_line ~= end_line then
    range = string.format("%d-%d", start_line, end_line)
  end
  return string.format(" %s:%s ", vim.fs.basename(source_path), range)
end

function M.geometry(opts)
  local win_width = vim.api.nvim_win_get_width(opts.source_win)
  local win_height = vim.api.nvim_win_get_height(opts.source_win)
  local bordered = win_width >= 3 and win_height >= 3
  local border_rows = bordered and 2 or 0
  local border_columns = bordered and 2 or 0
  local width = math.max(1, win_width - border_columns)

  local win_position = vim.fn.win_screenpos(opts.source_win)
  local start_position = vim.fn.screenpos(opts.source_win, opts.start_line, 1)
  local end_position = vim.fn.screenpos(opts.source_win, opts.end_line, 1)
  local start_row = start_position.row > 0 and start_position.row - win_position[1] or 0
  local end_row = end_position.row > 0 and end_position.row - win_position[1] or start_row
  local above = math.max(0, start_row)
  local below = math.max(0, win_height - end_row - 1)

  local place_below = below >= above
  local available = place_below and below or above
  if available <= border_rows then
    available = win_height
    place_below = true
    end_row = -1
  end

  local height = math.max(1, math.min(opts.max_height, available - border_rows))
  local row
  if place_below then
    row = end_row + 1
  else
    row = math.max(0, start_row - height - border_rows)
  end

  local geometry = {
    relative = "win",
    win = opts.source_win,
    row = row,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    zindex = 60,
  }

  if bordered then
    geometry.border = "rounded"
    if place_below then
      geometry.title = opts.label
      geometry.title_pos = "center"
    else
      geometry.footer = opts.label
      geometry.footer_pos = "center"
    end
  end

  return geometry
end

return M
