-- Furnace console controller for manual routing, purge actions, and UI sync.
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

-- Static device references used by the controller and mode handlers.
local Device = {
    Sensors = {
        FeedChamberSns = ic.find("fn-prepare-sns"),
        HotGasSns = ic.find("fn-hot-sns"),
        ColdGasSns = ic.find("fn-cold-sns"),
        CH4Sns = ic.find("fn-ch4-sns"),
        RecuperationSns = ic.find("fn-recup-sns"),
        FurnaceSns = ic.find("fn-device"),
        ExhaustGasSns = ic.find("fn-waste-sns")
    },
    Actuators = {
        FeedChamberDirectValve = ic.find("fn-prepare-vent"),
        HotGasDirectValve = ic.find("fn-hot-direct-valve"),
        HotGasPressureRegulator = ic.find("fn-hot-pr"),
        AutomaticHotPump = ic.find("fn-hot-pump"),
        AutomaticColdPump = ic.find("fn-cold-pump"),
        ExhaustGasExtractionPump = ic.find("fn-waste-out-pump"),
        Furnace = ic.find("fn-device"),
        CH4PressureRegulator = ic.find("fn-ch4-input-pr"),
        RecuperationToFeedPump = ic.find("fn-recup-to-prep-pump"),
        ExhaustGasToRecuperationPump = ic.find("fn-waste-to-recup-pump"),
        Mixer = ic.find("fn-mixer"),
    }
}

-- Writes furnace intake pump setting in percent.
function Device:runFurnaceInputPump(percentage)
    local safe = clamp(percentage, 0, 100);
    ic.write_id(self.Actuators.Furnace, LT.SettingInput, safe)
end

-- Writes furnace output pump setting in percent.
function Device:runFurnaceOutputPump(percentage)
    local safe = clamp(percentage, 0, 100);
    ic.write_id(self.Actuators.Furnace, LT.SettingOutput, safe)
end

local Direction = {
    Force = 0, 
    Back = 1
}

-- Shared helper for configurable directional pumps.
function Device:runFastPump(pump, percentage, direction)
    local safe = clamp(percentage, 0, 100);
    ic.write_id(pump, LT.Mode, direction) -- TODO: Check direction : possible wrong
    ic.write_id(pump, LT.Setting, safe)
    ic.write_id(pump, LT.On, safe ~= 0 and 1 or 0 )
end

function Device:runRecuperationToFeedPump(percentage)
    self:runFastPump(self.Actuators.RecuperationToFeedPump, percentage, Direction.Back) 
end

function Device:runExhaustGasPump(percentage)
    self:runFastPump(self.Actuators.ExhaustGasExtractionPump, percentage, Direction.Force)
end

function Device:runExhaustGasToRecuperationPump(percentage)
    self:runFastPump(self.Actuators.ExhaustGasToRecuperationPump, percentage, Direction.Back) -- TODO: Check direction : possible wrong
end

-- Reads a gas sensor and returns Celsius plus pressure.
function Device:getGasState(sensor)
    local temp = util.temp(ic.read_id(sensor, LT.Temperature) or 0, "K", "C")
    local pressure = ic.read_id(sensor, LT.Pressure) or 0
    return temp, pressure
end

-- Switches a binary gas device such as a regulator, valve, or mixer.
function Device:setGasGate(gate, on)
    ic.write_id(gate, LT.On, on and 1 or 0)    
end

-- Returns whether a device currently reports itself as enabled.
function Device:isOn(device)
    return ic.read_id(device, LT.On) == 1
end

-- Modes wrap individual furnace operations and their stop relationships.
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

-- Common enter path that also stops mutually exclusive modes.
local function generalEnter(base)
    if base.is_active then return false end 
    base.is_active = true
    for _, mode in ipairs(base.StopModes) do
        mode:exit()
    end
    return true
end

-- Common exit path for all mode tables.
local function generalExit(base)
    if not base.is_active then return false end
    base.is_active = false
    return true
end

-- Pumps recuperated gas back into the preparation chamber.
RecuperationToFeedMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function RecuperationToFeedMode:enter()
    if not generalEnter(self) then return end 
    if not self.externaly_activated then 
        Device:runRecuperationToFeedPump(50)
    end
    self.externaly_activated = false
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

function RecuperationToFeedMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.RecuperationToFeedPump)
end

-- Keeps the hot gas pressure regulator open while enabled.
HotGasPressureMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function HotGasPressureMode:enter()
    if not generalEnter(self) then return end 
    if not self.externaly_activated then 
        Device:setGasGate(Device.Actuators.HotGasPressureRegulator, true)
    end
    self.externaly_activated = false
end

function HotGasPressureMode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.HotGasPressureRegulator, false)
end

function HotGasPressureMode:perform()
    return true
end

function HotGasPressureMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.HotGasPressureRegulator)
end

-- Lets the mixer fill the feed chamber up to the dial pressure target.
MixerMode = {
    is_active = false,
    StopModes = {},
    mixerLimitkPa = 0,
    externaly_activated = false
}

function MixerMode:allowGasIn()
    if self.mixerLimitkPa == 0 then return false end
    local _, pressure = Device:getGasState(Device.Sensors.FeedChamberSns)
    return pressure < (self.mixerLimitkPa - EPSILON)
end 

function MixerMode:enter()
    if not generalEnter(self) then return end 
    if self:allowGasIn() then
        Device:setGasGate(Device.Actuators.Mixer, true)
    elseif self.externaly_activated then
        Device:setGasGate(Device.Actuators.Mixer, false)
    end
    self.externaly_activated = false
end

function MixerMode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.Mixer, false)
end

function MixerMode:perform()
    if self:allowGasIn() then
        Device:setGasGate(Device.Actuators.Mixer, true)
    else
        Device:setGasGate(Device.Actuators.Mixer, false)
    end
    return true
end

function MixerMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.Mixer)
end

-- Opens the CH4 feed regulator.
CH4Mode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function CH4Mode:enter()
    if not generalEnter(self) then return end 
    if not self.externaly_activated then 
        Device:setGasGate(Device.Actuators.CH4PressureRegulator, true)
    end
    self.externaly_activated = false
end

function CH4Mode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.CH4PressureRegulator, false)
end

function CH4Mode:perform()
    return true
end

function CH4Mode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.CH4PressureRegulator)
end

-- Opens the direct hot gas path to the furnace input.
DirectHotGasMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function DirectHotGasMode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.HotGasDirectValve, true)
end

function DirectHotGasMode:exit()
    if not generalExit(self) then return end
    if not self.externaly_activated then
        Device:setGasGate(Device.Actuators.HotGasDirectValve, false)
    end
    self.externaly_activated = false
end

function DirectHotGasMode:perform()
    return true
end

function DirectHotGasMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.HotGasDirectValve)
end

-- Opens the feed chamber direct valve.
DirectFeedChamberMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function DirectFeedChamberMode:enter()
    if not generalEnter(self) then return end 
    if not self.externaly_activated then
        Device:setGasGate(Device.Actuators.FeedChamberDirectValve, true)
    end
    self.externaly_activated = false
end

function DirectFeedChamberMode:exit()
    if not generalExit(self) then return end
    Device:setGasGate(Device.Actuators.FeedChamberDirectValve, false)
end

function DirectFeedChamberMode:perform()
    return true
end

function DirectFeedChamberMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.FeedChamberDirectValve)
end

-- Purges furnace contents through the furnace output pump.
ClearFurnaceMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function ClearFurnaceMode:enter()
    if not generalEnter(self) then return end 
    if not self.externaly_activated then
        Device:runFurnaceOutputPump(100)
    end
    self.externaly_activated = false
end

function ClearFurnaceMode:exit()
    if not generalExit(self) then return end
    Device:runFurnaceOutputPump(0)
end

function ClearFurnaceMode:perform()
    local _, pressure = Device:getGasState(Device.Sensors.FurnaceSns)
    return pressure > EPSILON
end

function ClearFurnaceMode:isFunctionalityExecuted()
    return false 
end

-- Pushes feed chamber contents directly into the furnace.
ClearFeedChamberMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function ClearFeedChamberMode:enter()
    if not generalEnter(self) then return end 
    DirectFeedChamberMode:enter()
    Device:runFurnaceInputPump(100)
    self.externaly_activated = false
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

function ClearFeedChamberMode:isFunctionalityExecuted()
    return false 
end

-- Purges waste gas into the exhaust extraction line.
ClearExhaustGasMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function ClearExhaustGasMode:enter()
    if not generalEnter(self) then return end 
    if not self.externaly_activated then
        Device:runExhaustGasPump(100)
    end
    self.externaly_activated = false
end

function ClearExhaustGasMode:exit()
    if not generalExit(self) then return end
    Device:runExhaustGasPump(0)
end

function ClearExhaustGasMode:perform()
    local _, pressure = Device:getGasState(Device.Sensors.ExhaustGasSns)
    return pressure > EPSILON
end

function ClearExhaustGasMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.ExhaustGasExtractionPump)
end

-- Moves waste gas from exhaust storage into recuperation storage.
ExhaustGasToRecuperationMode = {
    is_active = false,
    StopModes = {},
    externaly_activated = false
}

function ExhaustGasToRecuperationMode:enter()
    if not generalEnter(self) then return end 
    if not self.externaly_activated then
        Device:runExhaustGasToRecuperationPump(10)
    end
    self.externaly_activated = false
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

function ExhaustGasToRecuperationMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.ExhaustGasToRecuperationPump)
end

RecuperationToFeedMode.StopModes = {HotGasPressureMode, MixerMode, CH4Mode, DirectHotGasMode}
HotGasPressureMode.StopModes = {RecuperationToFeedMode, MixerMode, CH4Mode, DirectHotGasMode}
MixerMode.StopModes = {RecuperationToFeedMode, HotGasPressureMode, CH4Mode, DirectHotGasMode}
CH4Mode.StopModes = {RecuperationToFeedMode, HotGasPressureMode, MixerMode, DirectHotGasMode}
DirectHotGasMode.StopModes = {RecuperationToFeedMode, HotGasPressureMode, MixerMode, CH4Mode}
ClearFeedChamberMode.StopModes = {DirectHotGasMode, CH4Mode, MixerMode, HotGasPressureMode, RecuperationToFeedMode}
ExhaustGasToRecuperationMode.StopModes = {ClearExhaustGasMode}

-- Console switch definitions plus fast lookup from mode to switch device.
local Console = {
    Switches = {
        { 
            id = ic.find("fn-dir-feed-chamber-sw"),
            color = Color.Purple,
            mode = DirectFeedChamberMode
        },
        { 
            id = ic.find("fn-dir-hot-gas-sw"),
            color = Color.Red,
            mode = DirectHotGasMode
        },
        { 
            id = ic.find("fn-ch4-sw"),
            color = Color.Pink,
            mode = CH4Mode
        },
        { 
            id = ic.find("fn-mixer-sw"), 
            dial = ic.find("fn-mixer-pa-dial"),
            color = Color.Purple,
            mode = MixerMode
        },
        { 
            id = ic.find("fn-hot-pressure-sw"),
            color = Color.Red,
            mode = HotGasPressureMode
        },
        { 
            id = ic.find("fn-recup-to-feed-sw"),
            color = Color.Orange,
            mode = RecuperationToFeedMode
        },
        { 
            id = ic.find("fn-exchaust-to-recup-sw"),
            color = Color.Orange,
            mode = ExhaustGasToRecuperationMode
        },
        { 
            id = ic.find("fn-clear-feed-sw"),
            color = Color.Yellow,
            mode = ClearFeedChamberMode
        },
        { 
            id = ic.find("fn-clear-furnace-sw"),
            color = Color.Yellow,
            mode = ClearFurnaceMode
        },
        { 
            id = ic.find("fn-clear-exchaust-sw"),
            color = Color.Black,
            mode = ClearExhaustGasMode
        },
    },
    SwitchByMode = {}
}

-- Builds the mode-to-switch map used by the controller.
function Console:init()
    self.SwitchByMode = {}
    for _, sw in ipairs(self.Switches) do
        self.SwitchByMode[sw.mode] = sw
    end
end

-- Reads the mixer pressure target dial in kPa.
function Console:getMixerLimitkPa()
    local set = ic.read_id(self.SwitchByMode[MixerMode].dial, LT.Setting)
    return set * 1000
end

-- Colors switches to reflect their current active/inactive state.
function Console:updateSwitches()
    for _, sw in ipairs(self.Switches) do
        local on = ic.read_id(sw.id, LT.On) == 1
        ic.write_id(sw.id, LT.Color, on and sw.color or Color.Gray)
    end
end

-- Writes the requested state to a physical switch.
function Console:switch(sw, on)
    ic.write_id(sw.id, LT.Setting, on and 1 or 0)
end

-- Returns the requested state of a physical switch.
function Console:isSwitched(sw)
    return ic.read_id(sw.id, LT.Setting) == 1
end

-- Switches a mode by resolving its backing switch through the lookup table.
function Console:switchMode(mode, on)
    local sw = self.SwitchByMode[mode]
    if sw then
        self:switch(sw, on)
    end
end

-- Orchestrates console requests, conflict resolution, and mode execution.
local Controller = {
}

-- Detects devices that were enabled outside the console and mirrors them into UI state.
function Controller:checkModesExternalInitiated()
    for _, sw in ipairs(Console.Switches) do
        if sw.mode:isFunctionalityExecuted() and not sw.mode.is_active then
            sw.mode.externaly_activated = true  
            Console:switch(sw, true)
        end
    end
end

-- Enters a mode after clearing conflicting switches and stopping conflicting modes.
function Controller:enterMode(mode)
    for _, stopMode in ipairs(mode.StopModes) do
        Console:switchMode(stopMode, false)
        stopMode:exit()
    end
    mode:enter()
end

-- Applies switch requests to the mode state machines.
function Controller:updateModes()
    for _, sw in ipairs(Console.Switches) do
        if Console:isSwitched(sw) then  
            if not sw.mode.is_active then
                self:enterMode(sw.mode)
            else
                local continue = sw.mode:perform()
                if not continue then
                    sw.mode:exit()
                    Console:switch(sw, false)
                end
            end
        else 
            if sw.mode.is_active then
                sw.mode:exit()
            end  
        end 
    end
end

-- One controller cycle: refresh inputs, update modes, then refresh switch colors.
function Controller:run()
    MixerMode.mixerLimitkPa = Console:getMixerLimitkPa()
    self:checkModesExternalInitiated()
    self:updateModes()
    Console:updateSwitches()
end

-- Build console lookup tables before the main tick loop starts.
Console:init()

-- Stationeers callback entry point.
function tick(dt)
    Controller:run()
end
