# pam.nvim

> The package manager for Neovim

## Features

- Install, upgrade, list, and clean packages
- Support for URLs and local paths
- No unnecessary abstractions

## Getting started

Clone pam.nvim:

```sh
git clone https://github.com/mvllow/pam.nvim \
  ~/.local/share/nvim/site/pack/pam/start/pam.nvim
```

Add packages to manage:

```lua
require("pam").manage({
    { source = "mvllow/pam.nvim" },
    {
        source = "nvim-treesitter/nvim-treesitter",
        post_checkout = function()
            vim.cmd("TSUpdate")
        end,
        config = function()
            require("nvim-treesitter.configs").setup()
        end
    },
    {
        source = "ThePrimeagen/harpoon",
        branch = "harpoon2",
        dependencies = {
            { source = "nvim-lua/plenary.nvim" }
        }
    }
})
```

Install, upgrade, list, or clean packages via the builtin commands:

```vimscript
:Pam <command>
```

Please see [doc/pam.txt](doc/pam.txt) or `:help pam` for more information.

## Contributing

There are plenty of package managers out there, but none are named pam. Although that last part was irrelevant, we want to keep pam small. Pull requests are welcome and appreciated, however it may be best to create an issue to discuss any changes first.

### Generating documentation

Inside of Neovim, with [mini.doc](https://github.com/echasnovski/mini.doc) in your runtimepath:

```vimscript
:luafile scripts/minidoc.lua
```
