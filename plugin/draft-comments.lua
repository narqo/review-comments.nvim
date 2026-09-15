if vim.g.loaded_draft_comments == 1 then
  return
end
vim.g.loaded_draft_comments = 1

vim.api.nvim_create_user_command("DraftComment", function(args)
  require("draft-comments").draft({
    start_line = args.line1,
    end_line = args.line2,
  })
end, {
  desc = "Draft a comment for the selected lines",
  range = true,
})

vim.api.nvim_create_user_command("DraftCommentsRefresh", function()
  require("draft-comments").refresh()
end, {
  desc = "Reload draft comments from disk",
})

vim.api.nvim_create_user_command("DraftCommentView", function()
  require("draft-comments").view()
end, {
  desc = "View draft comments covering the cursor line",
})

local group = vim.api.nvim_create_augroup("DraftCommentsLoad", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function(args)
    require("draft-comments")._on_buf_enter(args.buf)
  end,
})
vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = function()
    require("draft-comments")._on_buf_enter(vim.api.nvim_get_current_buf())
  end,
})
