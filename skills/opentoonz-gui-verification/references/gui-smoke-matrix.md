# OpenToonz GUI Smoke Matrix

Use this matrix after `mise run gui-smoke-launch`. Start each interaction sequence with Computer Use `get_app_state` for `OpenToonz`.

## Startup

- Pass if the main OpenToonz window appears and has no visible crash, fatal error, missing `TOONZROOT`, or Qt plugin error dialog.
- Pass the isolated-profile check only if visible project paths, logs, or harness summary point at `OPENTOONZ_GUI_TOONZROOT`, not a user profile OpenToonz data directory or system-wide installed application.
- When `OPENTOONZ_GUI_STARTUP_POPUP=1`, pass if `OpenToonz Startup` appears with `Create Scene`, `Open Scene`, or equivalent startup controls, and can be dismissed without closing the main app.
- When `OPENTOONZ_GUI_STARTUP_POPUP=0`, pass if the main workspace is immediately reachable.
- Record startup time from launch to first stable main-window observation.

## Room Tabs

- Pass if these default room tabs are present or reachable: `Drawing`, `Timeline`, `Cleanup`, `Palette`, `InknPaint`, `Composite`, `Xsheet`, `Tasks`, `Browser`.
- Prefer clicking room tab accessibility elements by index. Use coordinates only if the tab bar is visible but not exposed in the accessibility tree.
- After each tab click, call `get_app_state` again and verify the room-specific panels below.

## Drawing

- Expected panels or visible controls: `ToolBar`, `ToolOptions`, `SceneViewer` or `ComboViewer`, `Timeline`, `LevelPalette`, `StyleEditor`, `FilmStrip`, `CommandBar`.
- Pass if the central viewer area is not blank from a failed load and core drawing-room controls are visible.

## Timeline

- Expected panels or visible controls: timeline/xsheet-style frame area, viewer, command bar, and tool options.
- Pass if the frame/cell grid area is visible and switching away and back does not hang.

## Cleanup

- Expected panels or visible controls: cleanup settings, viewer, xsheet or timeline controls.
- Pass if cleanup settings controls render and no missing widget/fatal dialog appears.

## Palette

- Expected panels or visible controls: palette/style editor controls, viewer, and level palette or studio palette.
- Pass if color/style controls are visible and the room responds to tab focus.

## InknPaint

- Expected panels or visible controls: viewer, level palette, filmstrip, and drawing/paint tools.
- Pass if paint-oriented panels render and the room switch completes within a few seconds.

## Composite

- Expected panels or visible controls: schematic, viewer, timeline/xsheet, and function/FX-related panels when exposed by the layout.
- Pass if the composite workspace appears without blank/fatal panels.

## Xsheet

- Expected panels or visible controls: `Xsheet`, frame/cell grid, function editor or related controls.
- Pass if the xsheet grid is visible and the app remains responsive after a simple click in the grid.

## Tasks

- Expected panels or visible controls: task list/viewer, cleanup/render task controls, batch server controls where present.
- Pass if the tasks room loads without requiring external services.

## Browser

- Expected panels or visible controls: file browser tree/list, folder/navigation controls, and scene cast area where present.
- Pass if the browser room shows filesystem/project navigation without blocking on missing folders.

## Responsiveness

- For each checked room, fail if a tab click or basic focus action takes more than 10 seconds to produce a stable `get_app_state` result.
- Record visible rendering corruption, empty main-window content, repeated beachball/spinner behavior, or escalating RSS as observations even if the smoke run continues.
