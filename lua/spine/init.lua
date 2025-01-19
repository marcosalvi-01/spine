local M = {}
-- Characters used to label each buffer
local characters = "neiatsrc"
-- Persistent list to track the buffer order
local buffer_order = nil
-- Variable to track the currently open popup window
local active_popup_win = nil

local saved = {
	guicursor = nil,
	scrolloff = nil,
	sidescrolloff = nil,
}
-- Function to restore original settings when closing
local function restore_settings()
	if saved.guicursor then
		vim.go.guicursor = saved.guicursor
	end
	if saved.scrolloff then
		vim.o.scrolloff = saved.scrolloff
	end
	if saved.sidescrolloff then
		vim.o.sidescrolloff = saved.sidescrolloff
	end
	-- zero them so we know they're restored
	saved.guicursor = nil
	saved.scrolloff = nil
	saved.sidescrolloff = nil
end

-- Theme colors
local colors = {
	background = "#282828", -- Gruvbox fg1
	foreground = "#ddc7a1", -- Gruvbox fg2
	taupe = "#504945", -- Gruvbox color2
	neutral_gray = "#32302f", -- Gruvbox color3
	beige = "#a89984", -- Gruvbox color4
	blue_green = "#7daea3", -- Gruvbox color5
	greenish = "#8ec07c", -- Gruvbox color6
	yellowish = "#d8a657", -- Gruvbox color7
	pinkish = "#d3869b", -- Gruvbox color8
	reddish = "#ea6962", -- Gruvbox color9
}

-- Create highlight groups when the plugin loads
local function setup_highlights()
	-- Tag highlight - using pinkish for emphasis
	vim.api.nvim_set_hl(0, "SpineTag", { fg = colors.yellowish, bold = true })
	-- File name highlight - using foreground color
	vim.api.nvim_set_hl(0, "SpineFileName", { fg = colors.foreground })
	-- Current line highlight (replaces Visual)
	vim.api.nvim_set_hl(0, "SpineSelected", { bg = colors.taupe })
	-- Border highlight
	vim.api.nvim_set_hl(0, "SpineBorder", { fg = colors.foreground })
	-- Title highlight
	vim.api.nvim_set_hl(0, "SpineTitle", { fg = colors.greenish, bold = true })
	-- Add a new highlight group for the invisible cursor
	vim.api.nvim_set_hl(0, "SpineInvisibleCursor", { reverse = true, blend = 100 })
end

function M.Open()
	-- Ensure highlights are set up
	setup_highlights()
	-- 1. Remember the current window so we can return to it later
	local prev_win = vim.api.nvim_get_current_win()
	-- Remember the current `scrolloff` setting
	if active_popup_win and vim.api.nvim_win_is_valid(active_popup_win) then
		vim.api.nvim_win_close(active_popup_win, true)
		restore_settings()
		active_popup_win = nil
		return
	end

	-- If we've never stored them, store them
	if not saved.guicursor then
		saved.guicursor = vim.go.guicursor
	end
	if not saved.scrolloff then
		saved.scrolloff = vim.o.scrolloff
	end
	if not saved.sidescrolloff then
		saved.sidescrolloff = vim.o.sidescrolloff
	end

	vim.o.scrolloff = 0
	vim.o.sidescrolloff = 0

	local picker_buf = vim.api.nvim_create_buf(false, true)

	-- Now use BufEnter to set invisible cursor
	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = picker_buf,
		callback = function()
			vim.go.guicursor = "a:SpineInvisibleCursor"
		end,
	})
	-- Close any existing popup before opening a new one
	if active_popup_win and vim.api.nvim_win_is_valid(active_popup_win) then
		vim.api.nvim_win_close(active_popup_win, true)
		restore_settings()
		return
	end
	-- 3. Gather all the *listed* buffers that are loaded
	if not buffer_order then
		buffer_order = {}
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and (vim.fn.buflisted(b) == 1) then
				table.insert(buffer_order, b)
			end
		end
	end

	-- Create namespace for highlights
	local ns_id = vim.api.nvim_create_namespace("SpineHighlight")

	-- 4. Build display lines and set them in the picker buffer
	local max_width = 0 -- Track the maximum line width
	local function update_buffer_lines()
		local lines = {}
		max_width = 0 -- Reset max_width before recalculating
		local max_items = math.min(#buffer_order, #characters)
		for i = 1, max_items do
			local bnr = buffer_order[i]
			local prefix_char = characters:sub(i, i)
			local full_path = vim.api.nvim_buf_get_name(bnr)
			local name = full_path == "" and "[No Name]" or vim.fn.fnamemodify(full_path, ":t")
			local line = prefix_char .. "  " .. name
			lines[i] = line
			max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
		end
		-- Temporarily make the buffer modifiable to update the lines
		vim.api.nvim_set_option_value("modifiable", true, { buf = picker_buf })
		vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)

		-- Apply syntax highlighting to each line
		vim.api.nvim_buf_clear_namespace(picker_buf, ns_id, 0, -1)
		for i = 1, #lines do
			-- Highlight tag (first character)
			vim.api.nvim_buf_add_highlight(picker_buf, ns_id, "SpineTag", i - 1, 0, 1)
			-- Highlight filename (after the tag and two spaces)
			vim.api.nvim_buf_add_highlight(picker_buf, ns_id, "SpineFileName", i - 1, 3, -1)
		end

		vim.api.nvim_set_option_value("modifiable", false, { buf = picker_buf })
	end

	-- Function to update keymaps for buffer selection
	local function update_buffer_keymaps()
		-- Clear existing keymaps first
		for i = 1, #characters do
			local char = characters:sub(i, i)
			pcall(vim.keymap.del, "n", char, { buffer = picker_buf })
		end

		for i = 1, #buffer_order do
			local bnr = buffer_order[i]
			local prefix_char = characters:sub(i, i)

			-- Now also call restore_settings() here:
			vim.keymap.set("n", prefix_char, function()
				local popup_win = vim.api.nvim_get_current_win()
				vim.api.nvim_win_close(popup_win, true)
				restore_settings()

				if vim.api.nvim_win_is_valid(prev_win) then
					vim.api.nvim_set_current_win(prev_win)
				end
				vim.cmd("buffer " .. bnr)
			end, { buffer = picker_buf, noremap = true, silent = true })
		end
	end

	update_buffer_lines()

	-- 5. Make the buffer unmodifiable/scratch
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = picker_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = picker_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = picker_buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = picker_buf })

	-- Function to switch tags between lines
	local function switch_tag()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local current_line = cursor_pos[1]

		-- Prompt for new tag
		vim.ui.input({
			prompt = "Enter new tag: ",
			default = "",
		}, function(new_tag)
			if not new_tag or new_tag == "" then
				return
			end

			-- Find if the new tag already exists
			local existing_pos = nil
			for i = 1, #characters do
				if characters:sub(i, i) == new_tag then
					existing_pos = i
					break
				end
			end

			if existing_pos then
				-- Swap buffer positions if tag exists
				local temp = buffer_order[current_line]
				buffer_order[current_line] = buffer_order[existing_pos]
				buffer_order[existing_pos] = temp
			else
				-- Add new tag to the characters string
				characters = characters .. new_tag

				-- Move the current buffer to the end of the list
				local current_buffer = buffer_order[current_line]
				table.remove(buffer_order, current_line)
				table.insert(buffer_order, current_buffer)
			end

			-- Update the display and keymaps
			update_buffer_lines()
			update_buffer_keymaps()
		end)
	end

	vim.keymap.set("n", "<C-c>", switch_tag, { buffer = picker_buf, noremap = true, silent = true })
	vim.keymap.set("n", "-", "<nop>", { buffer = picker_buf, noremap = true, silent = true })

	-- Highlight the line under the cursor
	local function update_highlight()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1] - 1 -- Convert 1-based to 0-based
		-- Clear previous selection highlight
		vim.api.nvim_buf_clear_namespace(picker_buf, ns_id + 1, 0, -1)
		-- Add new selection highlight
		vim.api.nvim_buf_add_highlight(picker_buf, ns_id + 1, "SpineSelected", line_num, 0, -1)
	end

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = picker_buf,
		callback = update_highlight,
	})
	-- Initialize the highlight for the first line
	update_highlight()
	-- Keymap to move items up and down
	local function swap_items(idx1, idx2)
		buffer_order[idx1], buffer_order[idx2] = buffer_order[idx2], buffer_order[idx1]
		update_buffer_lines()
		update_buffer_keymaps() -- Update keymaps after swapping
	end

	vim.keymap.set("n", "<S-Up>", function()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1]
		if line_num > 1 then
			swap_items(line_num, line_num - 1)
			vim.api.nvim_win_set_cursor(0, { line_num - 1, 0 })
		end
	end, { buffer = picker_buf, noremap = true, silent = true })

	vim.keymap.set("n", "<S-Down>", function()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1]
		if line_num < #buffer_order then
			swap_items(line_num, line_num + 1)
			vim.api.nvim_win_set_cursor(0, { line_num + 1, 0 })
		end
	end, { buffer = picker_buf, noremap = true, silent = true })

	-- Map `D` to close the buffer under the cursor
	vim.keymap.set("n", "<C-d>", function()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1]
		if line_num <= #buffer_order then
			local bnr = buffer_order[line_num]
			vim.cmd("bdelete " .. bnr)
			table.remove(buffer_order, line_num)
			update_buffer_lines()
			update_buffer_keymaps() -- Update keymaps after removing a buffer
		end
	end, { buffer = picker_buf, noremap = true, silent = true })

	-- Map `Control+S` to open the buffer under the cursor in a vertical split
	vim.keymap.set("n", "<C-s>", function()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1]
		if line_num <= #buffer_order then
			local bnr = buffer_order[line_num]
			local popup_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_close(popup_win, true)
			restore_settings()
			if vim.api.nvim_win_is_valid(prev_win) then
				vim.api.nvim_set_current_win(prev_win)
			end
			vim.cmd("vsplit | buffer " .. bnr)
		end
	end, { buffer = picker_buf, noremap = true, silent = true })

	-- Initial setup of buffer keymaps
	update_buffer_keymaps()
	-- Open the floating window with updated options
	local height = #buffer_order
	local total_lines = vim.o.lines
	local total_cols = vim.o.columns
	local width = math.min(max_width, total_cols + 1)
	local row = math.floor((total_lines - height) / 2)
	local col = math.floor((total_cols - width) / 2)

	active_popup_win = vim.api.nvim_open_win(picker_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height == 0 and 1 or height,
		style = "minimal",
		border = "rounded",
		title = " Spine ",
		title_pos = "center",
	})

	-- Apply window-specific highlights
	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:SpineNormal,FloatBorder:SpineBorder",
		{ win = active_popup_win }
	)

	-- Update close-related keymaps to restore settings
	vim.keymap.set("n", "q", function()
		restore_settings()
		vim.cmd("quit")
	end, { buffer = picker_buf, noremap = true, silent = true })

	vim.keymap.set("n", "<Esc>", function()
		restore_settings()
		vim.cmd("quit")
	end, { buffer = picker_buf, noremap = true, silent = true })

	-- Update buffer navigation functions to restore settings
	local function navigate_to_buffer()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1]
		if line_num <= #buffer_order then
			local bnr = buffer_order[line_num]
			local popup_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_close(popup_win, true)
			restore_settings()
			if vim.api.nvim_win_is_valid(prev_win) then
				vim.api.nvim_set_current_win(prev_win)
			end
			vim.cmd("buffer " .. bnr)
		end
	end

	vim.keymap.set("n", "<CR>", navigate_to_buffer, { buffer = picker_buf, noremap = true, silent = true })

	-- Initial setup of buffer keymaps
	update_buffer_keymaps()
end

return M
