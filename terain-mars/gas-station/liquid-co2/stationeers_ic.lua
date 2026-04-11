---@meta
-- StationeersLua API stubs for LuaLS / VS Code
--
-- Generated from the public StationeersLua API reference pages:
-- - Device I/O
-- - Batch Operations
-- - Slots & Reagents
-- - Memory & Stack
-- - Bitwise Operations
-- - String & Hash
-- - Net Messaging / PubSub / RPC / Pack
-- - Temperature / Time / JSON / Events
-- - Quick Reference
-- - Enums & Constants
--
-- Notes:
-- - This file is intended for editor IntelliSense, not runtime execution.
-- - Some enums/constants in the mod are broader than the docs pages explicitly enumerate.
--   Where the docs did not list every member, this stub exposes the documented members and
--   leaves the table open for additional values provided by the game/mod.
-- - Several APIs return nil when a device is missing/disconnected according to the docs.

---@alias logic_value number|integer|boolean|string|table|nil
---@alias stationeers_handler_ref fun(...: any): any|string
---@alias device_index integer
---@alias network_index integer
---@alias reference_id integer
---@alias prefab_hash integer
---@alias name_hash integer
---@alias reagent_hash integer
---@alias slot_index integer
---@alias memory_address integer
---@alias event_name string
---@alias topic_pattern string
---@alias rpc_method string
---@alias net_channel string|integer
---@alias net_target string|integer

-- ============================================================================
-- ENUMS
-- ============================================================================

---@class LogicTypeEnum
---@field On integer                     Device power state (0/1).
---@field Open integer                   Door/vent open state.
---@field Temperature integer            Temperature in Kelvin.
---@field Pressure integer               Pressure in kPa.
---@field Setting integer                Generic setting value.
---@field Mode integer                   Device operating mode.
---@field Activate integer               Sensor activation state.
---@field Charge integer                 Battery charge in joules.
---@field Maximum integer                Battery max charge.
---@field Ratio integer                  Generic ratio in range 0..1.
---@field Power integer                  Power draw in watts.
---@field Vertical integer               Vertical angle.
---@field Horizontal integer             Horizontal angle.
---@field Color integer                  Paint color index.
---@field Error integer                  Error flag.
---@field PrefabHash integer             Device prefab hash.
---@field Channel0 integer               Data network channel 0.
---@field Channel1 integer               Data network channel 1.
---@field Channel2 integer               Data network channel 2.
---@field Channel3 integer               Data network channel 3.
---@field Channel4 integer               Data network channel 4.
---@field Channel5 integer               Data network channel 5.
---@field Channel6 integer               Data network channel 6.
---@field Channel7 integer               Data network channel 7.
---@field RatioOxygen integer            O₂ gas ratio.
---@field RatioCarbonDioxide integer     CO₂ gas ratio.
---@field RatioNitrogen integer          N₂ gas ratio.
---@field RatioPollutant integer         Pollutant gas ratio.
---@field RatioMethane integer           Methane gas ratio.
---@field RatioVolatiles integer         Older scripts may use this alias for methane.
---@field RatioWater integer             H₂O gas ratio.
---@field RatioNitrousOxide integer      N₂O gas ratio.
---@field RatioHydrogen integer          H₂ gas ratio.
---@field RatioSteam integer             Steam ratio.
---@field RatioPollutedWater integer     Polluted water ratio.
---@field RatioHydrazine integer         Hydrazine ratio.
---@field RatioLiquidAlcohol integer     Ethanol ratio.
---@field RatioHelium integer            Helium ratio.
---@field RatioSilanol integer           Silanol/coolant ratio.
---@field RatioHydrochloricAcid integer  HCl ratio.
---@field RatioOzone integer             Ozone ratio.
---@field RatioLiquidOzone integer       Liquid ozone ratio.
---@field RatioLiquidNitrogen integer           Liquid nitrogen ratio.
---@field RatioLiquidOxygen integer             Liquid oxygen ratio.
---@field RatioLiquidMethane integer            Liquid methane ratio.
---@field RatioLiquidCarbonDioxide integer      Liquid CO₂ ratio.
---@field RatioLiquidPollutant integer          Liquid pollutant ratio.
---@field RatioLiquidNitrousOxide integer       Liquid N₂O ratio.
---@field RatioLiquidHydrogen integer           Liquid hydrogen ratio.
---@field RatioLiquidHydrazine integer          Liquid hydrazine ratio.
---@field RatioLiquidSilanol integer            Liquid silanol ratio.
---@field RatioLiquidHydrochloricAcid integer   Liquid HCl ratio.
---@field RatioLiquidOzone integer              Liquid ozone ratio.
---@field [string] integer

---@class LogicSlotTypeEnum
---@field Occupied integer        Whether the slot has an item (0/1).
---@field Quantity integer        Stack count in slot.
---@field Charge integer          Charge level of item in slot.
---@field MaxQuantity integer     Max stack size.
---@field PrefabHash integer      Prefab hash of item in slot.
---@field On integer              Documented on earlier pages; kept for compatibility.
---@field [string] integer

---@class LogicBatchMethodEnum
---@field Average integer         Average of all matching values.
---@field Sum integer             Sum of all matching values.
---@field Minimum integer         Smallest matching value.
---@field Maximum integer         Largest matching value.

---@class LogicReagentModeEnum
---@field TotalContents integer   Total contents for the requested reagent.
---@field [string] integer

---@class SoundAlertEnum
---@field [string] integer

---@class StationeersLuaEnums
---@field LogicType LogicTypeEnum
---@field LogicSlotType LogicSlotTypeEnum
---@field LogicBatchMethod LogicBatchMethodEnum
---@field LogicReagentMode LogicReagentModeEnum
---@field SoundAlert SoundAlertEnum

-- ============================================================================
-- CONSTANTS
-- ============================================================================

---@class StationeersLuaConst
---@field BASE_UNIT_INDEX integer    IC housing device index; docs say typically 6.
---@field BASE_NETWORK_INDEX integer Documented in quick reference.
---@field [string] integer|number|string|boolean

-- ============================================================================
-- DEVICE TYPES
-- ============================================================================

---@class StationeersDeviceInfo
---@field ref_id integer
---@field prefab_hash integer
---@field name_hash integer
---@field display_name string

---@class StationeersPeerInfo
---@field id integer
---@field name string

---@class StationeersPublishOptions
---@field retain boolean?        New subscribers get the retained value immediately.
---@field ttl number?            Retained message expiration in seconds.
---@field include_self boolean?  Whether publisher should receive its own message.

---@class StationeersNet
local _StationeersNet = {}

---Get own endpoint ID.
---@return integer
function _StationeersNet.id() end

---List all Lua chip peers visible on the current data network.
---@return StationeersPeerInfo[]
function _StationeersNet.peers() end

---Send a direct message to a specific target by name or ReferenceId.
---@param target net_target
---@param channel net_channel
---@param payload any
function _StationeersNet.send(target, channel, payload) end

---Broadcast a message to all Lua chip peers on the current network.
---@param channel net_channel
---@param payload any
---@return integer delivered_count
function _StationeersNet.broadcast(channel, payload) end

---Register or unregister a direct-message listener for a channel.
---Handler signature follows the message poll fields:
---`handler(fromId, fromName, channel, payload)`.
---@param channel net_channel
---@param handler stationeers_handler_ref|nil
function _StationeersNet.listen(channel, handler) end

---Poll for the next pending direct message.
---@return integer|nil fromId
---@return string|nil fromName
---@return string|integer|nil channel
---@return any payload
function _StationeersNet.recv() end

---Publish a payload to a topic.
---@param topic string
---@param payload any
---@param opts StationeersPublishOptions?
---@return integer delivered_count
function _StationeersNet.publish(topic, payload, opts) end

---Subscribe to an exact topic or wildcard pattern.
---Handler signature:
---`handler(topic, payload, fromId, fromName, retained)`.
---@param pattern topic_pattern
---@param handler stationeers_handler_ref
function _StationeersNet.subscribe(pattern, handler) end

---Remove a pub/sub subscription.
---@param pattern topic_pattern
function _StationeersNet.unsubscribe(pattern) end

---Register an RPC method.
---Handler signature:
---`handler(payload, fromId, fromName) -> responsePayload`
---@param method rpc_method
---@param handler fun(payload:any, fromId: integer, fromName: string): any
function _StationeersNet.register(method, handler) end

---Unregister an RPC method.
---@param method rpc_method
function _StationeersNet.unregister(method) end

---Issue an RPC request.
---Callback is expected to receive response state from the implementation; the docs do
---not fully formalize callback parameters on the reference page, so they are left open.
---@param target net_target
---@param method rpc_method
---@param payload any
---@param callback stationeers_handler_ref
---@param timeout number?
function _StationeersNet.request(target, method, payload, callback, timeout) end

---Serialize a value to base64 MessagePack.
---@param value any
---@return string
function _StationeersNet.pack(value) end

---Deserialize a value from base64 MessagePack.
---@param str string
---@return any
function _StationeersNet.unpack(str) end

---@class StationeersEvents
local _StationeersEvents = {}

---Register an event handler by function reference or function name.
---@param name event_name
---@param handler stationeers_handler_ref
function _StationeersEvents.on(name, handler) end

---Unregister an event handler.
---@param name event_name
function _StationeersEvents.off(name) end

---@class StationeersDeviceNamespace
local _StationeersDeviceNamespace = {}

---Set the display name of a device on a pin index.
---@param dev device_index
---@param name string
function _StationeersDeviceNamespace.label(dev, name) end

---@class StationeersIC
---@field enums StationeersLuaEnums
---@field const StationeersLuaConst
---@field net StationeersNet
---@field events StationeersEvents
---@field device StationeersDeviceNamespace
ic = {}

-- ----------------------------------------------------------------------------
-- Device I/O
-- ----------------------------------------------------------------------------

---Read a logic value from a device index.
---Returns nil if the device is missing or disconnected.
---@param dev device_index
---@param logicType integer
---@param net network_index?
---@return number|nil
function ic.read(dev, logicType, net) end

---Write a logic value to a device index.
---The docs warn this can throw if the device is missing.
---@param dev device_index
---@param logicType integer
---@param value number
---@param net network_index?
function ic.write(dev, logicType, value, net) end

---Read a logic value by ReferenceId.
---Returns nil if the device is missing or disconnected.
---@param id reference_id
---@param logicType integer
---@param net network_index?
---@return number|nil
function ic.read_id(id, logicType, net) end

---Write a logic value by ReferenceId.
---@param id reference_id
---@param logicType integer
---@param value number
---@param net network_index?
function ic.write_id(id, logicType, value, net) end

---Find a device by display label; returns its ReferenceId.
---@param name string
---@param net network_index?
---@return reference_id|nil
function ic.find(name, net) end

---Find all devices by display label; returns ReferenceIds.
---@param name string
---@param net network_index?
---@return reference_id[]
function ic.find_all(name, net) end

---Set the display name of a device on a pin index.
---@param dev device_index
---@param name string
function ic.device_label(dev, name) end

-- ----------------------------------------------------------------------------
-- Slots & Reagents
-- ----------------------------------------------------------------------------

---Read a slot property from a device index.
---@param dev device_index
---@param slot slot_index
---@param slotType integer
---@param net network_index?
---@return number|nil
function ic.read_slot(dev, slot, slotType, net) end

---Write a slot property on a device index.
---@param dev device_index
---@param slot slot_index
---@param slotType integer
---@param value number
---@param net network_index?
function ic.write_slot(dev, slot, slotType, value, net) end

---Read a slot property by ReferenceId.
---@param id reference_id
---@param slot slot_index
---@param slotType integer
---@param net network_index?
---@return number|nil
function ic.read_slot_id(id, slot, slotType, net) end

---Write a slot property by ReferenceId.
---@param id reference_id
---@param slot slot_index
---@param slotType integer
---@param value number
---@param net network_index?
function ic.write_slot_id(id, slot, slotType, value, net) end

---Read reagent data from a device.
---@param dev device_index
---@param mode integer
---@param reagentHash reagent_hash
---@param net network_index?
---@return number|nil
function ic.read_reagent(dev, mode, reagentHash, net) end

---Get reagent-hash to prefab-hash mapping for a device.
---@param dev device_index
---@param net network_index?
---@return table<integer, integer>
function ic.rmap(dev, net) end

-- ----------------------------------------------------------------------------
-- Batch operations
-- ----------------------------------------------------------------------------

---Batch-read a logic value across all matching devices of a prefab hash.
---@param hash prefab_hash
---@param logicType integer
---@param method integer
---@param net network_index?
---@return number|nil
function ic.batch_read(hash, logicType, method, net) end

---Batch-read with an additional name-hash filter.
---@param hash prefab_hash
---@param nameHash name_hash
---@param logicType integer
---@param method integer
---@param net network_index?
---@return number|nil
function ic.batch_read_name(hash, nameHash, logicType, method, net) end

---Batch-read a slot value.
---@param hash prefab_hash
---@param slot slot_index
---@param slotType integer
---@param method integer
---@param net network_index?
---@return number|nil
function ic.batch_read_slot(hash, slot, slotType, method, net) end

---Batch-read a slot value with an additional name-hash filter.
---@param hash prefab_hash
---@param nameHash name_hash
---@param slot slot_index
---@param slotType integer
---@param method integer
---@param net network_index?
---@return number|nil
function ic.batch_read_slot_name(hash, nameHash, slot, slotType, method, net) end

---Batch-write a logic value across all matching devices of a prefab hash.
---@param hash prefab_hash
---@param logicType integer
---@param value number
---@param net network_index?
function ic.batch_write(hash, logicType, value, net) end

---Batch-write with an additional name-hash filter.
---@param hash prefab_hash
---@param nameHash name_hash
---@param logicType integer
---@param value number
---@param net network_index?
function ic.batch_write_name(hash, nameHash, logicType, value, net) end

---Batch-write a slot value.
---@param hash prefab_hash
---@param slot slot_index
---@param slotType integer
---@param value number
---@param net network_index?
function ic.batch_write_slot(hash, slot, slotType, value, net) end

---Batch-write a slot value with an additional name-hash filter.
---@param hash prefab_hash
---@param nameHash name_hash
---@param slot slot_index
---@param slotType integer
---@param value number
---@param net network_index?
function ic.batch_write_slot_name(hash, nameHash, slot, slotType, value, net) end

-- Attach nested namespaces after member declarations.
ic.net = _StationeersNet
ic.events = _StationeersEvents
ic.device = _StationeersDeviceNamespace

-- Open-ended enum/const tables for editor completion.
ic.enums = {
    ---@type LogicTypeEnum
    LogicType = {
        On = 0,
        Open = 0,
        Temperature = 0,
        Pressure = 0,
        Setting = 0,
        Mode = 0,
        Activate = 0,
        Charge = 0,
        Maximum = 0,
        Ratio = 0,
        Power = 0,
        Vertical = 0,
        Horizontal = 0,
        Color = 0,
        Error = 0,
        PrefabHash = 0,
        Channel0 = 0,
        Channel1 = 0,
        Channel2 = 0,
        Channel3 = 0,
        Channel4 = 0,
        Channel5 = 0,
        Channel6 = 0,
        Channel7 = 0,
        RatioOxygen = 0,
        RatioCarbonDioxide = 0,
        RatioNitrogen = 0,
        RatioPollutant = 0,
        RatioMethane = 0,
        RatioVolatiles = 0,
        RatioWater = 0,
        RatioNitrousOxide = 0,
        RatioHydrogen = 0,
        RatioSteam = 0,
        RatioPollutedWater = 0,
        RatioHydrazine = 0,
        RatioLiquidAlcohol = 0,
        RatioHelium = 0,
        RatioSilanol = 0,
        RatioHydrochloricAcid = 0,
        RatioOzone = 0,
        RatioLiquidOzone = 0,
        RatioLiquidNitrogen = 0,
        RatioLiquidOxygen = 0,
        RatioLiquidMethane = 0,
        RatioLiquidCarbonDioxide = 0,
        RatioLiquidPollutant = 0,
        RatioLiquidNitrousOxide = 0,
        RatioLiquidHydrogen = 0,
        RatioLiquidHydrazine = 0,
        RatioLiquidSilanol = 0,
        RatioLiquidHydrochloricAcid = 0,
    },
    ---@type LogicSlotTypeEnum
    LogicSlotType = {
        Occupied = 0,
        Quantity = 0,
        Charge = 0,
        MaxQuantity = 0,
        PrefabHash = 0,
        On = 0,
    },
    ---@type LogicBatchMethodEnum
    LogicBatchMethod = {
        Average = 0,
        Sum = 0,
        Minimum = 0,
        Maximum = 0,
    },
    ---@type LogicReagentModeEnum
    LogicReagentMode = {
        TotalContents = 0,
    },
    ---@type SoundAlertEnum
    SoundAlert = {},
}

ic.const = {
    BASE_UNIT_INDEX = 6,
    BASE_NETWORK_INDEX = 0,
}

-- ============================================================================
-- GLOBAL HELPERS / IC10-STYLE ALIASES
-- ============================================================================

---Read logic value by device index.
---@param dev device_index
---@param logicType integer
---@param net network_index?
---@return number|nil
function logic_read(dev, logicType, net) end

---Write logic value by device index.
---@param dev device_index
---@param logicType integer
---@param value number
---@param net network_index?
function logic_write(dev, logicType, value, net) end

---Batch-read logic values.
---@param hash prefab_hash
---@param logicType integer
---@param method integer
---@param net network_index?
---@return number|nil
function logic_batch_read(hash, logicType, method, net) end

---Batch-write logic values.
---@param hash prefab_hash
---@param logicType integer
---@param value number
---@param net network_index?
function logic_batch_write(hash, logicType, value, net) end

---Get a device display name.
---@param dev device_index
---@param net network_index?
---@return string|nil
function device_name(dev, net) end

---Set a device display label.
---@param dev device_index
---@param name string
function device_label(dev, name) end

---List all devices visible on the chip's data cable network.
---@param net network_index?
---@return StationeersDeviceInfo[]
function device_list(net) end

---Resolve prefab hash to prefab name.
---@param hash prefab_hash
---@return string|nil
function prefab_name(hash) end

---Resolve name hash by scanning visible devices.
---@param devHash prefab_hash
---@param nameHash name_hash
---@param net network_index?
---@return string|nil
function namehash_name(devHash, nameHash, net) end

---Set the IC housing error state.
---@param state integer
function raise_error(state) end

---Clear the IC housing error state.
function clear_error() end

---Halt and catch fire.
function hcf() end

-- ============================================================================
-- MEMORY / STACK
-- ============================================================================

---Read chip internal memory (0..511 according to docs).
---@param addr memory_address
---@return number|nil
function mem_read(addr) end

---Write chip internal memory (0..511 according to docs).
---@param addr memory_address
---@param value number
function mem_write(addr, value) end

---Clear chip internal memory.
function mem_clear() end

---Read another device's memory by pin index.
---@param dev device_index
---@param addr memory_address
---@param net network_index?
---@return number|nil
function mem_get(dev, addr, net) end

---Write another device's memory by pin index.
---@param dev device_index
---@param addr memory_address
---@param value number
---@param net network_index?
function mem_put(dev, addr, value, net) end

---Clear another device's memory by pin index.
---@param dev device_index
---@param net network_index?
function mem_clear_device(dev, net) end

---Read another device's memory by ReferenceId.
---@param id reference_id
---@param addr memory_address
---@param net network_index?
---@return number|nil
function mem_get_id(id, addr, net) end

---Write another device's memory by ReferenceId.
---@param id reference_id
---@param addr memory_address
---@param value number
---@param net network_index?
function mem_put_id(id, addr, value, net) end

---Clear another device's memory by ReferenceId.
---@param id reference_id
---@param net network_index?
function mem_clear_id(id, net) end

---Push a value onto the chip stack.
---@param value number
function stack_push(value) end

---Peek stack top without removing it.
---@return number|nil
function stack_peek() end

---Pop stack top.
---@return number|nil
function stack_pop() end

---Write directly to a stack address.
---@param addr memory_address
---@param value number
function stack_poke(addr, value) end

---Get stack pointer.
---@return integer
function stack_get_sp() end

---Set stack pointer.
---@param value integer
function stack_set_sp(value) end

---Get return-address pointer.
---@return integer
function stack_get_ra() end

---Set return-address pointer.
---@param value integer
function stack_set_ra(value) end

-- ============================================================================
-- BITWISE
-- ============================================================================

---@param a integer
---@param b integer
---@return integer
function bit_and(a, b) end

---@param a integer
---@param b integer
---@return integer
function bit_or(a, b) end

---@param a integer
---@param b integer
---@return integer
function bit_xor(a, b) end

---@param a integer
---@param b integer
---@return integer
function bit_nor(a, b) end

---@param a integer
---@return integer
function bit_not(a) end

---@param a integer
---@param n integer
---@return integer
function bit_sll(a, n) end

---@param a integer
---@param n integer
---@return integer
function bit_srl(a, n) end

---@param a integer
---@param n integer
---@return integer
function bit_sra(a, n) end

---@param val integer
---@param pos integer
---@param len integer
---@return integer
function bit_ext(val, pos, len) end

---@param dst integer
---@param src integer
---@param pos integer
---@param len integer
---@return integer
function bit_ins(dst, src, pos, len) end

-- ============================================================================
-- STRING / HASH
-- ============================================================================

---String -> hash (Animator.StringToHash).
---@param str string
---@return integer
function hash(str) end

---Pack a short ASCII string into a number.
---@param str string
---@return integer
function pack_ascii6(str) end

---Unpack a number into an ASCII string.
---@param num integer
---@return string
function unpack_ascii6(num) end

---Remove Unity color tags from text.
---@param str string
---@return string
function strip_color_tags(str) end

---Convert a value to a 53-bit integer.
---@param value any
---@return integer
function to_int53(value) end

-- ============================================================================
-- UTIL
-- ============================================================================

---@class StationeersJsonUtil
util = util or {}

---@class StationeersJsonUtil
util.json = util.json or {}

---Convert temperature between "K", "C", and "F" units (case-insensitive).
---@param value number
---@param from string?
---@param to string?
---@return number
function util.temp(value, from, to) end

---Seconds since world start.
---@return number
function util.game_time() end

---Days passed in the world.
---@return number
function util.days_past() end

---Fraction of day in range 0..1.
---@return number
function util.time_of_day() end

---Formatted clock time.
---@param pattern string?
---@return string
function util.clock_time(pattern) end

---Encode a Lua value as JSON.
---@param value any
---@return string
function util.json.encode(value) end

---Decode a JSON string.
---@param str string
---@return any
function util.json.decode(str) end

-- ============================================================================
-- OTHER GLOBALS FROM QUICK REFERENCE
-- ============================================================================

---Load module from library chip.
---@param modname string
---@param reload boolean?
---@return any
function require(modname, reload) end

---Pause script for a number of seconds.
---@param seconds number
function sleep(seconds) end

---Pause until the next tick.
function yield() end

---Throw a runtime error.
---@param msg string
function throw(msg) end
