-- api.lua
local config = require("spine.config")
local buffers = require("spine.buffers")
local state = require("spine.state")
local persistence = require("spine.persistence")

local M = {}

-------------------------------------------------------
--					 API Functions					 --
-------------------------------------------------------

-- Switch to a buffer by index
function M.switch_to_buffer_by_index(index)
	if not state.custom_order then
		buffers.gather_buffers()
	end

	if index > 0 and index <= #state.custom_order then
		vim.cmd("buffer " .. state.custom_order[index])
		return true
	end
	return false
end

-- Switch to a buffer by tag character
function M.switch_to_buffer_by_tag(char)
	if not state.custom_order then
		buffers.gather_buffers()
	end

	local index = config.get("characters"):find(char)
	return M.switch_to_buffer_by_index(index)
end

-- Move a buffer in the custom order
function M.move_buffer(from_index, to_index)
	if not state.custom_order then
		buffers.gather_buffers()
	end

	if from_index > 0 and from_index <= #state.custom_order and to_index > 0 and to_index <= #state.custom_order then
		local buf = table.remove(state.custom_order, from_index)
		table.insert(state.custom_order, to_index, buf)

		if not config.get("auto") then
			persistence.save_project_buffers(state.custom_order)
		end

		return true
	end
	return false
end

-- Delete a buffer by index
function M.delete_buffer_by_index(index)
	if not state.custom_order then
		buffers.gather_buffers()
	end

	if index > 0 and index <= #state.custom_order then
		local bnr = state.custom_order[index]
		vim.api.nvim_buf_delete(bnr, { force = false })
		table.remove(state.custom_order, index)

		-- After adding the buffer:
		if not config.get("auto") then
			persistence.save_project_buffers(state.custom_order)
		end

		return true
	end
	return false
end

-- Split window and show buffer by index
function M.split_with_buffer(index, vertical)
	if not state.custom_order then
		buffers.gather_buffers()
	end

	if index > 0 and index <= #state.custom_order then
		local bnr = state.custom_order[index]
		local cmd = vertical and "vsplit" or "split"
		vim.cmd(cmd .. " | buffer " .. bnr)
		return true
	end
	return false
end

-- Update a buffer tag
function M.set_buffer_tag(index, new_tag)
	if not state.custom_order then
		buffers.gather_buffers()
	end

	if index > 0 and index <= #state.custom_order then
		-- Find if tag already exists
		local existing_pos = config.get("characters"):find(new_tag)

		if existing_pos then
			-- Swap if tag exists
			state.custom_order[index], state.custom_order[existing_pos] =
				state.custom_order[existing_pos], state.custom_order[index]
		else
			-- Add new tag if it doesn't exist
			config.update_characters(config.get("characters") .. new_tag)
			local current_buffer = state.custom_order[index]
			table.remove(state.custom_order, index)
			table.insert(state.custom_order, current_buffer)
		end
		return true
	end
	return false
end

return M
