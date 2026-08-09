-- Trader station middle atmosphere analyser screen.
-- Uses the shared atmos module to render live gas composition, pressure,
-- temperature, and mole readings from the "Middle" analyser device.
local atmos = require("atmos")

local uiSettings = atmos.init()
local pad = ic.find("Middle")

atmos.render(pad, uiSettings, "MIDDLE")

function tick(dt)
    atmos.render(pad, uiSettings, "MIDDLE")
end
