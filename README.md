# YAML Jumper

A Neovim plugin for quickly navigating YAML files using Telescope.

## Features

- **Navigate YAML paths with Telescope**: Quickly search and jump to any node in your YAML structure
- **Search by value**: Find YAML paths by their values
- **Path preview**: See what's at a selected path before jumping to it
- **Multi-file search**: Search YAML paths and values across all project files
- **Edit YAML values directly from the search interface**
- **Performance optimized with intelligent caching**
- **Smart error handling for large files**
- **History tracking**: Quickly return to your recently used YAML paths and values
- **Smart YAML Parsing**: Properly handles complex YAML structures including arrays and nested objects
- **Performance profiling**: Optional debug mode for optimizing performance

## Requirements

- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or [Snacks.nvim](https://github.com/folke/snacks.nvim)
- [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for multi-file search)
- [lyaml](https://github.com/gvvaughan/lyaml) (optional, for improved YAML parsing)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "DmarshalTU/yaml-jumper",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
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
  requires = { 
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim"
  },
  config = function()
    require("yaml-jumper").setup()
  end
}
```

### Optional Dependencies

For enhanced YAML parsing with proper support for complex structures, you can install the lyaml library:

```bash
luarocks install lyaml
```

## Usage

- **Navigate to YAML path**: Use `<leader>yp` to open a Telescope picker and search for YAML paths
- **Search by value**: Use `<leader>yv` to search for YAML values
- **Multi-file search**: 
  - `<leader>yJ` - Search YAML paths across all project files
  - `<leader>yV` - Search YAML values across all project files
- **Edit values**: Press `<C-e>` on a search result to edit the value
- **Browse history**: Press `<leader>yh` to view and jump to recently used paths and values

## Configuration

```lua
require('yaml-jumper').setup({
    -- Customizing keymaps
    path_keymap = '<leader>yp',        -- Search paths in current file
    value_keymap = '<leader>yv',       -- Search values in current file
    project_path_keymap = '<leader>yJ', -- Search paths across project
    project_value_keymap = '<leader>yV', -- Search values across project
    history_keymap = '<leader>yh',     -- Browse search history
    
    -- Performance settings
    max_file_size = 1024 * 1024,       -- Max file size to process (1MB)
    max_preview_lines = 20,            -- Max lines to show in preview
    depth_limit = 10,                  -- Max directory scan depth
    
    -- Cache settings
    cache_enabled = true,              -- Enable caching for better performance
    cache_ttl = 30,                    -- Cache time-to-live in seconds
    max_history_items = 20,            -- Max number of items to keep in history
    
    -- Parser settings
    use_smart_parser = true,           -- Use the enhanced YAML parser when available
    
    -- Picker settings
    picker_type = "telescope",         -- Choose between "telescope" or "snacks"
    
    -- Debug settings
    debug_performance = false,         -- Enable performance profiling and logging
    
    -- Highlight settings
    highlights = {
        enabled = true,
        path = { bg = '#404040', fg = '#ffffff', bold = true },
        key = { fg = '#ff9900', bg = '#333333', bold = true }
    }
})
```

## Special Commands

- `:YamlJumpPath` - Jump to YAML path in current file
- `:YamlJumpValue` - Search YAML values in current file
- `:YamlJumpProject` - Search YAML paths across project files
- `:YamlJumpValueProject` - Search YAML values across project files
- `:YamlJumpClearCache` - Clear the YAML path and value cache
- `:YamlJumpHistory` - Browse through your recently used paths and values

## Performance Profiling

You can enable performance profiling to identify bottlenecks by setting `debug_performance = true` in your configuration. This will output timing information for various operations to help optimize the plugin for your specific environment.

When enabled, you'll see detailed logs with:
- Parsing times for both smart and traditional parsers
- Cache hit/miss information
- Path extraction and mapping times
- Overall performance metrics

This is particularly useful when working with large YAML files or when experiencing any slowdowns.

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
  template:
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
```

- Press `<leader>yp` and type "meta" to find the `metadata` path
- Press `<leader>yp` and type "spec.rep" to find the `spec.replicas` path
- Press `<leader>yv` and type "nginx" to find values containing "nginx"
- Press `<leader>yJ` to search for paths across all YAML files in your project
- Press `<leader>yV` to search for values across all YAML files in your project
- The smart parser will correctly identify array items like `containers.1.name`

## Performance Notes

The plugin includes several optimizations for handling large YAML files and projects:

- **Smart caching**: Results are cached to improve response time for repeated operations
- **File size limiting**: Very large files (>1MB by default) are detected and warnings are shown
- **Automatic cache invalidation**: Cache is updated when you save files
- **Efficient parsing**: Optimized parsing algorithms for minimal memory usage
- **Smart YAML parsing**: With the lyaml library, complex YAML structures are parsed more accurately
- **Multi-level caching**: Both parsed YAML documents and extracted paths are cached separately for maximum efficiency
- **Performance profiling**: Optional debug mode helps identify and resolve bottlenecks

## License

MIT