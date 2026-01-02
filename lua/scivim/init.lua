-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- /home/tanzious/scivim/lua/scivim/init.lua
-- This file is in /lua/scivim/init.lua
-- =========================================================================
-- SCIVIM - Scientific Visualization for Neovim
-- =========================================================================
local M = {}

-- Lazy load submodules with NEW PATHS
local modules = {
  config    = "scivim.config",
  -- Core Logic
  charts    = "scivim.core.charts",
  context   = "scivim.core.context",
  generator = "scivim.core.generator",
  snippets  = "scivim.core.snippets",
  stats     = "scivim.core.stats",
  -- UI Components
  wizard    = "scivim.ui.wizard",
  preview   = "scivim.ui.preview",
  transform = "scivim.ui.transform",
  explorer  = "scivim.ui.explorer", 
}

-- Auto-loader for submodules
setmetatable(M, {
  __index = function(t, key)
    if modules[key] then
      local ok, mod = pcall(require, modules[key])
      if ok then
        rawset(t, key, mod)
        return mod
      end
    end
    return nil
  end
})

-- -------------------------------------------------------------------------
-- PUBLIC API
-- -------------------------------------------------------------------------

--- Install the IPython startup script (Robust Version)
function M.install_ipython()
  local paths = require("scivim.backend.paths")
  local source = paths.get_python_root() .. "expose.py"
  
  -- 1. Determine IPython Startup Directory
  local ipython_dir = vim.fn.expand("~/.ipython/profile_default/startup/")
  if vim.fn.has("win32") == 1 then
      ipython_dir = vim.fn.expand("$USERPROFILE/.ipython/profile_default/startup/")
  end

  if vim.fn.isdirectory(ipython_dir) == 0 then
      vim.fn.mkdir(ipython_dir, "p")
  end

  local target = ipython_dir .. "99_scivim_expose.py"

  -- 2. Check Source
  if vim.fn.filereadable(source) == 0 then
      vim.notify("❌ Could not find source file: " .. source, vim.log.levels.ERROR)
      return
  end

  -- 3. Install Strategy: Symlink -> WinSymlink -> Hard Copy
  local success = false
  
  -- Attempt Unix Symlink
  if vim.fn.has("unix") == 1 then
      local cmd = string.format("ln -sf '%s' '%s'", source, target)
      if vim.fn.system(cmd) == 0 then success = true end
  end

  -- Attempt Windows Symlink (Requires Admin/Dev Mode)
  if not success and vim.fn.has("win32") == 1 then
      local cmd = string.format("cmd /c mklink \"%s\" \"%s\"", target, source)
      local output = vim.fn.system(cmd)
      -- Check for success message or lack of error
      if output and not output:lower():match("privilege") then success = true end
  end

  -- Fallback: Hard Copy
  if not success then
      local content = vim.fn.readfile(source)
      vim.fn.writefile(content, target)
      vim.notify("⚠️  Symlink failed (Permissions?). Created a HARD COPY instead.\nNote: You must reinstall if you update the plugin.", vim.log.levels.WARN)
  else
      vim.notify("✅ SciVim hooked into IPython successfully!\nLocation: " .. target, vim.log.levels.INFO)
  end
end

--- Start the interactive visualization wizard
function M.start(ctx)
  M.wizard.start(ctx) 
end

--- Quick start with a specific chart type
function M.quick(chart_id)
  M.wizard.quick_start(chart_id)
end

--- Start from a preset template
function M.template(template_name)
  M.wizard.start_from_template(template_name)
end

--- Inspect available data columns
function M.inspect()
  require("scivim.ui.inspector").show()
end

--- User command to launch the live transformation UI
function M.run_transform()
  M.transform.inspect_transform()
end

--- Reload context from Python
function M.reload()
  M.context.reload()
  vim.notify("📊 Context reloaded", vim.log.levels.INFO)
end

--- Save current visualization as a snippet
function M.save_snippet(name)
  M.snippets.save(name)
end

--- Load a saved snippet
function M.load_snippet()
  M.snippets.load()
end

--- Show snippet library
function M.snippets_list()
  M.snippets.list()
end

--- Preview the current specification
function M.show_preview()
  M.preview.show_preview()
end

--- Setup plugin with user configuration
function M.setup(user_config)
  M.config.setup(user_config)
  
  -- Create commands
  vim.api.nvim_create_user_command("VizStart", function() M.start() end, {})
  
  vim.api.nvim_create_user_command("VizQuick", function(opts)
    M.quick(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizTemplate", function(opts)
    M.template(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizExplorer", function()
    require("scivim.ui.explorer").show_explorer()
  end, {})
  
  vim.api.nvim_create_user_command("VizInspect", function() M.inspect() end, {})
  
  vim.api.nvim_create_user_command("VizTransform", function() 
    require("scivim.ui.transform").inspect_transform() 
  end, {})
  
  vim.api.nvim_create_user_command("VizReload", function() M.reload() end, {})
  
  vim.api.nvim_create_user_command("VizSave", function(opts)
    M.save_snippet(opts.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command("VizLoad", function() M.load_snippet() end, {})
  vim.api.nvim_create_user_command("VizSnippets", function() M.snippets_list() end, {})
  vim.api.nvim_create_user_command("VizPreview", function() M.show_preview() end, {})
  
  vim.api.nvim_create_user_command("VizInstall", function() M.install_ipython() end, {})
  
  -- Auto-reload context on file change
  if M.config.get().auto_reload then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = M.config.get().json_filename,
      callback = function() M.reload() end,
    })
  end

  -- [[ CLEANUP ON EXIT ]]
  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      -- OPTIMIZATION: Do NOT delete the data cache on exit.
      -- Preserves data for parallel instances and faster restarts.
      require("scivim.backend.client").stop_daemon()
    end,
  })
  
  vim.notify("🔬 SciVim loaded", vim.log.levels.INFO)
end

return M
