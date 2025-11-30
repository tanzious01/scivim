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
