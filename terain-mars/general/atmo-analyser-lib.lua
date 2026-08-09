--@module atmos
-- Shared atmospheric analyser display module.
-- Reads pressure, temperature, total moles, and gas ratios from an
-- atmospheric device, then renders a scaled summary and gas composition list
-- on the active Stationpedia/ui display surface.
local LT = ic.enums.LogicType
local atmos = {}

local SURFACE_NAME = "main"
local DEFAULT_WIDTH = 480
local DEFAULT_HEIGHT = 272
local PADDING = 8
local HEADER_HEIGHT = 30
local LIST_HEADER_HEIGHT = 16
local ROW_HEIGHT = 20
local ROW_GAP = 2

local COLORS = {
    bg = "#0A0E1A",
    header = "#1E293B",
    text = "#E2E8F0",
    muted = "#94A3B8",
    row = "#111827",
    row_alt = "#172033",
    empty = "#64748B",
}

atmos.gases = {
    [LT.RatioOxygen] = { label = "O2", color = "#C3D8FA", icon = "Oxygen" },
    [LT.RatioNitrogen] = { label = "N2", color = "#01CD3B", icon = "Nitrogen" },
    [LT.RatioMethane] = { label = "CH4", color = "#EF4444", icon = "Methane" },
    [LT.RatioWater] = { label = "~H2O", color = "#1D69C7", icon = "Water" },
    [LT.RatioPollutedWater] = { label = "~pH2O", color = "#815400", icon = "PollutedWater" },
    [LT.RatioPollutant] = { label = "POL", color = "#CAFD11", icon = "Pollutant" },
    [LT.RatioCarbonDioxide] = { label = "CO2", color = "#F9CB16", icon = "CarbonDioxide" },
    [LT.RatioNitrousOxide] = { label = "N2O", color = "#01CD3B", icon = "NitrousOxide" },
    [LT.RatioHydrogen] = { label = "H2", color = "#FC7A7A", icon = "Hydrogen" },
    [LT.RatioLiquidNitrogen] = { label = "~N2", color = "#01CD3B", icon = "LiquidNitrogen" },
    [LT.RatioLiquidOxygen] = { label = "~O2", color = "#C3D8FA", icon = "LiquidOxygen" },
    [LT.RatioLiquidMethane] = { label = "~CH4", color = "#EF4444", icon = "LiquidMethane" },
    [LT.RatioLiquidCarbonDioxide] = { label = "~CO2", color = "#F9CB16", icon = "LiquidCarbonDioxide" },
    [LT.RatioLiquidPollutant] = { label = "~POL", color = "#CAFD11", icon = "LiquidPollutant" },
    [LT.RatioLiquidNitrousOxide] = { label = "~N2O", color = "#01CD3B", icon = "LiquidNitrousOxide" },
    [LT.RatioLiquidHydrogen] = { label = "~H2", color = "#FC7A7A", icon = "LiquidHydrogen" },
    [LT.RatioSteam] = { label = "*H2O", color = "#9EEAF8", icon = "Steam" },
    [LT.RatioHydrazine] = { label = "N2H4", color = "#F98A01", icon = "Hydrazine" },
    [LT.RatioLiquidHydrazine] = { label = "~N2H4", color = "#F98A01", icon = "LiquidHydrazine" },
    [LT.RatioLiquidAlcohol] = { label = "~ALC", color = "#A7A2A2", icon = "LiquidAlcohol" },
    [LT.RatioHelium] = { label = "He", color = "#CE00D9", icon = "Helium" },
    [LT.RatioLiquidSodiumChloride] = { label = "~NaCl", color = "#DDFCAE", icon = "LiquidSodiumChloride" },
    [LT.RatioSilanol] = { label = "Sil", color = "#3F2F2F", icon = "Silanol" },
    [LT.RatioLiquidSilanol] = { label = "~Sil", color = "#3F2F2F", icon = "LiquidSilanol" },
    [LT.RatioHydrochloricAcid] = { label = "HCl", color = "#00AB2B", icon = "HydrochloricAcid" },
    [LT.RatioLiquidHydrochloricAcid] = { label = "~HCl", color = "#00AB2B", icon = "LiquidHydrochloricAcid" },
    [LT.RatioOzone] = { label = "O3", color = "#DD00FF", icon = "Ozone" },
    [LT.RatioLiquidOzone] = { label = "~O3", color = "#DD00FF", icon = "LiquidOzone" },
}

local PREFIXES = {
    { 1e9, "G", 1e-9 }, 
    { 1e6, "M", 1e-6 }, 
    { 1e3, "k", 1e-3 },
    { 1, "", 1 }, 
    { 1e-3, "m", 1e3 }, 
    { 1e-6, "u", 1e6 }, 
    { 0, "n", 1e9 },
}

local function fmt_sig(value, significant_digits)
    if value == nil then return "N/A" end
    if value == 0 then return "0" end
    local digits = math.floor(math.log(math.abs(value), 10)) + 1
    return string.format("%." .. math.max(significant_digits - digits, 0) .. "f", value)
end

local function fmt_prefix(value, unit)
    if value == nil then return "N/A" end
    for _, prefix in ipairs(PREFIXES) do
        if math.abs(value) >= prefix[1] then
            return fmt_sig(value * prefix[3], 3) .. " " .. prefix[2] .. unit
        end
    end
end

local function read(device, logic_type)
    local ok, value = pcall(ic.read_id, device, logic_type)
    return ok and value or nil
end

local function collect_gases(device, total_moles)
    local rows = {}
    if total_moles <= 0 then return rows end
    for logic_type, gas in pairs(atmos.gases) do
        local ratio = read(device, logic_type) or 0
        if ratio > 0 then
            rows[#rows + 1] = {
                label = gas.label,
                color = gas.color,
                icon = gas.icon,
                ratio = ratio,
                moles = ratio * total_moles,
            }
        end
    end
    table.sort(rows, function(a, b) return a.moles > b.moles end)
    return rows
end

-- Initialise the active screen and calculate dimensions reused by render.
function atmos.init()
    local ui = ss.ui.surface(SURFACE_NAME)
    ss.ui.activate(SURFACE_NAME)
    local size = ui:size() or {}
    local width = size.w or DEFAULT_WIDTH
    local height = size.h or DEFAULT_HEIGHT
    local content_width = width - PADDING * 2
    local screen_scale = math.min(width / DEFAULT_WIDTH, height / DEFAULT_HEIGHT)
    local gas_scale = 3 * screen_scale
    local summary_row_height = math.max(1, math.floor(18 * gas_scale))
    local summary_row_gap = 0
    return {
        ui = ui,
        width = width,
        height = height,
        content_width = content_width,
        label_width = math.floor(content_width * 0.45),
        name_width = math.floor(content_width * 0.30),
        ratio_width = math.floor(content_width * 0.24),
        title_name_width = math.floor(content_width * 0.36),
        title_name_font = 12,
        gas_header_height = math.max(1, math.floor(LIST_HEADER_HEIGHT * gas_scale)),
        gas_row_height = math.max(1, math.floor(ROW_HEIGHT * gas_scale)),
        gas_row_gap = math.max(1, math.floor(ROW_GAP * gas_scale)),
        gas_icon_size = math.max(1, math.floor(14 * gas_scale)),
        gas_icon_width = math.max(1, math.floor(21 * gas_scale)),
        gas_header_font = math.max(1, math.floor(10 * gas_scale)),
        gas_row_font = math.max(1, math.floor(11 * gas_scale)),
        gas_padding = math.max(0, math.floor(3 * gas_scale)),
        gas_gap = math.max(1, math.floor(4 * gas_scale)),
        summary_height = math.max(1, summary_row_height * 3 + summary_row_gap * 2),
        summary_row_height = summary_row_height,
        summary_row_gap = summary_row_gap,
        summary_label_font = math.max(1, math.floor(10 * gas_scale)),
        summary_value_font = math.max(1, math.floor(12 * gas_scale)),
    }
end

-- Render readings from an analyser, pipe, tank, or other atmospheric device.
function atmos.render(device, sizes, name)
    sizes = sizes or atmos.init()
    local ui = sizes.ui
    ss.ui.activate(SURFACE_NAME)

    local pressure = read(device, LT.Pressure)
    local total_moles = read(device, LT.TotalMoles)
    local temperature = read(device, LT.Temperature)
    local has_atmosphere = total_moles ~= nil and total_moles > 0
    local rows = collect_gases(device, has_atmosphere and total_moles or 0)
    local summary = {
        { "Pressure:", pressure and pressure > 0 and fmt_prefix(pressure, "Pa") or "N/A", "#93C5FD" },
        { "Temperature:", has_atmosphere and temperature and fmt_sig(temperature - 273.15, 3) .. " °C" or "N/A", "#FCA5A5" },
        { "Moles:", has_atmosphere and fmt_prefix(total_moles, "mol") or "N/A", "#A7F3D0" },
    }
    local header_style = { color = COLORS.muted, font_size = sizes.gas_header_font, align = "left" }
    local content_children = {
        {
            id = "atmos-gases-header",
            type = "panel",
            layout = "flex",
            direction = "row",
            rect = { h = sizes.gas_header_height },
            children = {
                { id = "atmos-header-icon", type = "panel", rect = { w = sizes.gas_icon_width } },
                { id = "atmos-header-gas", type = "label", rect = { w = sizes.name_width }, props = { text = "GAS" }, style = header_style },
                { id = "atmos-header-ratio", type = "label", rect = { w = sizes.ratio_width }, props = { text = "RATIO" }, style = header_style },
                { id = "atmos-header-moles", type = "label", flex = 1, props = { text = "MOLES" }, style = header_style },
            },
        },
    }
    if #rows == 0 then
        content_children[#content_children + 1] = {
            id = "atmos-empty", type = "label", rect = { h = sizes.gas_row_height },
            props = { text = "NO GAS DATA" }, style = { color = COLORS.empty, font_size = sizes.gas_row_font, align = "left" },
        }
    end
    for i, gas in ipairs(rows) do
        local row_style = { color = COLORS.text, font_size = sizes.gas_row_font, align = "left" }
        content_children[#content_children + 1] = {
            id = "atmos-gas-row-" .. i,
            type = "panel",
            layout = "flex",
            direction = "row",
            rect = { h = sizes.gas_row_height },
            gap = sizes.gas_gap,
            padding = { horizontal = sizes.gas_padding },
            style = { bg = i % 2 == 0 and COLORS.row_alt or COLORS.row },
            children = {
                { id = "atmos-gas-icon-" .. i, type = "icon", rect = { w = sizes.gas_icon_size, h = sizes.gas_icon_size }, props = { name = ss.ui.icons.gas[gas.icon] or gas.icon, icon_type = "gas" }, style = { tint = gas.color } },
                { id = "atmos-gas-name-" .. i, type = "label", rect = { w = sizes.name_width }, props = { text = gas.label }, style = { color = gas.color, font_size = sizes.gas_row_font, align = "left" } },
                { id = "atmos-gas-ratio-" .. i, type = "label", rect = { w = sizes.ratio_width }, props = { text = fmt_sig(gas.ratio * 100, 3) .. "%" }, style = row_style },
                { id = "atmos-gas-moles-" .. i, type = "label", flex = 1, props = { text = fmt_prefix(gas.moles, "mol") }, style = row_style },
            },
        }
    end
    local visible_rows = math.max(1, #rows)
    local content_height = sizes.gas_header_height + visible_rows * (sizes.gas_row_height + sizes.gas_row_gap)

    ui:clear()
    ui:element({
        id = "atmos-bg", type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = sizes.width, h = sizes.height },
        style = { bg = COLORS.bg },
    })
    local summary_rows = {}
    for i, entry in ipairs(summary) do
        summary_rows[#summary_rows + 1] = {
            id = "atmos-summary-row-" .. i,
            type = "panel",
            layout = "flex",
            direction = "row",
            rect = { h = sizes.summary_row_height },
            children = {
                {
                    id = "atmos-summary-label-" .. i,
                    type = "label",
                    rect = { w = sizes.label_width },
                    props = { text = entry[1] },
                    style = { color = COLORS.muted, font_size = sizes.summary_label_font, align = "right" },
                },
                {
                    id = "atmos-summary-value-" .. i,
                    type = "label",
                    flex = 1,
                    props = { text = entry[2] },
                    style = { color = entry[3], font_size = sizes.summary_value_font, align = "left" },
                },
            },
        }
    end
    ui:layout({
        layout = "flex",
        direction = "column",
        rect = { unit = "px", x = PADDING, y = PADDING, w = sizes.content_width, h = sizes.height - PADDING * 2 },
        children = {
            {
                id = "atmos-header",
                type = "panel",
                layout = "flex",
                direction = "row",
                rect = { h = HEADER_HEIGHT },
                padding = { horizontal = PADDING },
                style = { bg = COLORS.header },
                children = {
                    {
                        id = "atmos-title",
                        type = "label",
                        flex = 1,
                        props = { text = "ATMOS ANALYSER" },
                        style = { color = COLORS.text, font_size = 16, align = "left" },
                    },
                    {
                        id = "atmos-name",
                        type = "label",
                        rect = { w = sizes.title_name_width },
                        props = { text = name or "" },
                        style = { color = COLORS.muted, font_size = sizes.title_name_font, align = "right" },
                    },
                },
            },
            {
                id = "atmos-summary",
                type = "panel",
                layout = "flex",
                direction = "column",
                rect = { h = sizes.summary_height },
                gap = sizes.summary_row_gap,
                children = summary_rows,
            },
            {
                id = "atmos-list",
                type = "panel",
                layout = "flex",
                direction = "column",
                flex = 1,
                children = {
                    {
                        id = "atmos-gases",
                        type = "scrollview",
                        flex = 1,
                        props = { content_height = tostring(content_height) },
                        style = { bg = COLORS.bg, scrollbar_bg = COLORS.header, scrollbar_handle = COLORS.muted, scroll_speed = "24" },
                        children = {
                            {
                                id = "atmos-gases-content",
                                type = "panel",
                                layout = "flex",
                                direction = "column",
                                rect = { w = sizes.content_width, h = content_height },
                                gap = sizes.gas_row_gap,
                                children = content_children,
                            },
                        },
                    },
                },
            },
        },
    })
    ui:commit()
end

return atmos
