-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- =========================================================================
-- CLIENT - Persistent Python Daemon Client
-- =========================================================================
local M = {}

local paths = require("scivim.backend.paths")

local daemon_state = {
  job_id = nil,
  stdout_buffer = "",
  callback_queue = {}, -- FIFO queue for pending requests
}

local function get_script_path()
   return paths.get_daemon_script()
end

--- Restart or Start the Python Daemon
function M.ensure_daemon()
  if daemon_state.job_id and vim.fn.jobwait({daemon_state.job_id}, 0)[1] == -1 then
    return -- Already running
  end

  local script_path = get_script_path()
  local python_cmd = vim.g.python3_host_prog or "python3"

  daemon_state.stdout_buffer = ""
  daemon_state.callback_queue = {}

  daemon_state.job_id = vim.fn.jobstart({python_cmd, script_path}, {
    on_stdout = function(_, data, _)
      if not data then return end
      
      -- 1. Append new data to buffer
      for i, chunk in ipairs(data) do
        daemon_state.stdout_buffer = daemon_state.stdout_buffer .. chunk
        if i < #data then
          daemon_state.stdout_buffer = daemon_state.stdout_buffer .. "\n"
        end
      end

      -- 2. Process complete lines (JSON objects)
      while true do
        local line_end = string.find(daemon_state.stdout_buffer, "\n")
        if not line_end then break end

        local line = string.sub(daemon_state.stdout_buffer, 1, line_end - 1)
        daemon_state.stdout_buffer = string.sub(daemon_state.stdout_buffer, line_end + 1)

        if line ~= "" then
          local callback = table.remove(daemon_state.callback_queue, 1)
          if callback then
            local ok, parsed = pcall(vim.json.decode, line)
            local result = ok and parsed or { error = "JSON Parse Fail: " .. line }
            
            vim.schedule(function()
              callback(result)
            end)
          end
        end
      end
    end,

    on_stderr = function(_, data, _)
      -- Optional: Log stderr for debugging daemon crashes
    end,

    on_exit = function(_, code, _)
      daemon_state.job_id = nil
      -- Flush queue with errors so UI doesn't hang forever
      for _, cb in ipairs(daemon_state.callback_queue) do
        cb({ error = "Daemon process crashed or exited (Code: " .. code .. ")" })
      end
      daemon_state.callback_queue = {}
    end,
    
    detach = false, 
  })
end

--- Send a request to the persistent daemon
function M.run_transform_async(df_name, lib, is_lazy, code, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." })
    return -1
  end

  local temp_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  local file_path = ""

  -- Only resolve specific file path if a specific DF is requested
  if df_name and df_name ~= "" then
      local feather_path = temp_dir .. "/" .. df_name .. ".feather"
      local pkl_path = temp_dir .. "/" .. df_name .. ".pkl"

      file_path = pkl_path
      if vim.fn.filereadable(feather_path) == 1 then
          file_path = feather_path
      end
  end

  local input_data = {
    type = "transform",
    file_path = file_path,
    cache_dir = temp_dir, -- [[ NEW: Explicit Cache Dir for Workspace Loading ]]
    lib = lib,
    is_lazy = is_lazy,
    code = code
  }

  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
  return daemon_state.job_id
end

-- [[ NEW: RPC for Preview Generation ]]
function M.generate_preview(code, out_path, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  
  local input_data = {
    type = "preview",
    code = code,
    out_path = out_path,
    cache_dir = cache_dir
  }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

function M.get_all_metadata(names, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  
  local input_data = {
    type = "metadata_all",
    cache_dir = cache_dir,
    names = names
  }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

function M.analyze_relationships(callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  local input_data = { type = "analyze_relationships", cache_dir = cache_dir }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

function M.stop_daemon()
  if daemon_state.job_id then
    vim.fn.jobstop(daemon_state.job_id)
    daemon_state.job_id = nil
  end
end

return M
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend
-- /home/tanzious/scivim/lua/scivim/backend
-- lua/scivim/backend/paths.lua
local M = {}

function M.get_plugin_root()
  -- Get the path to this file, then go up 4 levels to the root
  local current_file = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(current_file, ":h:h:h:h")
end

-- This was missing!
function M.get_python_root()
  return M.get_plugin_root() .. "/python/scivim/"
end

function M.get_daemon_script()
  return M.get_python_root() .. "daemon.py"
end

return M
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/pandas.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/pandas.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/pandas.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/pandas.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/pandas.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/pandas.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data
-- /home/tanzious/scivim/lua/scivim/core/adapters/data
--This file is in /lua/core/adapters/data/pandas.lua

local M = {}

-- Returns the import string required for this library
function M.get_import()
  return "import pandas as pd"
end

-- Returns code to filter data
function M.filter(df_var, condition)
  -- Smart check: is it a query string or a python expression?
  if condition:match(df_var) or condition:match("df%[") then
    return condition
  end
  return string.format("%s.query(\"%s\")", df_var, condition)
end

-- Returns code to aggregate data
function M.agg(df_var, group_cols, target_col, func)
  return string.format("%s.groupby('%s')['%s'].%s().reset_index()", 
    df_var, group_cols, target_col, func)
end

-- Returns code to convert to a format plotting libraries understand (usually pandas)
function M.normalize(df_var)
  return df_var -- It's already pandas
end

return M
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/polars.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/polars.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/polars.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/polars.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/polars.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data/polars.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/data
-- /home/tanzious/scivim/lua/scivim/core/adapters/data

--This file is in /lua/core/adapters/data/polars.lua

local M = {}

function M.get_import()
  return "import polars as pl"
end

function M.filter(df_var, condition)
  return string.format("%s.filter(%s)", df_var, condition)
end

function M.agg(df_var, group_cols, target_col, func)
  -- Polars syntax is very different
  return string.format("%s.group_by('%s').agg(pl.col('%s').%s())", 
    df_var, group_cols, target_col, func)
end

function M.normalize(df_var)
  -- Most plotters don't speak Polars natively yet, so we convert
  return string.format("%s.to_pandas()", df_var)
end

return M
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot
local M = {}
local config = require("scivim.config")

-- [[ CAPABILITIES ]]
M.supported_charts = {
  ["scatter"] = true,
  ["line"] = true,
  ["bar"] = true,
  ["area"] = true,
  ["step"] = true,
  ["log_scatter"] = true,
  ["hist"] = true,
  ["box"] = true,
  ["violin"] = true,
  ["splom"] = true
}

M.themes = { "default", "dark_minimal", "light_minimal", "night_sky", "contrast", "caliber" }
M.palettes = { "Category10", "Dark2", "Spectral", "Viridis", "Magma", "Inferno", "Turbo" }

M.imports = {
  "from bokeh.plotting import figure, show",
  "from bokeh.models import ColumnDataSource, HoverTool",
  "from bokeh.layouts import gridplot",
  "from bokeh.io import output_notebook, curdoc, export_png",
  "from bokeh.transform import factor_cmap",
  "import numpy as np",
  "import pandas as pd"
}

function M.configure_theme(theme, palette)
  local lines = {}
  local is_valid = false
  for _, t in ipairs(M.themes) do
    if t == theme then is_valid = true; break end
  end

  if is_valid and theme ~= "default" then
      table.insert(lines, string.format("curdoc().theme = '%s'", theme))
  end
  return table.concat(lines, "\n")
end

function M.generate_plot(chart_id, data_var, params)
  local lines = {}
  local title = params.title or (chart_id .. " Plot")
  local x = params.x
  local y = params.y

  -- [[ 1. HISTOGRAM ]] --
  if chart_id == "hist" then
    -- Ensure numeric
    table.insert(lines, string.format("hist_data = pd.to_numeric(%s['%s'], errors='coerce').dropna()", data_var, x))
    table.insert(lines, string.format("hist, edges = np.histogram(hist_data, bins=%s)", params.bins or 20))
    table.insert(lines, string.format(
      "p = figure(title='%s', x_axis_label='%s', y_axis_label='Count')", title, x))
    table.insert(lines, "p.quad(top=hist, bottom=0, left=edges[:-1], right=edges[1:], line_color='white', alpha=0.7)")

  -- [[ 2. BOX PLOT ]] --
  elseif chart_id == "box" then
    table.insert(lines, "# Data Prep for Box Plot")
    -- FIX: Force Y to numeric to prevent 'object' dtype crash
    table.insert(lines, string.format("%s['%s'] = pd.to_numeric(%s['%s'], errors='coerce')", data_var, y, data_var, y))
    table.insert(lines, string.format("df_box = %s.dropna(subset=['%s', '%s'])", data_var, x, y))
    
    table.insert(lines, string.format("cats = df_box['%s'].astype(str).unique()", x))
    table.insert(lines, string.format("groups = df_box.groupby('%s')", x))
    
    -- Quantiles
    table.insert(lines, string.format("q1 = groups['%s'].quantile(0.25)", y))
    table.insert(lines, string.format("q2 = groups['%s'].quantile(0.5)", y))
    table.insert(lines, string.format("q3 = groups['%s'].quantile(0.75)", y))
    table.insert(lines, "iqr = q3 - q1")
    table.insert(lines, "upper = q3 + 1.5 * iqr")
    table.insert(lines, "lower = q1 - 1.5 * iqr")
    
    -- Figure
    table.insert(lines, string.format(
      "p = figure(title='%s', x_range=list(cats), x_axis_label='%s', y_axis_label='%s')", 
      title, x, y))
    
    -- Draw
    table.insert(lines, "p.segment(cats, upper, cats, q3, line_color='white')")
    table.insert(lines, "p.segment(cats, lower, cats, q1, line_color='white')")
    table.insert(lines, "p.vbar(x=cats, width=0.7, bottom=q2, top=q3, fill_color='#E0E0E0', line_color='black')")
    table.insert(lines, "p.vbar(x=cats, width=0.7, bottom=q1, top=q2, fill_color='#E0E0E0', line_color='black')")

  -- [[ 3. VIOLIN PLOT ]] --
  elseif chart_id == "violin" then
    table.insert(lines, "from scipy.stats import gaussian_kde")
    -- FIX: Force Y to numeric
    table.insert(lines, string.format("%s['%s'] = pd.to_numeric(%s['%s'], errors='coerce')", data_var, y, data_var, y))
    
    table.insert(lines, string.format(
      "p = figure(title='%s', x_range=list(%s['%s'].unique().astype(str)), x_axis_label='%s', y_axis_label='%s')", 
      title, data_var, x, x, y))
      
    table.insert(lines, string.format("for cat in %s['%s'].unique():", data_var, x))
    table.insert(lines, string.format("    subset = %s[%s['%s'] == cat]['%s'].dropna()", data_var, data_var, x, y))
    table.insert(lines, "    if len(subset) > 1:")
    table.insert(lines, "        kde = gaussian_kde(subset)")
    table.insert(lines, "        y_range = np.linspace(subset.min(), subset.max(), 100)")
    table.insert(lines, "        density = kde(y_range)")
    table.insert(lines, "        density = density / density.max() * 0.4")
    table.insert(lines, "        p.varea(x=y_range, y1=cat, y2=density, level='overlay')")

  -- [[ 4. SPLOM ]] --
  elseif chart_id == "splom" then
    table.insert(lines, "from itertools import product")
    table.insert(lines, string.format("columns = [c for c in %s.columns if pd.api.types.is_numeric_dtype(%s[c])]", data_var, data_var))
    table.insert(lines, string.format("source = ColumnDataSource(%s)", data_var))
    table.insert(lines, "plots = []")
    table.insert(lines, "N = len(columns)")
    table.insert(lines, "for i, (y_col, x_col) in enumerate(product(columns, reversed(columns))):")
    table.insert(lines, "    p = figure(width=200, height=200, min_border=10)")
    table.insert(lines, "    p.scatter(x=x_col, y=y_col, source=source, size=5, alpha=0.6)")
    table.insert(lines, "    if i % N == 0: p.yaxis.axis_label = y_col")
    table.insert(lines, "    if i >= N * (N - 1): p.xaxis.axis_label = x_col")
    table.insert(lines, "    plots.append(p)")
    table.insert(lines, "p = gridplot(plots, ncols=N)")

  -- [[ 5. STANDARD PLOTS ]] --
  else
    table.insert(lines, string.format("source = ColumnDataSource(%s)", data_var))
    
    local tooltips = ""
    if x and y then tooltips = string.format(", tooltips=[('%s', '@%s'), ('%s', '@%s')]", x, x, y, y) end
    
    local y_axis_type = "linear"
    if chart_id == "log_scatter" then y_axis_type = "log" end

    table.insert(lines, string.format(
      "p = figure(title='%s', x_axis_label='%s', y_axis_label='%s', y_axis_type='%s'%s)", 
      title, x or "x", y or "y", y_axis_type, tooltips
    ))

    if chart_id == "scatter" or chart_id == "log_scatter" then
      table.insert(lines, string.format("p.scatter(x='%s', y='%s', source=source, size=%s, alpha=%s)", 
        x, y, params.size or 10, params.alpha or 0.6))
        
    elseif chart_id == "line" then
      table.insert(lines, string.format("p.line(x='%s', y='%s', source=source, line_width=2)", x, y))
      table.insert(lines, string.format("p.circle(x='%s', y='%s', source=source, size=4)", x, y))
      
    elseif chart_id == "step" then
      table.insert(lines, string.format("p.step(x='%s', y='%s', source=source, line_width=2, mode='center')", x, y))
      
    elseif chart_id == "area" then
      table.insert(lines, string.format("p.varea(x='%s', y1=0, y2='%s', source=source, alpha=%s)", x, y, params.alpha or 0.5))
      table.insert(lines, string.format("p.line(x='%s', y='%s', source=source, line_width=2)", x, y))
      
    elseif chart_id == "bar" then
      table.insert(lines, string.format("p.vbar(x='%s', top='%s', source=source, width=0.9)", x, y))
    end
  end

  return table.concat(lines, "\n")
end

function M.show()
  local cfg = config.get()
  
  if cfg.bokeh_output == "png" or cfg.features.preview then
      return [[
try:
    export_png(p, filename="plot.png")
    print("Exported to plot.png")
except:
    print("Export failed (missing Selenium?). Opening in browser...")
    show(p)
]]
  else
      return "show(p)"
  end
end

return M
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/plotly.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/plotly.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/plotly.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/plotly.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/plotly.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/plotly.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot
local M = {}

-- [[ CAPABILITIES ]]
M.supported_charts = {
  ["scatter"] = true,
  ["line"] = true,
  ["bar"] = true,
  ["hist"] = true,
  ["box"] = true,
  ["violin"] = true,
  ["heat"] = true,
  ["area"] = true,
  ["pie"] = true,
  ["density_heatmap"] = true,
  -- Advanced / Multivariate
  ["scatter3d"] = true,
  ["parcoords"] = true,
  ["sankey"] = true,     -- Implemented via parallel_categories for EDA flow
  ["sunburst"] = true,
  ["treemap"] = true,
}

M.themes = { "plotly", "plotly_white", "plotly_dark", "ggplot2", "seaborn", "simple_white", "none" }
M.palettes = { "Viridis", "Plasma", "Inferno", "Magma", "Turbo", "Cividis", "Deep" }

M.imports = {
  "import plotly.express as px",
  "import plotly.io as pio",
  "import pandas as pd" 
}

-- Map chart IDs to Plotly Express functions
M.mappings = {
  scatter    = "px.scatter",
  line       = "px.line",
  bar        = "px.bar",
  hist       = "px.histogram",
  box        = "px.box",
  violin     = "px.violin",
  heat       = "px.imshow",
  area       = "px.area",
  strip      = "px.strip",
  density    = "px.density_contour",
  -- Advanced
  scatter3d  = "px.scatter_3d",
  parcoords  = "px.parallel_coordinates", -- for continuous vars
  sankey     = "px.parallel_categories",  -- 'parcats' is the closest Express equivalent to Sankey
  sunburst   = "px.sunburst",
  treemap    = "px.treemap",
}

-- Map SciVim generic themes to Plotly templates
local theme_map = {
  darkgrid  = "plotly_dark",
  whitegrid = "seaborn",
  dark      = "plotly_dark",
  white     = "simple_white",
  ticks     = "ggplot2"
}

function M.configure_theme(theme, palette)
  local plotly_theme = theme_map[theme] or theme
  return string.format("pio.templates.default = '%s'", plotly_theme)
end

function M.generate_plot(chart_id, data_var, params)
  local func = M.mappings[chart_id]
  
  -- Special handling for Correlation Matrix
  if chart_id == "heat" then
      return string.format("fig = px.imshow(%s.corr(), text_auto=True, title='%s')", data_var, params.title or "Correlation Matrix")
  end

  if not func then return nil end

  local args = { data_var }
  local kwargs = {}

  -- == 1. DATA MAPPING LOGIC ==
  
  -- A. 3D PLOTS
  if chart_id == "scatter3d" then
      if params.x then table.insert(kwargs, string.format("x='%s'", params.x)) end
      if params.y then table.insert(kwargs, string.format("y='%s'", params.y)) end
      if params.z then table.insert(kwargs, string.format("z='%s'", params.z)) end
  
  -- B. HIERARCHICAL (Sunburst / Treemap)
  -- Logic: Combine X, Y, Z, Hue into the hierarchy 'path' list
  elseif chart_id == "sunburst" or chart_id == "treemap" then
      local path_cols = {}
      if params.x then table.insert(path_cols, params.x) end
      if params.y then table.insert(path_cols, params.y) end
      if params.z then table.insert(path_cols, params.z) end
      -- Note: 'hue' is usually used for color, not hierarchy path in px
      
      if #path_cols > 0 then
          local path_str = "['" .. table.concat(path_cols, "', '") .. "']"
          table.insert(kwargs, string.format("path=%s", path_str))
      end
      
      -- Use 'size' param for values if provided, otherwise count is default
      if params.size then 
          table.insert(kwargs, string.format("values='%s'", params.size)) 
      end

  -- C. FLOW (Sankey / Parallel Categories)
  -- Logic: Use X, Y, Z, Hue as dimensions
  elseif chart_id == "sankey" or chart_id == "parcoords" then
      -- If user provided specific columns, use them as dimensions
      local dims = {}
      if params.x then table.insert(dims, params.x) end
      if params.y then table.insert(dims, params.y) end
      if params.z then table.insert(dims, params.z) end
      
      if #dims > 0 then
          local dim_str = "['" .. table.concat(dims, "', '") .. "']"
          table.insert(kwargs, string.format("dimensions=%s", dim_str))
      end
      
      -- Parcoords often needs a color column
      if params.hue then 
          table.insert(kwargs, string.format("color='%s'", params.hue)) 
      end

  -- D. STANDARD PLOTS
  else
      if params.x then table.insert(kwargs, string.format("x='%s'", params.x)) end
      if params.y then table.insert(kwargs, string.format("y='%s'", params.y)) end
  end

  -- == 2. COMMON AESTHETICS ==
  
  -- Color (Hue) - Skip for parcoords/sankey as handled above
  if params.hue and chart_id ~= "parcoords" and chart_id ~= "sankey" then 
      table.insert(kwargs, string.format("color='%s'", params.hue)) 
  end
  
  -- Size (Bubble charts) - Skip for hierarchy (handled as 'values')
  if params.size and chart_id ~= "sunburst" and chart_id ~= "treemap" then 
      table.insert(kwargs, string.format("size='%s'", params.size)) 
  end
  
  if params.title then table.insert(kwargs, string.format("title='%s'", params.title)) end
  
  -- Chart specific adjustments
  if chart_id == "hist" and params.bins then
      table.insert(kwargs, string.format("nbins=%s", params.bins))
  end
  
  if chart_id == "scatter" or chart_id == "scatter3d" then
      if params.alpha then table.insert(kwargs, string.format("opacity=%s", params.alpha)) end
  end
  
  if chart_id == "box" or chart_id == "violin" then
      table.insert(kwargs, "points='all'")
  end
  
  -- == 3. BUILD STRING ==
  local kwargs_str = table.concat(kwargs, ", ")
  if #kwargs > 0 then
      return string.format("fig = %s(%s, %s)", func, table.concat(args, ", "), kwargs_str)
  else
      return string.format("fig = %s(%s)", func, table.concat(args, ", "))
  end
end

function M.show()
  return "fig.show()"
end

return M
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/seaborn.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/seaborn.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/seaborn.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/seaborn.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/seaborn.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/seaborn.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot
local M = {}

-- [[ DEFINITIONS: Options specific to Seaborn ]]
M.themes = { "darkgrid", "whitegrid", "dark", "white", "ticks" }
M.palettes = { "deep", "muted", "pastel", "bright", "dark", "colorblind", "viridis", "magma", "rocket", "mako" }

M.imports = {
  "import seaborn as sns",
  "import matplotlib.pyplot as plt"
}

-- Map generic chart IDs to specific library functions
M.mappings = {
  scatter = "sns.scatterplot",
  hist    = "sns.histplot",
  box     = "sns.boxplot",
  line    = "sns.lineplot",
  bar     = "sns.barplot",
  violin  = "sns.violinplot",
  kde     = "sns.kdeplot",
  count   = "sns.countplot",
  strip   = "sns.stripplot",
  swarm   = "sns.swarmplot",
  point   = "sns.pointplot",
  heat    = "sns.heatmap",
  pair    = "sns.pairplot",
  joint   = "sns.jointplot",
  lm      = "sns.lmplot",
}

function M.configure_theme(theme, palette)
  return string.format("sns.set_theme(style='%s', palette='%s')", theme, palette)
end

function M.generate_plot(chart_id, data_var, params)
  local func = M.mappings[chart_id]
  if not func then return nil end -- Not supported

  local args = { "data=" .. data_var }
  
  -- Add standard args (x, y, hue)
  if params.x then table.insert(args, string.format("x='%s'", params.x)) end
  if params.y then table.insert(args, string.format("y='%s'", params.y)) end
  if params.hue then table.insert(args, string.format("hue='%s'", params.hue)) end
  
  -- Add specific args if present
  if params.bins then table.insert(args, string.format("bins=%s", params.bins)) end
  if params.kde ~= nil then table.insert(args, string.format("kde=%s", params.kde and "True" or "False")) end
  if params.alpha then table.insert(args, string.format("alpha=%s", params.alpha)) end
  
  return string.format("ax = %s(%s)", func, table.concat(args, ", "))
end

function M.show()
  return "plt.show()"
end

return M
-- /home/tanzious/scivim/lua/scivim/core/charts.lua
-- /home/tanzious/scivim/lua/scivim/core/charts.lua
-- /home/tanzious/scivim/lua/scivim/core/charts.lua
-- /home/tanzious/scivim/lua/scivim/core/charts.lua
-- /home/tanzious/scivim/lua/scivim/core/charts.lua
-- /home/tanzious/scivim/lua/scivim/core/charts.lua
-- /home/tanzious/scivim/lua/scivim/core
-- /home/tanzious/scivim/lua/scivim/core
--This file is in /lua/core/charts.lua
-- =========================================================================
-- CHARTS - Visualization Definitions
-- =========================================================================
local M = {}

M.CHART_TYPES = {
  -- -------------------------------------------------------------------------
  -- RELATIONAL
  -- -------------------------------------------------------------------------
  { 
    name = "Scatter Plot", 
    id = "scatter", 
    icon = "󰄄", 
    category = "relational",
    req = {"x", "y"}, 
    opt = {"hue", "style", "size", "alpha"},
    desc = "Visualizes relationship between two continuous variables." 
  },
  { 
    name = "Line Plot", 
    id = "line", 
    icon = "", 
    category = "relational",
    req = {"x"}, 
    opt = {"y", "hue", "style", "markers"}, 
    desc = "Displays data trends over time or an ordered series." 
  },
  { 
    name = "Step Plot", 
    id = "step", 
    icon = "󰐕", 
    category = "relational", 
    req = {"x", "y"}, 
    opt = {"hue", "where"},
    desc = "Step line plot. Good for discrete changes over time." 
  },
  { 
    name = "Area Plot", 
    id = "area", 
    icon = "", 
    category = "relational", 
    req = {"x", "y"}, 
    opt = {"hue", "alpha"},
    desc = "Filled area plot. Useful for showing volume or accumulation." 
  },
  { 
    name = "Log-Scale Scatter", 
    id = "log_scatter", 
    icon = "󰄄", 
    category = "relational", 
    req = {"x", "y"}, 
    opt = {"hue", "size"},
    desc = "Scatter plot with Logarithmic Y-Axis." 
  },
  { 
    name = "Linear Regression", 
    id = "lm", 
    icon = "📈", 
    category = "relational",
    req = {"x", "y"}, 
    opt = {"hue", "col"}, 
    desc = "Scatter plot with a linear regression model fit." 
  },
  
  -- -------------------------------------------------------------------------
  -- DISTRIBUTION
  -- -------------------------------------------------------------------------
  { 
    name = "Histogram", 
    id = "hist", 
    icon = "📊", 
    category = "distribution",
    req = {"x"}, 
    opt = {"hue", "kde", "bins"},
    desc = "Binned frequency distribution of a variable." 
  },
  { 
    name = "KDE Plot", 
    id = "kde", 
    icon = "〰", 
    category = "distribution",
    req = {"x"}, 
    opt = {"hue", "fill"},
    desc = "Kernel Density Estimate. A smooth version of a histogram." 
  },
  { 
    name = "Violin Plot", 
    id = "violin", 
    icon = "", 
    category = "distribution", 
    req = {"x", "y"}, 
    opt = {"hue"},
    desc = "Shows the probability density of the data at different values." 
  },
  { 
    name = "Joint Plot", 
    id = "joint", 
    icon = "並", 
    category = "distribution",
    req = {"x", "y"}, 
    opt = {"hue", "kind"}, 
    desc = "Bivariate plot with marginal univariate distributions." 
  },

  -- -------------------------------------------------------------------------
  -- CATEGORICAL
  -- -------------------------------------------------------------------------
  { 
    name = "Box Plot", 
    id = "box", 
    icon = "󰡃", 
    category = "categorical",
    req = {"x", "y"}, 
    opt = {"hue"}, 
    desc = "Shows quartiles, median, and outliers." 
  },
  { 
    name = "Bar Plot", 
    id = "bar", 
    icon = "📊", 
    category = "categorical",
    req = {"x", "y"}, 
    opt = {"hue"}, 
    desc = "Point estimates (mean) with confidence intervals." 
  },
  { 
    name = "Count Plot", 
    id = "count", 
    icon = "", 
    category = "categorical",
    req = {"x"}, 
    opt = {"hue"}, 
    desc = "Shows the count of observations in each categorical bin." 
  },
  { 
    name = "Strip Plot", 
    id = "strip", 
    icon = "", 
    category = "categorical",
    req = {"x", "y"}, 
    opt = {"hue", "jitter"}, 
    desc = "Simple categorical scatter plot showing all data points." 
  },

  -- -------------------------------------------------------------------------
  -- MATRIX
  -- -------------------------------------------------------------------------
  { 
    name = "Heatmap (Corr)", 
    id = "heat", 
    icon = "▦", 
    category = "matrix",
    req = {}, 
    opt = {"cmap"},
    desc = "Visualizes the correlation matrix of numeric columns." 
  },
  { 
    name = "Pair Plot", 
    id = "pair", 
    icon = "", 
    category = "matrix",
    req = {}, 
    opt = {"hue"},
    desc = "Plot pairwise relationships in a dataset." 
  },
  { 
    name = "Scatter Matrix (SPLOM)", 
    id = "splom", 
    icon = "▦", 
    category = "matrix", 
    req = {}, 
    opt = {"hue"},
    desc = "Grid of scatter plots showing relationships between numeric variables." 
  },
{ 
    name = "Parallel Coordinates", 
    id = "parcoords", 
    icon = "", 
    category = "multivariate",
    req = {}, 
    opt = {"hue"}, -- In Plotly, color is used for the lines
    desc = "Visualizes high-dimensional data as lines across parallel axes." 
  },
  { 
    name = "3D Scatter", 
    id = "scatter3d", 
    icon = "🧊", 
    category = "multivariate", 
    req = {"x", "y", "z"}, 
    opt = {"hue", "size"},
    desc = "Scatter plot in three dimensions. Good for PCA/Clustering." 
  },
  { 
    name = "Sunburst", 
    id = "sunburst", 
    icon = "◎", 
    category = "hierarchical", 
    req = {"x"}, -- In this context, 'x' will be the list of path columns
    opt = {"y"}, -- 'y' can be the 'values' (size of wedge)
    desc = "Hierarchical data represented by concentric rings." 
  },
  { 
    name = "Sankey", 
    id = "sankey", 
    icon = "ﬡ", 
    category = "flow", 
    req = {"source", "target", "value"}, -- Requires custom mapping logic in Wizard
    opt = {}, 
    desc = "Flow diagram where width of arrows is proportional to flow rate." 
  },












}

function M.get_chart(chart_id)
  for _, chart in ipairs(M.CHART_TYPES) do
    if chart.id == chart_id then
      return chart
    end
  end
  return nil
end

return M
-- /home/tanzious/scivim/lua/scivim/core/context.lua
-- /home/tanzious/scivim/lua/scivim/core/context.lua
-- /home/tanzious/scivim/lua/scivim/core/context.lua
-- /home/tanzious/scivim/lua/scivim/core/context.lua
-- /home/tanzious/scivim/lua/scivim/core/context.lua
-- /home/tanzious/scivim/lua/scivim/core/context.lua
-- /home/tanzious/scivim/lua/scivim/core
-- /home/tanzious/scivim/lua/scivim/core
-- This file is in /lua/core/context.lua
-- =========================================================================
-- CONTEXT - Data Loading & Management (Core)
-- =========================================================================
local M = {}

local config = require("scivim.config")

local context_cache = {
  all_data = nil,
  active_df_name = nil,
  mtime = nil,
}

--- Load ALL contexts from JSON file
function M.load_all()
  local cfg = config.get()
  local filename = cfg.json_filename
  
  if cfg.features.cache_context and context_cache.all_data and context_cache.mtime then
    local stat = vim.loop.fs_stat(filename)
    if stat and stat.mtime.sec == context_cache.mtime then
      return context_cache.all_data, nil
    end
  end
  
  local ok, content = pcall(vim.fn.readfile, filename)
  if not ok then 
    return nil, "Run `vim_expose()` in Python first.\nFile not found: " .. filename
  end
  
  local json_str = table.concat(content, "\n")
  local parse_ok, data = pcall(vim.json.decode, json_str)
  if not parse_ok then
    return nil, "Failed to parse JSON: " .. tostring(data)
  end
  
  if type(data) ~= "table" or vim.tbl_isempty(data) then
     return nil, "No DataFrames found in context file."
  end
  
  if cfg.features.cache_context then
    local stat = vim.loop.fs_stat(filename)
    context_cache.all_data = data
    context_cache.mtime = stat and stat.mtime.sec or nil
  end
  
  return data, nil
end

--- Get the currently active DataFrame context
function M.get_active()
  local all_data, err = M.load_all()
  if not all_data then return nil, err end

  if context_cache.active_df_name and all_data[context_cache.active_df_name] then
    return all_data[context_cache.active_df_name], nil
  end
  
  local df_names = vim.tbl_keys(all_data)
  if #df_names > 0 then
    context_cache.active_df_name = df_names[1]
    return all_data[context_cache.active_df_name], nil
  end
  
  return nil, "No DataFrames found in context file."
end

--- Set the currently active DataFrame by name
function M.set_active(name)
  local all_data, err = M.load_all()
  if not all_data then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if all_data[name] then
    context_cache.active_df_name = name
    vim.notify("📊 Active DataFrame set to: " .. name, vim.log.levels.INFO)
  else
    vim.notify("DataFrame not found: " .. name, vim.log.levels.ERROR)
  end
end

function M.reload()
  context_cache.all_data = nil
  context_cache.mtime = nil
  return M.get_active()
end

-- Helper: Map JSON metadata to internal structure
function M.create_column_entry(col_name, meta, index)
  meta = meta or {}
  return {
    index = index or 0,
    name = col_name,
    dtype = meta.dtype or "unknown",
    null_count = meta.null_count or 0,
    unique_count = meta.unique_count or "?",
    -- Numeric Stats
    min_val = meta.min_val,
    max_val = meta.max_val,
    mean_val = meta.mean_val,
    std_val = meta.std_val,
    median_val = meta.median_val,
    -- Boxplot Stats
    q1 = meta.q1,
    q3 = meta.q3,
    outlier_count = meta.outlier_count or 0,
    -- Distribution Data
    sample_values = meta.sample_values or {},
    hist_counts = meta.hist_counts,
  }
end

-- Helper: Check if dtype is numeric
function M._is_numeric(dtype)
  if not dtype then return false end
  local d = dtype:lower()
  return d:match("int") or d:match("float") or d:match("double") or d:match("number")
end

return M
-- /home/tanzious/scivim/lua/scivim/core/generator.lua
-- /home/tanzious/scivim/lua/scivim/core/generator.lua
-- /home/tanzious/scivim/lua/scivim/core/generator.lua
-- /home/tanzious/scivim/lua/scivim/core/generator.lua
-- /home/tanzious/scivim/lua/scivim/core/generator.lua
-- /home/tanzious/scivim/lua/scivim/core/generator.lua
-- This file is in /lua/scivim/core/generator.lua
local M = {}
local config = require("scivim.config")

-- CACHE: Store loaded adapters to avoid pcall/require overhead
local _adapter_cache = { data = {}, plot = {} }

-- Helper to safely load adapters with caching
local function load_adapter(type, name)
  if _adapter_cache[type][name] then
      return _adapter_cache[type][name]
  end

  local ok, adapter = pcall(require, "scivim.core.adapters." .. type .. "." .. name)
  if not ok then
    -- Don't cache nil, allow retry if user fixes config
    vim.notify("Could not load " .. type .. " adapter: " .. name, vim.log.levels.ERROR)
    return nil
  end
  
  _adapter_cache[type][name] = adapter
  return adapter
end

-- Expose active adapter
function M.get_active_plot_adapter()
  local cfg = config.get()
  local plot_name = cfg.plot_backend or "seaborn"
  return load_adapter("plot", plot_name)
end

-- Filter charts based on backend support
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

    -- [[ OPTIMIZATION: Auto-Run with Molten ]]
    -- If Molten is installed and configured, run the block immediately
    local has_molten = (vim.fn.exists(":MoltenEvaluateVisual") == 2)
    
    if has_molten and cfg.features.auto_run ~= false then
        -- Calculate range of inserted text
        local end_line = vim.api.nvim_win_get_cursor(0)[1]
        local start_line = end_line - #lines + 1
        
        -- Run Molten on the inserted range
        vim.cmd(string.format(":%d,%dMoltenEvaluateVisual", start_line, end_line))
        
        -- Move cursor to end
        vim.api.nvim_win_set_cursor(0, {end_line, 0})
    end
  end

  return lines
end

return M
-- /home/tanzious/scivim/lua/scivim/core/snippets.lua
-- /home/tanzious/scivim/lua/scivim/core/snippets.lua
-- /home/tanzious/scivim/lua/scivim/core/snippets.lua
-- /home/tanzious/scivim/lua/scivim/core/snippets.lua
-- /home/tanzious/scivim/lua/scivim/core/snippets.lua
-- /home/tanzious/scivim/lua/scivim/core/snippets.lua
-- /home/tanzious/scivim/lua/scivim/core
-- /home/tanzious/scivim/lua/scivim/core
-- This file is in /lua/core/snippets.lua
--  =========================================================================
-- SNIPPETS - Save and Load Visualization Snippets (Snacks Edition)
-- =========================================================================
local M = {}

-- UPDATED IMPORTS:
local config = require("scivim.config")
local generator = require("scivim.core.generator")
local Snacks = require("snacks")

--- Get snippets file path
local function get_snippets_file()
  local cfg = config.get()
  return cfg.snippets_dir .. "/snippets.json"
end

--- Load all snippets from disk
local function load_snippets()
  local file = get_snippets_file()
  local ok, content = pcall(vim.fn.readfile, file)
  if not ok then return {} end
  
  local json_str = table.concat(content, "\n")
  local parse_ok, data = pcall(vim.json.decode, json_str)
  return parse_ok and data or {}
end

--- Save snippets to disk
local function save_snippets(snippets)
  local file = get_snippets_file()
  local json_str = vim.json.encode(snippets)
  vim.fn.writefile(vim.split(json_str, "\n"), file)
end

--- Save current visualization as a snippet
function M.save(name)
  if not name or name == "" then
    vim.notify("Snippet name cannot be empty", vim.log.levels.ERROR)
    return
  end
  
  local lines = generator.get_last_viz_code and generator.get_last_viz_code() or {}
  -- Note: You might need to expose get_last_viz_code in generator.lua if strictly hidden,
  -- or rely on the buffer content if the generator isn't caching it.
  
  -- Fallback: If generator doesn't cache, we can't save easily without grabbing buffer lines.
  -- Assuming generator has this method (it was in your original snippets.lua)
  
  if #lines == 0 then
    vim.notify("No visualization code found (Generator state empty)", vim.log.levels.WARN)
    return
  end
  
  local snippets = load_snippets()
  snippets[name] = {
    code = lines,
    created = os.time(),
    description = lines[1] or "",
  }
  
  save_snippets(snippets)
  vim.notify(config.icon("save") .. " Saved snippet: " .. name, vim.log.levels.INFO)
end

--- Load a snippet (Simple UI)
function M.load()
  M.list() -- Re-use the list UI for loading
end

--- List all snippets (Snacks Picker)
function M.list()
  local snippets = load_snippets()
  
  if vim.tbl_isempty(snippets) then
    vim.notify("No saved snippets found", vim.log.levels.WARN)
    return
  end

  local items = {}
  for name, snip in pairs(snippets) do
    table.insert(items, {
      text = name,
      snippet = snip,
      created = os.date("%Y-%m-%d", snip.created)
    })
  end

  Snacks.picker.pick({
    items = items,
    title = "📚 Visualization Snippets",
    layout = "vscode",
    
    format = function(item)
      return {
        { "🔖 ", "SnacksIcon" },
        { item.text, "Normal" },
        { "  " },
        { item.created, "Comment" }
      }
    end,
    
    preview = function(ctx)
      local code = ctx.item.snippet.code
      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, code)
      vim.bo[ctx.buf].modifiable = false
      vim.bo[ctx.buf].filetype = "python"
    end,
    
    confirm = function(picker, item)
      picker:close()
      local cursor = vim.api.nvim_win_get_cursor(0)
      vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, item.snippet.code)
      vim.notify(config.icon("load") .. " Loaded: " .. item.text, vim.log.levels.INFO)
    end,
    
    win = {
      input = {
        keys = {
          ["<c-d>"] = { "delete_snippet", mode = { "n", "i" } },
        }
      }
    },
    
    actions = {
      delete_snippet = function(picker, item)
        picker:close()
        M.delete(item.text)
        -- Re-open after delete
        vim.schedule(function() M.list() end)
      end
    }
  })
end

--- Delete a snippet
function M.delete(name)
  local snippets = load_snippets()
  if not snippets[name] then return end
  
  snippets[name] = nil
  save_snippets(snippets)
  vim.notify("🗑️  Deleted snippet: " .. name, vim.log.levels.INFO)
end

return M
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core
-- /home/tanzious/scivim/lua/scivim/core
-- =========================================================================
-- S-TATS - Statistical Annotations and Enhancements
-- =========================================================================
local M = {}

local config = require("scivim.config")

-- Statistical features available for each chart type
M.STATS_FEATURES = {
  scatter = {
    { id = "corr", name = "Correlation Coefficient", desc = "Add Pearson r and p-value" },
    { id = "regline", name = "Regression Line", desc = "Add best-fit line" },
    { id = "ci", name = "Confidence Interval", desc = "Add 95% confidence band" },
  },
  box = {
    { id = "mean", name = "Mean Markers", desc = "Show mean values" },
    { id = "sig", name = "Significance Tests", desc = "Add statistical significance indicators" },
    { id = "outliers", name = "Highlight Outliers", desc = "Mark outliers in red" },
  },
  hist = {
    { id = "normal", name = "Normal Curve", desc = "Overlay normal distribution" },
    { id = "mean", name = "Mean Line", desc = "Vertical line at mean" },
    { id = "median", name = "Median Line", desc = "Vertical line at median" },
    { id = "kde", name = "KDE Overlay", desc = "Add kernel density estimate" },
  },
  violin = {
    { id = "quartiles", name = "Quartile Lines", desc = "Show Q1, Q2, Q3" },
    { id = "mean", name = "Mean Points", desc = "Add mean markers" },
  },
  bar = {
    { id = "values", name = "Value Labels", desc = "Show bar values on top" },
    { id = "sig", name = "Significance Bars", desc = "Add significance brackets" },
  },
  line = {
    { id = "ci", name = "Confidence Interval", desc = "Add shaded confidence band" },
    { id = "trend", name = "Trend Line", desc = "Add polynomial trend" },
  },
}

--- Get available stats for a chart type
---@param chart_id string Chart identifier
---@return table|nil Available stats features
function M.get_available_stats(chart_id)
  return M.STATS_FEATURES[chart_id]
end

--- Prompt user to select statistical enhancements
---@param spec table Visualization spec
---@param callback function Callback with updated spec
function M.select_stats(spec, callback)
  local available = M.get_available_stats(spec.chart.id)
  
  if not available or #available == 0 then
    callback(spec)
    return
  end
  
  local items = {}
  for _, stat in ipairs(available) do
    table.insert(items, stat.name)
  end
  table.insert(items, 1, "(None)")
  
  vim.ui.select(items, {
    prompt = "📊 Add Statistical Features:",
    format_item = function(item)
      if item == "(None)" then
        return item
      end
      for _, stat in ipairs(available) do
        if stat.name == item then
          return stat.name .. " - " .. stat.desc
        end
      end
      return item
    end,
  }, function(choice)
    if not choice or choice == "(None)" then
      callback(spec)
      return
    end
    
    -- Find selected stat
    for _, stat in ipairs(available) do
      if stat.name == choice then
        spec.stats = spec.stats or {}
        table.insert(spec.stats, stat.id)
        break
      end
    end
    
    callback(spec)
  end)
end

--- Generate statistical enhancement code
---@param spec table Visualization spec
---@return table Code lines to append
function M.generate_stats_code(spec)
  if not spec.stats or #spec.stats == 0 then
    return {}
  end
  
  local lines = {}
  
  for _, stat_id in ipairs(spec.stats) do
    local stat_lines = M._generate_stat(stat_id, spec)
    vim.list_extend(lines, stat_lines)
  end
  
  return lines
end

--- Generate code for specific statistical feature
---@param stat_id string Statistical feature ID
---@param spec table Visualization spec
---@return table Code lines
function M._generate_stat(stat_id, spec)
  local lines = {}
  local cfg = config.get()
  
  -- Correlation coefficient for scatter plots
  if stat_id == "corr" then
    if cfg.generate_comments then
      table.insert(lines, "# Add correlation coefficient")
    end
    table.insert(lines, "from scipy import stats as scipy_stats")
    table.insert(lines, string.format(
      "r, p = scipy_stats.pearsonr(%s['%s'].dropna(), %s['%s'].dropna())",
      spec.df, spec.x, spec.df, spec.y
    ))
    table.insert(lines, "plt.text(0.05, 0.95, f'r = {r:.3f}, p = {p:.3f}',")
    table.insert(lines, "         transform=plt.gca().transAxes, fontsize=10,")
    table.insert(lines, "         verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))")
  
  -- Regression line
  elseif stat_id == "regline" then
    if cfg.generate_comments then
      table.insert(lines, "# Add regression line")
    end
    table.insert(lines, "import numpy as np")
    table.insert(lines, string.format("x_data = %s['%s'].dropna()", spec.df, spec.x))
    table.insert(lines, string.format("y_data = %s['%s'].dropna()", spec.df, spec.y))
    table.insert(lines, "z = np.polyfit(x_data, y_data, 1)")
    table.insert(lines, "p = np.poly1d(z)")
    table.insert(lines, "plt.plot(x_data, p(x_data), 'r--', alpha=0.8, linewidth=2)")
  
  -- Mean line for histogram
  elseif stat_id == "mean" and spec.chart.id == "hist" then
    if cfg.generate_comments then
      table.insert(lines, "# Add mean line")
    end
    table.insert(lines, string.format("mean_val = %s['%s'].mean()", spec.df, spec.x))
    table.insert(lines, "plt.axvline(mean_val, color='red', linestyle='--', linewidth=2, label=f'Mean: {mean_val:.2f}')")
    table.insert(lines, "plt.legend()")
  
  -- Median line for histogram
  elseif stat_id == "median" then
    if cfg.generate_comments then
      table.insert(lines, "# Add median line")
    end
    table.insert(lines, string.format("median_val = %s['%s'].median()", spec.df, spec.x))
    table.insert(lines, "plt.axvline(median_val, color='green', linestyle='--', linewidth=2, label=f'Median: {median_val:.2f}')")
    table.insert(lines, "plt.legend()")
  
  -- Normal curve overlay
  elseif stat_id == "normal" then
    if cfg.generate_comments then
      table.insert(lines, "# Add normal distribution overlay")
    end
    table.insert(lines, "import numpy as np")
    table.insert(lines, "from scipy.stats import norm")
    table.insert(lines, string.format("mu = %s['%s'].mean()", spec.df, spec.x))
    table.insert(lines, string.format("sigma = %s['%s'].std()", spec.df, spec.x))
    table.insert(lines, string.format("x_range = np.linspace(%s['%s'].min(), %s['%s'].max(), 100)", 
      spec.df, spec.x, spec.df, spec.x))
    table.insert(lines, "plt.plot(x_range, norm.pdf(x_range, mu, sigma) * len(" .. spec.df .. 
      ") * (x_range[1] - x_range[0]), 'r-', linewidth=2, label='Normal')")
    table.insert(lines, "plt.legend()")
  
  -- KDE overlay for histogram
  elseif stat_id == "kde" then
    if cfg.generate_comments then
      table.insert(lines, "# Add KDE overlay")
    end
    table.insert(lines, string.format("sns.kdeplot(data=%s, x='%s', color='red', linewidth=2)", 
      spec.df, spec.x))
  
  -- Mean markers for box/violin plots
  elseif stat_id == "mean" and (spec.chart.id == "box" or spec.chart.id == "violin") then
    if cfg.generate_comments then
      table.insert(lines, "# Add mean markers")
    end
    table.insert(lines, "plt.gca().scatter([], [], marker='D', color='red', s=100, label='Mean', zorder=3)")
    table.insert(lines, "# Note: Use showmeans=True in plot function for automatic mean markers")
  
  -- Value labels for bar plots
  elseif stat_id == "values" then
    if cfg.generate_comments then
      table.insert(lines, "# Add value labels")
    end
    table.insert(lines, "ax = plt.gca()")
    table.insert(lines, "for container in ax.containers:")
    table.insert(lines, "    ax.bar_label(container, fmt='%.2f')")
  
  -- Confidence interval
  elseif stat_id == "ci" then
    if cfg.generate_comments then
      table.insert(lines, "# Confidence interval already included in plot")
    end
    -- Most seaborn plots include CI by default
  
  -- Significance tests (placeholder)
  elseif stat_id == "sig" then
    if cfg.generate_comments then
      table.insert(lines, "# Statistical significance testing")
      table.insert(lines, "# TODO: Add your significance test logic here")
    end
  end
  
  return lines
end

--- Add statistical summary text box
---@param spec table Visualization spec
---@return table Code lines
function M.add_summary_box(spec)
  local lines = {}
  local cfg = config.get()
  
  if cfg.generate_comments then
    table.insert(lines, "# Add statistical summary box")
  end
  
  if spec.x and spec.y then
    table.insert(lines, string.format(
      "summary = %s[['%s', '%s']].describe()",
      spec.df, spec.x, spec.y
    ))
  elseif spec.x then
    table.insert(lines, string.format(
      "summary = %s['%s'].describe()",
      spec.df, spec.x
    ))
  end
  
  table.insert(lines, "summary_text = summary.to_string()")
  table.insert(lines, "plt.text(1.02, 0.5, summary_text, transform=plt.gca().transAxes,")
  table.insert(lines, "         fontsize=8, verticalalignment='center',")
  table.insert(lines, "         bbox=dict(boxstyle='round', facecolor='lightgray', alpha=0.5))")
  
  return lines
end

--- Quick statistical test between groups
---@param df_name string DataFrame name
---@param x_col string X column (groups)
---@param y_col string Y column (values)
---@return table Code lines for t-test or ANOVA
function M.generate_test_code(df_name, x_col, y_col)
  local lines = {}
  
  table.insert(lines, "# Statistical test")
  table.insert(lines, "from scipy import stats as scipy_stats")
  table.insert(lines, "")
  table.insert(lines, string.format("groups = %s.groupby('%s')['%s'].apply(list)", 
    df_name, x_col, y_col))
  table.insert(lines, "")
  table.insert(lines, "# Perform one-way ANOVA")
  table.insert(lines, "f_stat, p_value = scipy_stats.f_oneway(*groups)")
  table.insert(lines, "print(f'F-statistic: {f_stat:.4f}')")
  table.insert(lines, "print(f'P-value: {p_value:.4f}')")
  table.insert(lines, "")
  table.insert(lines, "if p_value < 0.05:")
  table.insert(lines, "    print('Significant difference between groups (p < 0.05)')")
  table.insert(lines, "else:")
  table.insert(lines, "    print('No significant difference between groups (p >= 0.05)')")
  
  return lines
end

return M
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui
--This file is in  lua/scivim/ui/explorer.lua
local M = {}
local executor = require("scivim.backend.client")
local context = require("scivim.core.context")
local Snacks = require("snacks")

local state = {
  mode = "list", -- 'list' or 'graph'
  dfs = {},
  rels = {},
  win_list = nil,
  win_preview = nil
}

--- Show DataFrame explorer with previews
function M.show_explorer()
  -- 1. Get Source of Truth (Current Session)
  local all_data = context.load_all()
  
  if not all_data or vim.tbl_count(all_data) == 0 then
      vim.notify("No active DataFrames found. Run vim_expose() in your kernel.", vim.log.levels.WARN)
      return
  end
  
  -- 2. Extract Valid Names
  local active_names = vim.tbl_keys(all_data)
  
  -- 3. Fetch Metadata
  executor.get_all_metadata(active_names, function(meta_resp)
    if meta_resp.error then 
        vim.notify("Error: " .. meta_resp.error, vim.log.levels.ERROR)
        return 
    end
    
    -- 4. Fetch Relationships
    executor.analyze_relationships(function(rel_resp)
      -- Process DataFrames
      local df_list = {}
      for name, info in pairs(meta_resp.dataframes or {}) do
        table.insert(df_list, {
          name = name,
          shape = info.shape or {0, 0},
          columns = info.columns or {},
          head = info.head or ""
        })
      end
      
      -- Process Relationships
      local rel_list = rel_resp.relationships or {}

      if #df_list == 0 then 
          vim.notify("No DataFrames found in cache.", vim.log.levels.WARN)
          return 
      end

      -- Init State
      state.dfs = df_list
      state.rels = rel_list
      state.mode = "list"
      
      M._render_ui()
    end)
  end)
end

function M._render_ui()
  -- Calculate Layout
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local list_width = 40
  local preview_width = width - list_width - 2 -- minus borders
  
  -- Prepare Content
  local left_lines = {}
  local title = ""
  local footer = " <Tab> Switch View • <CR> Actions • q Quit "
  local title_hl = "Title"

  if state.mode == "list" then
      title = " 🐼 Active DataFrames "
      title_hl = "String" -- Greenish usually
      for _, df in ipairs(state.dfs) do
        local dim_str = string.format("(%d x %d)", df.shape[1] or 0, df.shape[2] or 0)
        -- Pad spaces for alignment
        local padding = string.rep(" ", list_width - #df.name - #dim_str - 6)
        table.insert(left_lines, string.format(" %s%s%s ", df.name, padding, dim_str))
      end
  else
      title = " 🕸️  Data Relationships "
      title_hl = "Special" -- Blue/Purple usually
      if #state.rels == 0 then
          table.insert(left_lines, "")
          table.insert(left_lines, "  (No obvious joins detected)")
      else
          for _, r in ipairs(state.rels) do
             -- Shorten if too long
             local rel_str = string.format("%s -> %s", r.from_df, r.to_df)
             table.insert(left_lines, " " .. rel_str)
          end
      end
  end

  -- Close existing windows if open (redraw)
  if state.win_list then state.win_list:close(); state.win_preview:close() end

  -- 1. ACTION HANDLER (Press Enter)
  local function open_actions()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list.win)
      local idx = cursor[1]
      
      if state.mode ~= "list" then return end
      
      local df_meta = state.dfs[idx]
      if not df_meta then return end
      
      -- Load Full Context
      local all_data = context.load_all()
      local ctx = all_data[df_meta.name]
      if not ctx then return end

      state.win_list:close()
      state.win_preview:close()

      Snacks.picker.pick({
          items = {
              { text = "📊 Visualize (Wizard)",  action = "viz", icon = "📈" },
              { text = "🛠️  Transform (Python)", action = "py",  icon = "🐍" },
              { text = "🦆 Query (SQL)",        action = "sql", icon = "💾" },
              { text = "🔍 Inspect Columns",    action = "insp", icon = "🔎" },
          },
          title = " Action: " .. ctx.name .. " ",
          layout = "vscode",
          confirm = function(picker, item)
              picker:close()
              if item.action == "viz" then require("scivim.ui.wizard").start(ctx)
              elseif item.action == "py" then require("scivim.ui.transform")._launch_python_transform(ctx)
              elseif item.action == "sql" then require("scivim.ui.sql_transform").launch(ctx)
              elseif item.action == "insp" then require("scivim.ui.inspector")._inspect_snacks(ctx)
              end
          end
      })
  end

  -- 2. CREATE LIST WINDOW
  state.win_list = Snacks.win({
    relative = "editor", row = row, col = col, width = list_width, height = height,
    border = "rounded", 
    title = title, title_pos = "center",
    footer = footer, footer_pos = "center",
    wo = { cursorline = true, winhighlight = "FloatBorder:FloatBorder,Title:"..title_hl },
    keys = {
        ["q"] = "close", ["<Esc>"] = "close",
        ["<Tab>"] = function() 
            state.mode = (state.mode == "list") and "graph" or "list"
            M._render_ui() 
        end,
        ["<CR>"] = open_actions
    }
  })
  vim.api.nvim_buf_set_lines(state.win_list.buf, 0, -1, false, left_lines)
  
  -- 3. CREATE PREVIEW WINDOW
  state.win_preview = Snacks.win({
    relative = "editor", row = row, col = col + list_width + 1, width = preview_width, height = height,
    border = "rounded", title = " Details ", title_pos = "center", interactive = false,
    wo = { winhighlight = "FloatBorder:FloatBorder" }
  })
  
  -- 4. PREVIEW UPDATER LOGIC
  local function update_preview()
    if not vim.api.nvim_win_is_valid(state.win_list.win) then return end
    local cursor = vim.api.nvim_win_get_cursor(state.win_list.win)
    local idx = cursor[1]
    local p_lines = {}
    local p_title = " Details "

    if state.mode == "list" then
        local df = state.dfs[idx]
        if df then
            p_title = string.format(" %s ", df.name)
            
            -- Header
            table.insert(p_lines, string.format("📐 Shape: %d rows x %d cols", df.shape[1], df.shape[2]))
            table.insert(p_lines, string.rep("─", preview_width))
            
            -- Columns formatted nicely
            table.insert(p_lines, "📋 Columns:")
            local col_chunk_size = math.ceil(#df.columns / 2) -- split into 2 cols if needed
            for i, c in ipairs(df.columns) do
                 if i > 20 then 
                    table.insert(p_lines, string.format("  ... (%d more)", #df.columns - 20))
                    break 
                 end
                 table.insert(p_lines, string.format("  • %s", c))
            end
            
            table.insert(p_lines, "")
            table.insert(p_lines, string.rep("─", preview_width))
            table.insert(p_lines, "👓 Head:")
            
            -- Add Head content (handling raw string from pandas to_string)
            for _, l in ipairs(vim.split(df.head, '\n')) do
                table.insert(p_lines, "  " .. l)
            end
        end
    else
        -- Relationship Mode
        local r = state.rels[idx]
        if r then
             p_title = " Relationship Info "
             table.insert(p_lines, "")
             table.insert(p_lines, " 🔗 JOIN SUGGESTION")
             table.insert(p_lines, string.rep("─", 40))
             table.insert(p_lines, string.format(" Left:  %s", r.from_df))
             table.insert(p_lines, string.format(" Right: %s", r.to_df))
             table.insert(p_lines, "")
             table.insert(p_lines, string.format(" Key:   %s == %s", r.from_col, r.to_col))
             table.insert(p_lines, string.format(" Type:  %s", r.type))
             table.insert(p_lines, "")
             table.insert(p_lines, " 📝 SQL Pattern:")
             table.insert(p_lines, " ```sql")
             table.insert(p_lines, string.format(" SELECT * FROM %s a", r.from_df))
             table.insert(p_lines, string.format(" JOIN %s b ON a.%s = b.%s", r.to_df, r.from_col, r.to_col))
             table.insert(p_lines, " ```")
        else
             table.insert(p_lines, " No relationship selected.")
        end
    end
    
    -- Highlight SQL/Code in preview
    if state.mode == "graph" then vim.bo[state.win_preview.buf].filetype = "markdown" 
    else vim.bo[state.win_preview.buf].filetype = "text" end

    vim.api.nvim_buf_set_lines(state.win_preview.buf, 0, -1, false, p_lines)
    pcall(vim.api.nvim_win_set_config, state.win_preview.win, { title = p_title })
  end

  -- Navigation Binds
  local buf = state.win_list.buf
  vim.keymap.set('n', 'j', function() vim.cmd('normal! j'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', 'k', function() vim.cmd('normal! k'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', '<Down>', function() vim.cmd('normal! j'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', '<Up>', function() vim.cmd('normal! k'); update_preview() end, { buffer = buf })
  
  -- Initial Render
  update_preview()
end

return M
-- /home/tanzious/scivim/lua/scivim/ui/inspector.lua
-- /home/tanzious/scivim/lua/scivim/ui/inspector.lua
-- /home/tanzious/scivim/lua/scivim/ui/inspector.lua
-- /home/tanzious/scivim/lua/scivim/ui/inspector.lua
-- /home/tanzious/scivim/lua/scivim/ui/inspector.lua
-- /home/tanzious/scivim/lua/scivim/ui/inspector.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui

--This file is in  lua/scivim/ui/inspector.lua
-- =========================================================================
-- INSPECTOR - Data Inspection UI (Snacks)
-- =========================================================================
local M = {}

local context = require("scivim.core.context")
local generator = require("scivim.core.generator")
local charts = require("scivim.core.charts")
local config = require("scivim.config")
local Snacks = require("snacks")

-- Increased width for the preview panel
local CONTENT_WIDTH = 100 

-- =========================================================================
-- MAIN ENTRY POINT
-- =========================================================================

function M.show()
  local all_data, err = context.load_all()
  if not all_data then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  -- Convert map to list
  local ctx_list = {}
  for _, data in pairs(all_data) do
    table.insert(ctx_list, data)
  end

  if #ctx_list == 0 then
    vim.notify("No DataFrames exposed via vim_expose()", vim.log.levels.WARN)
    return
  elseif #ctx_list == 1 then
    -- Only one? Just show it.
    context.set_active(ctx_list[1].name)
    M._inspect_snacks(ctx_list[1])
  else
    -- More than one? Force the user to choose.
    M._pick_dataframe(ctx_list)
  end
end

function M._pick_dataframe(ctx_list)
  local items = {}
  for _, ctx in ipairs(ctx_list) do
    local icon = ctx.lib == "polars" and config.icon("polars") or config.icon("pandas")
    
    table.insert(items, {
      text = ctx.name,
      ctx = ctx,
      icon = icon,
      comment = string.format("(%d cols)", #ctx.columns)
    })
  end

  Snacks.picker.pick({
    items = items,
    title = "Select DataFrame to Inspect",
    layout = "vscode",
    format = function(item)
      return {
        { item.icon, "SnacksIcon" },
        { " " },
        { item.text, "Normal" },
        { "  " },
        { item.comment, "Comment" }
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        context.set_active(item.ctx.name)
        M._inspect_snacks(item.ctx)
      end
    end
  })
end

function M._inspect_snacks(ctx)
  local items = {}
  
  for i, col_name in ipairs(ctx.columns) do
    local meta = ctx.metadata and ctx.metadata[col_name] or {}
    local col_data = context.create_column_entry(col_name, meta, i)
    
    local icon = "󰙨" 
    local comment = col_data.dtype
    
    if context._is_numeric(col_data.dtype) then 
        icon = "󰎠"
        if col_data.outlier_count and col_data.outlier_count > 0 then
            comment = comment .. " (⚠️ " .. col_data.outlier_count .. ")"
        end
    elseif col_data.dtype:match("date") or col_data.dtype:match("time") then 
        icon = "󰃰" 
    elseif col_data.dtype:match("bool") then 
        icon = "󰨙" 
    end

    table.insert(items, {
      text = col_name,
      idx = i,
      icon = icon,
      col = col_data, 
      comment = comment
    })
  end

  local function generate_plot_action(picker, item)
    picker:close()
    M._quick_visualize_column(ctx, item.col)
  end

  local function copy_name(picker, item)
    picker:close()
    vim.fn.setreg('+', item.text)
    vim.notify("Copied: " .. item.text)
  end
  
  local function insert_code(picker, item)
    picker:close()
    local code = ctx.lib == "polars" and string.format('pl.col("%s")', item.text) or string.format("%s['%s']", ctx.name or "df", item.text)
    vim.api.nvim_put({code}, "c", true, true)
  end

  Snacks.picker.pick({
    source = "scivim_columns",
    items = items,
    title = string.format("DataFrame: %s (%s)", ctx.name, ctx.lib or "pandas"),
    
    layout = {
      layout = {
        box = "horizontal",
        width = 0.9,
        height = 0.9,
        {
          box = "vertical",
          border = "rounded",
          title = "{title} {live} {flags}",
          width = 0.3,
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        {
          win = "preview",
          title = "{preview}",
          border = "rounded",
          width = 0.7,
        },
      }
    },
    
    format = function(item)
      local ret = {
        { string.format("%2d", item.idx), "Comment" },
        { " " },
        { item.icon, "SnacksIcon" },
        { " " },
        { item.text, "Normal" },
      }
      if item.comment:match("⚠️") then
        table.insert(ret, { " " .. item.comment, "WarningMsg" })
      else
        table.insert(ret, { " " .. item.comment, "Comment" })
      end
      return ret
    end,

    preview = function(p_ctx)
      local item = p_ctx.item
      local lines = M.get_column_preview_lines(item.col)
      
      vim.bo[p_ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(p_ctx.buf, 0, -1, false, lines)
      vim.bo[p_ctx.buf].modifiable = false
      
      local ns = vim.api.nvim_create_namespace("scivim_inspect")
      for i, line in ipairs(lines) do
        if line:match("^%s*📦") or line:match("^%s*📋") or line:match("^%s*📈") or line:match("^%s*📊") or line:match("^%s*🧠") then
          vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Title", i - 1, 0, -1)
        elseif line:match("│") or line:match("├") or line:match("╔") or line:match("─") then
          vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Comment", i - 1, 0, -1)
        elseif line:match("⚠️") then
           vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "WarningMsg", i - 1, 0, -1)
        end
        
        local start_idx = 1
        while true do
            local s, e = string.find(line, "[▂▃▄▅▆▇█]+", start_idx)
            if not s then break end
            vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Function", i - 1, s - 1, e)
            start_idx = e + 1
        end
      end
    end,

    confirm = function(picker) picker:close() end,
    
    win = {
      input = {
        keys = {
          ["<C-y>"] = { "copy_col_name", desc = "Copy Name", mode = { "i", "n" } },
          ["<C-i>"] = { "insert_col_code", desc = "Insert Code", mode = { "i", "n" } },
          ["<C-g>"] = { "generate_plot", desc = "Generate Plot", mode = { "i", "n" } },
        }
      },
      list = { keys = { ["gp"] = "generate_plot" } }
    },
    actions = {
      copy_col_name = copy_name,
      insert_col_code = insert_code,
      generate_plot = generate_plot_action,
    }
  })
end

-- =========================================================================
-- PREVIEW GENERATION UTILITIES (PUBLIC)
-- =========================================================================

function M._str_width(str)
  return vim.fn.strdisplaywidth(str)
end

function M._pad_string(str, target_width)
  local current_width = M._str_width(str)
  if current_width >= target_width then
    return vim.fn.strcharpart(str, 0, target_width)
  end
  return str .. string.rep(" ", target_width - current_width)
end

function M.get_column_preview_lines(col)
  local lines = {}
  local width = CONTENT_WIDTH
  
  -- 1. TITLE
  table.insert(lines, "")
  table.insert(lines, " 📦 COLUMN: " .. col.name)
  table.insert(lines, " " .. string.rep("═", width))

  -- 2. INFO & HEALTH
  table.insert(lines, "")
  table.insert(lines, " 📋 BASIC INFO")
  table.insert(lines, " " .. string.rep("─", width))
  
  local info_str = string.format("  Type: %-10s  Nulls: %-6d  Unique: %s", col.dtype, col.null_count, col.unique_count)
  table.insert(lines, info_str)
  
  local quality_score = 100
  if type(col.null_count) == "number" and type(col.unique_count) == "number" then
    local total = (col.unique_count > 0 and col.null_count + col.unique_count * 2) or 1
    quality_score = math.floor(100 - (col.null_count / total * 100))
  end
  local q_bar = M._generate_bar(quality_score, 20)
  table.insert(lines, string.format("  Health: %s %d%%", q_bar, quality_score))
  
  -- 3. INSIGHTS
  if context._is_numeric(col.dtype) and col.mean_val then
      table.insert(lines, "")
      table.insert(lines, " 🧠 INSIGHTS")
      table.insert(lines, " " .. string.rep("─", width))
      
      local diff = (col.mean_val - col.median_val)
      local range = (col.max_val - col.min_val)
      
      local shape = "Symmetric"
      if range > 0 then
         local skew = diff/range
         if skew > 0.05 then shape = "Right Skewed (Tail ->)"
         elseif skew < -0.05 then shape = "Left Skewed (<- Tail)" end
      end
      
      local volatility = "Stable"
      if col.std_val and col.mean_val ~= 0 then
          local cv = math.abs(col.std_val/col.mean_val)
          if cv > 1 then volatility = "High (Volatile)"
          elseif cv > 0.5 then volatility = "Moderate" end
          volatility = volatility .. string.format(" (CV: %.2f)", cv)
      end
      
      local outlier_txt = "Clean"
      if col.outlier_count > 0 then outlier_txt = string.format("⚠️ %d Found", col.outlier_count) end

      table.insert(lines, string.format("  Shape:    %-25s Outliers: %s", shape, outlier_txt))
      table.insert(lines, string.format("  Spread:   %-25s", volatility))
  end

  -- 4. METRICS
  if context._is_numeric(col.dtype) and col.min_val then
      table.insert(lines, "")
      table.insert(lines, " 📈 KEY METRICS")
      table.insert(lines, " " .. string.rep("─", width))
      
      local function row(l1, v1, l2, v2)
          return string.format("  %-10s %12.4f      %-10s %12.4f", l1, v1, l2, v2)
      end
      
      table.insert(lines, row("Min:", col.min_val, "Max:", col.max_val))
      table.insert(lines, row("Mean:", col.mean_val, "Median:", col.median_val))
      if col.std_val then
         table.insert(lines, string.format("  %-10s %12.4f", "Std Dev:", col.std_val))
      end
      
      if col.min_val ~= col.max_val then
          table.insert(lines, "")
          table.insert(lines, "  Box Plot:")
          local box_lines = M._generate_boxplot_viz(col, width - 4)
          vim.list_extend(lines, box_lines)
      end
  end

  -- 5. CHARTS (Uses full width)
  if context._is_numeric(col.dtype) and col.hist_counts and #col.hist_counts > 0 then
      table.insert(lines, "")
      table.insert(lines, " 📊 HISTOGRAM")
      table.insert(lines, " " .. string.rep("─", width))
      local hist = M._render_counts_histogram(col.hist_counts, col.min_val, col.max_val, width - 4)
      vim.list_extend(lines, hist)
  elseif col.sample_values and #col.sample_values > 0 and not context._is_numeric(col.dtype) then
      table.insert(lines, "")
      table.insert(lines, " 📊 TOP VALUES")
      table.insert(lines, " " .. string.rep("─", width))
      local freq = M._render_categorical_freq(col.sample_values, width - 4)
      vim.list_extend(lines, freq)
  end

  -- 6. DATA
  table.insert(lines, "")
  table.insert(lines, " 👓 RAW DATA SAMPLE")
  table.insert(lines, " " .. string.rep("─", width))
  if col.sample_values and #col.sample_values > 0 then
      local tbl = M._render_column_table(col, width - 4)
      vim.list_extend(lines, tbl)
  else
      table.insert(lines, "  (No sample data)")
  end
  
  return lines
end

function M._generate_bar(percentage, width)
  local filled = math.floor(percentage / 100 * width)
  local empty = width - filled
  return string.rep("█", filled) .. string.rep("░", empty)
end

function M._render_column_table(col, max_width)
  local lines = {}
  local max_rows = 5 
  local samples = col.sample_values or {}
  
  local col_width = 30
  if (col_width + 8) > max_width then col_width = max_width - 8 end

  local sep = "  ├────┼" .. string.rep("─", col_width + 2) .. "┤"
  local top = "  ┌────┬" .. string.rep("─", col_width + 2) .. "┐"
  local bot = "  └────┴" .. string.rep("─", col_width + 2) .. "┘"
  
  table.insert(lines, top)
  table.insert(lines, string.format("  │ #  │ %s │", M._pad_string(col.name, col_width)))
  table.insert(lines, sep)
  
  for i, val in ipairs(samples) do
    if i > max_rows then break end
    local s = tostring(val):gsub("\n", " ")
    if M._str_width(s) > col_width then s = vim.fn.strcharpart(s, 0, col_width-2) .. ".." end
    table.insert(lines, string.format("  │ %2d │ %s │", i-1, M._pad_string(s, col_width)))
  end
  table.insert(lines, bot)
  return lines
end

function M._render_counts_histogram(counts, min_val, max_val, available_width)
  local lines = {}
  local num_bins = #counts
  local draw_width = available_width
  local height = 8
  local blocks = { " ", "▂", "▃", "▄", "▅", "▆", "▇", "█" } 
  
  local max_c = 0
  for _, c in ipairs(counts) do if c > max_c then max_c = c end end
  if max_c == 0 then max_c = 1 end
  
  local scaled_counts = {}
  for i = 1, draw_width do
    local bin_index = math.floor(((i - 1) / draw_width) * num_bins) + 1
    bin_index = math.min(math.max(1, bin_index), num_bins)
    scaled_counts[i] = counts[bin_index]
  end
  
  for row = height, 1, -1 do
    local line = "  "
    for _, val in ipairs(scaled_counts) do
      local val_height = (val / max_c) * height
      local char = " "
      if val_height >= row then char = "█"
      elseif val_height > (row - 1) then
        local idx = math.floor((val_height - (row - 1)) * 8) + 1
        char = blocks[math.max(1, math.min(8, idx))]
      elseif val > 0 and row == 1 then char = " " end
      line = line .. char
    end
    table.insert(lines, line)
  end
  
  local min_label = string.format("%.1f", min_val)
  local max_label = string.format("%.1f", max_val)
  local padding = draw_width - #min_label - #max_label
  if padding < 1 then padding = 1 end
  table.insert(lines, "  " .. min_label .. string.rep(" ", padding) .. max_label)
    
  return lines
end

function M._render_categorical_freq(values, available_width)
  local lines = {}
  local counts = {}
  for _, v in ipairs(values) do
    local k = tostring(v)
    counts[k] = (counts[k] or 0) + 1
  end
  
  local sorted = {}
  for k, v in pairs(counts) do table.insert(sorted, {k = k, v = v}) end
  table.sort(sorted, function(a, b) return a.v > b.v end)
  
  local label_width = 25
  local max_w = (available_width or 60) - label_width
  if max_w < 5 then max_w = 5 end
  
  local max_v = sorted[1] and sorted[1].v or 1
  
  for i, item in ipairs(sorted) do
    if i > 8 then break end
    local bar_len = math.floor(item.v / max_v * max_w)
    local bar = string.rep("█", bar_len)
    if bar_len == 0 and item.v > 0 then bar = "▏" end
    
    local lbl = item.k
    local max_lbl_len = label_width - 6
    if M._str_width(lbl) > max_lbl_len then lbl = vim.fn.strcharpart(lbl, 0, max_lbl_len - 1) .. "…" end
    
    table.insert(lines, string.format("  %-" .. label_width .. "s %s (%d)", lbl, bar, item.v))
  end
  return lines
end

function M._generate_boxplot_viz(col, width)
  local min_val, max_val, q1, q3 = col.min_val, col.max_val, col.q1, col.q3
  local width = width or 40
  local range = max_val - min_val
  if range == 0 then return { "  " .. string.rep("─", width) } end
  
  local function to_idx(val)
      if not val then return -1 end
      local pos = math.floor((val - min_val) / range * width)
      return math.max(0, math.min(width - 1, pos))
  end

  local q1_pos = to_idx(q1)
  local q3_pos = to_idx(q3)
  local median_pos = to_idx(col.median_val)
  
  local viz = ""
  for i = 0, width - 1 do
    if i == 0 then viz = viz .. "├"
    elseif i == width - 1 then viz = viz .. "┤"
    elseif q1_pos >= 0 and q3_pos >= 0 and i == q1_pos then viz = viz .. "["
    elseif q1_pos >= 0 and q3_pos >= 0 and i == q3_pos then viz = viz .. "]"
    elseif q1_pos >= 0 and q3_pos >= 0 and i > q1_pos and i < q3_pos then 
       if i == median_pos then viz = viz .. "|" else viz = viz .. "=" end
    else viz = viz .. "─" end
  end
  
  return { "  " .. viz }
end

function M._quick_visualize_column(ctx, col_entry)
  local chart_id = (col_entry.dtype:match("str") or col_entry.dtype:match("object")) and "count" or "hist"
  local chart = charts.get_chart(chart_id)
  if not chart then vim.notify("Chart not found", vim.log.levels.ERROR) return end
  generator.generate({
    df = ctx.name or "df",
    cols = ctx.columns,
    lib = ctx.lib or "pandas",
    metadata = ctx.metadata or {},
    chart = chart,
    x = col_entry.name,
    title = col_entry.name .. " Distribution",
  })
end

return M
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui

--This file is in  lua/scivim/ui/layout.lua

local M = {}

function M.toggle_scientific_mode()
  -- Get current buffer ID
  local main_buf = vim.api.nvim_get_current_buf()
  
  -- 1. Create a Vertical Split
  vim.cmd("vsplit")
  
  -- 2. Move to the new right-hand window
  local win_output = vim.api.nvim_get_current_win()
  
  -- 3. Create a scratch buffer for the output
  local out_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win_output, out_buf)
  
  -- 4. Configure the Output Window (No numbers, no signs)
  vim.wo[win_output].number = false
  vim.wo[win_output].relativenumber = false
  vim.wo[win_output].signcolumn = "no"
  vim.api.nvim_buf_set_name(out_buf, "Scientific Output")

  -- 5. Resize: Give code 60%, output 40%
  vim.cmd("vertical resize 60")
  
  -- 6. Go back to the code window
  vim.cmd("wincmd h")
  
  -- 7. (Crucial) Tell Molten/Image.nvim to target the other buffer?
  -- Molten renders virtual text inline by default. 
  -- To emulate PyCharm, you might want to map a key that sends 
  -- the output to the side buffer using `MoltenEvaluateVisual` 
  -- but capturing the output is tricky in Lua without patching Molten.
  
  print("Scientific Mode Enabled")
end

return M
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui



--This file is in  lua/scivim/ui/preview.lua
-- =========================================================================
-- PREVIEW - Live Plot Preview (Matplotlib & Plotly support)
-- =========================================================================
local M = {}

local config = require("scivim.config")
local generator = require("scivim.core.generator")

-- Preview state
local preview_state = {
  job_id = nil,
  temp_file = nil,
  image_buf = nil,
}

--- Check if preview is supported
---@return boolean, string
function M.is_supported()
  -- Check for image.nvim
  local has_image = pcall(require, "image")
  if has_image then
    return true, "image.nvim"
  end
  
  -- Check for kitty terminal
  if vim.env.TERM == "xterm-kitty" or vim.env.KITTY_WINDOW_ID then
    return true, "kitty"
  end
  
  -- Check for ueberzug (legacy)
  if vim.fn.executable("ueberzug") == 1 then
    return true, "ueberzug"
  end
  
  return false, "none"
end

--- Generate preview for current visualization spec
---@param spec table|nil Visualization spec (if nil, uses last generated code)
function M.show_preview(spec)
  local supported, backend = M.is_supported()
  
  if not supported then
    vim.notify(
      "Preview not supported. Install image.nvim or use Kitty terminal.",
      vim.log.levels.WARN
    )
    return
  end
  
  -- Get code to preview (Priority: Spec -> Last Generated)
  local code_lines = {}
  
  if spec then
    -- If a spec is passed, we might need to generate it on the fly
    -- Assuming generator has a method to get code without side effects, 
    -- otherwise we rely on the cached last run.
    code_lines = generator.get_code_lines and generator.get_code_lines(spec) or {}
  end

  -- Fallback to last generated code
  if #code_lines == 0 then
    code_lines = generator.get_last_viz_code and generator.get_last_viz_code() or {}
  end

  if #code_lines == 0 then
    vim.notify("No visualization code found to preview.", vim.log.levels.ERROR)
    return
  end
  
  vim.notify("🔄 Generating preview...", vim.log.levels.INFO)
  
  -- Create temp file for output
  preview_state.temp_file = os.tmpname() .. ".png"
  local raw_code = table.concat(code_lines, "\n")
  local final_code = ""

  -- [[ SMART BACKEND DETECTION ]]
  if raw_code:match("plotly") or raw_code:match("px%.") or raw_code:match("go%.") then
      -- === PLOTLY HANDLING ===
      final_code = raw_code:gsub("fig%.show%(%)", "") -- Remove interactive show
      final_code = final_code .. "\n# Export for Neovim Preview"
      final_code = final_code .. "\ntry:"
      final_code = final_code .. "\n    import plotly.io as pio"
      final_code = final_code .. "\n    # Requires: pip install kaleido"
      final_code = final_code .. "\n    pio.write_image(fig, '" .. preview_state.temp_file .. "', engine='kaleido', scale=2)"
      final_code = final_code .. "\nexcept Exception as e:"
      final_code = final_code .. "\n    print(f'Preview Error (Plotly): {e}. Ensure kaleido is installed.')"
      final_code = final_code .. "\n    exit(1)"
  else
      -- === MATPLOTLIB/SEABORN HANDLING (Default) ===
      final_code = raw_code:gsub("plt%.show%(%)", "") -- Remove blocking show
      final_code = final_code .. "\nplt.savefig('" .. preview_state.temp_file .. "', dpi=150, bbox_inches='tight')"
  end
  
  final_code = final_code .. "\nprint('PREVIEW_READY')"
  
  -- Execute Python code
  M._execute_preview(final_code, backend)
end

--- Execute Python code and display image
---@param code string Python code
---@param backend string Display backend
function M._execute_preview(code, backend)
  -- Cancel previous preview job if running
  if preview_state.job_id then
    vim.fn.jobstop(preview_state.job_id)
  end
  
  local output = {}
  
  preview_state.job_id = vim.fn.jobstart({"python3", "-c", code}, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(output, data)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        -- Only log actual errors, filter out common matplotlib warnings if desired
        vim.notify("Preview log: " .. table.concat(data, "\n"), vim.log.levels.INFO)
      end
    end,
    on_exit = function(_, exit_code)
      preview_state.job_id = nil
      
      if exit_code == 0 then
        -- Check if file was created
        if vim.fn.filereadable(preview_state.temp_file) == 1 then
          M._display_image(preview_state.temp_file, backend)
        else
          vim.notify("Preview failed: output file not created. Check Python logs.", vim.log.levels.ERROR)
        end
      else
        vim.notify("Preview process failed with exit code: " .. exit_code, vim.log.levels.ERROR)
      end
    end,
  })
end

--- Display image using appropriate backend
---@param filepath string Path to image
---@param backend string Display backend
function M._display_image(filepath, backend)
  if backend == "image.nvim" then
    M._display_image_nvim(filepath)
  elseif backend == "kitty" then
    M._display_kitty(filepath)
  elseif backend == "ueberzug" then
    M._display_ueberzug(filepath)
  end
end

--- Display using image.nvim
function M._display_image_nvim(filepath)
  local image = require("image")
  
  -- Calculate dimensions
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  
  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
  })
  
  preview_state.image_buf = buf
  
  -- Render image
  local img = image.from_file(filepath, {
    window = win,
    buffer = buf,
    -- Fit image to window
    width = width,
    height = height,
  })
  
  if img then
    img:render()
  end
  
  -- Close handlers
  local function close()
    M.close_preview()
  end
  
  vim.keymap.set('n', 'q', close, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, noremap = true, silent = true })
  
  vim.notify("✅ Preview ready (press 'q' to close)", vim.log.levels.INFO)
end

--- Display using Kitty graphics protocol
function M._display_kitty(filepath)
  -- Use kitty icat to display image
  local cmd = string.format("kitty +kitten icat --align left --hold '%s'", filepath)
  -- Note: 'hold' keeps it open, might need adjustment depending on workflow
  vim.fn.jobstart(cmd, { detach = true })
  
  vim.notify("✅ Preview displayed in terminal", vim.log.levels.INFO)
end

--- Display using ueberzug (legacy)
function M._display_ueberzug(filepath)
  vim.notify("Ueberzug preview not fully implemented yet.", vim.log.levels.WARN)
end

--- Close preview window
function M.close_preview()
  if preview_state.image_buf and vim.api.nvim_buf_is_valid(preview_state.image_buf) then
    local wins = vim.fn.win_findbuf(preview_state.image_buf)
    for _, win in ipairs(wins) do
      vim.api.nvim_win_close(win, true)
    end
    vim.api.nvim_buf_delete(preview_state.image_buf, { force = true })
  end
  
  -- Clean up temp file
  if preview_state.temp_file and vim.fn.filereadable(preview_state.temp_file) == 1 then
    os.remove(preview_state.temp_file)
  end
  
  preview_state.image_buf = nil
  preview_state.temp_file = nil
end

return M
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- =========================================================================
-- LIVE TRANSFORM - Interactive UI (Polyglot: Python + SQL)
-- =========================================================================
local M = {}

local executor = require("scivim.backend.client")
local context = require("scivim.core.context") -- [[ NEW: Required for Workspace Loading ]]
local Snacks = require("snacks")

local ICONS = {
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    pandas  = "🐼",
    polars  = "🐻",
    lazy    = "🐨",
    global  = "🌍",
    prompt  = "  ", 
}

-- 1. Standalone Highlights
local function setup_highlights()
    local hls = {
        ScivimBorder      = { link = "FloatBorder" },
        ScivimTitle       = { link = "Title" },
        ScivimPrompt      = { link = "NormalFloat" },
        ScivimInputPrefix = { fg = "#f38ba8", bold = true },
        ScivimError       = { fg = "#f38ba8" },
    }
    if vim.fn.hlexists("SnacksPickerBorder") == 1 then
        hls.ScivimBorder = { link = "SnacksPickerBorder" }
        hls.ScivimTitle  = { link = "SnacksPickerTitle" }
    end
    for group, opts in pairs(hls) do vim.api.nvim_set_hl(0, group, opts) end
end
setup_highlights()

-- ----------------------------------------------------------------------------
-- STATE
-- ----------------------------------------------------------------------------
local state = {
  current_code = "",
  update_timer = nil, -- Timer for RPC Preview (fast debounce)
  lsp_timer = nil,    -- Timer for Disk Write/LSP (slow debounce)
  ctx = nil,          -- nil = Global Workspace Mode
  preview_win = nil,
  input_win = nil,
  parent_win = nil,
  ghost_path = nil,
  spinner_timer = nil,
  spinner_idx = 1,
}

local function get_df_icon(ctx) 
    if not ctx then return ICONS.global end
    return (ctx.lib == "polars" and (ctx.is_lazy and ICONS.lazy or ICONS.polars) or ICONS.pandas) 
end

local function get_title(ctx)
    if not ctx then return " Global Workspace " end
    return string.format(" %s %s ", get_df_icon(ctx), ctx.name)
end

local function stop_spinner()
    if state.spinner_timer then state.spinner_timer:stop(); state.spinner_timer:close(); state.spinner_timer = nil end
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win.win) then
         pcall(vim.api.nvim_win_set_config, state.input_win.win, { title = get_title(state.ctx), title_pos = "center" })
    end
end

local function start_spinner()
    if state.spinner_timer then return end
    state.spinner_idx = 1
    state.spinner_timer = vim.loop.new_timer()
    state.spinner_timer:start(0, 100, vim.schedule_wrap(function()
        if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win.win) then stop_spinner(); return end
        local frame = ICONS.spinner[state.spinner_idx]
        state.spinner_idx = (state.spinner_idx % #ICONS.spinner) + 1
        pcall(vim.api.nvim_win_set_config, state.input_win.win, { title = string.format(" %s Processing... ", frame), title_pos = "center" })
    end))
end

local function cleanup_state()
  stop_spinner()
  -- Clean RPC Timer
  if state.update_timer then pcall(function() state.update_timer:stop() end); pcall(function() state.update_timer:close() end); state.update_timer = nil end
  -- Clean LSP Timer
  if state.lsp_timer then pcall(function() state.lsp_timer:stop() end); pcall(function() state.lsp_timer:close() end); state.lsp_timer = nil end
  
  if state.preview_win then pcall(function() state.preview_win:close() end); state.preview_win = nil end
  if state.input_win then
    if state.input_win.buf and vim.api.nvim_buf_is_valid(state.input_win.buf) then pcall(vim.cmd, "bdelete! " .. state.input_win.buf) end
    pcall(function() state.input_win:close() end); state.input_win = nil
  end
  if state.ghost_path and vim.fn.filereadable(state.ghost_path) == 1 then os.remove(state.ghost_path) end
  state.ghost_path = nil
  state.current_code = ""
  state.ctx = nil
  state.parent_win = nil
end

local function center_lines(lines, win)
  if not win or not win.win or not vim.api.nvim_win_is_valid(win.win) then return lines end
  local width = vim.api.nvim_win_get_width(win.win)
  local centered = {}
  for _, line in ipairs(lines) do
    local line_len = vim.fn.strdisplaywidth(line)
    if line_len < width then table.insert(centered, string.rep(" ", math.floor((width - line_len) / 2)) .. line) else table.insert(centered, line) end
  end
  return centered
end

-- ----------------------------------------------------------------------------
-- UPDATE LOGIC
-- ----------------------------------------------------------------------------
local function update_preview(response)
  stop_spinner()
  if not state.preview_win or not state.preview_win.buf or not vim.api.nvim_buf_is_valid(state.preview_win.buf) then return end
  
  local lines = {}
  local border_hl = "ScivimBorder"

  if response.error and type(response.error) == "string" then
    if not (response.error:match("Syntax") or response.error:match("unexpected EOF")) then
      border_hl = "ScivimError"
      local err_lines = vim.split(response.error, "\n")
      table.insert(lines, ""); table.insert(lines, "💥 " .. (err_lines[1] or "Error")); table.insert(lines, string.rep("─", 40))
      for i = 2, #err_lines do table.insert(lines, "  " .. err_lines[i]) end
    end
  end

  if response.text_table and type(response.text_table) == "string" then
    local raw_lines = vim.split(response.text_table, '\n')
    vim.list_extend(lines, center_lines(raw_lines, state.preview_win))
  end
  
  if vim.api.nvim_win_is_valid(state.preview_win.win) then
      vim.api.nvim_win_set_option(state.preview_win.win, "winhighlight", "FloatBorder:"..border_hl..",Normal:NormalFloat")
  end
  
  vim.api.nvim_buf_set_lines(state.preview_win.buf, 0, -1, false, lines)
end

local function trigger_request()
  start_spinner()
  -- Logic: If state.ctx exists, send its details. If nil (Global), send empty string but keep the request type.
  local name = state.ctx and state.ctx.name or ""
  local lib = state.ctx and state.ctx.lib or "pandas"
  local is_lazy = state.ctx and state.ctx.is_lazy or false
  
  executor.run_transform_async(
    name,
    lib,
    is_lazy,
    state.current_code,
    function(response)
      if state.input_win and state.preview_win then
          vim.schedule(function() update_preview(response) end)
      end
    end
  )
end

local function debounced_update(code)
  state.current_code = code
  if state.update_timer then state.update_timer:stop(); state.update_timer:close() end
  state.update_timer = vim.loop.new_timer()
  -- Fast debounce (150ms) for Preview RPC
  state.update_timer:start(150, 0, vim.schedule_wrap(trigger_request))
end

-- ----------------------------------------------------------------------------
-- UI LAUNCHER & UTILS
-- ----------------------------------------------------------------------------

local function patch_lsp_client(client)
    if client._scivim_patched then return end
    local method = "textDocument/signatureHelp"
    local orig_handler = client.handlers[method] or vim.lsp.handlers[method]
    client.handlers[method] = function(err, result, ctx, config)
        if ctx and ctx.bufnr and vim.b[ctx.bufnr].scivim_hide_signature then return end
        if orig_handler then orig_handler(err, result, ctx, config) end
    end
    client._scivim_patched = true
end

-- [[ UPDATED: Generate stub for ALL DataFrames in workspace ]]
local function generate_workspace_stub(all_contexts, primary_ctx)
  local lines = {}
  -- Imports for all potential libs
  table.insert(lines, "import pandas as pd")
  table.insert(lines, "import numpy as np")
  table.insert(lines, "import polars as pl")
  table.insert(lines, "from polars import col, lit, when")
  table.insert(lines, "")

  -- Generate a class and instance for EVERY dataframe found
  for _, ctx in pairs(all_contexts) do
      local class_name = ctx.name .. "_Type"
      local parent_class = "pd.DataFrame"
      if ctx.lib == "polars" then
          parent_class = ctx.is_lazy and "pl.LazyFrame" or "pl.DataFrame"
      end

      table.insert(lines, string.format("class %s(%s):", class_name, parent_class))
      
      if ctx.columns and #ctx.columns > 0 then
          for _, col in ipairs(ctx.columns) do
              -- Sanitize column names for Python syntax
              if col:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                  local type_hint = "pd.Series"
                  if ctx.lib == "polars" then type_hint = "pl.Expr" end
                  table.insert(lines, string.format("    %s: %s", col, type_hint))
              end
          end
      else
          table.insert(lines, "    pass")
      end
      table.insert(lines, "")
      -- Instantiate it so LSP sees the variable
      table.insert(lines, string.format("%s: %s = %s()", ctx.name, class_name, class_name))
  end

  -- If we focused on one specific DF, alias it to 'df'
  if primary_ctx then
      table.insert(lines, "")
      table.insert(lines, string.format("df = %s", primary_ctx.name))
  end

  return table.concat(lines, "\n")
end

local function setup_lsp_completion(input_buf, parent_buf, ctx)
  if not vim.api.nvim_buf_is_valid(input_buf) then return end
  
  -- 1. Aggressively flag this buffer to hide signatures
  vim.b[input_buf].scivim_hide_signature = true

  -- 2. Hook into LspAttach to castrate the signature capability for this specific buffer
  -- [FIX: This prevents the 'height must be positive Integer' crash]
  vim.api.nvim_create_autocmd("LspAttach", {
    buffer = input_buf,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then
        -- DISABLE Signature Help Capability for this instance
        if client.server_capabilities then
          client.server_capabilities.signatureHelpProvider = nil
        end
        -- Patch handler just in case capability check is bypassed
        patch_lsp_client(client) 
      end
    end
  })

  -- 3. Ghost File Setup (Standard Scivim Logic)
  local start_path = vim.api.nvim_buf_get_name(parent_buf)
  if start_path == "" then start_path = vim.fn.getcwd() end
  
  -- Use system temp to prevent workspace pollution
  local root_markers = { "pyproject.toml", "requirements.txt", ".git", ".venv", "venv" }
  local root_dir = vim.fs.dirname(vim.fs.find(root_markers, { path = start_path, upward = true })[1] or start_path)
  
  -- Optimization: Keep ghost file in root to allow relative imports in analysis
  local fake_path = root_dir .. "/__scivim_ghost_" .. os.time() .. ".py"
  state.ghost_path = fake_path
  
  local all_data = context.load_all() or {}
  local stub_content = generate_workspace_stub(all_data, ctx)
  local f = io.open(fake_path, "w"); if f then f:write(stub_content); f:close() end
  
  vim.api.nvim_buf_set_name(input_buf, fake_path)
  vim.bo[input_buf].buftype = "" 
  vim.bo[input_buf].filetype = "python"
  
  vim.api.nvim_buf_set_lines(input_buf, 0, 0, false, vim.split(stub_content, '\n'))
  
  -- Silence the write message
  vim.api.nvim_buf_call(input_buf, function() vim.cmd("silent! write") end)

  -- 4. Manual Client Attachment (Debounced)
  vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(input_buf) then return end
      
      -- Prioritize Pyright/BasedPyright/Pyrefly
      local attached = false
      local available_clients = vim.lsp.get_clients({ bufnr = parent_buf }) -- Optimization: reuse parent clients
      
      for _, client in ipairs(available_clients) do
         if client.name == "pyright" or client.name == "basedpyright" or client.name == "pyrefly" then
             vim.lsp.buf_attach_client(input_buf, client.id)
             attached = true
             break
         end
      end
      
      -- Fallback to global search if parent had no LSP
      if not attached then
          for _, client in ipairs(vim.lsp.get_clients()) do
             if client.name == "pyright" or client.name == "basedpyright" then
                 vim.lsp.buf_attach_client(input_buf, client.id)
                 break 
             end
          end
      end
  end)

  -- 5. CMP Setup (ensure 'buffer' source is prioritized for local variables)
  vim.defer_fn(function() 
      local has_cmp, cmp = pcall(require, "cmp")
      if has_cmp then 
          cmp.setup.buffer({ 
              enabled = true,
              completion = { autocomplete = { cmp.TriggerEvent.TextChanged } },
              sources = cmp.config.sources({ 
                  { name = "nvim_lsp", priority = 1000 }, 
                  { name = "buffer", priority = 500 } 
              }) 
          }) 
      end 
  end, 100)
end

local function open_transform_ui(ctx)
  state.ctx = ctx -- Can be nil for Global Mode
  state.current_code = ""
  state.parent_win = vim.api.nvim_get_current_win()
  local parent_buf = vim.api.nvim_get_current_buf()
  
  -- Dimensions
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local input_h = 3
  local preview_h = height - input_h

  local title_text = get_title(ctx)
  
  -- 1. Input Window
  state.input_win = Snacks.win({
    relative = "editor", row = row, col = col, width = width, height = 1,
    border = "rounded", title = title_text, title_pos = "center",
    wo = { winhighlight = "FloatBorder:ScivimBorder,Title:ScivimTitle,Normal:ScivimPrompt", scrolloff = 0 },
    keys = { ["<Esc>"] = { "close", mode = {"n", "i"} }, ["<C-c>"] = { "close", mode = {"n", "i"} } }
  })

  -- 2. Preview Window
  state.preview_win = Snacks.win({
    relative = "editor", row = row + input_h, col = col, width = width, height = preview_h,
    border = "rounded", wo = { winhighlight = "FloatBorder:ScivimBorder,Normal:NormalFloat" }, interactive = false
  })
  
  -- 3. Setup Input Buffer
  local input_buf = state.input_win.buf
  -- [[ NEW: Pass ctx (could be nil) for workspace generation ]]
  setup_lsp_completion(input_buf, parent_buf, ctx)
  
  -- Prompt Icon
  local ns_id = vim.api.nvim_create_namespace("scivim_prompt")
  local function set_prompt_extmark() 
      vim.api.nvim_buf_set_extmark(input_buf, ns_id, 0, 0, { virt_text = {{ ICONS.prompt, "ScivimInputPrefix" }}, virt_text_pos = "inline" }) 
  end
  
  -- Stub calculation needs to check if we are global or local
  local all_data = context.load_all() or {}
  local stub_lines = vim.split(generate_workspace_stub(all_data, ctx), '\n')
  local content_offset = #stub_lines + 1
  
  vim.defer_fn(function() 
      if vim.api.nvim_buf_is_valid(input_buf) and vim.api.nvim_win_is_valid(state.input_win.win) then 
          local line_count = vim.api.nvim_buf_line_count(input_buf)
          if line_count < content_offset then vim.api.nvim_buf_set_lines(input_buf, line_count, -1, false, { "" }) end
          vim.api.nvim_win_set_cursor(state.input_win.win, {content_offset, 0})
          vim.fn.winrestview({topline = content_offset, lnum = content_offset, col = 0})
          set_prompt_extmark() 
      end 
  end, 150)
  
  vim.api.nvim_set_current_win(state.input_win.win)
  vim.cmd("startinsert")
  
  -- Initialize Timer
  state.lsp_timer = vim.loop.new_timer()

  -- Auto-update hook with OPTIMIZED IO DEBOUNCE
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, { 
      buffer = input_buf, 
      callback = function() 
          set_prompt_extmark()

          -- 1. DEBOUNCED DISK WRITE (Fixes IO Thrashing for LSP)
          if state.lsp_timer then
              state.lsp_timer:stop()
              state.lsp_timer:start(500, 0, vim.schedule_wrap(function()
                 if vim.api.nvim_buf_is_valid(input_buf) then
                     vim.api.nvim_buf_call(input_buf, function() 
                         vim.cmd("silent! write") 
                     end)
                 end
              end))
          end
          
          -- 2. GET TEXT & DETECT SQL (Immediate Logic)
          local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
          local user_lines = {}
          for i = content_offset, #all_lines do if all_lines[i] then table.insert(user_lines, all_lines[i]) end end
          
          local full_text = table.concat(user_lines, "\n")
          
          -- Dynamic SQL Syntax Switching
          local first_word = full_text:match("^%s*(%w+)")
          if first_word then
              first_word = first_word:upper()
              if vim.tbl_contains({"SELECT", "WITH", "PRAGMA", "DESCRIBE", "SHOW", "EXPLAIN"}, first_word) then
                  if vim.bo[input_buf].filetype ~= "sql" then vim.bo[input_buf].filetype = "sql" end
              else
                  if vim.bo[input_buf].filetype ~= "python" then vim.bo[input_buf].filetype = "python" end
              end
          end

          -- 3. TRIGGER PREVIEW (Fast Debounce)
          debounced_update(full_text) 
      end 
  })
  trigger_request()
  
  -- Close/Accept Logic with SMART SUBSTITUTION
  local function accept_and_close()
    local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local user_lines = {}
    for i = content_offset, #all_lines do if all_lines[i] then table.insert(user_lines, all_lines[i]) end end
    local code = table.concat(user_lines, "\n")
    
    local target_win = state.parent_win
    cleanup_state()
    
    if target_win and vim.api.nvim_win_is_valid(target_win) then
        vim.api.nvim_set_current_win(target_win)
    end
    
    if code and code ~= "" then
        -- Check if it was SQL or Python
        local start_token = code:match("^%s*(%w+)")
        local is_sql = false
        if start_token and vim.tbl_contains({"SELECT", "WITH", "PRAGMA"}, start_token:upper()) then
            is_sql = true
        end

        local full_code = code
        if not is_sql then
            -- [[ NEW: Smart Substitution ]]
            -- Only replace 'df' if we are in a Specific Context
            if ctx then
                -- Be careful: don't replace 'df_sales' with 'ctx.name_sales'
                -- 1. Replace 'df.' with 'name.'
                if code:match("^%s*df%.") then
                    full_code = code:gsub("^%s*df", ctx.name, 1)
                -- 2. Replace chaining .function()
                elseif code:match("^%s*%.") then
                    full_code = ctx.name .. code
                else
                    -- 3. Replace isolated 'df'
                    full_code = code:gsub("([^%w_])df([^%w_])", "%1" .. ctx.name .. "%2")
                    full_code = full_code:gsub("^df([^%w_])", ctx.name .. "%1")
                    full_code = full_code:gsub("([^%w_])df$", "%1" .. ctx.name)
                    -- If the code was just "df", replace it
                    if full_code == "df" then full_code = ctx.name end
                end
            end
        else
            -- SQL Substitution Logic
            if ctx then
                -- In specific mode, allow 'FROM df' shorthand
                local clean_code = code:gsub("FROM%s+df", "FROM " .. ctx.name)
                clean_code = clean_code:gsub("from%s+df", "FROM " .. ctx.name)
                clean_code = clean_code:gsub("JOIN%s+df", "JOIN " .. ctx.name)
                -- Wrap in duckdb call
                full_code = string.format("import duckdb\n%s_sql = duckdb.sql(\"\"\"%s\"\"\").df()", ctx.name, clean_code)
            else
                -- In Global Mode, raw SQL, no wrapper auto-assign
                full_code = string.format("import duckdb\nsql_res = duckdb.sql(\"\"\"%s\"\"\").df()", code)
            end
        end
        vim.api.nvim_put(vim.split(full_code, '\n'), "c", true, true)
    end
  end
  
  vim.keymap.set({"n", "i"}, "<CR>", function() vim.cmd("stopinsert"); accept_and_close() end, { buffer = input_buf })
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, { buffer = input_buf, callback = function() vim.defer_fn(cleanup_state, 100) end, once = true })
end

-- [[ UPDATED: Picker now includes Global Option ]]
function M.inspect_transform(ctx_arg)
  if ctx_arg then 
    open_transform_ui(ctx_arg) 
  else 
    local all_data = context.load_all()
    local ctx_list = {}
    if all_data then for _, v in pairs(all_data) do table.insert(ctx_list, v) end end
    
    if #ctx_list == 0 then 
        vim.notify("No dataframes exposed via vim_expose()", vim.log.levels.WARN) 
    elseif #ctx_list == 1 then 
        open_transform_ui(ctx_list[1]) 
    else 
        local items = {}
        -- Add Global Option First
        table.insert(items, { 
            text = "Global Workspace (All DataFrames)", 
            ctx = nil, 
            icon = ICONS.global 
        })
        
        for _, c in ipairs(ctx_list) do 
            table.insert(items, { 
                text = c.name, 
                ctx = c, 
                icon = get_df_icon(c) 
            }) 
        end
        
        Snacks.picker.pick({
            items = items,
            title = "Select Context",
            layout = "vscode",
            format = function(item) 
                return { { item.icon, "SnacksIcon" }, { " " }, { item.text, "Normal" } } 
            end,
            confirm = function(picker, item)
                picker:close()
                if item then open_transform_ui(item.ctx) end
            end
        })
    end 
  end
end

return M
-- /home/tanzious/scivim/lua/scivim/ui/wizard.lua
-- /home/tanzious/scivim/lua/scivim/ui/wizard.lua
-- /home/tanzious/scivim/lua/scivim/ui/wizard.lua
-- /home/tanzious/scivim/lua/scivim/ui/wizard.lua
-- /home/tanzious/scivim/lua/scivim/ui/wizard.lua
-- /home/tanzious/scivim/lua/scivim/ui/wizard.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui
-- This file is in /lua/scivim/ui/wizard.lua
-- =========================================================================
-- WIZARD - Interactive Plot Builder (Expert Edition)
-- =========================================================================
local M = {}

local config = require("scivim.config")
local context = require("scivim.core.context")
local charts = require("scivim.core.charts")
local generator = require("scivim.core.generator")
local inspector = require("scivim.ui.inspector") 
local client = require("scivim.backend.client") -- [[ NEW: RPC Client ]]
local Snacks = require("snacks")

local has_image, image_nvim = pcall(require, "image")

local Builder = {
  active = false,
  state = {},
  active_img = nil,
  tmp_file = os.tmpname() .. ".png",
  debounce_timer = nil
}

local CAT_ICONS = {
  relational   = "🔗",
  distribution = "📊",
  categorical  = "📦",
  matrix       = "▦ ",
  multivariate = "🧊",
  hierarchical = "◎",
  flow         = "ﬡ",
}

--- Start the interactive builder
function M.start()
  local all_data, err = context.load_all()
  if not all_data then 
    vim.notify(err, vim.log.levels.ERROR) 
    return 
  end

  local ctx_list = {}
  for name, data in pairs(all_data) do
    table.insert(ctx_list, data)
  end

  if #ctx_list == 0 then
    vim.notify("No DataFrames exposed via vim_expose()", vim.log.levels.WARN)
    return
  end

  -- Auto-select based on cursor
  local cursor_word = vim.fn.expand("<cword>")
  for _, ctx in ipairs(ctx_list) do
    if ctx.name == cursor_word then
      vim.notify("📊 Auto-selected DataFrame: " .. cursor_word, vim.log.levels.INFO)
      M._step_select_chart(ctx, nil)
      return
    end
  end

  if #ctx_list == 1 then
    M._step_select_chart(ctx_list[1], nil)
    return
  end

  M._step_select_df(ctx_list)
end

function M.quick_start(chart_id)
  local all_data, err = context.load_all()
  if not all_data then return end
  
  local ctx_list = {}
  for name, data in pairs(all_data) do
    table.insert(ctx_list, data)
  end
  
  local cursor_word = vim.fn.expand("<cword>")
  local chart = charts.get_chart(chart_id)

  for _, ctx in ipairs(ctx_list) do
    if ctx.name == cursor_word and chart then
      M._init_builder(ctx, chart)
      return
    end
  end

  if chart then M._step_select_df(ctx_list, chart) end
end

-- -------------------------------------------------------------------------
-- STEP 1: DATA CONTEXT
-- -------------------------------------------------------------------------

function M._step_select_df(ctx_list, preselected_chart)
  local items = {}
  for _, ctx in ipairs(ctx_list) do
    local icon = ctx.lib == "polars" and config.icon("polars") or config.icon("pandas")
    table.insert(items, { 
      text = ctx.name, 
      ctx = ctx, 
      comment = string.format("%d cols", #ctx.columns), 
      icon = icon 
    })
  end

  Snacks.picker.pick({
    items = items, 
    title = "Select DataFrame", 
    layout = "vscode",
    format = function(item)
      return { 
        { item.icon, "SnacksIcon" }, 
        { " " }, 
        { item.text, "Normal" }, 
        { "  " }, 
        { item.comment, "Comment" } 
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.ctx then 
        vim.notify("✓ Selected: " .. item.ctx.name, vim.log.levels.INFO)
        M._step_select_chart(item.ctx, preselected_chart) 
      end
    end
  })
end

-- -------------------------------------------------------------------------
-- STEP 2: CHART TYPE
-- -------------------------------------------------------------------------

function M._step_select_chart(ctx, preselected_chart)
  if preselected_chart then 
    M._init_builder(ctx, preselected_chart) 
    return 
  end
  
  local avail_charts = generator.get_available_charts() 
  local adapter = generator.get_active_plot_adapter()
  local backend = config.get().plot_backend or "seaborn"
  
  table.sort(avail_charts, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.name < b.name
  end)

  local items = {}
  local last_cat = nil
  
  for _, chart in ipairs(avail_charts) do
    if chart.category ~= last_cat then
      local cat_icon = CAT_ICONS[chart.category] or "📂"
      table.insert(items, { 
        text = chart.category:upper(), 
        header = true,
        icon = cat_icon,
        desc = "Browse charts in the " .. chart.category .. " category."
      })
      last_cat = chart.category
    end
    
    local req_str = ""
    if chart.req and #chart.req > 0 then
      req_str = "[" .. table.concat(chart.req, ", "):upper() .. "]"
    end

    local func_name = nil
    local doc_url = nil
    
    if adapter and adapter.mappings and adapter.mappings[chart.id] then
       func_name = adapter.mappings[chart.id]
       if backend == "plotly" then
          local clean_func = func_name:gsub("px%.", "plotly.express.")
          doc_url = "https://plotly.com/python-api-reference/generated/" .. clean_func .. ".html"
       elseif backend == "seaborn" then
          local clean_func = func_name:gsub("sns%.", "seaborn.")
          doc_url = "https://seaborn.pydata.org/generated/" .. clean_func .. ".html"
       end
    end

    table.insert(items, { 
      text = chart.name, 
      item = chart, 
      icon = chart.icon,
      req_str = req_str, 
      desc = chart.desc or "Visualization",
      func_name = func_name,
      doc_url = doc_url,
      backend = backend
    })
  end

  Snacks.picker.pick({
    items = items, 
    title = "Select Visualization Type", 
    layout = {
        layout = {
            box = "horizontal",
            width = 0.8,
            height = 0.8,
            {
                box = "vertical",
                border = "rounded",
                { win = "input", height = 1, border = "bottom" },
                { win = "list", border = "none" },
            },
            {
                win = "preview",
                title = " Description ",
                border = "rounded",
                width = 0.5,
            }
        }
    },
    format = function(item)
      if item.header then
        return { { item.icon .. "  " .. item.text, "Directory" } }
      end
      return { { "  " }, { item.icon, "SnacksIcon" }, { " " }, { item.text, "Normal" } } 
    end,
    matcher = { filter = function(item) return not item.header end },
    
    preview = function(p_ctx)
        local item = p_ctx.item
        if not vim.api.nvim_buf_is_valid(p_ctx.buf) then return end
        
        vim.bo[p_ctx.buf].modifiable = true
        local lines = {}
        
        if item.header then
            table.insert(lines, "")
            table.insert(lines, "  " .. item.icon .. " CATEGORY: " .. item.text)
            table.insert(lines, "  " .. string.rep("─", 30))
            table.insert(lines, "")
            table.insert(lines, "  " .. item.desc)
        else
            table.insert(lines, "")
            table.insert(lines, "  " .. item.icon .. " " .. item.text)
            table.insert(lines, "  " .. string.rep("─", 35))
            table.insert(lines, "")
            for _, line in ipairs(vim.split(item.desc or "No description.", "\n")) do
                table.insert(lines, "  " .. line)
            end
            table.insert(lines, "")
            table.insert(lines, "  🔧 BACKEND: " .. (item.backend and item.backend:upper() or "GENERIC"))
            
            if item.func_name then
                table.insert(lines, "  ƒ  FUNCTION: " .. item.func_name)
            end

            if item.req_str and item.req_str ~= "" then
                table.insert(lines, "")
                table.insert(lines, "  REQUIRES: " .. item.req_str)
            end
            
            if item.doc_url then
                table.insert(lines, "")
                table.insert(lines, "  📚 DOCS:")
                table.insert(lines, "  " .. item.doc_url)
            end
        end
        
        vim.api.nvim_buf_set_lines(p_ctx.buf, 0, -1, false, lines)
        vim.bo[p_ctx.buf].filetype = "markdown"
        vim.bo[p_ctx.buf].modifiable = false
    end,

    confirm = function(picker, item)
      if item.header then return end
      picker:close()
      if item then M._init_builder(ctx, item.item) end
    end
  })
end

-- -------------------------------------------------------------------------
-- STEP 3: THE DASHBOARD
-- -------------------------------------------------------------------------

function M._init_builder(ctx, chart)
  if not ctx or not ctx.name then return end
  
  local needs_reset = false
  
  if not Builder.active then
    needs_reset = true
  elseif not Builder.state.df or Builder.state.df ~= ctx.name then
    needs_reset = true
  elseif Builder.state.chart and Builder.state.chart.id ~= chart.id then
    needs_reset = true
  end
  
  if needs_reset then
    if Builder.active_img then Builder.active_img:clear() end
    
    Builder.state = {
      ctx = ctx,
      df = ctx.name,
      lib = ctx.lib or "pandas",
      cols = ctx.columns or {},
      metadata = ctx.metadata or {},
      chart = chart,
      params = {
        x = chart.default_x or nil,
        y = nil,
        z = nil, 
        hue = nil,
        title = nil,
        size = nil,
        theme = nil,
        palette = nil,
        kde = (chart.id == "hist") and true or nil,
        bins = nil,
        alpha = (chart.id == "scatter" or chart.id == "scatter3d") and 0.8 or nil,
      },
      valid = false
    }
    Builder.active = true
  end
  
  M._open_dashboard()
end

function M._open_dashboard()
  local state = Builder.state
  local req = state.chart.req or {}
  
  local missing = {}
  if vim.tbl_contains(req, "x") and not state.params.x then table.insert(missing, "X") end
  if vim.tbl_contains(req, "y") and not state.params.y then table.insert(missing, "Y") end
  if vim.tbl_contains(req, "z") and not state.params.z then table.insert(missing, "Z") end
  state.valid = #missing == 0

  local items = {}
  
  local function add_item(group, label, key, action, icon, is_req)
     local val = state.params[key]
     local display_val = val
     
     if type(val) == "boolean" then display_val = val and "On" or "Off"
     elseif val == nil then display_val = "(Default)"
     else display_val = tostring(val) end
     
     local status_hl = "Comment"
     local status_icon = "🔹"
     
     if is_req then 
        if val then 
            status_icon = "✅" 
            status_hl = "String"
        else 
            status_icon = "🔴" 
            status_hl = "Error"
        end
     end
     
     table.insert(items, {
        group = group, 
        text = label, 
        key = key, 
        value = display_val,
        action = action, 
        icon = icon, 
        status = status_icon,
        hl = status_hl
     })
  end

  add_item("1. Data Mapping", "X Axis", "x", "pick_col", "📊", vim.tbl_contains(req, "x"))
  if vim.tbl_contains(state.chart.req, "y") or vim.tbl_contains(state.chart.opt, "y") then
    add_item("1. Data Mapping", "Y Axis", "y", "pick_col", "📊", vim.tbl_contains(req, "y"))
  end
  if vim.tbl_contains(state.chart.req, "z") or vim.tbl_contains(state.chart.opt, "z") then
    add_item("1. Data Mapping", "Z Axis", "z", "pick_col", "🧊", vim.tbl_contains(req, "z"))
  end
  add_item("1. Data Mapping", "Group/Color", "hue", "pick_col", "🎨", false)

  if state.chart.id == "hist" then
    add_item("2. Options", "KDE Line", "kde", "toggle_bool", "📈", false)
    add_item("2. Options", "Bins", "bins", "input_int", "🔢", false)
  elseif state.chart.id == "scatter" or state.chart.id == "scatter3d" then
    add_item("2. Options", "Opacity", "alpha", "input_float", "🌗", false)
    add_item("2. Options", "Size", "size", "pick_col", "⚪", false)
  end
  
  add_item("3. Styling", "Theme", "theme", "pick_adapter_opt", "🎭", false)
  add_item("3. Styling", "Palette", "palette", "pick_adapter_opt", "🌈", false)
  add_item("3. Styling", "Title", "title", "input_text", "📝", false)

  local gen_text = state.valid and "Generate Code" or "Missing Required Fields"
  local gen_icon = state.valid and "🚀" or "🚫"
  table.insert(items, { group = "4. Actions", text = gen_text, action = "generate", icon = gen_icon })
  
  if state.valid then
      table.insert(items, { group = "4. Actions", text = "Save Plot as PNG", action = "save_png", icon = "💾" })
  end

  Snacks.picker.pick({
    items = items,
    title = string.format(" %s %s [%s] ", state.chart.icon, state.chart.name, state.df),
    
    layout = {
      layout = {
        box = "horizontal", width = 0.95, height = 0.95,
        {
          box = "vertical", border = "rounded", title = "{title}", width = 0.4,
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        {
          win = "preview", title = " Live Preview ", border = "rounded", width = 0.6,
        },
      }
    },
    
    format = function(item)
      local ret = { 
          { item.status, "SnacksIcon" }, 
          { " " }, 
          { item.icon, "SnacksIcon" }, 
          { " " }, 
          { string.format("%-15s", item.text), "Normal" } 
      }
      if item.value and item.value ~= "" then
        table.insert(ret, { " │  ", "Comment" })
        table.insert(ret, { item.value, item.hl or "String" })
      end
      return ret
    end,
    
    preview = function(ctx)
      local ok, spec = pcall(M._build_spec_from_state)
      if not ok then return end
      local ok2, lines = pcall(generator.get_code_lines, spec, true)
      if not ok2 then return end
      
      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
      vim.bo[ctx.buf].modifiable = false
      vim.bo[ctx.buf].filetype = "python"
      
      if has_image and Builder.state.valid then
          M._render_live_image(ctx.buf, spec, lines)
      end
    end,
    
    confirm = function(picker, item)
      if item.action == "pick_col" then
        picker:close(); M._pick_column_rich(item.key)
      elseif item.action == "pick_adapter_opt" then
        picker:close(); M._pick_adapter_option(item.key)
      elseif item.action == "toggle_bool" then
        Builder.state.params[item.key] = not Builder.state.params[item.key]
        picker:find()
      elseif item.action == "input_text" then
        picker:close()
        vim.ui.input({ prompt = "Set " .. item.text, default = Builder.state.params[item.key] }, function(v)
            if v then Builder.state.params[item.key] = v end; M._open_dashboard()
        end)
      elseif item.action == "input_int" or item.action == "input_float" then
        picker:close()
        vim.ui.input({ prompt = "Set " .. item.text }, function(v)
            if v then Builder.state.params[item.key] = tonumber(v) end; M._open_dashboard()
        end)
      elseif item.action == "generate" then
        if Builder.state.valid then picker:close(); M._finalize() else vim.notify("Missing required fields!", vim.log.levels.WARN) end
      elseif item.action == "save_png" then
        picker:close()
        vim.ui.input({ prompt = "Filename (no ext): ", default = "plot" }, function(v)
            if v then M._finalize_save(v) end
        end)
      end
    end
  })
end

-- -------------------------------------------------------------------------
-- LIVE IMAGE RENDERING LOGIC (OPTIMIZED)
-- -------------------------------------------------------------------------

function M._render_live_image(bufnr, spec, code_lines)
  if Builder.debounce_timer then Builder.debounce_timer:stop() end
  Builder.debounce_timer = vim.defer_fn(function()
      M._execute_preview_job(spec, code_lines, bufnr)
  end, 200)
end

function M._execute_preview_job(spec, code_lines, bufnr)
  -- Flatten code
  local py_code = table.concat(code_lines, "\n")
  
  -- Send to Daemon via RPC
  client.generate_preview(py_code, Builder.tmp_file, function(res)
      if res.error then
         -- Silently fail or log debug
      elseif res.status == "ok" then
         vim.schedule(function() 
             M._display_image_in_buffer(bufnr, #code_lines + 3) 
         end)
      end
  end)
end

function M._display_image_in_buffer(bufnr, start_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if Builder.active_img then Builder.active_img:clear() end
  
  local img = image_nvim.from_file(Builder.tmp_file, {
    buffer = bufnr, x = 0, y = start_line, width = 60, height = 20,
  })
  if img then 
      img:render()
      Builder.active_img = img
  end
end

-- -------------------------------------------------------------------------
-- PICKERS (Unchanged)
-- -------------------------------------------------------------------------

function M._pick_column_rich(param_key)
  local state = Builder.state
  local items = {}
  table.insert(items, { text = "(None)", idx = 0, icon = "🚫", col = { name = "None", dtype = "none" } })

  for i, col_name in ipairs(state.cols) do
    local meta = state.metadata and state.metadata[col_name] or {}
    local col_data = context.create_column_entry(col_name, meta, i)
    local icon = "📊"
    if context._is_numeric(col_data.dtype) then icon = "🔢"
    elseif col_data.dtype:match("date") then icon = "📅" end

    table.insert(items, { text = col_name, idx = i, icon = icon, col = col_data, comment = col_data.dtype })
  end

  Snacks.picker.pick({
    items = items, title = " Select " .. param_key:upper() .. " ",
    layout = {
      layout = {
        box = "horizontal", width = 0.9, height = 0.9,
        {
          box = "vertical", border = "rounded", title = "{title}", width = 0.3,
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        { win = "preview", title = " Column Statistics ", border = "rounded", width = 0.7 },
      }
    },
    format = function(item) return { { item.icon, "SnacksIcon" }, { " " }, { item.text, "Normal" }, { "  " }, { item.comment, "Comment" } } end,
    preview = function(p_ctx)
        if p_ctx.item.text == "(None)" then return end
        local ok, lines = pcall(inspector.get_column_preview_lines, p_ctx.item.col)
        if not ok then return end
        vim.bo[p_ctx.buf].modifiable = true
        vim.api.nvim_buf_set_lines(p_ctx.buf, 0, -1, false, lines)
        vim.bo[p_ctx.buf].modifiable = false
        local ns = vim.api.nvim_create_namespace("scivim_inspect")
        for i, line in ipairs(lines) do
            if line:match("^%s*📦") then vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Title", i - 1, 0, -1) end
            local s_idx = 1
            while true do
                local s, e = string.find(line, "[▂▃▄▅▆▇█]+", s_idx)
                if not s then break end
                vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Function", i - 1, s - 1, e)
                s_idx = e + 1
            end
        end
    end,
    confirm = function(picker, item)
      picker:close()
      Builder.state.params[param_key] = (item.text ~= "(None)") and item.text or nil
      vim.schedule(function() M._open_dashboard() end)
    end
  })
end

function M._pick_adapter_option(key)
  local adapter = generator.get_active_plot_adapter()
  if not adapter then 
      vim.notify("No active plot adapter found", vim.log.levels.WARN)
      return 
  end

  local opts = adapter[key .. "s"] 
  if not opts or #opts == 0 then
      vim.notify("No " .. key .. " options available for this backend", vim.log.levels.INFO)
      return
  end

  local items = {}
  for _, v in ipairs(opts) do table.insert(items, { text = v }) end
  
  Snacks.picker.pick({
    items = items, title = "Select " .. key, layout = "vscode", 
    format = function(item) return { { item.text, "Normal" } } end,
    confirm = function(picker, item)
      picker:close()
      if item then Builder.state.params[key] = item.text end
      vim.schedule(function() M._open_dashboard() end)
    end
  })
end

function M._build_spec_from_state()
  local s = Builder.state
  local spec = vim.deepcopy(s.params)
  spec.df = s.df
  spec.lib = s.lib
  spec.chart = s.chart
  return spec
end

function M._finalize()
  local spec = M._build_spec_from_state()
  generator.generate(spec)
  Builder.active = false
  if Builder.active_img then Builder.active_img:clear() end
end

function M._finalize_save(filename)
  local spec = M._build_spec_from_state()
  spec.save_format = "png"
  spec.save_filename = filename
  generator.generate(spec)
  Builder.active = false
  if Builder.active_img then Builder.active_img:clear() end
end

return M
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
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- This file is in /lua/scivim/init.lua
-- =========================================================================
-- SCIVIM - Scientific Visualization for Neovim
-- =========================================================================
local M = {}

-- Lazy load submodules with NEW PATHS
local modules = {
  config    = "scivim.config",
  -- Core Logic
  charts    = "scivim.core.charts",
  context   = "scivim.core.context",
  generator = "scivim.core.generator",
  snippets  = "scivim.core.snippets",
  stats     = "scivim.core.stats",
  -- UI Components
  wizard    = "scivim.ui.wizard",
  preview   = "scivim.ui.preview",
  transform = "scivim.ui.transform",
  explorer  = "scivim.ui.explorer", 
}

-- Auto-loader for submodules
setmetatable(M, {
  __index = function(t, key)
    if modules[key] then
      local ok, mod = pcall(require, modules[key])
      if ok then
        rawset(t, key, mod)
        return mod
      end
    end
    return nil
  end
})

-- -------------------------------------------------------------------------
-- PUBLIC API
-- -------------------------------------------------------------------------

--- Install the IPython startup script (Robust Version)
function M.install_ipython()
  local paths = require("scivim.backend.paths")
  local source = paths.get_python_root() .. "expose.py"
  
  -- 1. Determine IPython Startup Directory
  local ipython_dir = vim.fn.expand("~/.ipython/profile_default/startup/")
  if vim.fn.has("win32") == 1 then
      ipython_dir = vim.fn.expand("$USERPROFILE/.ipython/profile_default/startup/")
  end

  if vim.fn.isdirectory(ipython_dir) == 0 then
      vim.fn.mkdir(ipython_dir, "p")
  end

  local target = ipython_dir .. "99_scivim_expose.py"

  -- 2. Check Source
  if vim.fn.filereadable(source) == 0 then
      vim.notify("❌ Could not find source file: " .. source, vim.log.levels.ERROR)
      return
  end

  -- 3. Install Strategy: Symlink -> WinSymlink -> Hard Copy
  local success = false
  
  -- Attempt Unix Symlink
  if vim.fn.has("unix") == 1 then
      local cmd = string.format("ln -sf '%s' '%s'", source, target)
      if vim.fn.system(cmd) == 0 then success = true end
  end

  -- Attempt Windows Symlink (Requires Admin/Dev Mode)
  if not success and vim.fn.has("win32") == 1 then
      local cmd = string.format("cmd /c mklink \"%s\" \"%s\"", target, source)
      local output = vim.fn.system(cmd)
      -- Check for success message or lack of error
      if output and not output:lower():match("privilege") then success = true end
  end

  -- Fallback: Hard Copy
  if not success then
      local content = vim.fn.readfile(source)
      vim.fn.writefile(content, target)
      vim.notify("⚠️  Symlink failed (Permissions?). Created a HARD COPY instead.\nNote: You must reinstall if you update the plugin.", vim.log.levels.WARN)
  else
      vim.notify("✅ SciVim hooked into IPython successfully!\nLocation: " .. target, vim.log.levels.INFO)
  end
end

--- Start the interactive visualization wizard
function M.start(ctx)
  M.wizard.start(ctx) 
end

--- Quick start with a specific chart type
function M.quick(chart_id)
  M.wizard.quick_start(chart_id)
end

--- Start from a preset template
function M.template(template_name)
  M.wizard.start_from_template(template_name)
end

--- Inspect available data columns
function M.inspect()
  require("scivim.ui.inspector").show()
end

--- User command to launch the live transformation UI
function M.run_transform()
  M.transform.inspect_transform()
end

--- Reload context from Python
function M.reload()
  M.context.reload()
  vim.notify("📊 Context reloaded", vim.log.levels.INFO)
end

--- Save current visualization as a snippet
function M.save_snippet(name)
  M.snippets.save(name)
end

--- Load a saved snippet
function M.load_snippet()
  M.snippets.load()
end

--- Show snippet library
function M.snippets_list()
  M.snippets.list()
end

--- Preview the current specification
function M.show_preview()
  M.preview.show_preview()
end

--- Setup plugin with user configuration
function M.setup(user_config)
  M.config.setup(user_config)
  
  -- Create commands
  vim.api.nvim_create_user_command("VizStart", function() M.start() end, {})
  
  vim.api.nvim_create_user_command("VizQuick", function(opts)
    M.quick(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizTemplate", function(opts)
    M.template(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizExplorer", function()
    require("scivim.ui.explorer").show_explorer()
  end, {})
  
  vim.api.nvim_create_user_command("VizInspect", function() M.inspect() end, {})
  
  vim.api.nvim_create_user_command("VizTransform", function() 
    require("scivim.ui.transform").inspect_transform() 
  end, {})
  
  vim.api.nvim_create_user_command("VizReload", function() M.reload() end, {})
  
  vim.api.nvim_create_user_command("VizSave", function(opts)
    M.save_snippet(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizLoad", function() M.load_snippet() end, {})
  vim.api.nvim_create_user_command("VizSnippets", function() M.snippets_list() end, {})
  vim.api.nvim_create_user_command("VizPreview", function() M.show_preview() end, {})
  
  vim.api.nvim_create_user_command("VizInstall", function() M.install_ipython() end, {})
  
  -- Auto-reload context on file change
  if M.config.get().auto_reload then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = M.config.get().json_filename,
      callback = function() M.reload() end,
    })
  end

  -- [[ CLEANUP ON EXIT ]]
  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      -- OPTIMIZATION: Do NOT delete the data cache on exit.
      -- Preserves data for parallel instances and faster restarts.
      require("scivim.backend.client").stop_daemon()
    end,
  })
  
  vim.notify("🔬 SciVim loaded", vim.log.levels.INFO)
end

return M
-- /home/tanzious/scivim/OLD_ALLS/all.lua
-- /home/tanzious/scivim/OLD_ALLS/all.lua
-- /home/tanzious/scivim/OLD_ALLS/all.lua
-- /home/tanzious/scivim/OLD_ALLS/all.lua
-- /home/tanzious/scivim/OLD_ALLS/all.lua
-- /home/tanzious/scivim/OLD_ALLS/all.lua
-- /home/tanzious/scivim/OLD_ALLS
-- /home/tanzious/scivim/OLD_ALLS
-- This file is in /lua/init.lua
-- =========================================================================
-- SCIVIM - Scientific Visualization for Neovim
-- =========================================================================
local M = {}

-- Lazy load submodules with NEW PATHS
local modules = {
  config    = "scivim.config",
  -- Core Logic
  charts    = "scivim.core.charts",
  context   = "scivim.core.context",
  generator = "scivim.core.generator",
  snippets  = "scivim.core.snippets",
  stats     = "scivim.core.stats",
  -- UI Components
  wizard    = "scivim.ui.wizard",
  preview   = "scivim.ui.preview",
  transform = "scivim.ui.transform",
  explorer  = "scivim.ui.explorer", -- [[ NEW: Explorer Module ]]
}

-- Auto-loader for submodules
setmetatable(M, {
  __index = function(t, key)
    if modules[key] then
      local ok, mod = pcall(require, modules[key])
      if ok then
        rawset(t, key, mod)
        return mod
      end
    end
    return nil
  end
})

-- -------------------------------------------------------------------------
-- PUBLIC API
-- -------------------------------------------------------------------------

--- Install the IPython startup script (Symlink)
function M.install_ipython()
  local paths = require("scivim.backend.paths")
  local source = paths.get_python_root() .. "expose.py"
  
  -- 1. Determine IPython Startup Directory
  local ipython_dir = vim.fn.expand("~/.ipython/profile_default/startup/")
  if vim.fn.has("win32") == 1 then
      -- Windows usually keeps it in %USERPROFILE%
      ipython_dir = vim.fn.expand("$USERPROFILE/.ipython/profile_default/startup/")
  end

  -- 2. Create directory if it doesn't exist
  if vim.fn.isdirectory(ipython_dir) == 0 then
      vim.fn.mkdir(ipython_dir, "p")
  end

  local target = ipython_dir .. "99_scivim_expose.py"

  -- 3. Check if source exists
  if vim.fn.filereadable(source) == 0 then
      vim.notify("❌ Could not find source file: " .. source, vim.log.levels.ERROR)
      return
  end

  -- 4. Create Symlink
  local cmd = string.format("ln -sf '%s' '%s'", source, target)
  
  if vim.fn.has("win32") == 1 then
      -- Windows mklink syntax: mklink Link Target
      cmd = string.format("cmd /c mklink \"%s\" \"%s\"", target, source)
  end

  local output = vim.fn.system(cmd)
  
  if vim.v.shell_error == 0 then
      vim.notify("✅ SciVim hooked into IPython successfully!\nLocation: " .. target, vim.log.levels.INFO)
  else
      vim.notify("⚠️  Symlink failed (Permissions?).\nYou should manually copy:\n" .. source .. "\nTO:\n" .. target, vim.log.levels.WARN)
  end
end

--- Start the interactive visualization wizard
function M.start(ctx)
  M.wizard.start(ctx) -- Updated to accept optional context
end

--- Quick start with a specific chart type
function M.quick(chart_id)
  M.wizard.quick_start(chart_id)
end

--- Start from a preset template
function M.template(template_name)
  M.wizard.start_from_template(template_name)
end

--- Inspect available data columns
function M.inspect()
  require("scivim.ui.inspector").show()
end

--- User command to launch the live transformation UI
function M.run_transform()
  -- Now points to the router function
  M.transform.inspect_transform()
end

--- Reload context from Python
function M.reload()
  M.context.reload()
  vim.notify("📊 Context reloaded", vim.log.levels.INFO)
end

--- Save current visualization as a snippet
function M.save_snippet(name)
  M.snippets.save(name)
end

--- Load a saved snippet
function M.load_snippet()
  M.snippets.load()
end

--- Show snippet library
function M.snippets_list()
  M.snippets.list()
end

--- Preview the current specification
function M.show_preview()
  M.preview.show_preview()
end

--- Setup plugin with user configuration
function M.setup(user_config)
  M.config.setup(user_config)
  
  -- Create commands
  vim.api.nvim_create_user_command("VizStart", function() M.start() end, {})
  
  vim.api.nvim_create_user_command("VizQuick", function(opts)
    M.quick(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizTemplate", function(opts)
    M.template(opts.args)
  end, { nargs = 1 })
  
  -- [[ NEW: Explorer Command ]]
  vim.api.nvim_create_user_command("VizExplorer", function()
    require("scivim.ui.explorer").show_explorer()
  end, {})
  
  vim.api.nvim_create_user_command("VizInspect", function() M.inspect() end, {})
  
  -- [[ UPDATED: Transform uses the Router ]]
  vim.api.nvim_create_user_command("VizTransform", function() 
    require("scivim.ui.transform").inspect_transform() 
  end, {})
  
  vim.api.nvim_create_user_command("VizReload", function() M.reload() end, {})
  
  vim.api.nvim_create_user_command("VizSave", function(opts)
    M.save_snippet(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizLoad", function() M.load_snippet() end, {})
  vim.api.nvim_create_user_command("VizSnippets", function() M.snippets_list() end, {})
  vim.api.nvim_create_user_command("VizPreview", function() M.show_preview() end, {})
  
  -- NEW: Installation Helper
  vim.api.nvim_create_user_command("VizInstall", function() M.install_ipython() end, {})
  
  -- Auto-reload context on file change
  if M.config.get().auto_reload then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = M.config.get().json_filename,
      callback = function() M.reload() end,
    })
  end

  -- [[ NEW: CLEANUP ON EXIT ]]
  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
      -- Recursive delete (rm -rf) of the cache directory
      if vim.fn.isdirectory(cache_dir) == 1 then
        vim.fn.delete(cache_dir, "rf")
      end
      
      -- Also stop the daemon process if running
      require("scivim.backend.client").stop_daemon()
    end,
  })
  
  vim.notify("🔬 SciVim loaded", vim.log.levels.INFO)
end

return M
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

--This file is in /lua/backend/client.lua

-- =========================================================================
-- CLIENT - Persistent Python Daemon Client
-- =========================================================================
local M = {}

-- 1. Import the paths module to locate the python script dynamically
local paths = require("scivim.backend.paths")

local daemon_state = {
  job_id = nil,
  stdout_buffer = "",
  callback_queue = {}, -- FIFO queue for pending requests
}

-- 2. Updated to use the robust path finder
local function get_script_path()
   return paths.get_daemon_script()
end

--- Restart or Start the Python Daemon
function M.ensure_daemon()
  if daemon_state.job_id and vim.fn.jobwait({daemon_state.job_id}, 0)[1] == -1 then
    return -- Already running
  end

  local script_path = get_script_path()
  local python_cmd = vim.g.python3_host_prog or "python3"

  daemon_state.stdout_buffer = ""
  daemon_state.callback_queue = {}

  daemon_state.job_id = vim.fn.jobstart({python_cmd, script_path}, {
    on_stdout = function(_, data, _)
      if not data then return end
      
      -- 1. Append new data to buffer
      for i, chunk in ipairs(data) do
        daemon_state.stdout_buffer = daemon_state.stdout_buffer .. chunk
        if i < #data then
          daemon_state.stdout_buffer = daemon_state.stdout_buffer .. "\n"
        end
      end

      -- 2. Process complete lines (JSON objects)
      while true do
        local line_end = string.find(daemon_state.stdout_buffer, "\n")
        if not line_end then break end

        local line = string.sub(daemon_state.stdout_buffer, 1, line_end - 1)
        daemon_state.stdout_buffer = string.sub(daemon_state.stdout_buffer, line_end + 1)

        if line ~= "" then
          local callback = table.remove(daemon_state.callback_queue, 1)
          if callback then
            local ok, parsed = pcall(vim.json.decode, line)
            local result = ok and parsed or { error = "JSON Parse Fail: " .. line }
            
            vim.schedule(function()
              callback(result)
            end)
          end
        end
      end
    end,

    on_stderr = function(_, data, _)
      -- Log stderr if needed
    end,

    on_exit = function(_, code, _)
      daemon_state.job_id = nil
      for _, cb in ipairs(daemon_state.callback_queue) do
        cb({ error = "Daemon process crashed or exited (Code: " .. code .. ")" })
      end
      daemon_state.callback_queue = {}
    end,
    
    detach = false, 
  })
end

--- Send a request to the persistent daemon
function M.run_transform_async(df_name, lib, is_lazy, code, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." })
    return -1
  end

  local temp_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  
  -- Try feather first
  local feather_path = temp_dir .. "/" .. df_name .. ".feather"
  local pkl_path = temp_dir .. "/" .. df_name .. ".pkl"

  local file_path = pkl_path
  if vim.fn.filereadable(feather_path) == 1 then
      file_path = feather_path
  end

  local input_data = {
    file_path = file_path,
    lib = lib,
    is_lazy = is_lazy,
    code = code
  }

  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
  return daemon_state.job_id
end

--- Get metadata for specific DataFrames (or all if names is nil)
--- @param names table|nil List of dataframe names to fetch (optional filter)
--- @param callback function(result_table)
function M.get_all_metadata(names, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  
  local input_data = {
    type = "metadata_all",
    cache_dir = cache_dir,
    names = names -- [[ NEW: Passing the filter list to backend ]]
  }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

--- Analyze relationships between DataFrames
function M.analyze_relationships(callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  local input_data = { type = "analyze_relationships", cache_dir = cache_dir }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

--- Stop daemon
function M.stop_daemon()
  if daemon_state.job_id then
    vim.fn.jobstop(daemon_state.job_id)
    daemon_state.job_id = nil
  end
end

return M


--  This file is in lua/scivim/backend/paths.lua
local M = {}

function M.get_plugin_root()
  -- Get the path to this file, then go up 4 levels to the root
  local current_file = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(current_file, ":h:h:h:h")
end

-- This was missing!
function M.get_python_root()
  return M.get_plugin_root() .. "/python/scivim/"
end

function M.get_daemon_script()
  return M.get_python_root() .. "daemon.py"
end

return M

        
--This file is in /lua/core/charts.lua
-- =========================================================================
-- CHARTS - Visualization Definitions
-- =========================================================================
local M = {}

M.CHART_TYPES = {
  -- -------------------------------------------------------------------------
  -- RELATIONAL
  -- -------------------------------------------------------------------------
  { 
    name = "Scatter Plot", 
    id = "scatter", 
    icon = "󰄄", 
    category = "relational",
    req = {"x", "y"}, 
    opt = {"hue", "style", "size", "alpha"},
    desc = "Visualizes relationship between two continuous variables." 
  },
  { 
    name = "Line Plot", 
    id = "line", 
    icon = "", 
    category = "relational",
    req = {"x"}, 
    opt = {"y", "hue", "style", "markers"}, 
    desc = "Displays data trends over time or an ordered series." 
  },
  { 
    name = "Step Plot", 
    id = "step", 
    icon = "󰐕", 
    category = "relational", 
    req = {"x", "y"}, 
    opt = {"hue", "where"},
    desc = "Step line plot. Good for discrete changes over time." 
  },
  { 
    name = "Area Plot", 
    id = "area", 
    icon = "", 
    category = "relational", 
    req = {"x", "y"}, 
    opt = {"hue", "alpha"},
    desc = "Filled area plot. Useful for showing volume or accumulation." 
  },
  { 
    name = "Log-Scale Scatter", 
    id = "log_scatter", 
    icon = "󰄄", 
    category = "relational", 
    req = {"x", "y"}, 
    opt = {"hue", "size"},
    desc = "Scatter plot with Logarithmic Y-Axis." 
  },
  { 
    name = "Linear Regression", 
    id = "lm", 
    icon = "📈", 
    category = "relational",
    req = {"x", "y"}, 
    opt = {"hue", "col"}, 
    desc = "Scatter plot with a linear regression model fit." 
  },
  
  -- -------------------------------------------------------------------------
  -- DISTRIBUTION
  -- -------------------------------------------------------------------------
  { 
    name = "Histogram", 
    id = "hist", 
    icon = "📊", 
    category = "distribution",
    req = {"x"}, 
    opt = {"hue", "kde", "bins"},
    desc = "Binned frequency distribution of a variable." 
  },
  { 
    name = "KDE Plot", 
    id = "kde", 
    icon = "〰", 
    category = "distribution",
    req = {"x"}, 
    opt = {"hue", "fill"},
    desc = "Kernel Density Estimate. A smooth version of a histogram." 
  },
  { 
    name = "Violin Plot", 
    id = "violin", 
    icon = "", 
    category = "distribution", 
    req = {"x", "y"}, 
    opt = {"hue"},
    desc = "Shows the probability density of the data at different values." 
  },
  { 
    name = "Joint Plot", 
    id = "joint", 
    icon = "並", 
    category = "distribution",
    req = {"x", "y"}, 
    opt = {"hue", "kind"}, 
    desc = "Bivariate plot with marginal univariate distributions." 
  },

  -- -------------------------------------------------------------------------
  -- CATEGORICAL
  -- -------------------------------------------------------------------------
  { 
    name = "Box Plot", 
    id = "box", 
    icon = "󰡃", 
    category = "categorical",
    req = {"x", "y"}, 
    opt = {"hue"}, 
    desc = "Shows quartiles, median, and outliers." 
  },
  { 
    name = "Bar Plot", 
    id = "bar", 
    icon = "📊", 
    category = "categorical",
    req = {"x", "y"}, 
    opt = {"hue"}, 
    desc = "Point estimates (mean) with confidence intervals." 
  },
  { 
    name = "Count Plot", 
    id = "count", 
    icon = "", 
    category = "categorical",
    req = {"x"}, 
    opt = {"hue"}, 
    desc = "Shows the count of observations in each categorical bin." 
  },
  { 
    name = "Strip Plot", 
    id = "strip", 
    icon = "", 
    category = "categorical",
    req = {"x", "y"}, 
    opt = {"hue", "jitter"}, 
    desc = "Simple categorical scatter plot showing all data points." 
  },

  -- -------------------------------------------------------------------------
  -- MATRIX
  -- -------------------------------------------------------------------------
  { 
    name = "Heatmap (Corr)", 
    id = "heat", 
    icon = "▦", 
    category = "matrix",
    req = {}, 
    opt = {"cmap"},
    desc = "Visualizes the correlation matrix of numeric columns." 
  },
  { 
    name = "Pair Plot", 
    id = "pair", 
    icon = "", 
    category = "matrix",
    req = {}, 
    opt = {"hue"},
    desc = "Plot pairwise relationships in a dataset." 
  },
  { 
    name = "Scatter Matrix (SPLOM)", 
    id = "splom", 
    icon = "▦", 
    category = "matrix", 
    req = {}, 
    opt = {"hue"},
    desc = "Grid of scatter plots showing relationships between numeric variables." 
  },
{ 
    name = "Parallel Coordinates", 
    id = "parcoords", 
    icon = "", 
    category = "multivariate",
    req = {}, 
    opt = {"hue"}, -- In Plotly, color is used for the lines
    desc = "Visualizes high-dimensional data as lines across parallel axes." 
  },
  { 
    name = "3D Scatter", 
    id = "scatter3d", 
    icon = "🧊", 
    category = "multivariate", 
    req = {"x", "y", "z"}, 
    opt = {"hue", "size"},
    desc = "Scatter plot in three dimensions. Good for PCA/Clustering." 
  },
  { 
    name = "Sunburst", 
    id = "sunburst", 
    icon = "◎", 
    category = "hierarchical", 
    req = {"x"}, -- In this context, 'x' will be the list of path columns
    opt = {"y"}, -- 'y' can be the 'values' (size of wedge)
    desc = "Hierarchical data represented by concentric rings." 
  },
  { 
    name = "Sankey", 
    id = "sankey", 
    icon = "ﬡ", 
    category = "flow", 
    req = {"source", "target", "value"}, -- Requires custom mapping logic in Wizard
    opt = {}, 
    desc = "Flow diagram where width of arrows is proportional to flow rate." 
  },












}

function M.get_chart(chart_id)
  for _, chart in ipairs(M.CHART_TYPES) do
    if chart.id == chart_id then
      return chart
    end
  end
  return nil
end

return M



-- This file is in /lua/core/context.lua
-- =========================================================================
-- CONTEXT - Data Loading & Management (Core)
-- =========================================================================
local M = {}

local config = require("scivim.config")

local context_cache = {
  all_data = nil,
  active_df_name = nil,
  mtime = nil,
}

--- Load ALL contexts from JSON file
function M.load_all()
  local cfg = config.get()
  local filename = cfg.json_filename
  
  if cfg.features.cache_context and context_cache.all_data and context_cache.mtime then
    local stat = vim.loop.fs_stat(filename)
    if stat and stat.mtime.sec == context_cache.mtime then
      return context_cache.all_data, nil
    end
  end
  
  local ok, content = pcall(vim.fn.readfile, filename)
  if not ok then 
    return nil, "Run `vim_expose()` in Python first.\nFile not found: " .. filename
  end
  
  local json_str = table.concat(content, "\n")
  local parse_ok, data = pcall(vim.json.decode, json_str)
  if not parse_ok then
    return nil, "Failed to parse JSON: " .. tostring(data)
  end
  
  if type(data) ~= "table" or vim.tbl_isempty(data) then
     return nil, "No DataFrames found in context file."
  end
  
  if cfg.features.cache_context then
    local stat = vim.loop.fs_stat(filename)
    context_cache.all_data = data
    context_cache.mtime = stat and stat.mtime.sec or nil
  end
  
  return data, nil
end

--- Get the currently active DataFrame context
function M.get_active()
  local all_data, err = M.load_all()
  if not all_data then return nil, err end

  if context_cache.active_df_name and all_data[context_cache.active_df_name] then
    return all_data[context_cache.active_df_name], nil
  end
  
  local df_names = vim.tbl_keys(all_data)
  if #df_names > 0 then
    context_cache.active_df_name = df_names[1]
    return all_data[context_cache.active_df_name], nil
  end
  
  return nil, "No DataFrames found in context file."
end

--- Set the currently active DataFrame by name
function M.set_active(name)
  local all_data, err = M.load_all()
  if not all_data then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if all_data[name] then
    context_cache.active_df_name = name
    vim.notify("📊 Active DataFrame set to: " .. name, vim.log.levels.INFO)
  else
    vim.notify("DataFrame not found: " .. name, vim.log.levels.ERROR)
  end
end

function M.reload()
  context_cache.all_data = nil
  context_cache.mtime = nil
  return M.get_active()
end

-- Helper: Map JSON metadata to internal structure
function M.create_column_entry(col_name, meta, index)
  meta = meta or {}
  return {
    index = index or 0,
    name = col_name,
    dtype = meta.dtype or "unknown",
    null_count = meta.null_count or 0,
    unique_count = meta.unique_count or "?",
    -- Numeric Stats
    min_val = meta.min_val,
    max_val = meta.max_val,
    mean_val = meta.mean_val,
    std_val = meta.std_val,
    median_val = meta.median_val,
    -- Boxplot Stats
    q1 = meta.q1,
    q3 = meta.q3,
    outlier_count = meta.outlier_count or 0,
    -- Distribution Data
    sample_values = meta.sample_values or {},
    hist_counts = meta.hist_counts,
  }
end

-- Helper: Check if dtype is numeric
function M._is_numeric(dtype)
  if not dtype then return false end
  local d = dtype:lower()
  return d:match("int") or d:match("float") or d:match("double") or d:match("number")
end

return M



--This file is in  lua/scivim/core/generator.lua
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

-- This file is in /lua/core/snippets.lua
--  =========================================================================
-- SNIPPETS - Save and Load Visualization Snippets (Snacks Edition)
-- =========================================================================
local M = {}

-- UPDATED IMPORTS:
local config = require("scivim.config")
local generator = require("scivim.core.generator")
local Snacks = require("snacks")

--- Get snippets file path
local function get_snippets_file()
  local cfg = config.get()
  return cfg.snippets_dir .. "/snippets.json"
end

--- Load all snippets from disk
local function load_snippets()
  local file = get_snippets_file()
  local ok, content = pcall(vim.fn.readfile, file)
  if not ok then return {} end
  
  local json_str = table.concat(content, "\n")
  local parse_ok, data = pcall(vim.json.decode, json_str)
  return parse_ok and data or {}
end

--- Save snippets to disk
local function save_snippets(snippets)
  local file = get_snippets_file()
  local json_str = vim.json.encode(snippets)
  vim.fn.writefile(vim.split(json_str, "\n"), file)
end

--- Save current visualization as a snippet
function M.save(name)
  if not name or name == "" then
    vim.notify("Snippet name cannot be empty", vim.log.levels.ERROR)
    return
  end
  
  local lines = generator.get_last_viz_code and generator.get_last_viz_code() or {}
  -- Note: You might need to expose get_last_viz_code in generator.lua if strictly hidden,
  -- or rely on the buffer content if the generator isn't caching it.
  
  -- Fallback: If generator doesn't cache, we can't save easily without grabbing buffer lines.
  -- Assuming generator has this method (it was in your original snippets.lua)
  
  if #lines == 0 then
    vim.notify("No visualization code found (Generator state empty)", vim.log.levels.WARN)
    return
  end
  
  local snippets = load_snippets()
  snippets[name] = {
    code = lines,
    created = os.time(),
    description = lines[1] or "",
  }
  
  save_snippets(snippets)
  vim.notify(config.icon("save") .. " Saved snippet: " .. name, vim.log.levels.INFO)
end

--- Load a snippet (Simple UI)
function M.load()
  M.list() -- Re-use the list UI for loading
end

--- List all snippets (Snacks Picker)
function M.list()
  local snippets = load_snippets()
  
  if vim.tbl_isempty(snippets) then
    vim.notify("No saved snippets found", vim.log.levels.WARN)
    return
  end

  local items = {}
  for name, snip in pairs(snippets) do
    table.insert(items, {
      text = name,
      snippet = snip,
      created = os.date("%Y-%m-%d", snip.created)
    })
  end

  Snacks.picker.pick({
    items = items,
    title = "📚 Visualization Snippets",
    layout = "vscode",
    
    format = function(item)
      return {
        { "🔖 ", "SnacksIcon" },
        { item.text, "Normal" },
        { "  " },
        { item.created, "Comment" }
      }
    end,
    
    preview = function(ctx)
      local code = ctx.item.snippet.code
      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, code)
      vim.bo[ctx.buf].modifiable = false
      vim.bo[ctx.buf].filetype = "python"
    end,
    
    confirm = function(picker, item)
      picker:close()
      local cursor = vim.api.nvim_win_get_cursor(0)
      vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, item.snippet.code)
      vim.notify(config.icon("load") .. " Loaded: " .. item.text, vim.log.levels.INFO)
    end,
    
    win = {
      input = {
        keys = {
          ["<c-d>"] = { "delete_snippet", mode = { "n", "i" } },
        }
      }
    },
    
    actions = {
      delete_snippet = function(picker, item)
        picker:close()
        M.delete(item.text)
        -- Re-open after delete
        vim.schedule(function() M.list() end)
      end
    }
  })
end

--- Delete a snippet
function M.delete(name)
  local snippets = load_snippets()
  if not snippets[name] then return end
  
  snippets[name] = nil
  save_snippets(snippets)
  vim.notify("🗑️  Deleted snippet: " .. name, vim.log.levels.INFO)
end

return M



--This file is in /lua/core/stats.lua
-- =========================================================================
-- STATS - Statistical Annotations and Enhancements
-- =========================================================================
local M = {}

local config = require("scivim.config")

-- Statistical features available for each chart type
M.STATS_FEATURES = {
  scatter = {
    { id = "corr", name = "Correlation Coefficient", desc = "Add Pearson r and p-value" },
    { id = "regline", name = "Regression Line", desc = "Add best-fit line" },
    { id = "ci", name = "Confidence Interval", desc = "Add 95% confidence band" },
  },
  box = {
    { id = "mean", name = "Mean Markers", desc = "Show mean values" },
    { id = "sig", name = "Significance Tests", desc = "Add statistical significance indicators" },
    { id = "outliers", name = "Highlight Outliers", desc = "Mark outliers in red" },
  },
  hist = {
    { id = "normal", name = "Normal Curve", desc = "Overlay normal distribution" },
    { id = "mean", name = "Mean Line", desc = "Vertical line at mean" },
    { id = "median", name = "Median Line", desc = "Vertical line at median" },
    { id = "kde", name = "KDE Overlay", desc = "Add kernel density estimate" },
  },
  violin = {
    { id = "quartiles", name = "Quartile Lines", desc = "Show Q1, Q2, Q3" },
    { id = "mean", name = "Mean Points", desc = "Add mean markers" },
  },
  bar = {
    { id = "values", name = "Value Labels", desc = "Show bar values on top" },
    { id = "sig", name = "Significance Bars", desc = "Add significance brackets" },
  },
  line = {
    { id = "ci", name = "Confidence Interval", desc = "Add shaded confidence band" },
    { id = "trend", name = "Trend Line", desc = "Add polynomial trend" },
  },
}

--- Get available stats for a chart type
---@param chart_id string Chart identifier
---@return table|nil Available stats features
function M.get_available_stats(chart_id)
  return M.STATS_FEATURES[chart_id]
end

--- Prompt user to select statistical enhancements
---@param spec table Visualization spec
---@param callback function Callback with updated spec
function M.select_stats(spec, callback)
  local available = M.get_available_stats(spec.chart.id)
  
  if not available or #available == 0 then
    callback(spec)
    return
  end
  
  local items = {}
  for _, stat in ipairs(available) do
    table.insert(items, stat.name)
  end
  table.insert(items, 1, "(None)")
  
  vim.ui.select(items, {
    prompt = "📊 Add Statistical Features:",
    format_item = function(item)
      if item == "(None)" then
        return item
      end
      for _, stat in ipairs(available) do
        if stat.name == item then
          return stat.name .. " - " .. stat.desc
        end
      end
      return item
    end,
  }, function(choice)
    if not choice or choice == "(None)" then
      callback(spec)
      return
    end
    
    -- Find selected stat
    for _, stat in ipairs(available) do
      if stat.name == choice then
        spec.stats = spec.stats or {}
        table.insert(spec.stats, stat.id)
        break
      end
    end
    
    callback(spec)
  end)
end

--- Generate statistical enhancement code
---@param spec table Visualization spec
---@return table Code lines to append
function M.generate_stats_code(spec)
  if not spec.stats or #spec.stats == 0 then
    return {}
  end
  
  local lines = {}
  
  for _, stat_id in ipairs(spec.stats) do
    local stat_lines = M._generate_stat(stat_id, spec)
    vim.list_extend(lines, stat_lines)
  end
  
  return lines
end

--- Generate code for specific statistical feature
---@param stat_id string Statistical feature ID
---@param spec table Visualization spec
---@return table Code lines
function M._generate_stat(stat_id, spec)
  local lines = {}
  local cfg = config.get()
  
  -- Correlation coefficient for scatter plots
  if stat_id == "corr" then
    if cfg.generate_comments then
      table.insert(lines, "# Add correlation coefficient")
    end
    table.insert(lines, "from scipy import stats as scipy_stats")
    table.insert(lines, string.format(
      "r, p = scipy_stats.pearsonr(%s['%s'].dropna(), %s['%s'].dropna())",
      spec.df, spec.x, spec.df, spec.y
    ))
    table.insert(lines, "plt.text(0.05, 0.95, f'r = {r:.3f}, p = {p:.3f}',")
    table.insert(lines, "         transform=plt.gca().transAxes, fontsize=10,")
    table.insert(lines, "         verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))")
  
  -- Regression line
  elseif stat_id == "regline" then
    if cfg.generate_comments then
      table.insert(lines, "# Add regression line")
    end
    table.insert(lines, "import numpy as np")
    table.insert(lines, string.format("x_data = %s['%s'].dropna()", spec.df, spec.x))
    table.insert(lines, string.format("y_data = %s['%s'].dropna()", spec.df, spec.y))
    table.insert(lines, "z = np.polyfit(x_data, y_data, 1)")
    table.insert(lines, "p = np.poly1d(z)")
    table.insert(lines, "plt.plot(x_data, p(x_data), 'r--', alpha=0.8, linewidth=2)")
  
  -- Mean line for histogram
  elseif stat_id == "mean" and spec.chart.id == "hist" then
    if cfg.generate_comments then
      table.insert(lines, "# Add mean line")
    end
    table.insert(lines, string.format("mean_val = %s['%s'].mean()", spec.df, spec.x))
    table.insert(lines, "plt.axvline(mean_val, color='red', linestyle='--', linewidth=2, label=f'Mean: {mean_val:.2f}')")
    table.insert(lines, "plt.legend()")
  
  -- Median line for histogram
  elseif stat_id == "median" then
    if cfg.generate_comments then
      table.insert(lines, "# Add median line")
    end
    table.insert(lines, string.format("median_val = %s['%s'].median()", spec.df, spec.x))
    table.insert(lines, "plt.axvline(median_val, color='green', linestyle='--', linewidth=2, label=f'Median: {median_val:.2f}')")
    table.insert(lines, "plt.legend()")
  
  -- Normal curve overlay
  elseif stat_id == "normal" then
    if cfg.generate_comments then
      table.insert(lines, "# Add normal distribution overlay")
    end
    table.insert(lines, "import numpy as np")
    table.insert(lines, "from scipy.stats import norm")
    table.insert(lines, string.format("mu = %s['%s'].mean()", spec.df, spec.x))
    table.insert(lines, string.format("sigma = %s['%s'].std()", spec.df, spec.x))
    table.insert(lines, string.format("x_range = np.linspace(%s['%s'].min(), %s['%s'].max(), 100)", 
      spec.df, spec.x, spec.df, spec.x))
    table.insert(lines, "plt.plot(x_range, norm.pdf(x_range, mu, sigma) * len(" .. spec.df .. 
      ") * (x_range[1] - x_range[0]), 'r-', linewidth=2, label='Normal')")
    table.insert(lines, "plt.legend()")
  
  -- KDE overlay for histogram
  elseif stat_id == "kde" then
    if cfg.generate_comments then
      table.insert(lines, "# Add KDE overlay")
    end
    table.insert(lines, string.format("sns.kdeplot(data=%s, x='%s', color='red', linewidth=2)", 
      spec.df, spec.x))
  
  -- Mean markers for box/violin plots
  elseif stat_id == "mean" and (spec.chart.id == "box" or spec.chart.id == "violin") then
    if cfg.generate_comments then
      table.insert(lines, "# Add mean markers")
    end
    table.insert(lines, "plt.gca().scatter([], [], marker='D', color='red', s=100, label='Mean', zorder=3)")
    table.insert(lines, "# Note: Use showmeans=True in plot function for automatic mean markers")
  
  -- Value labels for bar plots
  elseif stat_id == "values" then
    if cfg.generate_comments then
      table.insert(lines, "# Add value labels")
    end
    table.insert(lines, "ax = plt.gca()")
    table.insert(lines, "for container in ax.containers:")
    table.insert(lines, "    ax.bar_label(container, fmt='%.2f')")
  
  -- Confidence interval
  elseif stat_id == "ci" then
    if cfg.generate_comments then
      table.insert(lines, "# Confidence interval already included in plot")
    end
    -- Most seaborn plots include CI by default
  
  -- Significance tests (placeholder)
  elseif stat_id == "sig" then
    if cfg.generate_comments then
      table.insert(lines, "# Statistical significance testing")
      table.insert(lines, "# TODO: Add your significance test logic here")
    end
  end
  
  return lines
end

--- Add statistical summary text box
---@param spec table Visualization spec
---@return table Code lines
function M.add_summary_box(spec)
  local lines = {}
  local cfg = config.get()
  
  if cfg.generate_comments then
    table.insert(lines, "# Add statistical summary box")
  end
  
  if spec.x and spec.y then
    table.insert(lines, string.format(
      "summary = %s[['%s', '%s']].describe()",
      spec.df, spec.x, spec.y
    ))
  elseif spec.x then
    table.insert(lines, string.format(
      "summary = %s['%s'].describe()",
      spec.df, spec.x
    ))
  end
  
  table.insert(lines, "summary_text = summary.to_string()")
  table.insert(lines, "plt.text(1.02, 0.5, summary_text, transform=plt.gca().transAxes,")
  table.insert(lines, "         fontsize=8, verticalalignment='center',")
  table.insert(lines, "         bbox=dict(boxstyle='round', facecolor='lightgray', alpha=0.5))")
  
  return lines
end

--- Quick statistical test between groups
---@param df_name string DataFrame name
---@param x_col string X column (groups)
---@param y_col string Y column (values)
---@return table Code lines for t-test or ANOVA
function M.generate_test_code(df_name, x_col, y_col)
  local lines = {}
  
  table.insert(lines, "# Statistical test")
  table.insert(lines, "from scipy import stats as scipy_stats")
  table.insert(lines, "")
  table.insert(lines, string.format("groups = %s.groupby('%s')['%s'].apply(list)", 
    df_name, x_col, y_col))
  table.insert(lines, "")
  table.insert(lines, "# Perform one-way ANOVA")
  table.insert(lines, "f_stat, p_value = scipy_stats.f_oneway(*groups)")
  table.insert(lines, "print(f'F-statistic: {f_stat:.4f}')")
  table.insert(lines, "print(f'P-value: {p_value:.4f}')")
  table.insert(lines, "")
  table.insert(lines, "if p_value < 0.05:")
  table.insert(lines, "    print('Significant difference between groups (p < 0.05)')")
  table.insert(lines, "else:")
  table.insert(lines, "    print('No significant difference between groups (p >= 0.05)')")
  
  return lines
end

return M



    
--This file is in /lua/core/adapters/data/pandas.lua

local M = {}

-- Returns the import string required for this library
function M.get_import()
  return "import pandas as pd"
end

-- Returns code to filter data
function M.filter(df_var, condition)
  -- Smart check: is it a query string or a python expression?
  if condition:match(df_var) or condition:match("df%[") then
    return condition
  end
  return string.format("%s.query(\"%s\")", df_var, condition)
end

-- Returns code to aggregate data
function M.agg(df_var, group_cols, target_col, func)
  return string.format("%s.groupby('%s')['%s'].%s().reset_index()", 
    df_var, group_cols, target_col, func)
end

-- Returns code to convert to a format plotting libraries understand (usually pandas)
function M.normalize(df_var)
  return df_var -- It's already pandas
end

return M










--This file is in /lua/core/adapters/data/polars.lua

local M = {}

function M.get_import()
  return "import polars as pl"
end

function M.filter(df_var, condition)
  return string.format("%s.filter(%s)", df_var, condition)
end

function M.agg(df_var, group_cols, target_col, func)
  -- Polars syntax is very different
  return string.format("%s.group_by('%s').agg(pl.col('%s').%s())", 
    df_var, group_cols, target_col, func)
end

function M.normalize(df_var)
  -- Most plotters don't speak Polars natively yet, so we convert
  return string.format("%s.to_pandas()", df_var)
end

return M


    
--This file is in  lua/scivim/ui/explorer.lua
local M = {}
local executor = require("scivim.backend.client")
local context = require("scivim.core.context")
local Snacks = require("snacks")

local state = {
  mode = "list", -- 'list' or 'graph'
  dfs = {},
  rels = {},
  win_list = nil,
  win_preview = nil
}

--- Show DataFrame explorer with previews
function M.show_explorer()
  -- 1. Get Source of Truth (Current Session)
  local all_data = context.load_all()
  
  if not all_data or vim.tbl_count(all_data) == 0 then
      vim.notify("No active DataFrames found. Run vim_expose() in your kernel.", vim.log.levels.WARN)
      return
  end
  
  -- 2. Extract Valid Names
  local active_names = vim.tbl_keys(all_data)
  
  -- 3. Fetch Metadata
  executor.get_all_metadata(active_names, function(meta_resp)
    if meta_resp.error then 
        vim.notify("Error: " .. meta_resp.error, vim.log.levels.ERROR)
        return 
    end
    
    -- 4. Fetch Relationships
    executor.analyze_relationships(function(rel_resp)
      -- Process DataFrames
      local df_list = {}
      for name, info in pairs(meta_resp.dataframes or {}) do
        table.insert(df_list, {
          name = name,
          shape = info.shape or {0, 0},
          columns = info.columns or {},
          head = info.head or ""
        })
      end
      
      -- Process Relationships
      local rel_list = rel_resp.relationships or {}

      if #df_list == 0 then 
          vim.notify("No DataFrames found in cache.", vim.log.levels.WARN)
          return 
      end

      -- Init State
      state.dfs = df_list
      state.rels = rel_list
      state.mode = "list"
      
      M._render_ui()
    end)
  end)
end

function M._render_ui()
  -- Calculate Layout
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local list_width = 40
  local preview_width = width - list_width - 2 -- minus borders
  
  -- Prepare Content
  local left_lines = {}
  local title = ""
  local footer = " <Tab> Switch View • <CR> Actions • q Quit "
  local title_hl = "Title"

  if state.mode == "list" then
      title = " 🐼 Active DataFrames "
      title_hl = "String" -- Greenish usually
      for _, df in ipairs(state.dfs) do
        local dim_str = string.format("(%d x %d)", df.shape[1] or 0, df.shape[2] or 0)
        -- Pad spaces for alignment
        local padding = string.rep(" ", list_width - #df.name - #dim_str - 6)
        table.insert(left_lines, string.format(" %s%s%s ", df.name, padding, dim_str))
      end
  else
      title = " 🕸️  Data Relationships "
      title_hl = "Special" -- Blue/Purple usually
      if #state.rels == 0 then
          table.insert(left_lines, "")
          table.insert(left_lines, "  (No obvious joins detected)")
      else
          for _, r in ipairs(state.rels) do
             -- Shorten if too long
             local rel_str = string.format("%s -> %s", r.from_df, r.to_df)
             table.insert(left_lines, " " .. rel_str)
          end
      end
  end

  -- Close existing windows if open (redraw)
  if state.win_list then state.win_list:close(); state.win_preview:close() end

  -- 1. ACTION HANDLER (Press Enter)
  local function open_actions()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list.win)
      local idx = cursor[1]
      
      if state.mode ~= "list" then return end
      
      local df_meta = state.dfs[idx]
      if not df_meta then return end
      
      -- Load Full Context
      local all_data = context.load_all()
      local ctx = all_data[df_meta.name]
      if not ctx then return end

      state.win_list:close()
      state.win_preview:close()

      Snacks.picker.pick({
          items = {
              { text = "📊 Visualize (Wizard)",  action = "viz", icon = "📈" },
              { text = "🛠️  Transform (Python)", action = "py",  icon = "🐍" },
              { text = "🦆 Query (SQL)",        action = "sql", icon = "💾" },
              { text = "🔍 Inspect Columns",    action = "insp", icon = "🔎" },
          },
          title = " Action: " .. ctx.name .. " ",
          layout = "vscode",
          confirm = function(picker, item)
              picker:close()
              if item.action == "viz" then require("scivim.ui.wizard").start(ctx)
              elseif item.action == "py" then require("scivim.ui.transform")._launch_python_transform(ctx)
              elseif item.action == "sql" then require("scivim.ui.sql_transform").launch(ctx)
              elseif item.action == "insp" then require("scivim.ui.inspector")._inspect_snacks(ctx)
              end
          end
      })
  end

  -- 2. CREATE LIST WINDOW
  state.win_list = Snacks.win({
    relative = "editor", row = row, col = col, width = list_width, height = height,
    border = "rounded", 
    title = title, title_pos = "center",
    footer = footer, footer_pos = "center",
    wo = { cursorline = true, winhighlight = "FloatBorder:FloatBorder,Title:"..title_hl },
    keys = {
        ["q"] = "close", ["<Esc>"] = "close",
        ["<Tab>"] = function() 
            state.mode = (state.mode == "list") and "graph" or "list"
            M._render_ui() 
        end,
        ["<CR>"] = open_actions
    }
  })
  vim.api.nvim_buf_set_lines(state.win_list.buf, 0, -1, false, left_lines)
  
  -- 3. CREATE PREVIEW WINDOW
  state.win_preview = Snacks.win({
    relative = "editor", row = row, col = col + list_width + 1, width = preview_width, height = height,
    border = "rounded", title = " Details ", title_pos = "center", interactive = false,
    wo = { winhighlight = "FloatBorder:FloatBorder" }
  })
  
  -- 4. PREVIEW UPDATER LOGIC
  local function update_preview()
    if not vim.api.nvim_win_is_valid(state.win_list.win) then return end
    local cursor = vim.api.nvim_win_get_cursor(state.win_list.win)
    local idx = cursor[1]
    local p_lines = {}
    local p_title = " Details "

    if state.mode == "list" then
        local df = state.dfs[idx]
        if df then
            p_title = string.format(" %s ", df.name)
            
            -- Header
            table.insert(p_lines, string.format("📐 Shape: %d rows x %d cols", df.shape[1], df.shape[2]))
            table.insert(p_lines, string.rep("─", preview_width))
            
            -- Columns formatted nicely
            table.insert(p_lines, "📋 Columns:")
            local col_chunk_size = math.ceil(#df.columns / 2) -- split into 2 cols if needed
            for i, c in ipairs(df.columns) do
                 if i > 20 then 
                    table.insert(p_lines, string.format("  ... (%d more)", #df.columns - 20))
                    break 
                 end
                 table.insert(p_lines, string.format("  • %s", c))
            end
            
            table.insert(p_lines, "")
            table.insert(p_lines, string.rep("─", preview_width))
            table.insert(p_lines, "👓 Head:")
            
            -- Add Head content (handling raw string from pandas to_string)
            for _, l in ipairs(vim.split(df.head, '\n')) do
                table.insert(p_lines, "  " .. l)
            end
        end
    else
        -- Relationship Mode
        local r = state.rels[idx]
        if r then
             p_title = " Relationship Info "
             table.insert(p_lines, "")
             table.insert(p_lines, " 🔗 JOIN SUGGESTION")
             table.insert(p_lines, string.rep("─", 40))
             table.insert(p_lines, string.format(" Left:  %s", r.from_df))
             table.insert(p_lines, string.format(" Right: %s", r.to_df))
             table.insert(p_lines, "")
             table.insert(p_lines, string.format(" Key:   %s == %s", r.from_col, r.to_col))
             table.insert(p_lines, string.format(" Type:  %s", r.type))
             table.insert(p_lines, "")
             table.insert(p_lines, " 📝 SQL Pattern:")
             table.insert(p_lines, " ```sql")
             table.insert(p_lines, string.format(" SELECT * FROM %s a", r.from_df))
             table.insert(p_lines, string.format(" JOIN %s b ON a.%s = b.%s", r.to_df, r.from_col, r.to_col))
             table.insert(p_lines, " ```")
        else
             table.insert(p_lines, " No relationship selected.")
        end
    end
    
    -- Highlight SQL/Code in preview
    if state.mode == "graph" then vim.bo[state.win_preview.buf].filetype = "markdown" 
    else vim.bo[state.win_preview.buf].filetype = "text" end

    vim.api.nvim_buf_set_lines(state.win_preview.buf, 0, -1, false, p_lines)
    pcall(vim.api.nvim_win_set_config, state.win_preview.win, { title = p_title })
  end

  -- Navigation Binds
  local buf = state.win_list.buf
  vim.keymap.set('n', 'j', function() vim.cmd('normal! j'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', 'k', function() vim.cmd('normal! k'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', '<Down>', function() vim.cmd('normal! j'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', '<Up>', function() vim.cmd('normal! k'); update_preview() end, { buffer = buf })
  
  -- Initial Render
  update_preview()
end

return M









--This file is in  lua/scivim/ui/inspector.lua
-- =========================================================================
-- INSPECTOR - Data Inspection UI (Snacks)
-- =========================================================================
local M = {}

local context = require("scivim.core.context")
local generator = require("scivim.core.generator")
local charts = require("scivim.core.charts")
local config = require("scivim.config")
local Snacks = require("snacks")

-- Increased width for the preview panel
local CONTENT_WIDTH = 100 

-- =========================================================================
-- MAIN ENTRY POINT
-- =========================================================================

function M.show()
  local all_data, err = context.load_all()
  if not all_data then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  -- Convert map to list
  local ctx_list = {}
  for _, data in pairs(all_data) do
    table.insert(ctx_list, data)
  end

  if #ctx_list == 0 then
    vim.notify("No DataFrames exposed via vim_expose()", vim.log.levels.WARN)
    return
  elseif #ctx_list == 1 then
    -- Only one? Just show it.
    context.set_active(ctx_list[1].name)
    M._inspect_snacks(ctx_list[1])
  else
    -- More than one? Force the user to choose.
    M._pick_dataframe(ctx_list)
  end
end

function M._pick_dataframe(ctx_list)
  local items = {}
  for _, ctx in ipairs(ctx_list) do
    local icon = ctx.lib == "polars" and config.icon("polars") or config.icon("pandas")
    
    table.insert(items, {
      text = ctx.name,
      ctx = ctx,
      icon = icon,
      comment = string.format("(%d cols)", #ctx.columns)
    })
  end

  Snacks.picker.pick({
    items = items,
    title = "Select DataFrame to Inspect",
    layout = "vscode",
    format = function(item)
      return {
        { item.icon, "SnacksIcon" },
        { " " },
        { item.text, "Normal" },
        { "  " },
        { item.comment, "Comment" }
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        context.set_active(item.ctx.name)
        M._inspect_snacks(item.ctx)
      end
    end
  })
end

function M._inspect_snacks(ctx)
  local items = {}
  
  for i, col_name in ipairs(ctx.columns) do
    local meta = ctx.metadata and ctx.metadata[col_name] or {}
    local col_data = context.create_column_entry(col_name, meta, i)
    
    local icon = "󰙨" 
    local comment = col_data.dtype
    
    if context._is_numeric(col_data.dtype) then 
        icon = "󰎠"
        if col_data.outlier_count and col_data.outlier_count > 0 then
            comment = comment .. " (⚠️ " .. col_data.outlier_count .. ")"
        end
    elseif col_data.dtype:match("date") or col_data.dtype:match("time") then 
        icon = "󰃰" 
    elseif col_data.dtype:match("bool") then 
        icon = "󰨙" 
    end

    table.insert(items, {
      text = col_name,
      idx = i,
      icon = icon,
      col = col_data, 
      comment = comment
    })
  end

  local function generate_plot_action(picker, item)
    picker:close()
    M._quick_visualize_column(ctx, item.col)
  end

  local function copy_name(picker, item)
    picker:close()
    vim.fn.setreg('+', item.text)
    vim.notify("Copied: " .. item.text)
  end
  
  local function insert_code(picker, item)
    picker:close()
    local code = ctx.lib == "polars" and string.format('pl.col("%s")', item.text) or string.format("%s['%s']", ctx.name or "df", item.text)
    vim.api.nvim_put({code}, "c", true, true)
  end

  Snacks.picker.pick({
    source = "scivim_columns",
    items = items,
    title = string.format("DataFrame: %s (%s)", ctx.name, ctx.lib or "pandas"),
    
    layout = {
      layout = {
        box = "horizontal",
        width = 0.9,
        height = 0.9,
        {
          box = "vertical",
          border = "rounded",
          title = "{title} {live} {flags}",
          width = 0.3,
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        {
          win = "preview",
          title = "{preview}",
          border = "rounded",
          width = 0.7,
        },
      }
    },
    
    format = function(item)
      local ret = {
        { string.format("%2d", item.idx), "Comment" },
        { " " },
        { item.icon, "SnacksIcon" },
        { " " },
        { item.text, "Normal" },
      }
      if item.comment:match("⚠️") then
        table.insert(ret, { " " .. item.comment, "WarningMsg" })
      else
        table.insert(ret, { " " .. item.comment, "Comment" })
      end
      return ret
    end,

    preview = function(p_ctx)
      local item = p_ctx.item
      local lines = M.get_column_preview_lines(item.col)
      
      vim.bo[p_ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(p_ctx.buf, 0, -1, false, lines)
      vim.bo[p_ctx.buf].modifiable = false
      
      local ns = vim.api.nvim_create_namespace("scivim_inspect")
      for i, line in ipairs(lines) do
        if line:match("^%s*📦") or line:match("^%s*📋") or line:match("^%s*📈") or line:match("^%s*📊") or line:match("^%s*🧠") then
          vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Title", i - 1, 0, -1)
        elseif line:match("│") or line:match("├") or line:match("╔") or line:match("─") then
          vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Comment", i - 1, 0, -1)
        elseif line:match("⚠️") then
           vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "WarningMsg", i - 1, 0, -1)
        end
        
        local start_idx = 1
        while true do
            local s, e = string.find(line, "[▂▃▄▅▆▇█]+", start_idx)
            if not s then break end
            vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Function", i - 1, s - 1, e)
            start_idx = e + 1
        end
      end
    end,

    confirm = function(picker) picker:close() end,
    
    win = {
      input = {
        keys = {
          ["<C-y>"] = { "copy_col_name", desc = "Copy Name", mode = { "i", "n" } },
          ["<C-i>"] = { "insert_col_code", desc = "Insert Code", mode = { "i", "n" } },
          ["<C-g>"] = { "generate_plot", desc = "Generate Plot", mode = { "i", "n" } },
        }
      },
      list = { keys = { ["gp"] = "generate_plot" } }
    },
    actions = {
      copy_col_name = copy_name,
      insert_col_code = insert_code,
      generate_plot = generate_plot_action,
    }
  })
end

-- =========================================================================
-- PREVIEW GENERATION UTILITIES (PUBLIC)
-- =========================================================================

function M._str_width(str)
  return vim.fn.strdisplaywidth(str)
end

function M._pad_string(str, target_width)
  local current_width = M._str_width(str)
  if current_width >= target_width then
    return vim.fn.strcharpart(str, 0, target_width)
  end
  return str .. string.rep(" ", target_width - current_width)
end

function M.get_column_preview_lines(col)
  local lines = {}
  local width = CONTENT_WIDTH
  
  -- 1. TITLE
  table.insert(lines, "")
  table.insert(lines, " 📦 COLUMN: " .. col.name)
  table.insert(lines, " " .. string.rep("═", width))

  -- 2. INFO & HEALTH
  table.insert(lines, "")
  table.insert(lines, " 📋 BASIC INFO")
  table.insert(lines, " " .. string.rep("─", width))
  
  local info_str = string.format("  Type: %-10s  Nulls: %-6d  Unique: %s", col.dtype, col.null_count, col.unique_count)
  table.insert(lines, info_str)
  
  local quality_score = 100
  if type(col.null_count) == "number" and type(col.unique_count) == "number" then
    local total = (col.unique_count > 0 and col.null_count + col.unique_count * 2) or 1
    quality_score = math.floor(100 - (col.null_count / total * 100))
  end
  local q_bar = M._generate_bar(quality_score, 20)
  table.insert(lines, string.format("  Health: %s %d%%", q_bar, quality_score))
  
  -- 3. INSIGHTS
  if context._is_numeric(col.dtype) and col.mean_val then
      table.insert(lines, "")
      table.insert(lines, " 🧠 INSIGHTS")
      table.insert(lines, " " .. string.rep("─", width))
      
      local diff = (col.mean_val - col.median_val)
      local range = (col.max_val - col.min_val)
      
      local shape = "Symmetric"
      if range > 0 then
         local skew = diff/range
         if skew > 0.05 then shape = "Right Skewed (Tail ->)"
         elseif skew < -0.05 then shape = "Left Skewed (<- Tail)" end
      end
      
      local volatility = "Stable"
      if col.std_val and col.mean_val ~= 0 then
          local cv = math.abs(col.std_val/col.mean_val)
          if cv > 1 then volatility = "High (Volatile)"
          elseif cv > 0.5 then volatility = "Moderate" end
          volatility = volatility .. string.format(" (CV: %.2f)", cv)
      end
      
      local outlier_txt = "Clean"
      if col.outlier_count > 0 then outlier_txt = string.format("⚠️ %d Found", col.outlier_count) end

      table.insert(lines, string.format("  Shape:    %-25s Outliers: %s", shape, outlier_txt))
      table.insert(lines, string.format("  Spread:   %-25s", volatility))
  end

  -- 4. METRICS
  if context._is_numeric(col.dtype) and col.min_val then
      table.insert(lines, "")
      table.insert(lines, " 📈 KEY METRICS")
      table.insert(lines, " " .. string.rep("─", width))
      
      local function row(l1, v1, l2, v2)
          return string.format("  %-10s %12.4f      %-10s %12.4f", l1, v1, l2, v2)
      end
      
      table.insert(lines, row("Min:", col.min_val, "Max:", col.max_val))
      table.insert(lines, row("Mean:", col.mean_val, "Median:", col.median_val))
      if col.std_val then
         table.insert(lines, string.format("  %-10s %12.4f", "Std Dev:", col.std_val))
      end
      
      if col.min_val ~= col.max_val then
          table.insert(lines, "")
          table.insert(lines, "  Box Plot:")
          local box_lines = M._generate_boxplot_viz(col, width - 4)
          vim.list_extend(lines, box_lines)
      end
  end

  -- 5. CHARTS (Uses full width)
  if context._is_numeric(col.dtype) and col.hist_counts and #col.hist_counts > 0 then
      table.insert(lines, "")
      table.insert(lines, " 📊 HISTOGRAM")
      table.insert(lines, " " .. string.rep("─", width))
      local hist = M._render_counts_histogram(col.hist_counts, col.min_val, col.max_val, width - 4)
      vim.list_extend(lines, hist)
  elseif col.sample_values and #col.sample_values > 0 and not context._is_numeric(col.dtype) then
      table.insert(lines, "")
      table.insert(lines, " 📊 TOP VALUES")
      table.insert(lines, " " .. string.rep("─", width))
      local freq = M._render_categorical_freq(col.sample_values, width - 4)
      vim.list_extend(lines, freq)
  end

  -- 6. DATA
  table.insert(lines, "")
  table.insert(lines, " 👓 RAW DATA SAMPLE")
  table.insert(lines, " " .. string.rep("─", width))
  if col.sample_values and #col.sample_values > 0 then
      local tbl = M._render_column_table(col, width - 4)
      vim.list_extend(lines, tbl)
  else
      table.insert(lines, "  (No sample data)")
  end
  
  return lines
end

function M._generate_bar(percentage, width)
  local filled = math.floor(percentage / 100 * width)
  local empty = width - filled
  return string.rep("█", filled) .. string.rep("░", empty)
end

function M._render_column_table(col, max_width)
  local lines = {}
  local max_rows = 5 
  local samples = col.sample_values or {}
  
  local col_width = 30
  if (col_width + 8) > max_width then col_width = max_width - 8 end

  local sep = "  ├────┼" .. string.rep("─", col_width + 2) .. "┤"
  local top = "  ┌────┬" .. string.rep("─", col_width + 2) .. "┐"
  local bot = "  └────┴" .. string.rep("─", col_width + 2) .. "┘"
  
  table.insert(lines, top)
  table.insert(lines, string.format("  │ #  │ %s │", M._pad_string(col.name, col_width)))
  table.insert(lines, sep)
  
  for i, val in ipairs(samples) do
    if i > max_rows then break end
    local s = tostring(val):gsub("\n", " ")
    if M._str_width(s) > col_width then s = vim.fn.strcharpart(s, 0, col_width-2) .. ".." end
    table.insert(lines, string.format("  │ %2d │ %s │", i-1, M._pad_string(s, col_width)))
  end
  table.insert(lines, bot)
  return lines
end

function M._render_counts_histogram(counts, min_val, max_val, available_width)
  local lines = {}
  local num_bins = #counts
  local draw_width = available_width
  local height = 8
  local blocks = { " ", "▂", "▃", "▄", "▅", "▆", "▇", "█" } 
  
  local max_c = 0
  for _, c in ipairs(counts) do if c > max_c then max_c = c end end
  if max_c == 0 then max_c = 1 end
  
  local scaled_counts = {}
  for i = 1, draw_width do
    local bin_index = math.floor(((i - 1) / draw_width) * num_bins) + 1
    bin_index = math.min(math.max(1, bin_index), num_bins)
    scaled_counts[i] = counts[bin_index]
  end
  
  for row = height, 1, -1 do
    local line = "  "
    for _, val in ipairs(scaled_counts) do
      local val_height = (val / max_c) * height
      local char = " "
      if val_height >= row then char = "█"
      elseif val_height > (row - 1) then
        local idx = math.floor((val_height - (row - 1)) * 8) + 1
        char = blocks[math.max(1, math.min(8, idx))]
      elseif val > 0 and row == 1 then char = " " end
      line = line .. char
    end
    table.insert(lines, line)
  end
  
  local min_label = string.format("%.1f", min_val)
  local max_label = string.format("%.1f", max_val)
  local padding = draw_width - #min_label - #max_label
  if padding < 1 then padding = 1 end
  table.insert(lines, "  " .. min_label .. string.rep(" ", padding) .. max_label)
    
  return lines
end

function M._render_categorical_freq(values, available_width)
  local lines = {}
  local counts = {}
  for _, v in ipairs(values) do
    local k = tostring(v)
    counts[k] = (counts[k] or 0) + 1
  end
  
  local sorted = {}
  for k, v in pairs(counts) do table.insert(sorted, {k = k, v = v}) end
  table.sort(sorted, function(a, b) return a.v > b.v end)
  
  local label_width = 25
  local max_w = (available_width or 60) - label_width
  if max_w < 5 then max_w = 5 end
  
  local max_v = sorted[1] and sorted[1].v or 1
  
  for i, item in ipairs(sorted) do
    if i > 8 then break end
    local bar_len = math.floor(item.v / max_v * max_w)
    local bar = string.rep("█", bar_len)
    if bar_len == 0 and item.v > 0 then bar = "▏" end
    
    local lbl = item.k
    local max_lbl_len = label_width - 6
    if M._str_width(lbl) > max_lbl_len then lbl = vim.fn.strcharpart(lbl, 0, max_lbl_len - 1) .. "…" end
    
    table.insert(lines, string.format("  %-" .. label_width .. "s %s (%d)", lbl, bar, item.v))
  end
  return lines
end

function M._generate_boxplot_viz(col, width)
  local min_val, max_val, q1, q3 = col.min_val, col.max_val, col.q1, col.q3
  local width = width or 40
  local range = max_val - min_val
  if range == 0 then return { "  " .. string.rep("─", width) } end
  
  local function to_idx(val)
      if not val then return -1 end
      local pos = math.floor((val - min_val) / range * width)
      return math.max(0, math.min(width - 1, pos))
  end

  local q1_pos = to_idx(q1)
  local q3_pos = to_idx(q3)
  local median_pos = to_idx(col.median_val)
  
  local viz = ""
  for i = 0, width - 1 do
    if i == 0 then viz = viz .. "├"
    elseif i == width - 1 then viz = viz .. "┤"
    elseif q1_pos >= 0 and q3_pos >= 0 and i == q1_pos then viz = viz .. "["
    elseif q1_pos >= 0 and q3_pos >= 0 and i == q3_pos then viz = viz .. "]"
    elseif q1_pos >= 0 and q3_pos >= 0 and i > q1_pos and i < q3_pos then 
       if i == median_pos then viz = viz .. "|" else viz = viz .. "=" end
    else viz = viz .. "─" end
  end
  
  return { "  " .. viz }
end

function M._quick_visualize_column(ctx, col_entry)
  local chart_id = (col_entry.dtype:match("str") or col_entry.dtype:match("object")) and "count" or "hist"
  local chart = charts.get_chart(chart_id)
  if not chart then vim.notify("Chart not found", vim.log.levels.ERROR) return end
  generator.generate({
    df = ctx.name or "df",
    cols = ctx.columns,
    lib = ctx.lib or "pandas",
    metadata = ctx.metadata or {},
    chart = chart,
    x = col_entry.name,
    title = col_entry.name .. " Distribution",
  })
end

return M

--This file is in  lua/scivim/ui/layout.lua

local M = {}

function M.toggle_scientific_mode()
  -- Get current buffer ID
  local main_buf = vim.api.nvim_get_current_buf()
  
  -- 1. Create a Vertical Split
  vim.cmd("vsplit")
  
  -- 2. Move to the new right-hand window
  local win_output = vim.api.nvim_get_current_win()
  
  -- 3. Create a scratch buffer for the output
  local out_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win_output, out_buf)
  
  -- 4. Configure the Output Window (No numbers, no signs)
  vim.wo[win_output].number = false
  vim.wo[win_output].relativenumber = false
  vim.wo[win_output].signcolumn = "no"
  vim.api.nvim_buf_set_name(out_buf, "Scientific Output")

  -- 5. Resize: Give code 60%, output 40%
  vim.cmd("vertical resize 60")
  
  -- 6. Go back to the code window
  vim.cmd("wincmd h")
  
  -- 7. (Crucial) Tell Molten/Image.nvim to target the other buffer?
  -- Molten renders virtual text inline by default. 
  -- To emulate PyCharm, you might want to map a key that sends 
  -- the output to the side buffer using `MoltenEvaluateVisual` 
  -- but capturing the output is tricky in Lua without patching Molten.
  
  print("Scientific Mode Enabled")
end

return M


--This file is in  lua/scivim/ui/preview.lua
-- =========================================================================
-- PREVIEW - Live Plot Preview (Matplotlib & Plotly support)
-- =========================================================================
local M = {}

local config = require("scivim.config")
local generator = require("scivim.core.generator")

-- Preview state
local preview_state = {
  job_id = nil,
  temp_file = nil,
  image_buf = nil,
}

--- Check if preview is supported
---@return boolean, string
function M.is_supported()
  -- Check for image.nvim
  local has_image = pcall(require, "image")
  if has_image then
    return true, "image.nvim"
  end
  
  -- Check for kitty terminal
  if vim.env.TERM == "xterm-kitty" or vim.env.KITTY_WINDOW_ID then
    return true, "kitty"
  end
  
  -- Check for ueberzug (legacy)
  if vim.fn.executable("ueberzug") == 1 then
    return true, "ueberzug"
  end
  
  return false, "none"
end

--- Generate preview for current visualization spec
---@param spec table|nil Visualization spec (if nil, uses last generated code)
function M.show_preview(spec)
  local supported, backend = M.is_supported()
  
  if not supported then
    vim.notify(
      "Preview not supported. Install image.nvim or use Kitty terminal.",
      vim.log.levels.WARN
    )
    return
  end
  
  -- Get code to preview (Priority: Spec -> Last Generated)
  local code_lines = {}
  
  if spec then
    -- If a spec is passed, we might need to generate it on the fly
    -- Assuming generator has a method to get code without side effects, 
    -- otherwise we rely on the cached last run.
    code_lines = generator.get_code_lines and generator.get_code_lines(spec) or {}
  end

  -- Fallback to last generated code
  if #code_lines == 0 then
    code_lines = generator.get_last_viz_code and generator.get_last_viz_code() or {}
  end

  if #code_lines == 0 then
    vim.notify("No visualization code found to preview.", vim.log.levels.ERROR)
    return
  end
  
  vim.notify("🔄 Generating preview...", vim.log.levels.INFO)
  
  -- Create temp file for output
  preview_state.temp_file = os.tmpname() .. ".png"
  local raw_code = table.concat(code_lines, "\n")
  local final_code = ""

  -- [[ SMART BACKEND DETECTION ]]
  if raw_code:match("plotly") or raw_code:match("px%.") or raw_code:match("go%.") then
      -- === PLOTLY HANDLING ===
      final_code = raw_code:gsub("fig%.show%(%)", "") -- Remove interactive show
      final_code = final_code .. "\n# Export for Neovim Preview"
      final_code = final_code .. "\ntry:"
      final_code = final_code .. "\n    import plotly.io as pio"
      final_code = final_code .. "\n    # Requires: pip install kaleido"
      final_code = final_code .. "\n    pio.write_image(fig, '" .. preview_state.temp_file .. "', engine='kaleido', scale=2)"
      final_code = final_code .. "\nexcept Exception as e:"
      final_code = final_code .. "\n    print(f'Preview Error (Plotly): {e}. Ensure kaleido is installed.')"
      final_code = final_code .. "\n    exit(1)"
  else
      -- === MATPLOTLIB/SEABORN HANDLING (Default) ===
      final_code = raw_code:gsub("plt%.show%(%)", "") -- Remove blocking show
      final_code = final_code .. "\nplt.savefig('" .. preview_state.temp_file .. "', dpi=150, bbox_inches='tight')"
  end
  
  final_code = final_code .. "\nprint('PREVIEW_READY')"
  
  -- Execute Python code
  M._execute_preview(final_code, backend)
end

--- Execute Python code and display image
---@param code string Python code
---@param backend string Display backend
function M._execute_preview(code, backend)
  -- Cancel previous preview job if running
  if preview_state.job_id then
    vim.fn.jobstop(preview_state.job_id)
  end
  
  local output = {}
  
  preview_state.job_id = vim.fn.jobstart({"python3", "-c", code}, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(output, data)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        -- Only log actual errors, filter out common matplotlib warnings if desired
        vim.notify("Preview log: " .. table.concat(data, "\n"), vim.log.levels.INFO)
      end
    end,
    on_exit = function(_, exit_code)
      preview_state.job_id = nil
      
      if exit_code == 0 then
        -- Check if file was created
        if vim.fn.filereadable(preview_state.temp_file) == 1 then
          M._display_image(preview_state.temp_file, backend)
        else
          vim.notify("Preview failed: output file not created. Check Python logs.", vim.log.levels.ERROR)
        end
      else
        vim.notify("Preview process failed with exit code: " .. exit_code, vim.log.levels.ERROR)
      end
    end,
  })
end

--- Display image using appropriate backend
---@param filepath string Path to image
---@param backend string Display backend
function M._display_image(filepath, backend)
  if backend == "image.nvim" then
    M._display_image_nvim(filepath)
  elseif backend == "kitty" then
    M._display_kitty(filepath)
  elseif backend == "ueberzug" then
    M._display_ueberzug(filepath)
  end
end

--- Display using image.nvim
function M._display_image_nvim(filepath)
  local image = require("image")
  
  -- Calculate dimensions
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  
  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
  })
  
  preview_state.image_buf = buf
  
  -- Render image
  local img = image.from_file(filepath, {
    window = win,
    buffer = buf,
    -- Fit image to window
    width = width,
    height = height,
  })
  
  if img then
    img:render()
  end
  
  -- Close handlers
  local function close()
    M.close_preview()
  end
  
  vim.keymap.set('n', 'q', close, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, noremap = true, silent = true })
  
  vim.notify("✅ Preview ready (press 'q' to close)", vim.log.levels.INFO)
end

--- Display using Kitty graphics protocol
function M._display_kitty(filepath)
  -- Use kitty icat to display image
  local cmd = string.format("kitty +kitten icat --align left --hold '%s'", filepath)
  -- Note: 'hold' keeps it open, might need adjustment depending on workflow
  vim.fn.jobstart(cmd, { detach = true })
  
  vim.notify("✅ Preview displayed in terminal", vim.log.levels.INFO)
end

--- Display using ueberzug (legacy)
function M._display_ueberzug(filepath)
  vim.notify("Ueberzug preview not fully implemented yet.", vim.log.levels.WARN)
end

--- Close preview window
function M.close_preview()
  if preview_state.image_buf and vim.api.nvim_buf_is_valid(preview_state.image_buf) then
    local wins = vim.fn.win_findbuf(preview_state.image_buf)
    for _, win in ipairs(wins) do
      vim.api.nvim_win_close(win, true)
    end
    vim.api.nvim_buf_delete(preview_state.image_buf, { force = true })
  end
  
  -- Clean up temp file
  if preview_state.temp_file and vim.fn.filereadable(preview_state.temp_file) == 1 then
    os.remove(preview_state.temp_file)
  end
  
  preview_state.image_buf = nil
  preview_state.temp_file = nil
end

return M

--This file is in  lua/scivim/ui/transform.lua
-- =========================================================================
-- LIVE TRANSFORM - Interactive UI (Polyglot: Python + SQL)
-- =========================================================================
local M = {}

local executor = require("scivim.backend.client")
local Snacks = require("snacks")

local ICONS = {
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    pandas  = "🐼",
    polars  = "🐻",
    lazy    = "🐨",
    prompt  = "  ", 
}

-- 1. Standalone Highlights
local function setup_highlights()
    local hls = {
        ScivimBorder      = { link = "FloatBorder" },
        ScivimTitle       = { link = "Title" },
        ScivimPrompt      = { link = "NormalFloat" },
        ScivimInputPrefix = { fg = "#f38ba8", bold = true },
        ScivimError       = { fg = "#f38ba8" },
    }
    if vim.fn.hlexists("SnacksPickerBorder") == 1 then
        hls.ScivimBorder = { link = "SnacksPickerBorder" }
        hls.ScivimTitle  = { link = "SnacksPickerTitle" }
    end
    for group, opts in pairs(hls) do vim.api.nvim_set_hl(0, group, opts) end
end
setup_highlights()

-- ----------------------------------------------------------------------------
-- STATE
-- ----------------------------------------------------------------------------
local state = {
  current_code = "",
  update_timer = nil,
  ctx = nil,
  preview_win = nil,
  input_win = nil,
  parent_win = nil,
  ghost_path = nil,
  spinner_timer = nil,
  spinner_idx = 1,
}

local function get_df_icon(ctx) 
    return (ctx.lib == "polars" and (ctx.is_lazy and ICONS.lazy or ICONS.polars) or ICONS.pandas) 
end

local function stop_spinner()
    if state.spinner_timer then state.spinner_timer:stop(); state.spinner_timer:close(); state.spinner_timer = nil end
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win.win) then
         local icon = get_df_icon(state.ctx)
         pcall(vim.api.nvim_win_set_config, state.input_win.win, { title = string.format(" %s %s ", icon, state.ctx.name), title_pos = "center" })
    end
end

local function start_spinner()
    if state.spinner_timer then return end
    state.spinner_idx = 1
    state.spinner_timer = vim.loop.new_timer()
    state.spinner_timer:start(0, 100, vim.schedule_wrap(function()
        if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win.win) then stop_spinner(); return end
        local frame = ICONS.spinner[state.spinner_idx]
        state.spinner_idx = (state.spinner_idx % #ICONS.spinner) + 1
        pcall(vim.api.nvim_win_set_config, state.input_win.win, { title = string.format(" %s Processing... ", frame), title_pos = "center" })
    end))
end

local function cleanup_state()
  stop_spinner()
  if state.update_timer then pcall(function() state.update_timer:stop() end); pcall(function() state.update_timer:close() end); state.update_timer = nil end
  if state.preview_win then pcall(function() state.preview_win:close() end); state.preview_win = nil end
  if state.input_win then
    if state.input_win.buf and vim.api.nvim_buf_is_valid(state.input_win.buf) then pcall(vim.cmd, "bdelete! " .. state.input_win.buf) end
    pcall(function() state.input_win:close() end); state.input_win = nil
  end
  if state.ghost_path and vim.fn.filereadable(state.ghost_path) == 1 then os.remove(state.ghost_path) end
  state.ghost_path = nil
  state.current_code = ""
  state.ctx = nil
  state.parent_win = nil
end

local function center_lines(lines, win)
  if not win or not win.win or not vim.api.nvim_win_is_valid(win.win) then return lines end
  local width = vim.api.nvim_win_get_width(win.win)
  local centered = {}
  for _, line in ipairs(lines) do
    local line_len = vim.fn.strdisplaywidth(line)
    if line_len < width then table.insert(centered, string.rep(" ", math.floor((width - line_len) / 2)) .. line) else table.insert(centered, line) end
  end
  return centered
end

-- ----------------------------------------------------------------------------
-- UPDATE LOGIC
-- ----------------------------------------------------------------------------
local function update_preview(response)
  stop_spinner()
  if not state.preview_win or not state.preview_win.buf or not vim.api.nvim_buf_is_valid(state.preview_win.buf) then return end
  
  local lines = {}
  local border_hl = "ScivimBorder"

  if response.error and type(response.error) == "string" then
    if not (response.error:match("Syntax") or response.error:match("unexpected EOF")) then
      border_hl = "ScivimError"
      local err_lines = vim.split(response.error, "\n")
      table.insert(lines, ""); table.insert(lines, "💥 " .. (err_lines[1] or "Error")); table.insert(lines, string.rep("─", 40))
      for i = 2, #err_lines do table.insert(lines, "  " .. err_lines[i]) end
    end
  end

  if response.text_table and type(response.text_table) == "string" then
    local raw_lines = vim.split(response.text_table, '\n')
    vim.list_extend(lines, center_lines(raw_lines, state.preview_win))
  end
  
  if vim.api.nvim_win_is_valid(state.preview_win.win) then
      vim.api.nvim_win_set_option(state.preview_win.win, "winhighlight", "FloatBorder:"..border_hl..",Normal:NormalFloat")
  end
  
  vim.api.nvim_buf_set_lines(state.preview_win.buf, 0, -1, false, lines)
end

local function trigger_request()
  start_spinner()
  executor.run_transform_async(
    state.ctx.name,
    state.ctx.lib or "pandas",
    state.ctx.is_lazy or false,
    state.current_code,
    function(response)
      if state.ctx and state.preview_win then
          vim.schedule(function() update_preview(response) end)
      end
    end
  )
end

local function debounced_update(code)
  state.current_code = code
  if state.update_timer then state.update_timer:stop(); state.update_timer:close() end
  state.update_timer = vim.loop.new_timer()
  state.update_timer:start(150, 0, vim.schedule_wrap(trigger_request))
end

-- ----------------------------------------------------------------------------
-- UI LAUNCHER & UTILS
-- ----------------------------------------------------------------------------

local function patch_lsp_client(client)
    if client._scivim_patched then return end
    local method = "textDocument/signatureHelp"
    local orig_handler = client.handlers[method] or vim.lsp.handlers[method]
    client.handlers[method] = function(err, result, ctx, config)
        if ctx and ctx.bufnr and vim.b[ctx.bufnr].scivim_hide_signature then return end
        if orig_handler then orig_handler(err, result, ctx, config) end
    end
    client._scivim_patched = true
end

local function generate_python_stub(ctx)
  local lib, columns = ctx.lib or "pandas", ctx.columns or {}
  local lines = {}
  local is_lazy = ctx.is_lazy or false
  if lib == "pandas" then
    table.insert(lines, "import pandas as pd; import numpy as np")
    table.insert(lines, "class VirtualDF(pd.DataFrame):")
    if #columns > 0 then for _, col in ipairs(columns) do if col:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then table.insert(lines, string.format("    %s: pd.Series", col)) end end else table.insert(lines, "    pass") end
    table.insert(lines, "df: VirtualDF = VirtualDF()")
  elseif lib == "polars" then
    table.insert(lines, "import polars as pl; from polars import col, lit, when")
    table.insert(lines, is_lazy and "df: pl.LazyFrame = pl.LazyFrame()" or "df: pl.DataFrame = pl.DataFrame()")
    if #columns > 0 then for _, col in ipairs(columns) do if col:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then table.insert(lines, string.format("%s = pl.col('%s')", col, col)) end end end
  end
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

local function setup_lsp_completion(input_buf, parent_buf, ctx)
  if not vim.api.nvim_buf_is_valid(input_buf) then return end
  vim.b[input_buf].scivim_hide_signature = true
  vim.api.nvim_create_autocmd("LspAttach", { buffer = input_buf, callback = function(args) local client = vim.lsp.get_client_by_id(args.data.client_id); if client then if client.server_capabilities then client.server_capabilities.signatureHelpProvider = nil end; patch_lsp_client(client) end end })
  local start_path = vim.api.nvim_buf_get_name(parent_buf)
  if start_path == "" then start_path = vim.fn.getcwd() end
  local root_markers = { "pyproject.toml", "requirements.txt", ".git", ".venv", "venv" }
  local root_dir = vim.fs.dirname(vim.fs.find(root_markers, { path = start_path, upward = true })[1] or start_path)
  local fake_path = root_dir .. "/__scivim_ghost_" .. os.time() .. ".py"
  state.ghost_path = fake_path
  local stub_content = generate_python_stub(ctx)
  local f = io.open(fake_path, "w"); if f then f:write(stub_content); f:close() end
  vim.api.nvim_buf_set_name(input_buf, fake_path)
  vim.bo[input_buf].buftype = ""; vim.bo[input_buf].filetype = "python"
  vim.api.nvim_buf_set_lines(input_buf, 0, 0, false, vim.split(stub_content, '\n'))
  vim.api.nvim_buf_call(input_buf, function() vim.cmd("silent! write") end)
  vim.schedule(function() if not vim.api.nvim_buf_is_valid(input_buf) then return end; local attached = false; if #vim.lsp.get_clients({ buffer = input_buf }) > 0 then attached = true end; if not attached then for _, client in ipairs(vim.lsp.get_clients()) do if client.name == "pyrefly" then vim.lsp.buf_attach_client(input_buf, client.id); attached = true; break end end end; if not attached and vim.fn.exists(":LspStart") == 2 then vim.cmd("silent! LspStart pyrefly"); vim.defer_fn(function() for _, client in ipairs(vim.lsp.get_clients()) do if client.name == "pyrefly" and vim.api.nvim_buf_is_valid(input_buf) then vim.lsp.buf_attach_client(input_buf, client.id); patch_lsp_client(client); break end end end, 500) end end)
  vim.defer_fn(function() local has_cmp, cmp = pcall(require, "cmp"); if has_cmp then cmp.setup.buffer({ enabled = true, completion = { autocomplete = { cmp.TriggerEvent.TextChanged } }, sources = cmp.config.sources({ { name = "nvim_lsp", priority = 1000 }, { name = "buffer", priority = 500 } }) }) end end, 100)
end

local function open_transform_ui(ctx)
  state.ctx = ctx; state.current_code = ""
  state.parent_win = vim.api.nvim_get_current_win()
  local parent_buf = vim.api.nvim_get_current_buf()
  
  -- Dimensions
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local input_h = 3
  local preview_h = height - input_h

  local icon = get_df_icon(ctx)
  local title_text = string.format(" %s %s ", icon, ctx.name)
  
  -- 1. Input Window
  state.input_win = Snacks.win({
    relative = "editor", row = row, col = col, width = width, height = 1,
    border = "rounded", title = title_text, title_pos = "center",
    wo = { winhighlight = "FloatBorder:ScivimBorder,Title:ScivimTitle,Normal:ScivimPrompt", scrolloff = 0 },
    keys = { ["<Esc>"] = { "close", mode = {"n", "i"} }, ["<C-c>"] = { "close", mode = {"n", "i"} } }
  })

  -- 2. Preview Window
  state.preview_win = Snacks.win({
    relative = "editor", row = row + input_h, col = col, width = width, height = preview_h,
    border = "rounded", wo = { winhighlight = "FloatBorder:ScivimBorder,Normal:NormalFloat" }, interactive = false
  })
  
  -- 3. Setup Input Buffer
  local input_buf = state.input_win.buf
  setup_lsp_completion(input_buf, parent_buf, ctx)
  
  -- Prompt Icon
  local ns_id = vim.api.nvim_create_namespace("scivim_prompt")
  local function set_prompt_extmark() 
      vim.api.nvim_buf_set_extmark(input_buf, ns_id, 0, 0, { virt_text = {{ ICONS.prompt, "ScivimInputPrefix" }}, virt_text_pos = "inline" }) 
  end
  
  local stub_lines = vim.split(generate_python_stub(ctx), '\n')
  local content_offset = #stub_lines + 1
  
  vim.defer_fn(function() 
      if vim.api.nvim_buf_is_valid(input_buf) and vim.api.nvim_win_is_valid(state.input_win.win) then 
          local line_count = vim.api.nvim_buf_line_count(input_buf)
          if line_count < content_offset then vim.api.nvim_buf_set_lines(input_buf, line_count, -1, false, { "" }) end
          vim.api.nvim_win_set_cursor(state.input_win.win, {content_offset, 0})
          vim.fn.winrestview({topline = content_offset, lnum = content_offset, col = 0})
          set_prompt_extmark() 
      end 
  end, 150)
  
  vim.api.nvim_set_current_win(state.input_win.win)
  vim.cmd("startinsert")
  
  -- Auto-update hook with SQL DETECTION
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, { 
      buffer = input_buf, 
      callback = function() 
          vim.cmd("silent! write")
          set_prompt_extmark()
          local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
          local user_lines = {}
          for i = content_offset, #all_lines do if all_lines[i] then table.insert(user_lines, all_lines[i]) end end
          
          local full_text = table.concat(user_lines, "\n")
          
          -- [[ Dynamic SQL Syntax Switching ]]
          local first_word = full_text:match("^%s*(%w+)")
          if first_word then
              first_word = first_word:upper()
              if first_word == "SELECT" or first_word == "WITH" or first_word == "PRAGMA" or first_word == "DESCRIBE" or first_word == "SHOW" or first_word == "EXPLAIN" then
                  if vim.bo[input_buf].filetype ~= "sql" then vim.bo[input_buf].filetype = "sql" end
              else
                  if vim.bo[input_buf].filetype ~= "python" then vim.bo[input_buf].filetype = "python" end
              end
          end

          debounced_update(full_text) 
      end 
  })
  trigger_request()
  
  -- Close/Accept Logic with VARIABLE REPLACEMENT
  local function accept_and_close()
    local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local user_lines = {}
    for i = content_offset, #all_lines do if all_lines[i] then table.insert(user_lines, all_lines[i]) end end
    local code = table.concat(user_lines, "\n")
    
    local target_win = state.parent_win
    cleanup_state()
    
    if target_win and vim.api.nvim_win_is_valid(target_win) then
        vim.api.nvim_set_current_win(target_win)
    end
    
    if code and code ~= "" then
        -- Check if it was SQL or Python
        local start_token = code:match("^%s*(%w+)")
        local is_sql = false
        if start_token and (start_token:upper() == "SELECT" or start_token:upper() == "WITH" or start_token:upper() == "PRAGMA") then
            is_sql = true
        end

        local full_code = code
        if not is_sql then
            -- Python Substitution
            if code:match("^%s*df%.") then
                full_code = code:gsub("^%s*df", ctx.name, 1)
            elseif code:match("^%s*%.") then
                full_code = ctx.name .. code
            end
        else
            -- [[ NEW: SQL Substitution Logic ]]
            -- Preview uses 'df', but Notebook uses ctx.name (e.g., 'df_sales')
            -- We automatically fix this so user can just type 'FROM df'
            local clean_code = code:gsub("FROM%s+df", "FROM " .. ctx.name)
            clean_code = clean_code:gsub("from%s+df", "FROM " .. ctx.name)
            clean_code = clean_code:gsub("JOIN%s+df", "JOIN " .. ctx.name)

            -- Wrap in duckdb call
            full_code = string.format("import duckdb\n%s_sql = duckdb.sql(\"\"\"%s\"\"\").df()", ctx.name, clean_code)
        end
        vim.api.nvim_put(vim.split(full_code, '\n'), "c", true, true)
    end
  end
  
  vim.keymap.set({"n", "i"}, "<CR>", function() vim.cmd("stopinsert"); accept_and_close() end, { buffer = input_buf })
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, { buffer = input_buf, callback = function() vim.defer_fn(cleanup_state, 100) end, once = true })
end

local function pick_context_ui(ctx_list)
  local lines = {}; for _, ctx in ipairs(ctx_list) do local icon = get_df_icon(ctx); table.insert(lines, string.format(" %s %s ", icon, ctx.name)) end
  local width = 40; local height = math.min(#lines, 10); local row = math.floor((vim.o.lines - height) / 2); local col = math.floor((vim.o.columns - width) / 2)
  local win = Snacks.win({ relative = "editor", row = row, col = col, width = width, height = height, border = "rounded", title = " Select Dataframe ", title_pos = "center", wo = { winhighlight = "FloatBorder:ScivimBorder,Title:ScivimTitle,Normal:ScivimPrompt,CursorLine:PmenuSel", cursorline = true }, keys = { ["q"] = "close", ["<Esc>"] = "close", ["<CR>"] = function(self) local cursor = vim.api.nvim_win_get_cursor(self.win); local idx = cursor[1]; self:close(); vim.schedule(function() if ctx_list[idx] then open_transform_ui(ctx_list[idx]) end end) end } })
  vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines); vim.bo[win.buf].modifiable = false
end

function M.inspect_transform(ctx_arg)
  if ctx_arg then 
    open_transform_ui(ctx_arg) 
  else 
    local all_data = require("scivim.core.context").load_all()
    local ctx_list = {}
    if all_data then for _, v in pairs(all_data) do table.insert(ctx_list, v) end end
    
    if #ctx_list == 0 then 
        vim.notify("No dataframes exposed via vim_expose()", vim.log.levels.WARN) 
    elseif #ctx_list == 1 then 
        open_transform_ui(ctx_list[1]) 
    else 
        pick_context_ui(ctx_list) 
    end 
  end
end

return M






--This file is in  lua/scivim/ui/wizard.lua

-- =========================================================================
-- WIZARD - Interactive Plot Builder (Advanced Edition)
-- =========================================================================
local M = {}

local config = require("scivim.config")
local context = require("scivim.core.context")
local charts = require("scivim.core.charts")
local generator = require("scivim.core.generator")
local inspector = require("scivim.ui.inspector") 
local Snacks = require("snacks")

local has_image, image_nvim = pcall(require, "image")

local Builder = {
  active = false,
  state = {},
  preview_job = nil,
  active_img = nil,
  tmp_file = os.tmpname() .. ".png",
  debounce_timer = nil
}

local CAT_ICONS = {
  relational   = "🔗",
  distribution = "📊",
  categorical  = "📦",
  matrix       = "▦ ",
  multivariate = "🧊", -- New icon for 3D/Advanced
  hierarchical = "◎", -- New icon for Sunbursts
  flow         = "ﬡ", -- New icon for Sankey
}

--- Start the interactive builder
function M.start()
  local all_data, err = context.load_all()
  if not all_data then 
    vim.notify(err, vim.log.levels.ERROR) 
    return 
  end

  local ctx_list = {}
  for name, data in pairs(all_data) do
    table.insert(ctx_list, data)
  end

  if #ctx_list == 0 then
    vim.notify("No DataFrames exposed via vim_expose()", vim.log.levels.WARN)
    return
  end

  -- Auto-select based on cursor
  local cursor_word = vim.fn.expand("<cword>")
  for _, ctx in ipairs(ctx_list) do
    if ctx.name == cursor_word then
      vim.notify("📊 Auto-selected DataFrame: " .. cursor_word, vim.log.levels.INFO)
      M._step_select_chart(ctx, nil)
      return
    end
  end

  if #ctx_list == 1 then
    M._step_select_chart(ctx_list[1], nil)
    return
  end

  M._step_select_df(ctx_list)
end

function M.quick_start(chart_id)
  local all_data, err = context.load_all()
  if not all_data then return end
  
  local ctx_list = {}
  for name, data in pairs(all_data) do
    table.insert(ctx_list, data)
  end
  
  local cursor_word = vim.fn.expand("<cword>")
  local chart = charts.get_chart(chart_id)

  for _, ctx in ipairs(ctx_list) do
    if ctx.name == cursor_word and chart then
      M._init_builder(ctx, chart)
      return
    end
  end

  if chart then M._step_select_df(ctx_list, chart) end
end

-- -------------------------------------------------------------------------
-- STEP 1: DATA CONTEXT
-- -------------------------------------------------------------------------

function M._step_select_df(ctx_list, preselected_chart)
  local items = {}
  for _, ctx in ipairs(ctx_list) do
    local icon = ctx.lib == "polars" and config.icon("polars") or config.icon("pandas")
    table.insert(items, { 
      text = ctx.name, 
      ctx = ctx, 
      comment = string.format("%d cols", #ctx.columns), 
      icon = icon 
    })
  end

  Snacks.picker.pick({
    items = items, 
    title = "Select DataFrame", 
    layout = "vscode",
    format = function(item)
      return { 
        { item.icon, "SnacksIcon" }, 
        { " " }, 
        { item.text, "Normal" }, 
        { "  " }, 
        { item.comment, "Comment" } 
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.ctx then 
        vim.notify("✓ Selected: " .. item.ctx.name, vim.log.levels.INFO)
        M._step_select_chart(item.ctx, preselected_chart) 
      end
    end
  })
end

-- -------------------------------------------------------------------------
-- STEP 2: CHART TYPE (Advanced Docs & Categories)
-- -------------------------------------------------------------------------

function M._step_select_chart(ctx, preselected_chart)
  if preselected_chart then 
    M._init_builder(ctx, preselected_chart) 
    return 
  end
  
  local avail_charts = generator.get_available_charts() 
  local adapter = generator.get_active_plot_adapter()
  local backend = config.get().plot_backend or "seaborn"
  
  -- Sort by Category then Name
  table.sort(avail_charts, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.name < b.name
  end)

  local items = {}
  local last_cat = nil
  
  for _, chart in ipairs(avail_charts) do
    -- Add Section Headers
    if chart.category ~= last_cat then
      local cat_icon = CAT_ICONS[chart.category] or "📂"
      table.insert(items, { 
        text = chart.category:upper(), 
        header = true,
        icon = cat_icon,
        desc = "Browse charts in the " .. chart.category .. " category."
      })
      last_cat = chart.category
    end
    
    -- Requirement string for preview
    local req_str = ""
    if chart.req and #chart.req > 0 then
      req_str = "[" .. table.concat(chart.req, ", "):upper() .. "]"
    end

    -- Dynamic Docs Resolution
    local func_name = nil
    local doc_url = nil
    
    if adapter and adapter.mappings and adapter.mappings[chart.id] then
       func_name = adapter.mappings[chart.id]
       
       if backend == "plotly" then
          -- ex: px.bar -> https://plotly.com/python-api-reference/generated/plotly.express.bar.html
          local clean_func = func_name:gsub("px%.", "plotly.express.")
          doc_url = "https://plotly.com/python-api-reference/generated/" .. clean_func .. ".html"
       elseif backend == "seaborn" then
          -- ex: sns.barplot -> https://seaborn.pydata.org/generated/seaborn.barplot.html
          local clean_func = func_name:gsub("sns%.", "seaborn.")
          doc_url = "https://seaborn.pydata.org/generated/" .. clean_func .. ".html"
       end
    end

    table.insert(items, { 
      text = chart.name, 
      item = chart, 
      icon = chart.icon,
      req_str = req_str, 
      desc = chart.desc or "Visualization",
      func_name = func_name,
      doc_url = doc_url,
      backend = backend
    })
  end

  Snacks.picker.pick({
    items = items, 
    title = "Select Visualization Type", 
    layout = {
        layout = {
            box = "horizontal",
            width = 0.8,
            height = 0.8,
            {
                box = "vertical",
                border = "rounded",
                { win = "input", height = 1, border = "bottom" },
                { win = "list", border = "none" },
            },
            {
                win = "preview",
                title = " Description ",
                border = "rounded",
                width = 0.5,
            }
        }
    },
    format = function(item)
      if item.header then
        return { { item.icon .. "  " .. item.text, "Directory" } }
      end
      return { { "  " }, { item.icon, "SnacksIcon" }, { " " }, { item.text, "Normal" } } 
    end,
    matcher = { filter = function(item) return not item.header end },
    
    -- RICH PREVIEW PANE
    preview = function(p_ctx)
        local item = p_ctx.item
        if not vim.api.nvim_buf_is_valid(p_ctx.buf) then return end
        
        vim.bo[p_ctx.buf].modifiable = true
        local lines = {}
        
        if item.header then
            table.insert(lines, "")
            table.insert(lines, "  " .. item.icon .. " CATEGORY: " .. item.text)
            table.insert(lines, "  " .. string.rep("─", 30))
            table.insert(lines, "")
            table.insert(lines, "  " .. item.desc)
        else
            table.insert(lines, "")
            table.insert(lines, "  " .. item.icon .. " " .. item.text)
            table.insert(lines, "  " .. string.rep("─", 35))
            table.insert(lines, "")
            
            for _, line in ipairs(vim.split(item.desc or "No description.", "\n")) do
                table.insert(lines, "  " .. line)
            end
            
            table.insert(lines, "")
            table.insert(lines, "  🔧 BACKEND: " .. (item.backend and item.backend:upper() or "GENERIC"))
            
            if item.func_name then
                table.insert(lines, "  ƒ  FUNCTION: " .. item.func_name)
            end

            if item.req_str and item.req_str ~= "" then
                table.insert(lines, "")
                table.insert(lines, "  REQUIRES: " .. item.req_str)
            end
            
            if item.doc_url then
                table.insert(lines, "")
                table.insert(lines, "  📚 DOCS:")
                table.insert(lines, "  " .. item.doc_url)
            end
        end
        
        vim.api.nvim_buf_set_lines(p_ctx.buf, 0, -1, false, lines)
        vim.bo[p_ctx.buf].filetype = "markdown"
        vim.bo[p_ctx.buf].modifiable = false
    end,

    confirm = function(picker, item)
      if item.header then return end
      picker:close()
      if item then M._init_builder(ctx, item.item) end
    end
  })
end

-- -------------------------------------------------------------------------
-- STEP 3: THE DASHBOARD (Supports Z-Axis)
-- -------------------------------------------------------------------------

function M._init_builder(ctx, chart)
  if not ctx or not ctx.name then return end
  
  local needs_reset = false
  
  if not Builder.active then
    needs_reset = true
  elseif not Builder.state.df or Builder.state.df ~= ctx.name then
    needs_reset = true
  elseif Builder.state.chart and Builder.state.chart.id ~= chart.id then
    needs_reset = true
  end
  
  if needs_reset then
    if Builder.active_img then Builder.active_img:clear() end
    
    Builder.state = {
      ctx = ctx,
      df = ctx.name,
      lib = ctx.lib or "pandas",
      cols = ctx.columns or {},
      metadata = ctx.metadata or {},
      chart = chart,
      params = {
        x = chart.default_x or nil,
        y = nil,
        z = nil, -- NEW: Support for 3D/Multivariate
        hue = nil,
        title = nil,
        size = nil,
        theme = nil,
        palette = nil,
        kde = (chart.id == "hist") and true or nil,
        bins = nil,
        alpha = (chart.id == "scatter" or chart.id == "scatter3d") and 0.8 or nil,
      },
      valid = false
    }
    Builder.active = true
  end
  
  M._open_dashboard()
end

function M._open_dashboard()
  local state = Builder.state
  local req = state.chart.req or {}
  
  -- Validation: Check X, Y, and Z
  local missing = {}
  if vim.tbl_contains(req, "x") and not state.params.x then table.insert(missing, "X") end
  if vim.tbl_contains(req, "y") and not state.params.y then table.insert(missing, "Y") end
  if vim.tbl_contains(req, "z") and not state.params.z then table.insert(missing, "Z") end
  state.valid = #missing == 0

  local items = {}
  
  local function add_item(group, label, key, action, icon, is_req)
     local val = state.params[key]
     local display_val = val
     
     if type(val) == "boolean" then display_val = val and "On" or "Off"
     elseif val == nil then display_val = "(Default)"
     else display_val = tostring(val) end
     
     local status_hl = "Comment"
     local status_icon = "🔹"
     
     if is_req then 
        if val then 
            status_icon = "✅" 
            status_hl = "String"
        else 
            status_icon = "🔴" 
            status_hl = "Error"
        end
     end
     
     table.insert(items, {
        group = group, 
        text = label, 
        key = key, 
        value = display_val,
        action = action, 
        icon = icon, 
        status = status_icon,
        hl = status_hl
     })
  end

  -- GROUP 1: DIMENSIONS
  add_item("1. Data Mapping", "X Axis", "x", "pick_col", "📊", vim.tbl_contains(req, "x"))
  
  if vim.tbl_contains(state.chart.req, "y") or vim.tbl_contains(state.chart.opt, "y") then
    add_item("1. Data Mapping", "Y Axis", "y", "pick_col", "📊", vim.tbl_contains(req, "y"))
  end

  -- NEW: Z-Axis Support
  if vim.tbl_contains(state.chart.req, "z") or vim.tbl_contains(state.chart.opt, "z") then
    add_item("1. Data Mapping", "Z Axis", "z", "pick_col", "🧊", vim.tbl_contains(req, "z"))
  end

  add_item("1. Data Mapping", "Group/Color", "hue", "pick_col", "🎨", false)

  -- GROUP 2: OPTIONS
  if state.chart.id == "hist" then
    add_item("2. Options", "KDE Line", "kde", "toggle_bool", "📈", false)
    add_item("2. Options", "Bins", "bins", "input_int", "🔢", false)
  elseif state.chart.id == "scatter" or state.chart.id == "scatter3d" then
    add_item("2. Options", "Opacity", "alpha", "input_float", "🌗", false)
    add_item("2. Options", "Size", "size", "pick_col", "⚪", false)
  end
  
  -- GROUP 3: STYLING
  add_item("3. Styling", "Theme", "theme", "pick_adapter_opt", "🎭", false)
  add_item("3. Styling", "Palette", "palette", "pick_adapter_opt", "🌈", false)
  add_item("3. Styling", "Title", "title", "input_text", "📝", false)

  -- GROUP 4: ACTIONS
  local gen_text = state.valid and "Generate Code" or "Missing Required Fields"
  local gen_icon = state.valid and "🚀" or "🚫"
  table.insert(items, { group = "4. Actions", text = gen_text, action = "generate", icon = gen_icon })
  
  if state.valid then
      table.insert(items, { group = "4. Actions", text = "Save Plot as PNG", action = "save_png", icon = "💾" })
  end

  Snacks.picker.pick({
    items = items,
    title = string.format(" %s %s [%s] ", state.chart.icon, state.chart.name, state.df),
    
    layout = {
      layout = {
        box = "horizontal", width = 0.95, height = 0.95,
        {
          box = "vertical", border = "rounded", title = "{title}", width = 0.4,
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        {
          win = "preview", title = " Live Preview ", border = "rounded", width = 0.6,
        },
      }
    },
    
    format = function(item)
      local ret = { 
          { item.status, "SnacksIcon" }, 
          { " " }, 
          { item.icon, "SnacksIcon" }, 
          { " " }, 
          { string.format("%-15s", item.text), "Normal" } 
      }
      if item.value and item.value ~= "" then
        table.insert(ret, { " │  ", "Comment" })
        table.insert(ret, { item.value, item.hl or "String" })
      end
      return ret
    end,
    
    preview = function(ctx)
      local ok, spec = pcall(M._build_spec_from_state)
      if not ok then return end
      local ok2, lines = pcall(generator.get_code_lines, spec, true)
      if not ok2 then return end
      
      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
      vim.bo[ctx.buf].modifiable = false
      vim.bo[ctx.buf].filetype = "python"
      
      if has_image and Builder.state.valid then
          M._render_live_image(ctx.buf, spec, lines)
      end
    end,
    
    confirm = function(picker, item)
      if item.action == "pick_col" then
        picker:close(); M._pick_column_rich(item.key)
      elseif item.action == "pick_adapter_opt" then
        picker:close(); M._pick_adapter_option(item.key)
      elseif item.action == "toggle_bool" then
        Builder.state.params[item.key] = not Builder.state.params[item.key]
        picker:find()
      elseif item.action == "input_text" then
        picker:close()
        vim.ui.input({ prompt = "Set " .. item.text, default = Builder.state.params[item.key] }, function(v)
            if v then Builder.state.params[item.key] = v end; M._open_dashboard()
        end)
      elseif item.action == "input_int" or item.action == "input_float" then
        picker:close()
        vim.ui.input({ prompt = "Set " .. item.text }, function(v)
            if v then Builder.state.params[item.key] = tonumber(v) end; M._open_dashboard()
        end)
      elseif item.action == "generate" then
        if Builder.state.valid then picker:close(); M._finalize() else vim.notify("Missing required fields!", vim.log.levels.WARN) end
      elseif item.action == "save_png" then
        picker:close()
        vim.ui.input({ prompt = "Filename (no ext): ", default = "plot" }, function(v)
            if v then M._finalize_save(v) end
        end)
      end
    end
  })
end

-- -------------------------------------------------------------------------
-- LIVE IMAGE RENDERING LOGIC
-- -------------------------------------------------------------------------

function M._render_live_image(bufnr, spec, code_lines)
  if Builder.debounce_timer then Builder.debounce_timer:stop() end
  Builder.debounce_timer = vim.defer_fn(function()
      M._execute_preview_job(spec, code_lines, bufnr)
  end, 200)
end

function M._execute_preview_job(spec, code_lines, bufnr)
  if Builder.preview_job then vim.fn.jobstop(Builder.preview_job) end
  
  local df_name = spec.df
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data/"
  local is_polars = (spec.lib == "polars") and "True" or "False"

  -- Data Loader Script
  local loader_script = string.format([[
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import os
import sys

base_path = "%s"
name = "%s"
feather_path = os.path.join(base_path, name + ".feather")
pkl_path = os.path.join(base_path, name + ".pkl")

try:
    df_loaded = None
    if os.path.exists(feather_path):
        df_loaded = pd.read_feather(feather_path)
    elif os.path.exists(pkl_path):
        df_loaded = pd.read_pickle(pkl_path)
    else:
        found = False
        if os.path.exists(base_path):
            for f in os.listdir(base_path):
                if f.endswith(f"__{name}.feather") or f.endswith(f"__{name}.pkl"):
                     if f.endswith(".feather"): df_loaded = pd.read_feather(os.path.join(base_path, f))
                     else: df_loaded = pd.read_pickle(os.path.join(base_path, f))
                     found = True
                     break
        if not found: print(f"Error: Snapshot not found for {name}"); exit(1)

    if %s: import polars as pl; globals()[name] = pl.from_pandas(df_loaded)
    else: globals()[name] = df_loaded
except Exception as e: print(f"Error loading snapshot: {e}"); exit(1)
]], cache_dir, df_name, is_polars)

  local py_code = table.concat(code_lines, "\n")
  py_code = py_code:gsub("plt%.show%(%)", "")
  
  -- Handle Different Backends
  if py_code:match("seaborn") or py_code:match("matplotlib") then
      py_code = py_code .. "\nplt.savefig('" .. Builder.tmp_file .. "', dpi=100, bbox_inches='tight')"
      Builder.preview_job = vim.fn.jobstart({"python3", "-c", py_code}, {
        on_exit = function(_, code)
          if code == 0 then vim.schedule(function() M._display_image_in_buffer(bufnr, #code_lines + 3) end) end
        end
      })
      
  elseif py_code:match("plotly") then
      -- NEW: Plotly Preview Logic
      py_code = py_code:gsub("fig%.show%(%)", "")
      py_code = py_code .. "\ntry:\n    import plotly.io as pio\n    # Requires Kaleido\n    pio.write_image(fig, '" .. Builder.tmp_file .. "', engine='kaleido', scale=2)\nexcept Exception as e: pass"
      Builder.preview_job = vim.fn.jobstart({"python3", "-c", py_code}, {
        on_exit = function(_, code)
          if code == 0 then vim.schedule(function() M._display_image_in_buffer(bufnr, #code_lines + 3) end) end
        end
      })
  end
end

function M._display_image_in_buffer(bufnr, start_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if Builder.active_img then Builder.active_img:clear() end
  
  local img = image_nvim.from_file(Builder.tmp_file, {
    buffer = bufnr, x = 0, y = start_line, width = 60, height = 20,
  })
  if img then 
      img:render()
      Builder.active_img = img
  end
end

-- -------------------------------------------------------------------------
-- PICKERS
-- -------------------------------------------------------------------------

function M._pick_column_rich(param_key)
  local state = Builder.state
  local items = {}
  table.insert(items, { text = "(None)", idx = 0, icon = "🚫", col = { name = "None", dtype = "none" } })

  for i, col_name in ipairs(state.cols) do
    local meta = state.metadata and state.metadata[col_name] or {}
    local col_data = context.create_column_entry(col_name, meta, i)
    local icon = "📊"
    if context._is_numeric(col_data.dtype) then icon = "🔢"
    elseif col_data.dtype:match("date") then icon = "📅" end

    table.insert(items, { text = col_name, idx = i, icon = icon, col = col_data, comment = col_data.dtype })
  end

  Snacks.picker.pick({
    items = items, title = " Select " .. param_key:upper() .. " ",
    layout = {
      layout = {
        box = "horizontal", width = 0.9, height = 0.9,
        {
          box = "vertical", border = "rounded", title = "{title}", width = 0.3,
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        { win = "preview", title = " Column Statistics ", border = "rounded", width = 0.7 },
      }
    },
    format = function(item) return { { item.icon, "SnacksIcon" }, { " " }, { item.text, "Normal" }, { "  " }, { item.comment, "Comment" } } end,
    preview = function(p_ctx)
        if p_ctx.item.text == "(None)" then return end
        local ok, lines = pcall(inspector.get_column_preview_lines, p_ctx.item.col)
        if not ok then return end
        vim.bo[p_ctx.buf].modifiable = true
        vim.api.nvim_buf_set_lines(p_ctx.buf, 0, -1, false, lines)
        vim.bo[p_ctx.buf].modifiable = false
        local ns = vim.api.nvim_create_namespace("scivim_inspect")
        for i, line in ipairs(lines) do
            if line:match("^%s*📦") then vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Title", i - 1, 0, -1) end
            local s_idx = 1
            while true do
                local s, e = string.find(line, "[▂▃▄▅▆▇█]+", s_idx)
                if not s then break end
                vim.api.nvim_buf_add_highlight(p_ctx.buf, ns, "Function", i - 1, s - 1, e)
                s_idx = e + 1
            end
        end
    end,
    confirm = function(picker, item)
      picker:close()
      Builder.state.params[param_key] = (item.text ~= "(None)") and item.text or nil
      vim.schedule(function() M._open_dashboard() end)
    end
  })
end

function M._pick_adapter_option(key)
  local adapter = generator.get_active_plot_adapter()
  if not adapter then 
      vim.notify("No active plot adapter found", vim.log.levels.WARN)
      return 
  end

  local opts = adapter[key .. "s"] 
  if not opts or #opts == 0 then
      vim.notify("No " .. key .. " options available for this backend", vim.log.levels.INFO)
      return
  end

  local items = {}
  for _, v in ipairs(opts) do table.insert(items, { text = v }) end
  
  Snacks.picker.pick({
    items = items, title = "Select " .. key, layout = "vscode", 
    format = function(item) return { { item.text, "Normal" } } end,
    confirm = function(picker, item)
      picker:close()
      if item then Builder.state.params[key] = item.text end
      vim.schedule(function() M._open_dashboard() end)
    end
  })
end

function M._build_spec_from_state()
  local s = Builder.state
  local spec = vim.deepcopy(s.params)
  spec.df = s.df
  spec.lib = s.lib
  spec.chart = s.chart
  return spec
end

function M._finalize()
  local spec = M._build_spec_from_state()
  generator.generate(spec)
  Builder.active = false
  if Builder.active_img then Builder.active_img:clear() end
end

function M._finalize_save(filename)
  local spec = M._build_spec_from_state()
  spec.save_format = "png"
  spec.save_filename = filename
  generator.generate(spec)
  Builder.active = false
  if Builder.active_img then Builder.active_img:clear() end
end

return M


