local LT = ic.enums.LogicType
local signals = require("signals")
local dishes = require("dishes")

local READ_ATTEMPTS_ANTENNA_LIMIT = 12
local READ_ATTEMPTS_ANTENNA_MIDPOINT_LIMIT = 32
local SEARCH_STEP = 8
local SEARCH_STEP_MIDPOINT = 32
local OPTIMIZATION_RESOLUTION = 2

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

local SignalList = signals.SignalList.new(signals.SignalListRole.Updater, {
    fullTopic = signals.TOPIC_SIGNALS,
    updateTopic = signals.TOPIC_SIGNALS_UPDATE,
})

local AntennaState = {
    Idle = 1,
    Search = 2,
    Communication = 3,
    Error = 4,
    NoSignal = 5,
}

local AntennaStateNames = {
    [AntennaState.Idle] = "Idle",
    [AntennaState.Search] = "Search",
    [AntennaState.Communication] = "Communication",
    [AntennaState.Error] = "Error",
    [AntennaState.NoSignal] = "NoSignal",
}

local SearchPattern = {
    { h = -1, v = -1 }, { h = 0, v = -1 }, { h = 1, v = -1 },
    { h = -1, v =  0 },                    { h = 1, v =  0 },
    { h = -1, v =  1 }, { h = 0, v =  1 }, { h = 1, v =  1 }
}

local function nextSearchPatternIndex(patternIndex)
    return patternIndex % #SearchPattern + 1
end

local Antenna = {
    slot = signals.INVALID,
    currentState = AntennaState.Idle,
    searchPatternIndex = 0,
    searchStartPatternIndex = 1,
    searchPointsChecked = 0,
    skipCheckedPoints = false,
    signalId = signals.INVALID,
    bestAngularDistance = signals.INVALID,
    bestWattsReachingContact = signals.INVALID,
    step = SEARCH_STEP,
    dish = nil,
    searchCenterPosition = { h = signals.INVALID, v = signals.INVALID },
    searchPosition = { h = signals.INVALID, v = signals.INVALID },
    found = false,
    readAttempts = 0,
    readAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
    configuredReadAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
    optimizationResolution = OPTIMIZATION_RESOLUTION,
    StateMachine = {
        [AntennaState.Idle] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Search] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Communication] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Error] = { enter = nil, exit = nil, next = nil },
        [AntennaState.NoSignal] = { enter = nil, exit = nil, next = nil },
    },
}
Antenna.__index = Antenna

function Antenna.new(slot, dishName)
    local self = setmetatable({
        slot = slot,
        dish = dishes.Dish.new(dishName),
        configuredReadAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
        readAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
        optimizationResolution = OPTIMIZATION_RESOLUTION,
    }, Antenna)
    self.StateMachine[self.currentState].enter(self)
    return self
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

function Antenna:changeSlot(slot)
    local oldState = self.StateMachine[self.currentState]
    if oldState and oldState.exit then oldState.exit(self) end
    self.slot = slot
    self.currentState = AntennaState.Idle
    local newState = self.StateMachine[self.currentState]
    if newState and newState.enter then newState.enter(self) end
end

function Antenna:setOptimizationResolution(resolution)
    self.optimizationResolution = resolution
end

function Antenna:setReadAttemptsLimit(limit)
    self.configuredReadAttemptsLimit = limit
    self.readAttemptsLimit = limit
end

function Antenna:getCurrentSignalData()
    local data = SignalList:getBySlot(self.slot)
    if data == nil or data.signal.Id ~= self.signalId then return nil end
    return data
end

function Antenna:updateSignalBack(signal, hor, vert, publishUpdate)
    local data = self:getCurrentSignalData()
    if data == nil then return false end
    return SignalList:updateSignalBack(self.slot, self.signalId, signal or data.signal, hor, vert, publishUpdate)
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
        " src:" .. (SignalList:getPosSource(self.slot, self.signalId) or 0) ..
        " " .. message
    )
end

Antenna.StateMachine[AntennaState.Idle].enter = function(self)
    self.searchPatternIndex = 0
    self.signalId = signals.INVALID
    self.readAttemptsLimit = self.configuredReadAttemptsLimit
end

Antenna.StateMachine[AntennaState.Idle].exit = function(self)
end

Antenna.StateMachine[AntennaState.Idle].next = function(self)
    if self.slot ~= signals.INVALID then return AntennaState.Search end
    return AntennaState.Idle
end

Antenna.StateMachine[AntennaState.Search].enter = function(self)
    self.searchPatternIndex = 1
    self.searchStartPatternIndex = 1
    self.searchPointsChecked = 0
    self.found = false
    self:clearSkippedSearchPoints()
    self.readAttempts = 0

    local data = SignalList:getBySlot(self.slot)
    if data == nil then
        self.signalId = signals.INVALID
        return
    end

    self.signalId = data.signal.Id
    self.dish:setContactFilter(self.signalId)
    self.bestAngularDistance = data.signal.AngularDistance
    self.bestWattsReachingContact = data.signal.WattsReachingContact
    self.searchCenterPosition.h = data.bestHorizontal
    self.searchCenterPosition.v = data.bestVertical

    if data.positionSource == signals.SignalPositionSource.BorderMidpoint then
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

    if signals.isWithinResolution(self.bestAngularDistance, self.optimizationResolution) then
        self.found = true
        self:updateSignalBack(data.signal, self.searchCenterPosition.h, self.searchCenterPosition.v, false)
        self:returnToCenter()
    else
        self:startSearchRing(1)
    end
end

Antenna.StateMachine[AntennaState.Search].exit = function(self)
    self.dish:clearContactFilter()
end

Antenna.StateMachine[AntennaState.Search].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self.signalId == signals.INVALID then return AntennaState.NoSignal end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    if self.found then
        if self.dish:isIdle() then
            self.found = false
            return AntennaState.Communication
        end
        return AntennaState.Search
    end

    if not self.dish:isIdle() then
        return AntennaState.Search
    end

    self.dish:readData()
    if not signals.isValidReading(self.dish.signal.WattsReachingContact) then
        if self.readAttempts < self.readAttemptsLimit then
            self.readAttempts = self.readAttempts + 1
            return AntennaState.Search
        end
    end
    self.readAttempts = 0

    self:printState("Read signal")
    if self.dish.signal.Id ~= self.signalId and signals.isValidReading(self.dish.signal.Id) then
        SignalList:removeSignal(self.slot, self.signalId)
        return AntennaState.NoSignal
    end

    if self.signalId == self.dish.signal.Id then
        if signals.isWithinResolution(self.dish.signal.AngularDistance, self.optimizationResolution) then
            self.bestAngularDistance = self.dish.signal.AngularDistance
            self.bestWattsReachingContact = self.dish.signal.WattsReachingContact
            self.searchCenterPosition.h = self.dish.horizontal
            self.searchCenterPosition.v = self.dish.vertical
            self:updateSignalBack(self.dish.signal, self.dish.horizontal, self.dish.vertical, true)
            self.found = true
            return AntennaState.Communication
        end

        if signals.isBetterSignalSample(self.dish.signal.WattsReachingContact, self.bestWattsReachingContact) then
            self.bestAngularDistance = self.dish.signal.AngularDistance
            self.bestWattsReachingContact = self.dish.signal.WattsReachingContact
            self.searchCenterPosition.h = self.dish.horizontal
            self.searchCenterPosition.v = self.dish.vertical
            self:updateSignalBack(self.dish.signal, self.dish.horizontal, self.dish.vertical, true)
            if self.step <= SEARCH_STEP then
                self:setSkippedSearchPoints(self.searchPatternIndex)
            else
                self.step = SEARCH_STEP
            end
            self:startSearchRing(self.searchPatternIndex)
            self:printState("Better signal")
            return AntennaState.Search
        end
    end

    self.searchPointsChecked = self.searchPointsChecked + 1
    if (self.searchPointsChecked == #SearchPattern) or not moveToNextSearchPosition(self) then
        if not signals.isValidReading(self.bestWattsReachingContact) then return AntennaState.Error end
        self.step = self.step / 2
        if signals.isWithinResolution(self.step, self.optimizationResolution) then
            self:updateSignalBack(self.dish.signal, self.searchCenterPosition.h, self.searchCenterPosition.v, true)
            self:returnToCenter()
            self.found = true
            return AntennaState.Communication
        end
        self:clearSkippedSearchPoints()
        self:startSearchRing(self.searchStartPatternIndex)
        self:printState("No better signal")
        return AntennaState.Search
    end

    return AntennaState.Search
end

Antenna.StateMachine[AntennaState.NoSignal].enter = function(self)
    self.searchPatternIndex = 0
    self.searchPointsChecked = 0
    self:clearSkippedSearchPoints()
    self.signalId = signals.INVALID
end

Antenna.StateMachine[AntennaState.NoSignal].exit = function(self)
end

Antenna.StateMachine[AntennaState.NoSignal].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if SignalList:getBySlot(self.slot) ~= nil then return AntennaState.Search end
    return AntennaState.NoSignal
end

Antenna.StateMachine[AntennaState.Error].enter = function(self)
    self.searchPatternIndex = 0
    self.searchPointsChecked = 0
    self:clearSkippedSearchPoints()
end

Antenna.StateMachine[AntennaState.Error].exit = function(self)
end

Antenna.StateMachine[AntennaState.Error].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    local data = self:getCurrentSignalData()
    if data == nil then return AntennaState.NoSignal end
    if data.positionSource == signals.SignalPositionSource.BorderMidpoint then return AntennaState.Search end
    if signals.isValidReading(data.signal.WattsReachingContact) then return AntennaState.Search end
    return AntennaState.Error
end

Antenna.StateMachine[AntennaState.Communication].enter = function(self)
    self.dish:setContactFilter(self.signalId)
end

Antenna.StateMachine[AntennaState.Communication].exit = function(self)
    self.dish:clearContactFilter()
end

Antenna.StateMachine[AntennaState.Communication].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    self.dish:readData()
    if (self.dish.signal.Id ~= self.signalId) or
       not signals.isValidReading(self.dish.signal.AngularDistance) or
       not signals.isValidReading(self.dish.signal.WattsReachingContact) then
        SignalList:removeSignal(self.slot, self.signalId)
        return AntennaState.NoSignal
    end
    return AntennaState.Communication
end

function Antenna:defineNewState()
    return self.StateMachine[self.currentState].next(self)
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
    idle_diod = nil,
    stateColor = signals.INVALID,
    idleColor = signals.INVALID,
    on = false,
    slot = 0,
    res = OPTIMIZATION_RESOLUTION,
    attmpt = READ_ATTEMPTS_ANTENNA_LIMIT,
}
AntennaPanel.__index = AntennaPanel

function AntennaPanel.new(antenna, name)
    return setmetatable({
        name = name,
        antenna = antenna,
        on_sw = ic.find("tr-" .. name .. "-on-sw"),
        slot_dial = ic.find("tr-" .. name .. "-slot-dial"),
        res_dial = ic.find("tr-" .. name .. "-res-dial"),
        attmpt_dial = ic.find("tr-" .. name .. "-attmpt-dial"),
        angle_dsp = ic.find("tr-" .. name .. "-angle-dsp"),
        state_diod = ic.find("tr-" .. name .. "-state-diod"),
        idle_diod = ic.find("tr-" .. name .. "-idle-diod"),
        stateColor = signals.INVALID,
        idleColor = signals.INVALID,
        on = antenna.dish:isOn(),
        slot = antenna.slot,
        res = antenna.optimizationResolution,
        attmpt = antenna.configuredReadAttemptsLimit,
    }, AntennaPanel)
end

function AntennaPanel:updateUi()
    if self.angle_dsp ~= nil then
        local angle = self.antenna.bestAngularDistance
        if not signals.isValidReading(angle) then
            angle = 0
        end
        ic.write_id(self.angle_dsp, LT.Setting, signals.round2(angle))
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
        if color ~= self.stateColor then
            ic.write_id(self.state_diod, LT.Color, color)
            ic.write_id(self.state_diod, LT.On, 1)
            self.stateColor = color
        end
    end

    if self.idle_diod ~= nil then
        local color = Color.Gray
        if self.on then
            color = self.antenna.dish:isIdle() and Color.Green or Color.Orange
        end
        if color ~= self.idleColor then
            ic.write_id(self.idle_diod, LT.Color, color)
            ic.write_id(self.idle_diod, LT.On, 1)
            self.idleColor = color
        end
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

SignalList:start()

local antennaM = Antenna.new(-1, "antenna-dish-M")
local antennaL = Antenna.new(-1, "antenna-dish-L")

Console:init({
    { antenna = antennaM, name = "M" },
    { antenna = antennaL, name = "L" },
})

function tick(dt)
    Console:run()
    if Console.pannels[1].on then
        antennaM:run()
    end
    if Console.pannels[2].on then
        antennaL:run()
    end
end
