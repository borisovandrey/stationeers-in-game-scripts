# Stationeers Modding Research

This document provides a comprehensive overview of how to develop mods for Stationeers, focusing on the use of BepInEx and StationeersLaunchPad.

## What is a Mod?
In the context of Stationeers, a mod is typically a C# plugin that runs within the game process. It can:
- Modify existing game logic (using Harmony patches).
- Add new items, structures, or UI components.
- Integrate with game systems like atmospherics, IC10, or power.
- Use external libraries or run scripts (like Lua) via a specialized host mod.

## Getting Started
To start developing a mod, you need the following setup:

### Environment
1.  **Unity Editor:** Version **2022.3.62f3** (Crucial for compatibility).
2.  **BepInEx 5.4.x (x64):** The base framework for loading plugins.
3.  **StationeersLaunchPad:** The modern plugin manager and framework for Stationeers.
4.  **IDE:** Visual Studio 2022 or JetBrains Rider.
5.  **Decompiler:** **dnSpy** or **ILSpy** to read `Assembly-CSharp.dll` and find hooks.

### Installation
- Install BepInEx into the game folder.
- Place `StationeersLaunchPad-Client.zip` contents into `BepInEx/plugins`.
- Run the game once to generate the folder structure.

## C# vs Rust
- **C#:** The native language for Stationeers (Unity/.NET). It is the standard for BepInEx plugins and allows direct access to the game's internal classes and Harmony patching.
- **Rust:** Not used for direct game plugins. It is primarily used for external tools (e.g., Slang compiler) or high-performance standalone applications. For game-logic mods, **C# is mandatory**.

## Simple Mod Example (C#)
A basic BepInEx plugin looks like this:

```csharp
using BepInEx;
using HarmonyLib;
using UnityEngine;

[BepInPlugin("com.example.mymod", "My Example Mod", "1.0.0")]
public class MyModPlugin : BaseUnityPlugin
{
    void Awake()
    {
        var harmony = new Harmony("com.example.mymod");
        harmony.PatchAll();
        Logger.LogInfo("My Example Mod loaded!");
    }
}

[HarmonyPatch(typeof(Assets.Scripts.Objects.Thing), "Awake")]
public class ThingPatch
{
    static void Postfix(Assets.Scripts.Objects.Thing __instance)
    {
        // Logic to run after any 'Thing' is initialized
    }
}
```

## Typical Pattern to Communicate with the Game
The primary method is **Harmony Patching**:
- **Prefix:** Intercept a method before it runs. Can be used to change arguments or skip the original code.
- **Postfix:** Run logic after a method completes. Used to react to events or modify return values.
- **Accessing Game State:** Use `GameObject.Find`, `Object.FindObjectOfType<T>`, or static managers like `InventoryManager.Instance` or `Atmospherics.Atmosphere.WorldAtmosphere`.

## Making Graphical Components
For custom UI or complex 3D objects:
1.  **Unity Editor:** Create a project using the **StationeersUnityModdingTemplate**.
2.  **UI Design:** Create a `Canvas` and use `TextMeshPro` and standard Unity UI components.
3.  **AssetBundles:** Export your UI/Meshes as an AssetBundle.
4.  **Loading:** In your C# code, load the AssetBundle and instantiate the prefab:
    ```csharp
    var bundle = AssetBundle.LoadFromFile(path);
    var prefab = bundle.LoadAsset<GameObject>("MyUI");
    var instance = Instantiate(prefab, UIManager.Instance.Canvas.transform);
    ```

## Server Mode Issues (Multiplayer)
Multiplayer synchronization is handled via the RakNet-based networking system.
- **Logic Side:** Physics and state changes should usually happen on the **Server** (`GameManager.IsServer`).
- **Visuals Side:** UI and effects should happen on the **Client** (`GameManager.IsClient`).
- **RPCs:** To change state from a client (e.g., pressing a button), you must send a network message (RPC) to the server.
- **SyncField:** Many game objects have networked fields that sync automatically. Use `OnNetworkUpdate()` to react to changes from the server.
- **Desync:** Caused by logic running on both sides inconsistently or mismatched mod versions.

## References & Working Examples
- **ModularConsoleMod:** [GitHub - tom-is-unlucky/ModularConsoleMod](https://github.com/tom-is-unlucky/ModularConsoleMod) - Excellent example of modular components and IC10 integration.
- **StationeersLua:** [GitHub - jbe-stationeers/StationeersLua](https://github.com/jbe-stationeers/StationeersLua) - Shows how to host a scripting language inside the game.
- **StationeersLaunchPad:** [GitHub - StationeersLaunchPad/StationeersLaunchPad](https://github.com/StationeersLaunchPad/StationeersLaunchPad) - The core framework.
- **Official Modding Template:** [StationeersUnityModdingTemplate](https://github.com/StationeersModding/StationeersUnityModdingTemplate).

## Materials Used
- [BepInEx Documentation](https://docs.bepinex.dev/)
- [Harmony Documentation](https://harmony.pardeike.net/)
- [Stationeers Wiki - Modding](https://stationeers-wiki.com/Modding)
- GitHub Repositories for ModularConsole, StationeersLua, and LaunchPad.
