vim.api.nvim_create_user_command('CopyRelativePath', function()
  local path = vim.fn.expand('%')
  vim.fn.setreg('+', path)
  vim.notify('Copied "' .. path .. '"')
end, {})

vim.api.nvim_create_user_command('CopyAbsolutePath', function()
  local path = vim.fn.expand('%:p')
  vim.fn.setreg('+', path)
  vim.notify('Copied "' .. path .. '"')
end, {})

vim.api.nvim_create_user_command('Sa3Run', function()
  require('sa3-runner').run()
end, {})

vim.api.nvim_create_user_command('Sa3Stop', function()
  require('sa3-runner').stop()
end, {})
