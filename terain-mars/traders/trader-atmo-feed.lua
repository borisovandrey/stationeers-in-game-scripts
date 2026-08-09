-- Trader station feed atmosphere analyser screen.
-- Uses the shared atmos module to render live gas composition, pressure,
-- temperature, and mole readings from the feed analyser device.
local atmos = require("atmos")

local uiSettings = atmos.init()
local pad = ic.find("feed-analizer")

atmos.render(pad, uiSettings, "FEED")

function tick(dt)
    atmos.render(pad, uiSettings, "FEED")
end
