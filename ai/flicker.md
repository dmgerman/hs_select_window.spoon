# `hs.spaces` and the Mission Control flicker

Some `hs.spaces.*` calls briefly activate Mission Control on macOS, which
produces a visible shrink/restore animation on all windows — the "flicker."
This document records which functions do it, which don't, and how to design
around it.

## Flicker sources

The following calls trigger a Mission Control activation, even when the
target is the currently focused space:

- `hs.spaces.windowsForSpace(spaceId)`
- `hs.spaces.missionControlSpaceNames()` — avg 60 ms per call, max observed 155 ms
- `hs.spaces.gotoSpace(spaceId)` — by design (performs the space switch)
- `hs.spaces.moveWindowToSpace(win, spaceId)` — by design

The flicker is not perfectly reliable per call. A single isolated invocation
may not visibly animate; a tight loop of the same call reliably does. Do not
conclude a function is safe from one negative observation — repeat 10× before
believing.

## Clean functions

The following calls returned results without any Mission Control activation
across repeated tests:

- `hs.spaces.focusedSpace()`
- `hs.spaces.allSpaces()` — returns `{screenUUID: {spaceId, ...}}` in position order
- `hs.spaces.windowSpaces(win)` — returns `{spaceId, ...}` for a given window
- `hs.spaces.activeSpaceOnScreen(screen)`

## Design rules

### 1. Prefer per-window queries over per-space queries

`windowSpaces(win)` scales with window count and stays clean. `windowsForSpace(sid)`
scales with space count *and* flickers. Any question of the form "is window W
on space S" or "which windows are on space S" can be reformulated by
iterating windows and asking each which spaces it belongs to.

Example — build the set of window IDs on the focused space without flicker:

```lua
local focused = hs.spaces.focusedSpace()
local ids = {}
for _, w in ipairs(myWindowList) do
   for _, sid in ipairs(hs.spaces.windowSpaces(w) or {}) do
      if sid == focused then
         ids[w:id()] = true
         break
      end
   end
end
```

### 2. Derive space labels from `allSpaces()` position, not names

The 1-based index within each screen's `allSpaces()` array matches macOS's
own "Desktop N" numbering. Use it as the label instead of calling
`missionControlSpaceNames()`.

```lua
local indexBySid = {}
for _, spaceIds in pairs(hs.spaces.allSpaces() or {}) do
   for idx, sid in ipairs(spaceIds) do
      indexBySid[sid] = idx
   end
end
-- Then: local label = "Desktop " .. tostring(indexBySid[sid])
```

Cost of this labelling: a fullscreen app shows as `Desktop N` rather than by
app name (`Firefox`). That is the price of not flickering.

### 3. If you truly need names, cache MCSN behind a watcher

Call `hs.spaces.missionControlSpaceNames()` once at load, subscribe to
`hs.spaces.watcher`, and refresh the cache in the watcher callback. The
refresh flicker is masked by the space-transition animation macOS is already
rendering.

```lua
local nameById = {}
local function refresh()
   local ok, names = pcall(hs.spaces.missionControlSpaceNames)
   if not ok or not names then return end
   local m = {}
   for _, sn in pairs(names) do
      for sid, n in pairs(sn) do m[sid] = n end
   end
   nameById = m
end
refresh()
local watcher = hs.spaces.watcher.new(refresh):start()
```

Read `nameById[sid]` on hot paths. Never call MCSN directly outside `refresh()`.

### 4. Keep spaces APIs off latency-sensitive paths

Even the clean functions spike occasionally (a single `windowSpaces` call has
been observed at ~17 ms; `allSpaces` is usually sub-millisecond but can
stall). Fine at ~10 ms total per chooser build; not fine on a per-frame or
per-callback path.

### 5. User-initiated switches are fine

`gotoSpace()` and `moveWindowToSpace()` flicker because they *are* the space
switch. The user pressed the key expecting a transition; the Mission Control
activation blends in. Don't try to avoid these — just don't call them on
passive read paths.

## Recipe for a chooser build

Given the rules above, a flicker-free chooser build looks like:

1. Once per invocation: `hs.spaces.allSpaces()` → `{spaceId → index}` map.
2. Per candidate window: `hs.spaces.windowSpaces(w)` → take the first space,
   look up its index, format as `"Desktop N"`.
3. No `missionControlSpaceNames()`, no `windowsForSpace()`.

Typical cost on 31 tracked windows: ~10 ms total, no flicker.

## Timing reference (this machine, Aug 2026)

| Call | Per-call cost | Flickers? |
|---|---|---|
| `focusedSpace()` | sub-ms | no |
| `allSpaces()` | sub-ms | no |
| `windowSpaces(win)` | ~0.2 ms | no |
| `windowsForSpace(sid)` | ~3.5 ms | **yes** |
| `missionControlSpaceNames()` | 34-155 ms (avg 60) | **yes** |

Numbers vary by hardware, macOS version, and how many windows/spaces exist.
Use these as order-of-magnitude, not exact.
