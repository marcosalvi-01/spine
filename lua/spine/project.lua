-- project.lua

local M = {}

-- Get the project root directory (git root or cwd)
function M.get_project_root()
	-- Try to get git root first
	local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
	if git_root and vim.v.shell_error == 0 then
		return git_root
	end

	-- Fall back to current working directory
	return vim.fn.getcwd()
end

-- Get a unique identifier for the current project
function M.get_project_id()
	local root = M.get_project_root()
	-- Create a hash of the path to use as an identifier
	return vim.fn.sha256(root)
end

return M
