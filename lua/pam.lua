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
---     ~/.local/share/nvim/site/pack/pam/start/pam.nvim
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
	utilities.notify("Refreshed help tags")
end

---@param packages Package[]
---@param config? Config
---
---@usage >lua
---  require("pam").manage({
---    { source = "mvllow/pam.nvim" },
---    {
---      source = "nvim-treesitter/nvim-treesitter",
---      post_checkout = function()
---        vim.cmd("TSUpdate")
---      end,
---      config = function()
---        require("nvim-treesitter.configs").setup()
---      end
---    },
---    {
---      source = "ThePrimeagen/harpoon",
---      as = "baboon",
---      branch = "harpoon2",
---      dependencies = {
---        { source = "nvim-lua/plenary.nvim" }
---      }
---    }
---  })
--- <
function Pam.manage(packages, config)
	Pam.packages = packages or {}
	Pam.config = vim.tbl_extend("force", Pam.config, config or {})

	for _, package in ipairs(Pam.packages) do
		if type(package.config) == "function" then
			package.config()
		end
	end
end

---@param packages Package[]
---
---@usage :Pam install
function Pam.install(packages)
	local installed_any = false
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
			local clone_command = { "git", "clone", "--depth=1", "--filter=blob:none", "--single-branch", repo_path,
				install_path }
			if package.branch then
				table.insert(clone_command, "--branch=" .. package.branch)
			end

			vim.fn.system(clone_command)
			utilities.notify("Installing " .. package_name .. " (" .. package.source .. ")")
			installed_any = true

			if type(package.post_checkout) == "function" then
				utilities.notify("Running post checkout for " .. package_name)
				package.post_checkout()
			end
		end
	end

	utilities.notify("Installing packages...")
	for _, package in ipairs(packages) do
		install_package(package)

		if package.dependencies and #package.dependencies > 0 then
			for _, dependency in ipairs(package.dependencies) do
				install_package(dependency)
			end
		end
	end

	if installed_any then
		refresh_help_tags()
	else
		utilities.notify("All packages are already installed")
	end
end

---@param packages Package[]
---
---@usage :Pam upgrade
function Pam.upgrade(packages)
	local upgraded_any = false
	local home_dir = vim.fn.expand("$HOME")

	---@param package Package
	local function upgrade_package(package)
		if not utilities.validate_package_spec(package) then
			return false
		end

		local package_path = package.source:gsub("^~", home_dir)
		local package_name = package.as or utilities.get_package_name(package_path)
		local install_path = Pam.config.install_path .. "/" .. package_name

		if vim.uv.fs_stat(install_path) then
			local status = vim.fn.system({ "git", "-C", install_path, "pull" })

			if not status:find("Already up to date.") then
				utilities.notify("Upgrading " .. package_name .. " (" .. package.source .. ")")
				upgraded_any = true

				if type(package.post_checkout) == "function" then
					utilities.notify("Running post checkout for " .. package_name)
					package.post_checkout()
				end
			end
		end
	end

	utilities.notify("Upgrading packages...")
	for _, package in ipairs(packages) do
		upgrade_package(package)

		if package.dependencies and #package.dependencies > 0 then
			for _, dependency in ipairs(package.dependencies) do
				upgrade_package(dependency)
			end
		end
	end

	if upgraded_any then
		refresh_help_tags()
	else
		utilities.notify("Packages are already up to date")
	end
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

	local confirm_message = ("(pam) Remove the following directories?\n(pam) - %s\n(pam) [y/N]:"):format(table.concat(
		paths_to_remove,
		"\n"))

	if vim.fn.input(confirm_message):lower() == "y" then
		utilities.notify("Removing unused packages...")
		for _, path in ipairs(paths_to_remove) do
			vim.fn.delete(path, "rf")
			utilities.notify("Removed " .. path)
		end

		refresh_help_tags()
	else
		utilities.notify("Clean cancelled")
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
