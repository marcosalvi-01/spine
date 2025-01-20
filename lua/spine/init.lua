-- Spine: A Neovim buffer management plugin with a popup interface
local M = {}

-------------------------------
-- Constants & State
-------------------------------

local Constants = {
	CHARACTERS = "neiatsrchd0123456789", -- Characters used to label each buffer
	HIGHLIGHTS = {
		{ name = "SpineTag", attrs = { fg = "#d8a657", bold = true } },
		{ name = "SpineFileName", attrs = { fg = "#8ec07c" } },
		{ name = "SpineSelected", attrs = { bg = "#504945" } },
		{ name = "SpineBorder", attrs = { fg = "#ddc7a1" } },
		{ name = "SpineTitle", attrs = { fg = "#7daea3", bold = true } },
		{ name = "SpineInvisibleCursor", attrs = { reverse = true, blend = 100 } },
	},
}

-- State holds runtime properties.
local State = {
	-- custom_order persists changes across opening and closing the picker.
	custom_order = nil,
	active_popup_win = nil,
	prev_win = nil,
	saved_settings = {
		guicursor = nil,
		scrolloff = nil,
		sidescrolloff = nil,
	},
	ns_id = vim.api.nvim_create_namespace("SpineHighlight"),
}

-------------------------------
-- Settings Management
-------------------------------

local Settings = {}

function Settings.save()
	if not State.saved_settings.guicursor then
		State.saved_settings.guicursor = vim.go.guicursor
		State.saved_settings.scrolloff = vim.o.scrolloff
		State.saved_settings.sidescrolloff = vim.o.sidescrolloff
	end
	vim.o.scrolloff = 0
	vim.o.sidescrolloff = 0
end

function Settings.restore()
	if State.saved_settings.guicursor then
		vim.go.guicursor = State.saved_settings.guicursor
		vim.o.scrolloff = State.saved_settings.scrolloff
		vim.o.sidescrolloff = State.saved_settings.sidescrolloff
		State.saved_settings.guicursor = nil
		State.saved_settings.scrolloff = nil
		State.saved_settings.sidescrolloff = nil
	end
end

-------------------------------
-- UI Utilities
-------------------------------

local UI = {}

function UI.setup_highlights()
	for _, hl in ipairs(Constants.HIGHLIGHTS) do
		vim.api.nvim_set_hl(0, hl.name, hl.attrs)
	end
end

-- Calculates dimensions for the floating window.
function UI.calculate_dimensions()
	local max_width = 0
	local max_items = math.min(#State.custom_order, #Constants.CHARACTERS)

	for i = 1, max_items do
		local bnr = State.custom_order[i]
		local prefix_char = Constants.CHARACTERS:sub(i, i)
		local full_path = vim.api.nvim_buf_get_name(bnr)
		local name = (full_path == "" and "[No Name]") or vim.fn.fnamemodify(full_path, ":t")
		local line = prefix_char .. "  " .. name
		max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
	end

	local total_lines, total_cols = vim.o.lines, vim.o.columns
	local height = (#State.custom_order == 0) and 1 or #State.custom_order
	local width = math.min(max_width, total_cols - 2)

	return {
		width = width,
		height = height,
		row = math.floor((total_lines - height) / 2),
		col = math.floor((total_cols - width) / 2),
	}
end

function UI.update_window_size()
	if State.active_popup_win and vim.api.nvim_win_is_valid(State.active_popup_win) then
		local dims = UI.calculate_dimensions()
		vim.api.nvim_win_set_config(State.active_popup_win, {
			relative = "editor",
			row = dims.row,
			col = dims.col,
			width = dims.width,
			height = dims.height,
		})
	end
end

-------------------------------
-- Buffer Management
-------------------------------

local BufferManager = {}

-- Maintains persistent order across sessions.
-- If State.custom_order already exists, update it with new buffers and remove invalid ones.
function BufferManager.gather_buffers()
	local current_bufs = {}
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and (vim.fn.buflisted(b) == 1) then
			current_bufs[b] = true
		end
	end

	function Reverse(arr, count)
		local i, j = 1, count or #arr

		while i < j do
			arr[i], arr[j] = arr[j], arr[i]

			i = i + 1
			j = j - 1
		end
	end

	Reverse(current_bufs, #current_bufs)

	if not State.custom_order then
		State.custom_order = {}
		for b, _ in pairs(current_bufs) do
			table.insert(State.custom_order, b)
		end
	else
		-- Remove buffers that are no longer valid.
		local new_order = {}
		for _, b in ipairs(State.custom_order) do
			if current_bufs[b] then
				table.insert(new_order, b)
				current_bufs[b] = nil -- Remove from table to avoid duplicate insertion.
			end
		end
		-- Append any new buffers.
		for b, _ in pairs(current_bufs) do
			table.insert(new_order, b)
		end
		State.custom_order = new_order
	end
end

-- Creates a temporary, unlisted buffer for the picker.
function BufferManager.create_picker_buffer()
	local picker_buf = vim.api.nvim_create_buf(false, true)
	local buf_options = {
		buftype = "nofile",
		bufhidden = "wipe",
		swapfile = false,
		modifiable = false,
	}
	for opt, val in pairs(buf_options) do
		vim.api.nvim_set_option_value(opt, val, { buf = picker_buf })
	end

	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = picker_buf,
		callback = function()
			vim.go.guicursor = "a:SpineInvisibleCursor"
		end,
	})

	return picker_buf
end

-- Helper: returns the icon, icon's highlight group, and display name for a buffer.
local function get_buffer_display(bnr)
	local full_path = vim.api.nvim_buf_get_name(bnr)
	local name = (full_path == "" and "[No Name]") or vim.fn.fnamemodify(full_path, ":t")

	-- Extract the extension (without the leading dot)
	local ext = full_path:match("^.+%.(.+)$") or ""

	-- Retrieve the icon and icon highlight using the file name and extension.
	local icon, icon_hl = require("nvim-web-devicons").get_icon(name, ext, { default = true })

	return icon, icon_hl, name
end

-- Updates content and highlights for the picker buffer.
function BufferManager.update_buffer_lines(picker_buf)
	local lines = {}
	local max_items = math.min(#State.custom_order, #Constants.CHARACTERS)

	-- Build the lines.
	for i = 1, max_items do
		local bnr = State.custom_order[i]
		local prefix_char = Constants.CHARACTERS:sub(i, i)
		local icon, _, name = get_buffer_display(bnr)
		-- Format: prefix + "  " + icon + " " + name
		lines[i] = prefix_char .. "  " .. icon .. " " .. name
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = picker_buf })
	vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(picker_buf, State.ns_id, 0, -1)

	-- Apply highlights on each line:
	for i = 1, #lines do
		local bnr = State.custom_order[i]
		local icon, icon_hl, _ = get_buffer_display(bnr)

		local ns = State.ns_id

		-- Highlight the tag (prefix character)
		-- The tag occupies the first character (0 to 1).
		vim.api.nvim_buf_add_highlight(picker_buf, ns, "SpineTag", i - 1, 0, 1)

		-- Calculate the positions (in display cells) for icon and file name:
		-- Format: prefix_char (1 cell), "  " (2 cells), then icon, then " " then name.
		local icon_start = 3 -- 1 (prefix char) + 2 (spaces)
		local icon_width = vim.fn.strdisplaywidth(icon)
		local icon_end = icon_start + icon_width

		-- Highlight the icon with its own highlight group.
		vim.api.nvim_buf_add_highlight(picker_buf, ns, icon_hl, i - 1, icon_start, icon_end)

		-- File name highlight will start after a space following the icon.
		local name_start = icon_end + 1
		vim.api.nvim_buf_add_highlight(picker_buf, ns, "SpineFileName", i - 1, name_start, -1)
	end

	vim.api.nvim_set_option_value("modifiable", false, { buf = picker_buf })
end

-- Swap items in the custom order and update the picker.
function BufferManager.swap_items(picker_buf, idx1, idx2)
	State.custom_order[idx1], State.custom_order[idx2] = State.custom_order[idx2], State.custom_order[idx1]
	BufferManager.update_buffer_lines(picker_buf)
	Keymaps.setup_buffer_keymaps(picker_buf)
end

-------------------------------
-- Keymap Management
-------------------------------

Keymaps = {}

-- Helper to close the picker and switch to the selected buffer.
local function close_picker(bnr)
	local popup_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_close(popup_win, true)
	Settings.restore()
	if vim.api.nvim_win_is_valid(State.prev_win) then
		vim.api.nvim_set_current_win(State.prev_win)
	end
	vim.cmd("buffer " .. bnr)
end

-- Setup keymaps for the picker buffer.
function Keymaps.setup_buffer_keymaps(picker_buf)
	-- Clear previous character mappings.
	for i = 1, #Constants.CHARACTERS do
		local char = Constants.CHARACTERS:sub(i, i)
		pcall(vim.keymap.del, "n", char, { buffer = picker_buf })
	end

	-- Map each character to its corresponding buffer.
	for i = 1, #State.custom_order do
		local bnr = State.custom_order[i]
		local prefix_char = Constants.CHARACTERS:sub(i, i)
		vim.keymap.set("n", prefix_char, function()
			close_picker(bnr)
		end, { buffer = picker_buf, noremap = true, silent = true })
	end

	local function navigate_to_buffer()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_num = cursor_pos[1]
		if line_num <= #State.custom_order then
			close_picker(State.custom_order[line_num])
		end
	end

	local keymap_actions = {
		["<CR>"] = navigate_to_buffer,
		["q"] = function()
			Settings.restore()
			vim.cmd("quit")
		end,
		["<Esc>"] = function()
			Settings.restore()
			vim.cmd("quit")
		end,
		["<S-Up>"] = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum > 1 then
				BufferManager.swap_items(picker_buf, lnum, lnum - 1)
				vim.api.nvim_win_set_cursor(0, { lnum - 1, 0 })
			end
		end,
		["<S-Down>"] = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum < #State.custom_order then
				BufferManager.swap_items(picker_buf, lnum, lnum + 1)
				vim.api.nvim_win_set_cursor(0, { lnum + 1, 0 })
			end
		end,
		["<C-d>"] = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum <= #State.custom_order then
				local bnr = State.custom_order[lnum]
				vim.cmd("bdelete " .. bnr)
				table.remove(State.custom_order, lnum)
				BufferManager.update_buffer_lines(picker_buf)
				Keymaps.setup_buffer_keymaps(picker_buf)
				UI.update_window_size()
				if lnum > #State.custom_order then
					vim.api.nvim_win_set_cursor(0, { #State.custom_order, 0 })
				end
			end
		end,
		["<C-s>"] = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			if lnum <= #State.custom_order then
				local bnr = State.custom_order[lnum]
				local cur_win = vim.api.nvim_get_current_win()
				vim.api.nvim_win_close(cur_win, true)
				Settings.restore()
				if vim.api.nvim_win_is_valid(State.prev_win) then
					vim.api.nvim_set_current_win(State.prev_win)
				end
				vim.cmd("vsplit | buffer " .. bnr)
			end
		end,
		["<C-c>"] = function()
			local lnum = vim.api.nvim_win_get_cursor(0)[1]
			vim.ui.input({ prompt = "Enter new tag: ", default = "" }, function(new_tag)
				if not new_tag or new_tag == "" then
					return
				end

				local existing_pos = nil
				for i = 1, #Constants.CHARACTERS do
					if Constants.CHARACTERS:sub(i, i) == new_tag then
						existing_pos = i
						break
					end
				end

				if existing_pos then
					-- Swap with the tagged position.
					State.custom_order[lnum], State.custom_order[existing_pos] =
						State.custom_order[existing_pos], State.custom_order[lnum]
				else
					-- Append the new tag to our characters and move the current item to the end.
					Constants.CHARACTERS = Constants.CHARACTERS .. new_tag
					local current_buffer = State.custom_order[lnum]
					table.remove(State.custom_order, lnum)
					table.insert(State.custom_order, current_buffer)
				end
				BufferManager.update_buffer_lines(picker_buf)
				Keymaps.setup_buffer_keymaps(picker_buf)
			end)
		end,
		["-"] = "<nop>",
	}

	for key, action in pairs(keymap_actions) do
		vim.keymap.set("n", key, action, { buffer = picker_buf, noremap = true, silent = true })
	end
end

-------------------------------
-- Main Plugin Function
-------------------------------

function M.Open()
	-- If the picker is already open, close it.
	if State.active_popup_win and vim.api.nvim_win_is_valid(State.active_popup_win) then
		vim.api.nvim_win_close(State.active_popup_win, true)
		Settings.restore()
		State.active_popup_win = nil
		return
	end

	UI.setup_highlights()
	State.prev_win = vim.api.nvim_get_current_win()
	Settings.save()

	-- Gather buffers, preserving previous custom order.
	BufferManager.gather_buffers()

	local picker_buf = BufferManager.create_picker_buffer()
	BufferManager.update_buffer_lines(picker_buf)

	-- Update cursor highlight.
	local function update_highlight()
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
		vim.api.nvim_buf_clear_namespace(picker_buf, State.ns_id + 1, 0, -1)
		vim.api.nvim_buf_add_highlight(picker_buf, State.ns_id + 1, "SpineSelected", cursor_line, 0, -1)
	end

	vim.api.nvim_create_autocmd("CursorMoved", { buffer = picker_buf, callback = update_highlight })
	update_highlight()
	Keymaps.setup_buffer_keymaps(picker_buf)

	local dims = UI.calculate_dimensions()
	if dims.width <= 0 then
		print("[Spine] No open buffer found!")
		Settings.restore()
		return
	end

	State.active_popup_win = vim.api.nvim_open_win(picker_buf, true, {
		relative = "editor",
		row = dims.row,
		col = dims.col,
		width = dims.width + 2,
		height = dims.height,
		style = "minimal",
		border = "rounded",
		title = " Spine ",
		title_pos = "center",
	})

	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:SpineNormal,FloatBorder:SpineBorder,FloatTitle:SpineTitle",
		{ win = State.active_popup_win }
	)
end

return M
