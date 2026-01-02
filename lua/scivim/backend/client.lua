-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- /home/tanzious/scivim/lua/scivim/backend/client.lua
-- =========================================================================
-- CLIENT - Persistent Python Daemon Client
-- =========================================================================
local M = {}

local paths = require("scivim.backend.paths")

local daemon_state = {
  job_id = nil,
  stdout_buffer = "",
  callback_queue = {}, -- FIFO queue for pending requests
}

local function get_script_path()
   return paths.get_daemon_script()
end

--- Restart or Start the Python Daemon
function M.ensure_daemon()
  if daemon_state.job_id and vim.fn.jobwait({daemon_state.job_id}, 0)[1] == -1 then
    return -- Already running
  end

  local script_path = get_script_path()
  local python_cmd = vim.g.python3_host_prog or "python3"

  daemon_state.stdout_buffer = ""
  daemon_state.callback_queue = {}

  daemon_state.job_id = vim.fn.jobstart({python_cmd, script_path}, {
    on_stdout = function(_, data, _)
      if not data then return end
      
      -- 1. Append new data to buffer
      for i, chunk in ipairs(data) do
        daemon_state.stdout_buffer = daemon_state.stdout_buffer .. chunk
        if i < #data then
          daemon_state.stdout_buffer = daemon_state.stdout_buffer .. "\n"
        end
      end

      -- 2. Process complete lines (JSON objects)
      while true do
        local line_end = string.find(daemon_state.stdout_buffer, "\n")
        if not line_end then break end

        local line = string.sub(daemon_state.stdout_buffer, 1, line_end - 1)
        daemon_state.stdout_buffer = string.sub(daemon_state.stdout_buffer, line_end + 1)

        if line ~= "" then
          local callback = table.remove(daemon_state.callback_queue, 1)
          if callback then
            local ok, parsed = pcall(vim.json.decode, line)
            local result = ok and parsed or { error = "JSON Parse Fail: " .. line }
            
            vim.schedule(function()
              callback(result)
            end)
          end
        end
      end
    end,

    on_stderr = function(_, data, _)
      -- Optional: Log stderr for debugging daemon crashes
    end,

    on_exit = function(_, code, _)
      daemon_state.job_id = nil
      -- Flush queue with errors so UI doesn't hang forever
      for _, cb in ipairs(daemon_state.callback_queue) do
        cb({ error = "Daemon process crashed or exited (Code: " .. code .. ")" })
      end
      daemon_state.callback_queue = {}
    end,
    
    detach = false, 
  })
end

--- Send a request to the persistent daemon
function M.run_transform_async(df_name, lib, is_lazy, code, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." })
    return -1
  end

  local temp_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  local file_path = ""

  -- Only resolve specific file path if a specific DF is requested
  if df_name and df_name ~= "" then
      local feather_path = temp_dir .. "/" .. df_name .. ".feather"
      local pkl_path = temp_dir .. "/" .. df_name .. ".pkl"

      file_path = pkl_path
      if vim.fn.filereadable(feather_path) == 1 then
          file_path = feather_path
      end
  end

  local input_data = {
    type = "transform",
    file_path = file_path,
    cache_dir = temp_dir, -- [[ NEW: Explicit Cache Dir for Workspace Loading ]]
    lib = lib,
    is_lazy = is_lazy,
    code = code
  }

  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
  return daemon_state.job_id
end

-- [[ NEW: RPC for Preview Generation ]]
function M.generate_preview(code, out_path, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  
  local input_data = {
    type = "preview",
    code = code,
    out_path = out_path,
    cache_dir = cache_dir
  }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

function M.get_all_metadata(names, callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  
  local input_data = {
    type = "metadata_all",
    cache_dir = cache_dir,
    names = names
  }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

function M.analyze_relationships(callback)
  M.ensure_daemon()
  if not daemon_state.job_id or daemon_state.job_id <= 0 then
    callback({ error = "Failed to start Python daemon." }); return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/scivim_data"
  local input_data = { type = "analyze_relationships", cache_dir = cache_dir }
  
  local ok, json_str = pcall(vim.json.encode, input_data)
  if not ok then callback({ error = "JSON Encode Failed" }); return end
  table.insert(daemon_state.callback_queue, callback)
  vim.fn.chansend(daemon_state.job_id, json_str .. "\n")
end

function M.stop_daemon()
  if daemon_state.job_id then
    vim.fn.jobstop(daemon_state.job_id)
    daemon_state.job_id = nil
  end
end

return M
