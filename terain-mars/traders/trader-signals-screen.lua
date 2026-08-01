-- Trader signals screen.
-- Signal, selling-item, and buying-item sections update independently.
local signals = require("signals")
local trader = require("trader")

local SURFACE_NAME = "main"
local PADDING = 8
local TITLE_HEIGHT = 18
local SUBTITLE_HEIGHT = 12
local HEADER_HEIGHT = 18
local ROW_HEIGHT = 18
local ROW_GAP = 3
local CELL_GAP = 6
local MAX_SIGNAL_ROWS = 5
local ITEM_HEADER_HEIGHT = 18
local ITEM_ROW_HEIGHT = 22
local ITEM_ROW_GAP = 2
local ITEM_PANEL_GAP = 6
local ITEM_PANEL_PADDING = 4
local ITEM_PANEL_INNER_GAP = 3
local SUBITEM_INDENT = 12

local TITLE_COLOR = "#F8FAFC"
local SUBTITLE_COLOR = "#94A3B8"
local HEADER_BG = "#1E293B"
local HEADER_TEXT = "#E2E8F0"
local ITEM_PANEL_BG = "#0F172A"
local ITEM_ROW_BG = "#111827"
local ITEM_ROW_ALT_BG = "#172033"
local EMPTY_TEXT = "#64748B"
local ROW_TEXT = "#F8FAFC"
local SELL_QUANTITY_COLOR = "#F59E0B"
local BUY_QUANTITY_COLOR = "#22D3EE"
local SELL_HEADER_BG = "#3A2A10"
local BUY_HEADER_BG = "#083344"
local MUTED_NUMERIC_TEXT = "#64748B"
local ROOT_BG = "#020617"
local BASE_WIDTH = 480

local ItemType = trader.ItemType
local GasBitFlag = trader.GasBitFlag
local GAS_DETAILS = trader.GasDetails

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
local TraderSubscription
local ui = ss.ui.surface(SURFACE_NAME)

ss.ui.activate(SURFACE_NAME)

local FAKE_ITEMS = trader.FakeItems

local Screen = {
    rows = {},
    width = 480,
    height = 272,
    layout = nil,
    handles = nil,
    signalsDirty = true,
    itemSlot = nil,
    itemTraderId = nil,
    sell = { slot = 0, items = {}, scrollId = nil, elementIds = {}, generation = 0, dirty = true },
    buy = { slot = 0, items = {}, scrollId = nil, elementIds = {}, generation = 0, dirty = true },
}

local function buildLayout(width)
    local contentWidth = math.max(1, width - PADDING * 2)
    local scale = math.max(1, contentWidth / BASE_WIDTH)
    local gap = math.floor(CELL_GAP * scale + 0.5)
    local rowGap = math.max(3, math.floor(ROW_GAP * scale + 0.5))
    local widths = { 28, 84, 54, 48, 52, 58, 90 }
    local widthSum = 0
    for i = 1, #widths do
        widthSum = widthSum + widths[i]
    end
    local targetWidth = contentWidth - gap * (#widths - 1)
    local factor = targetWidth > 0 and targetWidth / widthSum or 1
    for i = 1, #widths do
        widths[i] = math.max(24, math.floor(widths[i] * factor + 0.5))
    end
    return {
        contentWidth = contentWidth,
        gap = gap,
        rowGap = rowGap,
        titleFontSize = math.floor(16 * scale + 0.5),
        subtitleFontSize = math.floor(10 * scale + 0.5),
        rowFontSize = math.floor(10 * scale + 0.5),
        itemPanelWidth = math.floor((contentWidth - ITEM_PANEL_GAP) / 2),
        widths = widths,
    }
end

function Screen:initLayout()
    local size = ui:size()
    if size then
        self.width = size.w or self.width
        self.height = size.h or self.height
    end
    self.layout = buildLayout(self.width)
end

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

local function buildHeaderRow()
    return {
        id = "signals-header-bg",
        type = "panel",
        layout = "flex",
        direction = "row",
        rect = { h = HEADER_HEIGHT },
        gap = Screen.layout.gap,
        style = { bg = HEADER_BG },
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

local function buildSignalRow(rowIndex)
    return {
        layout = "flex",
        direction = "row",
        rect = { h = ROW_HEIGHT },
        gap = Screen.layout.gap,
        children = {
            buildCell("slot-" .. rowIndex, "", Screen.layout.widths[1], nil, "right"),
            buildCell("type-" .. rowIndex, "", Screen.layout.widths[2]),
            buildCell("size-" .. rowIndex, "", Screen.layout.widths[3]),
            buildCell("angle-" .. rowIndex, "", Screen.layout.widths[4], nil, "right"),
            buildCell("min-" .. rowIndex, "", Screen.layout.widths[5], nil, "right"),
            buildCell("watts-" .. rowIndex, "", Screen.layout.widths[6], nil, "right"),
            buildCell("id-" .. rowIndex, "", Screen.layout.widths[7], nil, "right"),
        },
    }
end

local function buildItemPanel(side)
    local headerBg = side == "sell" and SELL_HEADER_BG or BUY_HEADER_BG
    local headerText = side == "sell" and SELL_QUANTITY_COLOR or BUY_QUANTITY_COLOR
    return {
        id = side .. "-panel",
        type = "panel",
        layout = "flex",
        direction = "column",
        flex = 1,
        gap = ITEM_PANEL_INNER_GAP,
        padding = ITEM_PANEL_PADDING,
        style = { bg = ITEM_PANEL_BG },
        children = {
            {
                id = side .. "-header-bg",
                type = "panel",
                layout = "flex",
                direction = "row",
                rect = { h = ITEM_HEADER_HEIGHT },
                padding = { horizontal = 4 },
                style = { bg = headerBg },
                children = {
                    {
                        id = side .. "-header",
                        type = "label",
                        flex = 1,
                        props = { text = "" },
                        style = {
                            color = headerText,
                            font_size = Screen.layout.rowFontSize,
                            align = "left",
                        },
                    },
                },
            },
            {
                id = side .. "-body",
                type = "panel",
                flex = 1,
                style = { bg = ITEM_PANEL_BG },
            },
        },
    }
end

function Screen:buildShell()
    ui:element({
        id = "signals-bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = self.width, h = self.height },
        style = { bg = ROOT_BG },
    })

    local signalRows = {}
    for i = 1, MAX_SIGNAL_ROWS do
        signalRows[#signalRows + 1] = buildSignalRow(i)
    end

    self.handles = ui:layout({
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
        children = {
            {
                id = "signals-title",
                type = "label",
                rect = { h = TITLE_HEIGHT },
                props = { text = "Trader Signals" },
                style = { color = TITLE_COLOR, font_size = self.layout.titleFontSize, align = "left" },
            },
            {
                id = "signals-subtitle",
                type = "label",
                rect = { h = SUBTITLE_HEIGHT },
                props = { text = "Scanner full-list sync with trader-type color coding" },
                style = { color = SUBTITLE_COLOR, font_size = self.layout.subtitleFontSize, align = "left" },
            },
            buildHeaderRow(),
            {
                layout = "flex",
                direction = "column",
                rect = { h = MAX_SIGNAL_ROWS * ROW_HEIGHT + (MAX_SIGNAL_ROWS - 1) * self.layout.rowGap },
                gap = self.layout.rowGap,
                children = signalRows,
            },
            {
                layout = "flex",
                direction = "row",
                flex = 1,
                gap = ITEM_PANEL_GAP,
                children = {
                    buildItemPanel("sell"),
                    buildItemPanel("buy"),
                },
            },
        },
    })

    self.signalsDirty = true
    self.sell.scrollId = nil
    self.buy.scrollId = nil
    self.sell.elementIds = {}
    self.buy.elementIds = {}
    self.sell.dirty = true
    self.buy.dirty = true
end

function Screen:updateSignals()
    for i = 1, MAX_SIGNAL_ROWS do
        local row = self.rows[i]
        local values = row and {
            row.slot, row.typeName, row.size, row.angle, row.minWatts, row.watts, row.id,
        } or { "", "", "", "", "", "", "" }
        if not row and #self.rows == 0 and i == 1 then
            values[2] = "No signals received"
        end

        local numericColor = row and row.hasInvalidTelemetry and MUTED_NUMERIC_TEXT or ROW_TEXT
        local typeColor = row and row.color or EMPTY_TEXT
        local ids = { "slot-", "type-", "size-", "angle-", "min-", "watts-", "id-" }
        for column = 1, #ids do
            local handle = self.handles[ids[column] .. i]
            handle:set_props({ text = values[column] })
            handle:set_style({ color = column == 2 and typeColor or numericColor })
        end
    end
    self.signalsDirty = false
end

local function resolveGas(bitFlag)
    local gas = GAS_DETAILS[bitFlag]
    if gas then
        return gas.name, ss.ui.icons.gas[gas.icon]
    end
    return "GasBitFlag " .. tostring(bitFlag), ss.ui.icons.gas.Pollutant
end

local function resolveItem(itemType, itemHash)
    if itemType == ItemType.Prefab then
        local name = prefab_name(itemHash)
        return name, tostring(itemHash), "prefab"
    end
    if itemType == ItemType.GasBitFlag then
        local name, icon = resolveGas(itemHash)
        return name, icon, nil
    end
    return "Unknown", tostring(itemHash), nil
end

local function flattenItems(source)
    local items = {}
    for _, item in ipairs(source or {}) do
        local itemHash = item.hash
        local name, icon, iconType = resolveItem(item.type, itemHash)
        items[#items + 1] = {
            type = item.type,
            hash = itemHash,
            name = name,
            icon = icon,
            iconType = iconType,
            quantity = item.quantity,
            isSubitem = item.isSubitem == true,
        }
    end
    return items
end

function Screen:setSellingItems(slot, source)
    self.sell.slot = slot
    self.sell.items = flattenItems(source)
    self.sell.dirty = true
end

function Screen:setBuyingItems(slot, source)
    self.buy.slot = slot
    self.buy.items = flattenItems(source)
    self.buy.dirty = true
end

function Screen:getItemScrollRect(side)
    local signalRowsHeight = MAX_SIGNAL_ROWS * ROW_HEIGHT + (MAX_SIGNAL_ROWS - 1) * self.layout.rowGap
    local itemsY = PADDING
        + TITLE_HEIGHT + self.layout.rowGap
        + SUBTITLE_HEIGHT + self.layout.rowGap
        + HEADER_HEIGHT + self.layout.rowGap
        + signalRowsHeight + self.layout.rowGap
    local panelX = PADDING
    if side == "buy" then
        panelX = panelX + self.layout.itemPanelWidth + ITEM_PANEL_GAP
    end
    local panelHeight = self.height - PADDING - itemsY
    return {
        x = panelX + ITEM_PANEL_PADDING,
        y = itemsY + ITEM_PANEL_PADDING + ITEM_HEADER_HEIGHT + ITEM_PANEL_INNER_GAP,
        w = self.layout.itemPanelWidth - ITEM_PANEL_PADDING * 2,
        h = math.max(1, panelHeight - ITEM_PANEL_PADDING * 2 - ITEM_HEADER_HEIGHT - ITEM_PANEL_INNER_GAP),
    }
end

function Screen:updateItemPanel(side, panel)
    if panel.scrollId then
        for i = #panel.elementIds, 1, -1 do
            ui:remove(panel.elementIds[i])
        end
        panel.scrollId = nil
        panel.elementIds = {}
        return
    end

    local header = side == "sell" and "Selling Items of slot " or "Buying Items of slot "
    local headerHandle = self.handles[side .. "-header"]
    headerHandle:set_props({ text = header .. tostring(panel.slot) })

    panel.generation = panel.generation + 1
    local scrollLocalId = side .. "-items-scroll-" .. panel.generation
    panel.scrollId = side .. "-body/" .. scrollLocalId
    panel.elementIds = { panel.scrollId }
    local scrollRect = self:getItemScrollRect(side)
    local listWidth = scrollRect.w
    local quantityColor = side == "sell" and SELL_QUANTITY_COLOR or BUY_QUANTITY_COLOR
    local count = math.max(1, #panel.items)
    local body = self.handles[side .. "-body"]
    local scroll = body:element({
        id = scrollLocalId,
        type = "scrollview",
        rect = {
            unit = "px",
            x = 0,
            y = 0,
            w = scrollRect.w,
            h = scrollRect.h,
        },
        props = {
            content_height = tostring(count * (ITEM_ROW_HEIGHT + ITEM_ROW_GAP)),
            z_index = 1,
        },
        style = {
            bg = ITEM_PANEL_BG,
            scrollbar_bg = HEADER_BG,
            scrollbar_handle = "#475569",
            scroll_speed = "24",
        },
    })

    if #panel.items == 0 then
        local rowId = scrollLocalId .. "-empty"
        panel.elementIds[#panel.elementIds + 1] = panel.scrollId .. "/" .. rowId
        panel.elementIds[#panel.elementIds + 1] = panel.scrollId .. "/" .. rowId .. "-text"
        scroll:element({
            id = rowId,
            type = "panel",
            rect = { unit = "px", x = 0, y = 0, w = listWidth, h = ITEM_ROW_HEIGHT },
            style = { bg = ITEM_ROW_BG },
        })
        scroll:element({
            id = rowId .. "-text",
            type = "label",
            rect = { unit = "px", x = 6, y = 0, w = listWidth - 12, h = ITEM_ROW_HEIGHT },
            props = { text = "No items" },
            style = { color = EMPTY_TEXT, font_size = self.layout.rowFontSize, align = "left" },
        })
        panel.dirty = false
        return
    end

    for i, item in ipairs(panel.items) do
        local rowId = scrollLocalId .. "-row-" .. i
        panel.elementIds[#panel.elementIds + 1] = panel.scrollId .. "/" .. rowId
        panel.elementIds[#panel.elementIds + 1] = panel.scrollId .. "/" .. rowId .. "-icon"
        panel.elementIds[#panel.elementIds + 1] = panel.scrollId .. "/" .. rowId .. "-name"
        panel.elementIds[#panel.elementIds + 1] = panel.scrollId .. "/" .. rowId .. "-quantity"
        local y = (i - 1) * (ITEM_ROW_HEIGHT + ITEM_ROW_GAP)
        local indent = item.isSubitem and SUBITEM_INDENT or 0
        scroll:element({
            id = rowId,
            type = "panel",
            rect = { unit = "px", x = 0, y = y, w = listWidth, h = ITEM_ROW_HEIGHT },
            style = { bg = i % 2 == 0 and ITEM_ROW_ALT_BG or ITEM_ROW_BG },
        })
        local iconProps = { name = item.icon }
        if item.iconType then
            iconProps.icon_type = item.iconType
        end
        scroll:element({
            id = rowId .. "-icon",
            type = "icon",
            rect = { unit = "px", x = 3 + indent, y = y + 2, w = 18, h = 18 },
            props = iconProps,
            style = { tint = "#FFFFFF" },
        })
        scroll:element({
            id = rowId .. "-name",
            type = "label",
            rect = { unit = "px", x = 25 + indent, y = y, w = math.max(30, listWidth - 101 - indent), h = ITEM_ROW_HEIGHT },
            props = { text = item.name },
            style = { color = ROW_TEXT, font_size = self.layout.rowFontSize, align = "left" },
        })
        scroll:element({
            id = rowId .. "-quantity",
            type = "label",
            rect = { unit = "px", x = listWidth - 72, y = y, w = 62, h = ITEM_ROW_HEIGHT },
            props = { text = tostring(item.quantity) },
            style = { color = quantityColor, font_size = self.layout.rowFontSize, align = "right" },
        })
    end
    panel.dirty = false
end

function Screen:rebuildSignals()
    self.rows = {}
    local entries = SignalList:getSortedEntries()
    for i = 1, math.min(#entries, MAX_SIGNAL_ROWS) do
        local entry = entries[i]
        self.rows[#self.rows + 1] = formatSignalRow(entry.slot, entry.value)
    end
    self.signalsDirty = true
end

function Screen:clearTraderItemsIfOutdated()
    if self.itemSlot == nil then return false end
    local signalData = SignalList:getBySlot(self.itemSlot)
    if signalData ~= nil and signalData.signal.Id == self.itemTraderId then return false end

    self:setSellingItems(self.itemSlot, {})
    self:setBuyingItems(self.itemSlot, {})
    self.itemSlot = nil
    self.itemTraderId = nil
    return true
end

function Screen:render()
    local changed = false
    if self.signalsDirty then
        self:updateSignals()
        changed = true
    end
    if self.sell.dirty then
        self:updateItemPanel("sell", self.sell)
        changed = true
    end
    if self.buy.dirty then
        self:updateItemPanel("buy", self.buy)
        changed = true
    end
    if changed then
        ui:commit()
    end
end

SignalList = signals.SignalList.new(signals.SignalListRole.Consumer, {
    fullTopic = signals.TOPIC_SIGNALS,
    onFullSync = function()
        Screen:rebuildSignals()
        Screen:clearTraderItemsIfOutdated()
    end,
})

local function extractTraderItems(payload)
    if type(payload) == "string" then
        return trader.deserializeItems(payload)
    end
    if type(payload) ~= "table" then return nil end
    if type(payload.j) == "string" then
        return trader.deserializeItems(payload.j)
    end
    return nil
end

TraderSubscription = ic.net.subscribe(trader.TOPIC, function(_, payload)
    local items = extractTraderItems(payload)
    if items == nil then return end
    Screen.itemSlot = items.slot
    Screen.itemTraderId = items.traderId
    Screen:setSellingItems(items.slot, items.sell)
    Screen:setBuyingItems(items.slot, items.buy)
end)

ui:clear()
Screen:initLayout()
Screen:rebuildSignals()
Screen:buildShell()
SignalList:start()
ui:commit()

function tick(dt)
    Screen:render()
end
