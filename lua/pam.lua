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
--- - No unnecessary abstractions
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

---@param msg string
---@param level? integer
---@private
local function notify(msg, level)
	level = level or vim.log.levels.INFO
	vim.notify("(pam) " .. msg, level)
end

---@param source string
---@private
local function get_package_name(source)
	return source:match(".*/(.*)")
end

---@param package Package
---@private
local function validate_package(package)
	if type(package) ~= "table" or not package.source or type(package.source) ~= "string" then
		notify(
			"Invalid package. Ensure it is a table with a proper source. For example, { source = 'mvllow/modes.nvim' }",
			vim.log.levels.ERROR
		)
		return false
	end

	if package.dependencies then
		for _, dependency in ipairs(package.dependencies) do
			if not validate_package(dependency) then
				return false
			end
		end
	end

	return true
end

---@param package Package
---@param install_path string
---@private
local function build_clone_cmd(package, install_path)
	local clone_cmd = { "git", "clone", "--depth=1", "--filter=blob:none", "--single-branch" }
	local repo_path = package.source:find("^http") and package.source
		or "https://github.com/" .. package.source .. ".git"
	table.insert(clone_cmd, repo_path)
	table.insert(clone_cmd, install_path)
	if package.branch then
		table.insert(clone_cmd, "--branch=" .. package.branch)
	end
	return clone_cmd
end

---@param packages Package[]
---@usage :Pam install
function Pam.install(packages)
	local installed_any = false

	---@param package Package
	local function install_package(package)
		if not validate_package(package) then
			return false
		end

		local package_path = package.source:gsub("^~", vim.fn.expand("$HOME"))
		local package_name = get_package_name(package_path)
		local install_path = Pam.config.install_path .. "/" .. (package.as and package.as or package_name)

		if not vim.uv.fs_stat(install_path) then
			vim.fn.system(build_clone_cmd(package, install_path))
			local package_line = {
				{ "      " .. "✔ " .. (package.as and package.as or package_name) },
				{ " (" .. package.source .. ")", "Comment" },
			}
			vim.api.nvim_echo(package_line, false, {})
			installed_any = true
		end

		if package.dependencies then
			for _, dependency in ipairs(package.dependencies) do
				install_package(dependency)
			end
		end

		if type(package.post_checkout) == "function" then
			notify("Running post checkout for " .. package_name)
			package.post_checkout()
		end
	end

	notify("Installing packages...")
	for _, package in ipairs(packages) do
		install_package(package)
	end

	if not installed_any then
		notify("All packages are already installed")
	else
		notify("Refreshing help tags...")
		vim.cmd("helptags ALL")
	end
end

---@param packages Package[]
---@usage :Pam upgrade
function Pam.upgrade(packages)
	local upgraded_any = false

	notify("Upgrading packages...")
	for _, package in ipairs(packages) do
		local package_name = get_package_name(package.source)
		local path = Pam.config.install_path .. "/" .. package_name
		if vim.uv.fs_stat(path) then
			local result = vim.fn.system({ "git", "-C", path, "pull" })
			if not result:find("Already up to date.") then
				notify(string.format("Upgraded %s (%s)", package_name, package.source))
				upgraded_any = true
			end

			if type(package.post_checkout) == "function" then
				notify("Running post checkout for " .. package_name)
				package.post_checkout()
			end
		end
	end

	if not upgraded_any then
		notify("Packages are already up to date")
	else
		notify("Refreshing help tags...")
		vim.cmd("helptags ALL")
	end
end

---@param packages Package[]
---@usage :Pam clean
function Pam.clean(packages)
	local directories = vim.fn.readdir(Pam.config.install_path)
	local managed_packages = {}

	local function add_managed_package(package)
		managed_packages[get_package_name(package.source)] = true
		if package.dependencies then
			for _, dependency in ipairs(package.dependencies) do
				add_managed_package(dependency)
			end
		end
	end

	for _, package in ipairs(packages) do
		add_managed_package(package)
	end

	local to_remove = {}
	for _, dir in ipairs(directories) do
		if not managed_packages[dir] then
			table.insert(to_remove, dir)
		end
	end

	if #to_remove == 0 then
		notify("No packages to remove")
		return
	end

	local confirm_msg = "Remove the following directories?\n" .. table.concat(to_remove, "\n") .. "\n[y/N]: "

	if vim.fn.input(confirm_msg):lower() == "y" then
		notify("Removing unused packages...")
		for _, dir in ipairs(to_remove) do
			vim.fn.delete(Pam.config.install_path .. "/" .. dir, "rf")
			notify("Removed " .. dir)
		end

		notify("Refreshing help tags...")
		vim.cmd("helptags ALL")
	else
		notify("Clean cancelled")
	end
end

---@param packages Package[]
---@usage :Pam list
function Pam.list(packages)
	notify("Showing managed packages...")
	local function list_package(package, prefix)
		local package_name = get_package_name(package.source)
		local package_line = {
			{ prefix .. package_name },
			{ " (" .. package.source .. ")", "Comment" },
		}
		vim.api.nvim_echo(package_line, false, {})

		if package.dependencies and #package.dependencies > 0 then
			for i, dependency in ipairs(package.dependencies) do
				local is_last = i == #package.dependencies
				local new_prefix = prefix .. (is_last and "└── " or "├── ")
				list_package(dependency, new_prefix)
			end
		end
	end

	for _, package in ipairs(packages) do
		-- Indent items with length of "(pam) "
		list_package(package, "      ")
	end
end

vim.api.nvim_create_user_command("Pam", function(opts)
	local subcommand = opts.fargs[1]
	if subcommand == "install" then
		Pam.install(Pam.packages)
	elseif subcommand == "upgrade" or subcommand == "update" then
		Pam.upgrade(Pam.packages)
	elseif subcommand == "clean" then
		Pam.clean(Pam.packages)
	elseif subcommand == "list" then
		Pam.list(Pam.packages)
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
