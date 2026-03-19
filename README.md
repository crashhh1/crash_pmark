This is my little ESX units tracker built around a UI inspired by GTA:W’s MDC. The point is simple: police can see who’s on duty, what callsign they’re running, their status + where they are, and then live tracking them straight from the panel.

## Install

- Run `@sql/callsigns.sql`
- Drag `crash_pmark` into resources folder and ensure.

## How it works

1. **Each officer sets a callsign** with:
   - `/setcallsign <callsign>`
2. **Everyone can set their live “status”** with:
   - `/status AVAILABLE|UNAVAILABLE|BUSY|ON-CALL|ON SCENE|ENROUTE`
   - Or just `/status` to get the valid options printed in chat.
3. **Tracking / MDC panel**:
   - `/pmark` (no args) opens/closes the UI roster.
   - `/pmark <callsign>` toggles tracking that unit.
   - In the UI: press the marker icon to track/untrack.

When you track someone, the script keeps their waypoint updated. It’s basically “set waypoint to their current position” repeatedly, so you get the route line on your minimap.


## Editing from the UI

- **Right click a unit row** to edit both:
  - their **callsign**
  - their **status** (dropdown-style options)

Callsign handling:
- If a unit never set a callsign, the panel shows **`unknown`**.

## Commands summary

- `/setcallsign <callsign>`
- `/status [AVAILABLE|UNAVAILABLE|BUSY|ON-CALL|ON SCENE|ENROUTE]`
- `/pmark [callsign]`


