-- ui.lua

local config = require("spine.config")
local state = require("spine.state")

local M = {}

-- Setup highlight groups defined in the configuration
function M.setup_highlights()
	for group, attrs in pairs(config.get("highlights")) do
		vim.api.nvim_set_hl(0, group, attrs)
	end
end

-- Calculates dimensions for the floating window
function M.calculate_dimensions()
	local max_width = 0
	local max_items = math.min(#state.custom_order, #config.get("characters"))

	for i = 1, max_items do
		local bnr = state.custom_order[i]
		local prefix_char = config.get("characters"):sub(i, i)
		local full_path = vim.api.nvim_buf_get_name(bnr)
		local name = (full_path == "" and "[No Name]") or vim.fn.fnamemodify(full_path, ":t")
		local line = prefix_char .. "  " .. name
		max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
	end

	local total_lines, total_cols = vim.o.lines, vim.o.columns
	local height = (#state.custom_order == 0) and 1 or #state.custom_order
	local width = math.min(max_width, total_cols - 2) + 2

	return {
		width = width,
		height = height,
		row = math.floor((total_lines - height) / 2),
		col = math.floor((total_cols - width) / 2),
	}
end

-- Update the window size based on the current buffers
function M.update_window_size()
	if state.active_popup_win and vim.api.nvim_win_is_valid(state.active_popup_win) then
		local dims = M.calculate_dimensions()
		vim.api.nvim_win_set_config(state.active_popup_win, {
			relative = "editor",
			row = dims.row,
			col = dims.col,
			width = dims.width,
			height = dims.height,
		})
	end
end

return M
