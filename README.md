# iron.nvim

[![Chat on Matrix](https://matrix.to/img/matrix-badge.svg)](https://matrix.to/#/#iron.nvim:matrix.org)

Interactive Repls Over Neovim.

## What is iron.nvim

[![asciicast](https://asciinema.org/a/495376.svg)](https://asciinema.org/a/495376)
Iron allows you to quickly interact with the repl without having to leave your
work buffer

It both a plugin and a library, allowing for better user experience and
extensibility at the same time.

## How to install

Using [packer.nvim](https://github.com/wbthomason/packer.nvim) 
(or the plugin manager of your choice):

```lua
  use {'Vigemus/iron.nvim'}
```

## How to configure

Below is a very simple configuration for iron:

```lua
local iron = require("iron.core")
local view = require("iron.view")
local common = require("iron.fts.common")

iron.setup {
  config = {
    -- Whether a repl should be discarded or not
    scratch_repl = true,
    -- Your repl definitions come here
    repl_definition = {
      sh = {
        -- Can be a table or a function that
        -- returns a table (see below)
        command = {"zsh"}
      },
      python = {
        command = { "python3" },  -- or { "ipython", "--no-autoindent" }
        format = common.bracketed_paste_python,
        block_dividers = { "# %%", "#%%" },
      }
    },
    -- set the file type of the newly created repl to ft
    -- bufnr is the buffer id of the REPL and ft is the filetype of the 
    -- language being used for the REPL. 
    repl_filetype = function(bufnr, ft)
      return ft
      -- or return a string name such as the following
      -- return "iron"
    end,
    -- Send selections to the DAP repl if an nvim-dap session is running.
    dap_integration = true
    -- How the repl window will be displayed
    -- See below for more information
    repl_open_cmd = view.bottom(40),

    -- repl_open_cmd can also be an array-style table so that multiple 
    -- repl_open_commands can be given.
    -- When repl_open_cmd is given as a table, the first command given will
    -- be the command that `IronRepl` initially toggles.
    -- Moreover, when repl_open_cmd is a table, each key will automatically
    -- be available as a keymap (see `keymaps` below) with the names 
    -- toggle_repl_with_cmd_1, ..., toggle_repl_with_cmd_k
    -- For example,
    -- 
    -- repl_open_cmd = {
    --   view.split.vertical.rightbelow("%40"), -- cmd_1: open a repl to the right
    --   view.split.rightbelow("%25")  -- cmd_2: open a repl below
    -- }

  },
  -- Iron doesn't set keymaps by default anymore.
  -- You can set them here or manually add keymaps to the functions in iron.core
  keymaps = {
    toggle_repl = "<space>rr", -- toggles the repl open and closed.
    -- If repl_open_command is a table as above, then the following keymaps are
    -- available
    -- toggle_repl_with_cmd_1 = "<space>rv",
    -- toggle_repl_with_cmd_2 = "<space>rh",
    restart_repl = "<space>rR", -- calls `IronRestart` to restart the repl
    send_motion = "<space>sc",
    visual_send = "<space>sc",
    send_file = "<space>sf",
    send_line = "<space>sl",
    send_paragraph = "<space>sp",
    send_until_cursor = "<space>su",
    send_mark = "<space>sm",
    send_code_block = "<space>sb",
    send_code_block_and_move = "<space>sn",
    mark_motion = "<space>mc",
    mark_visual = "<space>mc",
    remove_mark = "<space>md",
    cr = "<space>s<cr>",
    interrupt = "<space>s<space>",
    exit = "<space>sq",
    clear = "<space>cl",
  },
  -- If the highlight is on, you can change how it looks
  -- For the available options, check nvim_set_hl
  highlight = {
    italic = true
  },
  ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
}

-- iron also has a list of commands, see :h iron-commands for all available commands
vim.keymap.set('n', '<space>rf', '<cmd>IronFocus<cr>')
vim.keymap.set('n', '<space>rh', '<cmd>IronHide<cr>')
```

The repl `command` can also be a function:

```lua
iron.setup{
  config = {
    repl_definition = {
      -- custom repl that loads the current file
      haskell = {
        command = function(meta)
          local filename = vim.api.nvim_buf_get_name(meta.current_bufnr)
          return { 'cabal', 'v2-repl', filename}
        end
      }
    },
  },
}
```

### REPL windows

iron.nvim supports both splits and floating windows and has helper functions
for opening new repls in either of them:

#### For splits

If you prefer using splits to your repls, iron provides a few utility functions
to make it simpler:

```lua
local view = require("iron.view")

-- iron.setup {...

-- One can always use the default commands from vim directly
repl_open_cmd = "vertical botright 80 split"

-- But iron provides some utility functions to allow you to declare that dynamically,
-- based on editor size or custom logic, for example.

-- Vertical 50 columns split
-- Split has a metatable that allows you to set up the arguments in a "fluent" API
-- you can write as you would write a vim command.
-- It accepts:
--   - vertical
--   - leftabove/aboveleft
--   - rightbelow/belowright
--   - topleft
--   - botright
-- They'll return a metatable that allows you to set up the next argument
-- or call it with a size parameter
repl_open_cmd = view.split.vertical.botright(50)

-- If the supplied number is a fraction between 1 and 0,
-- it will be used as a proportion
repl_open_cmd = view.split.vertical.botright(0.61903398875)

-- The size parameter can be a number, a string or a function.
-- When it's a *number*, it will be the size in rows/columns
-- If it's a *string*, it requires a "%" sign at the end and is calculated
-- as a percentage of the editor size
-- If it's a *function*, it should return a number for the size of rows/columns

repl_open_cmd = view.split("40%")

-- You can supply custom logic
-- to determine the size of your
-- repl's window
repl_open_cmd = view.split.topleft(function()
  if some_check then
    return vim.o.lines * 0.4
  end
  return 20
end)

-- An optional set of options can be given to the split function if one
-- wants to configure the window behavior.
-- Note that, by default `winfixwidth` and `winfixheight` are set
-- to `true`. If you want to overwrite those values,
-- you need to specify the keys in the option map as the example below

repl_open_cmd = view.split("40%", {
  winfixwidth = false,
  winfixheight = false,
  -- any window-local configuration can be used here
  number = true
})
```

#### For floats

If you prefer floats, the API is the following:

```lua
local view = require("iron.view")

-- iron.setup {...

-- The same size arguments are valid for float functions
repl_open_cmd = view.top("10%")

-- `view.center` takes either one or two arguments
repl_open_cmd = view.center("30%", 20)

-- If you supply only one, it will be used for both dimensions
-- The function takes an argument to whether the orientation is vertical(true) or
-- horizontal (false)
repl_open_cmd = view.center(function(vertical)
-- Useless function, but it will be called twice,
-- once for each dimension (width, height)
  if vertical then
    return 50
  end
  return 20
end)

-- `view.offset` allows you to control both the size of each dimension and
-- the distance of them from the top-left corner of the screen
repl_open_cmd = view.offset{
  width = 60,
  height = vim.o.height * 0.75
  w_offset = 0,
  h_offset = "5%"
}

-- Some helper functions allow you to calculate the offset
-- in relation to the size of the window.
-- While all other sizing functions take only the orientation boolean (vertical or not),
-- for offsets, the functions will also take the repl size in that dimension
-- as argument. The helper functions then return a function that takes two arguments
-- to calculate the offset
repl_open_cmd = view.offset{
  width = 60,
  height = vim.o.height * 0.75
  -- `view.helpers.flip` will subtract the size of the REPL
  -- window from the total dimension, then apply an offset.
  -- Effectively, it flips the top/left to bottom/right orientation
  w_offset = view.helpers.flip(2),
  -- `view.helpers.proportion` allows you to apply a relative
  -- offset considering the REPL window size.
  -- for example, 0.5 will centralize the REPL in that dimension,
  -- 0 will pin it to the top/left and 1 will pin it to the bottom/right.
  h_offset = view.helpers.proportion(0.5)
}

-- Differently from `view.center`, all arguments are required
-- and no defaults will be applied if something is missing.
repl_open_cmd = view.offset{
  width = 60,
  height = vim.o.height * 0.75
  -- Since we know we're using this function in the width offset
  -- calculation, we can ignore the argument
  w_offset = function(_, repl_size)
    -- Ideally this function calculates a value based on something..
    return 42
  end,
  h_offset = view.helpers.flip(2)
}
```
