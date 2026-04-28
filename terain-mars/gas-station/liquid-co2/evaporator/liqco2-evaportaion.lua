--terain-mars\gas-station\liquid-co2\evaporator\liqco2-evaportaion.lua
-- Controls the liquid CO2 evaporation chamber and pushes recovered gas into the CO2 line.
-- The controller runs a small state machine: Off, Idle, Fulling, Evaporating, and Clearing.
-- Idle waits for low gas pressure, then Fulling opens the liquid path until the chamber is half full.
-- Evaporating heats the chamber to the target temperature while the gas outlet remains active.
-- Clearing purges the remaining chamber gas down to the minimum pressure before returning to Idle.
-- Console devices provide auto mode, target pressure control, state text, and chamber fill display.
-- Startup recovery re-enters Off first, then resumes Evaporating or Clearing if chamber contents remain.
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

-- Definitions
local EPSILON = 0.001 
local EVAPORATION_PRESSURE_LIMIT = 4800
local EVAPORATION_PRESSURE_MIN = 1000
local EVAPORATION_TEMPERATURE_TARGET = -5.8
local CO2_GAS_AUTOMATION_MAX = 55000
local SINGLE_HEAT_FORLITRES = 10

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
    Power =   2,
    Persent = 1,
    Celsius = 4,
    String = 10,
    Litres = 12,
    Mol =    13,
    Pa =     14,
}

local State = {
    Off = 1,
    Idle = 2,
    Fulling = 3,
    Evaporating = 4,
    Clearing = 5
}

local StateName = {
    [1] = pack_ascii6("off"),
    [2] = pack_ascii6("idle"),
    [3] = pack_ascii6("fullup"),
    [4] = pack_ascii6("evapur"),
    [5] = pack_ascii6("clear"),
}

-- Device
local Device = {
    CO2Pressure = 0,
    LiquidLitres = 0,
    CameraPressure = 0,
    CameraTemperature = 0,
    CameraVolume = 0,
    CameraLitres = 0,
    NumberOfHeaters = 0,
    Sensors = {
        GasCO2 = ic.find("co2-sns"),                    -- CO2 gas sensor
        LiquidCO2 = ic.find("liqco2-tank-sns"),         -- Luiquid CO2 gas sensor
        EvaporationCameraSns = ic.find("liqco2-evap-sns")  -- Evaporation camera sensor
    },
    Actuators = {
        LiquidToCameraVent = ic.find("liqco2-evap-valve"),     
        LiquidToCameraPomp = ic.find("liqco2-evap-input-pump"),
        CameraHeater1 = ic.find("liqco2-evap-heat1"),
        CameraHeater2 = ic.find("liqco2-evap-heat2"),
        CameraToGasAbsorption = ic.find("liqco2-evap-purge"),
        CameraToGasPump = ic.find("liqco2-evap-exit-pump"),
    },
    switchOn = {},
    switchOff = {},
    init = {},
    collectData = {},
    starFilling = {},
    stopFilling = {},
    heatCamera = {},
    startAbsorption = {},
    stopAbsorption = {},
    startEvaporating = {},
    stopEvaporating = {}
}

function Device:init()
    -- Empty
end

function Device:switchOn()
    ic.write_id(self.Sensors.EvaporationCameraSns, LT.On, 1)
end

function Device:switchOff()
    ic.write_id(self.Actuators.LiquidToCameraVent, LT.On, 0)
    ic.write_id(self.Actuators.LiquidToCameraPomp, LT.On, 0)    
    ic.write_id(self.Actuators.CameraHeater1, LT.On, 0)    
    ic.write_id(self.Actuators.CameraHeater2, LT.On, 0) 
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.On, 0) 
    ic.write_id(self.Actuators.CameraToGasPump, LT.On, 0)
    ic.write_id(self.Sensors.EvaporationCameraSns, LT.On, 0)
end

function Device:collectData()
    self.CO2Pressure = ic.read_id(self.Sensors.GasCO2, LT.Pressure) or 0
    self.LiquidLitres = ic.read_id(self.Sensors.LiquidCO2, LT.VolumeOfLiquid) or 0
    self.CameraPressure = ic.read_id(self.Sensors.EvaporationCameraSns, LT.Pressure) or 0
    self.CameraTemperature = util.temp(ic.read_id(self.Sensors.EvaporationCameraSns, LT.Temperature) or 0, "K", "C")
    self.CameraVolume = ic.read_id(self.Sensors.EvaporationCameraSns, LT.Volume) or 0
    self.CameraLitres = ic.read_id(self.Sensors.EvaporationCameraSns, LT.VolumeOfLiquid) or 0
end

function Device:starFilling()
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.On, 0) 
    ic.write_id(self.Actuators.CameraToGasPump, LT.On, 0)
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.Setting, EVAPORATION_PRESSURE_LIMIT)
    yield()
    ic.write_id(self.Actuators.LiquidToCameraVent, LT.On, 1)
    ic.write_id(self.Actuators.LiquidToCameraPomp, LT.On, 1)   
end

function Device:stopFilling()
    ic.write_id(self.Actuators.LiquidToCameraPomp, LT.On, 0)
    yield()
    ic.write_id(self.Actuators.LiquidToCameraVent, LT.On, 0)
    ic.write_id(self.Actuators.CameraToGasPump, LT.On, 1)
    yield()
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.On, 1) 
end

function Device:startEvaporating()
    ic.write_id(self.Actuators.CameraToGasPump, LT.On, 1)
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.On, 1)
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.Setting, EVAPORATION_PRESSURE_LIMIT)
end

function Device:stopEvaporating()
    -- nothing is here
end

function Device:heatCamera(numberOfHeaters)
    if self.NumberOfHeaters == numberOfHeaters then return end
    self.NumberOfHeaters = numberOfHeaters
    local on1 = numberOfHeaters >= 1
    local on2 = numberOfHeaters >= 2
    ic.write_id(self.Actuators.CameraHeater1, LT.On, on1 and 1 or 0)    
    ic.write_id(self.Actuators.CameraHeater2, LT.On, on2 and 1 or 0) 
end

function Device:startAbsorption()
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.On, 1)
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.Setting, EVAPORATION_PRESSURE_MIN)
    ic.write_id(self.Actuators.CameraToGasPump, LT.On, 1)
end

function Device:stopAbsorption()
    ic.write_id(self.Actuators.CameraToGasAbsorption, LT.On, 0) 
    ic.write_id(self.Actuators.CameraToGasPump, LT.On, 0)
end

-- Console 
local Console = {
    ConsoleState  = State.Off,
    AutoSwitch = ic.find("evap-auto-sw"), -- Set auto mode
    StateDisplay = ic.find("evap-state-dsp"), -- Text display for current state
    CO2LimitSetter = ic.find("evap-co2-limit-set"), -- Setter for CO2 limit
    CO2LimitDisplay = ic.find("evap-co2-limit-dsp"), -- Display for CO2 limit
    LiquidProcentageDisplay = ic.find("evap-liquid-procents"), -- Procentage of liquid   
    init = {},
    switchAuto = {},
    isAuto = {},
    update = {},
    changeState ={},
    getCO2limit = {},
}

function Console:init()
    self:switchAuto(self:isAuto())
    ic.write_id(self.StateDisplay, LT.Color, Color.Gray)
    ic.write_id(self.StateDisplay, LT.Mode, DisplayMode.String)
    ic.write_id(self.StateDisplay, LT.Setting, StateName[self.ConsoleState])
    ic.write_id(self.LiquidProcentageDisplay, LT.Color, Color.Orange)
    ic.write_id(self.CO2LimitDisplay, LT.Color, Color.Yellow)
    ic.write_id(self.CO2LimitDisplay, LT.Mode, DisplayMode.Pa)
end

function Console:isAuto()
    return ic.read_id(self.AutoSwitch, LT.Setting) == 1
end

function Console:switchAuto(on)
    local pos = on and 1 or 0
    ic.write_id(self.StateDisplay, LT.On, pos)
    ic.write_id(self.LiquidProcentageDisplay, LT.On, pos )
    ic.write_id(self.CO2LimitDisplay, LT.On, pos)
    ic.write_id(self.AutoSwitch, LT.Color, on and Color.Green or Color.Red)
end

function Console:getCO2limit()
    local setting = ic.read_id(self.CO2LimitSetter, LT.Setting)
    return setting * CO2_GAS_AUTOMATION_MAX
end

function Console:updateDisplays()
    local procentage = 0
    if Device.CameraVolume > EPSILON then
        procentage = Device.CameraLitres / Device.CameraVolume
    end
    ic.write_id(self.LiquidProcentageDisplay, LT.Setting, procentage)
    local limit = self:getCO2limit()
    ic.write_id(self.CO2LimitDisplay, LT.Setting, limit * 1000)
end

function Console:changeState(newState)
    if newState == State.Off then
       self:switchAuto(false) 
    elseif self.ConsoleState == State.Off then
       self:switchAuto(true)
    end
    self.ConsoleState = newState
    ic.write_id(self.StateDisplay, LT.Setting, StateName[self.ConsoleState])
end

function Console:update(newState)
    if newState ~= self.ConsoleState then
        self:changeState(newState)
    end
    if self.ConsoleState ~= State.Off then
        self:updateDisplays()
    end
end

-- Controller
local Controller = {
    ControllerState = State.Off,
    StateMachine = {
        [State.Off] =         { enter = nil, exit = nil, next = nil },
        [State.Idle] =        { enter = nil, exit = nil, next = nil },
        [State.Fulling] =     { enter = nil, exit = nil, next = nil },
        [State.Evaporating] = { enter = nil, exit = nil, next = nil },
        [State.Clearing] =    { enter = nil, exit = nil, next = nil },
    },
    init = {},
    defineNewState = {},
    run = {},
    update = {},
}

-- State Off
Controller.StateMachine[State.Off].enter = function(self)
    Device:switchOff()
end
Controller.StateMachine[State.Off].exit = function(self)
    Device:switchOn()
    yield()
    Device:collectData()
end
Controller.StateMachine[State.Off].next = function(self)
    if Console:isAuto() then
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
    if not Console:isAuto() then
        return State.Off
    end
    if Device.CO2Pressure < Console:getCO2limit() then
        return State.Fulling
    end
    return State.Idle
end
-- State Fulling
Controller.StateMachine[State.Fulling].enter = function(self)
    Device:starFilling()
end
Controller.StateMachine[State.Fulling].exit = function(self)
    Device:stopFilling()
end
Controller.StateMachine[State.Fulling].next = function(self)
    if Device.CameraLitres >= (Device.CameraVolume / 2) then
        return State.Evaporating
    end
    return State.Fulling
end
-- State Evaporating
Controller.StateMachine[State.Evaporating].enter = function(self)
    Device:startEvaporating()
end
Controller.StateMachine[State.Evaporating].exit = function(self)
    Device:heatCamera(0)
    Device:stopEvaporating()    
end
Controller.StateMachine[State.Evaporating].next = function(self)
    if Device.CameraTemperature < EVAPORATION_TEMPERATURE_TARGET then
        local NumberOfHeater = (Device.CameraLitres > SINGLE_HEAT_FORLITRES) and 2 or 1
        Device:heatCamera(NumberOfHeater)
    else
        Device:heatCamera(0)
    end
    if Device.CameraLitres < EPSILON then
        return State.Clearing
    end
    return State.Evaporating
end
-- State Clearing
Controller.StateMachine[State.Clearing].enter = function(self)
    Device:startAbsorption()
end
Controller.StateMachine[State.Clearing].exit = function(self)
    Device:stopAbsorption()
end
Controller.StateMachine[State.Clearing].next = function(self)
    if Device.CameraPressure <= (EVAPORATION_PRESSURE_MIN + EPSILON) then
        if Console:isAuto() then return State.Idle 
        else return State.Off
        end
    end
    return State.Clearing
end

-- End State definitions
function Controller:init()
    Device:collectData()
    self.ControllerState = nil
    self:update(State.Off)
    if Device.CameraLitres > EPSILON then
        self:update(State.Evaporating)
    elseif Device.CameraPressure > EVAPORATION_PRESSURE_MIN then
        self:update(State.Clearing)
    end
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
    if self.ControllerState ~= State.Off then 
        Device:collectData()
    end
    local newState = Controller:defineNewState()
    if self.ControllerState ~= newState then
        self:update(newState)
    else
        Console:update(newState)
    end
end

-- Application initialisation
Device:init()
Console:init()
Controller:init()

-- Application run
while true do
    yield()
    Controller:run()
end
