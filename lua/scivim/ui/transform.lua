-- =========================================================================
-- LIVE TRANSFORM - Interactive UI (Polyglot: Python + SQL)
-- =========================================================================
local M = {}

local executor = require("scivim.backend.client")
local Snacks = require("snacks")

local ICONS = {
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    pandas  = "🐼",
    polars  = "🐻",
    lazy    = "🐨",
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
  update_timer = nil,
  ctx = nil,
  preview_win = nil,
  input_win = nil,
  parent_win = nil,
  ghost_path = nil,
  spinner_timer = nil,
  spinner_idx = 1,
}

local function get_df_icon(ctx) 
    return (ctx.lib == "polars" and (ctx.is_lazy and ICONS.lazy or ICONS.polars) or ICONS.pandas) 
end

local function stop_spinner()
    if state.spinner_timer then state.spinner_timer:stop(); state.spinner_timer:close(); state.spinner_timer = nil end
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win.win) then
         local icon = get_df_icon(state.ctx)
         pcall(vim.api.nvim_win_set_config, state.input_win.win, { title = string.format(" %s %s ", icon, state.ctx.name), title_pos = "center" })
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
  if state.update_timer then pcall(function() state.update_timer:stop() end); pcall(function() state.update_timer:close() end); state.update_timer = nil end
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
  executor.run_transform_async(
    state.ctx.name,
    state.ctx.lib or "pandas",
    state.ctx.is_lazy or false,
    state.current_code,
    function(response)
      if state.ctx and state.preview_win then
          vim.schedule(function() update_preview(response) end)
      end
    end
  )
end

local function debounced_update(code)
  state.current_code = code
  if state.update_timer then state.update_timer:stop(); state.update_timer:close() end
  state.update_timer = vim.loop.new_timer()
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

local function generate_python_stub(ctx)
  local lib, columns = ctx.lib or "pandas", ctx.columns or {}
  local lines = {}
  local is_lazy = ctx.is_lazy or false
  if lib == "pandas" then
    table.insert(lines, "import pandas as pd; import numpy as np")
    table.insert(lines, "class VirtualDF(pd.DataFrame):")
    if #columns > 0 then for _, col in ipairs(columns) do if col:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then table.insert(lines, string.format("    %s: pd.Series", col)) end end else table.insert(lines, "    pass") end
    table.insert(lines, "df: VirtualDF = VirtualDF()")
  elseif lib == "polars" then
    table.insert(lines, "import polars as pl; from polars import col, lit, when")
    table.insert(lines, is_lazy and "df: pl.LazyFrame = pl.LazyFrame()" or "df: pl.DataFrame = pl.DataFrame()")
    if #columns > 0 then for _, col in ipairs(columns) do if col:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then table.insert(lines, string.format("%s = pl.col('%s')", col, col)) end end end
  end
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

local function setup_lsp_completion(input_buf, parent_buf, ctx)
  if not vim.api.nvim_buf_is_valid(input_buf) then return end
  vim.b[input_buf].scivim_hide_signature = true
  vim.api.nvim_create_autocmd("LspAttach", { buffer = input_buf, callback = function(args) local client = vim.lsp.get_client_by_id(args.data.client_id); if client then if client.server_capabilities then client.server_capabilities.signatureHelpProvider = nil end; patch_lsp_client(client) end end })
  local start_path = vim.api.nvim_buf_get_name(parent_buf)
  if start_path == "" then start_path = vim.fn.getcwd() end
  local root_markers = { "pyproject.toml", "requirements.txt", ".git", ".venv", "venv" }
  local root_dir = vim.fs.dirname(vim.fs.find(root_markers, { path = start_path, upward = true })[1] or start_path)
  local fake_path = root_dir .. "/__scivim_ghost_" .. os.time() .. ".py"
  state.ghost_path = fake_path
  local stub_content = generate_python_stub(ctx)
  local f = io.open(fake_path, "w"); if f then f:write(stub_content); f:close() end
  vim.api.nvim_buf_set_name(input_buf, fake_path)
  vim.bo[input_buf].buftype = ""; vim.bo[input_buf].filetype = "python"
  vim.api.nvim_buf_set_lines(input_buf, 0, 0, false, vim.split(stub_content, '\n'))
  vim.api.nvim_buf_call(input_buf, function() vim.cmd("silent! write") end)
  vim.schedule(function() if not vim.api.nvim_buf_is_valid(input_buf) then return end; local attached = false; if #vim.lsp.get_clients({ buffer = input_buf }) > 0 then attached = true end; if not attached then for _, client in ipairs(vim.lsp.get_clients()) do if client.name == "pyrefly" then vim.lsp.buf_attach_client(input_buf, client.id); attached = true; break end end end; if not attached and vim.fn.exists(":LspStart") == 2 then vim.cmd("silent! LspStart pyrefly"); vim.defer_fn(function() for _, client in ipairs(vim.lsp.get_clients()) do if client.name == "pyrefly" and vim.api.nvim_buf_is_valid(input_buf) then vim.lsp.buf_attach_client(input_buf, client.id); patch_lsp_client(client); break end end end, 500) end end)
  vim.defer_fn(function() local has_cmp, cmp = pcall(require, "cmp"); if has_cmp then cmp.setup.buffer({ enabled = true, completion = { autocomplete = { cmp.TriggerEvent.TextChanged } }, sources = cmp.config.sources({ { name = "nvim_lsp", priority = 1000 }, { name = "buffer", priority = 500 } }) }) end end, 100)
end

local function open_transform_ui(ctx)
  state.ctx = ctx; state.current_code = ""
  state.parent_win = vim.api.nvim_get_current_win()
  local parent_buf = vim.api.nvim_get_current_buf()
  
  -- Dimensions
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local input_h = 3
  local preview_h = height - input_h

  local icon = get_df_icon(ctx)
  local title_text = string.format(" %s %s ", icon, ctx.name)
  
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
  setup_lsp_completion(input_buf, parent_buf, ctx)
  
  -- Prompt Icon
  local ns_id = vim.api.nvim_create_namespace("scivim_prompt")
  local function set_prompt_extmark() 
      vim.api.nvim_buf_set_extmark(input_buf, ns_id, 0, 0, { virt_text = {{ ICONS.prompt, "ScivimInputPrefix" }}, virt_text_pos = "inline" }) 
  end
  
  local stub_lines = vim.split(generate_python_stub(ctx), '\n')
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
  
  -- Auto-update hook with SQL DETECTION
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, { 
      buffer = input_buf, 
      callback = function() 
          vim.cmd("silent! write")
          set_prompt_extmark()
          local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
          local user_lines = {}
          for i = content_offset, #all_lines do if all_lines[i] then table.insert(user_lines, all_lines[i]) end end
          
          local full_text = table.concat(user_lines, "\n")
          
          -- [[ Dynamic SQL Syntax Switching ]]
          local first_word = full_text:match("^%s*(%w+)")
          if first_word then
              first_word = first_word:upper()
              if first_word == "SELECT" or first_word == "WITH" or first_word == "PRAGMA" or first_word == "DESCRIBE" or first_word == "SHOW" or first_word == "EXPLAIN" then
                  if vim.bo[input_buf].filetype ~= "sql" then vim.bo[input_buf].filetype = "sql" end
              else
                  if vim.bo[input_buf].filetype ~= "python" then vim.bo[input_buf].filetype = "python" end
              end
          end

          debounced_update(full_text) 
      end 
  })
  trigger_request()
  
  -- Close/Accept Logic with VARIABLE REPLACEMENT
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
        if start_token and (start_token:upper() == "SELECT" or start_token:upper() == "WITH" or start_token:upper() == "PRAGMA") then
            is_sql = true
        end

        local full_code = code
        if not is_sql then
            -- Python Substitution
            if code:match("^%s*df%.") then
                full_code = code:gsub("^%s*df", ctx.name, 1)
            elseif code:match("^%s*%.") then
                full_code = ctx.name .. code
            end
        else
            -- [[ NEW: SQL Substitution Logic ]]
            -- Preview uses 'df', but Notebook uses ctx.name (e.g., 'df_sales')
            -- We automatically fix this so user can just type 'FROM df'
            local clean_code = code:gsub("FROM%s+df", "FROM " .. ctx.name)
            clean_code = clean_code:gsub("from%s+df", "FROM " .. ctx.name)
            clean_code = clean_code:gsub("JOIN%s+df", "JOIN " .. ctx.name)

            -- Wrap in duckdb call
            full_code = string.format("import duckdb\n%s_sql = duckdb.sql(\"\"\"%s\"\"\").df()", ctx.name, clean_code)
        end
        vim.api.nvim_put(vim.split(full_code, '\n'), "c", true, true)
    end
  end
  
  vim.keymap.set({"n", "i"}, "<CR>", function() vim.cmd("stopinsert"); accept_and_close() end, { buffer = input_buf })
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, { buffer = input_buf, callback = function() vim.defer_fn(cleanup_state, 100) end, once = true })
end

local function pick_context_ui(ctx_list)
  local lines = {}; for _, ctx in ipairs(ctx_list) do local icon = get_df_icon(ctx); table.insert(lines, string.format(" %s %s ", icon, ctx.name)) end
  local width = 40; local height = math.min(#lines, 10); local row = math.floor((vim.o.lines - height) / 2); local col = math.floor((vim.o.columns - width) / 2)
  local win = Snacks.win({ relative = "editor", row = row, col = col, width = width, height = height, border = "rounded", title = " Select Dataframe ", title_pos = "center", wo = { winhighlight = "FloatBorder:ScivimBorder,Title:ScivimTitle,Normal:ScivimPrompt,CursorLine:PmenuSel", cursorline = true }, keys = { ["q"] = "close", ["<Esc>"] = "close", ["<CR>"] = function(self) local cursor = vim.api.nvim_win_get_cursor(self.win); local idx = cursor[1]; self:close(); vim.schedule(function() if ctx_list[idx] then open_transform_ui(ctx_list[idx]) end end) end } })
  vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines); vim.bo[win.buf].modifiable = false
end

function M.inspect_transform(ctx_arg)
  if ctx_arg then 
    open_transform_ui(ctx_arg) 
  else 
    local all_data = require("scivim.core.context").load_all()
    local ctx_list = {}
    if all_data then for _, v in pairs(all_data) do table.insert(ctx_list, v) end end
    
    if #ctx_list == 0 then 
        vim.notify("No dataframes exposed via vim_expose()", vim.log.levels.WARN) 
    elseif #ctx_list == 1 then 
        open_transform_ui(ctx_list[1]) 
    else 
        pick_context_ui(ctx_list) 
    end 
  end
end

return M
