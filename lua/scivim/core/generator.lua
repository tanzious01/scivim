-- lua/scivim/core/generator.lua
local M = {}
local config = require("scivim.config")

-- Helper to safely load adapters
local function load_adapter(type, name)
  local ok, adapter = pcall(require, "scivim.core.adapters." .. type .. "." .. name)
  if not ok then
    vim.notify("Could not load " .. type .. " adapter: " .. name, vim.log.levels.ERROR)
    return nil
  end
  return adapter
end

-- [[ NEW: Helper to expose the active adapter to the UI ]]
function M.get_active_plot_adapter()
  local cfg = config.get()
  local plot_name = cfg.plot_backend or "seaborn"
  return load_adapter("plot", plot_name)
end

-- [[ NEW: Filter charts based on backend support ]]
function M.get_available_charts()
  local cfg = config.get()
  local all_charts = require("scivim.core.charts").CHART_TYPES
  
  local adapter = M.get_active_plot_adapter()
  if not adapter then return all_charts end 

  local filtered = {}
  
  for _, chart in ipairs(all_charts) do
    local is_supported = false
    
    -- Check 1: Explicit list (Bokeh style)
    if adapter.supported_charts and adapter.supported_charts[chart.id] then
      is_supported = true
    -- Check 2: Mappings table (Seaborn style)
    elseif adapter.mappings and adapter.mappings[chart.id] then
      is_supported = true
    end
    
    if is_supported then
      table.insert(filtered, chart)
    end
  end
  
  return filtered
end

function M.generate(spec)
  local cfg = config.get()
  local lines = {}

  -- 1. LOAD ADAPTERS
  local lib_name = spec.lib or "pandas"
  local data_adapter = load_adapter("data", lib_name)
  local plot_adapter = M.get_active_plot_adapter()

  if not data_adapter or not plot_adapter then return end

  -- 2. BUILD CODE
  table.insert(lines, "# %% [Viz: " .. (spec.chart.name or "Plot") .. "]")
  
  -- Imports
  if plot_adapter.imports then
    vim.list_extend(lines, plot_adapter.imports)
  end
  
  -- Theme
  if plot_adapter.configure_theme then
    local theme_line = plot_adapter.configure_theme(spec.theme or cfg.plot_theme, spec.palette or cfg.color_palette)
    if theme_line and theme_line ~= "" then
        table.insert(lines, theme_line)
    end
  end

  -- Data Prep
  local plot_var = spec.df
  if spec.filter and spec.filter ~= "" then
      plot_var = "plot_data"
      table.insert(lines, plot_var .. " = " .. data_adapter.filter(spec.df, spec.filter))
  end
  
  -- Normalization
  if data_adapter.normalize then
    local final_var = data_adapter.normalize(plot_var)
    if final_var ~= plot_var then
        plot_var = "plot_df"
        table.insert(lines, plot_var .. " = " .. final_var)
    end
  end

  -- Plot Command
  local plot_cmd = plot_adapter.generate_plot(spec.chart.id, plot_var, spec)
  if plot_cmd then
    table.insert(lines, plot_cmd)
  end
  
  -- Title
  if spec.title and spec.title ~= "" then
     if lines[#lines]:match("^ax%s*=") then
         table.insert(lines, string.format("ax.set_title('%s')", spec.title))
     elseif not (cfg.plot_backend == "bokeh") then
         -- Matplotlib fallback for title
         table.insert(lines, string.format("plt.title('%s')", spec.title))
     end
  end

  -- Show Command
  if cfg.auto_show and plot_adapter.show then
      table.insert(lines, plot_adapter.show())
  end
  
  table.insert(lines, "") 

  -- 3. INSERT INTO BUFFER
  if #lines > 0 then
    vim.api.nvim_put(lines, "l", true, true)
  end

  return lines
end

return M
