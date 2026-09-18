-- spring boot language server (bean/endpoint navigation, application.properties & yml completion)
return {
  'JavaHello/spring-boot.nvim',
  dependencies = { 'mfussenegger/nvim-jdtls' },
  ft = { 'java', 'yaml', 'jproperties' },
  keys = {
    {
      '<leader>jsb',
      function()
        require('telescope.builtin').lsp_dynamic_workspace_symbols({
          initial_mode = 'insert',
          default_text = '@+ ',
        })
      end,
      desc = 'Java Spring Find beans',
    },
    {
      '<leader>jse',
      function()
        require('telescope.builtin').lsp_dynamic_workspace_symbols({
          initial_mode = 'insert',
          default_text = '@/ ',
        })
      end,
      desc = 'Java Spring Find endpoints',
    },
  },
  opts = function()
    local java_home = vim.fn.executable('/usr/libexec/java_home') == 1
        and vim.trim(vim.fn.system({ '/usr/libexec/java_home', '-v', '21' }))
      or nil

    return {
      java_cmd = (java_home and vim.v.shell_error == 0) and java_home .. '/bin/java' or nil,
      project_filter = function(root_dir)
        return require('spring_boot.util').has_spring_boot_dependency(root_dir)
      end,
    }
  end,
  config = function(_, opts)
    require('spring_boot').setup(opts)
  end,
  -- config = function(_, opts)
  --   -- returns the resolved opts (ls_path filled in from mason or vscode), or nil
  --   -- when the language server could not be found
  --   local resolved = require('spring_boot').setup(opts)
  --   if not resolved then
  --     return
  --   end

  --   local launch = require('spring_boot.launch')
  --   local function start()
  --     -- rebuild per buffer, update_ls_config derives root_dir from the current one
  --     local config = launch.update_ls_config(resolved)
  --     -- jdtls owns java inlay hints. vim.lsp.inlay_hint keeps hints per client
  --     -- but only one version stamp for the whole buffer, so the slower server's
  --     -- positions end up drawn against a newer buffer and the decoration
  --     -- provider dies with "Invalid 'col': out of range"
  --     config.handlers = vim.tbl_extend('force', config.handlers or {}, {
  --       ['textDocument/inlayHint'] = function() end,
  --     })
  --     launch.start(config)
  --   end

  --   vim.api.nvim_create_autocmd('FileType', {
  --     group = vim.api.nvim_create_augroup('SpringBoot', { clear = true }),
  --     pattern = { 'java', 'yaml', 'jproperties' },
  --     callback = start,
  --   })

  --   start()
  -- end,
}
