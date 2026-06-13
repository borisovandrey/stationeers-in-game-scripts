--terain-mars\traders\dish-control.lua
-- Investigation Lua script for Stationeers game
-- Intended to investigate how Trading Medium Satelite Dish works
-- Script conatins scanner that move a dish around 
-- and collects the list of awalable signals in the list   
local LT  = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod

local EPSILON = 0.001
local INVALID = -1
local SCAN_HORISONTAL_STEP = 10 -- 10°
local SCAN_VERTICAL_STEP = 20   -- 20°
local READ_ATTEMPTS_LIMIT = 4 -- Ammount of reads the data if the signal strength is INVALID for Scanner
local READ_ATTEMPTS_ANTENNA_LIMIT = 12 -- Ammount of reads the data if the signal strength is INVALID for Antenna
local SEARCH_STEP = 16 -- Antenna search initial step
local MIN_VERTICAL_ANGLE = 0
local MAX_VERTICAL_ANGLE = 90

local TraderType = {
    Unknown             = INVALID,
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

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function normalizeHorizontal(angle)
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function isValidReading(value)
    return value ~= INVALID
end

local function hasValidSignalSample(signal)
    return isValidReading(signal.WattsReachingContact)
end

local function isBetterSignalSample(left, right)
    local leftHasPower = hasValidSignalSample(left)
    local rightHasPower = hasValidSignalSample(right)
    if leftHasPower ~= rightHasPower then
        return leftHasPower
    end
    if not leftHasPower then
        return false
    end
    if left.WattsReachingContact ~= right.WattsReachingContact then
        return left.WattsReachingContact > right.WattsReachingContact
    end

    local leftHasDistance = isValidReading(left.AngularDistance)
    local rightHasDistance = isValidReading(right.AngularDistance)
    if leftHasDistance and left.AngularDistance ~= right.AngularDistance then
        return left.AngularDistance < right.AngularDistance
    end

    return false
end

local Signal = {
    Id = INVALID,                -- current signal id
    AngularDistance = INVALID,   -- current angular distance to the signal source
    WattsReachingContact = INVALID, -- current power delivered to the contact
    contactTypeId = TraderType.Unknown, -- one of the possible contact type id (see TraderType)
    contactSlotIndex = INVALID   -- contact slot index
}
Signal.__index = Signal

function Signal.new()
    return setmetatable({
        Id = Signal.Id,
        AngularDistance = Signal.AngularDistance,
        WattsReachingContact = Signal.WattsReachingContact,
        contactTypeId = Signal.contactTypeId,
        contactSlotIndex = Signal.contactSlotIndex,
    }, Signal)
end

function Signal:toDebugString()
    return "Signal ID:" .. self.Id ..
        " Angular:" .. string.format("%.2f", self.AngularDistance) ..
        " Power:" .. string.format("%.2f", self.WattsReachingContact) ..
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
    bestHorizontal = INVALID,    -- best known horizontal angle
    bestVertical = INVALID,      -- best vertical angle
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
    vertical = INVALID,          -- vertical orientation
    horizontal = INVALID,        -- horizontal orientation
    signal = Signal.new()   -- signal
}
Dish.__index = Dish

function Dish.new(name)
    local self = setmetatable({
        device = ic.find(name),
        vertical = Dish.vertical,
        horizontal = Dish.horizontal,
        signal = Signal.new(),
    }, Dish)
    if self.device == nil then
        print("Dish " .. name .. " not found")
    end
    return self
end

-- dish is ready to ready for read signals
function Dish:isIdle()
    if self.device == nil then return false end
    return ic.read_id(self.device, LT.Idle) == 1
end

function Dish:readData()
    if self.device == nil then return end
    self.horizontal = ic.read_id(self.device, LT.Horizontal)
    self.vertical = ic.read_id(self.device, LT.Vertical)
    self.signal.Id = ic.read_id(self.device, LT.SignalID)
    self.signal.AngularDistance = ic.read_id(self.device, LT.SignalStrength)
    self.signal.WattsReachingContact = ic.read_id(self.device, LT.WattsReachingContact)
    self.signal.contactTypeId = ic.read_id(self.device, LT.ContactTypeId)
    self.signal.contactSlotIndex = ic.read_id(self.device, LT.ContactSlotIndex)
end

function Dish:setPosition(hor, vert)
    if self.device == nil then
        print("Dish setPosition failed: device not found")
        return
    end
    ic.write_id(self.device, LT.Horizontal, normalizeHorizontal(hor))
    ic.write_id(self.device, LT.Vertical, clamp(vert, MIN_VERTICAL_ANGLE, MAX_VERTICAL_ANGLE))
end

local SignalList = {
    currentVersion = 0,
    data = {}
}

function SignalList:update(signal, hor, vert)
    local found = self.data[signal.Id]
    if found ~= nil then
        found.version = self.currentVersion
        if isBetterSignalSample(signal, found.signal) then
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
            "ver:" .. value.version .. 
            value.signal:toDebugString() ..
            " H:" .. string.format("%.2f", value.bestHorizontal) .. "°" ..
            " V:" .. string.format("%.2f", value.bestVertical) .. "°"
        )
    end
end

function SignalList:findSlot(slot)
    for key, value in pairs(self.data) do
        if value.signal.contactSlotIndex == slot then return key end
    end
    return INVALID
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
    if self.dish:isIdle() then return ScannerStates.ScanCycle else return ScannerStates.Initial end
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
    if self.dish:isIdle() then 
        self.dish:readData()
        if not hasValidSignalSample(self.dish.signal) then
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

local ScannerArray = {
    scanners = {}
}

function ScannerArray:init(ammount, verticalLimit, verticalStep, horizontalStep)
    local sectorSize = 360 / ammount
    for i = 1, ammount do
        self.scanners[i] = Scanner.new(i, (i - 1) * sectorSize, i * sectorSize, 0, verticalLimit, verticalStep, horizontalStep)
    end
end

function ScannerArray:run()
    for i = 1, #self.scanners do
        self.scanners[i]:run()
    end
    local cycleFinsihed = true
    for i = 1, #self.scanners do
        cycleFinsihed = cycleFinsihed and self.scanners[i]:cycleFinsihed()
        if not cycleFinsihed then break end
    end
    if cycleFinsihed then
        SignalList:removeOutdated()
        print("End of cycle:")
        SignalList:printCurrentState()
        SignalList:initScan()
        for i = 1, #self.scanners do
            self.scanners[i]:continue()
        end
    end
end

local AntennaState = {
    Idle = 1,           -- Initial state and innactive state
    Search = 2,         -- Antenna searches the point
    Communication = 3,  -- Antenna have found the point
    Error = 4,          -- It is not possible to find the point as the signal strength is INVALID
    NoSignal = 5,       -- Signal disappears from signal list
}

local AntennaStateNames = {
    [AntennaState.Idle] = "Idle",
    [AntennaState.Search] = "Search",
    [AntennaState.Communication] = "Communication",
    [AntennaState.Error] = "Error",
    [AntennaState.NoSignal] = "NoSignal",
}

local Antenna = {
    slot = INVALID,
    currentState = AntennaState.Idle,
    searchPatternIndex = 0,
    searchStartPatternIndex = 1,
    searchPointsChecked = 0,
    skipCheckedPoints = false,
    signalId = INVALID,
    bestAngularDistance = INVALID,
    bestWattsReachingContact = INVALID,
    step = SEARCH_STEP,
    dish = {},
    searchCenterPosition = { h = INVALID, v = INVALID },
    searchPosition = { h = INVALID, v = INVALID },
    searchShift = { h = 0, v = 0 },
    readAttempts = 0,

    StateMachine = {
        [AntennaState.Idle] =    { enter = nil, exit = nil, next = nil },
        [AntennaState.Search] =  { enter = nil, exit = nil, next = nil, },
        [AntennaState.Communication] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Error] =    { enter = nil, exit = nil, next = nil },
        [AntennaState.NoSignal] = { enter = nil, exit = nil, next = nil },
    },
}
Antenna.__index = Antenna

local SearchPattern = {
    { h = -1, v = -1 }, { h = 0, v = -1 }, { h = 1, v = -1 },
    { h = -1, v =  0 },                    { h = 1, v =  0 },
    { h = -1, v =  1 }, { h = 0, v =  1 }, { h = 1, v =  1 }
}

local function nextSearchPatternIndex(patternIndex)
    return patternIndex % #SearchPattern + 1
end

local function clearSkippedSearchPoints(self)
    self.skipCheckedPoints = false
    self.searchShift.h = 0
    self.searchShift.v = 0
end

local function setSearchPosition(self, patternIndex)
    local pattern = SearchPattern[patternIndex]
    self.searchPatternIndex = patternIndex
    self.searchPosition.h = self.searchCenterPosition.h + self.step * pattern.h
    self.searchPosition.v = self.searchCenterPosition.v + self.step * pattern.v
    self.dish:setPosition(self.searchPosition.h, self.searchPosition.v)
end

local function startSearchRing(self, patternIndex)
    self.searchStartPatternIndex = patternIndex
    self.searchPointsChecked = 0
    setSearchPosition(self, patternIndex)
end

local function setSkippedSearchPoints(self, patternIndex)
    local pattern = SearchPattern[patternIndex]
    self.skipCheckedPoints = true
    self.searchShift.h = pattern.h
    self.searchShift.v = pattern.v
end

local function isAlreadyCheckedPoint(self, patternIndex)
    if not self.skipCheckedPoints then return false end
    local pattern = SearchPattern[patternIndex]
    local shiftH = pattern.h + self.searchShift.h
    local shiftV = pattern.v + self.searchShift.v
    if shiftH < -1 or shiftH > 1 then return false end
    if shiftV < -1 or shiftV > 1 then return false end
    return true
end

local function moveToNextSearchPosition(self)
    local patternIndex = self.searchPatternIndex
    while self.searchPointsChecked < #SearchPattern do
        patternIndex = nextSearchPatternIndex(patternIndex)
        if isAlreadyCheckedPoint(self, patternIndex) then
            self.searchPointsChecked = self.searchPointsChecked + 1
        else
            setSearchPosition(self, patternIndex)
            return true
        end
    end
    return false
end

function Antenna.new(slot, dishName)
    local self = setmetatable({
        slot = slot,
        dish = Dish.new(dishName)
    }, Antenna)
    self.StateMachine[self.currentState].enter(self)
    return self
end

function Antenna:printState(message)
    print(
        "Antenna slot:" .. self.slot ..
        " st:" .. (AntennaStateNames[self.currentState] or "Unknown") ..
        " id:" .. self.signalId ..
        " ang0:" .. string.format("%.2f", self.bestAngularDistance) ..
        " angP:" .. string.format("%.2f", self.dish.signal.AngularDistance) ..
        " pow0:" .. string.format("%.2f", self.bestWattsReachingContact) ..
        " powP:" .. string.format("%.2f", self.dish.signal.WattsReachingContact) ..
        " cntr:" .. string.format("%.1f", self.searchCenterPosition.h) .. ":" .. string.format("%.1f", self.searchCenterPosition.v) ..
        " pos:" .. string.format("%.1f", self.searchPosition.h) .. ":" .. string.format("%.1f", self.searchPosition.v) ..
        " idx:" .. self.searchPatternIndex .. 
        " stp:" .. self.step ..
        " " .. message
    )
end

-- State Idle
Antenna.StateMachine[AntennaState.Idle].enter = function(self)
    self.searchPatternIndex = 0
    self.signalId = INVALID
end
Antenna.StateMachine[AntennaState.Idle].exit = function(self)
    --Nothing to do
end
Antenna.StateMachine[AntennaState.Idle].next = function(self)
    if self.slot ~= INVALID then return AntennaState.Search end
    return AntennaState.Idle
end

-- State Search
Antenna.StateMachine[AntennaState.Search].enter = function(self)
    self.step = SEARCH_STEP
    self.searchPatternIndex = 1
    self.searchStartPatternIndex = 1
    self.searchPointsChecked = 0
    clearSkippedSearchPoints(self)
    self.readAttempts = 0
    self.signalId = SignalList:findSlot(self.slot)

    if self.signalId == INVALID then return end
    local data = SignalList.data[self.signalId]
    self.bestAngularDistance = data.signal.AngularDistance
    self.bestWattsReachingContact = data.signal.WattsReachingContact
    self.searchCenterPosition.h = data.bestHorizontal
    self.searchCenterPosition.v = data.bestVertical
    startSearchRing(self, 1)
end
Antenna.StateMachine[AntennaState.Search].exit = function(self)
    --Nothing to do
end
Antenna.StateMachine[AntennaState.Search].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    if self.signalId == INVALID then return AntennaState.NoSignal end
    local checkId = SignalList:findSlot(self.slot)
    if self.signalId  ~= checkId then return AntennaState.NoSignal end
    if self.dish:isIdle() then
        self.dish:readData()

        if not hasValidSignalSample(self.dish.signal) then
            if self.readAttempts < READ_ATTEMPTS_ANTENNA_LIMIT then
                self.readAttempts = self.readAttempts + 1
                return AntennaState.Search
            end
        end
        self.readAttempts = 0

        self:printState("Read signal")
        if self.signalId == self.dish.signal.Id then
            if isBetterSignalSample(self.dish.signal, {
                AngularDistance = self.bestAngularDistance,
                WattsReachingContact = self.bestWattsReachingContact,
            }) then
                self.bestAngularDistance = self.dish.signal.AngularDistance
                self.bestWattsReachingContact = self.dish.signal.WattsReachingContact
                self.searchCenterPosition.h = self.dish.horizontal
                self.searchCenterPosition.v = self.dish.vertical
                setSkippedSearchPoints(self, self.searchPatternIndex)
                startSearchRing(self, self.searchPatternIndex)
                self:printState("Better signal")
                return AntennaState.Search
            end
        end
        self.searchPointsChecked = self.searchPointsChecked + 1
        if self.searchPointsChecked == #SearchPattern then
            if not hasValidSignalSample({
                AngularDistance = self.bestAngularDistance,
                WattsReachingContact = self.bestWattsReachingContact,
            }) then return AntennaState.Error end
            self.step = self.step / 2
            if self.step < 2 then return AntennaState.Communication end
            clearSkippedSearchPoints(self)
            startSearchRing(self, self.searchStartPatternIndex)
            self:printState("No better signal")
            return AntennaState.Search
        end
        if not moveToNextSearchPosition(self) then
            if not hasValidSignalSample({
                AngularDistance = self.bestAngularDistance,
                WattsReachingContact = self.bestWattsReachingContact,
            }) then return AntennaState.Error end
            self.step = self.step / 2
            if self.step < 2 then return AntennaState.Communication end
            clearSkippedSearchPoints(self)
            startSearchRing(self, self.searchStartPatternIndex)
            self:printState("No better signal")
            return AntennaState.Search
        end
    end
    return AntennaState.Search
end

-- State NoSignal
Antenna.StateMachine[AntennaState.NoSignal].enter = function(self)
    self.searchPatternIndex = 0
    self.searchPointsChecked = 0
    clearSkippedSearchPoints(self)
    self.signalId = INVALID
end
Antenna.StateMachine[AntennaState.NoSignal].exit = function(self)
    --Nothing to do
end
Antenna.StateMachine[AntennaState.NoSignal].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    local signalId = SignalList:findSlot(self.slot)
    if signalId ~= INVALID then return AntennaState.Search end
    return AntennaState.NoSignal
end

-- State Error
Antenna.StateMachine[AntennaState.Error].enter = function(self)
    self.searchPatternIndex = 0
    self.searchPointsChecked = 0
    clearSkippedSearchPoints(self)
end
Antenna.StateMachine[AntennaState.Error].exit = function(self)
    --Nothing to do
end
Antenna.StateMachine[AntennaState.Error].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    local signalId = SignalList:findSlot(self.slot)
    if signalId ~= self.signalId then return AntennaState.NoSignal end
    local data = SignalList.data[signalId]
    if hasValidSignalSample(data.signal) then return AntennaState.Search end
    return AntennaState.Error
end

-- State Communication
Antenna.StateMachine[AntennaState.Communication].enter = function(self)
end
Antenna.StateMachine[AntennaState.Communication].exit = function(self)
    --Nothing to do
end
Antenna.StateMachine[AntennaState.Communication].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    local signalId = SignalList:findSlot(self.slot)
    if signalId == INVALID then return AntennaState.NoSignal end
    if signalId ~= self.signalId then return AntennaState.NoSignal end
    self.dish:readData()
    if self.dish.signal.Id ~= self.signalId then return AntennaState.NoSignal end
    return AntennaState.Communication
end

function Antenna:defineNewState()
    local state = self.StateMachine[self.currentState]
    return state.next(self)
end

function Antenna:run()
    local newState = self:defineNewState()
    if self.currentState ~= newState then
        print(
            "Antenna slot:" .. self.slot ..
            " transition:" ..
            (AntennaStateNames[self.currentState] or "Unknown") ..
            "->" ..
            (AntennaStateNames[newState] or "Unknown")
        )
        local old = self.StateMachine[self.currentState]
        local new = self.StateMachine[newState]
        if old and old.exit then old.exit(self) end
        if new and new.enter then new.enter(self) end
        self.currentState = newState
    end
end

-- Application Initialization

ScannerArray:init(4, 80, SCAN_VERTICAL_STEP, SCAN_HORISONTAL_STEP)

local antenna = Antenna.new(1, "antenna-dish")

-- Application run
function tick(dt)
    ScannerArray:run()
    antenna:run()
end
