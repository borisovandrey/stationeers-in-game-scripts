--terain-mars\gas-station\liquid-co2\luquid-co2.lua
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

-- Definitions
local EPSILON = 0.001
local FULL_LIQUID_VOLUME = 5700
local LOW_TEMPERATURE_LIMIT = util.temp(-50, "C", "K")
local HIGH_TEMPERATURE_LIMIT = util.temp(-25, "C", "K")
local EMERGENCY_PRESSURE_THRESHOLD = 0.5
local NORMAL_PRESSURE = 0.7
local NORMAL_PRESSURE_DELTA = 0.2
local VENT_DIRECT_MODE = 0
local VENT_REVERSE_MODE = 1

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

local State = {
    PowerOff    = 1, -- Power switch is off on console
    Idle        = 2, -- Power switch is on but operation switch is off
    Prepare     = 3, -- Operation switch is on, but there is a bad condition
    Operational = 4, -- Performing condensation
    Full        = 5, -- Liquid tank is full
    Clearing    = 6, -- Clear tanks
}

local StateName = {
    [1] = "PowerOff",
    [2] = "Idle",
    [3] = "Prepare",
    [4] = "Operational",
    [5] = "Full",
    [6] = "Clearing",
}

-- Gas Tables
local CO2 = {
    {t = -50, p =  687},
    {t = -45, p =  907},
    {t = -40, p = 1129},
    {t = -35, p = 1476},
    {t = -30, p = 1919},
    {t = -25, p = 2480},
    {t = -20, p = 3189},
    {t = -15, p = 4080},
}
local Pol = {
    {t = -50, p = 2505},
    {t = -45, p = 2581},
    {t = -40, p = 2643},
    {t = -35, p = 2720},
    {t = -30, p = 2798},
    {t = -25, p = 2876},
    {t = -20, p = 2955},
    {t = -15, p = 3034},
}
local function interp(tbl, t)
    local n = #tbl
    if t <= tbl[1].t then return tbl[1].p end
    if t >= tbl[n].t then return tbl[n].p end
    for i = 1, n - 1 do
        local a = tbl[i]
        local b = tbl[i + 1]
        if t <= b.t then
            return a.p + (t - a.t) * (b.p - a.p) / (b.t - a.t)
        end
    end
    return tbl[n].p
end

-- Device
local Device = {
    ExteranlTemperature = 0,
    GasTemperature      = 0,
    GasPressure         = 0,
    GasTubeLiquidVolume = 0,
    LiquidTemperature   = 0,
    LiquidPressure      = 0,
    LiquidVolume        = 0,
    Contaminated        = false,
    Sensors = {
        External = ic.find("co2-cond-sns-ext"), -- External gas sensor
        Gas = ic.find("co2-cond-sns-gas"),      -- Tube gas sensor
        Liquid = ic.find("co2-cond-sns-liquid"),-- Tube liquid sensor
    },
    Actuators = {
        MainVent = ic.find("co2-cond-main-vent"), -- Main ventilator system     
        LiquidAbsPump = ic.find("co2-cond-liq-pump"), -- Drain sysetm - pump
        LiquidAbsDrain = ic.find("co2-cond-liq-drain"), -- Drain system - drain
        GasAbsPump = ic.find("co2-cond-gas-pump") -- Gase exctractor from liquid tank
    },
    powerOn = {},
    powerOff = {},
    init = {},
    collectData = {},
    isFull = {},
    runVent = {},
    runVentReverse = {},
    stopVent = {},
    startCleraing = {},
    stopCleraing = {}
}

function Device:init()
    -- Empty
end

function Device:powerOn()
    ic.write_id(self.Sensors.External, LT.On, 1)
    ic.write_id(self.Sensors.Gas, LT.On, 1)
    ic.write_id(self.Sensors.Liquid, LT.On, 1)
end

function Device:powerOff()
    ic.write_id(self.Sensors.External, LT.On, 0)
    ic.write_id(self.Sensors.Gas, LT.On, 0)
    ic.write_id(self.Sensors.Liquid, LT.On, 0)
    ic.write_id(self.Actuators.MainVent, LT.On, 0)
    ic.write_id(self.Actuators.LiquidAbsPump, LT.On, 0)
    ic.write_id(self.Actuators.LiquidAbsDrain, LT.On, 0)
    ic.write_id(self.Actuators.GasAbsPump, LT.On, 0)
end

function Device:runVent()
    ic.write_id(self.Actuators.MainVent, LT.Mode, VENT_DIRECT_MODE)
    ic.write_id(self.Actuators.MainVent, LT.On, 1)
end

function Device:runVentReverse()
    ic.write_id(self.Actuators.MainVent, LT.Mode, VENT_REVERSE_MODE)
    ic.write_id(self.Actuators.MainVent, LT.On, 1)
end

function Device:stopVent()
    ic.write_id(self.Actuators.MainVent, LT.On, 0)
end

function Device:startCleraing()
    self:runVentReverse()
    ic.write_id(self.Actuators.GasAbsPump, LT.On, 1)
    ic.write_id(self.Actuators.LiquidAbsPump, LT.On, 1)
    ic.write_id(self.Actuators.LiquidAbsDrain, LT.On, 1)
end

function Device:stopCleraing()
    self:stopVent()
    ic.write_id(self.Actuators.GasAbsPump, LT.On, 0)
    ic.write_id(self.Actuators.LiquidAbsPump, LT.On, 0)
    ic.write_id(self.Actuators.LiquidAbsDrain, LT.On, 0)
end

function Device:collectData()
    self.ExteranlTemperature = util.temp(ic.read_id(self.Sensors.External, LT.Temperature) or 0, "K", "C")
    self.GasTemperature      = util.temp(ic.read_id(self.Sensors.Gas, LT.Temperature) or 0, "K", "C")
    self.GasPressure         = ic.read_id(self.Sensors.Gas, LT.Pressure) or 0
    self.GasTubeLiquidVolume = ic.read_id(self.Sensors.Gas, LT.VolumeOfLiquid) or 0
    self.LiquidTemperature   = util.temp(ic.read_id(self.Sensors.Liquid, LT.Temperature) or 0, "K", "C")
    self.LiquidPressure      = ic.read_id(self.Sensors.Liquid, LT.Pressure) or 0
    self.LiquidVolume        = ic.read_id(self.Sensors.Liquid, LT.VolumeOfLiquid) or 0
    local ratioCO2Gas        = ic.read_id(self.Sensors.Liquid, LT.RatioCarbonDioxide) or 0
    local ratioCO2Liq        = ic.read_id(self.Sensors.Liquid, LT.RatioLiquidCarbonDioxide) or 0
    local sum = ratioCO2Gas + ratioCO2Liq
    self.Contaminated        =  math.abs(sum - 1.0) > EPSILON
end

function Device:isFull()
    return self.LiquidVolume >= FULL_LIQUID_VOLUME
end

-- Console 
local Console = {
    ConsoleState  = State.PowerOff,
    ConsoleDevice = ic.find("co2-cond-condev"), -- Console as device 
    PowerSwitch   = ic.find("co2-cond-pwr"), -- Power swithc of the console
    OperateSwitch = ic.find("co2-cond-op"),  -- Operational switch
    ClearSwitch   = ic.find("co2-cond-clr"), -- Clear switch
    Lights = {
        StateLEDs = {
             [State.PowerOff]    = nil,
             [State.Idle]        = ic.find("co2-cond-light-idle"), -- Idle light 
             [State.Prepare]     = ic.find("co2-cond-light-prepare"), -- Prepare light
             [State.Operational] = ic.find("co2-cond-light-op"),   -- Operational
             [State.Full]        = ic.find("co2-cond-light-full"), -- Tank is full
             [State.Clearing]    = ic.find("co2-cond-light-clr"),  -- Clear
             init = {}
        },
        Dirty= ic.find("co2-cond-light-dirty"), -- Dirty
        init = {}
   },
   SensorDisplays = {
         EternalTemperature = ic.find("co2-cond-sns-exttemp"),
         GasTemperature = ic.find("co2-cond-sns-gastemp"),
         GasPressure = ic.find("co2-cond-sns-gaspress"),
         LiqTemperature = ic.find("co2-cond-sns-liqtemp"),
         LiqPressure = ic.find("co2-cond-sns-liqpress"),
         LiqVolume = ic.find("co2-cond-sns-liqvol"),
         init = {}
   }
   ,init = {}
   ,setPower = {}
   ,isPowerOn = {}
   ,isUp = {}
   ,isClearing = {}
   ,setClearing = {}
   ,changeState = {}
   ,setDisplaysData = {}
   ,update = {}
}

function Console.Lights.StateLEDs:init()
    ic.write_id(self[State.Idle], LT.Color, Color.Green)
    ic.write_id(self[State.Prepare], LT.Color, Color.Blue)
    ic.write_id(self[State.Full], LT.Color, Color.Blue)
    ic.write_id(self[State.Operational], LT.Color, Color.Orange)
    ic.write_id(self[State.Clearing],   LT.Color, Color.Yellow)
end

function Console.Lights:init()
    self.StateLEDs.init()
    ic.write_id(self.Dirty, LT.Color, Color.Red)
end

function Console.SensorDisplays:init()
    ic.write_id(self.EternalTemperature, LT.On, 1)
    ic.write_id(self.EternalTemperature, LT.Mode, DisplayMode.Celsius)
    ic.write_id(self.EternalTemperature, LT.Color, Color.White)
    ic.write_id(self.GasTemperature, LT.On, 1)
    ic.write_id(self.GasTemperature, LT.Mode, DisplayMode.Celsius)
    ic.write_id(self.GasTemperature, LT.Color, Color.Yellow)
    ic.write_id(self.GasPressure, LT.On, 1)
    ic.write_id(self.GasPressure, LT.Mode, DisplayMode.Pa)
    ic.write_id(self.GasPressure, LT.Color, Color.Orange)
    ic.write_id(self.LiqTemperature, LT.On, 1)
    ic.write_id(self.LiqTemperature, LT.Mode, DisplayMode.Celsius)
    ic.write_id(self.LiqTemperature, LT.Color, Color.Blue)
    ic.write_id(self.LiqPressure, LT.On, 1)
    ic.write_id(self.LiqPressure, LT.Mode, DisplayMode.Pa)
    ic.write_id(self.LiqPressure, LT.Color, Color.Blue)
    ic.write_id(self.LiqVolume, LT.On, 1)
    ic.write_id(self.LiqVolume, LT.Mode, DisplayMode.Litres)
    ic.write_id(self.LiqVolume, LT.Color, Color.Blue)
end

function Console:init()
    self.Lights:init()
    self.SensorDisplays.init()
    ic.write_id(self.ClearSwitch, LT.Color, Color.Red)
end

function Console:setPower(on)
    ic.write_id(self.ConsoleDevice, LT.On, on and 1 or 0)
end

function Console:isPowerOn()
    return ic.read_id(self.PowerSwitch, LT.On) == 1
end

function Console:isUp()
    return ic.read_id(self.OperateSwitch, LT.On) == 1
end

function Console:isClearing()
    return ic.read_id(self.ClearSwitch, LT.On) == 1
end

function Console:setClearing(on)
    return ic.write_id(self.ClearSwitch, LT.On, on and 1 or 0)
end

function Console:updateDisplays()
    ic.write_id(self.SensorDisplays.EternalTemperature, LT.Setting, Device.ExteranlTemperature)
    ic.write_id(self.SensorDisplays.GasTemperature, LT.Setting, Device.GasTemperature)
    ic.write_id(self.SensorDisplays.GasPressure, LT.Setting, Device.GasPressure)
    ic.write_id(self.SensorDisplays.LiqTemperature, LT.Setting, Device.LiquidTemperature)
    ic.write_id(self.SensorDisplays.LiqPressure, LT.Setting, Device.LiquidPressure)
    ic.write_id(self.SensorDisplays.LiqVolume, LT.Setting, Device.LiquidVolume)
    ic.write_id(self.Lights.Dirty, LT.On, Device.Contaminated and 1 or 0)
end

function Console:changeState(newState)
    local oldLed = self.Lights.StateLEDs[self.ConsoleState]
    local newLed = self.Lights.StateLEDs[newState]
    if oldLed then
        ic.write_id(oldLed, LT.On, 0)
    end
    if newLed then
        ic.write_id(newLed, LT.On, 1)
    end
    self.ConsoleState = newState
end

function Console:update(newState)
    if newState ~= self.ConsoleState then
        self:changeState(newState)
    end
    if self.ConsoleState ~= State.PowerOff then
        self:updateDisplays()
    end
end


-- Controller
local ControllerSubstates = {
    PrepareSubstate = {Ready = 1, ClearGas = 2}, 
    OperationalSubstate = { Run = 1, Pause = 2 }
}

local Controller = {
    ControllerState = State.PowerOff,

    StateMachine = {
        [State.PowerOff] =    { enter = nil, exit = nil, next = nil },
        [State.Idle] =        { enter = nil, exit = nil, next = nil },
        [State.Prepare] =     { enter = nil, exit = nil, next = nil, substate = ControllerSubstates.PrepareSubstate.ClearGas },
        [State.Operational] = { enter = nil, exit = nil, next = nil, substate = ControllerSubstates.OperationalSubstate.Run },
        [State.Full] =        { enter = nil, exit = nil, next = nil },
        [State.Clearing] =    { enter = nil, exit = nil, next = nil },
    },
    init = {},
    defineNewState = {},
    Conditions = {
        NeedClear = 1,      -- Wrong temperature or pressure bigger than Polutant condensation
        HighPressure = 2,   -- Pressure is higher than Median + 20%
        NormalPressure = 3, -- Pressure is -20%..20% range of Median (70% from HighPressure)
        LowPressure = 4     -- Pressure is low than Median - 20%
    },
    definePressureConditions = {},
    isTemperatureInRange = {},
    run = {},
}

-- Check Conditions
function Controller:isTemperatureInRange()
    if Device.ExteranlTemperature < LOW_TEMPERATURE_LIMIT 
    or Device.ExteranlTemperature > HIGH_TEMPERATURE_LIMIT then
        return false    
    end
    if Device.GasPressure > EPSILON and
       (Device.GasTemperature < LOW_TEMPERATURE_LIMIT 
     or Device.GasTemperature > HIGH_TEMPERATURE_LIMIT) then
        return false    
    end
    return true
end
function Controller:definePressureConditions()
    if Device.GasPressure < EPSILON then return self.Conditions.NormalPressure end

    local co2PressureLimit = interp(CO2, Device.GasTemperature)
    local polPressureLimit = interp(Pol, Device.GasTemperature)
    
    if co2PressureLimit >= polPressureLimit then return self.Conditions.NeedClear end
    
    local diff = polPressureLimit -  co2PressureLimit
    local normalPressure = NORMAL_PRESSURE * diff + co2PressureLimit;
    local emergencyPressureThreshold = polPressureLimit - (polPressureLimit * EMERGENCY_PRESSURE_THRESHOLD)
    local highPressure = normalPressure + NORMAL_PRESSURE_DELTA * diff;
    local lowPressure = normalPressure - NORMAL_PRESSURE_DELTA * diff;

    if Device.GasPressure >= emergencyPressureThreshold then return self.Conditions.NeedClear end
    if Device.GasPressure >= highPressure then return self.Conditions.HighPressure end
    if Device.GasPressure <= lowPressure then return self.Conditions.LowPressure end

    return self.Conditions.NormalPressure
end

-- Base state
local function commonNext()
    if not Console:isPowerOn() then
        return State.PowerOff
    end
    if Device.Contaminated or Console:isClearing() then
        return State.Clearing
    end
    return nil
end

-- State PowerOff
Controller.StateMachine[State.PowerOff].enter = function(self)
    Device:powerOff()
    Console:setPower(false)
end
Controller.StateMachine[State.PowerOff].exit = function(self)
    Device:powerOn()
    Console:setPower(true)
end
Controller.StateMachine[State.PowerOff].next = function(self)
    if Console:isPowerOn() then
        return State.Idle
    end
    return State.PowerOff
end
-- State Idle
Controller.StateMachine[State.Idle].enter = function(self)
    Device:stopVent()
end
Controller.StateMachine[State.Idle].exit = function(self)
    -- Nothing
end
Controller.StateMachine[State.Idle].next = function(self)
    local next = commonNext()
    if next then return next end
    if Device:isFull() then return State.Full end
    if Console:isUp() then return State.Prepare end
    return State.Idle
end
-- State Prepare
Controller.StateMachine[State.Prepare].enter = function(self)
    if Device.GasPressure > EPSILON then
        self.StateMachine[State.Prepare].substate = ControllerSubstates.PrepareSubstate.ClearGas
        Device:runVentReverse()
    else
        self.StateMachine[State.Prepare].substate = ControllerSubstates.PrepareSubstate.Ready
        Device:stopVent()
    end
end
Controller.StateMachine[State.Prepare].exit = function(self)
    Device:stopVent()
end
Controller.StateMachine[State.Prepare].next = function(self)
    local next = commonNext()
    if next then return next end
    if self.StateMachine[State.Prepare].substate == ControllerSubstates.PrepareSubstate.Ready then
        if Device.GasPressure > EPSILON then
            self.StateMachine[State.Prepare].substate = ControllerSubstates.PrepareSubstate.ClearGas
            Device:runVentReverse()
            return State.Prepare
        end
        if Device:isFull() then return State.Full end
        if not Console:isUp() then return State.Idle end
        local conditions = Controller:definePressureConditions()
        if conditions ~= Controller.Conditions.NeedClear 
        and Controller:isTemperatureInRange() then return State.Operational end
    else
        if Device.GasPressure <= EPSILON then
            self.StateMachine[State.Prepare].substate = ControllerSubstates.PrepareSubstate.Ready
            Device:stopVent()
        end
    end
    return State.Prepare
end
-- State Operational
Controller.StateMachine[State.Operational].enter = function(self)
    self.StateMachine[State.Operational].substate = ControllerSubstates.OperationalSubstate.Run
    Device:runVent()
end
Controller.StateMachine[State.Operational].exit = function(self)
    Device:stopVent()
end
Controller.StateMachine[State.Operational].next = function(self)
    local next = commonNext()
    if next then return next end
    if Device:isFull() then return State.Prepare end -- We need to clear gas tank, then it will get to full state
    if not Console:isUp() then return State.Prepare end
    if not Controller:isTemperatureInRange() then return State.Prepare end
    local conditions = Controller:definePressureConditions()
    if conditions == Controller.Conditions.NeedClear then return State.Prepare end
    if self.StateMachine[State.Operational].substate == ControllerSubstates.OperationalSubstate.Run then
        if conditions == Controller.Conditions.HighPressure then 
            self.StateMachine[State.Operational].substate = ControllerSubstates.OperationalSubstate.Pause
            Device:stopVent()
        end
        -- In case we have a pressure but there are no condensation: need to clear gas
        if conditions == Controller.Conditions.NormalPressure 
        and Device.GasTubeLiquidVolume < EPSILON then return State.Clearing end
    end
    if self.StateMachine[State.Operational].substate == ControllerSubstates.OperationalSubstate.Pause then
        if conditions == Controller.Conditions.LowPressure then
            self.StateMachine[State.Operational].substate = ControllerSubstates.OperationalSubstate.Run
            Device:runVent()
        end
    end
    return State.Operational
end
-- State Full
Controller.StateMachine[State.Full].enter = function(self)
end
Controller.StateMachine[State.Full].exit = function(self)
end
Controller.StateMachine[State.Full].next = function(self)
    local next = commonNext()
    if next then return next end
    if Device:isFull() then return State.Full end
    return State.Idle
end
-- State Clearing
Controller.StateMachine[State.Clearing].enter = function(self)
    Console:setClearing(true)
    Device:startCleraing()
end
Controller.StateMachine[State.Clearing].exit = function(self)
    Console:setClearing(false)
    Device:stopCleraing()
end
Controller.StateMachine[State.Clearing].next = function(self)
    if Device.GasPressure < EPSILON
    and Device.GasTubeLiquidVolume < EPSILON
    and Device.LiquidPressure < EPSILON
    and Device.LiquidVolume < EPSILON
    then return State.Idle end 
    return State.Clearing
end
-- End State definitions

function Controller:init()
    -- empty
end

function Controller:defineNewState()
    local state = Controller.StateMachine[self.ControllerState]
    return state.next(self)
end

function Controller:run()
    if self.ControllerState ~= State.PowerOff then 
        Device:collectData()
    end
    local newState = Controller:defineNewState()
    if self.ControllerState ~= newState then
        local old = Controller.StateMachine[self.ControllerState]
        local new = Controller.StateMachine[newState]
        if old and old.exit then old.exit(self) end
        if new and new.enter then new.enter(self) end
        self.ControllerState = newState
    end
    if self.ControllerState ~= State.PowerOff then 
        Console:update(newState)
    end
end

-- Application initialisation
Device:init()
Console:init()
Controller:init()

-- Application run
function tick(dt)
    Controller:run()
end