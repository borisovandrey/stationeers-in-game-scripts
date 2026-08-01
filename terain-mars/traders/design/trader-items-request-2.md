# Request the trader's rpoposals and reuiremets
## Description
This document describes a task to extend trader-control Lua scripts for Stationeers game.
The scripts controls different satelite dishes to find trader positions and aim target dish to prepare communication.
The current scripts shall be modified to request the list of items that trader wants to sell and buy.
### Current scripts
- Shared module for common trader's data: terain-mars\traders\signals-lib.lua
- Scanner script for collecting traders positions on the sky: terain-mars\traders\trader-scanner.lua
- Implement UI for expose trader's information: terain-mars\traders\trader-signals-screen.lua
### Importan references
**Important:** Current references contains examples and descriptions on how to solve different tasks with Lua in 
Stationeers.
- Publish/Subscribe: use to be aware of https://orbitalfoundrymodteam.github.io/StationeersLuaDocs/api/net-pubsub.html
- User Interface: 
    - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/guide/getting-started.html
    - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/canvas.html
    - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/nested-layout.html

Read this before you will design and implement UI.
Also check the real examples: D:\SteamLibrary\steamapps\workshop\content\544550\3666779631\Examples

## Task
- The Antenna script shall have an additional state "RequestItems".
- The state shall be reachable only from Idle and only to Idle shall be exited
- The Antenna script shall read the state (use saved state) of new switch "tr-request-items.sw"
- This switch shall be exclusive with the switch which start search.
- When one switch is on the second shall becomes off and antenna shall go to Idle state, then to selected state.
- There shall be separate switch for antenna power. Now power control is combined with search switch.
- Don't apply switch state directly, use saved state and apply only on difference, so on state change.
### Trader Items Reaquest
Antenna shall request items provided by selected slot/trader and itesm requested by the trader.
Antenna shall publish items as two lists "sell" and "buy" in topic "items", it shall provide also tarder id and slot with thje same trade. (see scanner script for message ttls)
The request is perfomed by setting some value into antenna memory. The best trader filter shall be set by antenna in the same manner as by search.
For write to antenna memory use:
```lua
-- By reference ID
local value = mem_get_id(deviceId, 5)
mem_put_id(deviceId, 5, 100)
mem_clear_id(deviceId)
``` 
Each request and response is a bitwise constrcution, described in: