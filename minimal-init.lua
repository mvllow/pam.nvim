--- minimal-init.lua
---
---@usage
--- nvim -u minimal-init.lua

vim.opt.rtp:prepend(".")

require("pam").manage({
	{ source = "echasnovski/mini.doc" },
})

-- Generate documentation
vim.cmd("luafile scripts/minidoc.lua")
