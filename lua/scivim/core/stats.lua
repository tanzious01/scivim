-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
-- /home/tanzious/scivim/lua/scivim/core/stats.lua
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
