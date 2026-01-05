-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim/config.lua
-- /home/tanzious/scivim/lua/scivim
-- /home/tanzious/scivim/lua/scivim
--This file is in /lua/config.lua
-- =========================================================================
-- CONFIG - Configuration Management
-- =========================================================================
local M = {}

-- Default configuration
local DEFAULT_CONFIG = {
  -- File paths
  json_filename = ".vim_context.json",
  snippets_dir = vim.fn.stdpath("data") .. "/scivim/snippets",
  
  -- Behavior
  auto_reload = true,
  auto_show = true,
  generate_comments = true,
  scan_lines = 50,
  
  -- Visual style
  plot_theme = "darkgrid",      -- whitegrid, dark, white, ticks
  color_palette = "deep",        -- deep, muted, bright, pastel, dark, colorblind
  default_figsize = "10, 6",
  
  -- UI preferences
  telescope_layout = "horizontal",
  telescope_width = 0.55,
  telescope_height = 0.45,
  preview_width = 0.6,
  
  -- Icons
  icons = {
    chart   = " ",
    axis    = "󰆧 ",
    hue     = " ",
    size    = " ",
    title   = "󰚝 ",
    pandas  = "🐼",
    polars  = "🐻‍❄️",
    save    = " ",
    load    = " ",
    preview = " ",
  },
  
  -- Import map
  imports = {
    ["sns"] = "import seaborn as sns",
    ["plt"] = "import matplotlib.pyplot as plt",
    ["pd"]  = "import pandas as pd",
    ["pl"]  = "import polars as pl",
    ["np"]  = "import numpy as np",
  },
  
  -- Features
  features = {
    preview = false,           -- Requires image.nvim or kitty
    smart_suggestions = true,
    treesitter_imports = true,
    cache_context = true,
    wizard_history = true,
  },
}

local config = vim.deepcopy(DEFAULT_CONFIG)

--- Setup configuration
---@param user_config table|nil User configuration to merge
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end
  
  -- Ensure snippets directory exists
  vim.fn.mkdir(config.snippets_dir, "p")
end

--- Get current configuration
---@return table Configuration table
function M.get()
  return config
end

--- Get a specific config value
---@param key string Config key (supports dot notation)
---@return any Config value
function M.get_value(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = config
  
  for _, k in ipairs(keys) do
    if type(value) == "table" then
      value = value[k]
    else
      return nil
    end
  end
  
  return value
end

--- Update a config value
---@param key string Config key
---@param value any New value
function M.set_value(key, value)
  local keys = vim.split(key, ".", { plain = true })
  local target = config
  
  for i = 1, #keys - 1 do
    if type(target[keys[i]]) ~= "table" then
      target[keys[i]] = {}
    end
    target = target[keys[i]]
  end
  
  target[keys[#keys]] = value
end

--- Get icon by name
---@param name string Icon name
---@return string Icon character
function M.icon(name)
  return config.icons[name] or ""
end

--- Get import statement by alias
---@param alias string Import alias (e.g., "sns", "plt")
---@return string Import statement
function M.import(alias)
  return config.imports[alias] or ""
end

--- Check if a feature is enabled
---@param feature string Feature name
---@return boolean
function M.is_enabled(feature)
  return config.features[feature] == true
end

return M
