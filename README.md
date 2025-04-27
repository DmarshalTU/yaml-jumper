# YAML Jumper

A Neovim plugin for quickly navigating YAML files using Telescope.

## Features

- Jump to YAML paths using fuzzy search (e.g., `metadata.name`)
- Jump to YAML keys directly
- Search for specific values in your YAML files
- Preview the content and context of each match
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

The plugin provides three main commands:

1. Jump to a YAML path (dot notation):
   - Press `<leader>yj` to open the Telescope path finder
   - Type any part of a path to find it (e.g., `metadata.name`)
   - Preview the content at that path in the preview window
   - Press Enter to jump to the selected path

2. Jump to a YAML key:
   - Press `<leader>yk` to open the Telescope key finder
   - Type any part of a key to find it (e.g., `image`)
   - Preview the content at that key in the preview window
   - Press Enter to jump to the selected key

3. Search for YAML values:
   - Press `<leader>yv` to open the Telescope value finder
   - Type any part of a value to find it (e.g., `nginx`)
   - See the full path and value in the results
   - Preview shows the context around that value
   - Press Enter to jump to the selected value

## Configuration

You can customize the keybindings by passing options to the setup function:

```lua
require("yaml-jumper").setup({
  path_keymap = "<leader>yj",  -- Change the path jump keybinding
  key_keymap = "<leader>yk",   -- Change the key jump keybinding
  value_keymap = "<leader>yv"  -- Change the value search keybinding
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