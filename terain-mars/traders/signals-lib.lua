--@module signals
--@module dishes
-- Shared trader modules.
-- `signals` contains signal models, list sync, serialization, persistence, and pub/sub behavior.
-- `dishes` contains the reusable dish device wrapper used by scanner and antenna scripts.
local LT = ic.enums.LogicType

local signals = {}
local dishes = {}

signals.INVALID = -1
signals.EPSILON = 0.001
signals.MIN_VERTICAL_ANGLE = 0
signals.MAX_VERTICAL_ANGLE = 90
signals.STORE_KEY = "Trader.SignalList"
signals.TOPIC_SIGNALS = "signals"
signals.TOPIC_SIGNALS_UPDATE = "signals/upd"

signals.TraderType = {
    Unknown             = signals.INVALID,
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

signals.TraderTypeNames = {
    [signals.TraderType.Unknown]             = "Unknown",
    [signals.TraderType.OreTrader]           = "Ore",
    [signals.TraderType.AlloyTrader]         = "Alloy",
    [signals.TraderType.HydroponicsTrader]   = "Hydroponics",
    [signals.TraderType.GasTrader]           = "Gas",
    [signals.TraderType.ConstructionTrader]  = "Construction",
    [signals.TraderType.LiquidTrader]        = "Liquid",
    [signals.TraderType.FoodTrader]          = "Food",
    [signals.TraderType.HardwareTrader]      = "Hardware",
    [signals.TraderType.ConsumablesTrader]   = "Consumables",
    [signals.TraderType.ApplianceTrader]     = "Appliance",
    [signals.TraderType.GeneticsTrader]      = "Genetics",
    [signals.TraderType.RareItemsTrader]     = "RareItems",
}

signals.SignalPositionSource = {
    Sample = 1,
    BorderMidpoint = 2,
}

signals.SignalListRole = {
    Master = 1,
    Consumer = 2,
    Updater = 3,
}

-- Shallow-copy a table while preserving its metatable.
function signals.copyTable(src)
    local dst = {}
    for key, value in pairs(src) do
        dst[key] = value
    end
    return setmetatable(dst, getmetatable(src))
end

-- Clamp a numeric value to the inclusive range.
function signals.clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

-- Wrap horizontal angles into the [0, 360) range.
function signals.normalizeHorizontal(angle)
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

-- Reflect positions crossing the zenith and rotate horizontal by half a turn.
function signals.normalizeDishPosition(hor, vert)
    if vert < signals.MIN_VERTICAL_ANGLE then
        hor = hor + 180
        vert = -vert
    end
    return signals.normalizeHorizontal(hor),
        signals.clamp(vert, signals.MIN_VERTICAL_ANGLE, signals.MAX_VERTICAL_ANGLE)
end

-- Treat nil and INVALID as unreadable signal values.
function signals.isValidReading(value)
    return value ~= signals.INVALID and value ~= nil
end

-- Compare two signal samples, preferring valid and stronger watts readings.
function signals.isBetterSignalSample(left, right)
    local leftValid = signals.isValidReading(left)
    local rightValid = signals.isValidReading(right)
    if leftValid ~= rightValid then
        return leftValid
    end
    if not leftValid then
        return false
    end
    return left > right
end

-- Compare floating-point values using the module epsilon.
function signals.almostEqual(left, right)
    if left == nil or right == nil then return false end
    return math.abs(left - right) < signals.EPSILON
end

-- Check whether a reading is within the requested resolution threshold.
function signals.isWithinResolution(value, resolution)
    return signals.isValidReading(value) and (value < resolution or signals.almostEqual(value, resolution))
end

-- Round a value to two fractional digits for displays.
function signals.round2(value)
    return math.floor(value * 100 + 0.5) / 100
end

local Signal = {
    Id = signals.INVALID,
    AngularDistance = signals.INVALID,
    WattsReachingContact = signals.INVALID,
    MinimumWattsToContact = signals.INVALID,
    SizeX = signals.INVALID,
    SizeZ = signals.INVALID,
    contactTypeId = signals.TraderType.Unknown,
    contactSlotIndex = signals.INVALID,
}
Signal.__index = Signal

-- Create a new signal record, optionally cloning field values from another table.
function Signal.new(source)
    local self = setmetatable({
        Id = Signal.Id,
        AngularDistance = Signal.AngularDistance,
        WattsReachingContact = Signal.WattsReachingContact,
        MinimumWattsToContact = Signal.MinimumWattsToContact,
        SizeX = Signal.SizeX,
        SizeZ = Signal.SizeZ,
        contactTypeId = Signal.contactTypeId,
        contactSlotIndex = Signal.contactSlotIndex,
    }, Signal)
    if type(source) == "table" then
        self.Id = source.Id ~= nil and source.Id or self.Id
        self.AngularDistance = source.AngularDistance ~= nil and source.AngularDistance or self.AngularDistance
        self.WattsReachingContact = source.WattsReachingContact ~= nil and source.WattsReachingContact or self.WattsReachingContact
        self.MinimumWattsToContact = source.MinimumWattsToContact ~= nil and source.MinimumWattsToContact or self.MinimumWattsToContact
        self.SizeX = source.SizeX ~= nil and source.SizeX or self.SizeX
        self.SizeZ = source.SizeZ ~= nil and source.SizeZ or self.SizeZ
        self.contactTypeId = source.contactTypeId ~= nil and source.contactTypeId or self.contactTypeId
        self.contactSlotIndex = source.contactSlotIndex ~= nil and source.contactSlotIndex or self.contactSlotIndex
    end
    return self
end

-- Convert a signal to its compact flat serialized form.
function Signal:serialize()
    return {
        id = self.Id,
        ad = self.AngularDistance,
        wr = self.WattsReachingContact,
        mw = self.MinimumWattsToContact,
        sx = self.SizeX,
        sz = self.SizeZ,
        ct = self.contactTypeId,
        cs = self.contactSlotIndex,
    }
end

-- Recreate a signal from the compact serialized form.
function Signal.fromSerialized(data)
    return Signal.new({
        Id = data.id,
        AngularDistance = data.ad,
        WattsReachingContact = data.wr,
        MinimumWattsToContact = data.mw,
        SizeX = data.sx,
        SizeZ = data.sz,
        contactTypeId = data.ct,
        contactSlotIndex = data.cs,
    })
end

-- Format a signal for debug logging.
function Signal:toDebugString()
    return "Signal ID:" .. self.Id ..
        " Angular:" .. string.format("%.2f", self.AngularDistance) ..
        " Power:" .. string.format("%.2f", self.WattsReachingContact) ..
        " MinPower:" .. string.format("%.2f", self.MinimumWattsToContact) ..
        " Size:" .. tostring(self.SizeX) .. "x" .. tostring(self.SizeZ) ..
        " Type:" .. (signals.TraderTypeNames[self.contactTypeId] or "Unknown") ..
        " Slot:" .. self.contactSlotIndex
end

signals.Signal = Signal

local SignalData = {}
SignalData.__index = SignalData

-- Wrap a signal with scan/version/position metadata used in the shared list.
function SignalData.new(version, signal, hor, vert, positionSource)
    hor, vert = signals.normalizeDishPosition(hor, vert)
    return setmetatable({
        version = version,
        signal = Signal.new(signal),
        bestHorizontal = hor,
        bestVertical = vert,
        positionSource = positionSource or signals.SignalPositionSource.Sample,
    }, SignalData)
end

-- Convert a slot entry to its compact serialized form.
function SignalData:serialize(slot)
    local payload = self.signal:serialize()
    payload.sl = slot
    payload.vr = self.version
    payload.bh = self.bestHorizontal
    payload.bv = self.bestVertical
    payload.ps = self.positionSource
    return payload
end

-- Recreate a slot entry from serialized data and return its slot number.
function SignalData.fromSerialized(data)
    if type(data) ~= "table" then return nil, nil end
    if data.sl == nil or data.id == nil or data.cs == nil then return nil, nil end
    return data.sl, SignalData.new(
        data.vr or -1,
        Signal.fromSerialized(data),
        data.bh or signals.INVALID,
        data.bv or signals.INVALID,
        data.ps or signals.SignalPositionSource.Sample
    )
end

local Dish = {
    device = nil,
    vertical = signals.INVALID,
    horizontal = signals.INVALID,
    signal = Signal.new(),
}
Dish.__index = Dish

-- Find a dish device by name and prepare a reusable wrapper around it.
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

-- Report whether the dish is idle and ready for the next action.
function Dish:isIdle()
    if self.device == nil then return false end
    return ic.read_id(self.device, LT.Idle) == 1
end

-- Read orientation and current signal fields from the dish device.
function Dish:readData()
    if self.device == nil then return end
    local function readOptional(logicName, fallback)
        local logicType = LT[logicName]
        if logicType == nil then return fallback end
        local ok, value = pcall(ic.read_id, self.device, logicType)
        if not ok or value == nil then return fallback end
        return value
    end

    self.horizontal = ic.read_id(self.device, LT.Horizontal)
    self.vertical = ic.read_id(self.device, LT.Vertical)
    self.signal.Id = ic.read_id(self.device, LT.SignalID)
    self.signal.AngularDistance = ic.read_id(self.device, LT.SignalStrength)
    self.signal.WattsReachingContact = ic.read_id(self.device, LT.WattsReachingContact)
    self.signal.MinimumWattsToContact = readOptional("MinimumWattsToContact", readOptional("MinWattsToContact", signals.INVALID))
    self.signal.SizeX = readOptional("SizeX", readOptional("SignalSizeX", signals.INVALID))
    self.signal.SizeZ = readOptional("SizeZ", readOptional("SignalSizeZ", signals.INVALID))
    self.signal.contactTypeId = ic.read_id(self.device, LT.ContactTypeId)
    self.signal.contactSlotIndex = ic.read_id(self.device, LT.ContactSlotIndex)
end

-- Report whether the dish device is powered on.
function Dish:isOn()
    if self.device == nil then return false end
    return ic.read_id(self.device, LT.On) == 1
end

-- Switch the dish device power state.
function Dish:setOn(on)
    if self.device == nil then return false end
    ic.write_id(self.device, LT.On, on and 1 or 0)
    return true
end

-- Move the dish to a safe normalized horizontal/vertical position.
function Dish:setPosition(hor, vert)
    if self.device == nil then
        print("Dish setPosition failed: device not found")
        return false
    end
    hor, vert = signals.normalizeDishPosition(hor, vert)
    ic.write_id(self.device, LT.Horizontal, hor)
    ic.write_id(self.device, LT.Vertical, vert)
    return true
end

-- Apply a contact filter so the dish tracks one signal id.
function Dish:setContactFilter(id)
    if self.device == nil then
        print("Dish setContactFilter failed: device not found")
        return false
    end
    ic.write_id(self.device, LT.BestContactFilter, id)
    return true
end

-- Clear the current dish contact filter.
function Dish:clearContactFilter()
    return self:setContactFilter(signals.INVALID)
end

dishes.Dish = Dish

local SignalList = {}
SignalList.__index = SignalList

-- Extract the raw JSON string from a network payload wrapper.
local function extractRawPayload(payload)
    if type(payload) == "string" then
        return payload
    end
    if type(payload) ~= "table" then
        return nil
    end
    if type(payload.j) == "string" then
        return payload.j
    end
    if type(payload.raw) == "string" then
        return payload.raw
    end
    return nil
end

-- Create a role-aware shared signal list instance.
function SignalList.new(role, options)
    options = options or {}
    return setmetatable({
        role = role or signals.SignalListRole.Consumer,
        storeKey = options.storeKey or signals.STORE_KEY,
        fullTopic = options.fullTopic or signals.TOPIC_SIGNALS,
        updateTopic = options.updateTopic or signals.TOPIC_SIGNALS_UPDATE,
        currentVersion = 0,
        data = {},
        isDirty = false,
        onFullSync = options.onFullSync,
    }, SignalList)
end

-- Mark the master list as changed so it will be persisted and republished.
function SignalList:_markDirty()
    self.isDirty = true
end

-- Return the slot entry stored for a given slot.
function SignalList:getBySlot(slot)
    return self.data[slot]
end

-- Return the signal id stored in a slot, or INVALID when absent.
function SignalList:findSignalIdBySlot(slot)
    local data = self:getBySlot(slot)
    if data == nil then return signals.INVALID end
    return data.signal.Id
end

-- Return the position source for a specific slot/id pair.
function SignalList:getPosSource(slot, id)
    local data = self:getBySlot(slot)
    if data == nil or data.signal.Id ~= id then return nil end
    return data.positionSource
end

-- Local position update helper. Updaters must publish through `updateSignalBack(..., true)`.
function SignalList:setBestPosition(slot, id, hor, vert)
    local data = self:getBySlot(slot)
    if data == nil or data.signal.Id ~= id then return false end
    data.bestHorizontal, data.bestVertical = signals.normalizeDishPosition(hor, vert)
    if self.role == signals.SignalListRole.Master then
        self:_markDirty()
    end
    return true
end

-- Update the stored position source for a specific slot/id pair.
function SignalList:setPosSource(slot, id, positionSource)
    local data = self:getBySlot(slot)
    if data == nil or data.signal.Id ~= id then return false end
    data.positionSource = positionSource
    if self.role == signals.SignalListRole.Master then
        self:_markDirty()
    end
    return true
end

-- Remove any slot entry without checking its signal id.
function SignalList:removeBySlot(slot)
    if self.data[slot] == nil then return false end
    self.data[slot] = nil
    if self.role == signals.SignalListRole.Master then
        self:_markDirty()
    end
    return true
end

-- Remove a slot entry only when the stored signal id matches.
function SignalList:removeSignal(slot, id)
    local data = self:getBySlot(slot)
    if data == nil or data.signal.Id ~= id then return false end
    self.data[slot] = nil
    if self.role == signals.SignalListRole.Master then
        self:_markDirty()
    end
    return true
end

-- Merge a scanner sample into the list using slot and watts precedence rules.
function SignalList:update(signal, hor, vert)
    local slot = signal.contactSlotIndex
    if slot == signals.INVALID then return false end

    local found = self.data[slot]
    if found ~= nil then
        found.version = self.currentVersion
        if found.signal.Id ~= signal.Id then
            print("Replace slot:" .. slot .. " " .. signal:toDebugString())
            self.data[slot] = SignalData.new(self.currentVersion, signal, hor, vert, signals.SignalPositionSource.Sample)
            self:_markDirty()
            return true
        end
        if signals.isBetterSignalSample(signal.WattsReachingContact, found.signal.WattsReachingContact) then
            print(
                "Update " ..
                signal:toDebugString() ..
                " pos:" ..
                string.format("%.2f", hor) ..
                ":" ..
                string.format("%.2f", vert)
            )
            found.signal = Signal.new(signal)
            found.bestHorizontal, found.bestVertical = signals.normalizeDishPosition(hor, vert)
            found.positionSource = signals.SignalPositionSource.Sample
            self:_markDirty()
            return true
        end
        return false
    end

    print("New " .. signal:toDebugString())
    self.data[slot] = SignalData.new(self.currentVersion, signal, hor, vert, signals.SignalPositionSource.Sample)
    self:_markDirty()
    return true
end

-- Apply a better local reading back into the list and optionally publish it.
function SignalList:updateSignalBack(slot, id, signal, hor, vert, publishUpdate)
    local data = self:getBySlot(slot)
    if data == nil or data.signal.Id ~= id then return false end

    local nextSignal = Signal.new(signal or data.signal)
    local normalizedHorizontal, normalizedVertical = signals.normalizeDishPosition(hor, vert)
    local sameAngularDistance = (data.signal.AngularDistance == nextSignal.AngularDistance) or
        (signals.isValidReading(data.signal.AngularDistance) and signals.isValidReading(nextSignal.AngularDistance) and signals.almostEqual(data.signal.AngularDistance, nextSignal.AngularDistance))
    local sameWatts = data.signal.WattsReachingContact == nextSignal.WattsReachingContact
    local sameMinWatts = data.signal.MinimumWattsToContact == nextSignal.MinimumWattsToContact
    local sameSize = data.signal.SizeX == nextSignal.SizeX and data.signal.SizeZ == nextSignal.SizeZ
    local sameHorizontal = signals.almostEqual(data.bestHorizontal, normalizedHorizontal)
    local sameVertical = signals.almostEqual(data.bestVertical, normalizedVertical)
    local sameSource = data.positionSource == signals.SignalPositionSource.Sample

    if sameAngularDistance and sameWatts and sameMinWatts and sameSize and sameHorizontal and sameVertical and sameSource then
        return false
    end

    data.signal = nextSignal
    data.bestHorizontal = normalizedHorizontal
    data.bestVertical = normalizedVertical
    data.positionSource = signals.SignalPositionSource.Sample
    data.version = self.currentVersion
    if self.role == signals.SignalListRole.Master then
        self:_markDirty()
    end
    if publishUpdate and self.role == signals.SignalListRole.Updater then
        self:publishSlotUpdate(slot)
    end
    return true
end

-- Toggle scan version so the next cycle can identify outdated slots.
function SignalList:initScan()
    if self.currentVersion == 0 then
        self.currentVersion = 1
    else
        self.currentVersion = 0
    end
end

-- Remove slots not refreshed during the current scan version.
function SignalList:removeOutdated()
    local keys = {}
    for key, value in pairs(self.data) do
        if value.version ~= self.currentVersion then
            print("Signal slot:" .. key .. " ID:" .. value.signal.Id .. " outdated")
            keys[#keys + 1] = key
        end
    end
    if #keys == 0 then return false end
    for i = 1, #keys do
        self.data[keys[i]] = nil
    end
    self:_markDirty()
    return true
end

-- Print the current list contents for debug output.
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

-- Build a slot-ordered array view for consumers that need stable iteration.
function SignalList:getSortedEntries()
    local items = {}
    for slot, value in pairs(self.data) do
        items[#items + 1] = { slot = slot, value = value }
    end
    table.sort(items, function(left, right)
        return left.slot < right.slot
    end)
    return items
end

-- Serialize the whole list to one JSON payload string.
function SignalList:serializeAll()
    local payload = {
        cv = self.currentVersion,
        d = {},
    }
    for slot, value in pairs(self.data) do
        payload.d[#payload.d + 1] = value:serialize(slot)
    end
    local ok, raw = pcall(util.json.encode, payload)
    if not ok then
        return nil
    end
    return raw
end

-- Serialize one slot entry to one JSON payload string.
function SignalList:serializeSlot(slot)
    local data = self:getBySlot(slot)
    if data == nil then return nil end
    local ok, raw = pcall(util.json.encode, data:serialize(slot))
    if not ok then
        return nil
    end
    return raw
end

-- Merge one incoming slot entry with optional same-slot replacement.
function SignalList:_mergeSlotData(slot, value, allowReplace)
    local current = self.data[slot]
    if current == nil then
        self.data[slot] = value
        return true
    end

    if current.signal.Id ~= value.signal.Id then
        if not allowReplace then
            return false
        end
        self.data[slot] = value
        return true
    end

    if not signals.isBetterSignalSample(value.signal.WattsReachingContact, current.signal.WattsReachingContact) then
        return false
    end

    self.data[slot] = value
    return true
end

-- Apply an authoritative full-list payload, including remote removals.
function SignalList:applyFullRaw(raw)
    if type(raw) ~= "string" then return false end
    local ok, decoded = pcall(util.json.decode, raw)
    if not ok or type(decoded) ~= "table" or type(decoded.d) ~= "table" then
        print("SignalList apply full payload failed")
        return false
    end

    local incoming = {}
    local changed = false
    for _, payload in pairs(decoded.d) do
        local slot, data = SignalData.fromSerialized(payload)
        if slot ~= nil and data ~= nil then
            incoming[slot] = data
        end
    end

    for slot, _ in pairs(self.data) do
        if incoming[slot] == nil then
            self.data[slot] = nil
            changed = true
        end
    end

    for slot, value in pairs(incoming) do
        if self:_mergeSlotData(slot, value, true) then
            changed = true
        end
    end

    if decoded.cv ~= nil then
        self.currentVersion = decoded.cv
    end
    return changed
end

-- Apply a single-slot update payload without replacing a different signal id.
function SignalList:applySlotRaw(raw)
    if type(raw) ~= "string" then return false end
    local ok, decoded = pcall(util.json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        print("SignalList apply slot payload failed")
        return false
    end

    local slot, value = SignalData.fromSerialized(decoded)
    if slot == nil or value == nil then
        return false
    end

    value.version = self.currentVersion
    if not self:_mergeSlotData(slot, value, false) then
        return false
    end
    if self.role == signals.SignalListRole.Master then
        self:_markDirty()
    end
    return true
end

-- Persist the current master list state to the IC save store.
function SignalList:save(raw)
    if self.role ~= signals.SignalListRole.Master or not self.isDirty then return false end
    raw = raw or self:serializeAll()
    if raw == nil then
        print("SignalList save failed")
        return false
    end
    ic.persist.set(self.storeKey, raw)
    return true
end

-- Restore the master list state from the IC save store.
function SignalList:restore()
    if self.role ~= signals.SignalListRole.Master or not ic.persist.has(self.storeKey) then return false end
    local raw = ic.persist.get(self.storeKey)
    if type(raw) ~= "string" then return false end
    local changed = self:applyFullRaw(raw)
    self.isDirty = false
    return changed
end

-- Remove the persisted master list state from the IC save store when supported.
function SignalList:clearStore()
    if self.role ~= signals.SignalListRole.Master then return false end
    ic.persist.set(self.storeKey, nil)
    return true
end

-- Publish the full master list as a retained network payload.
function SignalList:publishFull(raw)
    if self.role ~= signals.SignalListRole.Master then return false end
    raw = raw or self:serializeAll()
    if raw == nil then
        print("SignalList publish failed")
        return false
    end
    ic.net.publish(self.fullTopic, { j = raw }, {
        retain = true,
        ttl = 10,
        include_self = false,
    })
    self.isDirty = false
    return true
end

-- Clear the retained full-list topic by publishing nil with the same options.
function SignalList:clearPublishedFull()
    if self.role ~= signals.SignalListRole.Master then return false end
    ic.net.publish(self.fullTopic, nil, {
        retain = true,
        ttl = 10,
        include_self = false,
    })
    self.isDirty = false
    return true
end

-- Publish one updater-owned slot improvement on the update topic.
function SignalList:publishSlotUpdate(slot)
    if self.role ~= signals.SignalListRole.Updater then return false end
    local raw = self:serializeSlot(slot)
    if raw == nil then
        return false
    end
    ic.net.publish(self.updateTopic, { j = raw }, {
        include_self = false,
    })
    return true
end

-- Persist and publish the master list using one shared serialized payload.
function SignalList:flush()
    if self.role ~= signals.SignalListRole.Master or not self.isDirty then return false end
    local raw = self:serializeAll()
    if raw == nil then
        print("SignalList flush failed")
        return false
    end
    self:save(raw)
    self:publishFull(raw)
    return true
end

-- Subscribe the list instance to the topics required by its role.
function SignalList:start()
    if self.role == signals.SignalListRole.Master then
        local updateTopic = self.updateTopic
        ic.net.subscribe(updateTopic, function(_, payload)
            local raw = extractRawPayload(payload)
            if raw ~= nil then
                self:applySlotRaw(raw)
            end
        end)
    else
        local fullTopic = self.fullTopic
        ic.net.subscribe(fullTopic, function(_, payload)
            local raw = extractRawPayload(payload)
            if raw ~= nil then
                self:applyFullRaw(raw)
                if self.onFullSync ~= nil then
                    self.onFullSync(self)
                end
            end
        end)
    end
end

-- Clear all local list contents and reset scan version state.
function SignalList:clear()
    self.data = {}
    self.currentVersion = 0
    if self.role == signals.SignalListRole.Master then
        self:_markDirty()
    end
end

signals.SignalList = SignalList

return {
    signals = signals,
    dishes = dishes,
}
