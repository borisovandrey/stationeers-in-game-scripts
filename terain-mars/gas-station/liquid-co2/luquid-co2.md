# CO2 condesator
## Scope
This is a device and program description for CO2 condencer device in Stationeers game.
The document describe the device, and the LUA script controlling it work
## Principle
The CO2 condemnced device is ientended for fast collecting of large volumes of liquid cold CO2 gas.
It works on Mars setup.
Under working tempereature [-25°C..-50°C] it pressurise atmoshere with help of large vent into insolated gas tank. For certain pressure and temprature (see CO2 description in the game help) the CO2 take phase shift to liquid sustain. This liquid is absorbed by passive licker vent into liquid tank.
The pressure limits defined form the perspective that less than -55°C CO2 has solid state that corrup tubes.
The temepreature high than -25°C the condesation point of CO2 is bigger than condesation point of Polutant and liquid is contaminated with liquid polutatnt.
See CO2 and Pol tables in the code.
## Device description
Device consist:
- Modular Console containing switches, indicators and siaplays
  - Power On/Of switch
  - Up switch - run or stop
  - Clear switch - force to clear full system
- Lua controller chip
- Device
  - External temperature sensor
  - Insolated gas tank
  - High pressure vent connecting to gas tank
  - Gas sensor connected to gas tank
  - Passive licker to remove liquid from gas tank to the liquid tank
  - Liquid tank
  - Liquid sensor connected to liquid tank
  - Absorption pomp connected to liquid tank for clearing
  - Absorption gas pupm conncted to liquid tank for clearing
  - Active output drain after absoption pump for clearing
## Device state mchine

```plantuml
@startuml
[*] --> PowerOff
note right of PowerOff : Off is absolute

legend top left
  Signal priorities:
  - Off
  - Dirty
  - Full
  - Up
endlegend

PowerOff -> Idle : On
Idle -[#Blue]-> Prepare : [Up]
Idle -[#Red]-> Clearing: [Dirty]
Idle -[#Orange]-> Full : [Full]

Prepare -> Idle : [!Up]

Prepare -[#Green]-> Operational : [Cond] 
Prepare -[#Orange]-> Full : [Full]

Operational -[#Blue]-> Prepare : [!Cond || !Up || Full]

note right of Clearing : [Dirty] means also switch on and is absolute
Prepare -[#Red]-> Clearing: [Dirty]
Operational -[#Red]-> Clearing: [Dirty]
Full -[#Red]-> Clearing: [Dirty]

Full --> Idle : [!Full]
Clearing --> Idle : [!Dirty]

note right of Prepare : Can leave only when Ready
state Prepare {
    [*] -> Prepare_Ready
    state "Ready" as Prepare_Ready
    ClearGas -> Prepare_Ready : [GasEmpty]
    Prepare_Ready -> ClearGas : [!GasEmpty]
    Prepare_Ready --> [*] : [GasEmpty]
    ClearGas : entry / reverse
    ClearGas : exit / restore
}

state Operational {
  [*] -> Run
  Run -> Pause : [high pressure] / stop vent
  Pause -> Run : [normal pressure] / start vent
  Run --> [*] : [!Up || Full || !Dirty]
  Pause --> [*] : [!Up || Full || !Dirty]
} 

Full : entry / stop went
Clearing : entry / reverse vent, start all
Clearing : exit / restore vent, stop all
Operational : entry / start vent
Operational : exit / stop vent
PowerOff : entry / disable all
PowerOff : exit / enable sensors only


Idle -[#Gray]-> PowerOff : Off
Prepare -[#Gray]-> PowerOff : Off
Operational -[#Gray]-> PowerOff : Off
Clearing -[#Gray]-> PowerOff : Off
Full -[#Gray]-> PowerOff : Off
@enduml
```
