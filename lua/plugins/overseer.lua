local function project_root()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		path = vim.uv.cwd()
	end
	return vim.fs.root(path, { "pom.xml" }) or vim.uv.cwd()
end

local function maven_command(root)
	local configured = vim.env.MAVEN
	if configured and configured ~= "" then
		configured = vim.fn.expand(configured)
		if vim.fn.executable(configured) == 1 then
			return configured
		end
	end

	local wrapper = root .. "/mvnw"
	if vim.fn.executable(wrapper) == 1 then
		return wrapper
	end

	return vim.fn.exepath("mvn") ~= "" and vim.fn.exepath("mvn") or "mvn"
end

local function maven_template(overseer, name, args)
	overseer.register_template({
		name = name,
		tags = { overseer.TAG.BUILD },
		builder = function()
			local root = project_root()
			return {
				cmd = { maven_command(root) },
				args = args,
				cwd = root,
				components = {
					"default",
					{ "open_output", direction = "dock", on_start = "always", focus = false },
				},
			}
		end,
	})
end

local maven_icon = ""

return {
	"stevearc/overseer.nvim",
	cmd = { "OverseerRun", "OverseerToggle", "OverseerTaskAction" },
	keys = {
		{ "<leader>otr", "<CMD>OverseerRun<CR>", desc = "Overseer task run" },
		{ "<leader>ota", "<CMD>OverseerTaskAction<CR>", desc = "Overseer task action" },
		{ "<leader>to", "<CMD>OverseerToggle<CR>", desc = "Toggle Overseer" },
	},
	opts = {
		output = {
			use_terminal = true,
			preserve_output = true,
		},
		task_list = {
			direction = "bottom",
		},
	},
	config = function(_, opts)
		local overseer = require("overseer")
		overseer.setup(opts)

		maven_template(overseer, maven_icon .. " Maven: clean", { "clean" })
		maven_template(overseer, maven_icon .. " Maven: compile", { "compile" })
		maven_template(overseer, maven_icon .. " Maven: test", { "test" })
		maven_template(overseer, maven_icon .. " Maven: package", { "package" })
		maven_template(overseer, maven_icon .. " Maven: install", { "install" })
		maven_template(overseer, maven_icon .. " Maven: clean install", { "clean", "install" })
		maven_template(overseer, maven_icon .. " Maven: clean install (skip tests)", {
			"clean",
			"install",
			"-DskipTests",
		})
		maven_template(overseer, maven_icon .. " Maven: verify", { "verify" })
	end,
}
