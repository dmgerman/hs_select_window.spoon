---
--- dmg hammerspoon
---

local obj={}
obj.__index = obj
local log = hs.logger.new("selectWindow", "warning")
-- metadata

obj.name = "selectWindow"
obj.version = "2.0"
obj.author = "dmg <dmg@turingmachine.org>"
obj.homepage = "https://github.com/dmgerman/hs_select_window.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"


-- things to configure

obj.rowsToDisplay = 14 -- how many rows to display in the chooser

-- font size for chooser text (nil = system default)
obj.fontSize = nil


-- do we show the current selected window on the right corner of the screen?
obj.showCurrentlySelectedWindow = nil

-- delay for the timer... it only refreshes at this interval
obj.displayDelay = 0.2

-- persist thumbnail cache across chooser invocations (faster but may show stale content)
-- use Shift+Tab to force refresh when enabled
obj.persistentThumbnailCache = false


-- keep track of hotkeys so we can disable/enable them
obj.hotkeys = {}
obj.modalKeys = hs.hotkey.modal.new()

obj.modalKeys:bind({}, "tab", function()
    -- toggle it when typing tab
    obj.showCurrentlySelectedWindow = not obj.showCurrentlySelectedWindow
end)

obj.modalKeys:bind({"shift"}, "tab", function()
    -- force refresh thumbnail for current selection
    if obj.trackChooser then
      local selectedWin = obj.trackChooser:selectedRowContents()["win"]
      if selectedWin then
        local wid = selectedWin:id()
        if wid then
          obj.imageCache[wid] = nil  -- clear cached thumbnail
          obj.prevWindow = nil       -- force regeneration
        end
      end
    end
end)


obj.trackChooser = nil    -- timer callback to track the chooser selection
obj.imageCache = {}       -- cache window thumbnails
obj.appIconCache = {}     -- cache app icons (keyed by bundleID, never expires)

-- Get app icon from cache or load it
function obj:getAppIcon(bundleId)
  if not bundleId then return nil end
  if not obj.appIconCache[bundleId] then
    obj.appIconCache[bundleId] = hs.image.imageFromAppBundle(bundleId)
  end
  return obj.appIconCache[bundleId]
end
obj.overlay = nil         -- keep track of the snapshop being displayed
obj.overlayHeightRatio = 0.4 -- ratio of the screen to use for the overlay

-- Focus a window and activate its application.
-- Activation is needed when the window is on a different screen.
local function focusAndActivate(w)
  w:focus()
  local app = w:application()
  if app then app:activate() end
end

local TITLE_COLOR = { white = 0.25 }   -- very dark grey
local SUBTITLE_COLOR = { white = 0.35 } -- slightly lighter
local function styledText(text, sizeOffset, color, indent)
  if not obj.fontSize then
    if indent then return "    " .. text end
    return text
  end
  local size = obj.fontSize + (sizeOffset or 0)
  local attrs = { font = { size = size } }
  if color then attrs.color = color end
  local displayText = indent and ("    " .. text) or text
  return hs.styledtext.new(displayText, attrs)
end



function obj:hotkeys_enable(enable)
  for _,v in pairs (obj.hotkeys)do
    if enable then
      v:enable()
    else
      v:disable()
    end
  end
end


-- Window filter is initialized asynchronously to avoid blocking startup
obj.windowFilter = nil
obj.currentWindows = {}
obj.windowFilterReady = false


-- Callback for window events - defined here so initWindowFilter can use it
local function callback_window_created(w, appName, event)
   if event == "windowDestroyed" then
      for i,v in ipairs(obj.currentWindows) do
         if v == w then
            table.remove(obj.currentWindows, i)
            return
         end
      end
      return
   end

   if event == "windowCreated" then
      table.insert(obj.currentWindows, 1, w)
      return
   end
   if event == "windowFocused" then
      callback_window_created(w, appName, "windowDestroyed")
      callback_window_created(w, appName, "windowCreated")
   end
end

-- Function to initialize window filter (called after short delay)
local function initWindowFilter()
  log.i("Starting initialization...")
  local wf_start = hs.timer.absoluteTime()

  log.i("Creating filter...")
  obj.windowFilter = hs.window.filter.new()
  -- Only include standard, visible windows (excludes tooltips, popups, etc.)
  obj.windowFilter:setDefaultFilter{
    visible = true,
    allowRoles = 'AXStandardWindow',  -- Only standard windows
    currentSpace = nil  -- All spaces
  }
  obj.windowFilter:setSortOrder(hs.window.filter.sortByFocusedLast)
  log.i("Filter created, getting windows...")

  -- Get all windows
  for i,v in ipairs(obj.windowFilter:getWindows()) do
    table.insert(obj.currentWindows, v)
  end
  log.f("Got %d windows, subscribing...", #obj.currentWindows)

  -- Subscribe to window events
  obj.windowFilter:subscribe(hs.window.filter.windowCreated, callback_window_created)
  obj.windowFilter:subscribe(hs.window.filter.windowDestroyed, callback_window_created)
  obj.windowFilter:subscribe(hs.window.filter.windowFocused, callback_window_created)
  log.i("Subscribed to events")

  obj.windowFilterReady = true
  local elapsed = (hs.timer.absoluteTime() - wf_start) / 1e9
  log.f("Window filter initialized (%.1fs)", elapsed)
  hs.alert.show(string.format("Window filter ready (%d windows)", #obj.currentWindows))
end

function obj:findByTitle(t)
   for i,v in ipairs(obj.currentWindows) do
      if v:application() and string.find(v:title(), t) then
         return v
      end
   end
   return nil
end

function obj:focusByTitle(t)
   if not t then
      hs.alert.show("No string provided to focusByTitle")
      return nil
   end
   local w = obj:findByTitle(t)
   if w then
      w:focus()
   end
   return w
end

function obj:focusByApp(appName)
   for i,v in ipairs(obj.currentWindows) do
      local app = v:application()
      if app and string.find(app:name(), appName) then
         v:focus()
         return v
      end
   end
   return nil
end


function obj:focusByAppAndTitle(appName, title)
  for i,v in ipairs(obj.currentWindows) do
    local app = v:application()
    if app and (app:name() == appName) and string.find(v:title(), title) then
      v:focus()
      return v
    end
  end
  return nil
end


-- Initialize window filter after a short delay to not block startup
-- (callback_window_created is now defined earlier in file)
log.i("Timer scheduled for window filter init")
obj.initTimer = hs.timer.doAfter(0.1, initWindowFilter)



-- Helper: append running apps without windows to a choices list
-- @param choices table The choices list to append to
-- @param seenBundleIds table Bundle IDs already in the list (will be skipped)
-- @param excludeBundleId string|nil Bundle ID to exclude (e.g., current app)
function obj:appendWindowlessApps(choices, seenBundleIds, excludeBundleId)
   for _, app in ipairs(hs.application.runningApplications()) do
      local bundleId = app:bundleID()
      local appName = app:name()
      -- Skip apps that have windows, excluded app, and apps without UI
      if bundleId and appName and
         not seenBundleIds[bundleId] and
         bundleId ~= excludeBundleId and
         app:kind() == 1 then  -- kind 1 = regular app (not background/accessory)
         local appImage = obj:getAppIcon(bundleId)
         table.insert(choices, {
                         text = styledText(appName .. " (no windows)", 0, TITLE_COLOR),
                         subText = styledText(bundleId, -2, SUBTITLE_COLOR, true),
                         uuid = "app_" .. bundleId,
                         image = appImage,
                         win = nil,
                         app = app})
      end
   end
end

function obj:windowChoices(onlyCurrentApp, currentWin)
   local windowChoices = {}
   local currentApp = currentWin and currentWin:application() or nil
   local appsWithWindows = {}  -- Track which apps have windows

   for i,w in ipairs(obj.currentWindows) do
      -- Skip non-standard windows (tooltips, popups, etc.) and the current window
      if w ~= currentWin and w:isStandard() then
         local app = w:application()
         local appName  = '(none)'
         local appBundleId = nil
         if app then
           appName = app:name()
           appBundleId = app:bundleID()
           if appBundleId then
              appsWithWindows[appBundleId] = true
           end
         end
         if (not onlyCurrentApp) or (app == currentApp) then
           local appImage = obj:getAppIcon(appBundleId)
           local screenName = w:screen() and w:screen():name() or ""
           table.insert(windowChoices, {
                           text = styledText(w:title(), 0, TITLE_COLOR),
                           subText = styledText(appName .. " — " .. screenName, -2, SUBTITLE_COLOR, true),
                           uuid = i,
                           image = appImage,
                           win=w})
         end
      end
   end

   -- Add running apps without windows (only when not filtering by current app)
   if not onlyCurrentApp then
      local currentBundleId = currentApp and currentApp:bundleID() or nil
      obj:appendWindowlessApps(windowChoices, appsWithWindows, currentBundleId)
   end

   return windowChoices
end


function obj:_showChooser(fnListWindows, moveToCurrentSpace)

  local windowChooser = hs.chooser.new(function(choice)
       obj:leave_chooser()

       if not choice then
         return
       end
       local v = choice["win"]
       if v then
         if moveToCurrentSpace then
           hs.alert.show("move to current")
           -- we don't want to keep the window maximized
           -- move to the current space... so we leave that space alone
           if v:isFullScreen() then
             v:toggleFullScreen()
           end
           hs.spaces.moveWindowToSpace(v,
                hs.spaces.activeSpaceOnScreen(hs.screen.mainScreen())
           )
           v:moveToScreen(hs.screen.mainScreen())
         end
         focusAndActivate(v)
       elseif choice["app"] then
         -- App without windows - just activate it
         local app = choice["app"]
         local activated = app:activate(true)
         if not activated then
           log.w("activate failed, trying setFrontmost")
           activated = app:setFrontmost(true)
         end
       else
         hs.alert.show("unable to focus")
       end
   end)

   if #obj.currentWindows == 0 then
      hs.alert.show("no other window available")
      return
   end

   -- Build choices before showing the chooser so we never need to
   -- show-then-immediately-hide (which leaks enter_chooser state)
   local windowChoices = fnListWindows()
   if #windowChoices == 0 then
     hs.alert.show("no other window to select")
     return
   end
   if #windowChoices == 1 then
     local choice = windowChoices[1]
     if choice["win"] then
       focusAndActivate(choice["win"])
     elseif choice["app"] then
       local app = choice["app"]
       local activated = app:activate(true)
       if not activated then
         app:setFrontmost(true)
       end
     end
     return
   end

   obj:enter_chooser(windowChooser)
   windowChooser:choices(windowChoices)
   windowChooser:rows(obj.rowsToDisplay)
   windowChooser:query(nil)
end

function obj:selectWindow()
  local currentWin = hs.window.focusedWindow()
  obj:_showChooser(
    function () return obj:windowChoices(false, currentWin) end
  )
end

function obj:selectWindowAndMove()
  local currentWin = hs.window.focusedWindow()
  obj:_showChooser(
    function () return obj:windowChoices(false, currentWin) end,
    true
  )
end

function obj:selectAppWindow()
  local currentWin = hs.window.focusedWindow()
  local currentApp = currentWin:application()
  local otherWindows = {}
  for _, w in ipairs(obj.currentWindows) do
    if w ~= currentWin and w:application() == currentApp and w:isStandard() then
      table.insert(otherWindows, w)
    end
  end

  if #otherWindows == 0 then
    hs.alert.show("no other window for this application")
    return
  end

  -- Fast path: directly focus the only other window, skip chooser entirely
  if #otherWindows == 1 then
    focusAndActivate(otherWindows[1])
    return
  end

  obj:_showChooser(
    function () return obj:windowChoices(true, currentWin) end
  )
end

function obj:selectApp()
  local currentWin = hs.window.focusedWindow()
  local currentApp = currentWin and currentWin:application() or nil
  local currentPid = currentApp and currentApp:pid() or nil
  local currentBundleID = currentApp and (currentApp:bundleID() or currentApp:name()) or nil

  local function list_window_first_choices()
    local windowChoices = {}
    local seenPids = {}        -- Track by PID for instance uniqueness
    local seenBundleIds = {}   -- Track by bundleID for appendWindowlessApps
    for i,w in ipairs(obj.currentWindows) do
      -- Skip non-standard windows (tooltips, popups, etc.)
      if w:isStandard() then
        local app = w:application()
        local appName = (app and app:name()) or '(none)'
        local bundleID = (app and app:bundleID()) or appName
        local pid = app and app:pid()
        if pid and pid ~= currentPid and (not seenPids[pid]) then
          seenPids[pid] = true
          seenBundleIds[bundleID] = true
          local appImage = obj:getAppIcon(bundleID)
          local screenName = w:screen() and w:screen():name() or ""
          table.insert(windowChoices, {
              text = styledText(w:title(), 0, TITLE_COLOR),
              subText = styledText(appName .. " — " .. screenName, -2, SUBTITLE_COLOR, true),
              uuid = i,
              image = appImage,
              win=w})
        end
      end
    end
    -- Add running apps without windows
    obj:appendWindowlessApps(windowChoices, seenBundleIds, currentBundleID)

    return windowChoices
  end

  obj:_showChooser(list_window_first_choices)
end



function obj:enter_chooser(windowChooser)
  obj:hotkeys_enable(false)
  obj.pollChooser:start()

  obj.trackChooser = windowChooser
  if not obj.persistentThumbnailCache then
    obj.imageCache = {}
  else
    -- Clean up cache entries for windows that no longer exist
    local validIds = {}
    for _, w in ipairs(obj.currentWindows) do
      local wid = w:id()
      if wid then validIds[wid] = true end
    end
    for wid in pairs(obj.imageCache) do
      if not validIds[wid] then
        obj.imageCache[wid] = nil
      end
    end
  end

  local screenW = hs.screen.mainScreen():frame().w
  if screenW > 3000 then
    windowChooser:width(20)
  end

  windowChooser:searchSubText(true)
  windowChooser:show()
  obj.modalKeys:enter()
end

function obj:leave_chooser()
  obj.pollChooser:stop()
  obj:showImageOverlay()
  obj.trackChooser = nil

  if obj.overlay then
    obj.overlay:delete()
    obj.overlay = nil
  end

  if not obj.persistentThumbnailCache then
    obj.imageCache = {}
  end

  obj.modalKeys:exit()
  obj:hotkeys_enable(true)
end


function obj:previousWindow()
   return obj.currentWindows[2]
end

function obj:selectPreviousWindow()
  if obj.currentWindows[2] then
    focusAndActivate(obj.currentWindows[2])
  end
end

function obj:nextFullScreen()
  for _, v in ipairs(obj.currentWindows) do
    if v:isFullScreen() and v ~= obj.currentWindows[1] then
      focusAndActivate(v)
      return
    end
  end
  hs.alert.show("no next fullscreen window")
end

function obj:captureWindowSnapshot(window)
  if not window then return nil end
  return window:snapshot()
end


function obj:showImageOverlay(image)
  if obj.overlay then
    obj.overlay:delete()
    obj.overlay = nil
  end
  if not image then
    return
  end
  local screenFrame = hs.screen.mainScreen():frame()

  local origSize = image:size()
  local h = screenFrame.h * obj.overlayHeightRatio
  local w, scale
  if h < origSize.h then
    scale = h / origSize.h
    w = origSize.w * scale
  else
    h = origSize.h
    w = origSize.w
  end

  -- Position image so its right edge aligns with the chooser's left edge
  -- chooser:width() returns percentage of screen width; chooser is centered
  local chooserPct = obj.trackChooser and obj.trackChooser:width() or 40
  local chooserW = screenFrame.w * (chooserPct / 100)
  local chooserLeft = screenFrame.x + (screenFrame.w - chooserW) / 2
  local posX = chooserLeft - w

  -- Find the chooser window's actual Y position
  local posY = screenFrame.y + 40 -- fallback
  for _, w2 in ipairs(hs.window.allWindows()) do
    local app = w2:application()
    if app and app:name() == "Hammerspoon" and w2:title() == "Chooser" then
      posY = w2:frame().y
      break
    end
  end

  obj.overlay = hs.canvas.new({ x = posX, y = posY, w = w, h = h })
  obj.overlay:appendElements({
    type = "image",
    image = image,
    imageScaling = "scaleToFit",
  })
  obj.overlay:level(hs.canvas.windowLevels.overlay)
  obj.overlay:alpha(1.0)
  obj.overlay:show()
end

-- call back to display the snapshot of the currently
-- active window
local function display_currently_selected_window_callback()
  
  if obj.trackChooser and obj.trackChooser:isVisible() then
    
    if not obj.showCurrentlySelectedWindow then
      -- user might have disabled it
      obj:showImageOverlay() -- clean any window that is currently being shown
      return
    end

    local selectedWin = obj.trackChooser:selectedRowContents()["win"]

    -- only update if the window is different than the previous one

    if not selectedWin then
      -- No window (e.g., windowless app) - clear any existing overlay
      obj:showImageOverlay()
      obj.prevWindow = nil
      return
    end

    local wid = selectedWin:id()
    if wid ~= obj.prevWindow then
      local wImage = obj.imageCache[wid]
      if not wImage then
        wImage = obj:captureWindowSnapshot(selectedWin)
        obj.imageCache[wid] = wImage
      end
      obj:showImageOverlay(wImage)
      obj.prevWindow = wid
    end
  end
end

-- only enable showing the thumbnails when desired
-- it could be a bit slow and will take some memory
obj.pollChooser = hs.timer.doEvery(obj.displayDelay,display_currently_selected_window_callback)
obj.pollChooser:stop()

function obj:bindHotkeys(mapping)
  local def = {
    all_windows                          = function() self:selectWindow() end,
    all_windows_move_to_current_workspace = function() self:selectWindowAndMove() end,
    app_windows                          = function() self:selectAppWindow() end,
    first_window_per_app                 = function() self:selectApp() end,
    previous_window                      = function() self:selectPreviousWindow() end,
  }
  local descriptions = {
    all_windows                   = "Select window from all windows [hs_select_window]",
    all_windows_move_to_current_workspace = "Select window and move to current workspace [hs_select_window]",
    app_windows                   = "Select window from current app [hs_select_window]",
    first_window_per_app          = "Select first window per app [hs_select_window]",
    previous_window               = "Select previously focused window [hs_select_window]",
  }
  -- do it by hand, so we can keep track of the hotkeys
  for i,v in pairs (mapping)do
    obj.hotkeys[i] = hs.hotkey.bind(v[1], v[2], descriptions[i] or "Window selection [hs_select_window]", def[i])
    obj.modalKeys:bind(v[1], v[2], function()
        hs.eventtap.keyStroke({"ctrl"}, "n")
    end)
-- I am just going to assume that nobody is going to use shift to call the function
    local ks = {table.unpack(v[1])}
    ks[#ks+1] = "shift"
    obj.modalKeys:bind(ks, v[2], function()
        hs.eventtap.keyStroke({"ctrl"}, "p")
    end)
  end
end

function obj:stop()
  self.pollChooser:stop()
  if self.initTimer then
    self.initTimer:stop()
    self.initTimer = nil
  end
  if self.windowFilter then
    self.windowFilter:unsubscribeAll()
    self.windowFilter = nil
  end
  for name, hk in pairs(self.hotkeys) do
    hk:delete()
  end
  self.hotkeys = {}
  self.modalKeys:exit()
  self.currentWindows = {}
  if self.overlay then
    self.overlay:delete()
    self.overlay = nil
  end
end

return obj

