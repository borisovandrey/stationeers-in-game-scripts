--terain-mars\traders\dish-control.lua
-- Investigation Lua script for Stationeers game
-- Intended to investigate how Trading Medium Satelite Dish works
-- Script conatins scanner that move a dish around 
-- and collects the list of awalable signals in the list   
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

local EPSILON = 0.001
local SCAN_HORISONTAL_STEP = 45 -- 0°
local SCAN_VERTICAL_STEP = 30   -- 30°

local TraderType = {
    Unknown             = -1,
    OreTrader           = -1374574351,
    AlloyTrader         =  54412100,
    HydroponicsTrader   = -1077922067,
    GasTrader           = -470575659,
    ConstructionTrader  =  175935584,
    LiquidTrader        =  135244511,
    FoodTrader          = -82964957,
    HardwareTrader      =  1325142661,
    ConsumablesTrader   = -1650376125,
    ApplianceTrader     = -1590718013,
    GeneticsTrader      = -188927486,
    RareItemsTrader     =  649254485, 
}

local TraderTypeNames = {
    [TraderType.Unknown]             = "Unknown",
    [TraderType.OreTrader]           = "Ore",
    [TraderType.AlloyTrader]         = "Alloy",
    [TraderType.HydroponicsTrader]   = "Hydroponics",
    [TraderType.GasTrader]           = "Gas",
    [TraderType.ConstructionTrader]  = "Construction",
    [TraderType.LiquidTrader]        = "Liquid",
    [TraderType.FoodTrader]          = "Food",
    [TraderType.HardwareTrader]      = "Hardware",
    [TraderType.ConsumablesTrader]   = "Consumables",
    [TraderType.ApplianceTrader]     = "Appliance",
    [TraderType.GeneticsTrader]      = "Genetics",
    [TraderType.RareItemsTrader]     = "RareItems", 
}

local function copyTable(src)
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = v
    end
    return setmetatable(dst, getmetatable(src))
end

local Signal = {
    Id = -1,                -- current signal id
    Strength = -1,          -- current signal strenght
    contactTypeId = TraderType.Unknown, -- one of the possible contact type id (see TraderType)
    contactSlotIndex = -1   -- contact slot index
}
Signal.__index = Signal

function Signal.new()
    return setmetatable({
        Id = Signal.Id,
        Strength = Signal.Strength,
        contactTypeId = Signal.contactTypeId,
        contactSlotIndex = Signal.contactSlotIndex,
    }, Signal)
end

function Signal:toDebugString()
    return "Signal ID:" .. self.Id ..
        " Strength:" .. string.format("%.2f", self.Strength) ..
        " Type:" .. (TraderTypeNames[self.contactTypeId] or "Unknown") ..
        " Slot:" .. self.contactSlotIndex
end

function Signal:print()
    print(self:toDebugString())
end

-- Container for signals used in signal list with version
local SignalData = {
    version = 0,            -- version of the signal - can be 0 or 1, used for detecting dead signals       
    signal = {},            -- signal data
    bestHorizontal = -1,    -- best known horizontal angle
    bestVertical = -1,      -- best vertical angle
}

function SignalData.new(version, signal, hor, vert)
    local self = {
        version = version,
        signal = copyTable(signal),
        bestHorizontal = hor, 
        bestVertical = vert
    }
    return self
end

Dish = {
    device = nil,
    vertical = -1,          -- vertical orientation
    horizontal = -1,        -- horizontal orientation
    isIdle = false,         -- dish is ready to ready for signals
    signal = Signal.new()   -- signal
}
Dish.__index = Dish

function Dish.new(name)
    local self = setmetatable({
        device = ic.find(name),
        vertical = Dish.vertical,
        horizontal = Dish.horizontal,
        isIdle = Dish.isIdle,
        signal = Signal.new(),
    }, Dish)
    if self.device == nil then
        print("Dish " .. name .. " not found")
    end
    return self
end

function Dish:readData()
    if self.device == nil then return end
    self.isIdle = ic.read_id(self.device, LT.Idle) == 1
    self.horizontal = ic.read_id(self.device, LT.Horizontal)
    self.vertical = ic.read_id(self.device, LT.Vertical)
    self.signal.Id = ic.read_id(self.device, LT.SignalID)
    self.signal.Strength = ic.read_id(self.device, LT.SignalStrength)
    self.signal.contactTypeId = ic.read_id(self.device, LT.ContactTypeId)
    self.signal.contactSlotIndex = ic.read_id(self.device, LT.ContactSlotIndex)
end

function Dish:setPosition(hor, vert)
    ic.write_id(self.device, LT.Horizontal, hor)
    ic.write_id(self.device, LT.Vertical, vert)
end

local SignalList = {
    currentVersion = 0,
    data = {}
}

function SignalList:update(signal, hor, vert)
    local found = self.data[signal.Id]
    if found ~= nil then
        found.version = self.currentVersion
        if signal.Strength > found.signal.Strength then
            print(
                "Update " ..
                signal:toDebugString() ..
                " pos:" ..
                string.format("%.2f", hor) ..
                ":" ..
                string.format("%.2f", vert)
            )
            found.signal = copyTable(signal)
            found.bestHorizontal = hor
            found.bestVertical = vert
        end
    else
        print("New " .. signal:toDebugString())
        self.data[signal.Id] = SignalData.new(self.currentVersion, signal, hor, vert)
    end
end

function SignalList:initScan()
    self.currentVersion = 1 - self.currentVersion 
end

function SignalList:removeOutdated()
    local keys = {}
    for key, value in pairs(self.data) do
        if value.version ~= self.currentVersion then
            print("Signal ID:" .. key .. " outdated")
            keys[key] = true
        end
    end
    for key, _ in pairs(keys) do
        self.data[key] = nil
    end
end

function SignalList:printCurrentState()
    for _, value in pairs(self.data) do
        print(
            value.signal:toDebugString() ..
            " H:" .. string.format("%.2f", value.bestHorizontal) .. "°" ..
            " V:" .. string.format("%.2f", value.bestVertical) .. "°"
        )
    end
end

local ScannerStates = {
    Initial   = 0,
    ScanCycle = 1,
    FinishCycle = 2,
}

Scanner = {
    dish = nil,
    StateMachine = {
        [ScannerStates.Initial] =    { enter = nil, exit = nil, next = nil },
        [ScannerStates.ScanCycle] =  { enter = nil, exit = nil, next = nil },
        [ScannerStates.FinishCycle] =  { enter = nil, exit = nil, next = nil },
    },
    currentState = ScannerStates.Initial
}
Scanner.__index = Scanner

function Scanner.new()
    local self = setmetatable({
        dish = Dish.new("scanner-dish"),
        currentState = ScannerStates.Initial,
    }, Scanner)
    self.StateMachine[self.currentState].enter(self)
    return self
end

-- State Initial
Scanner.StateMachine[ScannerStates.Initial].enter = function(self)
    self.dish:setPosition(0, 0)
end
Scanner.StateMachine[ScannerStates.Initial].exit = function(self)
    --Nothing to do
end
Scanner.StateMachine[ScannerStates.Initial].next = function(self)
    self.dish:readData()
    if self.dish.isIdle then return ScannerStates.ScanCycle else return ScannerStates.Initial end
end

-- State ScanCycle
Scanner.StateMachine[ScannerStates.ScanCycle].enter = function(self)
    self.dish:setPosition(0, SCAN_VERTICAL_STEP)
    SignalList:initScan()
end
Scanner.StateMachine[ScannerStates.ScanCycle].exit = function(self)
    --Nothing to do
end
Scanner.StateMachine[ScannerStates.ScanCycle].next = function(self)
    self.dish:readData()
    if self.dish.isIdle then 
        sleep(1)
        self.dish:readData()
        --print("Current position:" .. self.dish.horizontal .. ":" .. self.dish.vertical .. self.dish.signal:toDebugString())
        SignalList:update(self.dish.signal, self.dish.horizontal, self.dish.vertical)
        local newHorizontal = self.dish.horizontal + SCAN_HORISONTAL_STEP
        local newVertical = self.dish.vertical
        if newHorizontal >= 360 then
            newHorizontal = 0
            newVertical = newVertical + SCAN_VERTICAL_STEP
            if newVertical > 90 then
                return ScannerStates.FinishCycle -- Full cycle
            end
        end
        self.dish:setPosition(newHorizontal, newVertical)
    end
    return ScannerStates.ScanCycle
end

-- State Initial
Scanner.StateMachine[ScannerStates.FinishCycle].enter = function(self)
    SignalList:removeOutdated()
    print("End of cycle:")
    SignalList:printCurrentState()
end
Scanner.StateMachine[ScannerStates.FinishCycle].exit = function(self)
    --Nothing to do
end
Scanner.StateMachine[ScannerStates.FinishCycle].next = function(self)
    return ScannerStates.ScanCycle
end

function Scanner:defineNewState()
    local state = self.StateMachine[self.currentState]
    return state.next(self)
end

function Scanner:run()
    local newState = self:defineNewState()
    if self.currentState ~= newState then
        local old = self.StateMachine[self.currentState]
        local new = self.StateMachine[newState]
        if old and old.exit then old.exit(self) end
        if new and new.enter then new.enter(self) end
        self.currentState = newState
    end
end

local scanner = Scanner.new()

while true do
    scanner:run()
    sleep(1)
end
