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
