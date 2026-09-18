-- return {
--   {
--     'tpope/vim-dadbod',
--     lazy = true,
--     ft = 'lua',
--   },
--   {
--     'kristijanhusak/vim-dadbod-ui',
--     dependencies = {
--       { 'tpope/vim-dadbod', lazy = true },
--       {
--         'kristijanhusak/vim-dadbod-completion',
--         ft = { 'sql', 'mysql', 'plsql' },
--         lazy = true,
--       },
--     },
--     cmd = {
--       'DBUI',
--       'DBUIToggle',
--       'DBUIAddConnection',
--       'DBUIFindBuffer',
--     },
--     keys = {
--       { '<leader>odt', '<CMD>DBUIToggle<CR>', desc = 'Database Toggle UI' },
--       { '<leader>oda', '<CMD>DBUIAddConnection<CR>', desc = 'Database Add connection' },
--       { '<leader>odf', '<CMD>DBUIFindBuffer<CR>', desc = 'Database Find buffer' },
--     },
--     init = function()
--       vim.g.db_ui_use_nerd_fonts = 1
--       vim.g.db_ui_auto_execute_table_helpers = 0
--       vim.g.db_ui_execute_on_save = 0
--       vim.g.db_ui_save_location = vim.fn.stdpath('data') .. '/db_ui_queries'
--     end,
--   },
-- }
return {
  {
    'kopecmaciej/vi-sql.nvim',
    cmd = { 'ViSQL', 'ViSQLJump' },
    keys = {
      { '<leader>tD', '<CMD>ViSQL<CR>', desc = 'Toggle vi-sql' },
      {
        '<leader>Dj',
        ':ViSQLJump ',
        desc = 'vi-sql: jump to table',
        silent = false,
      },
    },
    config = function()
      require('vi-sql').setup({
        hide_key = '<C-q>',
        width = 0.9,
        height = 0.9,
      })
    end,
  },
}
