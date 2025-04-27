# YAML Jumper

A Neovim plugin for quickly navigating YAML files using dot-notation paths.

## Features

- Jump to YAML paths using dot notation (e.g., `metadata.name`)
- Incremental search functionality (type the beginning of a key to jump to it)
- Highlights both the target line and the specific keys in the path
- Displays current search path in a mini floating window

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "DmarshalTU/yaml-jumper",
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
  config = function()
    require("yaml-jumper").setup()
  end
}
```

## Usage

1. In a YAML file, press `<leader>yj` to activate YAML Jumper
2. Type a key name to jump to it (e.g., `m` will jump to the first key starting with "m")
3. Use dot notation to navigate nested structures (e.g., `metadata.name`)
4. Press Enter to confirm or Escape to cancel

## Configuration

You can customize the keybinding by passing options to the setup function:

```lua
require("yaml-jumper").setup({
  keymap = "<leader>y", -- Change the default keybinding
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

You can type:
- `m` to jump to `metadata`
- `s` to jump to `spec`
- `metadata.name` to jump to the `name` field under `metadata`
- `spec.selector.matchLabels` to jump to the `matchLabels` field

## License

MIT