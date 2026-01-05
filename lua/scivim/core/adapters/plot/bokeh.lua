-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
-- /home/tanzious/scivim/lua/scivim/core/adapters/plot/bokeh.lua
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
