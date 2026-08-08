There is Lua Screen Script for Stationeers game: terain-mars\general\atmo-analyser-lib.lua
This script is not finished, just defined some set of functions.

You need to write a libraray module "atmos" that will provide functions 

init() -> returns precalculated sizes for elements
render(device, sizes)

device is a device id, that can be accessed as ic.read_id.
The script shall collect:
temperature, pressure, total moles of device and show this on screen vertically.
Then for each gas from atmos.gases shall take ratio, using key and put it in the row in scrolled area.
It shall provide icon, name, ratio and moles.

The example of using flex and scroll is:
terain-mars\traders\trader-signals-screen.lua
The example of module library:
terain-mars\traders\signals-lib.lua

**Important:** Current references contains examples and descriptions on how to solve different tasks with Lua in 
Stationeers.
- Publish/Subscribe: use to be aware of https://orbitalfoundrymodteam.github.io/StationeersLuaDocs/api/net-pubsub.html
- User Interface: 
    - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/guide/getting-started.html
    - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/canvas.html
    - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/nested-layout.html

Read this before you will design and implement UI.
Also check the real examples: D:\SteamLibrary\steamapps\workshop\content\544550\3666779631\Examples
