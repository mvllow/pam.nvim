local M = {}
local Pam = require("pam")
local utilities = require("pam.utilities")
local health = require("vim.health")

local function check_external_tools()
	health.start("External tools")
	if vim.fn.executable "git" == 0 then
		health.error("`git` executable not found.", {
			"Install it with your package manager.",
			"Check that your `$PATH` is set correctly.",
		})
	else
		health.ok("`git` executable found.")
	end
end

local function check_config()
	health.start("Config")

	if vim.uv.fs_stat(Pam.config.install_path) then
		health.ok("`install_path`: '" .. Pam.config.install_path .. "'")
	else
		health.error("`install_path` not found: '" .. Pam.config.install_path .. "'", {
			"Ensure `Pam.config.install_path` exists.",
			"Update the install path, e.g.: `require('pam').manage({ ... }, { install_path = '~/.local/share/nvim/site/pack/pam/start' })`",
		})
	end
end

local function check_managed_packages()
	local packages = Pam.packages
	health.start(("Managed packages (%s)"):format(#packages))

	---@param package Package
	local function list_package(package)
		if not utilities.validate_package_spec(package) then
			health.error("Invalid package spec:\n`" .. vim.inspect(package) .. "`", {
				"Ensure the package has a valid 'source', e.g.: `{ source = 'mvllow/modes.nvim' }`",
				"See |Pam.manage| for more information."
			})
			return false
		end

		local package_name = package.as or utilities.get_package_name(package.source)
		health.ok(("%s `%s`"):format(package_name, package.source))

		if package.dependencies and #package.dependencies > 0 then
			for _, dependency in ipairs(package.dependencies) do
				local dependency_name = dependency.as or utilities.get_package_name(dependency.source)
				health.ok(("└─ %s `%s`"):format(dependency_name, dependency.source))
			end
		end

		return true
	end

	local managed_packages = {}
	for _, package in ipairs(packages) do
		if list_package(package) then
			managed_packages[package.as or utilities.get_package_name(package.source)] = true
			if package.dependencies then
				for _, dependency in ipairs(package.dependencies) do
					managed_packages[dependency.as or utilities.get_package_name(dependency.source)] = true
				end
			end
		end
	end

	health.start("Untracked packages")
	local installed_packages = vim.fn.readdir(Pam.config.install_path)
	local untracked_packages = {}

	for _, package in ipairs(installed_packages) do
		if not managed_packages[package] then
			table.insert(untracked_packages, package)
		end
	end

	if #untracked_packages > 0 then
		health.warn(("Found untracked packages: `%s`"):format(table.concat(untracked_packages, ", ")), {
			"Consider removing untracked packages with `:Pam clean`.",
			"See |Pam.clean| for more information."
		})
	else
		health.ok("No untracked packages found.")
	end
end

function M.check()
	check_external_tools()
	check_config()
	check_managed_packages()
end

return M
