barWidget.define({
  label = "WireGuard Status",
  version = "1.0.0",
  icon = "shield-lock",
  description = "Show and toggle a WireGuard status command",
  settings = {
    { key = "status_command", type = "string", label = "Status command" },
    { key = "toggle_command", type = "string", label = "Toggle command" },
    { key = "tooltip", type = "string", label = "Tooltip", default = "WireGuard" },
    { key = "fallback_glyph", type = "glyph", label = "Fallback glyph", default = "shield-lock" },
  },
})

local pending = false

local function cfg(key, default)
  return barWidget.getConfig(key, default)
end

local function jsonString(raw, key)
  return raw:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end

local function colorOrDefault(color)
  if color == nil or color == "" or color == "none" then
    return "on_surface"
  end
  return color
end

local function applyStatus(raw)
  local text = jsonString(raw, "text") or "?"
  local glyph = jsonString(raw, "icon") or cfg("fallback_glyph", "shield-lock")
  local color = colorOrDefault(jsonString(raw, "color"))
  local tooltip = cfg("tooltip", "WireGuard")

  barWidget.setText(text)
  barWidget.setGlyph(glyph)
  barWidget.setColor(color, "script")
  barWidget.setGlyphColor(color, "script")
  barWidget.setTooltip({
    { key = "Status", value = text },
    { key = "Left click", value = "Toggle" },
    { key = "Command", value = tooltip },
  })
end

local function refresh()
  if pending then return end

  local command = cfg("status_command", "")
  if command == "" then
    barWidget.setText("wg?")
    barWidget.setGlyph(cfg("fallback_glyph", "shield-lock"))
    barWidget.setColor("error", "script")
    barWidget.setGlyphColor("error", "script")
    barWidget.setTooltip("Missing status command")
    return
  end

  pending = true
  noctalia.runAsync(command, function(result)
    pending = false
    if result.exitCode == 0 then
      applyStatus(result.stdout)
    else
      barWidget.setText("err")
      barWidget.setGlyph(cfg("fallback_glyph", "shield-lock"))
      barWidget.setColor("error", "script")
      barWidget.setGlyphColor("error", "script")
      barWidget.setTooltip(result.stderr ~= "" and result.stderr or "Status command failed")
    end
  end, 5000)
end

barWidget.setUpdateInterval(5000)
refresh()

function update()
  refresh()
end

function onClick()
  local command = cfg("toggle_command", "")
  if command == "" then return end

  noctalia.runAsync(command, function()
    refresh()
  end, 10000)
end
