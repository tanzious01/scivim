-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui/layout.lua
-- /home/tanzious/scivim/lua/scivim/ui
-- /home/tanzious/scivim/lua/scivim/ui

--This file is in  lua/scivim/ui/layout.lua

local M = {}

function M.toggle_scientific_mode()
  -- Get current buffer ID
  local main_buf = vim.api.nvim_get_current_buf()
  
  -- 1. Create a Vertical Split
  vim.cmd("vsplit")
  
  -- 2. Move to the new right-hand window
  local win_output = vim.api.nvim_get_current_win()
  
  -- 3. Create a scratch buffer for the output
  local out_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win_output, out_buf)
  
  -- 4. Configure the Output Window (No numbers, no signs)
  vim.wo[win_output].number = false
  vim.wo[win_output].relativenumber = false
  vim.wo[win_output].signcolumn = "no"
  vim.api.nvim_buf_set_name(out_buf, "Scientific Output")

  -- 5. Resize: Give code 60%, output 40%
  vim.cmd("vertical resize 60")
  
  -- 6. Go back to the code window
  vim.cmd("wincmd h")
  
  -- 7. (Crucial) Tell Molten/Image.nvim to target the other buffer?
  -- Molten renders virtual text inline by default. 
  -- To emulate PyCharm, you might want to map a key that sends 
  -- the output to the side buffer using `MoltenEvaluateVisual` 
  -- but capturing the output is tricky in Lua without patching Molten.
  
  print("Scientific Mode Enabled")
end

return M
