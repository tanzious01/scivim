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
