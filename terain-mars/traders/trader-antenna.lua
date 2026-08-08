local LT = ic.enums.LogicType
local signals = require("signals")
local dishes = require("dishes")
local trader = require("trader")

local READ_ATTEMPTS_ANTENNA_LIMIT = 12
local SEARCH_STEP = 8
local SEARCH_STEP_MIDPOINT = 32
local OPTIMIZATION_RESOLUTION = 2
local TRADER_MEMORY_SIZE = 32
local DATA_WRITE_INDEX = 1
local DATA_WRITE_COUNT = TRADER_MEMORY_SIZE - DATA_WRITE_INDEX

local TraderInstruction = {
    WriteTraderBuyData = 5,
    WriteTraderSellData = 6,
    TraderBuyThingData = 7,
    TraderBuyThingChildData = 8,
    TraderBuyGasData = 9,
    TraderSellThingData = 10,
    TraderSellGasData = 11,
    TraderSellThingChildData = 12,
}

local DataRequestPhase = {
    RequestBuy = 1,
    WaitResponsBuy = 2,
    RequestSell = 3,
    WaitResponseSell = 4,
}
-- Scale diagonal directions to the same radius as cardinal directions.
local DIAGONAL_STEP_SCALE = 1 / math.sqrt(2)

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
    GradientSearch = 4,
    Error = 5,
    NoSignal = 6,
    RequestData = 7,
}

local AntennaMode = {
    Inactive = 1,
    Optimize = 2,
    FetchData = 3,
}

local AntennaStateNames = {
    [AntennaState.Idle] = "Idle",
    [AntennaState.RingSearch] = "RingSearch",
    [AntennaState.GradientSearch] = "GradientSearch",
    [AntennaState.Communication] = "Communication",
    [AntennaState.Error] = "Error",
    [AntennaState.NoSignal] = "NoSignal",
    [AntennaState.RequestData] = "RequestData",
}

local SearchPattern = {
    { h = -1, v = -1 }, 
    { h = 0,  v = -1 }, 
    { h = 1,  v = -1 }, 
    { h = 1,  v =  0 }, 
    { h = 1,  v =  1 }, 
    { h = 0,  v =  1 }, 
    { h = -1, v =  1 },
    { h = -1, v =  0 }
}

local StepPattern = {
    DIAGONAL_STEP_SCALE, 
    1, 
    DIAGONAL_STEP_SCALE,
    1,
    DIAGONAL_STEP_SCALE, 
    1, 
    DIAGONAL_STEP_SCALE,
    1
}

local function nextSearchPatternIndex(patternIndex)
    return patternIndex % #SearchPattern + 1
end

local function normalizeDishPosition(hor, vert)
    if vert < signals.MIN_VERTICAL_ANGLE then
        hor = hor + 180
        vert = -vert
    end
    return signals.normalizeHorizontal(hor), signals.clamp(vert, signals.MIN_VERTICAL_ANGLE, signals.MAX_VERTICAL_ANGLE)
end

local Antenna = {
    StateMachine = {
        [AntennaState.Idle] = { enter = nil, exit = nil, next = nil },
        [AntennaState.RingSearch] = { enter = nil, exit = nil, next = nil },
        [AntennaState.GradientSearch] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Communication] = { enter = nil, exit = nil, next = nil },
        [AntennaState.Error] = { enter = nil, exit = nil, next = nil },
        [AntennaState.NoSignal] = { enter = nil, exit = nil, next = nil },
        [AntennaState.RequestData] = { enter = nil, exit = nil, next = nil },
    },
}
Antenna.__index = Antenna

function Antenna.new(slot, dishName)
    local self = setmetatable({
        slot = slot,
        currentState = AntennaState.Idle,
        mode = AntennaMode.Inactive,
        signalId = signals.INVALID,
        dish = dishes.Dish.new(dishName),
        searchArea = {
            patternIndex = 0,
            startPatternIndex = 1,
            pointsChecked = 0,
            positionCandidate = { h = signals.INVALID, v = signals.INVALID },
        },
        centralPoint = {
            angularDistance = signals.INVALID,
            wattsReachingContact = signals.INVALID,
            h = signals.INVALID,
            v = signals.INVALID,
        },
        waitingToCentrating = false,
        signalIsValid = false,
        readAttempts = 0,
        readAttemptsLimit = READ_ATTEMPTS_ANTENNA_LIMIT,
        optimizationResolution = OPTIMIZATION_RESOLUTION,
        RequestParameters = {
            dataRequestPhase = DataRequestPhase.RequestBuy,
            response = nil,
            onDataRequested = nil,
        },
    }, Antenna)
    self.StateMachine[self.currentState].enter(self)
    return self
end

function Antenna:getStep()
    if self.centralPoint.angularDistance == signals.INVALID then return SEARCH_STEP_MIDPOINT end
    if self.currentState == AntennaState.GradientSearch then
        return signals.clamp(self.centralPoint.angularDistance / 2, 1, SEARCH_STEP_MIDPOINT)
    end
    return signals.clamp(self.centralPoint.angularDistance, 1, SEARCH_STEP)
end

function Antenna:setSearchPosition(patternIndex)
    local pattern = SearchPattern[patternIndex]
    local baseStep = self:getStep()
    local moveStep = baseStep * StepPattern[patternIndex]
    self.searchArea.patternIndex = patternIndex
    local hor, vert = normalizeDishPosition(
        self.centralPoint.h + moveStep * pattern.h,
        self.centralPoint.v + moveStep * pattern.v
    )
    self.searchArea.positionCandidate.h = hor
    self.searchArea.positionCandidate.v = vert
    print(
        "Position base:" .. string.format("%.2f", baseStep) ..
        " move:" .. string.format("%.2f", moveStep) ..
        " h:" .. string.format("%.2f", hor) ..
        " v:" .. string.format("%.2f", vert) ..
        " idx:" .. patternIndex ..
        " c.h:" .. string.format("%.2f", self.centralPoint.h) ..
        " c.v:" .. string.format("%.2f", self.centralPoint.v)
    )
    self.dish:setPosition(self.searchArea.positionCandidate.h, self.searchArea.positionCandidate.v)
end

function Antenna:continueGradientSearch()
    self:setSearchPosition(self.searchArea.patternIndex)
end

function Antenna:startSearchRing(patternIndex)
    self.searchArea.startPatternIndex = patternIndex
    self.searchArea.pointsChecked = 0
    self:setSearchPosition(patternIndex)
end

function Antenna:getOppoiste(patternIndex)
    local size = #SearchPattern
    return (patternIndex - 1 + size / 2) % size + 1
end

function Antenna:returnToCenter()
    self.dish:setPosition(self.centralPoint.h, self.centralPoint.v)
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

function Antenna:setMode(mode)
    self.mode = mode
end

function Antenna:setOptimizationResolution(resolution)
    self.optimizationResolution = resolution
end

function Antenna:setReadAttemptsLimit(limit)
    self.readAttemptsLimit = limit
end

function Antenna:readDishData()
    self.signalIsValid = false
    self.dish:readData()
    self.signalIsValid = signals.isValidReading(self.dish.signal.AngularDistance) and
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

function Antenna:updateCentralPointFromDish()
    self.centralPoint.angularDistance = self.dish.signal.AngularDistance
    self.centralPoint.wattsReachingContact = self.dish.signal.WattsReachingContact
    self.centralPoint.h = self.dish.horizontal
    self.centralPoint.v = self.dish.vertical
    self:updateSignalBack(self.dish.signal, self.dish.horizontal, self.dish.vertical, true)
end

function Antenna:printState(message)
    print(
        "slot:" .. self.slot ..
        " st:" .. (AntennaStateNames[self.currentState] or "Unknown") ..
        " id:" .. self.signalId ..
        " ang0:" .. string.format("%.2f", self.centralPoint.angularDistance) ..
        " angP:" .. string.format("%.2f", self.dish.signal.AngularDistance) ..
        " pow0:" .. string.format("%.2f", self.centralPoint.wattsReachingContact) ..
        " powP:" .. string.format("%.2f", self.dish.signal.WattsReachingContact) ..
        " cntr:" .. string.format("%.1f", self.centralPoint.h) .. ":" .. string.format("%.1f", self.centralPoint.v) ..
        " pos:" .. string.format("%.1f", self.searchArea.positionCandidate.h) .. ":" .. string.format("%.1f", self.searchArea.positionCandidate.v) ..
        " idx:" .. self.searchArea.patternIndex ..
        " src:" .. (SignalList:getPosSource(self.slot, self.signalId) or 0) ..
        " " .. message
    )
end

Antenna.StateMachine[AntennaState.Idle].enter = function(self)
    self.searchArea.patternIndex = 0
    self.signalId = signals.INVALID
    self.signalIsValid = false
end

Antenna.StateMachine[AntennaState.Idle].exit = function(self)
end

Antenna.StateMachine[AntennaState.Idle].next = function(self)
    if self.mode == AntennaMode.FetchData then
        if SignalList:getBySlot(self.slot) ~= nil then return AntennaState.RequestData end
        return AntennaState.Idle
    end
    if self.mode == AntennaMode.Optimize and self.slot ~= signals.INVALID then
        if self:initializeRingSearch() then return AntennaState.RingSearch end
        print("Can't initialize ring search")
        return AntennaState.NoSignal
    end
    return AntennaState.Idle
end

function Antenna:initializeRingSearch()
    self.searchArea.patternIndex = 1
    self.searchArea.startPatternIndex = 1
    self.searchArea.pointsChecked = 0
    self.waitingToCentrating = false
    self.signalIsValid = false
    self.readAttempts = 0

    local data = SignalList:getBySlot(self.slot)
    if data == nil then
        self.signalId = signals.INVALID
        return false
    end

    self.signalId = data.signal.Id
    self.centralPoint.angularDistance = data.signal.AngularDistance
    self.centralPoint.wattsReachingContact = data.signal.WattsReachingContact
    self.centralPoint.h = data.bestHorizontal
    self.centralPoint.v = data.bestVertical
    if signals.isWithinResolution(self.centralPoint.angularDistance, self.optimizationResolution) then
        self.waitingToCentrating = true
        self:updateSignalBack(data.signal, self.centralPoint.h, self.centralPoint.v, false)
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
    self.waitingToCentrating = false
    self.dish:clearContactFilter()
end

Antenna.StateMachine[AntennaState.RingSearch].next = function(self)
    if self.mode ~= AntennaMode.Optimize then return AntennaState.Idle end
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self.signalId == signals.INVALID then return AntennaState.NoSignal end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    if not self.dish:isIdle() then
        return AntennaState.RingSearch
    end
    if self.waitingToCentrating and self.dish:isIdle() then --This means that we already have found the best positiona and jsut wait antenna
        return AntennaState.Communication
    end

    self:readDishData()
    if not self.signalIsValid then
        self.readAttempts = self.readAttempts + 1
        if self.readAttempts < self.readAttemptsLimit then
            return AntennaState.RingSearch
        end
    end
    self.readAttempts = 0

    self:printState("read")
    if self.dish.signal.Id ~= self.signalId and signals.isValidReading(self.dish.signal.Id) then --Not my signal
        SignalList:removeSignal(self.slot, self.signalId)
        return AntennaState.NoSignal
    end

    if self.signalId == self.dish.signal.Id then
        if signals.isWithinResolution(self.dish.signal.AngularDistance, self.optimizationResolution) then
            self:updateCentralPointFromDish()
            return AntennaState.Communication
        end

        if self.signalIsValid and signals.isBetterSignalSample(self.dish.signal.WattsReachingContact, self.centralPoint.wattsReachingContact) then
            local oldAngleIsValid = signals.isValidReading(self.centralPoint.angularDistance)
            self:updateCentralPointFromDish()
            if not oldAngleIsValid then -- have found some signal after start with invalid one
                self:startSearchRing(self.searchArea.patternIndex)
                self:printState("found")
                return AntennaState.RingSearch
            end
            self:printState("start gradient")
            return AntennaState.GradientSearch
        end
    end

    self.searchArea.pointsChecked = self.searchArea.pointsChecked + 1
    if (self.searchArea.pointsChecked == #SearchPattern) or not moveToNextSearchPosition(self) then
        if not signals.isValidReading(self.centralPoint.wattsReachingContact) then return AntennaState.Error end
        self:updateSignalBack(nil, self.centralPoint.h, self.centralPoint.v, true)
        self:returnToCenter()
        self.waitingToCentrating = true
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
    self.waitingToCentrating = false
    self.dish:clearContactFilter()
end

Antenna.StateMachine[AntennaState.GradientSearch].next = function(self)
    if self.mode ~= AntennaMode.Optimize then return AntennaState.Idle end
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self.signalId == signals.INVALID then return AntennaState.NoSignal end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end

    if not self.dish:isIdle() then
        return AntennaState.GradientSearch
    end
    if self.waitingToCentrating then
        return AntennaState.Communication
    end

    self:readDishData()
    if not self.signalIsValid then
        self.readAttempts = self.readAttempts + 1
        if self.readAttempts < self.readAttemptsLimit then
            return AntennaState.GradientSearch
        end
    end
    self.readAttempts = 0

    self:printState("move gradient")
    if self.dish.signal.Id ~= self.signalId and signals.isValidReading(self.dish.signal.Id) then
        SignalList:removeSignal(self.slot, self.signalId)
        return AntennaState.NoSignal
    end

    if self.signalId == self.dish.signal.Id then
        if signals.isWithinResolution(self.dish.signal.AngularDistance, self.optimizationResolution) then
            self:updateCentralPointFromDish()
            return AntennaState.Communication
        end

        if self.signalIsValid and signals.isBetterSignalSample(self.dish.signal.WattsReachingContact, self.centralPoint.wattsReachingContact) then
            self:updateCentralPointFromDish()
            self:continueGradientSearch()
            return AntennaState.GradientSearch
        end
    end

    --self:startSearchRing(self:getOppoiste(self.searchArea.patternIndex))
    self:startSearchRing(self.searchArea.patternIndex)
    self:printState("gradient ended")
    return AntennaState.RingSearch
end

Antenna.StateMachine[AntennaState.NoSignal].enter = function(self)
    self.searchArea.patternIndex = 0
    self.searchArea.pointsChecked = 0
    self.signalId = signals.INVALID
end

Antenna.StateMachine[AntennaState.NoSignal].exit = function(self)
end

Antenna.StateMachine[AntennaState.NoSignal].next = function(self)
    if self.mode ~= AntennaMode.Optimize then return AntennaState.Idle end
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if SignalList:getBySlot(self.slot) ~= nil then
        if self:initializeRingSearch() then return AntennaState.RingSearch end
    end
    return AntennaState.NoSignal
end

Antenna.StateMachine[AntennaState.Error].enter = function(self)
    self.searchArea.patternIndex = 0
    self.searchArea.pointsChecked = 0
end

Antenna.StateMachine[AntennaState.Error].exit = function(self)
end

Antenna.StateMachine[AntennaState.Error].next = function(self)
    if self.mode ~= AntennaMode.Optimize then return AntennaState.Idle end
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
    if self.mode ~= AntennaMode.Optimize then return AntennaState.Idle end
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self:getCurrentSignalData() == nil then return AntennaState.NoSignal end
    self:readDishData()
    if not self.signalIsValid then return AntennaState.Communication end
    if self.dish.signal.Id ~= self.signalId then
        SignalList:removeSignal(self.slot, self.signalId)
        return AntennaState.NoSignal
    end
    return AntennaState.Communication
end

local function makeWriteInstruction(opcode, writeIndex, writeCount)
    return bit_or(opcode, bit_or(bit_sll(writeIndex, 8), bit_sll(writeCount, 16)))
end

function Antenna:writeDataRequest(opcode)
    if self.dish.device == nil then return false end
    mem_clear_id(self.dish.device)
    mem_put_id(self.dish.device, 0, makeWriteInstruction(opcode, DATA_WRITE_INDEX, DATA_WRITE_COUNT))
    return true
end

function Antenna:readTraderItems(result, readBuyResponse)
    if self.dish.device == nil then return false end
    local received = false

    for address = DATA_WRITE_INDEX, TRADER_MEMORY_SIZE - 1 do
        local value = mem_get_id(self.dish.device, address)
        if value ~= nil then
            local opcode = bit_ext(value, 0, 8)
            local quantity = bit_ext(value, 8, 8)
            local itemHash = bit_sra(value, 16)
            local target = nil
            local itemType = nil
            local isSubitem = false

            if opcode == TraderInstruction.TraderBuyThingData then
                target = result.buy
                itemType = trader.ItemType.Prefab
            elseif opcode == TraderInstruction.TraderBuyThingChildData then
                target = result.buy
                itemType = trader.ItemType.Prefab
                isSubitem = true
            elseif opcode == TraderInstruction.TraderBuyGasData then
                target = result.buy
                itemType = trader.ItemType.GasBitFlag
            elseif opcode == TraderInstruction.TraderSellThingData then
                target = result.sell
                itemType = trader.ItemType.Prefab
            elseif opcode == TraderInstruction.TraderSellThingChildData then
                target = result.sell
                itemType = trader.ItemType.Prefab
                isSubitem = true
            elseif opcode == TraderInstruction.TraderSellGasData then
                target = result.sell
                itemType = trader.ItemType.GasBitFlag
            end

            local expectedTarget = readBuyResponse and result.buy or result.sell
            if target == expectedTarget then
                target[#target + 1] = {
                    hash = itemHash,
                    type = itemType,
                    quantity = quantity,
                    isSubitem = isSubitem,
                }
                received = true
            end
        end
    end
    return received
end

function Antenna:publishTraderItems(items)
    local raw = trader.serializeItems(items)
    if raw == nil then
        print("Trader items serialization failed")
        return false
    end
    ic.net.publish(trader.TOPIC, { j = raw }, {
        retain = true,
        ttl = 10,
        include_self = false,
    })
    return true
end

Antenna.StateMachine[AntennaState.RequestData].enter = function(self)
    local data = SignalList:getBySlot(self.slot)
    if data == nil then return end
    self.signalId = data.signal.Id
    self.centralPoint.angularDistance = data.signal.AngularDistance
    self.centralPoint.wattsReachingContact = data.signal.WattsReachingContact
    self.centralPoint.h = data.bestHorizontal
    self.centralPoint.v = data.bestVertical
    self.RequestParameters.dataRequestPhase = DataRequestPhase.RequestBuy
    self.RequestParameters.response = {
        slot = self.slot,
        traderId = self.signalId,
        sell = {},
        buy = {},
    }
    self.dish:setContactFilter(self.signalId)
    self:returnToCenter()
end

Antenna.StateMachine[AntennaState.RequestData].exit = function(self)
    self.dish:clearContactFilter()
    self.RequestParameters.dataRequestPhase = DataRequestPhase.RequestBuy
    self.RequestParameters.response = nil
end

Antenna.StateMachine[AntennaState.RequestData].next = function(self)
    if self.mode ~= AntennaMode.FetchData then return AntennaState.Idle end
    if self.slot == signals.INVALID then return AntennaState.Idle end
    if self:getCurrentSignalData() == nil then return AntennaState.Idle end
    if not self.dish:isIdle() then return AntennaState.RequestData end

    local request = self.RequestParameters
    if request.dataRequestPhase == DataRequestPhase.RequestBuy then
        self:writeDataRequest(TraderInstruction.WriteTraderBuyData)
        request.dataRequestPhase = DataRequestPhase.WaitResponsBuy
        return AntennaState.RequestData
    end

    if request.dataRequestPhase == DataRequestPhase.WaitResponsBuy then
        if not self:readTraderItems(request.response, true) then return AntennaState.RequestData end
        request.dataRequestPhase = DataRequestPhase.RequestSell
        return AntennaState.RequestData
    end

    if request.dataRequestPhase == DataRequestPhase.RequestSell then
        self:writeDataRequest(TraderInstruction.WriteTraderSellData)
        request.dataRequestPhase = DataRequestPhase.WaitResponseSell
        return AntennaState.RequestData
    end

    if request.dataRequestPhase == DataRequestPhase.WaitResponseSell then
        if not self:readTraderItems(request.response, false) then return AntennaState.RequestData end
        self:publishTraderItems(request.response)
        if self.dish.device ~= nil then mem_clear_id(self.dish.device) end
        self.mode = AntennaMode.Inactive
        if request.onDataRequested ~= nil then request.onDataRequested(self, request.response) end
        return AntennaState.Idle
    end

    return AntennaState.RequestData
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
    search_sw = nil,
    request_sw = nil,
    slot_dial = nil,
    res_dial = nil,
    attmpt_dial = nil,
    angle_dsp = nil,
    state_diod = nil,
    idle_diod = nil,
    stateColor = signals.INVALID,
    idleColor = signals.INVALID,
    on = false,
    search = false,
    request = false,
    slot = 0,
    res = OPTIMIZATION_RESOLUTION,
    attmpt = READ_ATTEMPTS_ANTENNA_LIMIT,
}
AntennaPanel.__index = AntennaPanel

function AntennaPanel:updatePowerSwitchColor()
    if self.on_sw == nil then return end
    ic.write_id(self.on_sw, LT.Color, self.on and Color.Green or Color.Red)
end

function AntennaPanel:updateModeSwitchColors()
    if self.search_sw ~= nil then
        ic.write_id(self.search_sw, LT.Color, self.search and Color.Orange or Color.Gray)
    end
    if self.request_sw ~= nil then
        ic.write_id(self.request_sw, LT.Color, self.request and Color.Blue or Color.Gray)
    end
end

function AntennaPanel.new(antenna, name)
    local self = setmetatable({
        name = name,
        antenna = antenna,
        on_sw = ic.find("tr-" .. name .. "-on-sw"),
        search_sw = ic.find("tr-" .. name .. "-search-sw"),
        request_sw = ic.find("tr-" .. name .. "-request-sw"),
        slot_dial = ic.find("tr-" .. name .. "-slot-dial"),
        res_dial = ic.find("tr-" .. name .. "-res-dial"),
        attmpt_dial = ic.find("tr-" .. name .. "-attmpt-dial"),
        angle_dsp = ic.find("tr-" .. name .. "-angle-dsp"),
        state_diod = ic.find("tr-" .. name .. "-state-diod"),
        idle_diod = ic.find("tr-" .. name .. "-idle-diod"),
        stateColor = signals.INVALID,
        idleColor = signals.INVALID,
        on = antenna.dish:isOn(),
        search = false,
        request = false,
        slot = antenna.slot,
        res = antenna.optimizationResolution,
        attmpt = antenna.readAttemptsLimit,
    }, AntennaPanel)

    if self.search_sw ~= nil then
        self.search = ic.read_id(self.search_sw, LT.On) == 1
    end
    if self.request_sw ~= nil then
        self.request = ic.read_id(self.request_sw, LT.On) == 1
    end
    if self.search and self.request then
        ic.write_id(self.search_sw, LT.On, 0)
        self.search = false
    end
    if self.request then
        self.antenna:setMode(AntennaMode.FetchData)
    elseif self.search then
        self.antenna:setMode(AntennaMode.Optimize)
    end

    antenna.RequestParameters.onDataRequested = function()
        if self.request_sw ~= nil then
            ic.write_id(self.request_sw, LT.On, 0)
        end
        self.request = false
        self.antenna:setMode(AntennaMode.Inactive)
        self:updateModeSwitchColors()
    end

    self:updatePowerSwitchColor()
    self:updateModeSwitchColors()

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
        local angle = self.antenna.centralPoint.angularDistance
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
            elseif self.antenna.currentState == AntennaState.RequestData then
                color = Color.Purple
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
            self:updatePowerSwitchColor()
        end
    end


    local search = self.search_sw ~= nil and ic.read_id(self.search_sw, LT.On) == 1 or false
    local request = self.request_sw ~= nil and ic.read_id(self.request_sw, LT.On) == 1 or false
    local searchChanged = search ~= self.search
    local requestChanged = request ~= self.request

    -- If both switches are changed on together, RequestData wins deterministically.
    if requestChanged and request then
        if self.search_sw ~= nil and search then
            ic.write_id(self.search_sw, LT.On, 0)
        end
        self.search = false
        self.request = true
        self.antenna:setMode(AntennaMode.FetchData)
    elseif searchChanged and search then
        if self.request_sw ~= nil and request then
            ic.write_id(self.request_sw, LT.On, 0)
        end
        self.search = true
        self.request = false
        self.antenna:setMode(AntennaMode.Optimize)
    elseif searchChanged or requestChanged then
        self.search = search
        self.request = request
        if self.request then
            self.antenna:setMode(AntennaMode.FetchData)
        elseif self.search then
            self.antenna:setMode(AntennaMode.Optimize)
        else
            self.antenna:setMode(AntennaMode.Inactive)
        end
    end
    if searchChanged or requestChanged then
        self:updateModeSwitchColors()
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
