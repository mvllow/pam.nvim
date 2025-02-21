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

---@param msg string
---@param level? integer
---@private
local function notify(msg, level)
	level = level or vim.log.levels.INFO
	vim.notify("(pam) " .. msg, level)
end

---@param package Package
---@private
function Pam._validate_package_spec(package)
	if type(package) ~= "table" or not package.source or type(package.source) ~= "string" then
		return false
	end
	return true
end

---@param source string
---@private
function Pam._get_package_name(source)
	return source:match(".*/(.*)")
end

---@param packages Package[]
---@param fn function
---@private
local function process_with_deps(packages, fn)
	for _, package in ipairs(packages) do
		fn(package)

		if package.dependencies and #package.dependencies > 0 then
			process_with_deps(package.dependencies, fn)
		end
	end
end

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
		if not Pam._validate_package_spec(package) then
			return
		end

		local package_path = package.source:gsub("^~", home_dir)
		local package_name = package.as or Pam._get_package_name(package_path)
		local install_path = Pam.config.install_path .. "/" .. package_name

		if vim.uv.fs_stat(install_path) then
			notify(package_name .. " is already installed.")
			return
		end

		local repo_path = package.source:find("^http") and package.source or "https://github.com/" .. package.source
		local git_args = { "clone", "--depth=1", "--filter=blob:none", "--single-branch", repo_path, install_path }
		if package.branch then
			table.insert(git_args, "--branch=" .. package.branch)
		end

		local handle
		handle = vim.uv.spawn("git", { args = git_args }, function(code)
			handle:close()

			vim.schedule(function()
				if code == 0 then
					notify(("Installing %s (%s)"):format(package_name, package.source))
					if type(package.post_checkout) == "function" then
						notify(("└─ Running post checkout"):format(package_name, package.source))
						package.post_checkout()
					end
				else
					notify(("Failed to install '%s'"):format(package_name), vim.log.levels.ERROR)
				end
			end)
		end)
	end

	process_with_deps(packages, install_package)
	refresh_help_tags()
end

---@param packages Package[]
---
---@usage :Pam upgrade
function Pam.upgrade(packages)
	local home_dir = vim.fn.expand("$HOME")

	---@param package Package
	local function upgrade_package(package)
		if not Pam._validate_package_spec(package) then
			return
		end

		local package_path = package.source:gsub("^~", home_dir)
		local package_name = package.as or Pam._get_package_name(package_path)
		local install_path = Pam.config.install_path .. "/" .. package_name

		if not vim.uv.fs_stat(install_path) then
			return
		end

		local output = {}
		local stdout
		local handle
		---@diagnostic disable-next-line: missing-fields
		handle = vim.uv.spawn("git", {
			args = { "-C", install_path, "pull" },
			stdio = { nil, stdout, nil }

		}, function(code)
			handle:close()

			if not stdout then
				return
			end

			stdout:close()

			if code == 0 and not table.concat(output):find("Already up to date") then
				notify(("Upgrading %s (%s)"):format(package_name, package.source))
				if type(package.post_checkout) == "function" then
					notify(("└─ Running post checkout"):format(package_name, package.source))
					package.post_checkout()
				end
			else
				notify(("Failed to upgrade '%s'"):format(package_name), vim.log.levels.ERROR)
			end
		end)

		vim.uv.read_start(stdout, function(err, data)
			assert(not err, err)
			if data then
				table.insert(output, data)
			end
		end)
	end

	process_with_deps(packages, upgrade_package)
	refresh_help_tags()
end

---@param packages Package[]
---
---@usage :Pam clean
function Pam.clean(packages)
	local managed = {}

	process_with_deps(packages, function(package)
		if Pam._validate_package_spec then
			managed[package.as or Pam._get_package_name(package.source)] = true
		end
	end)

	local to_remove = vim.tbl_filter(function(dir)
		return not managed[dir]
	end, vim.fn.readdir(Pam.config.install_path))

	if #to_remove == 0 then
		notify("No packages to remove")
		return
	end

	local confirm_message = ("(pam) Unused packages:\n(pam) - %s\n(pam) Remove unused packages? [y/N]: "):format(table
		.concat(
			to_remove,
			"\n"))

	if vim.fn.input(confirm_message):lower() ~= "y" then
		vim.print("\n(pam) Clean cancelled")
		return
	end

	for _, path in ipairs(to_remove) do
		vim.fn.delete(path, "rf")
		notify("Removed" .. path)
	end

	refresh_help_tags()
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
		notify("Invalid subcommand: " .. subcommand)
	end
end, {
	nargs = "+",
	complete = function()
		return { "install", "upgrade", "clean", "list" }
	end,
})

return Pam
