-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui/explorer.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui
--This file is in  lua/scivim/ui/explorer.lua
local M = {}
local executor = require("scivim.backend.client")
local context = require("scivim.core.context")
local Snacks = require("snacks")

local state = {
  mode = "list", -- 'list' or 'graph'
  dfs = {},
  rels = {},
  win_list = nil,
  win_preview = nil
}

--- Show DataFrame explorer with previews
function M.show_explorer()
  -- 1. Get Source of Truth (Current Session)
  local all_data = context.load_all()
  
  if not all_data or vim.tbl_count(all_data) == 0 then
      vim.notify("No active DataFrames found. Run vim_expose() in your kernel.", vim.log.levels.WARN)
      return
  end
  
  -- 2. Extract Valid Names
  local active_names = vim.tbl_keys(all_data)
  
  -- 3. Fetch Metadata
  executor.get_all_metadata(active_names, function(meta_resp)
    if meta_resp.error then 
        vim.notify("Error: " .. meta_resp.error, vim.log.levels.ERROR)
        return 
    end
    
    -- 4. Fetch Relationships
    executor.analyze_relationships(function(rel_resp)
      -- Process DataFrames
      local df_list = {}
      for name, info in pairs(meta_resp.dataframes or {}) do
        table.insert(df_list, {
          name = name,
          shape = info.shape or {0, 0},
          columns = info.columns or {},
          head = info.head or ""
        })
      end
      
      -- Process Relationships
      local rel_list = rel_resp.relationships or {}

      if #df_list == 0 then 
          vim.notify("No DataFrames found in cache.", vim.log.levels.WARN)
          return 
      end

      -- Init State
      state.dfs = df_list
      state.rels = rel_list
      state.mode = "list"
      
      M._render_ui()
    end)
  end)
end

function M._render_ui()
  -- Calculate Layout
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local list_width = 40
  local preview_width = width - list_width - 2 -- minus borders
  
  -- Prepare Content
  local left_lines = {}
  local title = ""
  local footer = " <Tab> Switch View • <CR> Actions • q Quit "
  local title_hl = "Title"

  if state.mode == "list" then
      title = " 🐼 Active DataFrames "
      title_hl = "String" -- Greenish usually
      for _, df in ipairs(state.dfs) do
        local dim_str = string.format("(%d x %d)", df.shape[1] or 0, df.shape[2] or 0)
        -- Pad spaces for alignment
        local padding = string.rep(" ", list_width - #df.name - #dim_str - 6)
        table.insert(left_lines, string.format(" %s%s%s ", df.name, padding, dim_str))
      end
  else
      title = " 🕸️  Data Relationships "
      title_hl = "Special" -- Blue/Purple usually
      if #state.rels == 0 then
          table.insert(left_lines, "")
          table.insert(left_lines, "  (No obvious joins detected)")
      else
          for _, r in ipairs(state.rels) do
             -- Shorten if too long
             local rel_str = string.format("%s -> %s", r.from_df, r.to_df)
             table.insert(left_lines, " " .. rel_str)
          end
      end
  end

  -- Close existing windows if open (redraw)
  if state.win_list then state.win_list:close(); state.win_preview:close() end

  -- 1. ACTION HANDLER (Press Enter)
  local function open_actions()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list.win)
      local idx = cursor[1]
      
      if state.mode ~= "list" then return end
      
      local df_meta = state.dfs[idx]
      if not df_meta then return end
      
      -- Load Full Context
      local all_data = context.load_all()
      local ctx = all_data[df_meta.name]
      if not ctx then return end

      state.win_list:close()
      state.win_preview:close()

      Snacks.picker.pick({
          items = {
              { text = "📊 Visualize (Wizard)",  action = "viz", icon = "📈" },
              { text = "🛠️  Transform (Python)", action = "py",  icon = "🐍" },
              { text = "🦆 Query (SQL)",        action = "sql", icon = "💾" },
              { text = "🔍 Inspect Columns",    action = "insp", icon = "🔎" },
          },
          title = " Action: " .. ctx.name .. " ",
          layout = "vscode",
          confirm = function(picker, item)
              picker:close()
              if item.action == "viz" then require("scivim.ui.wizard").start(ctx)
              elseif item.action == "py" then require("scivim.ui.transform")._launch_python_transform(ctx)
              elseif item.action == "sql" then require("scivim.ui.sql_transform").launch(ctx)
              elseif item.action == "insp" then require("scivim.ui.inspector")._inspect_snacks(ctx)
              end
          end
      })
  end

  -- 2. CREATE LIST WINDOW
  state.win_list = Snacks.win({
    relative = "editor", row = row, col = col, width = list_width, height = height,
    border = "rounded", 
    title = title, title_pos = "center",
    footer = footer, footer_pos = "center",
    wo = { cursorline = true, winhighlight = "FloatBorder:FloatBorder,Title:"..title_hl },
    keys = {
        ["q"] = "close", ["<Esc>"] = "close",
        ["<Tab>"] = function() 
            state.mode = (state.mode == "list") and "graph" or "list"
            M._render_ui() 
        end,
        ["<CR>"] = open_actions
    }
  })
  vim.api.nvim_buf_set_lines(state.win_list.buf, 0, -1, false, left_lines)
  
  -- 3. CREATE PREVIEW WINDOW
  state.win_preview = Snacks.win({
    relative = "editor", row = row, col = col + list_width + 1, width = preview_width, height = height,
    border = "rounded", title = " Details ", title_pos = "center", interactive = false,
    wo = { winhighlight = "FloatBorder:FloatBorder" }
  })
  
  -- 4. PREVIEW UPDATER LOGIC
  local function update_preview()
    if not vim.api.nvim_win_is_valid(state.win_list.win) then return end
    local cursor = vim.api.nvim_win_get_cursor(state.win_list.win)
    local idx = cursor[1]
    local p_lines = {}
    local p_title = " Details "

    if state.mode == "list" then
        local df = state.dfs[idx]
        if df then
            p_title = string.format(" %s ", df.name)
            
            -- Header
            table.insert(p_lines, string.format("📐 Shape: %d rows x %d cols", df.shape[1], df.shape[2]))
            table.insert(p_lines, string.rep("─", preview_width))
            
            -- Columns formatted nicely
            table.insert(p_lines, "📋 Columns:")
            local col_chunk_size = math.ceil(#df.columns / 2) -- split into 2 cols if needed
            for i, c in ipairs(df.columns) do
                 if i > 20 then 
                    table.insert(p_lines, string.format("  ... (%d more)", #df.columns - 20))
                    break 
                 end
                 table.insert(p_lines, string.format("  • %s", c))
            end
            
            table.insert(p_lines, "")
            table.insert(p_lines, string.rep("─", preview_width))
            table.insert(p_lines, "👓 Head:")
            
            -- Add Head content (handling raw string from pandas to_string)
            for _, l in ipairs(vim.split(df.head, '\n')) do
                table.insert(p_lines, "  " .. l)
            end
        end
    else
        -- Relationship Mode
        local r = state.rels[idx]
        if r then
             p_title = " Relationship Info "
             table.insert(p_lines, "")
             table.insert(p_lines, " 🔗 JOIN SUGGESTION")
             table.insert(p_lines, string.rep("─", 40))
             table.insert(p_lines, string.format(" Left:  %s", r.from_df))
             table.insert(p_lines, string.format(" Right: %s", r.to_df))
             table.insert(p_lines, "")
             table.insert(p_lines, string.format(" Key:   %s == %s", r.from_col, r.to_col))
             table.insert(p_lines, string.format(" Type:  %s", r.type))
             table.insert(p_lines, "")
             table.insert(p_lines, " 📝 SQL Pattern:")
             table.insert(p_lines, " ```sql")
             table.insert(p_lines, string.format(" SELECT * FROM %s a", r.from_df))
             table.insert(p_lines, string.format(" JOIN %s b ON a.%s = b.%s", r.to_df, r.from_col, r.to_col))
             table.insert(p_lines, " ```")
        else
             table.insert(p_lines, " No relationship selected.")
        end
    end
    
    -- Highlight SQL/Code in preview
    if state.mode == "graph" then vim.bo[state.win_preview.buf].filetype = "markdown" 
    else vim.bo[state.win_preview.buf].filetype = "text" end

    vim.api.nvim_buf_set_lines(state.win_preview.buf, 0, -1, false, p_lines)
    pcall(vim.api.nvim_win_set_config, state.win_preview.win, { title = p_title })
  end

  -- Navigation Binds
  local buf = state.win_list.buf
  vim.keymap.set('n', 'j', function() vim.cmd('normal! j'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', 'k', function() vim.cmd('normal! k'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', '<Down>', function() vim.cmd('normal! j'); update_preview() end, { buffer = buf })
  vim.keymap.set('n', '<Up>', function() vim.cmd('normal! k'); update_preview() end, { buffer = buf })
  
  -- Initial Render
  update_preview()
end

return M
