local M = {}

---@param msg string
---@param level? integer
---@private
function M.notify(msg, level)
	level = level or vim.log.levels.INFO
	vim.notify("(pam) " .. msg, level)
end

---@param package Package
---@private
function M.validate_package_spec(package)
	if type(package) ~= "table" or not package.source or type(package.source) ~= "string" then
		return false
	end

	return true
end

---@param source string
---@private
function M.get_package_name(source)
	return source:match(".*/(.*)")
end

return M
