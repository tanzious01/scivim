-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui/preview.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui



--This file is in  lua/scivim/ui/preview.lua
-- =========================================================================
-- PREVIEW - Live Plot Preview (Matplotlib & Plotly support)
-- =========================================================================
local M = {}

local config = require("scivim.config")
local generator = require("scivim.core.generator")

-- Preview state
local preview_state = {
  job_id = nil,
  temp_file = nil,
  image_buf = nil,
}

--- Check if preview is supported
---@return boolean, string
function M.is_supported()
  -- Check for image.nvim
  local has_image = pcall(require, "image")
  if has_image then
    return true, "image.nvim"
  end
  
  -- Check for kitty terminal
  if vim.env.TERM == "xterm-kitty" or vim.env.KITTY_WINDOW_ID then
    return true, "kitty"
  end
  
  -- Check for ueberzug (legacy)
  if vim.fn.executable("ueberzug") == 1 then
    return true, "ueberzug"
  end
  
  return false, "none"
end

--- Generate preview for current visualization spec
---@param spec table|nil Visualization spec (if nil, uses last generated code)
function M.show_preview(spec)
  local supported, backend = M.is_supported()
  
  if not supported then
    vim.notify(
      "Preview not supported. Install image.nvim or use Kitty terminal.",
      vim.log.levels.WARN
    )
    return
  end
  
  -- Get code to preview (Priority: Spec -> Last Generated)
  local code_lines = {}
  
  if spec then
    -- If a spec is passed, we might need to generate it on the fly
    -- Assuming generator has a method to get code without side effects, 
    -- otherwise we rely on the cached last run.
    code_lines = generator.get_code_lines and generator.get_code_lines(spec) or {}
  end

  -- Fallback to last generated code
  if #code_lines == 0 then
    code_lines = generator.get_last_viz_code and generator.get_last_viz_code() or {}
  end

  if #code_lines == 0 then
    vim.notify("No visualization code found to preview.", vim.log.levels.ERROR)
    return
  end
  
  vim.notify("🔄 Generating preview...", vim.log.levels.INFO)
  
  -- Create temp file for output
  preview_state.temp_file = os.tmpname() .. ".png"
  local raw_code = table.concat(code_lines, "\n")
  local final_code = ""

  -- [[ SMART BACKEND DETECTION ]]
  if raw_code:match("plotly") or raw_code:match("px%.") or raw_code:match("go%.") then
      -- === PLOTLY HANDLING ===
      final_code = raw_code:gsub("fig%.show%(%)", "") -- Remove interactive show
      final_code = final_code .. "\n# Export for Neovim Preview"
      final_code = final_code .. "\ntry:"
      final_code = final_code .. "\n    import plotly.io as pio"
      final_code = final_code .. "\n    # Requires: pip install kaleido"
      final_code = final_code .. "\n    pio.write_image(fig, '" .. preview_state.temp_file .. "', engine='kaleido', scale=2)"
      final_code = final_code .. "\nexcept Exception as e:"
      final_code = final_code .. "\n    print(f'Preview Error (Plotly): {e}. Ensure kaleido is installed.')"
      final_code = final_code .. "\n    exit(1)"
  else
      -- === MATPLOTLIB/SEABORN HANDLING (Default) ===
      final_code = raw_code:gsub("plt%.show%(%)", "") -- Remove blocking show
      final_code = final_code .. "\nplt.savefig('" .. preview_state.temp_file .. "', dpi=150, bbox_inches='tight')"
  end
  
  final_code = final_code .. "\nprint('PREVIEW_READY')"
  
  -- Execute Python code
  M._execute_preview(final_code, backend)
end

--- Execute Python code and display image
---@param code string Python code
---@param backend string Display backend
function M._execute_preview(code, backend)
  -- Cancel previous preview job if running
  if preview_state.job_id then
    vim.fn.jobstop(preview_state.job_id)
  end
  
  local output = {}
  
  preview_state.job_id = vim.fn.jobstart({"python3", "-c", code}, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(output, data)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        -- Only log actual errors, filter out common matplotlib warnings if desired
        vim.notify("Preview log: " .. table.concat(data, "\n"), vim.log.levels.INFO)
      end
    end,
    on_exit = function(_, exit_code)
      preview_state.job_id = nil
      
      if exit_code == 0 then
        -- Check if file was created
        if vim.fn.filereadable(preview_state.temp_file) == 1 then
          M._display_image(preview_state.temp_file, backend)
        else
          vim.notify("Preview failed: output file not created. Check Python logs.", vim.log.levels.ERROR)
        end
      else
        vim.notify("Preview process failed with exit code: " .. exit_code, vim.log.levels.ERROR)
      end
    end,
  })
end

--- Display image using appropriate backend
---@param filepath string Path to image
---@param backend string Display backend
function M._display_image(filepath, backend)
  if backend == "image.nvim" then
    M._display_image_nvim(filepath)
  elseif backend == "kitty" then
    M._display_kitty(filepath)
  elseif backend == "ueberzug" then
    M._display_ueberzug(filepath)
  end
end

--- Display using image.nvim
function M._display_image_nvim(filepath)
  local image = require("image")
  
  -- Calculate dimensions
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  
  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
  })
  
  preview_state.image_buf = buf
  
  -- Render image
  local img = image.from_file(filepath, {
    window = win,
    buffer = buf,
    -- Fit image to window
    width = width,
    height = height,
  })
  
  if img then
    img:render()
  end
  
  -- Close handlers
  local function close()
    M.close_preview()
  end
  
  vim.keymap.set('n', 'q', close, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, noremap = true, silent = true })
  
  vim.notify("✅ Preview ready (press 'q' to close)", vim.log.levels.INFO)
end

--- Display using Kitty graphics protocol
function M._display_kitty(filepath)
  -- Use kitty icat to display image
  local cmd = string.format("kitty +kitten icat --align left --hold '%s'", filepath)
  -- Note: 'hold' keeps it open, might need adjustment depending on workflow
  vim.fn.jobstart(cmd, { detach = true })
  
  vim.notify("✅ Preview displayed in terminal", vim.log.levels.INFO)
end

--- Display using ueberzug (legacy)
function M._display_ueberzug(filepath)
  vim.notify("Ueberzug preview not fully implemented yet.", vim.log.levels.WARN)
end

--- Close preview window
function M.close_preview()
  if preview_state.image_buf and vim.api.nvim_buf_is_valid(preview_state.image_buf) then
    local wins = vim.fn.win_findbuf(preview_state.image_buf)
    for _, win in ipairs(wins) do
      vim.api.nvim_win_close(win, true)
    end
    vim.api.nvim_buf_delete(preview_state.image_buf, { force = true })
  end
  
  -- Clean up temp file
  if preview_state.temp_file and vim.fn.filereadable(preview_state.temp_file) == 1 then
    os.remove(preview_state.temp_file)
  end
  
  preview_state.image_buf = nil
  preview_state.temp_file = nil
end

return M
