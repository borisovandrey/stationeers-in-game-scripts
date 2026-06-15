-- Trader signals screen.
-- Builds a Scripted Screens surface that refreshes on each full-list update from the scanner.
local signals = require("signals")

local SURFACE_NAME = "main"
local USE_FAKE_DATA = true
local ROOT_ID = "signals-root"
local PADDING = 8
local TITLE_HEIGHT = 20
local SUBTITLE_HEIGHT = 14
local HEADER_HEIGHT = 18
local ROW_HEIGHT = 18
local ROW_GAP = 3
local CELL_GAP = 6

local TITLE_COLOR = "#F8FAFC"
local SUBTITLE_COLOR = "#94A3B8"
local HEADER_BG = "#1E293B"
local HEADER_TEXT = "#E2E8F0"
local EMPTY_BG = "#0F172A"
local EMPTY_TEXT = "#64748B"
local ROW_TEXT = "#F8FAFC"
local ROOT_BG = "#020617"

local TRADER_TEXT_COLORS = {
    [signals.TraderType.Unknown] = "#CBD5E1",
    [signals.TraderType.OreTrader] = "#F59E0B",
    [signals.TraderType.AlloyTrader] = "#D1D5DB",
    [signals.TraderType.HydroponicsTrader] = "#4ADE80",
    [signals.TraderType.GasTrader] = "#22D3EE",
    [signals.TraderType.ConstructionTrader] = "#FB923C",
    [signals.TraderType.LiquidTrader] = "#60A5FA",
    [signals.TraderType.FoodTrader] = "#F97316",
    [signals.TraderType.HardwareTrader] = "#E5E7EB",
    [signals.TraderType.ConsumablesTrader] = "#C084FC",
    [signals.TraderType.ApplianceTrader] = "#93C5FD",
    [signals.TraderType.GeneticsTrader] = "#F472B6",
    [signals.TraderType.RareItemsTrader] = "#FDE047",
}

local SignalList
local ui = ss.ui.surface(SURFACE_NAME)

ss.ui.activate(SURFACE_NAME)

local Screen = {
    rows = {},
    dirty = true,
}

local FAKE_ROWS = {
    { slot = "0", typeName = "Ore",          size = "2 x 3", angle = "14.25", minWatts = "120.00", watts = "186.40", id = "40121", color = TRADER_TEXT_COLORS[signals.TraderType.OreTrader] },
    { slot = "1", typeName = "Alloy",        size = "4 x 4", angle = "8.10",  minWatts = "210.00", watts = "264.55", id = "40122", color = TRADER_TEXT_COLORS[signals.TraderType.AlloyTrader] },
    { slot = "2", typeName = "Hydroponics",  size = "3 x 5", angle = "3.45",  minWatts = "90.00",  watts = "144.10", id = "40123", color = TRADER_TEXT_COLORS[signals.TraderType.HydroponicsTrader] },
    { slot = "3", typeName = "Gas",          size = "6 x 2", angle = "19.80", minWatts = "240.00", watts = "311.90", id = "40124", color = TRADER_TEXT_COLORS[signals.TraderType.GasTrader] },
    { slot = "4", typeName = "Liquid",       size = "2 x 2", angle = "6.75",  minWatts = "160.00", watts = "225.30", id = "40125", color = TRADER_TEXT_COLORS[signals.TraderType.LiquidTrader] },
    { slot = "5", typeName = "RareItems",    size = "7 x 3", angle = "1.95",  minWatts = "420.00", watts = "509.70", id = "40126", color = TRADER_TEXT_COLORS[signals.TraderType.RareItemsTrader] },
}

-- Build the compact row model used by the nested screen layout.
local function formatSignalRow(slot, data)
    local signal = data.signal
    return {
        slot = tostring(slot),
        typeName = signals.TraderTypeNames[signal.contactTypeId] or "Unknown",
        size = tostring(signal.SizeX) .. " x " .. tostring(signal.SizeZ),
        angle = string.format("%.2f", signal.AngularDistance),
        minWatts = string.format("%.2f", signal.MinimumWattsToContact),
        watts = string.format("%.2f", signal.WattsReachingContact),
        id = tostring(signal.Id),
        color = TRADER_TEXT_COLORS[signal.contactTypeId] or TRADER_TEXT_COLORS[signals.TraderType.Unknown],
    }
end

-- Build one fixed-width row label for the nested horizontal layout.
local function buildCell(id, text, width, color)
    return {
        id = id,
        type = "label",
        rect = { w = width, h = ROW_HEIGHT },
        props = { text = text },
        style = {
            color = color or ROW_TEXT,
            font_size = 10,
            align = "left",
        },
    }
end

-- Build the shared header row.
local function buildHeaderRow()
    return {
        id = "signals-header-bg",
        type = "panel",
        layout = "flex",
        direction = "row",
        rect = { h = HEADER_HEIGHT },
        gap = CELL_GAP,
        style = {
            bg = HEADER_BG,
        },
        children = {
            buildCell("hdr-slot", "Slot", 28, HEADER_TEXT),
            buildCell("hdr-type", "Type", 84, HEADER_TEXT),
            buildCell("hdr-size", "Size", 54, HEADER_TEXT),
            buildCell("hdr-angle", "Angle", 48, HEADER_TEXT),
            buildCell("hdr-min", "Min W", 52, HEADER_TEXT),
            buildCell("hdr-watts", "W Reach", 58, HEADER_TEXT),
            buildCell("hdr-id", "Signal Id", 90, HEADER_TEXT),
        },
    }
end

-- Build one trader row with a type-colored type column and neutral remaining cells.
local function buildSignalRow(rowIndex, row)
    return {
        layout = "flex",
        direction = "row",
        rect = { h = ROW_HEIGHT },
        gap = CELL_GAP,
        children = {
            buildCell("slot-" .. rowIndex, row.slot, 28),
            buildCell("type-" .. rowIndex, row.typeName, 84, row.color),
            buildCell("size-" .. rowIndex, row.size, 54),
            buildCell("angle-" .. rowIndex, row.angle, 48),
            buildCell("min-" .. rowIndex, row.minWatts, 52),
            buildCell("watts-" .. rowIndex, row.watts, 58),
            buildCell("id-" .. rowIndex, row.id, 90),
        },
    }
end

-- Build the root child list for the current screen state.
function Screen:buildChildren()
    local children = {
        {
            id = "signals-title",
            type = "label",
            rect = { h = TITLE_HEIGHT },
            props = { text = "Trader Signals" },
            style = {
                color = TITLE_COLOR,
                font_size = 16,
                align = "left",
            },
        },
        {
            id = "signals-subtitle",
            type = "label",
            rect = { h = SUBTITLE_HEIGHT },
            props = { text = "Scanner full-list sync with trader-type color coding" },
            style = {
                color = SUBTITLE_COLOR,
                font_size = 10,
                align = "left",
            },
        },
        buildHeaderRow(),
    }

    if #self.rows == 0 then
        children[#children + 1] = {
            layout = "flex",
            direction = "row",
            rect = { h = ROW_HEIGHT + 4 },
            gap = CELL_GAP,
            children = {
                {
                    id = "signals-empty-text",
                    type = "label",
                    rect = { h = ROW_HEIGHT },
                    props = { text = "No signals received" },
                    style = {
                        color = EMPTY_TEXT,
                        font_size = 10,
                        align = "left",
                    },
                },
            },
        }
        return children
    end

    for i = 1, #self.rows do
        children[#children + 1] = buildSignalRow(i, self.rows[i])
    end

    return children
end

-- Rebuild the row model from the latest shared signal list snapshot.
function Screen:rebuild()
    self.rows = {}
    if USE_FAKE_DATA then
        for i = 1, #FAKE_ROWS do
            self.rows[#self.rows + 1] = FAKE_ROWS[i]
        end
        self.dirty = true
        return
    end
    local entries = SignalList:getSortedEntries()
    for i = 1, #entries do
        local entry = entries[i]
        self.rows[#self.rows + 1] = formatSignalRow(entry.slot, entry.value)
    end
    self.dirty = true
end

-- Render the whole nested layout tree to the active Scripted Screens surface.
function Screen:render()
    local size = ui:size()
    local width = 480
    local height = 272
    if size then
        width = size.w or width
        height = size.h or height
    end

    ui:clear()
    ui:element({
        id = "signals-bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = width, h = height },
        style = { bg = ROOT_BG }
    })

    ui:layout({
        layout = "flex",
        direction = "column",
        rect = {
            unit = "px",
            x = PADDING,
            y = PADDING,
            w = width - PADDING * 2,
            h = height - PADDING * 2,
        },
        gap = ROW_GAP,
        children = self:buildChildren(),
    })
    ui:commit()
    self.dirty = false
end

SignalList = signals.SignalList.new(signals.SignalListRole.Consumer, {
    fullTopic = signals.TOPIC_SIGNALS,
    onFullSync = function()
        Screen:rebuild()
    end,
})

if USE_FAKE_DATA then
    Screen:rebuild()
else
    SignalList:start()
    Screen.dirty = true
end

function tick(dt)
    if Screen.dirty then
        Screen:render()
    end
end
