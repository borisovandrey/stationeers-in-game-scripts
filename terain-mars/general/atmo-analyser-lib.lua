--@module atmos
-- Shared atmospheric analyser display module.
-- Reads pressure, temperature, total moles, and gas ratios from an
-- atmospheric device, then updates only the changed UI values each tick.
local LT = ic.enums.LogicType
local atmos = {}

local SURFACE_NAME = "main"
local DEFAULT_WIDTH = 862
local DEFAULT_HEIGHT = 584
local DEFAULT_FONT_SIZE = 30
local MIN_FONT_SIZE = 8
local GAS_LABEL_PLACEHOLDER = "~XXXXXX"
local HORISONTAL_GAP = 6
local VERTICAL_GAP = 4
local HORISONTAL_MAX_GAP = 12
local VERTICAL_MAX_GAP = 8
local ROW_PADDING = 10
local HORISONTAL_PADDING = 10
local EPSILON = 1e-6

local COLORS = {
    DARK_TEXT = "#202020",
    PANEL_BACKGROUND = "#1E293B",
    TITLE_TEXT = "#22C55E",
    DIMENSIONS_TEXT = "#2269C5",
    SUMMARY_BACKGROUND = "#959595",
    LIST_TEXT = "#E2E8F0",
    PRESSURE_TEXT = "#757D00",
    TEMPERATURE_TEXT = "#7D0F00",
    MOLES_TEXT = "#001D7D",
    SCROLL_BACKGROUND = "#64748B",
    SCROLLBAR_HANDLE = "#475569",
    ROW_BACKGROUND_EVEN = "#111827",
    ROW_BACKGROUND_ODD = "#172033",
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

local function fmt_value(value, unit, prec)
    for _, prefix in ipairs(PREFIXES) do
        if math.abs(value) >= prefix[1] then
            return string.format("%." .. prec .. "f", value * prefix[3]) .. " " .. prefix[2] .. unit
        end
    end
    return "N/A"
end

atmos.gases = {
    { logic_type = LT.RatioOxygen, label = "O2", color = "#C3D8FA", icon = "Oxygen" },
    { logic_type = LT.RatioNitrogen, label = "N2", color = "#01CD3B", icon = "Nitrogen" },
    { logic_type = LT.RatioMethane, label = "CH4", color = "#EF4444", icon = "Methane" },
    { logic_type = LT.RatioWater, label = "~H2O", color = "#1D69C7", icon = "Water" },
    { logic_type = LT.RatioPollutedWater, label = "~pH2O", color = "#815400", icon = "PollutedWater" },
    { logic_type = LT.RatioPollutant, label = "POL", color = "#CAFD11", icon = "Pollutant" },
    { logic_type = LT.RatioCarbonDioxide, label = "CO2", color = "#F9CB16", icon = "CarbonDioxide" },
    { logic_type = LT.RatioNitrousOxide, label = "N2O", color = "#01CD3B", icon = "NitrousOxide" },
    { logic_type = LT.RatioHydrogen, label = "H2", color = "#FC7A7A", icon = "Hydrogen" },
    { logic_type = LT.RatioLiquidNitrogen, label = "~N2", color = "#01CD3B", icon = "LiquidNitrogen" },
    { logic_type = LT.RatioLiquidOxygen, label = "~O2", color = "#C3D8FA", icon = "LiquidOxygen" },
    { logic_type = LT.RatioLiquidMethane, label = "~CH4", color = "#EF4444", icon = "LiquidMethane" },
    { logic_type = LT.RatioLiquidCarbonDioxide, label = "~CO2", color = "#F9CB16", icon = "LiquidCarbonDioxide" },
    { logic_type = LT.RatioLiquidPollutant, label = "~POL", color = "#CAFD11", icon = "LiquidPollutant" },
    { logic_type = LT.RatioLiquidNitrousOxide, label = "~N2O", color = "#01CD3B", icon = "LiquidNitrousOxide" },
    { logic_type = LT.RatioLiquidHydrogen, label = "~H2", color = "#FC7A7A", icon = "LiquidHydrogen" },
    { logic_type = LT.RatioSteam, label = "*H2O", color = "#9EEAF8", icon = "Steam" },
    { logic_type = LT.RatioHydrazine, label = "N2H4", color = "#F98A01", icon = "Hydrazine" },
    { logic_type = LT.RatioLiquidHydrazine, label = "~N2H4", color = "#F98A01", icon = "LiquidHydrazine" },
    { logic_type = LT.RatioLiquidAlcohol, label = "~ALC", color = "#A7A2A2", icon = "LiquidAlcohol" },
    { logic_type = LT.RatioHelium, label = "He", color = "#CE00D9", icon = "Helium" },
    { logic_type = LT.RatioLiquidSodiumChloride, label = "~NaCl", color = "#DDFCAE", icon = "LiquidSodiumChloride" },
    { logic_type = LT.RatioSilanol, label = "Sil", color = "#3F2F2F", icon = "Silanol" },
    { logic_type = LT.RatioLiquidSilanol, label = "~Sil", color = "#3F2F2F", icon = "LiquidSilanol" },
    { logic_type = LT.RatioHydrochloricAcid, label = "HCl", color = "#00AB2B", icon = "HydrochloricAcid" },
    { logic_type = LT.RatioLiquidHydrochloricAcid, label = "~HCl", color = "#00AB2B", icon = "LiquidHydrochloricAcid" },
    { logic_type = LT.RatioOzone, label = "O3", color = "#DD00FF", icon = "Ozone" },
    { logic_type = LT.RatioLiquidOzone, label = "~O3", color = "#DD00FF", icon = "LiquidOzone" },
}

local function calculate_row_min_size(ui, font_size)
    local row_string_size = ui:measure_text(" " .. GAS_LABEL_PLACEHOLDER .. " 000.00 % 0000.0000 kMol XXX", 0, font_size)
    row_string_size.w = row_string_size.w + row_string_size.h
    return row_string_size
end

local function create_ui_state(ui, options)
    options = options or {}
    local screen_size = ui:size()
    local font_size = DEFAULT_FONT_SIZE
    local row_string_size = calculate_row_min_size(ui, font_size)
    local ratio = 1
    if row_string_size.w > screen_size.w then
        ratio = screen_size.w / row_string_size.w
        font_size = math.max( math.floor( font_size * ratio ), MIN_FONT_SIZE )
        row_string_size = calculate_row_min_size(ui, font_size)
    end

    local vertical_gap = math.min(math.max(math.floor(VERTICAL_GAP * ratio), 1), VERTICAL_MAX_GAP)
    local expected_height = 8 * ( row_string_size.h + vertical_gap)
    if expected_height > screen_size.h then
        local height_ratio = screen_size.h / expected_height
        font_size = math.max( math.floor( font_size * height_ratio ), MIN_FONT_SIZE )
        ratio = ratio * height_ratio
        row_string_size = calculate_row_min_size(ui, font_size)
        vertical_gap = math.min(math.max(math.floor(VERTICAL_GAP * ratio), 1), VERTICAL_MAX_GAP)
    end

    local row_heitght = row_string_size.h
    local horizontal_gap = math.min(math.max(math.floor(HORISONTAL_GAP * ratio), 1), HORISONTAL_MAX_GAP)
    local horisontal_padding = math.min(math.max(math.floor(HORISONTAL_PADDING * ratio), 1), HORISONTAL_PADDING)
    local gas_label_width = ui:measure_text(GAS_LABEL_PLACEHOLDER, 0, font_size).w + horizontal_gap
    local gas_icon_width = row_heitght
    local gas_ratio_width = math.floor((screen_size.w - gas_icon_width - gas_label_width) / 2) - 2 * ROW_PADDING

    return {
        ui = ui,
        name = options.name or "",
        page = {},
        font_size = font_size,
        screen_size = screen_size,
        row_height = row_heitght,
        vertical_gap = vertical_gap,
        horizontal_gap = horizontal_gap,
        horizontal_padding = horisontal_padding,
        gas_label_width = gas_label_width,
        gas_icon_width = row_heitght, 
        gas_ratio_width = gas_ratio_width,
        gas_mole_width = gas_ratio_width,
        temperature = nil,
        pressure = nil,
        moles = nil,
        gas_list_generation = 0,
        gas_list_cache = nil,
        gas_list_mask = nil,
        gas_list_to_delete_ids = {}
    }

end

local function generate_summary_rows(state)
    local function row(id, label, color, state)
        return {
                layout = "flex", direction = "row",
                rect = { h = state.row_height },
                children = {
                    { 
                        id = id .. "_hdr", type = "label", flex = 2,
                        props = { text = label},
                        style = { font_size = state.font_size, color = COLORS.DARK_TEXT, align = "right"}
                    },
                    {
                        id = id .. "_val", type = "label", flex = 3,
                        props = { text = "N/A"},
                        style = { font_size = state.font_size, color = color, align = "left"}
                    }
            }
        }
    end
    
    return {
        row("prss", "Pressure:", COLORS.PRESSURE_TEXT, state),
        row("temp", "Temperature:", COLORS.TEMPERATURE_TEXT, state),
        row("mole", "Moles:", COLORS.MOLES_TEXT, state),
    }
end

local function create_ui_page(state)
    state.ui:clear()
    local page = state.ui:layout({
        layout = "flex", flex = 1,
        rect = {unit = "px", x = state.horizontal_padding, y = 0, w = state.screen_size.w - 2 * state.horizontal_padding, h = state.screen_size.h},
        direction = "column",
        gap = state.vertical_gap,
        children = {
            --Title bar
            {
                layout = "flex", id = "hdr", type = "panel",
                rect = { h = state.row_height + state.vertical_gap }, direction = "row", gap = 0,
                style = {bg = COLORS.PANEL_BACKGROUND},
                children = {
                    { 
                        id = "hdr_ttl_1", type = "label", flex = 2,
                        props = { text = "Atmo Analiser"},
                        style = { font_size = state.font_size, color = COLORS.TITLE_TEXT}
                    },
                    { 
                        id = "hdr_ttl_2", type = "label", flex = 1,
                        props = { text = state.name },
                        style = { font_size = state.font_size, color = COLORS.DIMENSIONS_TEXT, align = "right"}
                    },
                }
            },
            -- Summary
            {
                layout = "flex", id = "sum", type = "panel",
                rect = { h = 3 * (state.row_height + state.vertical_gap) }, direction = "column", gap = state.vertical_gap,
                style = {bg = COLORS.SUMMARY_BACKGROUND},
                children = generate_summary_rows(state)
            },
            -- List header
            {
                layout = "flex", id = "lst_hdr", type = "panel",
                rect = { h = state.row_height + state.vertical_gap }, direction = "row", gap = state.horizontal_gap,
                style = {bg = COLORS.PANEL_BACKGROUND},
                children = {
                    { 
                        id = "lst_ttl_1", type = "label",
                        rect = { w = state.gas_icon_width }, 
                        props = { text = "#"},
                        style = { font_size = state.font_size, color = COLORS.LIST_TEXT}
                    },
                    { 
                        id = "lst_ttl_2", type = "label",
                        rect = { w = state.gas_label_width },
                        props = { text = "Item" },
                        style = { font_size = state.font_size, color = COLORS.LIST_TEXT, align = "left"}
                    },
                    { 
                        id = "lst_ttl_3", type = "label",
                        rect = { w = state.gas_ratio_width },
                        props = { text = "Ratio" },
                        style = { font_size = state.font_size, color = COLORS.LIST_TEXT, align = "left"}
                    },
                    { 
                        id = "lst_ttl_4", type = "label", flex = 1,
                        rect = { w = state.gas_mole_width },
                        props = { text = "Moles" },
                        style = { font_size = state.font_size, color = COLORS.LIST_TEXT, align = "left"}
                    },
                }
            }, 
            -- Scroll view
            {
                layout = "flex", id = "scroll_pan", flex = 1, direction = "column", gap = state.vertical_gap,
                children = {}
            }
        }
    })
    state.page = page
end

-- Initialise the active screen and calculate dimensions reused by render.
function atmos.init(options)
    local ui = ss.ui.surface(SURFACE_NAME)
    ss.ui.activate(SURFACE_NAME)
    local state = create_ui_state(ui, options)
    create_ui_page(state)
    ui:commit()
    return state
end


local function generate_gas_scroll_list(settings)
    local scroll_pan = settings.page.scroll_pan
    for index = #settings.gas_list_to_delete_ids, 1, -1 do
        settings.ui:remove(settings.gas_list_to_delete_ids[index])
    end
    settings.gas_list_to_delete_ids = {}

    settings.gas_list_generation = settings.gas_list_generation + 1
    local scroll_id = "scroll_list" .. settings.gas_list_generation
    local scroll_path = "scroll_pan/" .. scroll_id
    local row_height = settings.row_height + settings.vertical_gap
    local content_height = #settings.gas_list_cache * row_height
    local scroll = scroll_pan:element({
            id = scroll_id, type = "scrollview", flex = 1,
            props = { content_height = tostring(content_height)  },
            style = {
                        bg = COLORS.SCROLL_BACKGROUND,
                        scrollbar_bg = COLORS.PANEL_BACKGROUND,
                        scrollbar_handle = COLORS.SCROLLBAR_HANDLE,
                        scroll_speed = "30",
                    },
        })
    settings.gas_list_to_delete_ids[#settings.gas_list_to_delete_ids + 1] = scroll_path

    for index, entry in ipairs(settings.gas_list_cache) do
        local gas = atmos.gases[entry.index]
        local id = "item_" .. gas.logic_type .. "_" .. settings.gas_list_generation
        local pos = index - 1
        local y = pos * row_height
        scroll:element({
                id = id .. "_p", type = "panel",
                rect = { unit = "px", x = 0, y = y, h = row_height, w = settings.screen_size.w}, 
                gap = settings.horizontal_gap,
                style = {bg = (( pos % 2) == 0) and COLORS.ROW_BACKGROUND_EVEN or COLORS.ROW_BACKGROUND_ODD },
        })
        settings.gas_list_to_delete_ids[#settings.gas_list_to_delete_ids + 1] = scroll_path .. "/" .. id .. "_p"
        local x = 0
        scroll:element({
                            id = id .. "_ico", type = "icon",
                            rect = { unit = "px", x = x, y = y, h = row_height, w = settings.gas_icon_width }, 
                            props = { name = ss.ui.icons.gas[gas.icon] or gas.icon, icon_type = "gas" },
                            style = { tint = gas.color }, 
        })
        settings.gas_list_to_delete_ids[#settings.gas_list_to_delete_ids + 1] = scroll_path .. "/" .. id .. "_ico"
        x = x + settings.gas_icon_width
        scroll:element({
                             id = id .. "_lbl", type = "label",
                             props = { text = gas.label },
                             rect = { unit = "px", x = x, y = y, h = row_height, w = settings.gas_label_width}, 
                             style = { font_size = settings.font_size, color = gas.color, align = "right"}
        })
        settings.gas_list_to_delete_ids[#settings.gas_list_to_delete_ids + 1] = scroll_path .. "/" .. id .. "_lbl"
        x = x + settings.gas_label_width
        entry.ratio_handle = scroll:element({
                             id = id .. "_rat", type = "label",
                             props = { text = string.format("%.2f%%", entry.ratio * 100) },
                             rect = { unit = "px", x = x, y = y, h = row_height, w = settings.gas_ratio_width}, 
                             style = { font_size = settings.font_size, color = COLORS.LIST_TEXT, align = "right"}
        })
        settings.gas_list_to_delete_ids[#settings.gas_list_to_delete_ids + 1] = scroll_path .. "/" .. id .. "_rat"
        x = x + settings.gas_ratio_width
        entry.moles_handle = scroll:element({
                             id = id .. "_mol", type = "label",
                             props = { text = fmt_value(entry.moles, "Mol", 3) },
                             rect = { unit = "px", x = x, y = y, h = row_height, w = settings.gas_mole_width}, 
                             style = { font_size = settings.font_size, color = COLORS.LIST_TEXT, align = "right"}
        })
        settings.gas_list_to_delete_ids[#settings.gas_list_to_delete_ids + 1] = scroll_path .. "/" .. id .. "_mol"
    end
end

local function calculate_gases(device, settings)
    
    if settings.moles <= 0 then return {}, 0 end
    local gases = {}
    local rest_ratio = 1
    local total_moles = settings.moles
    local gas_list_mask = 0
    for index, entry in ipairs(atmos.gases) do
        local ratio = ic.read_id(device, entry.logic_type)
        if ratio > EPSILON then
            gas_list_mask = gas_list_mask + 2 ^ (index - 1)
            gases[#gases + 1] = {
                logic_type = entry.logic_type,
                index = index,
                ratio = ratio,
                moles = ratio * total_moles,
                ratio_handle = nil,
                moles_handle = nil,
            }
            rest_ratio = rest_ratio - ratio
            if math.abs(rest_ratio) < EPSILON then
                break
            end
        end
    end
    return gases, gas_list_mask
end

local function update_gas_scroll_list(settings, gas_cache)
    local changed = false
    for index, entry in ipairs(gas_cache) do
        local cached_entry = settings.gas_list_cache[index]
        if cached_entry.logic_type == entry.logic_type then
            if cached_entry.ratio ~= entry.ratio then
                cached_entry.ratio = entry.ratio
                cached_entry.ratio_handle:set_props({ text = string.format("%.2f%%", entry.ratio * 100)})
                changed = true
            end
            if cached_entry.moles ~= entry.moles then
                cached_entry.moles = entry.moles
                cached_entry.moles_handle:set_props({ text = fmt_value(entry.moles, "Mol", 3)})
                changed = true
            end
        end
    end
    return changed
end

function atmos.render(device, settings)
    local temperature = ic.read_id(device, LT.Temperature)
    local pressure = ic.read_id(device, LT.Pressure)
    local moles = ic.read_id(device, LT.TotalMoles)
    local changed = false
    if settings.temperature == nil or settings.temperature ~= temperature then
        settings.temperature = temperature
        changed = true
        settings.page.temp_val:set_props({text = fmt_value( util.temp(temperature or 0, "K", "C") , "°C", 5)})
    end
    if settings.pressure == nil or settings.pressure ~= pressure then
        settings.pressure = pressure
        changed = true
        settings.page.prss_val:set_props({text = fmt_value(pressure, "Pa", 3)})
    end 
    if settings.moles == nil or settings.moles ~= moles then
        settings.moles = moles
        changed = true
        settings.page.mole_val:set_props({text = fmt_value(moles, "Mol", 3)})
    end

    local gas_cache, mask = calculate_gases(device, settings)
    if settings.gas_list_mask == nil or settings.gas_list_mask ~= mask then
       settings.gas_list_mask = mask
       settings.gas_list_cache = gas_cache
       generate_gas_scroll_list(settings)
       changed = true
    else
       local list_updated = update_gas_scroll_list(settings, gas_cache)
       changed = changed or list_updated
    end

    if changed then settings.ui:commit() end
end

return atmos