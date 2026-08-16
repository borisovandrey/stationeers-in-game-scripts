-- Trader station middle atmosphere analyser screen.
-- Uses the shared atmos module to render live gas composition, pressure,
-- temperature, and mole readings from the "Middle" analyser device.
local atmos = require("atmos")
local uiSettings = atmos.init({ name = "MIDDLE"})
local pad = ic.find("Middle")
function tick(dt)
    atmos.render(pad, uiSettings)
end
