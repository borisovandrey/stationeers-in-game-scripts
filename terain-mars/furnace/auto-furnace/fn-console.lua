-- Furnace console controller for manual routing, purge actions, and UI sync.
--terain-mars\furnance\auto-furnance\fn-console.lua
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

-- Definitions
local EPSILON = 0.0001
local PRESSURE_MAX_KPA = 60000
local PRESSURE_LIMIT_KPA = 53000
local PRESSURE_LIMIT_CANISTER_KPA = 18000
local TEMPERATURE_MAX_C = 3000
local MPA = 1000
local TEMPERATURE_COMPLETNESS_DIV_C = 30
local PRESSURE_COMPLETNESS_DIV_KPA = 200
local TEMPERATURE_DEFAULT_OFFSET_C = 35
local PRESSURE_DEFAULT_OFFSET_KPA = 250

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

local function sliderPositionForTarget(minValue, maxValue, targetValue)
    local span = maxValue - minValue
    if math.abs(span) < EPSILON then return 0 end
    return clamp((targetValue - minValue) / span, 0, 1)
end

-- Ingots
local Ingots = {
    Steel = {
        id = hash("ItemSteelIngot"),
        temperature = { 627, TEMPERATURE_MAX_C },
        pressure = { 1 * MPA, PRESSURE_MAX_KPA }
    },
    Invar = {
        id = hash("ItemInvarIngot"),
        temperature = { 927, 1227 },
        pressure = { 18 * MPA, 20 * MPA }
    },
    Solder = {
        id = hash("ItemSolderIngot"),
        temperature = { 76.8, 277 },
        pressure = { 1 * MPA, PRESSURE_MAX_KPA }
    },
    Constantan = {
        id = hash("ItemConstantanIngot"),
        temperature = { 727, TEMPERATURE_MAX_C },
        pressure = { 20 * MPA, PRESSURE_MAX_KPA }
    },
    Electrum = {
        id = hash("ItemElectrumIngot"),
        temperature = { 327, TEMPERATURE_MAX_C },
        pressure = { 800, 2.4 * MPA }
    },
    Waspaloy = {
        id = hash("ItemWaspaloyIngot"),
        temperature = { 127, 527 },
        pressure = { 50 * MPA, PRESSURE_MAX_KPA }
    },
    Stellite = {
        id = hash("ItemStelliteIngot"),
        temperature = { 1527, TEMPERATURE_MAX_C },
        pressure = { 10 * MPA, 20 * MPA }
    },
    Inconel = {
        id = hash("ItemInconelIngot"),
        temperature = { 327, TEMPERATURE_MAX_C },
        pressure = { 23.5 * MPA, 24 * MPA }
    },
    Hastelloy = {
        id = hash("ItemHastelloyIngot"),
        temperature = { 677, 727 },
        pressure = { 25 * MPA, 30 * MPA }
    },
    Astraloy = {
        id = hash("ItemAstroloyIngot"),
        temperature = { 727, TEMPERATURE_MAX_C },
        pressure = { 30 * MPA, 40 * MPA }
    },
}

local IngotList = {
    [1] = Ingots.Steel,
    [2] = Ingots.Invar,
    [3] = Ingots.Solder,
    [4] = Ingots.Constantan,
    [5] = Ingots.Electrum,
    [6] = Ingots.Waspaloy,
    [7] = Ingots.Stellite,
    [8] = Ingots.Inconel,
    [9] = Ingots.Hastelloy,
    [10] = Ingots.Astraloy,
}

-- Static device references used by the controller and mode handlers.
local Device = {
    Console = ic.find("fn-main-console"),
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

function Device:getFurnaceRecipe()
    return ic.read_id(self.Sensors.FurnaceSns, LT.RecipeHash)
end

function Device:isHotPumpOn()
    return (ic.read_id(self.Actuators.AutomaticHotPump, LT.Setting) or 0) > 0
end

function Device:isColdPumpOn()
    return (ic.read_id(self.Actuators.AutomaticColdPump, LT.Setting) or 0) > 0
end

local Direction = {
    Force = 0, 
    Back = 1
}

local ModeState = {
    Inactive = 0,
    ActiveInternal = 1,
    RequestedExternal = 2,
    ActiveExternal = 3,
    Suppressed = 4,
}

local ExitReason = {
    Normal = 0,
    Suppressed = 1,
}

local function isModeActive(mode)
    return mode.state == ModeState.ActiveInternal or mode.state == ModeState.ActiveExternal
end

local function isModeRequestedExternally(mode)
    return mode.state == ModeState.RequestedExternal
end

local function isModeOwnedExternally(mode)
    return mode.state == ModeState.ActiveExternal
end

local function isSuppressed(mode)
    return mode.state == ModeState.Suppressed
end

local function setInactive(mode)
    mode.state = ModeState.Inactive
end

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
local AutomaticMode
local DirectFeedChamberMode
local ClearFurnaceMode
local ClearFeedChamberMode
local ClearExhaustGasMode
local ExhaustGasToRecuperationMode


-- Common enter path that also stops mutually exclusive modes.
local function generalEnter(base)
    if isModeActive(base) then return false end
    base.state = isModeRequestedExternally(base) and ModeState.ActiveExternal or ModeState.ActiveInternal
    for _, mode in ipairs(base.StopModes) do
        mode:exit()
    end
    return true
end

-- Common exit path for all mode tables.
local function generalExit(base, reason)
    if not isModeActive(base) then return false end
    reason = reason or ExitReason.Normal
    base.state = reason == ExitReason.Suppressed and ModeState.Suppressed or ModeState.Inactive
    return true
end

-- Pumps recuperated gas back into the preparation chamber.
RecuperationToFeedMode = {
    state = ModeState.Inactive,
    StopModes = {},
}

function RecuperationToFeedMode:enter()
    if not generalEnter(self) then return end 
    if not isModeOwnedExternally(self) then
        Device:runRecuperationToFeedPump(50)
    end
end

function RecuperationToFeedMode:exit(reason)
    if not generalExit(self, reason) then return end
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
    state = ModeState.Inactive,
    StopModes = {},
}

function HotGasPressureMode:enter()
    if not generalEnter(self) then return end 
    if not isModeOwnedExternally(self) then
        Device:setGasGate(Device.Actuators.HotGasPressureRegulator, true)
    end
end

function HotGasPressureMode:exit(reason)
    if not generalExit(self, reason) then return end
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
    state = ModeState.Inactive,
    StopModes = {},
    mixerLimitkPa = 0,
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
    elseif isModeOwnedExternally(self) then
        Device:setGasGate(Device.Actuators.Mixer, false)
    end
end

function MixerMode:exit(reason)
    if not generalExit(self, reason) then return end
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
    state = ModeState.Inactive,
    StopModes = {},
}

function CH4Mode:enter()
    if not generalEnter(self) then return end 
    if not isModeOwnedExternally(self) then
        Device:setGasGate(Device.Actuators.CH4PressureRegulator, true)
    end
end

function CH4Mode:exit(reason)
    if not generalExit(self, reason) then return end
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
    state = ModeState.Inactive,
    StopModes = {},
}

function DirectHotGasMode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.HotGasDirectValve, true)
end

function DirectHotGasMode:exit(reason)
    if not generalExit(self, reason) then return end
    Device:setGasGate(Device.Actuators.HotGasDirectValve, false)
end

function DirectHotGasMode:perform()
    return true
end

function DirectHotGasMode:isFunctionalityExecuted()
    return Device:isOn(Device.Actuators.HotGasDirectValve)
end

-- Tracks automatic furnace control state without directly driving devices.
AutomaticMode = {
    state = ModeState.Inactive,
    StopModes = {},
}

function AutomaticMode:enter()
    if not generalEnter(self) then return end
end

function AutomaticMode:exit(reason)
    if not generalExit(self, reason) then return end
end

function AutomaticMode:perform()
    return true
end

function AutomaticMode:isFunctionalityExecuted()
    return false
end

-- Opens the feed chamber direct valve.
DirectFeedChamberMode = {
    state = ModeState.Inactive,
    StopModes = {},
}

function DirectFeedChamberMode:enter()
    if not generalEnter(self) then return end 
    if not isModeOwnedExternally(self) then
        Device:setGasGate(Device.Actuators.FeedChamberDirectValve, true)
    end
end

function DirectFeedChamberMode:exit(reason)
    if not generalExit(self, reason) then return end
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
    state = ModeState.Inactive,
    StopModes = {},
}

function ClearFurnaceMode:enter()
    if not generalEnter(self) then return end 
    if not isModeOwnedExternally(self) then
        Device:runFurnaceOutputPump(100)
    end
end

function ClearFurnaceMode:exit(reason)
    if not generalExit(self, reason) then return end
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
    state = ModeState.Inactive,
    StopModes = {},
}

function ClearFeedChamberMode:enter()
    if not generalEnter(self) then return end 
    Device:setGasGate(Device.Actuators.FeedChamberDirectValve, true)
    Device:runFurnaceInputPump(100)
end

function ClearFeedChamberMode:exit(reason)
    if not generalExit(self, reason) then return end
    DirectFeedChamberMode:exit(reason)
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
    state = ModeState.Inactive,
    StopModes = {},
}

function ClearExhaustGasMode:enter()
    if not generalEnter(self) then return end 
    if not isModeOwnedExternally(self) then
        Device:runExhaustGasPump(100)
    end
end

function ClearExhaustGasMode:exit(reason)
    if not generalExit(self, reason) then return end
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
    state = ModeState.Inactive,
    StopModes = {},
}

function ExhaustGasToRecuperationMode:enter()
    if not generalEnter(self) then return end 
    if not isModeOwnedExternally(self) then
        Device:runExhaustGasToRecuperationPump(50)
    end
end

function ExhaustGasToRecuperationMode:exit(reason)
    if not generalExit(self, reason) then return end
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
AutomaticMode.StopModes = {DirectFeedChamberMode, ClearFurnaceMode, ClearFeedChamberMode}
DirectFeedChamberMode.StopModes = {AutomaticMode}
ClearFurnaceMode.StopModes = {AutomaticMode}
ClearFeedChamberMode.StopModes = {AutomaticMode, DirectHotGasMode, CH4Mode, MixerMode, HotGasPressureMode, RecuperationToFeedMode}
ExhaustGasToRecuperationMode.StopModes = {ClearExhaustGasMode}

-- Console switch definitions plus fast lookup from mode to switch device.
local Console = {
    Switches = {
        {
            id = ic.find("fn-automatic-sw"),
            color = Color.Green,
            mode = AutomaticMode
        },
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
    SwitchByMode = {},
    AutomaticPannel = {
        active = false,
        IngotSelector = ic.find("fn-auto-dial"),
        TemperatureSlider = ic.find("fn-auto-temp-sld"),
        PressureSlider = ic.find("fn-auto-press-sld"),
        TemperatureMinDsp = ic.find("fn-auto-temp-min-dsp"),
        TemperatureToDsp = ic.find("fn-auto-temp-target-dsp"),
        TemperatureMaxDsp = ic.find("fn-auto-temp-max-dsp"),
        PressureMinDsp = ic.find("fn-auto-press-min-dsp"),
        PressureToDsp = ic.find("fn-auto-press-target-dsp"),
        PressureMaxDsp = ic.find("fn-auto-press-max-dsp"),
        SelectedIngotHashMem = ic.find("fn-auto-sel-ing-mem"),
        SelectedIngotHashDsp = ic.find("fn-auto-sel-ing-dsp"),
        SelectedIngotHash = 0,
        TemperatureTarget = 0,
        PressureTarget = 0,
        TemeperatureSliderPos = 0,
        PressureSliderPos = 0,
        SelectedTemperatureMem = ic.find("fn-auto-temperature-mem"),
        SelectedPressureMem = ic.find("fn-auto-pressure-mem"),
        FurnaceTemperatureDsp = ic.find("fn-auto-furnace-temp-dsp"),
        FurnacePressureDsp = ic.find("fn-auto-furnace-press-dsp"),
        FurnaceTemperatureMem = ic.find("fn-auto-furnace-temp-mem"),
        FurnacePressureMem = ic.find("fn-auto-furnace-press-mem"),
        TemperatureErrorDsp = ic.find("fn-auto-temp-err-dsp"),
        PressureErrorDsp = ic.find("fn-auto-press-err-dsp"),
        AutoStartSwitch = ic.find("fn-auto-start"),
        isAutoActive = false,
        SmallLed = ic.find("fn-auto-small-led"),
        BigLed = ic.find("fn-auto-big-led"),
    },
    General = {
        InFurnaceHashReadyMem = ic.find("fn-infurnace-hash-mem")
    }
}

function Console.AutomaticPannel:init()
    ic.write_id(self.TemperatureMinDsp, LT.Mode, DisplayMode.Celsius)
    ic.write_id(self.TemperatureToDsp, LT.Mode, DisplayMode.Celsius) 
    ic.write_id(self.TemperatureMaxDsp, LT.Mode, DisplayMode.Celsius) 
    ic.write_id(self.TemperatureMinDsp, LT.Color, Color.Pink)
    ic.write_id(self.TemperatureToDsp, LT.Color, Color.Red) 
    ic.write_id(self.TemperatureMaxDsp, LT.Color, Color.Purple) 

    ic.write_id(self.PressureMinDsp, LT.Mode, DisplayMode.Pa)
    ic.write_id(self.PressureToDsp, LT.Mode, DisplayMode.Pa) 
    ic.write_id(self.PressureMaxDsp, LT.Mode, DisplayMode.Pa) 
    ic.write_id(self.PressureMinDsp, LT.Color, Color.Yellow)
    ic.write_id(self.PressureToDsp, LT.Color, Color.Orange) 
    ic.write_id(self.PressureMaxDsp, LT.Color, Color.Brown) 
    ic.write_id(self.SelectedIngotHashMem, LT.Setting, 0)
    ic.write_id(self.TemperatureErrorDsp, LT.Mode, DisplayMode.Celsius)
    ic.write_id(self.PressureErrorDsp, LT.Mode, DisplayMode.Pa)
    ic.write_id(self.TemperatureErrorDsp, LT.Color, Color.Red)
    ic.write_id(self.PressureErrorDsp, LT.Color, Color.Yellow)

    ic.write_id(self.AutoStartSwitch, LT.On, 0)
    self:clearAutoStart()
end

-- Builds the mode-to-switch map used by the controller.
function Console:init()
    self.SwitchByMode = {}
    for _, sw in ipairs(self.Switches) do
        self.SwitchByMode[sw.mode] = sw
    end
    self.AutomaticPannel:init()
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
    ic.write_id(sw.id, LT.On, on and 1 or 0)
end

-- Returns the requested state of a physical switch.
function Console:isSwitched(sw)
    return ic.read_id(sw.id, LT.On) == 1
end

-- Switches a mode by resolving its backing switch through the lookup table.
function Console:switchMode(mode, on)
    local sw = self.SwitchByMode[mode]
    if sw then
        self:switch(sw, on)
    end
end

function Console.AutomaticPannel:clearAutoStart()
    ic.write_id(self.AutoStartSwitch, LT.On, 0) 
    self.isAutoActive = false
    ic.write_id(self.AutoStartSwitch, LT.Color, Color.Gray)
    ic.write_id(self.TemperatureErrorDsp, LT.Setting, 0)
    ic.write_id(self.PressureErrorDsp, LT.Setting, 0)
    ic.write_id(self.FurnaceTemperatureMem, LT.Setting, 0)
    ic.write_id(self.FurnacePressureMem, LT.Setting, 0)
    ic.write_id(self.SmallLed, LT.Color, Color.Gray)
    ic.write_id(self.BigLed, LT.Color, Color.Gray)
    ic.write_id(self.SmallLed, LT.On, 0)
    ic.write_id(self.BigLed, LT.On, 0)
end

function Console.AutomaticPannel:checkAutoStarted()
    local sw = ic.read_id(self.AutoStartSwitch, LT.On) == 1
    if sw ~= self.isAutoActive then
        if(not sw) then 
            self:clearAutoStart()
        else
            self.isAutoActive = true
            ic.write_id(self.AutoStartSwitch, LT.Color, Color.Blue)
            ic.write_id(self.TemperatureErrorDsp, LT.Setting, 0)
            ic.write_id(self.PressureErrorDsp, LT.Setting, 0)
            ic.write_id(self.FurnaceTemperatureMem, LT.Setting, 0)
            ic.write_id(self.FurnacePressureMem, LT.Setting, 0)
            ic.write_id(self.SmallLed, LT.On, 1)
            ic.write_id(self.BigLed, LT.On, 1)
        end
    end
end

function Console.AutomaticPannel:activate(on)
    if self.active == on then return end
    self.active = on
    ic.write_id(self.TemperatureMinDsp, LT.On, on and 1 or 0)
    ic.write_id(self.TemperatureToDsp, LT.On, on and 1 or 0) 
    ic.write_id(self.TemperatureMaxDsp, LT.On, on and 1 or 0) 
    ic.write_id(self.PressureMinDsp, LT.On, on and 1 or 0)
    ic.write_id(self.PressureToDsp, LT.On, on and 1 or 0) 
    ic.write_id(self.PressureMaxDsp, LT.On, on and 1 or 0)   
    ic.write_id(self.SelectedIngotHashDsp, LT.On, on and 1 or 0)
    
    ic.write_id(self.FurnacePressureDsp, LT.On, on and 1 or 0)
    ic.write_id(self.FurnaceTemperatureDsp, LT.On, on and 1 or 0)
    ic.write_id(self.TemperatureErrorDsp, LT.On, on and 1 or 0)
    ic.write_id(self.PressureErrorDsp, LT.On, on and 1 or 0)

    self:clearAutoStart() -- Reset auto-start request when panel mode toggles
end

function Console.AutomaticPannel:isAutoStarted()
    return self.isAutoActive 
end 

function Console.AutomaticPannel:lightsUpdate(deltaTemp, deltaPressure)
    local hot = Device:isHotPumpOn()
    local cool = Device:isColdPumpOn()
    local hash = Device:getFurnaceRecipe() or 0
    local color = Color.Gray
    local isErrorSmall = math.abs(deltaTemp) < TEMPERATURE_COMPLETNESS_DIV_C
                     and math.abs(deltaPressure) < PRESSURE_COMPLETNESS_DIV_KPA
    local isComplete = isErrorSmall and (hash == self.SelectedIngotHash)

    if isComplete then color = Color.Green
    elseif isErrorSmall then color = Color.Orange
    elseif hot then color = Color.Red
    elseif cool then color = Color.Blue
    end
    ic.write_id(self.SmallLed, LT.Color, color)
    ic.write_id(self.BigLed, LT.Color, color)
end

function Console.AutomaticPannel:update()
    local dial = clamp(ic.read_id(self.IngotSelector, LT.Setting) + 1, 1, #IngotList)
    local ingot = IngotList[dial]
    if ingot.id ~= self.SelectedIngotHash then
        self.SelectedIngotHash = ingot.id
        local defaultTempTarget = clamp(
            ingot.temperature[1] + TEMPERATURE_DEFAULT_OFFSET_C,
            ingot.temperature[1],
            ingot.temperature[2]
        )
        local defaultPressureTarget = clamp(
            ingot.pressure[1] + PRESSURE_DEFAULT_OFFSET_KPA,
            ingot.pressure[1],
            ingot.pressure[2]
        )
        self.TemeperatureSliderPos = sliderPositionForTarget(
            ingot.temperature[1],
            ingot.temperature[2],
            defaultTempTarget
        )
        self.PressureSliderPos = sliderPositionForTarget(
            ingot.pressure[1],
            ingot.pressure[2],
            defaultPressureTarget
        )
        ic.write_id(self.SelectedIngotHashMem, LT.Setting, self.SelectedIngotHash)
        ic.write_id(self.TemperatureMinDsp, LT.Setting, ingot.temperature[1])
        ic.write_id(self.TemperatureMaxDsp, LT.Setting, ingot.temperature[2]) 
        ic.write_id(self.PressureMinDsp, LT.Setting, ingot.pressure[1] * 1000)
        ic.write_id(self.PressureMaxDsp, LT.Setting, ingot.pressure[2] * 1000)
        ic.write_id(self.TemperatureSlider, LT.Setting, self.TemeperatureSliderPos)
        ic.write_id(self.PressureSlider, LT.Setting, self.PressureSliderPos)
    end

    local temperatureSlider = ic.read_id(self.TemperatureSlider, LT.Setting)
    local pressureSlider = ic.read_id(self.PressureSlider, LT.Setting)

    if self.TemeperatureSliderPos ~= temperatureSlider then
        self.TemeperatureSliderPos = temperatureSlider
        self.TemperatureTarget = ingot.temperature[1] + self.TemeperatureSliderPos * (ingot.temperature[2] - ingot.temperature[1])
        ic.write_id(self.TemperatureToDsp, LT.Setting, self.TemperatureTarget)
        ic.write_id(self.SelectedTemperatureMem, LT.Setting, self.TemperatureTarget)
    end
    if self.PressureSliderPos ~= pressureSlider then
        self.PressureSliderPos = pressureSlider
        self.PressureTarget = ingot.pressure[1] + self.PressureSliderPos * (ingot.pressure[2] - ingot.pressure[1])
        ic.write_id(self.PressureToDsp, LT.Setting, self.PressureTarget * 1000)
        ic.write_id(self.SelectedPressureMem, LT.Setting, self.PressureTarget)
    end

    self:checkAutoStarted()
    -- Update tempearture and error
    if self:isAutoStarted() then
        local temp, press = Device:getGasState(Device.Sensors.FurnaceSns)
        local deltaTemp = temp - self.TemperatureTarget
        local deltaPressure = press - self.PressureTarget
        ic.write_id(self.TemperatureErrorDsp, LT.Setting, deltaTemp)
        ic.write_id(self.PressureErrorDsp, LT.Setting, deltaPressure * 1000)
        ic.write_id(self.FurnaceTemperatureMem, LT.Setting, temp)
        ic.write_id(self.FurnacePressureMem, LT.Setting, press)
        self:lightsUpdate(deltaTemp, deltaPressure)
    end
end

function Console:updateAutomatic(on)
    self.AutomaticPannel:activate(on)
    if on then 
        self.AutomaticPannel:update()
    end
end

function Console:updateInFurnaceHash()
    local hsh = Device:getFurnaceRecipe() or 0
    ic.write_id(self.General.InFurnaceHashReadyMem, LT.Setting, hsh)
end

-- Orchestrates console requests, conflict resolution, and mode execution.
local Controller = {
}

-- Detects devices that were enabled outside the console and mirrors them into UI state.
function Controller:checkModesExternalInitiated()
    for _, sw in ipairs(Console.Switches) do
        if sw.mode:isFunctionalityExecuted() and sw.mode.state == ModeState.Inactive then
            sw.mode.state = ModeState.RequestedExternal
            Console:switch(sw, true)
        end
    end
end

-- Enters a mode after clearing conflicting switches and stopping conflicting modes.
function Controller:enterMode(mode)
    for _, stopMode in ipairs(mode.StopModes) do
        Console:switchMode(stopMode, false)
        stopMode:exit(ExitReason.Suppressed)
    end
    mode:enter()
end

-- Applies switch requests to the mode state machines.
function Controller:updateModes()
    for _, sw in ipairs(Console.Switches) do
        if Console:isSwitched(sw) then  
            if not isModeActive(sw.mode) then
                if isSuppressed(sw.mode) then
                    Console:switch(sw, false)
                    setInactive (sw.mode)
                else
                    self:enterMode(sw.mode)
                end
            else
                local continue = sw.mode:perform()
                if not continue then
                    sw.mode:exit()
                    Console:switch(sw, false)
                end
            end
        else 
            if isSuppressed(sw.mode) then 
                setInactive(sw.mode)
            elseif isModeActive(sw.mode) 
                then sw.mode:exit()
            end 
        end
    end
end

-- One controller cycle: refresh inputs, update modes, then refresh switch colors.
function Controller:run()
    if not Device:isOn(Device.Console) then return end
    MixerMode.mixerLimitkPa = Console:getMixerLimitkPa()
    self:checkModesExternalInitiated()
    self:updateModes()
    Console:updateSwitches()
    Console:updateAutomatic(isModeActive(AutomaticMode))
    Console:updateInFurnaceHash()
end

-- Build console lookup tables before the main tick loop starts.
Console:init()

-- Stationeers callback entry point.
function tick(dt)
    Controller:run()
end
