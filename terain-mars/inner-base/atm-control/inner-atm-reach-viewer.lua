local atmos = require("atmos")
local ui_settings = atmos.init({name = "ROOM"})
local device = ic.find("atm-quality-sns")

function tick(dt)
    atmos.render(device, ui_settings)
end
