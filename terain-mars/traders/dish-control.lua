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
local READ_ATTEMPTS_ANTENNA_MIDPOINT_LIMIT = 32 -- Around 1 minute waiting for midpoint-derived targets
local SEARCH_STEP = 8 -- Antenna search initial step
local SEARCH_STEP_MIDPOINT = 32 -- Antenna search initial step for midpoint-derived targets
local MIN_VERTICAL_ANGLE = 0
local MAX_VERTICAL_ANGLE = 90
local OPTIMIZATION_RESOLUTION = 2 -- Optimization resolution window for direction 
local BORDER_ONLY_SLOTS = {
    [3] = true,
    [4] = true,
}
local STORE_KEY = "Trader.SignalList"

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

local SignalPositionSource = {
    Sample = 1,
    BorderMidpoint = 2,
}

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

local function isBetterSignalSample(left, right)
    local leftValid = isValidReading(left)
    local rightValid = isValidReading(right)
    if leftValid ~= rightValid then
        return leftValid
    end
    if not leftValid then
        return false
    end
    return left > right
end

local function almostEqual(left, right)
    return math.abs(left - right) < EPSILON
end

local function isWithinResolution(value, resolution)
    return isValidReading(value) and (value < resolution or almostEqual(value, resolution))
end

local function round2(value)
    return math.floor(value * 100 + 0.5) / 100
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
    positionSource = SignalPositionSource.Sample,
}

function SignalData.new(version, signal, hor, vert, positionSource)
    local self = {
        version = version,
        signal = copyTable(signal),
        bestHorizontal = hor, 
        bestVertical = vert,
        positionSource = positionSource or SignalPositionSource.Sample,
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

function Dish:isOn()
    if self.device == nil then return false end
    return ic.read_id(self.device, LT.On) == 1
end

function Dish:setOn(on)
    if self.device == nil then return false end
    ic.write_id(self.device, LT.On, on and 1 or 0)
end

function Dish:setPosition(hor, vert)
    if self.device == nil then
        print("Dish setPosition failed: device not found")
        return
    end
    ic.write_id(self.device, LT.Horizontal, normalizeHorizontal(hor))
    ic.write_id(self.device, LT.Vertical, clamp(vert, MIN_VERTICAL_ANGLE, MAX_VERTICAL_ANGLE))
end

function Dish:setContactFilter(id)
    if self.device == nil then
        print("Dish setPosition failed: device not found")
        return
    end
    ic.write_id(self.device, LT.BestContactFilter, id)
end

function Dish:clearContactFilter()
    self:setContactFilter(-1)
end

local SignalList = {
    currentVersion = 0,
    data = {},
    isDirty = false,
}

function SignalList:update(signal, hor, vert)
    local slot = signal.contactSlotIndex
    if slot == INVALID then return end

    local found = self.data[slot]
    if found ~= nil then
        found.version = self.currentVersion
        if found.signal.Id ~= signal.Id then
            print("Replace slot:" .. slot .. " " .. signal:toDebugString())
            self.data[slot] = SignalData.new(self.currentVersion, signal, hor, vert, SignalPositionSource.Sample)
            self.isDirty = true
        elseif isBetterSignalSample(signal.WattsReachingContact, found.signal.WattsReachingContact) then
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
            found.positionSource = SignalPositionSource.Sample
            self.isDirty = true
        end
    else
        print("New " .. signal:toDebugString())
        self.data[slot] = SignalData.new(self.currentVersion, signal, hor, vert, SignalPositionSource.Sample)
        self.isDirty = true
    end
end

function SignalList:initScan()
    if self.currentVersion == 0 then
        self.currentVersion = 1
    else
        self.currentVersion = 0
    end
    self.isDirty = true
end

function SignalList:removeOutdated()
    local keys = {}
    for key, value in pairs(self.data) do
        if value.version ~= self.currentVersion then
            print("Signal slot:" .. key .. " ID:" .. value.signal.Id .. " outdated")
            keys[key] = true
        end
    end
    for key, _ in pairs(keys) do
        self.data[key] = nil
        self.isDirty = true
    end
end

function SignalList:printCurrentState()
    for slot, value in pairs(self.data) do
        print(
            "slot:" .. slot .. " " ..
            "ver:" .. value.version .. 
            value.signal:toDebugString() ..
            " H:" .. string.format("%.2f", value.bestHorizontal) .. "°" ..
            " V:" .. string.format("%.2f", value.bestVertical) .. "°"
        )
    end
end

function SignalList:getBySlot(slot)
    return self.data[slot]
end

function SignalList:findSignalIdBySlot(slot)
    local data = self:getBySlot(slot)
    if data == nil then return INVALID end
    return data.signal.Id
end

function SignalList:removeBySlot(slot)
    self.data[slot] = nil
    self.isDirty = true
end

function SignalList:removeSignalBySlotAndId(slot, id)
    local data = self:getBySlot(slot)
    if data == nil then return false end
    if data.signal.Id ~= id then return false end
    self.data[slot] = nil
    self.isDirty = true
    return true
end

function SignalList:setBestPositionBySlotAndId(slot, id, hor, vert)
    local data = self:getBySlot(slot)
    if data == nil then return false end
    if data.signal.Id ~= id then return false end
    data.bestHorizontal = normalizeHorizontal(hor)
    data.bestVertical = clamp(vert, MIN_VERTICAL_ANGLE, MAX_VERTICAL_ANGLE)
    self.isDirty = true
    return true
end

function SignalList:setPositionSourceBySlotAndId(slot, id, positionSource)
    local data = self:getBySlot(slot)
    if data == nil then return false end
    if data.signal.Id ~= id then return false end
    data.positionSource = positionSource
    self.isDirty = true
    return true
end

function SignalList:getPositionSourceBySlotAndId(slot, id)
    local data = self:getBySlot(slot)
    if data == nil then return nil end
    if data.signal.Id ~= id then return nil end
    return data.positionSource
end

local BorderSignalTracker

function SignalList:updateSignalBack(slot, id, angularDistance, watts, hor, vert)
    local data = self:getBySlot(slot)
    if data == nil then return false end
    if data.signal.Id ~= id then return false end
    local normalizedHorizontal = normalizeHorizontal(hor)
    local normalizedVertical = clamp(vert, MIN_VERTICAL_ANGLE, MAX_VERTICAL_ANGLE)
    local sameAngularDistance = (data.signal.AngularDistance == angularDistance) or
        (isValidReading(data.signal.AngularDistance) and isValidReading(angularDistance) and almostEqual(data.signal.AngularDistance, angularDistance))
    local sameWatts = data.signal.WattsReachingContact == watts
    local sameHorizontal = almostEqual(data.bestHorizontal, normalizedHorizontal)
    local sameVertical = almostEqual(data.bestVertical, normalizedVertical)
    local sameSource = data.positionSource == SignalPositionSource.Sample
    if sameAngularDistance and sameWatts and sameHorizontal and sameVertical and sameSource then
        BorderSignalTracker:clearBySlotAndId(slot, id)
        return false
    end

    data.signal.AngularDistance = angularDistance
    data.signal.WattsReachingContact = watts
    data.bestHorizontal = normalizedHorizontal
    data.bestVertical = normalizedVertical
    data.positionSource = SignalPositionSource.Sample
    data.version = self.currentVersion
    self.isDirty = true
    BorderSignalTracker:clearBySlotAndId(slot, id)
    return true
end

function SignalList:save()
    if not self.isDirty then return end

    local payload = {
        -- Persist as bootstrap data; restored entries should not be treated as a completed live scan cycle.
        v = -1,
        d = {}
    }

    for slot, value in pairs(self.data) do
        payload.d[#payload.d + 1] = {
            slot,
            -1,
            value.signal.Id,
            value.signal.AngularDistance,
            value.signal.WattsReachingContact,
            value.signal.contactTypeId,
            value.signal.contactSlotIndex,
            value.bestHorizontal,
            value.bestVertical,
            value.positionSource,
        }
    end

    local ok, raw = pcall(util.json.encode, payload)
    if ok and raw then
        ic.persist.set(STORE_KEY, raw)
        self.isDirty = false
    else
        print("SignalList save failed")
    end
end

function SignalList:restore()
    if not ic.persist.has(STORE_KEY) then return end
    local raw = ic.persist.get(STORE_KEY)
    if type(raw) ~= "string" then return end
    local ok, decoded = pcall(util.json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        print("SignalList restore failed")
        return
    end

    self.currentVersion = 0
    self.data = {}
    self.isDirty = false

    if type(decoded.d) ~= "table" then return end

    for _, value in pairs(decoded.d) do
        if type(value) == "table" then
            local slot = value[1]
            local signalId = value[3]
            local contactSlotIndex = value[7]
            if slot ~= nil and signalId ~= nil and contactSlotIndex ~= nil then
                local signal = Signal.new()
                signal.Id = signalId
                signal.AngularDistance = value[4] or INVALID
                signal.WattsReachingContact = value[5] or INVALID
                signal.contactTypeId = value[6] or TraderType.Unknown
                signal.contactSlotIndex = contactSlotIndex
                self.data[slot] = SignalData.new(
                    -1,
                    signal,
                    value[8] or INVALID,
                    value[9] or INVALID,
                    value[10] or SignalPositionSource.Sample
                )
            end
        end
    end
end

function SignalList:clear()
    self.data = {}
    self.currentVersion = 0
    self.isDirty = true
end


BorderSignalTracker = {
    data = {}
}

function BorderSignalTracker:initCycle()
    self.data = {}
end

function BorderSignalTracker:clearBySlotAndId(slot, id)
    local tracked = self.data[slot]
    if tracked == nil then return false end
    if tracked.signalId ~= id then return false end
    self.data[slot] = nil
    return true
end

function BorderSignalTracker:update(signal, hor, vert)
    local slot = signal.contactSlotIndex
    if not BORDER_ONLY_SLOTS[slot] then return end
    if signal.Id == INVALID then return end

    local tracked = self.data[slot]
    if tracked == nil or tracked.signalId ~= signal.Id then
        tracked = {
            signalId = signal.Id,
            hasValidWatts = false,
            firstHorizontal = normalizeHorizontal(hor),
            minHorizontalOffset = 0,
            maxHorizontalOffset = 0,
            minVertical = vert,
            maxVertical = vert,
        }
        self.data[slot] = tracked
    end

    if isValidReading(signal.WattsReachingContact) then
        tracked.hasValidWatts = true
    end

    local offset = normalizeHorizontal(hor) - tracked.firstHorizontal
    if offset > 180 then
        offset = offset - 360
    elseif offset < -180 then
        offset = offset + 360
    end

    if offset < tracked.minHorizontalOffset then
        tracked.minHorizontalOffset = offset
    end
    if offset > tracked.maxHorizontalOffset then
        tracked.maxHorizontalOffset = offset
    end
    if vert < tracked.minVertical then
        tracked.minVertical = vert
    end
    if vert > tracked.maxVertical then
        tracked.maxVertical = vert
    end
end

function BorderSignalTracker:applyFallbacks()
    for slot, tracked in pairs(self.data) do
        if not tracked.hasValidWatts then
            local midHorizontal = normalizeHorizontal(
                tracked.firstHorizontal + (tracked.minHorizontalOffset + tracked.maxHorizontalOffset) / 2
            )
            local midVertical = (tracked.minVertical + tracked.maxVertical) / 2
            if SignalList:setBestPositionBySlotAndId(slot, tracked.signalId, midHorizontal, midVertical) then
                SignalList:setPositionSourceBySlotAndId(slot, tracked.signalId, SignalPositionSource.BorderMidpoint)
                print(
                    "Border midpoint slot:" .. slot ..
                    " id:" .. tracked.signalId ..
                    " H:" .. string.format("%.2f", midHorizontal) ..
                    " V:" .. string.format("%.2f", midVertical)
                )
            end
        end
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
    id = -1,
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
        id = id,
        dish = Dish.new("scanner-dish"..id),
        currentState = ScannerStates.Initial,
        plan = buildScanPlan(hStart, hEnd, vMin, vMax, vStep, desiredHStep),
        nextIndex = 1,
    }, Scanner)
    self.StateMachine[self.currentState].enter(self)
    return self
end

function Scanner:moveToNextPoint()
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
    return ScannerStates.ScanCycle
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
        if not isValidReading(self.dish.signal.WattsReachingContact) then
            if self.readAttempts < READ_ATTEMPTS_LIMIT then
                self.readAttempts = self.readAttempts + 1
                return ScannerStates.ScanCycle
            end
        end
        self.readAttempts = 0
        --print("Scan:" .. self.id .. " pos:" .. string.format("%.2f", self.dish.horizontal)  .. ":" .. string.format("%.2f", self.dish.vertical) .. " signal:" .. self.dish.signal:toDebugString())
        SignalList:update(self.dish.signal, self.dish.horizontal, self.dish.vertical)
        BorderSignalTracker:update(self.dish.signal, self.dish.horizontal, self.dish.vertical)
        return self:moveToNextPoint()
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
        BorderSignalTracker:applyFallbacks()
        print("End of cycle:")
        SignalList:printCurrentState()
        SignalList:save()
        SignalList:initScan()
        BorderSignalTracker:initCycle()
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
    found = false,
    readAttempts = 0,
    readAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
    configuredReadAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
    optimizationResolution = OPTIMIZATION_RESOLUTION,

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

function Antenna:clearSkippedSearchPoints()
    self.skipCheckedPoints = false
end

function Antenna:setSearchPosition(patternIndex)
    local pattern = SearchPattern[patternIndex]
    self.searchPatternIndex = patternIndex
    self.searchPosition.h = self.searchCenterPosition.h + self.step * pattern.h
    self.searchPosition.v = self.searchCenterPosition.v + self.step * pattern.v
    self.dish:setPosition(self.searchPosition.h, self.searchPosition.v)
end

function Antenna:startSearchRing(patternIndex)
    self.searchStartPatternIndex = patternIndex
    self.searchPointsChecked = 0
    self:setSearchPosition(patternIndex)
end

function Antenna:returnToCenter()
    self.dish:setPosition(self.searchCenterPosition.h, self.searchCenterPosition.v)
end 

function Antenna:setSkippedSearchPoints(patternIndex)
    self.skipCheckedPoints = true
    self.searchStartPatternIndex = patternIndex
end

function Antenna:isAlreadyCheckedPoint(patternIndex)
    if not self.skipCheckedPoints then return false end
    local shiftPattern = SearchPattern[self.searchStartPatternIndex]
    local pattern = SearchPattern[patternIndex]
    local shiftH = pattern.h + shiftPattern.h
    local shiftV = pattern.v + shiftPattern.v
    if shiftH < -1 or shiftH > 1 then return false end
    if shiftV < -1 or shiftV > 1 then return false end
    return true
end

local function moveToNextSearchPosition(self)
    local patternIndex = self.searchPatternIndex
    while self.searchPointsChecked < #SearchPattern do
        patternIndex = nextSearchPatternIndex(patternIndex)
        if self:isAlreadyCheckedPoint(patternIndex) then
            self.searchPointsChecked = self.searchPointsChecked + 1
        else
            self:setSearchPosition(patternIndex)
            return true
        end
    end
    return false
end

function Antenna.new(slot, dishName)
    local self = setmetatable({
        slot = slot,
        dish = Dish.new(dishName),
        configuredReadAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
        readAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
        optimizationResolution = OPTIMIZATION_RESOLUTION,
    }, Antenna)
    self.StateMachine[self.currentState].enter(self)
    return self
end

function Antenna:changeSlot(slot)
    local oldState = self.StateMachine[self.currentState]
    if oldState and oldState.exit then
        oldState.exit(self)
    end
    self.slot = slot
    self.currentState = AntennaState.Idle
    local newState = self.StateMachine[self.currentState]
    if newState and newState.enter then
        newState.enter(self)
    end
end

function Antenna:setOptimizationResolution(resolution)
    self.optimizationResolution = resolution
end

function Antenna:setReadAttemptsLimit(limit)
    self.configuredReadAttemptsLimit = limit
    self.readAttemptsLimit = limit
end

function Antenna:updateSignalBack(hor, vert)
    local data = self:getCurrentSignalData()
    if data == nil then return false end

    SignalList:updateSignalBack(
        self.slot,
        self.signalId,
        self.bestAngularDistance,
        self.bestWattsReachingContact,
        hor,
        vert
    )
    return true
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
        " src:" .. (SignalList:getPositionSourceBySlotAndId(self.slot, self.signalId) or 0) ..
        " " .. message
    )
end

function Antenna:getCurrentSignalData()
    local data = SignalList:getBySlot(self.slot)
    if data == nil then return nil end
    if data.signal.Id ~= self.signalId then return nil end
    return data
end

-- State Idle
Antenna.StateMachine[AntennaState.Idle].enter = function(self)
    self.searchPatternIndex = 0
    self.signalId = INVALID
    self.readAttemptsLimit = self.configuredReadAttemptsLimit
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
    self.searchPatternIndex = 1 
    self.searchStartPatternIndex = 1
    self.searchPointsChecked = 0
    self.found = false
    self:clearSkippedSearchPoints()
    self.readAttempts = 0
    local data = SignalList:getBySlot(self.slot)

    if data == nil then
        self.signalId = INVALID
        return
    end

    self.signalId = data.signal.Id
    self.dish:setContactFilter(self.signalId)
    self.bestAngularDistance = data.signal.AngularDistance
    self.bestWattsReachingContact = data.signal.WattsReachingContact
    self.searchCenterPosition.h = data.bestHorizontal
    self.searchCenterPosition.v = data.bestVertical
    if data.positionSource == SignalPositionSource.BorderMidpoint then
        self.step = SEARCH_STEP_MIDPOINT
        if self.configuredReadAttemptsLimit > READ_ATTEMPTS_ANTENNA_MIDPOINT_LIMIT then
            self.readAttemptsLimit = self.configuredReadAttemptsLimit
        else
            self.readAttemptsLimit = READ_ATTEMPTS_ANTENNA_MIDPOINT_LIMIT
        end
    else
        self.step = SEARCH_STEP
        self.readAttemptsLimit = self.configuredReadAttemptsLimit
    end
    if isWithinResolution(self.bestAngularDistance, self.optimizationResolution) then
        self.found = true
        self:updateSignalBack(self.searchCenterPosition.h, self.searchCenterPosition.v)
        self:returnToCenter()
    else
        self:startSearchRing(1)
    end
end
Antenna.StateMachine[AntennaState.Search].exit = function(self)
    self.dish:clearContactFilter()
end
Antenna.StateMachine[AntennaState.Search].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    if self.signalId == INVALID then return AntennaState.NoSignal end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    if self.found then
        if self.dish:isIdle() then
            self.found = false
            return AntennaState.Communication
        end
        return AntennaState.Search
    end
    if self.dish:isIdle() then
        self.dish:readData()
        if not isValidReading(self.dish.signal.WattsReachingContact) then
            if self.readAttempts < self.readAttemptsLimit then
                self.readAttempts = self.readAttempts + 1
                return AntennaState.Search
            end
        end
        self.readAttempts = 0

        self:printState("Read signal")
        if self.dish.signal.Id ~= self.signalId then
            SignalList:removeSignalBySlotAndId(self.slot, self.signalId)
            return AntennaState.NoSignal
        end
        if self.signalId == self.dish.signal.Id then
            if isWithinResolution(self.dish.signal.AngularDistance, self.optimizationResolution) then
                self.bestAngularDistance = self.dish.signal.AngularDistance
                self.bestWattsReachingContact = self.dish.signal.WattsReachingContact
                self.searchCenterPosition.h = self.dish.horizontal
                self.searchCenterPosition.v = self.dish.vertical
                self:updateSignalBack(self.dish.horizontal, self.dish.vertical)
                self.found = true
                return AntennaState.Communication
            end
            if isBetterSignalSample(self.dish.signal.WattsReachingContact, self.bestWattsReachingContact) then
                self.bestAngularDistance = self.dish.signal.AngularDistance
                self.bestWattsReachingContact = self.dish.signal.WattsReachingContact
                self.searchCenterPosition.h = self.dish.horizontal
                self.searchCenterPosition.v = self.dish.vertical
                self:updateSignalBack(self.dish.horizontal, self.dish.vertical)
                if(self.step <= SEARCH_STEP) then
                    -- In case of search by samples 
                    self:setSkippedSearchPoints(self.searchPatternIndex) 
                else 
                    -- In case of search by borders and calculated middle - swithc to normal search, but don't exclude points
                    self.step = SEARCH_STEP
                end
                self:startSearchRing(self.searchPatternIndex)
                self:printState("Better signal")
                return AntennaState.Search
            end
        end
        self.searchPointsChecked = self.searchPointsChecked + 1

        --Check we have reached the end of serach pattern
        if (self.searchPointsChecked == #SearchPattern) or not moveToNextSearchPosition(self) then
            if not isValidReading(self.bestWattsReachingContact) then return AntennaState.Error end
            self.step = self.step / 2
            if isWithinResolution(self.step, self.optimizationResolution) then 
                self:updateSignalBack(self.searchCenterPosition.h, self.searchCenterPosition.v)
                self:returnToCenter() 
                self.found = true
                return AntennaState.Communication     
            end
            self:clearSkippedSearchPoints(self)
            self:startSearchRing(self.searchStartPatternIndex)
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
    self:clearSkippedSearchPoints()
    self.signalId = INVALID
end
Antenna.StateMachine[AntennaState.NoSignal].exit = function(self)
    --Nothing to do
end
Antenna.StateMachine[AntennaState.NoSignal].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    if SignalList:getBySlot(self.slot) ~= nil then return AntennaState.Search end
    return AntennaState.NoSignal
end

-- State Error
Antenna.StateMachine[AntennaState.Error].enter = function(self)
    self.searchPatternIndex = 0
    self.searchPointsChecked = 0
    self:clearSkippedSearchPoints()
end
Antenna.StateMachine[AntennaState.Error].exit = function(self)
    --Nothing to do
end
Antenna.StateMachine[AntennaState.Error].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    local data = self:getCurrentSignalData()
    if data == nil then return AntennaState.NoSignal end
    if data.positionSource == SignalPositionSource.BorderMidpoint then return AntennaState.Search end
    if isValidReading(data.signal.WattsReachingContact) then return AntennaState.Search end
    return AntennaState.Error
end

-- State Communication
Antenna.StateMachine[AntennaState.Communication].enter = function(self)
    self.dish:setContactFilter(self.signalId)
end
Antenna.StateMachine[AntennaState.Communication].exit = function(self)
    self.dish:clearContactFilter()
end
Antenna.StateMachine[AntennaState.Communication].next = function(self)
    if self.slot == INVALID then return AntennaState.Idle end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    self.dish:readData()
    if (self.dish.signal.Id ~= self.signalId) or
       not isValidReading(self.dish.signal.AngularDistance) or
       not isValidReading(self.dish.signal.WattsReachingContact) then
        SignalList:removeSignalBySlotAndId(self.slot, self.signalId)
        return AntennaState.NoSignal 
    end
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

local AntennaPanel = {
    name = "",
    antenna = nil,
    on_sw = nil,
    slot_dial = nil,
    res_dial = nil,
    attmpt_dial = nil,
    angle_dsp = nil,
    state_diod = nil,
    on = false,
    slot = 0,
    res = OPTIMIZATION_RESOLUTION,
    attmpt = READ_ATTEMPTS_ANTENNA_LIMIT,
}
AntennaPanel.__index = AntennaPanel

function AntennaPanel.new(antenna, name)
    local self = setmetatable({
        name = name,
        antenna = antenna,
        on_sw = ic.find("tr-" .. name .. "-on-sw"),
        slot_dial = ic.find("tr-" .. name .. "-slot-dial"),
        res_dial = ic.find("tr-" .. name .. "-res-dial"),
        attmpt_dial = ic.find("tr-" .. name .. "-attmpt-dial"),
        angle_dsp = ic.find("tr-" .. name .. "-angle-dsp"),
        state_diod = ic.find("tr-" .. name .. "-state-diod"),
        on = antenna.dish:isOn(),
        slot = antenna.slot,
        res = antenna.optimizationResolution,
        attmpt = antenna.configuredReadAttemptsLimit,
    }, AntennaPanel)
    return self
end

function AntennaPanel:updateUi()
    if self.angle_dsp ~= nil then
        local angle = self.antenna.bestAngularDistance
        if not isValidReading(angle) then
            angle = 0
        end
        ic.write_id(self.angle_dsp, LT.Setting, round2(angle))
    end

    if self.state_diod ~= nil then
        local color = Color.Gray
        if self.on then
            if self.antenna.currentState == AntennaState.Search then
                color = Color.Orange
            elseif self.antenna.currentState == AntennaState.Communication then
                color = Color.Green
            elseif self.antenna.currentState == AntennaState.Error then
                color = Color.Red
            elseif self.antenna.currentState == AntennaState.NoSignal then
                color = Color.Yellow
            elseif self.antenna.currentState == AntennaState.Idle then
                color = Color.Blue
            end
        end
        ic.write_id(self.state_diod, LT.Color, color)
        ic.write_id(self.state_diod, LT.On, 1)
    end
end

function AntennaPanel:run()
    if self.on_sw ~= nil then
        local on = ic.read_id(self.on_sw, LT.On) == 1
        if on ~= self.on then
            self.antenna.dish:setOn(on)
            self.on = on
        end
    end

    if self.slot_dial ~= nil then
        local dial = ic.read_id(self.slot_dial, LT.Setting)
        if dial ~= self.slot then
            self.antenna:changeSlot(dial)
            self.slot = dial
        end
    end

    if self.res_dial ~= nil then
        local dial = ic.read_id(self.res_dial, LT.Setting)
        if dial ~= self.res then
            self.antenna:setOptimizationResolution(dial)
            self.res = dial
        end
    end

    if self.attmpt_dial ~= nil then
        local dial = ic.read_id(self.attmpt_dial, LT.Setting)
        if dial ~= self.attmpt then
            self.antenna:setReadAttemptsLimit(dial)
            self.attmpt = dial
        end
    end

    self:updateUi()
end

-- Console
local Console = {
    pannels = {}
}

function Console:init(definitions)
    self.pannels = {}
    for i = 1, #definitions do
        local definition = definitions[i]
        self.pannels[i] = AntennaPanel.new(definition.antenna, definition.name)
    end
end

function Console:run()
    for i = 1, #self.pannels do
        self.pannels[i]:run()
    end
end

-- Application Initialization

SignalList:restore()
print("Startup restored signal list:")
SignalList:printCurrentState()
ScannerArray:init(4, 80, SCAN_VERTICAL_STEP, SCAN_HORISONTAL_STEP)

local antennaM = Antenna.new(-1, "antenna-dish-M")
local antennaL = Antenna.new(-1, "antenna-dish-L")

Console:init({
    { antenna = antennaM, name = "M" },
    { antenna = antennaL, name = "L" },
})

-- Application run
function tick(dt)
    ScannerArray:run()
    Console:run()
    if Console.pannels[1].on then 
        antennaM:run()
    end
    if Console.pannels[2].on then 
        antennaL:run()
    end
end
