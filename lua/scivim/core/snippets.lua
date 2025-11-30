-- =========================================================================
-- SNIPPETS - Save and Load Visualization Snippets (Snacks Edition)
-- =========================================================================
local M = {}

-- UPDATED IMPORTS:
local config = require("scivim.config")
local generator = require("scivim.core.generator")
local Snacks = require("snacks")

--- Get snippets file path
local function get_snippets_file()
  local cfg = config.get()
  return cfg.snippets_dir .. "/snippets.json"
end

--- Load all snippets from disk
local function load_snippets()
  local file = get_snippets_file()
  local ok, content = pcall(vim.fn.readfile, file)
  if not ok then return {} end
  
  local json_str = table.concat(content, "\n")
  local parse_ok, data = pcall(vim.json.decode, json_str)
  return parse_ok and data or {}
end

--- Save snippets to disk
local function save_snippets(snippets)
  local file = get_snippets_file()
  local json_str = vim.json.encode(snippets)
  vim.fn.writefile(vim.split(json_str, "\n"), file)
end

--- Save current visualization as a snippet
function M.save(name)
  if not name or name == "" then
    vim.notify("Snippet name cannot be empty", vim.log.levels.ERROR)
    return
  end
  
  local lines = generator.get_last_viz_code and generator.get_last_viz_code() or {}
  -- Note: You might need to expose get_last_viz_code in generator.lua if strictly hidden,
  -- or rely on the buffer content if the generator isn't caching it.
  
  -- Fallback: If generator doesn't cache, we can't save easily without grabbing buffer lines.
  -- Assuming generator has this method (it was in your original snippets.lua)
  
  if #lines == 0 then
    vim.notify("No visualization code found (Generator state empty)", vim.log.levels.WARN)
    return
  end
  
  local snippets = load_snippets()
  snippets[name] = {
    code = lines,
    created = os.time(),
    description = lines[1] or "",
  }
  
  save_snippets(snippets)
  vim.notify(config.icon("save") .. " Saved snippet: " .. name, vim.log.levels.INFO)
end

--- Load a snippet (Simple UI)
function M.load()
  M.list() -- Re-use the list UI for loading
end

--- List all snippets (Snacks Picker)
function M.list()
  local snippets = load_snippets()
  
  if vim.tbl_isempty(snippets) then
    vim.notify("No saved snippets found", vim.log.levels.WARN)
    return
  end

  local items = {}
  for name, snip in pairs(snippets) do
    table.insert(items, {
      text = name,
      snippet = snip,
      created = os.date("%Y-%m-%d", snip.created)
    })
  end

  Snacks.picker.pick({
    items = items,
    title = "📚 Visualization Snippets",
    layout = "vscode",
    
    format = function(item)
      return {
        { "🔖 ", "SnacksIcon" },
        { item.text, "Normal" },
        { "  " },
        { item.created, "Comment" }
      }
    end,
    
    preview = function(ctx)
      local code = ctx.item.snippet.code
      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, code)
      vim.bo[ctx.buf].modifiable = false
      vim.bo[ctx.buf].filetype = "python"
    end,
    
    confirm = function(picker, item)
      picker:close()
      local cursor = vim.api.nvim_win_get_cursor(0)
      vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, item.snippet.code)
      vim.notify(config.icon("load") .. " Loaded: " .. item.text, vim.log.levels.INFO)
    end,
    
    win = {
      input = {
        keys = {
          ["<c-d>"] = { "delete_snippet", mode = { "n", "i" } },
        }
      }
    },
    
    actions = {
      delete_snippet = function(picker, item)
        picker:close()
        M.delete(item.text)
        -- Re-open after delete
        vim.schedule(function() M.list() end)
      end
    }
  })
end

--- Delete a snippet
function M.delete(name)
  local snippets = load_snippets()
  if not snippets[name] then return end
  
  snippets[name] = nil
  save_snippets(snippets)
  vim.notify("🗑️  Deleted snippet: " .. name, vim.log.levels.INFO)
end

return M
