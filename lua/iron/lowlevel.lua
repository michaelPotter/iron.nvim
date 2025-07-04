-- luacheck: globals vim
-- TODO Remove config from this layer
local config = require("iron.config")
local fts = require("iron.fts")
local providers = require("iron.providers")
local format = require("iron.fts.common").format
local view = require("iron.view")

--- @class iron.repl_meta
--- @field ft string filetype of the repl
--- @field job number job id of the repl
--- @field bufnr number buffer id of the repl
--- @field repldef iron.repl_def definition of the repl

--- @class iron.repl_def
--- @field command string[]|function command to be executed
--- @field open string
--- @field close string
--- @field format fun(lines: string[]): string[] function to format the input

--- Low level functions for iron
-- This is needed to reduce the complexity of the user API functions.
-- There are a few rules to the functions in this document:
--    * They should not interact with each other
--        * An exception for this is @{lowlevel.get_repl_def} during the transition to v3
--    * They should do one small thing only
--    * They should not care about setting/cleaning up state (i.e. moving back to another window)
--    * They must be explicit in their documentation about the state changes they cause.
-- @module lowlevel
-- @alias ll
local ll = {}

ll.store = {}

-- Quick fix for changing repl_open_cmd
ll.tmp = {}

-- TODO This should not be part of lowlevel
ll.get = function(ft)
  if ft == nil or ft == "" then
    error("Empty filetype")
  end
  return config.scope.get(ll.store, ft)
end

-- TODO this should not be part of lowlevel
ll.set = function(ft, fn)
  return config.scope.set(ll.store, ft, fn)
end

ll.get_buffer_ft = function(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == nil or ft == "" then
    error("Empty filetype")
  elseif fts[ft] == nil and config.repl_definition[ft] == nil then
    error("There's no REPL definition for current filetype "..ft)
  end
  return ft
end

--- Creates the repl in the current window
--- This function effectively creates the repl without caring
--- about window management. It is expected that the client
--- ensures the right window is created and active before calling this function.
--- If @{\\config.close_window_on_exit} is set to true, it will plug a callback
--- to the repl so the window will automatically close when the process finishes
--- @param ft string of the current repl
--- @param repl iron.repl_def definition of the repl being created
--- @param repl.command table with the command to be invoked.
--- @param bufnr number to be used
--- @param current_bufnr number buffer
--- @param opts Options passed through to the terminal
--- @warning changes current window's buffer to bufnr
--- @return iron.repl_meta meta unsaved metadata about created repl
ll.create_repl_on_current_window = function(ft, repl, bufnr, current_bufnr, opts)
  vim.api.nvim_win_set_buf(0, bufnr)
  -- TODO Move this out of this function
  -- Checking config should be done on an upper layer.
  -- This layer should be simpler
  opts = opts or {}
  if config.close_window_on_exit then
    opts.on_exit = function()
      local bufwinid = vim.fn.bufwinid(bufnr)
      while bufwinid ~= -1 do
        vim.api.nvim_win_close(bufwinid, true)
        bufwinid = vim.fn.bufwinid(bufnr)
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  else
    opts.on_exit = function() end
  end

  local cmd = repl.command
  if type(repl.command) == 'function' then
    local meta = {
      current_bufnr = current_bufnr,
    }
    cmd = repl.command(meta)
  end
  local job_id = vim.fn.termopen(cmd, opts)

  return {
    ft = ft,
    bufnr = bufnr,
    job = job_id,
    repldef = repl
  }
end

--- Wrapper function for getting repl definition from config
--- This allows for an easier transition between old and new methods
--- @param ft string filetype of the desired repl
--- @return iron.repl_def repl_def repl definition
ll.get_repl_def = function(ft)
  -- TODO should not call providers directly, but from config
  return config.repl_definition[ft] or providers.first_matching_binary(ft)
end

--- Creates a new window for placing a repl.
--- Expected to be called before creating the repl.
--- It knows nothing about the repl and only takes in account the
--- configuration.
--- @warning might change the current window
--- @param bufnr number to be used
--- @param repl_open_cmd command to be used to open the repl. if nil than will use config.repl_open_cmd
--- @return number winnr window id of the newly created window
ll.new_window = function(bufnr, repl_open_cmd)
  if repl_open_cmd == nil then
    repl_open_cmd = ll.tmp.repl_open_cmd
  end

  if type(repl_open_cmd) == "function" then
    local result = repl_open_cmd(bufnr)
    if type(result) == "table" then
      return view.openfloat(result, bufnr)
    else
      return result
    end
  else
    vim.cmd(repl_open_cmd)
    vim.api.nvim_set_current_buf(bufnr)
    return vim.fn.bufwinid(bufnr)
  end
end

--- Creates a new buffer to be used by the repl
--- @return number bufnr the buffer id
ll.new_buffer = function()
  return vim.api.nvim_create_buf(config.buflisted, config.scratch_repl)
end

--- Wraps the condition checking of whether a repl exists
--- created for convenience
--- @param meta iron.repl_meta metadata for repl. Can be nil.
--- @return boolean repl_exists whether the repl exists
ll.repl_exists = function(meta)
  return meta ~= nil and vim.api.nvim_buf_is_loaded(meta.bufnr)
end

--- Sends data to an existing repl of given filetype
--- The content supplied is ensured to be a table of lines,
--- being coerced if supplied as a string.
--- As a side-effect of pasting the contents to the repl,
--- it changes the scroll position of that window.
--- Does not affect currently active window and its cursor position.
--- @param meta iron.repl_meta metadata for repl. Should not be nil
-- @param ft string name of the filetype
--- @param data string|string[] A multiline string or a table containing lines to be sent to the repl
--- @warning changes cursor position if window is visible
ll.send_to_repl = function(meta, data)
  local dt = data

  if type(data) == "string" then
    dt = vim.split(data, '\n')
  end

  dt = format(meta.repldef, dt)

  local window = vim.fn.bufwinid(meta.bufnr)
  if window ~= -1 then
    vim.api.nvim_win_set_cursor(window, {vim.api.nvim_buf_line_count(meta.bufnr), 0})
  end

  --TODO check vim.api.nvim_chan_send
  --TODO tool to get the progress of the chan send function
  vim.fn.chansend(meta.job, dt)

  if window ~= -1 then
    vim.api.nvim_win_set_cursor(window, {vim.api.nvim_buf_line_count(meta.bufnr), 0})
  end
end


--- Reshapes the repl window according to a preset config described in views
--- @param meta iron.repl_meta metadata for the repl
--- @param key string|number either name or index in the table for the preset to be active
ll.set_window_shape = function(meta, key)
  local window = vim.fn.bufwinid(meta.bufnr)
  local preset = config.views[key]
  if preset ~= nil then
    if type(preset) == "function" then
      preset = preset(meta.bufnr)
    end
    vim.api.nvim_win_set_config(window, preset)
  end
end

--- Closes the window
--- @param meta iron.repl_meta metadata for the repl
ll.close_window = function(meta)
  local window = vim.fn.bufwinid(meta.bufnr)
  vim.api.nvim_win_close(window, true)
end

--- Tries to look up the corresponding filetype of a REPL
--- If the corresponding buffer number is a repl,
--- return its filetype otherwise return nil
--- @param bufnr number number of the buffer being checked
--- @return string filetype filetype of the buffer's repl (or nil if it doesn't have a repl associated)
ll.get_repl_ft_for_bufnr = function(bufnr)
  for _, values  in pairs(ll.store) do
    for _, meta in pairs(values) do
      if meta.bufnr == bufnr then
        return meta.ft
      end
    end
  end
end

return ll
