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

local PumpMode = {
    Input = 1,
    Output = 0,
    Unknown = 0xFFFF
}

local function setPower(self, on)
    if self.on ~= on then
        ic.write_id(self.id, LT.On, on and 1 or 0)
        self.on = on
    end
end

local function setPump(self, on, mode, strength)
    if not on and self.on then
        ic.write_id(self.id, LT.On, 0)
        self.on = false
    end
    if mode and self.mode ~= mode then
        ic.write_id(self.id, LT.Mode, mode)
        self.mode = mode
    end

    if strength and self.strength ~= strength then
        ic.write_id(self.id, LT.Setting, strength)
        self.strength = strength
    end

    if on and not self.on then 
        ic.write_id(self.id, LT.On, 1)
        self.on = true
    end
end

local Model = {
    landing = {
        pad = { id = ic.find("Middle") },
        gas_input = { id = ic.find("tr-m-gas-input"), on = true, setPower = setPower,},
        gas_output = { id = ic.find("tr-m-gas-output"), on = true, setPower = setPower,},
        liquid_input = { id = ic.find("tr-m-liquid-input"), on = true, setPower = setPower,},
        liquid_output = { id = ic.find("tr-m-liquid-output"), on = true, setPower = setPower,},
    },
    tubes = {
        pumps = {
            [LT.RatioOxygen] = { id = ic.find("tr-pump-oxygen"), on = true, mode = PumpMode.Unknown, strength = -1, setPump = setPump },
            [LT.RatioNitrogen] = { id = ic.find("tr-pump-nytrogen"), on = true, mode = PumpMode.Unknown, strength = -1, setPump = setPump },
            [LT.RatioMethane] = { id = ic.find("tr-pump-methane"), on = true, mode = PumpMode.Unknown, strength = -1, setPump = setPump },
            [LT.RatioCarbonDioxide] = { id = ic.find("tr-pump-carbo"), on = true, mode = PumpMode.Unknown, strength = -1, setPump = setPump },
            [LT.RatioWater] = { id = ic.find("tr-pump-water"), on = true, mode = PumpMode.Unknown, strength = -1, setPump = setPump },
        },
        clear = {id = ic.find("tr-pump-clear"), on = true, setPump = setPump},
        heater = { id = ic.find("tr-heater"), on = true, setPower = setPower},
        sensors = {
            gas = ic.find("tr-gas-sns"),
            liquid = ic.find("tr-liquid-sns"),
        }
    }
}

function Model:powerDown()
    self.landing.gas_input:setPower(false)
    self.landing.gas_output:setPower(false)
    self.landing.liquid_input:setPower(false)
    self.landing.liquid_output:setPower(false)
    self.tubes.clear:setPump(false, PumpMode.Output, 0)
    self.tubes.heater:setPower(false)
    for _, pump in pairs(self.tubes.pumps) do
        pump:setPump(false, PumpMode.Input, 0)
    end
end

function Model:init()
    self:powerDown()
end

function Model:clearGas()
    local moles = ic.read_id(self.tubes.sensors.gas, LT.TotalMoles)
    if moles == 0 then
        for _, pump in pairs(self.tubes.pumps) do
            pump:setPump(false, PumpMode.Input, 0)
        end
        self.tubes.clear:setPump(false, PumpMode.Output, 0)
    else
        for gas, pump in pairs(self.tubes.pumps) do
            local ratio = ic.read_id(self.tubes.sensors.gas, gas)
            if ratio == 1 then
                pump:setPump(false, PumpMode.Output, 100)
                break
            end
            if ratio > 0 then
                self.tubes.clear:setPump(false, PumpMode.Output, 100)
                break
            end
        end
    end
end

function Model:clearWater()
end

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
    clearOn = false,
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

function Console:getPower()
    return ic.read_id(self.Controls.power, LT.Setting) == 1
end

function Console:setPower(on)
    if on ~= self.powered then
        ic.write_id(self.Controls.device, LT.On, on and 1 or 0)
        self.powered = on
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
    self:checkGasSelector()
end

function Console:checkClear()
     local on = ic.read_id(self.Controls.clear_sw, LT.On) == 1
     if on ~= self.clearOn then
        self.clearOn = on
        ic.write_id(self.Controls.clear_sw, LT.Color, on and Color.Red or Color.Gray)
     end
     return on
end

function Console:setClear(on)
    if on ~= self.clearOn then
        ic.write_id(self.Controls.clear_sw, LT.On, on and 1 or 0)
    end
end

local State = {
    Off = 0,
    Idle = 1,
    Clearing = 2,
}

local Controller = {
    ControllerState = State.Off,
    StateMachine = {
        [State.Off] =         { enter = nil, exit = nil, next = nil },
        [State.Idle] =        { enter = nil, exit = nil, next = nil },
        [State.Clearing] =    { enter = nil, exit = nil, next = nil },
    },
    init = {},
    defineNewState = {},
    run = {},
    update = {},
}

-- State Off
Controller.StateMachine[State.Off].enter = function(self)
    Model:powerDown()
    Console:setPower(false)
end
Controller.StateMachine[State.Off].exit = function(self)
    Console:setPower(true)
end
Controller.StateMachine[State.Off].next = function(self)
    if Console:getPower() then
        return State.Idle
    end
    return State.Off
end
-- State Idle
Controller.StateMachine[State.Idle].enter = function(self)
end
Controller.StateMachine[State.Idle].exit = function(self)
end
Controller.StateMachine[State.Idle].next = function(self)
    if not Console:getPower() then
        return State.Off
    end

    if Console:checkClear() then
        return State.Clearing
    end
    return State.Idle
end
-- State Clearing
Controller.StateMachine[State.Clearing].enter = function(self)
    Model:powerDown()
end
Controller.StateMachine[State.Clearing].exit = function(self)
    Model:powerDown()
end
Controller.StateMachine[State.Clearing].next = function(self)
    if not Console:checkClear() then
        return State.Idle
    end
    if not Console:getPower() then
        return State.Off
    end
    Model:clearGas()
    Model:clearWatter()
    return State.Clearing
end


function Controller:init()
    Console:init()
    Model:init()
end

function Controller:update(newState)
    local old = Controller.StateMachine[self.ControllerState]
    local new = Controller.StateMachine[newState]
    if old and old.exit then old.exit(self) end
    if new and new.enter then new.enter(self) end
    self.ControllerState = newState
end

function Controller:defineNewState()
    local state = Controller.StateMachine[self.ControllerState]
    return state.next(self)
end

function Controller:run()
    local newState = Controller:defineNewState()
    if self.ControllerState ~= newState then
        self:update(newState)
    end
    Console:update()
end


Controller:init()

function tick(dt)
    Controller:run()
end
