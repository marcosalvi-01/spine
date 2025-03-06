-- init.lua

local config = require("spine.config")
local ui = require("spine.ui")
local buffers = require("spine.buffers")
local keymaps = require("spine.keymaps")
local state = require("spine.state")
local api = require("spine.api")

local M = {}

-- The user can override the defaults via the setup() function
function M.setup(user_config)
	config.setup(user_config)
	ui.setup_highlights()

	-- Add autocmd to save buffers when Neovim exits
	if not config.get("auto") and config.get("persist_manual_buffers") then
		vim.api.nvim_create_autocmd("VimLeavePre", {
			callback = function()
				if state.custom_order and #state.custom_order > 0 then
					require("spine.persistence").save_project_buffers(state.custom_order)
				end
			end,
		})
	end
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

-- Export API functions
M.api = {
	switch_to_buffer_by_index = api.switch_to_buffer_by_index,
	switch_to_buffer_by_tag = api.switch_to_buffer_by_tag,
	move_buffer = api.move_buffer,
	delete_buffer_by_index = api.delete_buffer_by_index,
	split_with_buffer = api.split_with_buffer,
	set_buffer_tag = api.set_buffer_tag,
	get_buffer_list = function()
		return vim.deepcopy(state.custom_order)
	end,
	refresh_buffers = buffers.gather_buffers,
	add_current_buffer = buffers.add_current_buffer,
}

return M
