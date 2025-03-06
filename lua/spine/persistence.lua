-- persitence.lua

local M = {}
local project = require("spine.project")
local config = require("spine.config")

-- Get the path to the state directory
function M.get_state_dir()
	local base_dir = vim.fn.stdpath("data") .. "/spine"
	-- Create directory if it doesn't exist
	if vim.fn.isdirectory(base_dir) == 0 then
		vim.fn.mkdir(base_dir, "p")
	end
	return base_dir
end

-- Get the path to the project state file
function M.get_project_state_file()
	local project_id = project.get_project_id()
	return M.get_state_dir() .. "/" .. project_id .. ".json"
end

-- Save the custom_order buffers for the current project
function M.save_project_buffers(buffers)
	if not config.get("persist_manual_buffers") then
		return
	end

	local state_file = M.get_project_state_file()

	-- Convert buffer numbers to file paths
	local buffer_paths = {}
	for _, buf in ipairs(buffers) do
		local path = vim.api.nvim_buf_get_name(buf)
		if path and path ~= "" then
			table.insert(buffer_paths, path)
		end
	end

	-- Save to file
	local file = io.open(state_file, "w")
	if file then
		file:write(vim.json.encode({
			buffers = buffer_paths,
			timestamp = os.time(),
		}))
		file:close()
	end
end

-- Load the custom_order buffers for the current project
function M.load_project_buffers()
	if not config.get("persist_manual_buffers") then
		return {}
	end

	local state_file = M.get_project_state_file()

	-- Check if file exists
	if vim.fn.filereadable(state_file) ~= 1 then
		return {}
	end

	-- Read file
	local file = io.open(state_file, "r")
	if not file then
		return {}
	end

	local content = file:read("*all")
	file:close()

	-- Parse JSON
	local success, data = pcall(vim.json.decode, content)
	if not success or not data or not data.buffers then
		return {}
	end

	-- Convert paths to buffer numbers, creating them if needed
	local buffers = {}
	for _, path in ipairs(data.buffers) do
		-- Check if file still exists
		if vim.fn.filereadable(path) == 1 then
			-- Try to find existing buffer
			local found = false
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_get_name(buf) == path then
					table.insert(buffers, buf)
					found = true
					break
				end
			end

			-- Create buffer if not found
			if not found and config.get("recreate_saved_buffers") then
				local buf = vim.fn.bufadd(path)
				table.insert(buffers, buf)
			end
		end
	end

	return buffers
end

return M
