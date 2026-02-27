# yaml-jumper

Fast YAML navigation for Neovim -- supports **fzf-lua**, **telescope**, and **snacks** pickers.

## Features

- Jump to any YAML path, key, or value with fuzzy search
- Project-wide search across all YAML files
- Smart YAML parsing via [lyaml](https://github.com/gvvaughan/lyaml) (optional) with array/nested object support
- Jump history -- quickly return to recent locations
- In-place value editing from the picker
- Intelligent caching with automatic invalidation on save
- Zero mandatory dependencies beyond your chosen picker

## Requirements

One of the following picker plugins:

- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [snacks.nvim](https://github.com/folke/snacks.nvim)

Optional:

- [lyaml](https://github.com/gvvaughan/lyaml) -- enhanced YAML parsing (`luarocks install lyaml`)

## Installation

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
    "https://github.com/DmarshalTU/yaml-jumper",
})
```

Then in your config:

```lua
require("yaml-jumper").setup({
    picker_type = "fzf-lua", -- or "telescope" or "snacks"
})
```

### lazy.nvim

```lua
{
    "DmarshalTU/yaml-jumper",
    config = function()
        require("yaml-jumper").setup({
            picker_type = "fzf-lua",
        })
    end,
    ft = { "yaml", "yml" },
}
```

### mini.deps

```lua
MiniDeps.add({ source = "DmarshalTU/yaml-jumper" })
require("yaml-jumper").setup({ picker_type = "fzf-lua" })
```

## Usage

| Keymap | Command | Description |
|---|---|---|
| `<leader>yp` | `:YamlJump` | Jump to YAML path (current file) |
| `<leader>yk` | `:YamlJumpKey` | Jump to YAML key (current file) |
| `<leader>yv` | `:YamlJumpValue` | Jump to YAML value (current file) |
| `<leader>yJ` | `:YamlJumpProject` | Search YAML paths across project |
| `<leader>yV` | `:YamlJumpValueProject` | Search YAML values across project |
| `<leader>yh` | `:YamlJumpHistory` | Browse jump history |
| | `:YamlJumpClearCache` | Clear the YAML cache |

All keymaps are customizable (see Configuration below). Set any keymap to `false` to disable it.

## Configuration

```lua
require("yaml-jumper").setup({
    -- Picker backend: "fzf-lua", "telescope", or "snacks"
    picker_type = "fzf-lua",

    -- Keymaps (set to false to disable)
    path_keymap = "<leader>yp",
    key_keymap = "<leader>yk",
    value_keymap = "<leader>yv",
    project_path_keymap = "<leader>yJ",
    project_value_keymap = "<leader>yV",
    history_keymap = "<leader>yh",

    -- Performance
    max_file_size = 1024 * 1024, -- Skip files larger than 1MB
    cache_enabled = true,
    cache_ttl = 30,              -- Cache lifetime in seconds

    -- Parser
    use_smart_parser = true,     -- Use lyaml when available
    depth_limit = 10,            -- Max directory scan depth

    -- History
    max_history_items = 20,
})
```

## Example

Given this YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
```

- `<leader>yp` then type `meta` -- jumps to `metadata`
- `<leader>yp` then type `spec.rep` -- jumps to `spec.replicas`
- `<leader>yv` then type `nginx` -- finds values containing "nginx"
- `<leader>yJ` -- searches all YAML files in the project
- Smart parser correctly identifies array items like `containers.1.name`

## Architecture

```
lua/yaml-jumper/
├── init.lua        -- Setup, public API, keymaps, commands
├── config.lua      -- Configuration defaults and merging
├── parser.lua      -- YAML parsing (smart + traditional), file scanning
├── cache.lua       -- TTL-based caching with auto-invalidation
├── utils.lua       -- File I/O, path parsing, shared helpers
├── navigation.lua  -- Single-file jump commands (path, key, value)
├── project.lua     -- Project-wide search commands
├── history.lua     -- Jump history tracking
└── picker.lua      -- Picker backends (fzf-lua, telescope, snacks)
```

## License

MIT
