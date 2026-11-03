local M = {}

local active_job

local function decode_xml(value)
	return (value:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

local function attribute(tag, name)
	local value = tag:match(name .. '%s*=%s*"(.-)"') or tag:match(name .. "%s*=%s*'(.-)'")
	return value and decode_xml(value) or nil
end

local function option(xml, name)
	for tag in xml:gmatch("<option(.-)>") do
		if attribute(tag, "name") == name then
			return attribute(tag, "value") or ""
		end
	end
end

local function map_entries(section)
	local result = {}
	for tag in section:gmatch("<entry(.-)/?>") do
		local key = attribute(tag, "key")
		local value = attribute(tag, "value")
		if key and value then
			result[key] = value
		end
	end
	return result
end

local function replace_project_dir(path, root)
	if not path or path == "" then
		return nil
	end
	return path:gsub("%$PROJECT_DIR%$", root)
end

local function shell_words(value)
	local words = {}
	local current = {}
	local quote
	local escaped = false

	for i = 1, #value do
		local char = value:sub(i, i)
		if escaped then
			table.insert(current, char)
			escaped = false
		elseif char == "\\" and quote ~= "'" then
			escaped = true
		elseif quote then
			if char == quote then
				quote = nil
			else
				table.insert(current, char)
			end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char:match("%s") then
			if #current > 0 then
				table.insert(words, table.concat(current))
				current = {}
			end
		else
			table.insert(current, char)
		end
	end

	if escaped then
		table.insert(current, "\\")
	end
	if #current > 0 then
		table.insert(words, table.concat(current))
	end

	return words
end

local function quote_exec_arg(value)
	if value == "" then
		return '""'
	end
	if not value:find('[%s"]') then
		return value
	end
	return '"' .. value:gsub('([\\"])', "\\%1") .. '"'
end

local function project_root()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		path = vim.uv.cwd()
	end
	return vim.fs.root(path, { ".run", ".idea", ".git" }) or vim.fs.root(path, { "pom.xml" }) or vim.uv.cwd()
end

local function workspace_config_order(root)
	local path = root .. "/.idea/workspace.xml"
	if vim.fn.filereadable(path) ~= 1 then
		return {}
	end
	local xml = table.concat(vim.fn.readfile(path), "\n")
	local run_manager = xml:match('<component name="RunManager"(.-)</component>') or ""
	local order = {}
	for item in run_manager:gmatch('<item%s+itemvalue="(.-)"%s*/>') do
		local value = decode_xml(item)
		value = value:gsub("^[^.]+%.", "")
		order[value] = #vim.tbl_keys(order) + 1
	end
	return order
end

local function config_files(root)
	local result = {}
	for _, pattern in ipairs({
		root .. "/.idea/runConfigurations/*.xml",
		root .. "/.idea/runConfig/*.xml",
		root .. "/.run/*.run.xml",
	}) do
		vim.list_extend(result, vim.fn.glob(pattern, false, true))
	end
	-- Keep the filesystem/glob order. IntelliJ's .run XML files are presented
	-- in the order returned by the project configuration directory; do not
	-- apply an alphabetical or environment-based sort here.
	return result
end

local function read_config(path, root)
	local xml = table.concat(vim.fn.readfile(path), "\n")
	local configuration = xml:match("<configuration(.-)>")
	if not configuration then
		return nil
	end

	local config_type = attribute(configuration, "type") or "Application"
	local result = {
		file = path,
		name = attribute(configuration, "name") or vim.fn.fnamemodify(path, ":t:r"),
		type = config_type,
		main_class = option(xml, "MAIN_CLASS_NAME"),
		java = option(xml, "ALTERNATIVE_JRE_PATH"),
		group = attribute(configuration, "folderName"),
		vm_args = shell_words(option(xml, "VM_PARAMETERS") or ""),
		program_args = shell_words(option(xml, "PROGRAM_PARAMETERS") or ""),
		env = {},
	}

	for tag in xml:gmatch("<env(.-)/?>") do
		local name = attribute(tag, "name")
		local value = attribute(tag, "value")
		if name and value then
			result.env[name] = value
		end
	end

	if config_type == "ShConfigurationType" then
		result.kind = "shell"
		result.script = option(xml, "SCRIPT_TEXT") or ""
		result.script_path = replace_project_dir(option(xml, "SCRIPT_PATH"), root)
		result.cwd = replace_project_dir(option(xml, "SCRIPT_WORKING_DIRECTORY"), root) or root
		if result.script == "" and not result.script_path then
			return nil
		end
	elseif config_type == "MavenRunConfiguration" then
		result.kind = "maven"
		result.cwd = replace_project_dir(option(xml, "workingDirPath"), root) or root
		local goals_section = xml:match('<option name="goals">(.-)</option>') or ""
		result.maven_args = {}
		for tag in goals_section:gmatch("<option(.-)/?>") do
			local goal = attribute(tag, "value")
			if goal then
				table.insert(result.maven_args, goal)
			end
		end
		local runner_section = xml:match("<MavenRunnerSettings>(.-)</MavenRunnerSettings>") or ""
		local environment_section = runner_section:match('<option name="environmentProperties">(.-)</option>') or ""
		for name, value in pairs(map_entries(environment_section)) do
			result.env[name] = value
		end
		if option(runner_section, "skipTests") == "true" then
			table.insert(result.maven_args, "-DskipTests")
		end
		local cmd_options = option(xml, "cmdOptions")
		if cmd_options and cmd_options ~= "" then
			vim.list_extend(result.maven_args, shell_words(cmd_options))
		end
	elseif result.main_class then
		result.kind = "application"
	else
		result.kind = "other"
	end

	return result
end

local function find_java(identifier)
	if not identifier or identifier == "" then
		return vim.fn.exepath("java")
	end

	if vim.fn.executable("asdf") == 1 then
		local path = vim.fn.system({ "asdf", "where", "java", identifier }):gsub("%s+$", "")
		if vim.v.shell_error == 0 and vim.fn.executable(path .. "/bin/java") == 1 then
			return path .. "/bin/java"
		end
	end

	local version = identifier:match("(%d+)")
	if version and vim.fn.executable("/usr/libexec/java_home") == 1 then
		local path = vim.fn.system({ "/usr/libexec/java_home", "-v", version }):gsub("%s+$", "")
		if vim.v.shell_error == 0 and vim.fn.executable(path .. "/bin/java") == 1 then
			return path .. "/bin/java"
		end
	end

	return vim.fn.exepath("java")
end

local function environment(overrides)
	local result = vim.fn.environ()
	for name, value in pairs(overrides) do
		result[name] = value
	end
	return result
end

function M.stop()
	if active_job then
		vim.fn.jobstop(active_job)
		active_job = nil
	end
end

local function icon_for_group(group)
	if not group then
		return "󰖲"
	end
	if group == "LOCAL" then
		return "󰋜"
	elseif group:match("^INT") then
		return "󰅟"
	elseif group:match("^TEST") then
		return "󰦨"
	elseif group == "GEN" then
		return "󰐱"
	end
	return "󰖲"
end

local function folder_icon(is_open)
	return is_open and "󰝰" or "󰉋"
end

local run_config_icon = "󰖲"
local shell_icon = "󰆍"
local maven_icon = ""

local function prepare_configs(configs)
	for _, config in ipairs(configs) do
		-- IntelliJ stores run-configuration folders in the XML as folderName.
		-- Do not infer folders from configuration names.
		config.group_icon = icon_for_group(config.group)
		if config.kind == "shell" then
			config.icon = shell_icon
		elseif config.kind == "maven" then
			config.icon = maven_icon
		else
			config.icon = run_config_icon
		end
	end

end

local function maven_command(root)
	local configured = vim.env.MAVEN
	if configured and configured ~= "" then
		configured = vim.fn.expand(vim.fn.trim(configured))
		-- Accept an explicitly configured Maven invocation such as
		-- "~/tools/apache-maven-3.9.16/bin/mvn" without letting the shell or
		-- PATH replace it with another mvn executable.
		if configured:sub(1, 2) == "~/" then
			configured = vim.fn.expand(configured)
		end
		-- MAVEN is authoritative. Keep the configured command/path exactly as
		-- supplied; do not resolve it through PATH or fall back to another Maven.
		return configured
	end

	local wrapper = root .. "/mvnw"
	if vim.fn.executable(wrapper) == 1 then
		return wrapper
	end

	local system_maven = vim.fn.exepath("mvn")
	if system_maven ~= "" then
		return system_maven
	end
	return "mvn"
end

local function build_command(root, config)
	if config.kind == "other" then
		return { "echo", "Unsupported IntelliJ run configuration: " .. config.name }
	end

	if config.kind == "shell" then
		local maven = maven_command(root)
		local maven_override = "mvn() { " .. vim.fn.shellescape(maven) .. ' "$@"; }\n'
		if config.script_path and config.script_path ~= "" and config.script == "" then
			return { "sh", "-lc", maven_override .. vim.fn.shellescape(config.script_path) }
		end
		return { "sh", "-lc", maven_override .. config.script }
	end

	if config.kind == "maven" then
		return vim.list_extend({ maven_command(root) }, config.maven_args)
	end

	local exec_args = {}
	vim.list_extend(exec_args, config.vm_args)
	table.insert(exec_args, "-cp")
	table.insert(exec_args, "%classpath")
	table.insert(exec_args, config.main_class)
	vim.list_extend(exec_args, config.program_args)

	local command = {
		maven_command(root),
		"compile",
		"exec:exec",
		"-Dexec.executable=" .. find_java(config.java),
		"-Dexec.args=" .. table.concat(vim.tbl_map(quote_exec_arg, exec_args), " "),
	}

	if vim.fn.executable(command[1]) ~= 1 and command[1] ~= "mvn" then
		command[1] = "mvn"
	end
	return command
end

local function command_line(command)
	return table.concat(vim.tbl_map(vim.fn.shellescape, command), " ")
end

local function select_tree(configs, callback, root)
	local ok, pickers = pcall(require, "telescope.pickers")
	local finders_ok, finders = pcall(require, "telescope.finders")
	local sorters_ok, sorters = pcall(require, "telescope.sorters")
	local actions_ok, actions = pcall(require, "telescope.actions")
	local state_ok, action_state = pcall(require, "telescope.actions.state")
	local previewers_ok, previewers = pcall(require, "telescope.previewers")

	if not (ok and finders_ok and sorters_ok and actions_ok and state_ok and previewers_ok) then
		vim.ui.select(configs, {
			prompt = "Select SA3 run configuration:",
			format_item = function(config)
				return config.icon .. "  " .. config.name
			end,
		}, callback)
		return
	end

	local expanded = {}
	local groups = {}
	for _, config in ipairs(configs) do
		if config.group then
			groups[config.group] = groups[config.group] or {}
			table.insert(groups[config.group], config)
		end
	end

	local function preview_lines(value, root)
		local lines = {}
		if value.kind == "group" then
			table.insert(lines, folder_icon(expanded[value.group]) .. "  " .. value.group)
			table.insert(lines, "")
			table.insert(lines, "Configurations: " .. #value.configs)
			table.insert(lines, "")
			for _, config in ipairs(value.configs) do
				table.insert(lines, config.name)
			end
			return lines
		end

		local config = value.config
		table.insert(lines, config.icon .. "  " .. config.name)
		table.insert(lines, "")
		table.insert(lines, "Type")
		table.insert(lines, "  " .. config.kind)
		table.insert(lines, "")
		table.insert(lines, "Source")
		table.insert(lines, "  " .. config.file)
		table.insert(lines, "")
		table.insert(lines, "Working directory")
		table.insert(lines, "  " .. (config.cwd or root))
		table.insert(lines, "")
		if config.kind == "application" then
			table.insert(lines, "Main class")
			table.insert(lines, "  " .. config.main_class)
			table.insert(lines, "")
			table.insert(lines, "JDK")
			table.insert(lines, "  " .. (config.java or "default"))
			table.insert(lines, "")
			table.insert(lines, "VM parameters")
			if #config.vm_args == 0 then
				table.insert(lines, "  (none)")
			else
				for _, arg in ipairs(config.vm_args) do
					table.insert(lines, "  " .. arg)
				end
			end
			table.insert(lines, "")
			table.insert(lines, "Program parameters")
			if #config.program_args == 0 then
				table.insert(lines, "  (none)")
			else
				for _, arg in ipairs(config.program_args) do
					table.insert(lines, "  " .. arg)
				end
			end
		elseif config.kind == "maven" then
			table.insert(lines, "Maven goals")
			for _, arg in ipairs(config.maven_args) do
				table.insert(lines, "  " .. arg)
			end
		elseif config.kind == "shell" then
			table.insert(lines, "Shell script")
			table.insert(lines, "  " .. (config.script_path or "inline script"))
			if config.script ~= "" then
				table.insert(lines, "")
				vim.list_extend(lines, vim.split(config.script:gsub("\r\n", "\n"), "\n", { plain = true }))
			end
		end
		table.insert(lines, "")
		table.insert(lines, "Environment")
		local env_names = {}
		for name in pairs(config.env) do
			table.insert(env_names, name)
		end
		table.sort(env_names)
		if #env_names == 0 then
			table.insert(lines, "  (none)")
		else
			for _, name in ipairs(env_names) do
				table.insert(lines, "  " .. name .. "=" .. config.env[name])
			end
		end
		table.insert(lines, "")
		table.insert(lines, "Command")
		if config.kind == "other" then
			table.insert(lines, "  (not supported by the run-only launcher)")
		else
			vim.list_extend(
				lines,
				vim.split("  " .. command_line(build_command(root, config)):gsub("\r\n", "\n"), "\n", { plain = true })
			)
		end
		return lines
	end

	local function matches(text, prompt)
		return prompt == "" or text:lower():find(prompt:lower(), 1, true) ~= nil
	end

	local function visible_entries(prompt)
		local matching_groups = {}
		local entries = {}
		local added_groups = {}

		for group, group_configs in pairs(groups) do
			if matches(group, prompt) then
				matching_groups[group] = true
			else
				for _, config in ipairs(group_configs) do
					if matches(config.name, prompt) then
						matching_groups[group] = true
						break
					end
				end
			end
		end

		for _, config in ipairs(configs) do
			if not config.group then
				if matches(config.name, prompt) then
					table.insert(entries, {
						kind = "config",
						config = config,
						ordinal = config.name,
						display = config.icon .. "  " .. config.name,
					})
				end
			else
				if not added_groups[config.group] then
					added_groups[config.group] = true
					local group_names = {}
					for _, group_config in ipairs(groups[config.group]) do
						table.insert(group_names, group_config.name)
					end
					table.insert(entries, {
						kind = "group",
						group = config.group,
						configs = groups[config.group],
						ordinal = config.group .. " " .. table.concat(group_names, " "),
						display = folder_icon(expanded[config.group]) .. "  " .. config.group,
					})
				end
				local show_children = expanded[config.group] or (prompt ~= "" and matching_groups[config.group])
				if show_children and matches(config.name, prompt) then
					table.insert(entries, {
						kind = "config",
						config = config,
						ordinal = config.group .. " " .. config.name,
						display = "    " .. config.icon .. "  " .. config.name,
					})
				end
			end
		end
		return entries
	end

	local finder = finders.new_dynamic({
		fn = visible_entries,
		entry_maker = function(entry)
			return {
				value = entry,
				ordinal = entry.ordinal,
				display = entry.display,
			}
		end,
	})

	local picker = pickers.new({}, {
		prompt_title = "SA3 Run Configurations",
		finder = finder,
		sorter = sorters.get_generic_fuzzy_sorter({}),
		layout_strategy = "horizontal",
		layout_config = {
			width = 0.9,
			height = 0.8,
			preview_cutoff = 0,
			horizontal = {
				prompt_position = "top",
				preview_width = 0.45,
			},
		},
		previewer = previewers.new_buffer_previewer({
			title = "Run Configuration Preview",
			define_preview = function(self, entry)
				local lines = preview_lines(entry.value, root)
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				vim.bo[self.state.bufnr].filetype = "sa3run"
			end,
		}),
		attach_mappings = function(prompt_bufnr, map)
			local current_picker = action_state.get_current_picker(prompt_bufnr)
			current_picker:register_completion_callback(function(picker)
				local group_to_restore = picker._sa3_group_to_restore
				if not group_to_restore then
					return
				end

				for row = 0, picker.manager:num_results() - 1 do
					local entry = picker.manager:get_entry(picker:get_index(row))
					if entry and entry.value.kind == "group" and entry.value.group == group_to_restore then
						picker:set_selection(row)
						picker._sa3_group_to_restore = nil
						return
					end
				end
			end)

			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				if not selection then
					return
				end

				if selection.value.kind == "group" then
					local group = selection.value.group
					expanded[group] = not expanded[group]
					current_picker._sa3_group_to_restore = group
					current_picker:refresh(current_picker.finder, { reset_prompt = false })
					return
				end

				actions.close(prompt_bufnr)
				callback(selection.value.config)
			end)

			local function edit_config()
				local selection = action_state.get_selected_entry()
				if not selection or selection.value.kind ~= "config" then
					vim.notify("Select a run configuration to edit", vim.log.levels.INFO)
					return
				end
				actions.close(prompt_bufnr)
				vim.cmd("edit " .. vim.fn.fnameescape(selection.value.config.file))
			end

			local function yank_command()
				local selection = action_state.get_selected_entry()
				if not selection or selection.value.kind ~= "config" then
					vim.notify("Select a run configuration to copy its command", vim.log.levels.INFO)
					return
				end
				local command = command_line(build_command(root, selection.value.config))
				vim.fn.setreg("+", command)
				vim.notify("Run command copied to clipboard")
			end

			map("i", "<C-e>", edit_config)
			map("n", "<C-e>", edit_config)
			map("i", "<C-y>", yank_command)
			map("n", "<C-y>", yank_command)
			return true
		end,
	})

	picker:find()
end

function M.internal()
	return {
		project_root = project_root,
		config_files = config_files,
		read_config = read_config,
		prepare_configs = prepare_configs,
		select_tree = select_tree,
		build_command = build_command,
		environment = environment,
		start_terminal = function(config, command, root, title)
			M.stop()
			local terminal = require("snacks.terminal")
			local command_text = command_line(command)
			local terminal_instance = terminal.open(command_text, {
				cwd = config.cwd or root,
				env = environment(config.env),
				title = title or ("SA3 Run: " .. config.name),
				auto_close = false,
				win = {
					position = "bottom",
					height = 15,
				},
			})
			vim.schedule(function()
				if terminal_instance and terminal_instance.win and vim.api.nvim_win_is_valid(terminal_instance.win) then
					vim.api.nvim_set_current_win(terminal_instance.win)
					vim.cmd("startinsert")
				end
			end)
			active_job = terminal_instance and terminal_instance.job_id or nil
			return active_job
		end,
	}
end

function M.run()
	local root = project_root()
	local configs = {}
	for _, path in ipairs(config_files(root)) do
		local config = read_config(path, root)
		if config then
			table.insert(configs, config)
		end
	end

	if #configs == 0 then
		vim.notify("No IntelliJ run configuration found in " .. root, vim.log.levels.WARN)
		return
	end

	prepare_configs(configs)

	select_tree(configs, function(config)
		if not config then
			return
		end
		if config.kind == "other" then
			vim.notify("This run configuration type is not supported yet", vim.log.levels.WARN)
			return
		end

		local command = build_command(root, config)

		M.internal().start_terminal(config, command, root, "SA3 Run: " .. config.name)
	end, root)
end

return M
