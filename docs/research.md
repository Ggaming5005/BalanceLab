# Research and design

## Existing work

[game-econ-sim](https://github.com/GlorisMoon/game-econ-sim) explores local Monte Carlo game-economy simulation, design targets and pity-aware odds. [loot-table-lab](https://github.com/fenton59/loot-table-lab) provides probability distributions, charts and pity analysis in a dependency-free web tool. These establish that economy and drop-rate analysis already have useful open-source implementations. Their source and assets are not included here.

BalanceLab focuses on the Studio workflow: a native inspector, a pinned before/after run, editable Luau-compatible configs, and a small library using the same upgrade curves as the analysis. It models a narrow deterministic purchase schedule and derives first-success loot probabilities analytically. It does not claim to simulate every economy or reproduce measured player behavior.

## Engine decisions

- [Require by string](https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#require) lets the pure modules run in both standalone Luau and Roblox. Relative paths and `@self` are used by the runtime.
- The plugin uses a [DockWidgetPluginGui](https://create.roblox.com/docs/reference/engine/classes/DockWidgetPluginGui) and Studio theme colors. No embedded browser or UI framework is needed.
- Configuration export uses [ChangeHistoryService](https://create.roblox.com/docs/reference/engine/classes/ChangeHistoryService) recording so the inserted ModuleScript can be undone.
- Module import is an explicit user action because [ModuleScript execution](https://create.roblox.com/docs/reference/engine/classes/ModuleScript) runs code. JSON editing provides a data-only path.

## Mathematics and boundaries

Income changes at purchase events, so the simulator jumps directly to the next affordable action. Between events, wallet balance is linear. The efficient strategy minimizes a local payback estimate subject to improving its current goal estimate; it makes no global-optimality claim.

With fixed target chance `p`, the probability of a first drop by roll `n` is `1 - (1-p)^n`. With hard pity `N`, this becomes 1 at `n=N`. Expected rolls are the sum of survival probabilities, `(1-(1-p)^N)/p`, or `1/p` without pity. Given misses so far, hard pity reduces the remaining count. Mapping these roll counts onto the all-misses purchase schedule gives the displayed play-time percentiles.

Rare-roll calculations use stable small-probability expressions. Curve evaluation avoids intermediate exponential overflow when a small base keeps the combined value in range. Validation rejects generated values outside the documented bounds; simulation and game-facing helpers share the same curve values. Numeric outputs still use double precision.

The core limits work and accepts yielding/cancellation callbacks. The UI yields during long runs and discards stale results after edits. Chart drawing uses a bounded sample count; inspecting a cursor uses the full event timeline. A roll cap is reported as a limit, including when no median was reached.

## Ownership

Each plugin App owns its widget, toolbar, connections, in-flight tasks and temporary import module. Destroy cancels tasks, disconnects external signals and removes owned instances. Configuration exports are deliberate scene objects and remain after the plugin closes. The runtime is pure Luau and does not connect engine events.
