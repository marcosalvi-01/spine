-- Spine: A Neovim buffer management plugin with a popup interface
local config = require("spine.config")
local ui = require("spine.ui")
local buffers = require("spine.buffers")
local keymaps = require("spine.keymaps")
local state = require("spine.state")

local M = {}

-- The user can override the defaults via the setup() function
function M.setup(user_config)
	config.setup(user_config)
	ui.setup_highlights()
end

-- Main function to open the buffer picker
function M.open()
	if state.active_popup_win and vim.api.nvim_win_is_valid(state.active_popup_win) then
		vim.api.nvim_win_close(state.active_popup_win, true)
		state.restore_settings()
		state.active_popup_win = nil
		return
	end

	ui.setup_highlights()
	state.prev_win = vim.api.nvim_get_current_win()
	state.save_settings()

	buffers.gather_buffers()

	-- Do not open the picker if no buffers are available
	if #state.custom_order == 0 then
		print("[Spine] No open buffer found!")
		state.restore_settings()
		return
	end

	local picker_buf = buffers.create_picker_buffer()
	buffers.update_buffer_lines(picker_buf)

	local function update_highlight()
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
		vim.api.nvim_buf_clear_namespace(picker_buf, state.ns_id + 1, 0, -1)
		vim.api.nvim_buf_add_highlight(picker_buf, state.ns_id + 1, "SpineSelected", cursor_line, 0, -1)
	end

	vim.api.nvim_create_autocmd("CursorMoved", { buffer = picker_buf, callback = update_highlight })
	update_highlight()
	keymaps.setup_buffer_keymaps(picker_buf)

	local dims = ui.calculate_dimensions()
	if dims.width <= 0 then
		print("[Spine] No open buffer found!")
		state.restore_settings()
		return
	end

	state.active_popup_win = vim.api.nvim_open_win(picker_buf, true, {
		relative = "editor",
		row = dims.row,
		col = dims.col,
		width = dims.width,
		height = dims.height,
		style = "minimal",
		border = config.get("border"),
		title = " " .. config.get("title") .. " ",
		title_pos = config.get("title_pos"),
	})

	vim.api.nvim_set_option_value("winhighlight", config.get("winhighlight"), { win = state.active_popup_win })
end

-- API Functions
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
		vim.cmd("bdelete " .. bnr)
		table.remove(state.custom_order, index)
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

-- Export API functions
M.api = {
	switch_to_buffer_by_index = M.switch_to_buffer_by_index,
	switch_to_buffer_by_tag = M.switch_to_buffer_by_tag,
	move_buffer = M.move_buffer,
	delete_buffer_by_index = M.delete_buffer_by_index,
	split_with_buffer = M.split_with_buffer,
	set_buffer_tag = M.set_buffer_tag,
	get_buffer_list = function()
		return vim.deepcopy(state.custom_order)
	end,
	refresh_buffers = buffers.gather_buffers,
}

return M
