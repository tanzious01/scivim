-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- =========================================================================
-- LIVE TRANSFORM - Interactive UI (Polyglot: Python + SQL)
-- =========================================================================
local M = {}

local executor = require("scivim.backend.client")
local context = require("scivim.core.context") -- [[ NEW: Required for Workspace Loading ]]
local Snacks = require("snacks")

local ICONS = {
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    pandas  = "🐼",
    polars  = "🐻",
    lazy    = "🐨",
    global  = "🌍",
    prompt  = "  ", 
}

-- 1. Standalone Highlights
local function setup_highlights()
    local hls = {
        ScivimBorder      = { link = "FloatBorder" },
        ScivimTitle       = { link = "Title" },
        ScivimPrompt      = { link = "NormalFloat" },
        ScivimInputPrefix = { fg = "#f38ba8", bold = true },
        ScivimError       = { fg = "#f38ba8" },
    }
    if vim.fn.hlexists("SnacksPickerBorder") == 1 then
        hls.ScivimBorder = { link = "SnacksPickerBorder" }
        hls.ScivimTitle  = { link = "SnacksPickerTitle" }
    end
    for group, opts in pairs(hls) do vim.api.nvim_set_hl(0, group, opts) end
end
setup_highlights()

-- ----------------------------------------------------------------------------
-- STATE
-- ----------------------------------------------------------------------------
local state = {
  current_code = "",
  update_timer = nil, -- Timer for RPC Preview (fast debounce)
  lsp_timer = nil,    -- Timer for Disk Write/LSP (slow debounce)
  ctx = nil,          -- nil = Global Workspace Mode
  preview_win = nil,
  input_win = nil,
  parent_win = nil,
  ghost_path = nil,
  spinner_timer = nil,
  spinner_idx = 1,
}

local function get_df_icon(ctx) 
    if not ctx then return ICONS.global end
    return (ctx.lib == "polars" and (ctx.is_lazy and ICONS.lazy or ICONS.polars) or ICONS.pandas) 
end

local function get_title(ctx)
    if not ctx then return " Global Workspace " end
    return string.format(" %s %s ", get_df_icon(ctx), ctx.name)
end

local function stop_spinner()
    if state.spinner_timer then state.spinner_timer:stop(); state.spinner_timer:close(); state.spinner_timer = nil end
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win.win) then
         pcall(vim.api.nvim_win_set_config, state.input_win.win, { title = get_title(state.ctx), title_pos = "center" })
    end
end

local function start_spinner()
    if state.spinner_timer then return end
    state.spinner_idx = 1
    state.spinner_timer = vim.loop.new_timer()
    state.spinner_timer:start(0, 100, vim.schedule_wrap(function()
        if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win.win) then stop_spinner(); return end
        local frame = ICONS.spinner[state.spinner_idx]
        state.spinner_idx = (state.spinner_idx % #ICONS.spinner) + 1
        pcall(vim.api.nvim_win_set_config, state.input_win.win, { title = string.format(" %s Processing... ", frame), title_pos = "center" })
    end))
end

local function cleanup_state()
  stop_spinner()
  -- Clean RPC Timer
  if state.update_timer then pcall(function() state.update_timer:stop() end); pcall(function() state.update_timer:close() end); state.update_timer = nil end
  -- Clean LSP Timer
  if state.lsp_timer then pcall(function() state.lsp_timer:stop() end); pcall(function() state.lsp_timer:close() end); state.lsp_timer = nil end
  
  if state.preview_win then pcall(function() state.preview_win:close() end); state.preview_win = nil end
  if state.input_win then
    if state.input_win.buf and vim.api.nvim_buf_is_valid(state.input_win.buf) then pcall(vim.cmd, "bdelete! " .. state.input_win.buf) end
    pcall(function() state.input_win:close() end); state.input_win = nil
  end
  if state.ghost_path and vim.fn.filereadable(state.ghost_path) == 1 then os.remove(state.ghost_path) end
  state.ghost_path = nil
  state.current_code = ""
  state.ctx = nil
  state.parent_win = nil
end

local function center_lines(lines, win)
  if not win or not win.win or not vim.api.nvim_win_is_valid(win.win) then return lines end
  local width = vim.api.nvim_win_get_width(win.win)
  local centered = {}
  for _, line in ipairs(lines) do
    local line_len = vim.fn.strdisplaywidth(line)
    if line_len < width then table.insert(centered, string.rep(" ", math.floor((width - line_len) / 2)) .. line) else table.insert(centered, line) end
  end
  return centered
end

-- ----------------------------------------------------------------------------
-- UPDATE LOGIC
-- ----------------------------------------------------------------------------
local function update_preview(response)
  stop_spinner()
  if not state.preview_win or not state.preview_win.buf or not vim.api.nvim_buf_is_valid(state.preview_win.buf) then return end
  
  local lines = {}
  local border_hl = "ScivimBorder"

  if response.error and type(response.error) == "string" then
    if not (response.error:match("Syntax") or response.error:match("unexpected EOF")) then
      border_hl = "ScivimError"
      local err_lines = vim.split(response.error, "\n")
      table.insert(lines, ""); table.insert(lines, "💥 " .. (err_lines[1] or "Error")); table.insert(lines, string.rep("─", 40))
      for i = 2, #err_lines do table.insert(lines, "  " .. err_lines[i]) end
    end
  end

  if response.text_table and type(response.text_table) == "string" then
    local raw_lines = vim.split(response.text_table, '\n')
    vim.list_extend(lines, center_lines(raw_lines, state.preview_win))
  end
  
  if vim.api.nvim_win_is_valid(state.preview_win.win) then
      vim.api.nvim_win_set_option(state.preview_win.win, "winhighlight", "FloatBorder:"..border_hl..",Normal:NormalFloat")
  end
  
  vim.api.nvim_buf_set_lines(state.preview_win.buf, 0, -1, false, lines)
end

local function trigger_request()
  start_spinner()
  -- Logic: If state.ctx exists, send its details. If nil (Global), send empty string but keep the request type.
  local name = state.ctx and state.ctx.name or ""
  local lib = state.ctx and state.ctx.lib or "pandas"
  local is_lazy = state.ctx and state.ctx.is_lazy or false
  
  executor.run_transform_async(
    name,
    lib,
    is_lazy,
    state.current_code,
    function(response)
      if state.input_win and state.preview_win then
          vim.schedule(function() update_preview(response) end)
      end
    end
  )
end

local function debounced_update(code)
  state.current_code = code
  if state.update_timer then state.update_timer:stop(); state.update_timer:close() end
  state.update_timer = vim.loop.new_timer()
  -- Fast debounce (150ms) for Preview RPC
  state.update_timer:start(150, 0, vim.schedule_wrap(trigger_request))
end

-- ----------------------------------------------------------------------------
-- UI LAUNCHER & UTILS
-- ----------------------------------------------------------------------------

local function patch_lsp_client(client)
    if client._scivim_patched then return end
    local method = "textDocument/signatureHelp"
    local orig_handler = client.handlers[method] or vim.lsp.handlers[method]
    client.handlers[method] = function(err, result, ctx, config)
        if ctx and ctx.bufnr and vim.b[ctx.bufnr].scivim_hide_signature then return end
        if orig_handler then orig_handler(err, result, ctx, config) end
    end
    client._scivim_patched = true
end

-- [[ UPDATED: Generate stub for ALL DataFrames in workspace ]]
local function generate_workspace_stub(all_contexts, primary_ctx)
  local lines = {}
  -- Imports for all potential libs
  table.insert(lines, "import pandas as pd")
  table.insert(lines, "import numpy as np")
  table.insert(lines, "import polars as pl")
  table.insert(lines, "from polars import col, lit, when")
  table.insert(lines, "")

  -- Generate a class and instance for EVERY dataframe found
  for _, ctx in pairs(all_contexts) do
      local class_name = ctx.name .. "_Type"
      local parent_class = "pd.DataFrame"
      if ctx.lib == "polars" then
          parent_class = ctx.is_lazy and "pl.LazyFrame" or "pl.DataFrame"
      end

      table.insert(lines, string.format("class %s(%s):", class_name, parent_class))
      
      if ctx.columns and #ctx.columns > 0 then
          for _, col in ipairs(ctx.columns) do
              -- Sanitize column names for Python syntax
              if col:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                  local type_hint = "pd.Series"
                  if ctx.lib == "polars" then type_hint = "pl.Expr" end
                  table.insert(lines, string.format("    %s: %s", col, type_hint))
              end
          end
      else
          table.insert(lines, "    pass")
      end
      table.insert(lines, "")
      -- Instantiate it so LSP sees the variable
      table.insert(lines, string.format("%s: %s = %s()", ctx.name, class_name, class_name))
  end

  -- If we focused on one specific DF, alias it to 'df'
  if primary_ctx then
      table.insert(lines, "")
      table.insert(lines, string.format("df = %s", primary_ctx.name))
  end

  return table.concat(lines, "\n")
end

local function setup_lsp_completion(input_buf, parent_buf, ctx)
  if not vim.api.nvim_buf_is_valid(input_buf) then return end
  
  -- 1. Aggressively flag this buffer to hide signatures
  vim.b[input_buf].scivim_hide_signature = true

  -- 2. Hook into LspAttach to castrate the signature capability for this specific buffer
  -- [FIX: This prevents the 'height must be positive Integer' crash]
  vim.api.nvim_create_autocmd("LspAttach", {
    buffer = input_buf,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then
        -- DISABLE Signature Help Capability for this instance
        if client.server_capabilities then
          client.server_capabilities.signatureHelpProvider = nil
        end
        -- Patch handler just in case capability check is bypassed
        patch_lsp_client(client) 
      end
    end
  })

  -- 3. Ghost File Setup (Standard Scivim Logic)
  local start_path = vim.api.nvim_buf_get_name(parent_buf)
  if start_path == "" then start_path = vim.fn.getcwd() end
  
  -- Use system temp to prevent workspace pollution
  local root_markers = { "pyproject.toml", "requirements.txt", ".git", ".venv", "venv" }
  local root_dir = vim.fs.dirname(vim.fs.find(root_markers, { path = start_path, upward = true })[1] or start_path)
  
  -- Optimization: Keep ghost file in root to allow relative imports in analysis
  local fake_path = root_dir .. "/__scivim_ghost_" .. os.time() .. ".py"
  state.ghost_path = fake_path
  
  local all_data = context.load_all() or {}
  local stub_content = generate_workspace_stub(all_data, ctx)
  local f = io.open(fake_path, "w"); if f then f:write(stub_content); f:close() end
  
  vim.api.nvim_buf_set_name(input_buf, fake_path)
  vim.bo[input_buf].buftype = "" 
  vim.bo[input_buf].filetype = "python"
  
  vim.api.nvim_buf_set_lines(input_buf, 0, 0, false, vim.split(stub_content, '\n'))
  
  -- Silence the write message
  vim.api.nvim_buf_call(input_buf, function() vim.cmd("silent! write") end)

  -- 4. Manual Client Attachment (Debounced)
  vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(input_buf) then return end
      
      -- Prioritize Pyright/BasedPyright/Pyrefly
      local attached = false
      local available_clients = vim.lsp.get_clients({ bufnr = parent_buf }) -- Optimization: reuse parent clients
      
      for _, client in ipairs(available_clients) do
         if client.name == "pyright" or client.name == "basedpyright" or client.name == "pyrefly" then
             vim.lsp.buf_attach_client(input_buf, client.id)
             attached = true
             break
         end
      end
      
      -- Fallback to global search if parent had no LSP
      if not attached then
          for _, client in ipairs(vim.lsp.get_clients()) do
             if client.name == "pyright" or client.name == "basedpyright" then
                 vim.lsp.buf_attach_client(input_buf, client.id)
                 break 
             end
          end
      end
  end)

  -- 5. CMP Setup (ensure 'buffer' source is prioritized for local variables)
  vim.defer_fn(function() 
      local has_cmp, cmp = pcall(require, "cmp")
      if has_cmp then 
          cmp.setup.buffer({ 
              enabled = true,
              completion = { autocomplete = { cmp.TriggerEvent.TextChanged } },
              sources = cmp.config.sources({ 
                  { name = "nvim_lsp", priority = 1000 }, 
                  { name = "buffer", priority = 500 } 
              }) 
          }) 
      end 
  end, 100)
end

local function open_transform_ui(ctx)
  state.ctx = ctx -- Can be nil for Global Mode
  state.current_code = ""
  state.parent_win = vim.api.nvim_get_current_win()
  local parent_buf = vim.api.nvim_get_current_buf()
  
  -- Dimensions
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local input_h = 3
  local preview_h = height - input_h

  local title_text = get_title(ctx)
  
  -- 1. Input Window
  state.input_win = Snacks.win({
    relative = "editor", row = row, col = col, width = width, height = 1,
    border = "rounded", title = title_text, title_pos = "center",
    wo = { winhighlight = "FloatBorder:ScivimBorder,Title:ScivimTitle,Normal:ScivimPrompt", scrolloff = 0 },
    keys = { ["<Esc>"] = { "close", mode = {"n", "i"} }, ["<C-c>"] = { "close", mode = {"n", "i"} } }
  })

  -- 2. Preview Window
  state.preview_win = Snacks.win({
    relative = "editor", row = row + input_h, col = col, width = width, height = preview_h,
    border = "rounded", wo = { winhighlight = "FloatBorder:ScivimBorder,Normal:NormalFloat" }, interactive = false
  })
  
  -- 3. Setup Input Buffer
  local input_buf = state.input_win.buf
  -- [[ NEW: Pass ctx (could be nil) for workspace generation ]]
  setup_lsp_completion(input_buf, parent_buf, ctx)
  
  -- Prompt Icon
  local ns_id = vim.api.nvim_create_namespace("scivim_prompt")
  local function set_prompt_extmark() 
      vim.api.nvim_buf_set_extmark(input_buf, ns_id, 0, 0, { virt_text = {{ ICONS.prompt, "ScivimInputPrefix" }}, virt_text_pos = "inline" }) 
  end
  
  -- Stub calculation needs to check if we are global or local
  local all_data = context.load_all() or {}
  local stub_lines = vim.split(generate_workspace_stub(all_data, ctx), '\n')
  local content_offset = #stub_lines + 1
  
  vim.defer_fn(function() 
      if vim.api.nvim_buf_is_valid(input_buf) and vim.api.nvim_win_is_valid(state.input_win.win) then 
          local line_count = vim.api.nvim_buf_line_count(input_buf)
          if line_count < content_offset then vim.api.nvim_buf_set_lines(input_buf, line_count, -1, false, { "" }) end
          vim.api.nvim_win_set_cursor(state.input_win.win, {content_offset, 0})
          vim.fn.winrestview({topline = content_offset, lnum = content_offset, col = 0})
          set_prompt_extmark() 
      end 
  end, 150)
  
  vim.api.nvim_set_current_win(state.input_win.win)
  vim.cmd("startinsert")
  
  -- Initialize Timer
  state.lsp_timer = vim.loop.new_timer()

  -- Auto-update hook with OPTIMIZED IO DEBOUNCE
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, { 
      buffer = input_buf, 
      callback = function() 
          set_prompt_extmark()

          -- 1. DEBOUNCED DISK WRITE (Fixes IO Thrashing for LSP)
          if state.lsp_timer then
              state.lsp_timer:stop()
              state.lsp_timer:start(500, 0, vim.schedule_wrap(function()
                 if vim.api.nvim_buf_is_valid(input_buf) then
                     vim.api.nvim_buf_call(input_buf, function() 
                         vim.cmd("silent! write") 
                     end)
                 end
              end))
          end
          
          -- 2. GET TEXT & DETECT SQL (Immediate Logic)
          local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
          local user_lines = {}
          for i = content_offset, #all_lines do if all_lines[i] then table.insert(user_lines, all_lines[i]) end end
          
          local full_text = table.concat(user_lines, "\n")
          
          -- Dynamic SQL Syntax Switching
          local first_word = full_text:match("^%s*(%w+)")
          if first_word then
              first_word = first_word:upper()
              if vim.tbl_contains({"SELECT", "WITH", "PRAGMA", "DESCRIBE", "SHOW", "EXPLAIN"}, first_word) then
                  if vim.bo[input_buf].filetype ~= "sql" then vim.bo[input_buf].filetype = "sql" end
              else
                  if vim.bo[input_buf].filetype ~= "python" then vim.bo[input_buf].filetype = "python" end
              end
          end

          -- 3. TRIGGER PREVIEW (Fast Debounce)
          debounced_update(full_text) 
      end 
  })
  trigger_request()
  
  -- Close/Accept Logic with SMART SUBSTITUTION
  local function accept_and_close()
    local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local user_lines = {}
    for i = content_offset, #all_lines do if all_lines[i] then table.insert(user_lines, all_lines[i]) end end
    local code = table.concat(user_lines, "\n")
    
    local target_win = state.parent_win
    cleanup_state()
    
    if target_win and vim.api.nvim_win_is_valid(target_win) then
        vim.api.nvim_set_current_win(target_win)
    end
    
    if code and code ~= "" then
        -- Check if it was SQL or Python
        local start_token = code:match("^%s*(%w+)")
        local is_sql = false
        if start_token and vim.tbl_contains({"SELECT", "WITH", "PRAGMA"}, start_token:upper()) then
            is_sql = true
        end

        local full_code = code
        if not is_sql then
            -- [[ NEW: Smart Substitution ]]
            -- Only replace 'df' if we are in a Specific Context
            if ctx then
                -- Be careful: don't replace 'df_sales' with 'ctx.name_sales'
                -- 1. Replace 'df.' with 'name.'
                if code:match("^%s*df%.") then
                    full_code = code:gsub("^%s*df", ctx.name, 1)
                -- 2. Replace chaining .function()
                elseif code:match("^%s*%.") then
                    full_code = ctx.name .. code
                else
                    -- 3. Replace isolated 'df'
                    full_code = code:gsub("([^%w_])df([^%w_])", "%1" .. ctx.name .. "%2")
                    full_code = full_code:gsub("^df([^%w_])", ctx.name .. "%1")
                    full_code = full_code:gsub("([^%w_])df$", "%1" .. ctx.name)
                    -- If the code was just "df", replace it
                    if full_code == "df" then full_code = ctx.name end
                end
            end
        else
            -- SQL Substitution Logic
            if ctx then
                -- In specific mode, allow 'FROM df' shorthand
                local clean_code = code:gsub("FROM%s+df", "FROM " .. ctx.name)
                clean_code = clean_code:gsub("from%s+df", "FROM " .. ctx.name)
                clean_code = clean_code:gsub("JOIN%s+df", "JOIN " .. ctx.name)
                -- Wrap in duckdb call
                full_code = string.format("import duckdb\n%s_sql = duckdb.sql(\"\"\"%s\"\"\").df()", ctx.name, clean_code)
            else
                -- In Global Mode, raw SQL, no wrapper auto-assign
                full_code = string.format("import duckdb\nsql_res = duckdb.sql(\"\"\"%s\"\"\").df()", code)
            end
        end
        vim.api.nvim_put(vim.split(full_code, '\n'), "c", true, true)
    end
  end
  
  vim.keymap.set({"n", "i"}, "<CR>", function() vim.cmd("stopinsert"); accept_and_close() end, { buffer = input_buf })
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, { buffer = input_buf, callback = function() vim.defer_fn(cleanup_state, 100) end, once = true })
end

-- [[ UPDATED: Picker now includes Global Option ]]
function M.inspect_transform(ctx_arg)
  if ctx_arg then 
    open_transform_ui(ctx_arg) 
  else 
    local all_data = context.load_all()
    local ctx_list = {}
    if all_data then for _, v in pairs(all_data) do table.insert(ctx_list, v) end end
    
    if #ctx_list == 0 then 
        vim.notify("No dataframes exposed via vim_expose()", vim.log.levels.WARN) 
    elseif #ctx_list == 1 then 
        open_transform_ui(ctx_list[1]) 
    else 
        local items = {}
        -- Add Global Option First
        table.insert(items, { 
            text = "Global Workspace (All DataFrames)", 
            ctx = nil, 
            icon = ICONS.global 
        })
        
        for _, c in ipairs(ctx_list) do 
            table.insert(items, { 
                text = c.name, 
                ctx = c, 
                icon = get_df_icon(c) 
            }) 
        end
        
        Snacks.picker.pick({
            items = items,
            title = "Select Context",
            layout = "vscode",
            format = function(item) 
                return { { item.icon, "SnacksIcon" }, { " " }, { item.text, "Normal" } } 
            end,
            confirm = function(picker, item)
                picker:close()
                if item then open_transform_ui(item.ctx) end
            end
        })
    end 
  end
end

return M
