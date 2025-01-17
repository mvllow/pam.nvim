--- *pam.nvim* The package manager for Neovim
--- *Pam*
---
--- MIT License Copyright (c) mvllow
---
--- ==============================================================================
---
--- Features:
---
--- - Install and manage packages
--- - Support for URLs and local paths
--- - Prefer builtins over abstractions
---
--- # Setup ~
---
--- Clone pam.nvim
--- >sh
---   git clone https://github.com/mvllow/pam.nvim \
---   	~/.local/share/nvim/site/pack/pam/start/pam.nvim
--- <
---
--- Manage packages via |Pam.manage()|

---@class Config
---@field install_path string
---@private

---@class Package
---@field source string
---@field as? string
---@field branch? string
---@field dependencies? Package[]
---@field post_checkout? function
---@field config? function
---@private

local Pam = {}
local utilities = require("pam.utilities")

---@type Package[]
---@private
Pam.packages = {}

---@type Config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
Pam.config = {
	install_path = vim.fn.stdpath("data") .. "/site/pack/pam/start",
}
--minidoc_afterlines_end

---@private
local function refresh_help_tags()
	vim.cmd("helptags ALL")
end

---@param packages Package[]
---@param config? Config
---
---@usage >lua
---   require("pam").manage({
---   	{ source = "mvllow/pam.nvim" },
---   	{
---   		source = "nvim-treesitter/nvim-treesitter",
---   		post_checkout = function()
---   			vim.cmd("TSUpdate")
---   		end,
---   		config = function()
---   			require("nvim-treesitter.configs").setup()
---   		end
---   	},
---   	{
---   		source = "ThePrimeagen/harpoon",
---   		as = "baboon",
---   		branch = "harpoon2",
---   		dependencies = {
---   			{ source = "nvim-lua/plenary.nvim" }
---   		}
---   	}
---   })
--- <
function Pam.manage(packages, config)
	Pam.packages = packages or {}
	Pam.config = vim.tbl_extend("force", Pam.config, config or {})

	for _, package in ipairs(Pam.packages) do
		if type(package.config) == "function" then
			pcall(package.config)
		end
	end
end

---@param packages Package[]
---
---@usage :Pam install
function Pam.install(packages)
	local home_dir = vim.fn.expand("$HOME")

	---@param package Package
	local function install_package(package)
		if not utilities.validate_package_spec(package) then
			return
		end

		local package_path = package.source:gsub("^~", home_dir)
		local package_name = package.as or utilities.get_package_name(package_path)
		local install_path = Pam.config.install_path .. "/" .. package_name

		if not vim.uv.fs_stat(install_path) then
			local repo_path = package.source:find("^http") and package.source or "https://github.com/" .. package.source
			local git_args = { "clone", "--depth=1", "--filter=blob:none", "--single-branch", repo_path, install_path }
			if package.branch then
				table.insert(git_args, "--branch=" .. package.branch)
			end

			local handle
			---@diagnostic disable-next-line: missing-fields
			handle = vim.uv.spawn("git", { args = git_args }, function(code)
				handle:close()

				vim.schedule(function()
					if code == 0 then
						utilities.notify(("Installing %s (%s)"):format(package_name, package.source))
						if type(package.post_checkout) == "function" then
							utilities.notify(("└─ Running post checkout"):format(package_name, package.source))
							package.post_checkout()
						end
					else
						utilities.notify(("Failed to install '%s'"):format(package_name), vim.log.levels.ERROR)
					end
				end)
			end)
		else
			utilities.notify(package_name .. " is already installed.")
		end
	end

	for _, package in ipairs(packages) do
		install_package(package)

		if package.dependencies and #package.dependencies > 0 then
			for _, dependency in ipairs(package.dependencies) do
				install_package(dependency)
			end
		end
	end

	refresh_help_tags()
end

---@param packages Package[]
---
---@usage :Pam upgrade
function Pam.upgrade(packages)
	local home_dir = vim.fn.expand("$HOME")

	---@param package Package
	local function upgrade_package(package)
		if not utilities.validate_package_spec(package) then
			return
		end

		local package_path = package.source:gsub("^~", home_dir)
		local package_name = package.as or utilities.get_package_name(package_path)
		local install_path = Pam.config.install_path .. "/" .. package_name
		local stdout_output = {}

		if vim.uv.fs_stat(install_path) then
			local stdout = vim.uv.new_pipe(false)
			local handle
			---@diagnostic disable-next-line: missing-fields
			handle = vim.uv.spawn("git", { args = { "-C", install_path, "pull" }, stdio = { nil, stdout, nil } },
				function(code)
					if not stdout then
						return
					end

					stdout:close()
					handle:close()

					vim.schedule(function()
						if code == 0 then
							local output = table.concat(stdout_output, "")
							if not output:find("Already up to date.") then
								utilities.notify("Upgrading " .. package_name .. " (" .. package.source .. ")")

								if type(package.post_checkout) == "function" then
									utilities.notify("Running post checkout for " .. package_name)
									package.post_checkout()
								end
							else
								utilities.notify(package_name .. " is already up to date.")
							end
						else
							utilities.notify("Failed to upgrade '" .. package_name .. "'", vim.log.levels.ERROR)
						end
					end)
				end)

			if not stdout then
				return
			end

			vim.uv.read_start(stdout, function(err, data)
				assert(not err, err)
				if data then
					table.insert(stdout_output, data)
				end
			end)
		end
	end

	for _, package in ipairs(packages) do
		upgrade_package(package)

		if package.dependencies and #package.dependencies > 0 then
			for _, dependency in ipairs(package.dependencies) do
				upgrade_package(dependency)
			end
		end
	end

	refresh_help_tags()
end

---@param packages Package[]
---
---@usage :Pam clean
function Pam.clean(packages)
	local managed_packages = {}

	---@param package Package
	local function add_managed_package(package)
		if not utilities.validate_package_spec(package) then
			return false
		end

		local package_name = package.as or utilities.get_package_name(package.source)
		managed_packages[package_name] = true
	end

	for _, package in ipairs(packages) do
		add_managed_package(package)

		if package.dependencies and #package.dependencies > 0 then
			for _, dependency in ipairs(package.dependencies) do
				add_managed_package(dependency)
			end
		end
	end

	local directories = vim.fn.readdir(Pam.config.install_path)
	local paths_to_remove = {}

	for _, directory in ipairs(directories) do
		if not managed_packages[directory] then
			table.insert(paths_to_remove, Pam.config.install_path .. "/" .. directory)
		end
	end

	if #paths_to_remove == 0 then
		utilities.notify("No packages to remove")
		return
	end

	local confirm_message = ("(pam) Unused packages:\n(pam) - %s\n(pam) Remove unused packages? [y/N]: "):format(table
		.concat(
			paths_to_remove,
			"\n"))

	if vim.fn.input(confirm_message):lower() == "y" then
		for _, path in ipairs(paths_to_remove) do
			vim.fn.delete(path, "rf")
			utilities.notify("Removed" .. path)
		end

		refresh_help_tags()
	else
		vim.print("\n(pam) Clean cancelled")
	end
end

---@usage :Pam list
function Pam.list()
	vim.cmd("checkhealth pam")
end

vim.api.nvim_create_user_command("Pam", function(opts)
	local subcommand = opts.fargs[1]
	if subcommand == "install" then
		Pam.install(Pam.packages)
	elseif subcommand == "upgrade" or subcommand == "update" then
		Pam.upgrade(Pam.packages)
	elseif subcommand == "clean" then
		Pam.clean(Pam.packages)
	elseif subcommand == "list" or subcommand == "status" then
		Pam.list()
	else
		utilities.notify("Invalid subcommand: " .. subcommand)
	end
end, {
	nargs = "+",
	complete = function()
		return { "install", "upgrade", "clean", "list" }
	end,
})

return Pam
