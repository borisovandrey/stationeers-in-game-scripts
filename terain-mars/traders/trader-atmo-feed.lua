local atmos = require("atmos")

local uiSettings = atmos.init()
local pad = ic.find("feed-analizer")

atmos.render(pad, uiSettings, "FEED")

function tick(dt)
    atmos.render(pad, uiSettings, "FEED")
end
