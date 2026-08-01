# Traders Refactor Plan

Source:
  - Derived from [task.md](/D:/project/stationeers/terain-mars/traders/task.md)
  - Implementation must stay aligned with the requirements and examples listed in `task.md`.

- [x] Review `dish-control.lua` and map the code that belongs to shared signal models, scanner flow, antenna flow, panel logic, persistence, and future UI integration.

- [x] Create shared library module `signals-lib.lua` using the Stationeers library chip pattern with `--@module` declaration and a returned module table.
Reference:
  - https://orbitalfoundrymodteam.github.io/StationeersLuaDocs/guide/library-chips.html
Acceptance:
  - Confirm the module shape, `--@module` usage, and `require(...)` contract against the linked library-chip example before writing the file.

- [x] Move shared constants, enums, and helpers needed by multiple scripts into `signals-lib.lua`.
Acceptance:
  - Keep reusable signal-domain items together, including trader type names, signal position source, comparison helpers, and serialization helpers.
  - Leave script-specific state machines out of the library.

- [x] Implement `Signal` in `signals-lib.lua`.
Acceptance:
  - Preserve current fields from the prototype.
  - Add `SizeX`, `SizeZ`, and `MinimumWattsToContact` read from dish logic.
  - Keep compact serialization with short field names and a flat structure.

- [x] Implement `Dish` in `signals-lib.lua`.
Acceptance:
  - Preserve current device lookup, idle/on checks, positioning, and signal reads.
  - Extend dish reads to include the new signal size and minimum-contact-watts fields.
  - Keep the API usable from both scanner and antenna scripts.

- [x] Implement `SignalList` in `signals-lib.lua` with role-based behavior for `Master`, `Consumer`, and `Updater`.
Reference:
  - https://orbitalfoundrymodteam.github.io/StationeersLuaDocs/api/net-pubsub.html
Acceptance:
  - Check publish/subscribe options, retained-message behavior, and topic usage against the linked net pub/sub examples before implementation.
  - `Master` persists the full list by key and publishes retained full-list payloads on `signals`.
  - `Consumer` subscribes to `signals` and replaces local state from incoming full-list payloads.
  - `Updater` listens to `signals`, applies incoming full-list data, and can publish slot updates to `signals/upd`.
  - Use JSON string payloads for both persistence and pub/sub messages.
  - Keep serialized field names as 2-3 character acronyms in a single-level object.

- [x] Define `SignalList` merge and sync rules clearly in code before splitting scripts.
Acceptance:
  - Full-list sync removes local entries that are absent remotely.
  - Slot update sync adds missing local entries.
  - If local and incoming slots contain the same signal, keep the better sample based on watts reaching contact.
  - Local changes caused by subscribed updates must not be republished on the update topic.

- [x] Extract scanner functionality into its own script.
Acceptance:
  - Move scanner state machine, scan planning, border tracking, cycle cleanup, persistence triggers, and pub/sub publishing into a dedicated scanner script.
  - Scanner script uses `signals-lib.lua` and owns the `SignalList` as `Master`.
  - Scanner listens to `signals/upd` and applies valid slot-level improvements.

- [x] Extract antenna functionality into its own script and separate antenna panel logic into a dedicated module or script-local component.
Acceptance:
  - Antenna code uses `signals-lib.lua` and consumes the shared list instead of owning the master copy.
  - Antenna updates only its slot when it finds better data and publishes full slot payloads to `signals/upd`.
  - Antenna applies the requested rules for remove/add/update behavior without echoing subscribed changes back onto the network.
  - Existing panel/control behavior remains functional after the split.

- [x] Create the scripted screen UI script for signal list display.
Reference:
  - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/guide/getting-started.html
  - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/canvas.html
  - https://orbitalfoundrymodteam.github.io/ScriptedScreensDocs/api/nested-layout.html
Acceptance:
  - Review the linked getting-started, canvas, and nested-layout examples before implementing the screen script structure and redraw flow.
  - Use Scripted Screens APIs and prefer nested layout instead of a plain table widget.
  - Subscribe to the shared signal list topic and rebuild the displayed list whenever a new full list is received.
  - Display `Slot`, trader type name, `SizeX x SizeZ`, angle to signal, minimum watts to contact, watts reaching contact, and signal id.

- [x] Define final file layout under `terain-mars/traders` and update imports/usages accordingly.
Acceptance:
  - Shared library, scanner script, antenna script, and UI script have stable names and clear responsibilities.
  - All consumers load the shared module via `require(...)`.

- [ ] Validate the refactor in game.
Acceptance:
  - Startup restore works after `yield`.
  - Scanner repopulates and republishes the list.
  - Antenna receives list data, improves slot data when appropriate, and publishes valid updates.
  - UI refreshes on incoming list changes.
  - Edge cases are checked for empty lists, missing signals, invalid readings, and power/device-off states.
