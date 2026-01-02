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
