## Introduction
The terain-mars\traders\dish-control.lua contains prototype of the Satelite Dish Scanner and Antenna Signal serach scripts.
There is a help for game Trading mechanic in Stationeers game.
The script shall be changed an extending. Before make any changes create paln.md file with checkboxes.
When you will implement the plan, set the checkboxes for steps.

## Goal
I want to split the existent script for some parts by functionality and add the UI script.
The following description will contains this modules description

### General functionality module
- Create library module by the rule, described at https://orbitalfoundrymodteam.github.io/StationeersLuaDocs/guide/library-chips.html
- The name of the module shall be signals-lib.lua
- The module is defined by writing `--@module <name>`
Example:
```lua
--@module pid
--@module utils

local M = {}

M.pid = { ... }    -- PID controller module
M.utils = { ... }  -- Utility functions

return M  -- Must return a table with keys matching module names    
```

- The module shall be loaded in using script by:
```lua
local atmos = require("atmos")
local safe, reason = atmos.is_breathable(101, 295, 0.5)
```
#### Module content
Module shall include `Signal`, `Dish`, `SignalList`.
All other modules shall import it and reuse SignalLsit and Dish.
So it has sense to defined differetn namespaces for them.

#### Persistence and notificarion
SignalList saves itself in case of changes and restore itself on startup. 
As we split the initial scripts, the code will be shared between other scripts, but they will have different instances.
One script, that will be responsible for scanning will create it and publish it for other.
So the SignalList shall be able to have parameters - enum 'Master', 'Consumer', 'Updater'
- Master stores it with keys and publish it over network topic
- Consumer only lsiten the topic and apply it
- Updater can partially update the lsit as it is done by Antenna script.
When list is published it is published enire, when it is updated the only single slot is updated if the signal id is the same and parameters are better.
The publish/subscribe shall be perfomed using https://orbitalfoundrymodteam.github.io/StationeersLuaDocs/api/net-pubsub.html
Example:
```lua
-- Simple publish
ic.net.publish("sensors/temp", { temp = 300, zone = "HAB-1" })

-- Publish with options
ic.net.publish("sensors/temp", { temp = 300 }, {
    retain = true,        -- New subscribers get the last retained value immediately
    ttl = 60,             -- Retained message expires after 60 seconds
    include_self = false  -- Don't deliver to self (default)
})

-- Clear a retained message by publishing nil
ic.net.publish("sensors/temp", nil, { retain = true })
```

The topics for publishing is `signals` for updates `signals/upd`.
The persistance by Key already uses the json serialisation.
Keep it also for network. Use the serialised string as signle message field.

Use short 2-3 symbols acronims for fields in serialisation.
Use plain signle level structure

#### Additional fields for signal
Ad dthe follwoing fields red from a dish:
- `SizeX`
- `SizeZ`
- `MinimumWattsToContact`

### Scanner script
- Extract scanner logic into separate script.
- Scrip shall use Signals module.
- Script shall be able to fill ScannerList.
- ScannerList publishes and persist himself.
- Scanner list listen and applies updates received from `signals/upd` topic

### Antenna script
- Extract Antenna script and AntennaPannel logic into separate module
- Script controls console inetrface elements 
- Script listens SignalList and update it by slots (in case the its slot data values are worse)
- Script publish updates for the slot (full data of slot) 
**Important** the rules of updates are:
     - if the local signal is not in the incomming list remove local
     - if the incomming slot has a signal and local has not add it to local
     - if the incomming slot and local have the same signal, update it only if watts data is better by incomming
     - in case of update local don't publish it over update channel

### UI script
UI script is based on 
- https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/guide/getting-started.html
- https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/canvas.html

- script shall represent the list (don't use table) of Signals
- script shall subscribe for SignalLsit and regenerate table each time it recives new data.

Try to use https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/nested-layout.html

The table shall contains:
- Slot
- Type of the signal (TraderTypeNames)
- SizeX x SizeZ
- Anfgle to signal
- Watts to contact
- Watts reaching the contact
- Signal Id

