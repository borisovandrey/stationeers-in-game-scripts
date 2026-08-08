local atmos = require("atmos")

local uiSettings = atmos.init()
local pad = ic.find("Middle")

atmos.render(pad, uiSettings, "MIDDLE")

function tick(dt)
    atmos.render(pad, uiSettings, "MIDDLE")
end
