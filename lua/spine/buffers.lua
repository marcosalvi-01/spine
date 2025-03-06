-- buffers.lua
-- Buffer management utilities for Spine
local config = require("spine.config")
local state = require("spine.state")
local ui = require("spine.ui")
local persistence = require("spine.persistence")

local M = {}

-- Gathers buffers and persists a custom order
function M.gather_buffers()
	local buf_array = {}

	-- If auto mode is on, gather all buffers
	if config.get("auto") then
		-- Build the list in the original order (original behavior)
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and (vim.fn.buflisted(b) == 1) then
				table.insert(buf_array, b)
			end
		end
	else
		-- In manual mode, load from saved state
		buf_array = persistence.load_project_buffers()
	end

	if config.get("reverse_sort") then
		local i, j = 1, #buf_array
		while i < j do
			buf_array[i], buf_array[j] = buf_array[j], buf_array[i]
			i = i + 1
			j = j - 1
		end
	end

	if not state.custom_order then
		state.custom_order = buf_array
	else
		-- Only perform merging logic when in auto mode
		if config.get("auto") then
			-- Build a set for fast lookup
			local current_bufs = {}
			for _, b in ipairs(buf_array) do
				current_bufs[b] = true
			end

			local new_order = {}
			local seen = {}

			-- Retain buffers that are still valid
			for _, b in ipairs(state.custom_order) do
				if current_bufs[b] then
					table.insert(new_order, b)
					seen[b] = true
				end
			end

			-- Append any new buffers
			for _, b in ipairs(buf_array) do
				if not seen[b] then
					if config.get("reverse_sort") then
						table.insert(new_order, 1, b)
					else
						table.insert(new_order, b)
					end
				end
			end

			state.custom_order = new_order
		else
			-- In manual mode, just use the filtered buf_array
			state.custom_order = buf_array
		end
	end

	-- After setting state.custom_order, save if in manual mode
	if not config.get("auto") then
		persistence.save_project_buffers(state.custom_order)
	end
end

-- Creates a temporary, unlisted buffer for the picker
function M.create_picker_buffer()
	local picker_buf = vim.api.nvim_create_buf(false, true)
	for opt, val in pairs(config.get("picker_buffer_options")) do
		vim.api.nvim_set_option_value(opt, val, { buf = picker_buf })
	end

	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = picker_buf,
		callback = function()
			vim.go.guicursor = "a:" .. "SpineInvisibleCursor"
		end,
	})

	return picker_buf
end

-- Helper: returns the icon, its highlight group, and display name for a buffer
local function get_buffer_display(bnr)
	local full_path = vim.api.nvim_buf_get_name(bnr)
	local name = (full_path == "" and "[No Name]") or vim.fn.fnamemodify(full_path, ":t")
	local ext = full_path:match("^.+%.(.+)$") or ""
	local icon, icon_hl = require("nvim-web-devicons").get_icon(name, ext, { default = true })
	return icon, icon_hl, name
end

-- Updates content and highlights for the picker buffer
function M.update_buffer_lines(picker_buf)
	local lines = {}
	local max_items = math.min(#state.custom_order, #config.get("characters"))

	for i = 1, max_items do
		local bnr = state.custom_order[i]
		local prefix_char = config.get("characters"):sub(i, i)
		local icon, _, name = get_buffer_display(bnr)
		lines[i] = prefix_char .. "  " .. icon .. " " .. name
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = picker_buf })
	vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(picker_buf, state.ns_id, 0, -1)

	for i = 1, #lines do
		local bnr = state.custom_order[i]
		local icon, icon_hl, _ = get_buffer_display(bnr)
		local ns = state.ns_id

		-- Highlight the tag (prefix character)
		vim.api.nvim_buf_add_highlight(picker_buf, ns, "SpineTag", i - 1, 0, 1)
		local icon_start = 3
		local icon_width = vim.fn.strdisplaywidth(icon)
		local icon_end = icon_start + icon_width
		vim.api.nvim_buf_add_highlight(picker_buf, ns, icon_hl, i - 1, icon_start, icon_end)
		local name_start = icon_end + 1
		vim.api.nvim_buf_add_highlight(picker_buf, ns, "SpineFileName", i - 1, name_start, -1)
	end

	vim.api.nvim_set_option_value("modifiable", false, { buf = picker_buf })
end

-- Swap two items in the custom order and update the picker
function M.swap_items(picker_buf, idx1, idx2)
	state.custom_order[idx1], state.custom_order[idx2] = state.custom_order[idx2], state.custom_order[idx1]
	M.update_buffer_lines(picker_buf)
	require("spine.keymaps").setup_buffer_keymaps(picker_buf)
end

-- manually add current buffer to the list
function M.add_current_buffer()
	local current_buf = vim.api.nvim_get_current_buf()

	-- Check if the buffer is valid for listing
	if
		not vim.api.nvim_buf_is_valid(current_buf)
		or not vim.api.nvim_buf_is_loaded(current_buf)
		or vim.fn.buflisted(current_buf) ~= 1
	then
		vim.notify("[Spine] Current buffer cannot be added.")
		return false
	end

	-- Initialize custom_order if needed
	if not state.custom_order then
		state.custom_order = {}
	end

	-- Check if the buffer is already in the list
	for _, b in ipairs(state.custom_order) do
		if b == current_buf then
			vim.notify("[Spine] Buffer already in the list.")
			return false
		end
	end

	-- Add the buffer to the list
	if config.get("reverse_sort") then
		table.insert(state.custom_order, 1, current_buf)
	else
		table.insert(state.custom_order, current_buf)
	end

	vim.notify("[Spine] Buffer added to the list.")

	-- After adding the buffer:
	if not config.get("auto") then
		persistence.save_project_buffers(state.custom_order)
	end

	return true
end

return M
