local LT = ic.enums.LogicType
local EPSILON = 1e-6


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

local function isZero(value)
    return value ~= nil and math.abs(value) < EPSILON
end

local function isOne(value)
    return value ~= nil and math.abs(value - 1) < EPSILON
end

local function isPositive(value)
    return value ~= nil and value > EPSILON
end

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

function Model:switchGasInputPump(on)
    self.landing.gas_input:setPower(on)
end

function Model:switchGasHeater(on)
    self.tubes.heater:setPower(on)
end

function Model:switchGasTypeTubePump(on, gas_type)
    local pump = self.tubes.pumps[gas_type]
    if pump then
        pump:setPump(on, PumpMode.Input, on and 30 or 0)
    end
end

function Model.tubes:getLitres()
    return ic.read_id(self.sensors.liquid, LT.VolumeOfLiquid)
end

function Model.tubes:isClear()
    local moles = ic.read_id(self.sensors.gas, LT.TotalMoles)
    local litres = ic.read_id(self.sensors.liquid, LT.VolumeOfLiquid)
    return isZero(moles) and isZero(litres)
end

function Model.landing:isClear()
    local moles = ic.read_id(self.pad.id, LT.TotalMoles)
    return isZero(moles)
end

function Model:isClear()
    return self.tubes:isClear() and self.landing:isClear()
end

function Model:clearGas()
    local moles = ic.read_id(self.tubes.sensors.gas, LT.TotalMoles)
    if isZero(moles) then
        for _, pump in pairs(self.tubes.pumps) do
            pump:setPump(false, PumpMode.Input, 0)
        end
        self.tubes.clear:setPump(false, PumpMode.Output, 0)
    else
        for gas, pump in pairs(self.tubes.pumps) do
            local ratio = ic.read_id(self.tubes.sensors.gas, gas)
            if isOne(ratio) then
                pump:setPump(true, PumpMode.Output, 100)
                break
            end
            if isPositive(ratio) then
                self.tubes.clear:setPump(true, PumpMode.Output, 100)
                break
            end
        end
    end
end

function Model:clearWater()
    local litres = ic.read_id(self.tubes.sensors.liquid, LT.VolumeOfLiquid)
    local pump = self.tubes.pumps[LT.RatioWater]
    if isZero(litres) then
        pump:setPump(false, PumpMode.Input, 0)
    else
        local ratio = (ic.read_id(self.tubes.sensors.liquid, LT.RatioWater) or 0) +
                      (ic.read_id(self.tubes.sensors.liquid, LT.RatioSteam) or 0)

        if isOne(ratio) then
            pump:setPump(true, PumpMode.Output, 100)
        else
            pump:setPump(false, PumpMode.Input, 0)
        end
    end
end

function Model:clearLandingGas()
    local landing_moles = ic.read_id(self.landing.pad.id, LT.TotalMoles)
    if isZero(landing_moles) then
        self.landing.gas_output:setPower(false)
        return
    end
    local tube_moles = ic.read_id(self.tubes.sensors.gas, LT.TotalMoles)
    if isZero(tube_moles) then
        self.landing.gas_output:setPower(true)
    else
        for gas, _ in pairs(self.tubes.pumps) do
            local landing_ratio = ic.read_id(self.landing.pad.id, gas)
            local tube_ratio = ic.read_id(self.tubes.sensors.gas, gas)
            if isOne(landing_ratio) and isOne(tube_ratio) then
                self.landing.gas_output:setPower(true)
                return;
            end
        end
        self.landing.gas_output:setPower(false)
    end
end

function Model:clearLandingWater()
    local landing_ratio = (ic.read_id(self.landing.pad.id, LT.RatioWater) or 0) +
                          (ic.read_id(self.landing.pad.id, LT.RatioSteam) or 0)
    if isZero(landing_ratio) then
        self.landing.liquid_output:setPower(false)
        return
    end

    local tube_litres = ic.read_id(self.tubes.sensors.liquid, LT.VolumeOfLiquid)
    if isZero(tube_litres) then
        self.landing.liquid_output:setPower(true)
        return
    end

    local tube_ratio = (ic.read_id(self.tubes.sensors.liquid, LT.RatioWater) or 0) +
                       (ic.read_id(self.tubes.sensors.liquid, LT.RatioSteam) or 0)
    if isOne(landing_ratio) and isOne(tube_ratio) then
        self.landing.liquid_output:setPower(true)
        return
    end

    self.landing.liquid_output:setPower(false)
end

function Model:isTheOnlyGasInTube(gas_type)
    local moles = ic.read_id(self.tubes.sensors.gas, LT.TotalMoles)
    local temperature = util.temp(ic.read_id(self.tubes.sensors.gas, LT.Temperature) or 0, "K", "C")
    if isZero(moles) then return true, 0, temperature end

    local ratio = ic.read_id(self.tubes.sensors.gas, gas_type)
    return isOne(ratio), moles, temperature
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
    loadOn = false,
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

function Console:getSelectedGas()
    self:checkGasSelector()
    return gases[self.selectedGas].logicType
end

function Console:getMolesToLoad()
    return (ic.read_id(self.Controls.numpad, LT.Setting) or 0) * 100
end

function Console:update()
    self:checkGasSelector()
    ic.write_id(self.Controls.water_dsp, LT.Setting, Model.tubes:getLitres())
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

function Console:checkLoad()
     local on = ic.read_id(self.Controls.load_sw, LT.On) == 1
     if on ~= self.loadOn then
        self.loadOn = on
        ic.write_id(self.Controls.load_sw, LT.Color, on and Color.Green or Color.Gray)
     end
     return on
end

function Console:setLoad(on)
    if on ~= self.loadOn then
        ic.write_id(self.Controls.load_sw, LT.On, on and 1 or 0)
        ic.write_id(self.Controls.load_sw, LT.Color, on and Color.Green or Color.Gray)
    end
end


local State = {
    Off = 0,
    Idle = 1,
    Clearing = 2,
    LoadPepare = 3,
    LoadFinish = 4
}

local Controller = {
    ControllerState = State.Off,
    gas_type = nil,
    to_load = 0,
    StateMachine = {
        [State.Off] =         { enter = nil, exit = nil, next = nil },
        [State.Idle] =        { enter = nil, exit = nil, next = nil },
        [State.Clearing] =    { enter = nil, exit = nil, next = nil },
        [State.LoadPepare] =    { enter = nil, exit = nil, next = nil },
        [State.LoadFinish] =    { enter = nil, exit = nil, next = nil },
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

    if Console:checkLoad() then
        return State.LoadPepare
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
    if Model:isClear() then
        Console:setClear(false)
        return State.Idle
    end
    
    Model:clearGas()
    Model:clearWater()
    Model:clearLandingGas()
    Model:clearLandingWater()
    return State.Clearing
end
-- State LoadPepare
Controller.StateMachine[State.LoadPepare].enter = function(self)
    self.gas_type = Console:getSelectedGas()
    self.to_load = Console:getMolesToLoad()
end
Controller.StateMachine[State.LoadPepare].exit = function(self)
    Model:switchGasTypeTubePump(false, self.gas_type)
    Model:switchGasHeater(false)
end
Controller.StateMachine[State.LoadPepare].next = function(self)
    if not Console:getPower() then
        return State.Off
    end

    if Console:checkClear() then
        return State.Clearing
    end

    if not Console:checkLoad() then
        return State.Idle
    end

    local gas_type = self.gas_type
    local to_load = self.to_load
    local ok, moles, temperature = Model:isTheOnlyGasInTube(gas_type)

    if not ok then
        Console:setClear(true)
        return State.Clearing
    end

    Model:switchGasTypeTubePump(moles < to_load, gas_type)
    Model:switchGasHeater(temperature < EPSILON)
    if moles >= to_load and temperature >= -EPSILON then
        return State.LoadFinish
    end

    return State.LoadPepare
end

Controller.StateMachine[State.LoadFinish].enter = function(self)
end
Controller.StateMachine[State.LoadFinish].exit = function(self)
    Model:switchGasInputPump(false)
end
Controller.StateMachine[State.LoadFinish].next = function(self)
    if not Console:getPower() then
        return State.Off
    end

    if Console:checkClear() then
        return State.Clearing
    end

    if not Console:checkLoad() then
        return State.Idle
    end

    if Model.tubes:isClear() then
        Model:switchGasInputPump(false)
        Console:setLoad(false)
        return State.Idle
    end

    Model:switchGasInputPump(true)

    return State.LoadFinish
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
