-- Configuration module for Spine
local M = {}

-- Default configuration values
local default_config = {
	-- Characters used to label each buffer
	characters = "neiatsrchd0123456789",
	-- Highlight groups used in the plugin
	highlights = {
		SpineTag = { fg = "#d8a657", bold = true },
		SpineFileName = { fg = "#ddc7a1" },
		SpineSelected = { bg = "#504945" },
		SpineBorder = { fg = "#ddc7a1" },
		SpineTitle = { fg = "#7daea3", bold = true },
		SpineInvisibleCursor = { reverse = true, blend = 100 },
		-- (Optional) A normal highlight for the floating window
		SpineNormal = {},
	},
	-- Options for the picker buffer
	picker_buffer_options = {
		buftype = "nofile",
		bufhidden = "wipe",
		swapfile = false,
		modifiable = false,
	},
	-- Floating window options
	border = "rounded",
	title = "Spine",
	title_pos = "center",
	winhighlight = "Normal:SpineNormal,FloatBorder:SpineBorder,FloatTitle:SpineTitle",
	-- Prompt text for changing the tag
	prompt_tag = "Enter new tag: ",
	-- Reverse the order of buffers
	reverse_sort = true,
	-- Keymappings for the picker
	keys = {
		close = { "q", "<Esc>" },
		select = { "<CR>" },
		move_up = { "<S-Up>" },
		move_down = { "<S-Down>" },
		delete_buffer = { "<C-d>" },
		split_buffer = { "<C-s>" },
		change_tag = { "<C-c>" },
	},
}

-- The actual configuration that will be used
M.current = vim.deepcopy(default_config)

-- Setup function to merge user config with defaults
function M.setup(user_config)
	M.current = vim.tbl_deep_extend("force", {}, default_config, user_config or {})
end

-- Get a configuration value
function M.get(key)
	return M.current[key]
end

-- Update a specific configuration value
function M.set(key, value)
	M.current[key] = value
end

-- Update the characters configuration
function M.update_characters(new_chars)
	M.current.characters = new_chars
end

return M
