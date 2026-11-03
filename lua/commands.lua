vim.api.nvim_create_user_command("CopyRelativePath", function()
	local path = vim.fn.expand("%")
	vim.fn.setreg("+", path)
	vim.notify('Copied "' .. path .. '"')
end, {})

vim.api.nvim_create_user_command("CopyAbsolutePath", function()
	local path = vim.fn.expand("%:p")
	vim.fn.setreg("+", path)
	vim.notify('Copied "' .. path .. '"')
end, {})

vim.api.nvim_create_user_command("ConfigRun", function()
	require("run-configs").run()
end, {})

vim.api.nvim_create_user_command("ConfigDebug", function()
	require("debug-configs").debug()
end, {})
