local M = {}

-- Default user config
local config = {
  theme = "tundra",
  transparency = false,
  hl_override = {},
  changed_themes = {},
  integrations = {}, -- user-defined integrations only
}

-- Allow user to override defaults
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- If user passed custom integrations, install them
  if opts and opts.integrations then
    for name, hl in pairs(opts.integrations) do
      M.install_integration(name, hl)
    end
  end

  M.load_all_highlights()
end

-- Load theme tables
M.get_theme_tb = function(type)
  local name = config.theme
  local present1, default_theme = pcall(require, "base46-extracted.themes." .. name)
  local present2, user_theme = pcall(require, "themes." .. name)

  if present1 then
    return default_theme[type]
  elseif present2 then
    return user_theme[type]
  else
    error("No such theme: " .. name)
  end
end

M.override_theme = function(default_theme, theme_name)
  local changed_themes = config.changed_themes
  return M.merge_tb(default_theme, changed_themes.all or {}, changed_themes[theme_name] or {})
end

-- Color helpers
local lighten = require("base46-extracted.colors").change_hex_lightness
local mixcolors = require("base46-extracted.colors").mix

-- Convert string color names to actual hex values
M.turn_str_to_color = function(tb)
  local colors = vim.tbl_extend("force", M.get_theme_tb "base_30", M.get_theme_tb "base_16")
  local copy = vim.deepcopy(tb)

  for _, hlgroups in pairs(copy) do
    for opt, val in pairs(hlgroups) do
      local valtype = type(val)

      if opt == "fg" or opt == "bg" or opt == "sp" then
        if valtype == "string" and val:sub(1, 1) ~= "#" and val ~= "none" and val ~= "NONE" then
          hlgroups[opt] = colors[val]
        elseif valtype == "table" then
          hlgroups[opt] = #val == 2 and lighten(colors[val[1]], val[2])
            or mixcolors(colors[val[1]], colors[val[2]], val[3])
        end
      end
    end
  end
  return copy
end

M.merge_tb = function(...)
  return vim.tbl_deep_extend("force", ...)
end

-- Extend highlights with overrides + transparency
M.extend_default_hl = function(highlights, integration_name)
  local polish_hl = M.get_theme_tb "polish_hl"

  if polish_hl and polish_hl[integration_name] then
    highlights = M.merge_tb(highlights, polish_hl[integration_name])
  end

  if config.transparency then
    local glassy = require "base46-extracted.glassy"
    for key, value in pairs(glassy) do
      if highlights[key] then
        highlights[key] = M.merge_tb(highlights[key], value)
      end
    end
  end

  local hl_override = config.hl_override
  local overriden_hl = M.turn_str_to_color(hl_override)

  for key, value in pairs(overriden_hl) do
    if highlights[key] then
      highlights[key] = M.merge_tb(highlights[key], value)
    end
  end

  return highlights
end

-- Apply highlights directly
M.apply_highlights = function(hl_table)
  local colored = M.turn_str_to_color(hl_table)
  for group, opts in pairs(colored) do
    print("Applying HL:", group, vim.inspect(opts))
    vim.api.nvim_set_hl(0, group, opts)
  end
end

-- Install a new integration (user-defined)
M.install_integration = function(name, highlights)
  local extended = M.extend_default_hl(highlights, name)
  config.integrations[name] = extended
  M.apply_highlights(extended)
  vim.notify("Integration '" .. name .. "' installed successfully!", "info")
end

-- Load all highlights (apply everything fresh)
M.load_all_highlights = function()
  local merged = {}
  for _, hl in pairs(config.integrations) do
    merged = M.merge_tb(merged, hl)
  end
  M.apply_highlights(merged)
  vim.api.nvim_exec_autocmds("User", { pattern = "ThemeReload" })
end

-- Programmatically set theme
M.set_theme = function(name)
  config.theme = name
  M.load_all_highlights()
end

-- Toggle transparency
M.toggle_transparency = function()
  config.transparency = not config.transparency
  M.load_all_highlights()
end

M.config = config

return M
