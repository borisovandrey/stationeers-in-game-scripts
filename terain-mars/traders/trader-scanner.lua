-- Trader scanner controller.
-- Owns the master signal list, performs dish scan cycles, persists results, and republishes them on the network.
local signals = require("signals")
local dishes = require("dishes")

local READ_ATTEMPTS_LIMIT = 4
local SCAN_HORISONTAL_STEP = 10
local SCAN_VERTICAL_STEP = 20
local SCANNER_SWITCH_NAME = "tr-scanner-sw"
local BORDER_ONLY_SLOTS = {
    [3] = true,
    [4] = true,
}

local SignalList = signals.SignalList.new(signals.SignalListRole.Master, {
    storeKey = signals.STORE_KEY,
    fullTopic = signals.TOPIC_SIGNALS,
    updateTopic = signals.TOPIC_SIGNALS_UPDATE,
})

local BorderSignalTracker = {
    data = {}
}

-- Reset border-only tracking state for a new full scan cycle.
function BorderSignalTracker:initCycle()
    self.data = {}
end

-- Stop tracking a border fallback candidate once a normal sample is confirmed.
function BorderSignalTracker:clearBySlotAndId(slot, id)
    local tracked = self.data[slot]
    if tracked == nil or tracked.signalId ~= id then return false end
    self.data[slot] = nil
    return true
end

-- Accumulate the scan bounds needed to infer midpoint fallback positions.
function BorderSignalTracker:update(signal, hor, vert)
    local slot = signal.contactSlotIndex
    if not BORDER_ONLY_SLOTS[slot] or signal.Id == signals.INVALID then return end

    local tracked = self.data[slot]
    if tracked == nil or tracked.signalId ~= signal.Id then
        tracked = {
            signalId = signal.Id,
            hasValidWatts = false,
            firstHorizontal = signals.normalizeHorizontal(hor),
            minHorizontalOffset = 0,
            maxHorizontalOffset = 0,
            minVertical = vert,
            maxVertical = vert,
        }
        self.data[slot] = tracked
    end

    if signals.isValidReading(signal.WattsReachingContact) then
        tracked.hasValidWatts = true
    end

    local offset = signals.normalizeHorizontal(hor) - tracked.firstHorizontal
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

-- Convert border-only detections into midpoint fallback positions when no watts sample was found.
function BorderSignalTracker:applyFallbacks()
    for slot, tracked in pairs(self.data) do
        if not tracked.hasValidWatts then
            local midHorizontal = signals.normalizeHorizontal(
                tracked.firstHorizontal + (tracked.minHorizontalOffset + tracked.maxHorizontalOffset) / 2
            )
            local midVertical = (tracked.minVertical + tracked.maxVertical) / 2
            if SignalList:setBestPosition(slot, tracked.signalId, midHorizontal, midVertical) then
                SignalList:setPosSource(slot, tracked.signalId, signals.SignalPositionSource.BorderMidpoint)
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

-- Build one serpentine scan plan for a horizontal sector and vertical range.
local function buildScanPlan(hStart, hEnd, vMin, vMax, vStep, desiredHStep)
    local function degToRad(deg)
        return deg * math.pi / 180.0
    end

    local plan = {}
    local sectorWidth = hEnd - hStart
    local rowIndex = 0
    local v = vMin

    while v <= vMax do
        local sinv = math.sin(degToRad(v))
        local count = 1
        if sinv > 0.01 then
            count = math.ceil(sectorWidth * sinv / desiredHStep)
            if count < 1 then
                count = 1
            end
        end

        local row = {}
        for i = 0, count - 1 do
            row[#row + 1] = {
                h = hStart + sectorWidth * (i + 0.5) / count,
                v = v,
            }
        end

        if rowIndex % 2 == 1 then
            local reversed = {}
            for i = #row, 1, -1 do
                reversed[#reversed + 1] = row[i]
            end
            row = reversed
        end

        for i = 1, #row do
            plan[#plan + 1] = row[i]
        end

        rowIndex = rowIndex + 1
        v = v + vStep
    end

    return plan
end

local ScannerStates = {
    Initial = 0,
    ScanCycle = 1,
    FinishCycle = 2,
}

local Scanner = {
    id = -1,
    dish = nil,
    readAttempts = 0,
    nextIndex = 1,
    plan = {},
    step = 1,
    shouldContinue = false,
    currentState = ScannerStates.Initial,
    StateMachine = {
        [ScannerStates.Initial] = { enter = nil, exit = nil, next = nil },
        [ScannerStates.ScanCycle] = { enter = nil, exit = nil, next = nil },
        [ScannerStates.FinishCycle] = { enter = nil, exit = nil, next = nil },
    },
}
Scanner.__index = Scanner

-- Create one scanner state machine bound to one physical dish and scan sector.
function Scanner.new(id, hStart, hEnd, vMin, vMax, vStep, desiredHStep)
    local self = setmetatable({
        id = id,
        dish = dishes.Dish.new("scanner-dish" .. id),
        currentState = ScannerStates.Initial,
        plan = buildScanPlan(hStart, hEnd, vMin, vMax, vStep, desiredHStep),
        nextIndex = 1,
    }, Scanner)
    self.StateMachine[self.currentState].enter(self)
    return self
end

-- Move the scanner dish to the next planned point or finish the cycle.
function Scanner:moveToNextPoint()
    if #self.plan < 2 then
        return ScannerStates.FinishCycle
    end
    if self.nextIndex > #self.plan then
        self.nextIndex = #self.plan - 1
        return ScannerStates.FinishCycle
    end
    if self.nextIndex < 1 then
        self.nextIndex = 2
        return ScannerStates.FinishCycle
    end

    local point = self.plan[self.nextIndex]
    self.dish:setPosition(point.h, point.v)
    self.nextIndex = self.nextIndex + self.step
    return ScannerStates.ScanCycle
end

-- Position the dish at the first planned point when a cycle starts.
Scanner.StateMachine[ScannerStates.Initial].enter = function(self)
    if #self.plan == 0 then return end
    self.nextIndex = 1
    self.step = 1
    self.dish:setPosition(self.plan[self.nextIndex].h, self.plan[self.nextIndex].v)
    self.nextIndex = self.nextIndex + 1
end

-- Initial state has no exit-side cleanup.
Scanner.StateMachine[ScannerStates.Initial].exit = function(self)
end

-- Leave the initial state only after the dish reports idle.
Scanner.StateMachine[ScannerStates.Initial].next = function(self)
    if self.dish:isIdle() then return ScannerStates.ScanCycle end
    return ScannerStates.Initial
end

-- Reset retry counters before each scan-read step.
Scanner.StateMachine[ScannerStates.ScanCycle].enter = function(self)
    self.readAttempts = 0
end

-- Flip traversal direction so the next move continues the serpentine plan.
Scanner.StateMachine[ScannerStates.ScanCycle].exit = function(self)
    self.step = -self.step
end

-- Read one scan sample, merge it, and advance to the next point.
Scanner.StateMachine[ScannerStates.ScanCycle].next = function(self)
    if #self.plan == 0 then return ScannerStates.FinishCycle end
    if not self.dish:isIdle() then return ScannerStates.ScanCycle end

    self.dish:readData()
    if not signals.isValidReading(self.dish.signal.WattsReachingContact) then
        if self.readAttempts < READ_ATTEMPTS_LIMIT then
            self.readAttempts = self.readAttempts + 1
            return ScannerStates.ScanCycle
        end
    end
    self.readAttempts = 0
    SignalList:update(self.dish.signal, self.dish.horizontal, self.dish.vertical)
    BorderSignalTracker:update(self.dish.signal, self.dish.horizontal, self.dish.vertical)
    return self:moveToNextPoint()
end

-- Mark the scanner as paused until the array starts the next cycle.
Scanner.StateMachine[ScannerStates.FinishCycle].enter = function(self)
    self.shouldContinue = false
end

-- Finish state has no exit-side cleanup.
Scanner.StateMachine[ScannerStates.FinishCycle].exit = function(self)
end

-- Stay finished until the array explicitly continues the next cycle.
Scanner.StateMachine[ScannerStates.FinishCycle].next = function(self)
    if self.shouldContinue then return ScannerStates.ScanCycle end
    return ScannerStates.FinishCycle
end

-- Ask the current state which state should run next.
function Scanner:defineNewState()
    return self.StateMachine[self.currentState].next(self)
end

-- Advance the scanner state machine by one tick.
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

-- Report whether this scanner completed its current scan cycle.
function Scanner:cycleFinsihed()
    return self.currentState == ScannerStates.FinishCycle
end

-- Allow a finished scanner to start the next cycle on the next tick.
function Scanner:continue()
    self.shouldContinue = true
end

local ScannerArray = {
    scanners = {},
    onSwitch = nil,
    on = true,
}

-- Read the scanner master switch state, defaulting to enabled when the switch is absent.
function ScannerArray:isOnRequested()
    if self.onSwitch == nil then
        return true
    end
    return ic.read_id(self.onSwitch, ic.enums.LogicType.On) == 1
end

-- Apply a changed power state to every scanner dish.
function ScannerArray:applyOnChange(on)
    for i = 1, #self.scanners do
        self.scanners[i].dish:setOn(on)
    end
end

-- Clear scanner-owned state and publish an empty retained full list when switched off.
function ScannerArray:handleOff()
    SignalList:clear()
    SignalList:clearStore()
    SignalList:clearPublishedFull()
    BorderSignalTracker:initCycle()
end

-- Build the full scanner array by splitting the horizon into equal sectors.
function ScannerArray:init(amount, verticalLimit, verticalStep, horizontalStep)
    local sectorSize = 360 / amount
    self.scanners = {}
    self.onSwitch = ic.find(SCANNER_SWITCH_NAME)
    self.on = self:isOnRequested()
    for i = 1, amount do
        self.scanners[i] = Scanner.new(
            i,
            (i - 1) * sectorSize,
            i * sectorSize,
            0,
            verticalLimit,
            verticalStep,
            horizontalStep
        )
    end
    self:applyOnChange(self.on)
end

-- Run all scanners and finalize the shared list when the full cycle completes.
function ScannerArray:run()
    local requestedOn = self:isOnRequested()
    if requestedOn ~= self.on then
        self.on = requestedOn
        self:applyOnChange(self.on)
        if not self.on then
            self:handleOff()
        end
    end
    if not self.on then return end

    for i = 1, #self.scanners do
        self.scanners[i]:run()
    end

    local cycleFinished = true
    for i = 1, #self.scanners do
        cycleFinished = cycleFinished and self.scanners[i]:cycleFinsihed()
        if not cycleFinished then break end
    end

    if not cycleFinished then return end

    SignalList:removeOutdated()
    BorderSignalTracker:applyFallbacks()
    print("End of cycle:")
    SignalList:printCurrentState()
    SignalList:flush()
    SignalList:initScan()
    BorderSignalTracker:initCycle()
    for i = 1, #self.scanners do
        self.scanners[i]:continue()
    end
end

SignalList:start()
SignalList:restore()
print("Startup restored signal list:")
SignalList:printCurrentState()
SignalList:publishFull()
SignalList:initScan()
BorderSignalTracker:initCycle()
ScannerArray:init(4, 80, SCAN_VERTICAL_STEP, SCAN_HORISONTAL_STEP)

-- Stationeers tick entry point for the scanner controller.
function tick(dt)
    ScannerArray:run()
    SignalList:flush()
end
