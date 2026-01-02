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
