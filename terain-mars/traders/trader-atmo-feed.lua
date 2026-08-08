local atmos = require("atmos")

local uiSettings = atmos.init()
local pad = ic.find("feed-analizer")

atmos.render(pad, uiSettings)

function tick(dt)
    atmos.render(pad, uiSettings)
end
