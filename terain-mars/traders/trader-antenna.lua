local LT = ic.enums.LogicType
local signals = require("signals")
local dishes = require("dishes")

local READ_ATTEMPTS_ANTENNA_LIMIT = 12
local SEARCH_STEP = 8
local SEARCH_STEP_MIDPOINT = 32
local OPTIMIZATION_RESOLUTION = 2
-- Length of a diagonal direction in the normalized search pattern.
local DIAGONAL_LENGTH = math.sqrt(2)

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
    RingSearch = 2,
    Communication = 3,
    Error = 4,
    NoSignal = 5,
    GradientSearch = 6,
}

local AntennaStateNames = {
    [AntennaState.Idle] = "Idle",
    [AntennaState.RingSearch] = "RingSearch",
    [AntennaState.GradientSearch] = "GradientSearch",
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

local function normalizeDishPosition(hor, vert)
    if vert < signals.MIN_VERTICAL_ANGLE then
        hor = hor + 180
        vert = -vert
    end
    return signals.normalizeHorizontal(hor),
        signals.clamp(vert, signals.MIN_VERTICAL_ANGLE, signals.MAX_VERTICAL_ANGLE)
end

local Antenna = {
    StateMachine = {
        [AntennaState.Idle] = { enter = nil, exit = nil, next = nil },
        [AntennaState.RingSearch] = { enter = nil, exit = nil, next = nil },
        [AntennaState.GradientSearch] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Communication] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Error] = { enter = nil, exit = nil, next = nil },
        [AntennaState.NoSignal] = { enter = nil, exit = nil, next = nil },
    },
}
Antenna.__index = Antenna

function Antenna.new(slot, dishName)
    local self = setmetatable({
        slot = slot,
        currentState = AntennaState.Idle,
        signalId = signals.INVALID,
        step = SEARCH_STEP,
        dish = dishes.Dish.new(dishName),
        searchArea = {
            patternIndex = 0,
            startPatternIndex = 1,
            pointsChecked = 0,
            gradientPatternIndex = 1,
            position = { h = signals.INVALID, v = signals.INVALID },
        },
        bestPoint = {
            angularDistance = signals.INVALID,
            wattsReachingContact = signals.INVALID,
            h = signals.INVALID,
            v = signals.INVALID,
        },
        waitingForBestPosition = false,
        signalIsResolved = false,
        readAttempts = 0,
        readAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
        optimizationResolution = OPTIMIZATION_RESOLUTION,
    }, Antenna)
    self.StateMachine[self.currentState].enter(self)
    return self
end

function Antenna:setSearchPosition(patternIndex)
    local pattern = SearchPattern[patternIndex]
    self.searchArea.patternIndex = patternIndex
    local hor, vert = normalizeDishPosition(
        self.bestPoint.h + self.step * pattern.h,
        self.bestPoint.v + self.step * pattern.v
    )
    self.searchArea.position.h = hor
    self.searchArea.position.v = vert
    self.dish:setPosition(self.searchArea.position.h, self.searchArea.position.v)
end

function Antenna:startSearchRing(patternIndex)
    self.searchArea.startPatternIndex = patternIndex
    self.searchArea.pointsChecked = 0
    self:setSearchPosition(patternIndex)
end

function Antenna:continueGradientSearch()
    local patternIndex = self.searchArea.gradientPatternIndex
    local pattern = SearchPattern[patternIndex]
    local directionLength = pattern.h ~= 0 and pattern.v ~= 0 and DIAGONAL_LENGTH or 1
    local distance = self.bestPoint.angularDistance
    self.searchArea.patternIndex = patternIndex
    local hor, vert = normalizeDishPosition(
        self.bestPoint.h + pattern.h / directionLength * distance,
        self.bestPoint.v + pattern.v / directionLength * distance
    )
    self.searchArea.position.h = hor
    self.searchArea.position.v = vert
    self.dish:setPosition(self.searchArea.position.h, self.searchArea.position.v)
end

function Antenna:returnToCenter()
    self.dish:setPosition(self.bestPoint.h, self.bestPoint.v)
end

local function moveToNextSearchPosition(self)
    local patternIndex = self.searchArea.patternIndex
    if self.searchArea.pointsChecked >= #SearchPattern then return false end
    self:setSearchPosition(nextSearchPatternIndex(patternIndex))
    return true
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
    self.readAttemptsLimit = limit
end

function Antenna:readDishData()
    self.signalIsResolved = false
    self.dish:readData()
    self.signalIsResolved = signals.isValidReading(self.dish.signal.AngularDistance) and
        signals.isValidReading(self.dish.signal.WattsReachingContact)
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

function Antenna:updateBestPointFromDish()
    self.bestPoint.angularDistance = self.dish.signal.AngularDistance
    self.bestPoint.wattsReachingContact = self.dish.signal.WattsReachingContact
    self.bestPoint.h = self.dish.horizontal
    self.bestPoint.v = self.dish.vertical
    self:updateSignalBack(self.dish.signal, self.dish.horizontal, self.dish.vertical, true)
end

function Antenna:printState(message)
    print(
        "slot:" .. self.slot ..
        " st:" .. (AntennaStateNames[self.currentState] or "Unknown") ..
        " id:" .. self.signalId ..
        " ang0:" .. string.format("%.2f", self.bestPoint.angularDistance) ..
        " angP:" .. string.format("%.2f", self.dish.signal.AngularDistance) ..
        " pow0:" .. string.format("%.2f", self.bestPoint.wattsReachingContact) ..
        " powP:" .. string.format("%.2f", self.dish.signal.WattsReachingContact) ..
        " cntr:" .. string.format("%.1f", self.bestPoint.h) .. ":" .. string.format("%.1f", self.bestPoint.v) ..
        " pos:" .. string.format("%.1f", self.searchArea.position.h) .. ":" .. string.format("%.1f", self.searchArea.position.v) ..
        " idx:" .. self.searchArea.patternIndex ..
        " stp:" .. self.step ..
        " src:" .. (SignalList:getPosSource(self.slot, self.signalId) or 0) ..
        " " .. message
    )
end

Antenna.StateMachine[AntennaState.Idle].enter = function(self)
    self.searchArea.patternIndex = 0
    self.signalId = signals.INVALID
    self.signalIsResolved = false
end

Antenna.StateMachine[AntennaState.Idle].exit = function(self)
end

Antenna.StateMachine[AntennaState.Idle].next = function(self)
    if self.slot ~= signals.INVALID then
        if self:initializeRingSearch() then return AntennaState.RingSearch end
        return AntennaState.NoSignal
    end
    return AntennaState.Idle
end

function Antenna:initializeRingSearch()
    self.searchArea.patternIndex = 1
    self.searchArea.startPatternIndex = 1
    self.searchArea.pointsChecked = 0
    self.searchArea.gradientPatternIndex = 1
    self.waitingForBestPosition = false
    self.signalIsResolved = false
    self.readAttempts = 0

    local data = SignalList:getBySlot(self.slot)
    if data == nil then
        self.signalId = signals.INVALID
        return false
    end

    self.signalId = data.signal.Id
    self.bestPoint.angularDistance = data.signal.AngularDistance
    self.bestPoint.wattsReachingContact = data.signal.WattsReachingContact
    self.bestPoint.h = data.bestHorizontal
    self.bestPoint.v = data.bestVertical

    if data.positionSource == signals.SignalPositionSource.BorderMidpoint then
        self.step = SEARCH_STEP_MIDPOINT
    else
        self.step = SEARCH_STEP
    end

    if signals.isWithinResolution(self.bestPoint.angularDistance, self.optimizationResolution) then
        self.waitingForBestPosition = true
        self:updateSignalBack(data.signal, self.bestPoint.h, self.bestPoint.v, false)
        self:returnToCenter()
    else
        self:startSearchRing(1)
    end
    return true
end

Antenna.StateMachine[AntennaState.RingSearch].enter = function(self)
    self.dish:setContactFilter(self.signalId)
end

Antenna.StateMachine[AntennaState.RingSearch].exit = function(self)
    self.waitingForBestPosition = false
    self.dish:clearContactFilter()
end

Antenna.StateMachine[AntennaState.RingSearch].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self.signalId == signals.INVALID then return AntennaState.NoSignal end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    if self.waitingForBestPosition then
        if self.dish:isIdle() then
            return AntennaState.Communication
        end
        return AntennaState.RingSearch
    end

    if not self.dish:isIdle() then
        return AntennaState.RingSearch
    end

    self:readDishData()
    if not self.signalIsResolved then
        self.readAttempts = self.readAttempts + 1
        if self.readAttempts < self.readAttemptsLimit then
            return AntennaState.RingSearch
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
            self:updateBestPointFromDish()
            return AntennaState.Communication
        end

        if self.signalIsResolved and signals.isBetterSignalSample(self.dish.signal.WattsReachingContact, self.bestPoint.wattsReachingContact) then
            local patternIndex = self.searchArea.patternIndex
            self:updateBestPointFromDish()
            if self.step > SEARCH_STEP then
                self.step = SEARCH_STEP
            end
            self.searchArea.gradientPatternIndex = patternIndex
            self:printState("Better signal")
            return AntennaState.GradientSearch
        end
    end

    self.searchArea.pointsChecked = self.searchArea.pointsChecked + 1
    if (self.searchArea.pointsChecked == #SearchPattern) or not moveToNextSearchPosition(self) then
        if not signals.isValidReading(self.bestPoint.wattsReachingContact) then return AntennaState.Error end
        self.step = self.step / 2
        if signals.isWithinResolution(self.step, self.optimizationResolution) then
            self:updateSignalBack(nil, self.bestPoint.h, self.bestPoint.v, true)
            self:returnToCenter()
            self.waitingForBestPosition = true
            return AntennaState.RingSearch
        end
        self:startSearchRing(self.searchArea.startPatternIndex)
        self:printState("No better signal")
        return AntennaState.RingSearch
    end

    return AntennaState.RingSearch
end

Antenna.StateMachine[AntennaState.GradientSearch].enter = function(self)
    self.readAttempts = 0
    self.dish:setContactFilter(self.signalId)
    self:continueGradientSearch()
end

Antenna.StateMachine[AntennaState.GradientSearch].exit = function(self)
    self.waitingForBestPosition = false
    self.dish:clearContactFilter()
end

Antenna.StateMachine[AntennaState.GradientSearch].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self.signalId == signals.INVALID then return AntennaState.NoSignal end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    if self.waitingForBestPosition then
        if self.dish:isIdle() then
            return AntennaState.Communication
        end
        return AntennaState.GradientSearch
    end

    if not self.dish:isIdle() then
        return AntennaState.GradientSearch
    end

    self:readDishData()
    if not self.signalIsResolved then
        self.readAttempts = self.readAttempts + 1
        if self.readAttempts < self.readAttemptsLimit then
            return AntennaState.GradientSearch
        end
    end
    self.readAttempts = 0

    self:printState("Read gradient signal")
    if self.dish.signal.Id ~= self.signalId and signals.isValidReading(self.dish.signal.Id) then
        SignalList:removeSignal(self.slot, self.signalId)
        return AntennaState.NoSignal
    end

    if self.signalId == self.dish.signal.Id then
        if signals.isWithinResolution(self.dish.signal.AngularDistance, self.optimizationResolution) then
            self:updateBestPointFromDish()
            return AntennaState.Communication
        end

        if self.signalIsResolved and signals.isBetterSignalSample(self.dish.signal.WattsReachingContact, self.bestPoint.wattsReachingContact) then
            self:updateBestPointFromDish()
            self:continueGradientSearch()
            self:printState("Better gradient signal")
            return AntennaState.GradientSearch
        end
    end

    self.step = self.step / 2
    self:startSearchRing(self.searchArea.gradientPatternIndex)
    self:printState("Gradient search ended")
    return AntennaState.RingSearch
end

Antenna.StateMachine[AntennaState.NoSignal].enter = function(self)
    self.searchArea.patternIndex = 0
    self.searchArea.pointsChecked = 0
    self.searchArea.gradientPatternIndex = 1
    self.signalId = signals.INVALID
end

Antenna.StateMachine[AntennaState.NoSignal].exit = function(self)
end

Antenna.StateMachine[AntennaState.NoSignal].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if SignalList:getBySlot(self.slot) ~= nil then
        if self:initializeRingSearch() then return AntennaState.RingSearch end
    end
    return AntennaState.NoSignal
end

Antenna.StateMachine[AntennaState.Error].enter = function(self)
    self.searchArea.patternIndex = 0
    self.searchArea.pointsChecked = 0
    self.searchArea.gradientPatternIndex = 1
end

Antenna.StateMachine[AntennaState.Error].exit = function(self)
end

Antenna.StateMachine[AntennaState.Error].next = function(self)
    if self.slot == signals.INVALID then return AntennaState.Idle end
    local data = self:getCurrentSignalData()
    if data == nil then return AntennaState.NoSignal end
    if data.positionSource == signals.SignalPositionSource.BorderMidpoint or
        signals.isValidReading(data.signal.WattsReachingContact) then
        if self:initializeRingSearch() then return AntennaState.RingSearch end
        return AntennaState.NoSignal
    end
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
    self:readDishData()
    if not self.signalIsResolved then return AntennaState.Communication end
    if self.dish.signal.Id ~= self.signalId then
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
            "slot:" .. self.slot ..
            " transition:" ..
            (AntennaStateNames[self.currentState] or "Unknown") ..
            "->" ..
            (AntennaStateNames[newState] or "Unknown")
        )
        local old = self.StateMachine[self.currentState]
        local new = self.StateMachine[newState]
        if old and old.exit then old.exit(self) end
        self.currentState = newState
        if new and new.enter then new.enter(self) end
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
    local self = setmetatable({
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
        attmpt = antenna.readAttemptsLimit,
    }, AntennaPanel)

    if self.attmpt_dial ~= nil then
        local dial = ic.read_id(self.attmpt_dial, LT.Setting)
        self.antenna:setReadAttemptsLimit(dial)
        self.attmpt = dial
    end

    if self.res_dial ~= nil then
        local dial = ic.read_id(self.res_dial, LT.Setting)
        self.antenna:setOptimizationResolution(dial)
        self.res = dial
    end

    return self
end

function AntennaPanel:updateUi()
    if self.angle_dsp ~= nil then
        local angle = self.antenna.bestPoint.angularDistance
        if not signals.isValidReading(angle) then
            angle = 0
        end
        ic.write_id(self.angle_dsp, LT.Setting, signals.round2(angle))
    end

    if self.state_diod ~= nil then
        local color = Color.Gray
        if self.on then
            if self.antenna.currentState == AntennaState.RingSearch or
                self.antenna.currentState == AntennaState.GradientSearch then
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
