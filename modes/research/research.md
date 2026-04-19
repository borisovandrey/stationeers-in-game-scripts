# Stationeers Mod Research

## What is a mod

For Stationeers, "mod" currently means one of two practical things:

1. An XML/content mod loaded from the Stationeers mods folder.
2. A code mod loaded through `BepInEx` and managed by `StationeersLaunchPad`.

The XML path is the simplest. You add a folder under:

`%USERPROFILE%\Documents\My Games\Stationeers\mods\YourMod`

Inside it, you place:

- `About/About.xml`
- `About/Preview.png`
- `About/thumb.png`
- `GameData/*.xml`
- `GameData/Language/*.xml`

This lets you change recipes, world settings, traders, language, start conditions, and other data-driven parts of the game.

The code path is for behavior the base XML system cannot express: runtime hooks, custom logic, custom UI systems, prefab registration, and Harmony-style patches. In practice, Stationeers code mods are built around Unity + .NET, with `BepInEx` as the loader and `StationeersLaunchPad` as the Stationeers-specific mod framework and packaging layer.

## What I need to start a mod

### Minimum path: XML/content mod

You need:

- Stationeers installed
- A folder in `%USERPROFILE%\Documents\My Games\Stationeers\mods`
- `About.xml`
- one or more `GameData/*.xml` files

This is enough to start changing recipes, printers, furnace behavior, world settings, and localization.

### Recommended path: modern code mod

You need:

- Stationeers
- `BepInEx 5.4.x` installed into the game folder
- `StationeersLaunchPad` installed into `BepInEx/plugins`
- a C#/.NET project for your mod
- optional Unity project if you want custom prefabs, assets, or more advanced visuals

As of March 15, 2026, the `StationeersLaunchPad` repository shows latest release `v0.3.0`, and its README still documents `BepInEx 5.4` for Stationeers.

### Recommended toolchain

For XML-first work:

- any text editor
- compare your modded XML against vanilla files under `rocketstation_Data/StreamingAssets/Data` and `rocketstation_Data/StreamingAssets/Worlds`

For code mods:

- `Visual Studio` or `Rider`
- .NET SDK
- C#
- optionally Unity, using the `StationeersUnityModdingTemplate`

### Do I need C# or can I use Rust?

The practical answer is: use **C#**.

Why:

- `BepInEx` plugins are .NET DLLs.
- official BepInEx plugin docs describe a **C#** plugin workflow and explicitly say elementary understanding of C# is required.
- Stationeers templates and current community examples are C# and Unity-oriented.
- `StationeersLaunchPad` default entrypoints are Unity `MonoBehaviour` classes or BepInEx `BaseUnityPlugin` classes.

Rust is only a theoretical or niche option if you build a .NET-compatible layer around it. That is not the standard Stationeers modding path, it will increase complexity immediately, and it will make examples and community help much less useful. If the goal is to get into the loop fast, choose C#.

## Simple mod example

### Example 1: simplest useful XML mod

This adds or overrides an electronics printer recipe:

```xml
<?xml version="1.0" encoding="utf-8"?>
<GameData>
  <ElectronicsPrinterRecipes>
    <RecipeData>
      <PrefabName>ItemGasCanisterEmpty</PrefabName>
      <Recipe>
        <Iron>10</Iron>
        <Copper>2</Copper>
        <Time>10</Time>
        <Energy>500</Energy>
      </Recipe>
    </RecipeData>
  </ElectronicsPrinterRecipes>
</GameData>
```

Put it in:

`YourMod/GameData/recipes.xml`

And pair it with a minimal `About/About.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<ModMetadata>
  <Name>My First Stationeers Mod</Name>
  <Author>YourName</Author>
  <Version>0.1.0</Version>
  <Description>Small recipe tweak for learning mod structure.</Description>
</ModMetadata>
```

### Example 2: minimal C# code mod

For StationeersLaunchPad, the preferred entrypoint is a `MonoBehaviour` with `OnLoaded(...)`:

```csharp
using BepInEx.Configuration;
using System.Collections.Generic;
using UnityEngine;

public class MyMod : MonoBehaviour
{
    void OnLoaded(ConfigFile config, List<GameObject> prefabs)
    {
        Debug.Log("MyMod loaded");
    }
}
```

This is the StationeersLaunchPad-native path. It is preferred over directly linking to unstable internal StationeersLaunchPad classes.

### Example 3: minimal BepInEx plugin shape

```csharp
[BepInPlugin("com.example.stationeers.mymod", "My Mod", "0.1.0")]
public class Plugin : BaseUnityPlugin
{
    private void Awake()
    {
        Logger.LogInfo("Plugin loaded");
    }
}
```

This works as a BepInEx-style plugin, but StationeersLaunchPad notes that these entrypoints are not loaded by the normal BepInEx ChainLoader, so BepInEx dependency and incompatibility annotations are not respected the same way there.

## Typical pattern to communicate with the game

There are three common communication patterns.

### 1. Data-driven communication

You modify the game by supplying XML that the game merges after vanilla data loads.

Typical use cases:

- recipes
- world settings
- traders
- spawn definitions
- language/localization

This is the safest starting point because it does not require runtime patching.

### 2. Runtime plugin lifecycle

With BepInEx/StationeersLaunchPad, your code runs during startup and then interacts with Unity/game objects during normal lifecycle methods.

Typical pattern:

1. Loader starts before the main game scene.
2. Your mod entrypoint is discovered.
3. `OnLoaded(...)` or `Awake()` runs.
4. You register config, inspect prefabs, attach components, or patch methods.
5. Later Unity callbacks like `Update()` or scene-specific hooks drive ongoing behavior.

Important constraint:

StationeersLaunchPad initializes entrypoints on the splash screen before the main scene is fully loaded, so early code must avoid touching parts of the game that are not ready yet.

### 3. Harmony/method patching

This is the classic BepInEx pattern for changing behavior the game does not expose through XML.

Typical use cases:

- changing vanilla logic
- intercepting UI behavior
- fixing bugs
- adding QoL behavior

If you go down this route, expect to inspect decompiled assemblies and work in C#.

## Making graphical components

There are two realistic levels here.

### Level 1. Workshop/menu graphics

Every mod should have:

- `About/Preview.png`
- `About/thumb.png`

These are used for the in-game mod browser and Steam Workshop presentation.

### Level 2. In-game visual/game objects

For real graphical components such as custom prefabs, boards, screens, or other Unity assets, you are in Unity mod territory.

Relevant facts from the current docs:

- StationeersLaunchPad automatically loads `.asset` files from enabled mods.
- its preferred entrypoint can receive `List<GameObject> prefabs`.
- the Unity template says it creates `Scripts/` content to register prefabs in the game and generates `About/` content plus an assembly definition for Stationeers DLLs.

That means the normal advanced pipeline is:

1. create assets/prefabs in Unity
2. export/package them with your mod
3. let StationeersLaunchPad load them
4. register or wire them up from your entrypoint

### Practical example from live mods

`ScriptedScreens [StationeersLaunchPad]` shows one current pattern for graphics-heavy modding:

- custom touchscreen UIs
- Lua-defined UI elements
- interactive controls
- screen/tablet rendering
- extra boards/cartridges added as craftable items

That is a good example of how the community handles richer presentation: the low-level framework is still BepInEx + StationeersLaunchPad, but the user-facing scripting layer can be something higher level like Lua.

## Server mod issues

Dedicated server support exists, but it raises operational constraints.

### Installation model

The current StationeersLaunchPad docs say the dedicated server setup is:

- install `BepInEx` into the dedicated server folder
- install the StationeersLaunchPad server package into `BepInEx/plugins`
- export a mod package from the client LaunchPad configuration
- extract it into the dedicated server folder so it creates `modconfig.xml` and a `mods` folder next to `rocketstation_DedicatedServer.exe`

### Common risks

1. Client/server mismatch.
If the server and client do not have matching required mods or compatible versions, behavior will diverge or fail.

2. Load order and dependency issues.
StationeersLaunchPad adds `ModID`, `DependsOn`, `OrderBefore`, and `OrderAfter` support in `About.xml`. Use them for anything nontrivial.

3. Early startup timing.
Because entrypoints initialize before the primary scene is loaded, mods that assume world objects already exist can break on both client and server startup.

4. Multiplayer sync.
Mods that create UI, graphics, or scripted behavior must be explicit about what is client-only and what must be synchronized. For example, ScriptedScreens warns that canvas behavior needs all players to have the mod installed.

5. Server-only testing burden.
A mod that works in single-player can still fail on a dedicated server because of timing, authority, serialization, or absent client-side assets.

### Rule of thumb

Start with:

- XML-only changes
- or a small code mod with config/logging only

Then move toward:

- Harmony patches
- custom prefabs
- custom UI systems
- multiplayer/server-aware logic

## Working examples to study

### 1. StationeersLaunchPad itself

Why study it:

- current loader and packaging expectations
- dedicated server workflow
- mod metadata extensions
- preferred code entrypoint model

### 2. StationeersUnityModdingTemplate

Why study it:

- current Unity-based project scaffold
- prefab registration approach
- generated `About/` content
- assembly definition setup for Stationeers DLLs

### 3. StationeersLua [StationeersLaunchPad]

Why study it:

- shows how a mod can expose a higher-level scripting language on top of the framework
- demonstrates a serious runtime/gameplay extension while still depending on BepInEx + LaunchPad
- useful to understand how people build a feature layer above vanilla IC10

### 4. ScriptedScreens [StationeersLaunchPad]

Why study it:

- clear example of graphical/UI modding
- Lua-driven UI layer
- demonstrates added craftable devices plus custom rendering and interactivity
- shows mod config exposed through the LaunchPad config panel

### 5. ExamplePatchMod / community example templates

The StationeersLaunchPad docs currently link example BepInEx mod templates such as:

- `StationeersModding/ExamplePatchMod`
- `aproposmath/stationeers-example-mod`

These are worth cloning first because they represent the shortest path to a compilable code mod.

## Recommended way to get into the loop fast

1. Install `BepInEx 5.4.x` and `StationeersLaunchPad`.
2. Build one XML-only mod that changes a recipe or world setting.
3. Clone a Stationeers example code mod/template.
4. Build one tiny C# code mod that only logs and registers config.
5. After that, decide whether your actual project is:
   - XML/content-first
   - Harmony patch/QoL
   - Unity asset/prefab heavy
   - custom scripting/UI heavy

If your long-term goal includes custom devices, custom boards, custom UI, or systems like Lua-backed logic, the right stack is:

- `C#`
- `BepInEx`
- `StationeersLaunchPad`
- optionally `Unity`

## Step-by-step: start your first mod

There are two good starting tracks.

### Track A: fastest possible start with an XML mod

This is the best first mod if you want to learn the file layout and see results quickly.

#### Step 1. Install and run the game once

Make sure Stationeers starts normally at least once. This ensures the standard user folders exist.

#### Step 2. Create your mod folder

Create:

`%USERPROFILE%\Documents\My Games\Stationeers\mods\MyFirstMod`

Inside it, create:

- `About`
- `GameData`

#### Step 3. Create `About/About.xml`

Use:

```xml
<?xml version="1.0" encoding="utf-8"?>
<ModMetadata>
  <Name>My First Mod</Name>
  <Author>YourName</Author>
  <Version>0.1.0</Version>
  <Description>My first Stationeers learning mod.</Description>
</ModMetadata>
```

This is the minimum metadata needed for the game to recognize the mod.

#### Step 4. Add a simple XML change

Create:

`GameData/recipes.xml`

Put a small recipe override in it. Start with one thing only. Do not try to change many systems in the first pass.

#### Step 5. Add preview images later

You can add:

- `About/Preview.png`
- `About/thumb.png`

They are useful, but they are not the first blocker for local testing.

#### Step 6. Start the game and verify the mod is visible

Open Stationeers and check whether the mod appears in the in-game mod list or behaves as expected.

If nothing changes:

- re-check folder names
- re-check XML structure
- compare your XML against vanilla files under `rocketstation_Data/StreamingAssets`

#### Step 7. Make one tiny change at a time

Good first XML mod ideas:

- change one printer recipe
- change one starting item set
- add one localization string
- adjust one world or trader value

That gives you a tight edit-test loop.

### Track B: first code mod with BepInEx and StationeersLaunchPad

This is the right path if you want runtime behavior, custom logic, custom UI, or eventually custom devices.

#### Step 1. Install BepInEx

Download the Windows `BepInEx 5.4` release and extract it into the Stationeers game folder, next to `rocketstation.exe`.

After extraction you should have:

- `BepInEx/`
- `doorstop_config.ini`

#### Step 2. Run the game once

Launch the game once, then close it. This lets BepInEx create its folders and initial config files.

#### Step 3. Install StationeersLaunchPad

Download the current `StationeersLaunchPad` client release and extract it into:

`BepInEx/plugins`

After that, LaunchPad should appear during game startup.

#### Step 4. Verify the loader stack before writing code

Do not start coding until this works:

- BepInEx is installed
- LaunchPad loads on startup
- local mods folder is recognized

If the loader stack is broken, everything after that is wasted effort.

#### Step 5. Create a C# project

Use either:

- a Stationeers example mod template
- the Unity modding template
- or a plain C# class library if you already know the references you need

For a first attempt, use a template. It removes avoidable setup mistakes.

#### Step 6. Build the smallest possible plugin

Start with a plugin that only logs a message on load. Do not patch gameplay first. Do not build a large feature first.

Your first success criterion should be:

- the DLL loads
- a log message appears
- the game still starts cleanly

#### Step 7. Add configuration next

The second milestone should be config, not gameplay complexity.

For example:

- one boolean toggle
- one integer value
- one string setting

This proves your mod can load state and exposes a cleaner base for future work.

#### Step 8. Only then start touching game behavior

After logging and config work, move to one controlled runtime change:

- inspect loaded prefabs
- attach one component
- patch one method
- change one UI behavior

Keep the first runtime change small enough that you can revert or isolate it quickly.

#### Step 9. Keep logs open while testing

For code mods, logging is your main debugging tool at the start. Expect timing issues, null references, and scene-load assumptions.

#### Step 10. Graduate to Unity assets only when needed

Do not begin with custom prefabs unless the mod really needs them. A lot of useful mods can start as:

- XML changes
- Harmony patches
- simple runtime components

Bring in Unity asset workflows only when the feature truly needs new prefabs or custom graphics.

## Example first-week plan

If you want a concrete path, this is a sensible first week:

### Day 1

- install Stationeers
- install `BepInEx`
- install `StationeersLaunchPad`
- verify startup works

### Day 2

- make one XML mod
- change one recipe
- confirm the game loads it

### Day 3

- clone an example code mod
- compile it
- make the log message unique so you know your own build is loading

### Day 4

- add one config value
- read it during startup

### Day 5

- inspect one game system you care about
- decide whether your real project is mostly XML, patching, or Unity assets

### Day 6-7

- implement one tiny real feature
- test in single-player
- if relevant, test on a dedicated server after the single-player case is stable

## Common beginner mistakes

- trying to start with a huge mod instead of one tiny proof of concept
- choosing Rust and immediately fighting the toolchain instead of learning Stationeers
- mixing old `StationeersMods` assumptions with modern `StationeersLaunchPad`
- patching too early before verifying that the loader and logs work
- adding custom assets before you understand the base file structure
- testing too many changes at once

## Sources

- BepInEx docs, "Writing a basic plugin": https://docs.bepinex.dev/master/articles/dev_guide/plugin_tutorial/
- BepInEx docs, "Creating a new project": https://docs.bepinex.dev/articles/dev_guide/plugin_tutorial/2_plugin_start.html
- BepInEx GitHub: https://github.com/BepInEx/BepInEx
- StationeersLaunchPad GitHub: https://github.com/StationeersLaunchPad/StationeersLaunchPad/
- Stationeers modding docs home: https://stationeerslaunchpad.github.io/docs/
- StationeersLaunchPad docs, "Mod Structure": https://stationeerslaunchpad.github.io/docs/structure/
- StationeersLaunchPad docs, "Writing a Code Mod": https://stationeerslaunchpad.github.io/docs/codemod/
- StationeersLaunchPad docs, "GameData Overview": https://stationeerslaunchpad.github.io/docs/xml/gamedata/
- StationeersLaunchPad docs, "RecipeData": https://stationeerslaunchpad.github.io/docs/xml/gamedata/recipedata/
- StationeersUnityModdingTemplate: https://github.com/StationeersModding/StationeersUnityModdingTemplate
- Unofficial Stationeers Wiki, modding guide: https://stationeers-wiki.com/Guide_%28Modding%29
- Steam Workshop, `StationeersLua [StationeersLaunchPad]`: https://steamcommunity.com/workshop/filedetails/?id=3659911735
- Steam Workshop, `ScriptedScreens [StationeersLaunchPad]`: https://steamcommunity.com/workshop/filedetails/?id=3666779631

## Final recommendation

If the goal is "start writing a Stationeers mod soon with the least wasted motion", do this:

- start with an XML recipe or world-settings mod today
- use C# for any code mod
- use StationeersLaunchPad's preferred `OnLoaded(...)` entrypoint instead of depending on its unstable internals
- bring in Unity only when you need custom prefabs, assets, or richer graphics/UI
- do not choose Rust for the first mod
