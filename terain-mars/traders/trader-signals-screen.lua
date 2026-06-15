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
local MUTED_NUMERIC_TEXT = "#64748B"
local ROOT_BG = "#020617"
local BASE_WIDTH = 480

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
    layout = nil,
    width = 480,
    height = 272,
}

local FAKE_ROWS = {
    { slot = "0", typeName = "Ore",          size = "2 x 3", angle = "14.25", minWatts = "120.00", watts = "186.40", id = "40121", color = TRADER_TEXT_COLORS[signals.TraderType.OreTrader] },
    { slot = "1", typeName = "Alloy",        size = "4 x 4", angle = "8.10",  minWatts = "210.00", watts = "264.55", id = "40122", color = TRADER_TEXT_COLORS[signals.TraderType.AlloyTrader] },
    { slot = "2", typeName = "Hydroponics",  size = "3 x 5", angle = "3.45",  minWatts = "90.00",  watts = "144.10", id = "40123", color = TRADER_TEXT_COLORS[signals.TraderType.HydroponicsTrader] },
    { slot = "3", typeName = "Gas",          size = "6 x 2", angle = "19.80", minWatts = "240.00", watts = "311.90", id = "40124", color = TRADER_TEXT_COLORS[signals.TraderType.GasTrader] },
    { slot = "4", typeName = "Liquid",       size = "2 x 2", angle = "-1.00", minWatts = "160.00", watts = "-1.00",  id = "40125", color = TRADER_TEXT_COLORS[signals.TraderType.LiquidTrader], hasInvalidTelemetry = true },
    { slot = "5", typeName = "RareItems",    size = "7 x 3", angle = "1.95",  minWatts = "420.00", watts = "509.70", id = "40126", color = TRADER_TEXT_COLORS[signals.TraderType.RareItemsTrader] },
}

-- Build layout metrics from the actual surface size so wide displays use the full width.
local function buildLayout(width)
    local contentWidth = math.max(1, width - PADDING * 2)
    local scale = math.max(1, contentWidth / BASE_WIDTH)
    local gap = math.floor(CELL_GAP * scale + 0.5)
    local rowGap = math.max(3, math.floor(ROW_GAP * scale + 0.5))
    local titleSize = math.floor(16 * scale + 0.5)
    local subtitleSize = math.floor(10 * scale + 0.5)
    local rowFontSize = math.floor(10 * scale + 0.5)
    local widths = {
        28, -- Slot
        84, -- Type
        54, -- Size
        48, -- Angle
        52, -- Min W
        58, -- W Reach
        90, -- Signal Id
    }
    local widthSum = 0
    for i = 1, #widths do
        widthSum = widthSum + widths[i]
    end
    local targetWidth = contentWidth - gap * (#widths - 1)
    local factor = 1
    if widthSum > 0 and targetWidth > 0 then
        factor = targetWidth / widthSum
    end
    for i = 1, #widths do
        widths[i] = math.max(24, math.floor(widths[i] * factor + 0.5))
    end
    return {
        gap = gap,
        rowGap = rowGap,
        titleFontSize = titleSize,
        subtitleFontSize = subtitleSize,
        rowFontSize = rowFontSize,
        widths = widths,
    }
end

-- Resolve the screen size once and cache the layout metrics for later renders.
function Screen:initLayout()
    local size = ui:size()
    if size then
        self.width = size.w or self.width
        self.height = size.h or self.height
    end
    self.layout = buildLayout(self.width)
end

-- Build the compact row model used by the nested screen layout.
local function formatSignalRow(slot, data)
    local signal = data.signal
    local hasInvalidTelemetry = signal.AngularDistance == -1 or signal.WattsReachingContact == -1
    return {
        slot = tostring(slot),
        typeName = signals.TraderTypeNames[signal.contactTypeId] or "Unknown",
        size = tostring(signal.SizeX) .. " x " .. tostring(signal.SizeZ),
        angle = string.format("%.2f", signal.AngularDistance),
        minWatts = string.format("%.2f", signal.MinimumWattsToContact),
        watts = string.format("%.2f", signal.WattsReachingContact),
        id = tostring(signal.Id),
        color = TRADER_TEXT_COLORS[signal.contactTypeId] or TRADER_TEXT_COLORS[signals.TraderType.Unknown],
        hasInvalidTelemetry = hasInvalidTelemetry,
    }
end

-- Build one fixed-width row label for the nested horizontal layout.
local function buildCell(id, text, width, color, align)
    return {
        id = id,
        type = "label",
        rect = { w = width, h = ROW_HEIGHT },
        props = { text = text },
        style = {
            color = color or ROW_TEXT,
            font_size = Screen.layout.rowFontSize,
            align = align or "left",
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
        gap = Screen.layout.gap,
        style = {
            bg = HEADER_BG,
        },
        children = {
            buildCell("hdr-slot", "Slot", Screen.layout.widths[1], HEADER_TEXT, "left"),
            buildCell("hdr-type", "Type", Screen.layout.widths[2], HEADER_TEXT),
            buildCell("hdr-size", "Size", Screen.layout.widths[3], HEADER_TEXT),
            buildCell("hdr-angle", "Angle", Screen.layout.widths[4], HEADER_TEXT, "right"),
            buildCell("hdr-min", "Min W", Screen.layout.widths[5], HEADER_TEXT, "right"),
            buildCell("hdr-watts", "W Reach", Screen.layout.widths[6], HEADER_TEXT, "right"),
            buildCell("hdr-id", "Signal Id", Screen.layout.widths[7], HEADER_TEXT, "right"),
        },
    }
end

-- Build one trader row with a type-colored type column and neutral remaining cells.
local function buildSignalRow(rowIndex, row)
    local numericColor = row.hasInvalidTelemetry and MUTED_NUMERIC_TEXT or nil
    return {
        layout = "flex",
        direction = "row",
        rect = { h = ROW_HEIGHT },
        gap = Screen.layout.gap,
        children = {
            buildCell("slot-" .. rowIndex, row.slot, Screen.layout.widths[1], numericColor, "right"),
            buildCell("type-" .. rowIndex, row.typeName, Screen.layout.widths[2], row.color),
            buildCell("size-" .. rowIndex, row.size, Screen.layout.widths[3], numericColor),
            buildCell("angle-" .. rowIndex, row.angle, Screen.layout.widths[4], numericColor, "right"),
            buildCell("min-" .. rowIndex, row.minWatts, Screen.layout.widths[5], numericColor, "right"),
            buildCell("watts-" .. rowIndex, row.watts, Screen.layout.widths[6], numericColor, "right"),
            buildCell("id-" .. rowIndex, row.id, Screen.layout.widths[7], numericColor, "right"),
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
                font_size = Screen.layout.titleFontSize,
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
                font_size = Screen.layout.subtitleFontSize,
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
            gap = Screen.layout.gap,
            children = {
                {
                    id = "signals-empty-text",
                    type = "label",
                    rect = { h = ROW_HEIGHT },
                    props = { text = "No signals received" },
                    style = {
                        color = EMPTY_TEXT,
                        font_size = Screen.layout.rowFontSize,
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
    ui:clear()
    ui:element({
        id = "signals-bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = self.width, h = self.height },
        style = { bg = ROOT_BG }
    })

    ui:layout({
        layout = "flex",
        direction = "column",
        rect = {
            unit = "px",
            x = PADDING,
            y = PADDING,
            w = self.width - PADDING * 2,
            h = self.height - PADDING * 2,
        },
        gap = self.layout.rowGap,
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
    Screen:initLayout()
    Screen:rebuild()
else
    Screen:initLayout()
    SignalList:start()
    Screen.dirty = true
end

function tick(dt)
    if Screen.dirty then
        Screen:render()
    end
end
