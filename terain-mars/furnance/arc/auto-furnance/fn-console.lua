--terain-mars\furnance\arc\auto-furnance\fn-console.lua
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

-- Definitions
local EPSILON = 0.001
local PRESSURE_LIMIT_KPA = 47000
local PRESSURE_LIMIT_CANISTER_KPA = 18000

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
    Percent = 1,
    Celsius = 4,
    String = 10,
    Litres = 12,
    Mol = 13,
    Pa = 14,
}

local function clamp(x, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, x))
end

local Device = {
    Sensors = {
        FeedChamberSns = ic.find("***"),
        HotGasSns = ic.find("***"),
        ColdGasSns = ic.find("***"),
        CH4Sns = ic.find("***"),
        RecuperationSns = ic.find("***"),
        FurnaceSns = ic.find("***"),
        ExhaustGasSns = ic.find("***")
    },
    Actuators = {
        FeedChamberDirectValve = ic.find("***"),
        HotGasDirectValve = ic.find("***"),
        HotGasPressureRegulator = ic.find("***"),
        AutomaticHotPump = ic.find("***"),
        AutomaticColdPump = ic.find("***"),
        ExhaustGasExtractionPump = ic.find("***"),
        Furnace = ic.find("***"),
        CH4PressureRegulator = ic.find("***"),
        RecuperationToFeedPump = ic.find("***"),
        ExhaustGasToRecuperationPump = ic.find("***"),
        Mixer = ic.find("***"),
    }
}

function Device:runFurnaceInputPump(percentage)
    local safe = clamp(percentage, 0, 100);
    ic.write_id(self.Actuators.Furnace, LT.SettingInput, safe)
end

function Device:runFurnaceOutputPump(percentage)
    local safe = clamp(percentage, 0, 100);
    ic.write_id(self.Actuators.Furnace, LT.SettingOutput, safe)
end

local Direction = {
    Force = 0, 
    Back = 1
}

function Device:runFastPump(pump, percentage, direction)
    local safe = clamp(percentage, 0, 100);
    ic.write_id(pump, LT.Mode, direction) -- TODO: Check direction : possible wrong
    ic.write_id(pump, LT.Setting, safe)
    ic.write_id(pump, LT.On, safe ~= 0 and 1 or 0 )
end

function Device:runRecuperationToFeedPump(percentage)
    self:runFastPump(self.Actuators.RecuperationToFeedPump, percentage, Direction.Force) -- TODO: Check direction : possible wrong
end

function Device:runExhaustGasPump(percentage)
    self:runFastPump(self.Actuators.ExhaustGasExtractionPump, percentage, Direction.Force) -- TODO: Check direction : possible wrong
end

function Device:runExhaustGasToRecuperationPump(percentage)
    self:runFastPump(self.Actuators.ExhaustGasToRecuperationPump, percentage, Direction.Force) -- TODO: Check direction : possible wrong
end

function Device:getGasState(sensor)
    local temp = util.temp(ic.read_id(sensor, LT.Temperature) or 0, "K", "C")
    local pressure = ic.read_id(sensor, LT.Pressure) or 0
    return temp, pressure
end

function Device:setGasGate(gate, on)
    ic.write_id(gate, LT.On, on and 1 or 0)    
end

function Device:isOn(device)
    return ic.read_id(device, LT.On) == 1
end

local RecuperationToFeedMode
local HotGasPressureMode
local MixerMode
local CH4Mode
local DirectHotGasMode
local DirectFeedChamberMode
local ClearFurnaceMode
local ClearFeedChamberMode
local ClearExhaustGasMode
local ExhaustGasToRecuperationMode

local function generalEnter(base)
    if base.is_active then return false end 
    base.is_active = true
    for _, mode in ipairs(base.StopModes) do
        mode:exit()
    end
    return true
end

local function generalExit(base)
    if not base.is_active then return false end
    base.is_active = false
    return true
end

RecuperationToFeedMode = {
    is_active = false,
    StopModes = {}
}

function RecuperationToFeedMode:enter()
    if not generalEnter(self) then return end 
    Device:runRecuperationToFeedPump(50)
end

function RecuperationToFeedMode:exit()
    if not generalExit(self) then return end 
    Device:runRecuperationToFeedPump(0)
end

function RecuperationToFeedMode:perform()
    local _, pressureRecuperation = Device:getGasState(Device.Sensors.RecuperationSns)
    local _, pressureFeed = Device:getGasState(Device.Sensors.FeedChamberSns)
    return pressureRecuperation > EPSILON and pressureFeed < PRESSURE_LIMIT_KPA
end

HotGasPressureMode = {
    is_active = false,
    StopModes = {}
}

function HotGasPressureMode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.HotGasPressureRegulator, true)
end

function HotGasPressureMode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.HotGasPressureRegulator, false)
end

function HotGasPressureMode:perform()
    return true
end

MixerMode = {
    is_active = false,
    StopModes = {}
}

function MixerMode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.Mixer, true)
end

function MixerMode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.Mixer, false)
end

function MixerMode:perform()
    return true
end

CH4Mode = {
    is_active = false,
    StopModes = {}
}

function CH4Mode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.CH4PressureRegulator, true)
end

function CH4Mode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.CH4PressureRegulator, false)
end

function CH4Mode:perform()
    return true
end

DirectHotGasMode = {
    is_active = false,
    StopModes = {}
}

function DirectHotGasMode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.HotGasDirectValve, true)
end

function DirectHotGasMode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.HotGasDirectValve, false)
end

function DirectHotGasMode:perform()
    return true
end

DirectFeedChamberMode = {
    is_active = false,
    StopModes = {}
}

function DirectFeedChamberMode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.FeedChamberDirectValve, true)
end

function DirectFeedChamberMode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.FeedChamberDirectValve, false)
end

function DirectFeedChamberMode:perform()
    return true
end

ClearFurnaceMode = {
    is_active = false,
    StopModes = {}
}

function ClearFurnaceMode:enter()
    if not generalEnter(self) then return end 
    Device:runFurnaceOutputPump(100)
end

function ClearFurnaceMode:exit()
    if not generalExit(self) then return end
    Device:runFurnaceOutputPump(0)
end

function ClearFurnaceMode:perform()
    local _, pressure = Device:getGasState(Device.Sensors.FurnaceSns)
    return pressure > EPSILON
end

ClearFeedChamberMode = {
    is_active = false,
    StopModes = {}
}

function ClearFeedChamberMode:enter()
    if not generalEnter(self) then return end 
    DirectFeedChamberMode:enter()
    Device:runFurnaceInputPump(100)
end

function ClearFeedChamberMode:exit()
    if not generalExit(self) then return end
    DirectFeedChamberMode:exit()
    Device:runFurnaceInputPump(0)
end

function ClearFeedChamberMode:perform()
    local _, pressure = Device:getGasState(Device.Sensors.FeedChamberSns)
    return pressure > EPSILON
end

ClearExhaustGasMode = {
    is_active = false,
    StopModes = {}
}

function ClearExhaustGasMode:enter()
    if not generalEnter(self) then return end 
    Device:runExhaustGasPump(100)
end

function ClearExhaustGasMode:exit()
    if not generalExit(self) then return end
    Device:runExhaustGasPump(0)
end

function ClearExhaustGasMode:perform()
    local _, pressure = Device:getGasState(Device.Sensors.ExhaustGasSns)
    return pressure > EPSILON
end

ExhaustGasToRecuperationMode = {
    is_active = false,
    StopModes = {}
}

function ExhaustGasToRecuperationMode:enter()
    if not generalEnter(self) then return end 
    Device:runExhaustGasToRecuperationPump(10)
end

function ExhaustGasToRecuperationMode:exit()
    if not generalExit(self) then return end
    Device:runExhaustGasToRecuperationPump(0)
end

function ExhaustGasToRecuperationMode:perform()
    local _, pressureRecuperation = Device:getGasState(Device.Sensors.RecuperationSns)
    local _, pressureExhaustGas = Device:getGasState(Device.Sensors.ExhaustGasSns)
    return pressureExhaustGas > EPSILON and pressureRecuperation < PRESSURE_LIMIT_CANISTER_KPA
end

RecuperationToFeedMode.StopModes = {HotGasPressureMode, MixerMode, CH4Mode, DirectHotGasMode}
HotGasPressureMode.StopModes = {RecuperationToFeedMode, MixerMode, CH4Mode, DirectHotGasMode}
MixerMode.StopModes = {RecuperationToFeedMode, HotGasPressureMode, CH4Mode, DirectHotGasMode}
CH4Mode.StopModes = {RecuperationToFeedMode, HotGasPressureMode, MixerMode, DirectHotGasMode}
DirectHotGasMode.StopModes = {RecuperationToFeedMode, HotGasPressureMode, MixerMode, CH4Mode}
ClearFeedChamberMode.StopModes = {DirectHotGasMode, CH4Mode, MixerMode, HotGasPressureMode, RecuperationToFeedMode}
ExhaustGasToRecuperationMode.StopModes = {ClearExhaustGasMode}

local Console = {
    ModeSwitchers = {
        DirectFeedChamberSwitch = ic.find("***"),
        DirectHotGasSwitch = ic.find("***"),
        CH4Switch = ic.find("***"),
        MixerSwitch = ic.find("***"),
        HotGasPressureSwitch = ic.find("***"),
        RecuperationToFeedSwitch = ic.find("***"),
        ExhaustGasToRecuperationSwitch = ic.find("***"),
        ClearFeedChamberSwitch = ic.find("***"),
        ClearFurnaceSwitch = ic.find("***"),
        ClearExhaustGasSwitch = ic.find("***"),
    }
}

local Controller = {
    run = {},
}

function Controller:run()
end

function tick(dt)
    Controller:run()
end
