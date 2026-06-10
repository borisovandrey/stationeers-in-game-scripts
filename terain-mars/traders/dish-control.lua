--terain-mars\traders\dish-control.lua
-- Investigation Lua script for Stationeers game
-- Intended to investigate how Trading Medium Satelite Dish works
-- Script conatins scanner that move a dish around 
-- and collects the list of awalable signals in the list   
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

local EPSILON = 0.001
local SCAN_HORISONTAL_STEP = 10 -- 10°
local SCAN_VERTICAL_STEP = 20   -- 20°
local READ_ATTEMPTS_LIMIT = 4 -- Ammount of reads the data if the signal strength is -1

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
    Strength = -1,          -- current signal strength
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

local function buildScanPlan(hStart,         -- horizontal sector start
                             hEnd,           -- horizontal sector end
                             vMin,           -- vertical min, zenith
                             vMax,           -- vertical max, near horizon
                             vStep,          -- vertical step
                             desiredHStep    -- desired horizontal resolution near horizon
                            )
    local function degToRad(deg)
        return deg * math.pi / 180.0
    end
    local plan = {}
    local sectorWidth = hEnd - hStart
    local rowIndex = 0

    local v = vMin
    while v <= vMax do
        local sinv = math.sin(degToRad(v))

        -- Near zenith, horizontal direction has almost no meaning.
        -- Therefore scan only one horizontal point.
        local count = 1
        if sinv > 0.01 then
            count = math.ceil(sectorWidth * sinv / desiredHStep)
            if count < 1 then
                count = 1
            end
        end

        local row = {}
        for i = 0, count - 1 do
            -- Cell-center sampling, avoids sector-border overlap.
            local h = hStart + sectorWidth * (i + 0.5) / count
            table.insert(row, { h = h, v = v })
        end

        -- Serpentine order: every second row is reversed.
        if rowIndex % 2 == 1 then
            local reversed = {}
            for i = #row, 1, -1 do
                table.insert(reversed, row[i])
            end
            row = reversed
        end

        for i = 1, #row do
            table.insert(plan, row[i])
        end

        rowIndex = rowIndex + 1
        v = v + vStep
    end

    return plan
end

local ScannerStates = {
    Initial   = 0,
    ScanCycle = 1,
    FinishCycle = 2,
}

Scanner = {
    dish = nil,
    readAttempts = 0,
    nextIndex = 1,
    plan = {},
    step = 1,
    shouldContinue = false,
    StateMachine = {
        [ScannerStates.Initial] =    { enter = nil, exit = nil, next = nil },
        [ScannerStates.ScanCycle] =  { enter = nil, exit = nil, next = nil, },
        [ScannerStates.FinishCycle] =  { enter = nil, exit = nil, next = nil },
    },
    currentState = ScannerStates.Initial
}
Scanner.__index = Scanner

function Scanner.new(id,             -- scanner id
                     hStart,         -- horizontal sector start
                     hEnd,           -- horizontal sector end
                     vMin,           -- vertical min, zenith
                     vMax,           -- vertical max, near horizon
                     vStep,          -- vertical step
                     desiredHStep    -- desired horizontal resolution near horizon
                    )
    local self = setmetatable({
        dish = Dish.new("scanner-dish"..id),
        currentState = ScannerStates.Initial,
        plan = buildScanPlan(hStart, hEnd, vMin, vMax, vStep, desiredHStep),
        nextIndex = 1,
    }, Scanner)
    self.StateMachine[self.currentState].enter(self)
    return self
end

-- State Initial
Scanner.StateMachine[ScannerStates.Initial].enter = function(self)
    if #self.plan == 0 then return end
    self.nextIndex = 1
    self.step = 1
    self.dish:setPosition(self.plan[self.nextIndex].h, self.plan[self.nextIndex].v)
    self.nextIndex = self.nextIndex + 1
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
    self.readAttempts = 0
end
Scanner.StateMachine[ScannerStates.ScanCycle].exit = function(self)
    self.step = -self.step
end
Scanner.StateMachine[ScannerStates.ScanCycle].next = function(self)
    if #self.plan == 0 then return ScannerStates.FinishCycle end
    self.dish:readData()
    if self.dish.isIdle then 
        if self.dish.signal.Strength == -1 then
            if self.readAttempts < READ_ATTEMPTS_LIMIT then
                self.readAttempts = self.readAttempts + 1
                return ScannerStates.ScanCycle
            end
        end
        self.readAttempts = 0
        --print("Current position:" .. self.dish.horizontal .. ":" .. self.dish.vertical .. self.dish.signal:toDebugString())
        SignalList:update(self.dish.signal, self.dish.horizontal, self.dish.vertical)
        if #self.plan < 2 then
            return ScannerStates.FinishCycle -- Full cycle
        end
        if self.nextIndex > #self.plan then
            self.nextIndex = #self.plan - 1
            return ScannerStates.FinishCycle -- Full cycle
        end
        if self.nextIndex < 1 then
            self.nextIndex = 2
            return ScannerStates.FinishCycle -- Full cycle
        end

        local newHorizontal = self.plan[self.nextIndex].h
        local newVertical = self.plan[self.nextIndex].v
        self.dish:setPosition(newHorizontal, newVertical)
        self.nextIndex = self.nextIndex + self.step
    end
    return ScannerStates.ScanCycle
end

-- State Initial
Scanner.StateMachine[ScannerStates.FinishCycle].enter = function(self)
    self.shouldContinue = false 
end
Scanner.StateMachine[ScannerStates.FinishCycle].exit = function(self)
    --Nothing to do
end
Scanner.StateMachine[ScannerStates.FinishCycle].next = function(self)
    if self.shouldContinue then return ScannerStates.ScanCycle else return ScannerStates.FinishCycle end
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

function Scanner:cycleFinsihed()
    return self.currentState == ScannerStates.FinishCycle
end

function Scanner:continue()
    self.shouldContinue = true
end

local scanner1 = Scanner.new(1, 0, 90, 0, 80, SCAN_VERTICAL_STEP, SCAN_HORISONTAL_STEP)
local scanner2 = Scanner.new(2, 90, 180, 0, 80, SCAN_VERTICAL_STEP, SCAN_HORISONTAL_STEP)
local scanner3 = Scanner.new(3, 180, 270, 0, 80, SCAN_VERTICAL_STEP, SCAN_HORISONTAL_STEP)
local scanner4 = Scanner.new(4, 270, 360, 0, 80, SCAN_VERTICAL_STEP, SCAN_HORISONTAL_STEP)

-- Application run
function tick(dt)
    scanner1:run()
    scanner2:run()
    scanner3:run()
    scanner4:run()
    if scanner1:cycleFinsihed() and
       scanner2:cycleFinsihed() and
       scanner3:cycleFinsihed() and
       scanner4:cycleFinsihed() then
            SignalList:removeOutdated()
            print("End of cycle:")
            SignalList:printCurrentState()
            SignalList:initScan()
            scanner1:continue()
            scanner2:continue()
            scanner3:continue()
            scanner4:continue()
    end 
end
