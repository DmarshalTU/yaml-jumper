# YAML Jumper

A Neovim plugin for quickly navigating YAML files using Telescope.

## Features

- Jump to YAML paths using fuzzy search (e.g., `metadata.name`)
- Jump to YAML keys directly
- Uses Telescope UI for smooth interaction and reliable input handling
- Works with any YAML file structure

## Requirements

- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "DmarshalTU/yaml-jumper",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("yaml-jumper").setup()
  end,
  ft = {"yaml", "yml"},
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "DmarshalTU/yaml-jumper",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("yaml-jumper").setup()
  end
}
```

## Usage

The plugin provides two main commands:

1. Jump to a YAML path (dot notation):
   - Press `<leader>yj` to open the Telescope path finder
   - Type any part of a path to find it (e.g., `metadata.name`)
   - Press Enter to jump to the selected path

2. Jump to a YAML key:
   - Press `<leader>yk` to open the Telescope key finder
   - Type any part of a key to find it (e.g., `image`)
   - Press Enter to jump to the selected key

## Configuration

You can customize the keybindings by passing options to the setup function:

```lua
require("yaml-jumper").setup({
  path_keymap = "<leader>yj", -- Change the path jump keybinding
  key_keymap = "<leader>yk"   -- Change the key jump keybinding
})
```

## Example

For the following YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
```

- Press `<leader>yj` and type "meta" to find the `metadata` path  
- Press `<leader>yj` and type "spec.rep" to find the `spec.replicas` path
- Press `<leader>yk` and type "name" to find the `name` key

## License

MIT