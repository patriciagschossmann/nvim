local M = {}

local dap = require("dap")

local function debug_command(command)
  local exec_args, exec_index

  for index, value in ipairs(command) do
    if value:match("^%-Dexec%.args=") then
      exec_index = index
      exec_args = value:sub(#"-Dexec.args=" + 1)
      break
    end
  end

  if not exec_args then
    return command
  end

  local classpath = exec_args:find(" %-cp ") or exec_args:find(" %-classpath ")
  local debug_args
  if classpath then
    debug_args = exec_args:sub(1, classpath - 1)
      .. " -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
      .. exec_args:sub(classpath)
  else
    debug_args = "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005 " .. exec_args
  end

  local rebuilt = {}
  for index, value in ipairs(command) do
    if index == exec_index then
      table.insert(rebuilt, "-Dexec.args=" .. debug_args)
    else
      table.insert(rebuilt, value)
    end
  end
  return rebuilt
end

local function wait_for_debug_port(host, port, callback, attempts)
  attempts = attempts or 120
  local socket = vim.uv.new_tcp()
  socket:connect(host, port, function(error)
    socket:close()
    if not error then
      vim.schedule(callback)
      return
    end
    if attempts <= 1 then
      vim.schedule(function()
        vim.notify("Java debug port " .. port .. " did not open", vim.log.levels.ERROR)
      end)
      return
    end
    vim.defer_fn(function()
      wait_for_debug_port(host, port, callback, attempts - 1)
    end, 250)
  end)
end

local function open_terminal(config, command, root)
  local runner = require("run-configs")
  return runner.internal().start_terminal(config, command, root, "SA3 Debug: " .. config.name)
end


function M.debug()
  local runner = require("run-configs")
  local internal = runner.internal()
  local root = internal.project_root()
  local configs = {}

  for _, path in ipairs(internal.config_files(root)) do
    local config = internal.read_config(path, root)
    if config then
      table.insert(configs, config)
    end
  end

  if #configs == 0 then
    vim.notify("No IntelliJ run configuration found in " .. root, vim.log.levels.WARN)
    return
  end

  internal.prepare_configs(configs)
  internal.select_tree(configs, function(config)
    if not config or config.kind == "other" then
      vim.notify("This run configuration type is not supported for debugging", vim.log.levels.WARN)
      return
    end

    if config.kind ~= "application" then
      vim.notify("Only Java application run configurations support SA3 debugging", vim.log.levels.WARN)
      return
    end

    local command = debug_command(internal.build_command(root, config))
    vim.notify("Starting debug configuration on port 5005")
    open_terminal(config, command, root)

    wait_for_debug_port("127.0.0.1", 5005, function()
      dap.run({
        type = "java",
        request = "attach",
        name = "Attach to remote JVM (5005)",
        hostName = "127.0.0.1",
        port = 5005,
      }, { filetype = "java" })
      vim.schedule(function()
        require("dap-view").open()
      end)
    end)
  end, root)
end

return M
