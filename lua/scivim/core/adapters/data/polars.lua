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
