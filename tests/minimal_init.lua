vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.cmd("runtime plugin/draft-comments.lua")
