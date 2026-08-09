local LT = ic.enums.LogicType

local Color = {
    Blue   = 0,
    Gray   = 1,
    Green  = 2,
    Orange = 3,
    Red    = 4,
    Yellow = 5,
    White  = 6,
    Black  = 7,
    Brown  = 8,
    Khaki  = 9,
    Pink   = 10,
    Purple = 11,
}

local DisplayMode = {
    Default = 0,
    Power = 2,
    Persent = 1,
    Celsius = 4,
    String = 10,
    Litres = 12,
    Mol = 13,
    Pa = 14,
}

local Model = {
    landing = {
        pad = ic.find("Middle"),
        gas_input = ic.find("tr-m-gas-input"),
        gas_output = ic.find("tr-m-gas-output"),
    }
}

local gases = {
    { logicType = LT.RatioOxygen, label = pack_ascii6("O2"), color = Color.White },
    { logicType = LT.RatioNitrogen, label = pack_ascii6("N2"), color = Color.Green },
    { logicType = LT.RatioMethane, label = pack_ascii6("CH4"), color = Color.Red },
    { logicType = LT.RatioCarbonDioxide, label = pack_ascii6("CO2"), color = Color.Yellow },
}

local Console = {
    Controls = {
        device = ic.find("tr-m-console"),
        power = ic.find("tr-m-power-sw"),
        numpad = ic.find("tr-m-moles-numpad"),
        load_sw = ic.find("tr-m-load-sw"),
        clear_sw = ic.find("tr-m-clear-sw"),
        gas_dial = ic.find("tr-m-gas-dial"),
        gas_dsp = ic.find("tr-m-gas-dsp"),
        water_dsp = ic.find("tr-m-tube-water-dsp")
    },
    powered = false,
    selectedGas = 0,
}

function Console:init()
    ic.write_id(self.Controls.numpad, LT.Setting, 0)
    ic.write_id(self.Controls.gas_dsp, LT.Mode, DisplayMode.String)
    ic.write_id(self.Controls.water_dsp, LT.Mode, DisplayMode.Litres)
    ic.write_id(self.Controls.water_dsp, LT.Color, Color.Blue)
    ic.write_id(self.Controls.gas_dial, LT.Setting, 0)
    ic.write_id(self.Controls.load_sw, LT.On, 0)
    ic.write_id(self.Controls.load_sw, LT.Color, Color.Gray)
    ic.write_id(self.Controls.clear_sw, LT.On, 0)
    ic.write_id(self.Controls.clear_sw, LT.Color, Color.Gray)
end

function Console:checkPower()
    local sw = ic.read_id(self.Controls.power, LT.Setting) == 1
    if sw ~= self.powered then
        ic.write_id(self.Controls.device, LT.On, sw and 1 or 0)
        self.powered = sw
    end
end

function Console:checkGasSelector()
    local dial = ic.read_id(self.Controls.gas_dial, LT.Setting) or 0
    dial = math.max(1, math.min(dial + 1, #gases))
    if self.selectedGas ~= dial then
        self.selectedGas = dial
        local gas = gases[dial]
        ic.write_id(self.Controls.gas_dsp, LT.Setting, gas.label)
        ic.write_id(self.Controls.gas_dsp, LT.Color, gas.color)
    end
end

function Console:update()
    self:checkPower()
    self:checkGasSelector()
end

Console:init()

function tick(dt)
    Console:update()
end
