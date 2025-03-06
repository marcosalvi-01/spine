-- State management for Spine
local M = {}

-- Shared state
M.custom_order = nil
M.active_popup_win = nil
M.prev_win = nil
M.saved_settings = {
	guicursor = nil,
	scrolloff = nil,
	sidescrolloff = nil,
}
M.ns_id = vim.api.nvim_create_namespace("SpineHighlight")

-- Save editor settings before opening the popup
function M.save_settings()
	if not M.saved_settings.guicursor then
		M.saved_settings.guicursor = vim.go.guicursor
		M.saved_settings.scrolloff = vim.o.scrolloff
		M.saved_settings.sidescrolloff = vim.o.sidescrolloff
	end
	vim.o.scrolloff = 0
	vim.o.sidescrolloff = 0
end

-- Restore editor settings after closing the popup
function M.restore_settings()
	if M.saved_settings.guicursor then
		vim.go.guicursor = M.saved_settings.guicursor
		vim.o.scrolloff = M.saved_settings.scrolloff
		vim.o.sidescrolloff = M.saved_settings.sidescrolloff
		M.saved_settings.guicursor = nil
		M.saved_settings.scrolloff = nil
		M.saved_settings.sidescrolloff = nil
	end
end

return M
