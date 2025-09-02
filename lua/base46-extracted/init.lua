local M = {}

-- Default user config (can be overridden with setup())
local config = {
  theme = "tundra",
  transparency = false,
  hl_override = {},
  changed_themes = {},
  cache_path = vim.fn.stdpath "data" .. "/base46-extracted/",
  integrations = {
    "blankline",
    "cmp",
    "git",
    "lsp",
    "mason",
    "nvimtree",
    "statusline",
    "syntax",
    "treesitter",
    "telescope",
    "whichkey",
  },
}

-- Allow user to override defaults
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  if opts and opts.integrations then
    for _, value in ipairs(opts.integrations) do
      table.insert(config.integrations, value)
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

-- Load integration highlights
M.get_integration = function(name)
  local highlights = require("base46-extracted.integrations." .. name)
  return M.extend_default_hl(highlights, name)
end

-- Convert table to string for caching
M.tb_2str = function(tb)
  local result = ""
  for hlgroupName, v in pairs(tb) do
    local hlname = "'" .. hlgroupName .. "',"
    local hlopts = ""
    for optName, optVal in pairs(v) do
      local valueInStr = ((type(optVal)) == "boolean" or type(optVal) == "number") and tostring(optVal)
        or '"' .. optVal .. '"'
      hlopts = hlopts .. optName .. "=" .. valueInStr .. ","
    end
    result = result .. "vim.api.nvim_set_hl(0," .. hlname .. "{" .. hlopts .. "})"
  end
  return result
end

-- Write compiled highlights to cache
M.str_to_cache = function(filename, str)
  local lines = "return string.dump(function()" .. str .. "end, true)"
  local file = io.open(config.cache_path .. filename, "wb")
  if file then
    file:write(loadstring(lines)())
    file:close()
  end
end

-- Compile all highlights
M.compile = function()
  if not vim.uv.fs_stat(config.cache_path) then
    vim.fn.mkdir(config.cache_path, "p")
  end

  M.str_to_cache("term", require "base46-extracted.term")
  M.str_to_cache("colors", require "base46-extracted.color_vars")

  for _, name in ipairs(config.integrations) do
    local hl_str = M.tb_2str(M.get_integration(name))

    if name == "defaults" then
      hl_str = "vim.o.tgc=true vim.o.bg='" .. M.get_theme_tb "type" .. "' " .. hl_str
    end

    M.str_to_cache(name, hl_str)
  end
end

-- Load all highlights
M.load_all_highlights = function()
  M.compile()
  for _, name in ipairs(config.integrations) do
    dofile(config.cache_path .. name)
  end
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
