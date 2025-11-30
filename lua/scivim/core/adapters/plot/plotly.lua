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
