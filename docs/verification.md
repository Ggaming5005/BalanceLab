# Verification

A 24-second 1280×720 H.264 clip was recorded from the real Studio plugin at 30 fps. It shows the Crystal Mine baseline, the cost-growth change from 1.16 to 1.13, exact chart values and the JSON editor. The modeled goal moves from 23m21s to 11m17s; this is a simulation result, not live player analytics. Selected frames were visually reviewed.

Local validation uses official Luau 0.747 and Rojo 7.7.0 on Windows.

## Automated checks

- Core regression suite covers closed-form times, purchase strategies, timeline invariants, first-success quantiles, hard pity and cancellation.
- Boundary regressions cover a goal reached at an eager purchase threshold, rare-roll caps, mixed/sparse loot arrays, generated curve bounds, zero and tiny-base exponentials, pity precision and public numeric counters.
- Strict analysis covers the pure library and tests. All plugin source is compiled; standalone analysis does not provide Roblox engine definitions.
- The example comparison runs directly in Luau. Rojo produces independent runtime and plugin assets.

All 51 tests passed. Strict analysis of the library and tests passed, as did compilation of every source file and both Rojo builds.

## Native Studio checks

Tested in Studio Edit mode using a real `PluginManager():CreatePlugin()` instance and `App.start(plugin)`. No Play session or persistent game storage was needed.

- The native preset button changed Crystal Mine to Factory Tycoon and recomputed the result.
- The Crystal Mine comparison matched standalone Luau: 1,400.77962997674 seconds at pickaxe cost growth 1.16, then 677.3958703137569 seconds at 1.13. The pinned baseline retained the original result.
- Negative action rate was rejected without changing the draft.
- Export produced a real returning ModuleScript. Requiring it preserved the edited value. Editing its source to a different preset and importing it read the fresh source rather than the cached result. The disposable exported module was removed afterward.
- Pet Hatchery with hard pity at roll 300 returned 300 rolls for the median, 90th and 99th percentiles, each at 1,284.9826463291348 seconds.
- The chart reacted to native pointer input and displayed exact timeline values. The independently scrolling controls, chart, result rows and JSON editor were inspected visually.
- The native JSON Apply button accepted an edited pity of 200, closed the editor, and recomputed the chart and median.
- Editing during a yielding rare-loot run cancelled its stale result. Repeated `Destroy()` was safe; its widget was removed and a fresh plugin instance opened successfully.
- After the modal fix, an engine assertion confirmed that opening JSON leaves no covered root controls visible. Destroying and reopening with the modal active was safe. A separate assertion confirmed that the cursor's right edge stays within the plot at the final time.

An independent source review also checked the numerical core and plugin. The JSON editor hides covered controls until it closes, so covered preset buttons and fields cannot receive input. Cursor positioning keeps the final pixel inside the plot; redraw clears stale cursor values.
