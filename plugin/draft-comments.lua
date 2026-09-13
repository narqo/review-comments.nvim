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
