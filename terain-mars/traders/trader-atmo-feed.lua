-- Trader station feed atmosphere analyser screen.
-- Uses the shared atmos module to render live gas composition, pressure,
-- temperature, and mole readings from the feed analyser device.
local atmos = require("atmos")
local uiSettings = atmos.init({ name = "FEED"})
local pad = ic.find("tr-gas-sns")
function tick(dt)
    atmos.render(pad, uiSettings)
end
