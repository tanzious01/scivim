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
