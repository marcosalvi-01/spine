local M = {}
-- Characters used to label each buffer
local characters = "neiotsrc"
-- Persistent list to track the buffer order
local buffer_order = nil

function M.Open()
	-- 1. Remember the current window so we can return to it later
	local prev_win = vim.api.nvim_get_current_win()
	-- Remember the current `scrolloff` setting
	local original_scrolloff = vim.o.scrolloff
	-- Temporarily disable `scrolloff`
	vim.o.scrolloff = 0

	-- 2. Create a scratch buffer for the popup
	local picker_buf = vim.api.nvim_create_buf(false, true)
	-- 3. Gather all the *listed* buffers that are loaded
	if not buffer_order then
		buffer_order = {}
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and (vim.fn.buflisted(b) == 1) then
				table.insert(buffer_order, b)
			end
		end
	end

	-- 4. Build display lines and set them in the picker buffer
	local function update_buffer_lines()
		local lines = {}
		local max_width = 0 -- Track the maximum line width
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
		vim.api.nvim_set_option_value("modifiable", false, { buf = picker_buf })
	end
	update_buffer_lines()

	-- 5. Make the buffer unmodifiable/scratch
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = picker_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = picker_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = picker_buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = picker_buf })

	-- Keymaps to close the popup
	vim.keymap.set("n", "q", function()
		vim.o.scrolloff = original_scrolloff
		vim.cmd("quit")
	end, { buffer = picker_buf, noremap = true, silent = true })
	vim.keymap.set("n", "<Esc>", function()
		vim.o.scrolloff = original_scrolloff
		vim.cmd("quit")
	end, { buffer = picker_buf, noremap = true, silent = true })
	vim.keymap.set("n", "<C-c>", function()
		vim.o.scrolloff = original_scrolloff
		vim.cmd("quit")
	end, { buffer = picker_buf, noremap = true, silent = true })

	-- Highlight the line under the cursor
	local ns_id = vim.api.nvim_create_namespace("PickerHighlight")
	local function update_highlight()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1] - 1 -- Convert 1-based to 0-based
		vim.api.nvim_buf_clear_namespace(picker_buf, ns_id, 0, -1)
		vim.api.nvim_buf_add_highlight(picker_buf, ns_id, "Visual", line_num, 0, -1)
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

	-- Map each label character to open its corresponding buffer
	for i = 1, #buffer_order do
		local bnr = buffer_order[i]
		local prefix_char = characters:sub(i, i)
		vim.keymap.set("n", prefix_char, function()
			local popup_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_close(popup_win, true)
			vim.o.scrolloff = original_scrolloff
			if vim.api.nvim_win_is_valid(prev_win) then
				vim.api.nvim_set_current_win(prev_win)
			end
			vim.cmd("buffer " .. bnr)
		end, { buffer = picker_buf, noremap = true, silent = true })
	end

	-- Open the floating window
	local height = #buffer_order
	local width = 40
	local total_lines = vim.o.lines
	local total_cols = vim.o.columns
	width = math.min(width, total_cols - 4) -- Leave some margin
	local row = math.floor((total_lines - height) / 2)
	local col = math.floor((total_cols - width) / 2)
	vim.api.nvim_open_win(picker_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height == 0 and 1 or height,
		style = "minimal",
		border = "rounded",
		title = "Buffer Picker",
		title_pos = "center",
	})
end

return M
