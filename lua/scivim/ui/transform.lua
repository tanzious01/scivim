-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- /home/tanzious/scivim/lua/scivim/ui/transform.lua
-- =========================================================================
-- LIVE TRANSFORM - Interactive UI (Polyglot: Python + Polars SQL)
-- Optimized: sqlglot-transpilation & native Polars execution
-- =========================================================================
local M = {}

local executor = require("scivim.backend.client")
local context = require("scivim.core.context")
local Snacks = require("snacks")

local ICONS = {
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    pandas  = "🐼",
    polars  = "🧊🐻", -- UPDATED: Actual Polar Bear Branding
    lazy    = "🐨",
    global  = "🌍",
    prompt  = "  ", 
}

-- ----------------------------------------------------------------------------
-- HIGHLIGHTS & STATE
-- ----------------------------------------------------------------------------
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

local state = {
  current_code = "",
  update_timer = nil, 
  lsp_timer = nil,    
  ctx = nil,          
  preview_win = nil,
  input_win = nil,
  parent_win = nil,
  ghost_path = nil,
  spinner_timer = nil,
  spinner_idx = 1,
}

-- ----------------------------------------------------------------------------
-- UI UTILS (Icons, Spinners, Centering)
-- ----------------------------------------------------------------------------

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
  if state.update_timer then pcall(function() state.update_timer:stop() end); state.update_timer = nil end
  if state.lsp_timer then pcall(function() state.lsp_timer:stop() end); state.lsp_timer = nil end
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
-- UPDATE LOGIC (With Dynamic Resizing)
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

  -- DYNAMIC RESIZING
  local table_height = #lines
  local max_allowed_h = math.floor(vim.o.lines * 0.7)
  local final_h = math.max(3, math.min(table_height, max_allowed_h))
  
  if vim.api.nvim_win_is_valid(state.preview_win.win) then
      pcall(vim.api.nvim_win_set_config, state.preview_win.win, {
          height = final_h,
          row = math.floor(vim.o.lines * 0.1) + 3 
      })
  end
end

local function trigger_request()
  start_spinner()
  local name = state.ctx and state.ctx.name or ""
  local lib = state.ctx and state.ctx.lib or "pandas"
  local is_lazy = state.ctx and state.ctx.is_lazy or false
  
  executor.run_transform_async(name, lib, is_lazy, state.current_code, function(response)
      if state.input_win and state.preview_win then
          vim.schedule(function() update_preview(response) end)
      end
  end)
end

local function debounced_update(code)
  state.current_code = code
  if state.update_timer then state.update_timer:stop(); state.update_timer:close() end
  state.update_timer = vim.loop.new_timer()
  state.update_timer:start(150, 0, vim.schedule_wrap(trigger_request))
end

-- ----------------------------------------------------------------------------
-- LSP GHOST FILE & STUB LOGIC
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

local function generate_workspace_stub(all_contexts, primary_ctx)
  local lines = { "import pandas as pd", "import numpy as np", "import polars as pl", "from polars import col, lit, when", "" }

  for _, ctx in pairs(all_contexts) do
      local class_name = ctx.name .. "_Type"
      local parent_class = (ctx.lib == "polars") and (ctx.is_lazy and "pl.LazyFrame" or "pl.DataFrame") or "pd.DataFrame"
      table.insert(lines, string.format("class %s(%s):", class_name, parent_class))
      if ctx.columns and #ctx.columns > 0 then
          for _, col_n in ipairs(ctx.columns) do
              if col_n:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                  local hint = (ctx.lib == "polars") and "pl.Expr" or "pd.Series"
                  table.insert(lines, string.format("    %s: %s", col_n, hint))
              end
          end
      else table.insert(lines, "    pass") end
      table.insert(lines, string.format("%s: %s = %s()", ctx.name, class_name, class_name))
  end
  if primary_ctx then table.insert(lines, "\ndf = " .. primary_ctx.name) end
  return table.concat(lines, "\n")
end

local function setup_lsp_completion(input_buf, parent_buf, ctx)
  if not vim.api.nvim_buf_is_valid(input_buf) then return end
  vim.b[input_buf].scivim_hide_signature = true

  vim.api.nvim_create_autocmd("LspAttach", {
    buffer = input_buf,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then
        if client.server_capabilities then client.server_capabilities.signatureHelpProvider = nil end
        patch_lsp_client(client) 
      end
    end
  })

  local start_path = vim.api.nvim_buf_get_name(parent_buf)
  if start_path == "" then start_path = vim.fn.getcwd() end
  local root_markers = { "pyproject.toml", "requirements.txt", ".git", ".venv", "venv" }
  local root_dir = vim.fs.dirname(vim.fs.find(root_markers, { path = start_path, upward = true })[1] or start_path)
  
  local fake_path = root_dir .. "/__scivim_ghost_" .. os.time() .. ".py"
  state.ghost_path = fake_path
  
  local all_data = context.load_all() or {}
  local stub_content = generate_workspace_stub(all_data, ctx)
  local f = io.open(fake_path, "w"); if f then f:write(stub_content); f:close() end
  
  vim.api.nvim_buf_set_name(input_buf, fake_path)
  vim.bo[input_buf].filetype = "python"
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, vim.split(stub_content, '\n'))
  vim.api.nvim_buf_call(input_buf, function() vim.cmd("silent! write") end)

  vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(input_buf) then return end
      local available_clients = vim.lsp.get_clients({ bufnr = parent_buf })
      for _, client in ipairs(available_clients) do
         if client.name == "pyright" or client.name == "basedpyright" or client.name == "pyrefly" then
             vim.lsp.buf_attach_client(input_buf, client.id)
             break
         end
      end
  end)
end

-- ----------------------------------------------------------------------------
-- UI MAIN & SUBSTITUTION LOGIC (POLARS SQL FIX)
-- ----------------------------------------------------------------------------

local function open_transform_ui(ctx)
  state.ctx = ctx; state.current_code = ""; state.parent_win = vim.api.nvim_get_current_win()
  local parent_buf = vim.api.nvim_get_current_buf()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  state.input_win = Snacks.win({
    relative = "editor", row = row, col = col, width = width, height = 1,
    border = "rounded", title = get_title(ctx), title_pos = "center",
    wo = { winhighlight = "FloatBorder:ScivimBorder,Title:ScivimTitle,Normal:ScivimPrompt", scrolloff = 0 },
    keys = { ["<Esc>"] = { "close", mode = {"n", "i"} }, ["<C-c>"] = { "close", mode = {"n", "i"} } }
  })

  state.preview_win = Snacks.win({
    relative = "editor", row = row + 3, col = col, width = width, height = height - 3,
    border = "rounded", wo = { winhighlight = "FloatBorder:ScivimBorder,Normal:NormalFloat", wrap = false }, interactive = false
  })
  
  local input_buf = state.input_win.buf
  setup_lsp_completion(input_buf, parent_buf, ctx)
  
  local ns_id = vim.api.nvim_create_namespace("scivim_prompt")
  local function set_prompt_extmark() 
      vim.api.nvim_buf_set_extmark(input_buf, ns_id, 0, 0, { virt_text = {{ ICONS.prompt, "ScivimInputPrefix" }}, virt_text_pos = "inline" }) 
  end
  
  local all_data = context.load_all() or {}
  local stub_lines = vim.split(generate_workspace_stub(all_data, ctx), '\n')
  local content_offset = #stub_lines + 1
  
  vim.defer_fn(function() 
      if vim.api.nvim_buf_is_valid(input_buf) then 
          if vim.api.nvim_buf_line_count(input_buf) < content_offset then vim.api.nvim_buf_set_lines(input_buf, content_offset-1, -1, false, { "" }) end
          vim.api.nvim_win_set_cursor(state.input_win.win, {content_offset, 0})
          set_prompt_extmark() 
      end 
  end, 150)
  
  vim.api.nvim_set_current_win(state.input_win.win)
  vim.cmd("startinsert")
  state.lsp_timer = vim.loop.new_timer()

  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, { 
      buffer = input_buf, 
      callback = function() 
          set_prompt_extmark()
          if state.lsp_timer then
              state.lsp_timer:stop()
              state.lsp_timer:start(500, 0, vim.schedule_wrap(function()
                 if vim.api.nvim_buf_is_valid(input_buf) then
                    local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
                    local content = table.concat(lines, "\n")
                    vim.loop.fs_open(state.ghost_path, "w", 438, function(err, fd)
                        if not err then vim.loop.fs_write(fd, content, 0, function() vim.loop.fs_close(fd) end) end
                    end)
                 end
              end))
          end
          
          local all_l = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
          local user_l = {}; for i = content_offset, #all_l do table.insert(user_l, all_l[i]) end
          local full_text = table.concat(user_l, "\n")
          
          local first_w = full_text:match("^%s*(%w+)")
          if first_w then
              first_w = first_w:upper()
              local is_sql = vim.tbl_contains({"SELECT", "WITH", "PRAGMA", "DESCRIBE", "SHOW", "EXPLAIN"}, first_w)
              vim.bo[input_buf].filetype = is_sql and "sql" or "python"
          end
          debounced_update(full_text) 
      end 
  })

  local function accept_and_close()
    local all_l = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local user_l = {}; for i = content_offset, #all_l do table.insert(user_l, all_l[i]) end
    local code = table.concat(user_l, "\n")
    local target_win = state.parent_win
    cleanup_state()
    if target_win and vim.api.nvim_win_is_valid(target_win) then vim.api.nvim_set_current_win(target_win) end
    
    if code and code ~= "" then
        local first = code:match("^%s*(%w+)")
        local is_sql = first and vim.tbl_contains({"SELECT", "WITH", "PRAGMA"}, first:upper())
        local full_code = code

        if is_sql then
            -- [[ FIXED: POLARS SQLCONTEXT GENERATION ]]
            local df_target = ctx and ctx.name or "df_sql_result"
            full_code = table.concat({
                "import polars as pl",
                "# Native Polars SQL engine (sqlglot-powered)",
                "sql_ctx = pl.SQLContext(register_globals=True)",
                string.format("%s = sql_ctx.execute(\"\"\"%s\"\"\", eager=True)", df_target, code),
            }, "\n")
        else
            if ctx then
                if code:match("^%s*df%.") then full_code = code:gsub("^%s*df", ctx.name, 1)
                elseif code:match("^%s*%.") then full_code = ctx.name .. code
                else
                    full_code = code:gsub("([^%w_])df([^%w_])", "%1" .. ctx.name .. "%2")
                    full_code = full_code:gsub("^df([^%w_])", ctx.name .. "%1")
                    full_code = full_code:gsub("([^%w_])df$", "%1" .. ctx.name)
                    if full_code == "df" then full_code = ctx.name end
                end
            end
        end
        vim.api.nvim_put(vim.split(full_code, '\n'), "c", true, true)
    end
  end
  
  vim.keymap.set({"n", "i"}, "<CR>", function() vim.cmd("stopinsert"); accept_and_close() end, { buffer = input_buf })
end

function M.inspect_transform(ctx_arg)
  if ctx_arg then open_transform_ui(ctx_arg) 
  else 
    local all_data = context.load_all()
    local ctx_list = {}; if all_data then for _, v in pairs(all_data) do table.insert(ctx_list, v) end end
    if #ctx_list == 0 then vim.notify("No dataframes exposed", vim.log.levels.WARN) 
    elseif #ctx_list == 1 then open_transform_ui(ctx_list[1]) 
    else 
        local items = { { text = "Global Workspace (All DataFrames)", ctx = nil, icon = ICONS.global } }
        for _, c in ipairs(ctx_list) do table.insert(items, { text = c.name, ctx = c, icon = get_df_icon(c) }) end
        Snacks.picker.pick({
            items = items, title = "Select Context", layout = "vscode",
            format = function(item) return { { item.icon, "SnacksIcon" }, { " " }, { item.text, "Normal" } } end,
            confirm = function(picker, item) picker:close(); if item then open_transform_ui(item.ctx) end end
        })
    end 
  end
end

return M
