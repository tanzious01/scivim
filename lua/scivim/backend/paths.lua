-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend/paths.lua
-- /home/tanzious/scivim/lua/scivim/backend
-- /home/tanzious/scivim/lua/scivim/backend
-- lua/scivim/backend/paths.lua
local M = {}

function M.get_plugin_root()
  -- Get the path to this file, then go up 4 levels to the root
  local current_file = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(current_file, ":h:h:h:h")
end

-- This was missing!
function M.get_python_root()
  return M.get_plugin_root() .. "/python/scivim/"
end

function M.get_daemon_script()
  return M.get_python_root() .. "daemon.py"
end

return M
