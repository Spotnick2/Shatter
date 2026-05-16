# Shatter

**Shatter** is a standalone disenchanting workflow addon for *World of Warcraft: TBC Anniversary*.

The MVP is planned as a lightweight replacement for the useful parts of the TradeSkillMaster Destroy UI for disenchanting, without requiring TSM. Shatter will guide enchanters through one safe player-clicked action at a time.

## Planned Modes

- Solo Mode: scan bags, queue disenchantable items, disenchant one item per click, and track results.
- Mail Mode: guide mailed disenchant requests, track the sender for each item, and help return generated materials.
- Raid / Trade Mode: track items received by trade, disenchant them, and guide material trade-back.

## Status

This repository currently contains a working Solo Mode MVP with guided disenchanting, result tracking, Shatter-owned progress UI, queue ordering, expected material estimates, and optional value filtering. Mail Mode and Raid / Trade Mode are documented but not implemented yet.

## Usage

Open Shatter:

```text
/shatter
```

Other early commands:

```text
/shatter scan
/shatter debug
/shatter trace
/shatter sim
/shatter simreset
/shatter reset
```

The main window can be resized from the bottom-right grip. Hold Shift while dragging the grip to scale the full window, or right-click the grip to reset size, scale, and position.

`/shatter sim` toggles development simulation mode. In simulation mode Shatter records fake disenchant results and advances through the queue without casting Disenchant or consuming items. `/shatter simreset` makes simulated items visible again for another test pass.

Simulation mode is a development setting. Enabling it through the slash command also enables debug mode; in the settings UI it is only shown while debug mode is active.
When simulation is enabled, Shatter shows a small `SIMULATION` badge in the header and status text warning that no items will be disenchanted.

Debug logging reports meaningful state changes. `/shatter trace` enables verbose scan and event logging for short troubleshooting sessions.

## Phase 1 Notes

Solo Mode is the only implemented mode. Mail and Raid / Trade tabs are disabled placeholders for later phases.

The real `Shatter Next` path uses a guided secure macro button for one player click against the selected bag slot. Additional in-game API validation is still needed before treating real disenchant result tracking as final.

## Phase 2 Notes

Expected materials use built-in Shatter tables for Classic/TBC disenchant outcomes. Expected value is optional and only appears when a supported pricing addon is installed and has data for the resulting materials.

Value filtering is opt-in from Settings. If no pricing source is available, Shatter keeps otherwise eligible items in the queue instead of hiding them.

## Installation

Manual install target:

```text
C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\Shatter\
```

After installing or updating, run:

```text
/reload
```

## Supported Version

- World of Warcraft: TBC Anniversary
- Interface: `20505`
