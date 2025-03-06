-- keymaps.lua

local config = require("spine.config")
local state = require("spine.state")
local buffers = require("spine.buffers")
local ui = require("spine.ui")
local api = require("spine.api")
local persistence = require("spine.persistence")

local M = {}

-- Helper: close the picker and switch to the selected buffer
local function close_picker(bnr)
	local popup_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_close(popup_win, true)
	state.restore_settings()
	if vim.api.nvim_win_is_valid(state.prev_win) then
		vim.api.nvim_set_current_win(state.prev_win)
	end
	vim.cmd("buffer " .. bnr)
end

-- Setup keymaps for the picker buffer
function M.setup_buffer_keymaps(picker_buf)
	-- Clear existing keymaps
	for i = 1, #config.get("characters") do
		local char = config.get("characters"):sub(i, i)
		pcall(vim.keymap.del, "n", char, { buffer = picker_buf })
	end

	-- Set up buffer selection keymaps
	for i = 1, #state.custom_order do
		local bnr = state.custom_order[i]
		local prefix_char = config.get("characters"):sub(i, i)
		vim.keymap.set("n", prefix_char, function()
			close_picker(bnr)
		end, { buffer = picker_buf, noremap = true, silent = true })
	end

	-- Helper function to navigate to the buffer under cursor
	local function navigate_to_buffer()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1]
		if line_num <= #state.custom_order then
			close_picker(state.custom_order[line_num])
		end
	end

	-- Actions mapped to keys
	local actions = {
		-- Close picker actions
		close = api.close,
		-- Select buffer action
		select = navigate_to_buffer,

		-- Move buffer up in list
		move_up = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum > 1 then
				buffers.swap_items(picker_buf, lnum, lnum - 1)
				vim.api.nvim_win_set_cursor(0, { lnum - 1, 0 })

				-- update the saved state
				if not config.get("auto") then
					persistence.save_project_buffers(state.custom_order)
				end
			end
		end,

		-- Move buffer down in list
		move_down = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum < #state.custom_order then
				buffers.swap_items(picker_buf, lnum, lnum + 1)
				vim.api.nvim_win_set_cursor(0, { lnum + 1, 0 })

				-- update the saved state
				if not config.get("auto") then
					persistence.save_project_buffers(state.custom_order)
				end
			end
		end,

		-- Delete buffer action
		delete_buffer = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum <= #state.custom_order then
				api.delete_buffer_by_index(lnum)
				if #state.custom_order == 0 then
					api.close()
					vim.notify("[Spine] Closing empty popup!")
					return
				end
				buffers.update_buffer_lines(picker_buf)
				M.setup_buffer_keymaps(picker_buf)
				ui.update_window_size()
				if lnum > #state.custom_order then
					vim.api.nvim_win_set_cursor(0, { #state.custom_order, 0 })
				end
			end
		end,

		-- Split buffer action
		split_buffer = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum <= #state.custom_order then
				local bnr = state.custom_order[lnum]
				local cur_win = vim.api.nvim_get_current_win()
				vim.api.nvim_win_close(cur_win, true)
				state.restore_settings()
				if vim.api.nvim_win_is_valid(state.prev_win) then
					vim.api.nvim_set_current_win(state.prev_win)
				end
				vim.cmd("vsplit | buffer " .. bnr)
			end
		end,

		-- Change tag action
		change_tag = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			vim.ui.input({ prompt = config.get("prompt_tag"), default = "" }, function(new_tag)
				if not new_tag or new_tag == "" then
					return
				end

				local existing_pos = nil
				for i = 1, #config.get("characters") do
					if config.get("characters"):sub(i, i) == new_tag then
						existing_pos = i
						break
					end
				end

				if existing_pos then
					state.custom_order[lnum], state.custom_order[existing_pos] =
						state.custom_order[existing_pos], state.custom_order[lnum]
				else
					config.update_characters(config.get("characters") .. new_tag)
					local current_buffer = state.custom_order[lnum]
					table.remove(state.custom_order, lnum)
					table.insert(state.custom_order, current_buffer)
				end
				buffers.update_buffer_lines(picker_buf)
				M.setup_buffer_keymaps(picker_buf)
			end)
		end,
	}

	-- Set up the keymaps based on the config
	for action_name, keys in pairs(config.get("keys")) do
		local action = actions[action_name]
		if action then
			for _, key in ipairs(keys) do
				vim.keymap.set("n", key, action, { buffer = picker_buf, noremap = true, silent = true })
			end
		end
	end

	-- Additional keymap to disable the dash key
	vim.keymap.set("n", "-", "<nop>", { buffer = picker_buf, noremap = true, silent = true })
end

return M
