local filetypes = { 'java' }
local connection_id = 'sonarqube'
local keychain_account = 'nvim-sonarlint'
local token_cache = {}

local function normalize_url(url)
  if type(url) ~= 'string' then
    return ''
  end
  return url:gsub('/+$', '')
end

local function read_project_config(root_dir)
  local path = vim.fs.joinpath(root_dir, '.sonarlint', 'connectedMode.json')
  if vim.fn.filereadable(path) == 0 then
    return
  end

  local ok, project = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
  if
    not ok
    or type(project) ~= 'table'
    or type(project.sonarQubeUri) ~= 'string'
    or type(project.projectKey) ~= 'string'
  then
    vim.notify_once('Invalid SonarLint config: ' .. path, vim.log.levels.WARN)
    return
  end

  project.sonarQubeUri = normalize_url(project.sonarQubeUri)
  return project
end

local function get_keychain_token(_, url)
  local service = normalize_url(url)
  if service == '' then
    return vim.NIL
  end

  if token_cache[service] then
    return token_cache[service]
  end

  local result = vim
    .system({
      '/usr/bin/security',
      'find-generic-password',
      '-a',
      keychain_account,
      '-s',
      service,
      '-w',
    }, { text = true })
    :wait()

  local token = vim.trim(result.stdout or '')
  if result.code ~= 0 or token == '' then
    vim.notify_once('Could not read Keychain item for: ' .. service, vim.log.levels.WARN)
    return vim.NIL
  end

  token_cache[service] = token
  return token
end

return {
  {
    name = 'sonarlint',
    url = 'https://gitlab.com/schrieveslaach/sonarlint.nvim',
    dependencies = { 'mason-org/mason.nvim' },
    ft = filetypes,

    opts = function()
      local mason = assert(vim.env.MASON, 'mason.nvim is not configured')
      local analyzers = vim.fs.joinpath(mason, 'share', 'sonarlint-analyzers')

      return {
        filetypes = filetypes,
        connected = { get_credentials = get_keychain_token },

        server = {
          cmd = {
            'sonarlint-language-server',
            '-stdio',
            '-analyzers',
            vim.fs.joinpath(analyzers, 'sonarjava.jar'),
            vim.fs.joinpath(analyzers, 'sonarjavasymbolicexecution.jar'),
          },

          before_init = function(_, config)
            local project = config.root_dir and read_project_config(config.root_dir)
            if not project then
              return
            end

            config.settings = vim.tbl_deep_extend('force', config.settings or {}, {
              sonarlint = {
                connectedMode = {
                  connections = {
                    sonarqube = {
                      {
                        connectionId = connection_id,
                        serverUrl = project.sonarQubeUri,
                      },
                    },
                  },
                  project = {
                    connectionId = connection_id,
                    projectKey = project.projectKey,
                  },
                },
              },
            })
          end,
        },
      }
    end,
  },
}
