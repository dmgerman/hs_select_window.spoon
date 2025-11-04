---
--- dmg hammerspoon
---

local obj={}
obj.__index = obj

-- metadata

obj.name = "selectWindow"
obj.version = "0.2"
obj.author = "dmg <dmg@turingmachine.org>"
obj.homepage = "https://github.com/dmgerman/hs_select_window.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- things to configure

obj.rowsToDisplay = 14 -- how many rows to display in the chooser

-- for debugging purposes
function obj:print_table(t, f)
--   for i,v in ipairs(t) do
--      print(i, f(v))
--   end
end

-- for debugging purposes

function obj:print_windows()
  function w_info(w)
     return string.format("[%s] [%s] [%s]",
       w:application():bundleID(),
       w:application():name(),
       w:title()
     )
   end
   obj:print_table(hs.window.visibleWindows(), w_info)
end

theWindows = hs.window.filter.new()
theWindows:setDefaultFilter{}
theWindows:setSortOrder(hs.window.filter.sortByFocusedLast)
obj.currentWindows = {}
obj.previousSelection = nil  -- the idea is that one switches back and forth between two windows all the time


-- Start by saving all windows

for i,v in ipairs(theWindows:getWindows()) do
   table.insert(obj.currentWindows, v)
end

function obj:find_window_by_title(t)
   -- find a window by title.
   for i,v in ipairs(obj.currentWindows) do
      if string.find(v:title(), t) then
         return v
      end
   end
   return nil
end

function obj:focus_by_title(t)
   -- focus the window with given title
   if not t then
      hs.alert.show("No string provided to focus_by_title")
      return nil
   end
   w = obj:find_window_by_title(t)
   if w then
      w:focus()
   end
   return w
end

function obj:focus_by_app(appName)
   -- find a window with that application name and jump to it
--   print(' [' .. appName ..']')
   for i,v in ipairs(obj.currentWindows) do
--      print('           [' .. v:application():name() .. ']')
      if string.find(v:application():name(), appName) then
--         print("Focusing window" .. v:title())
         v:focus()
         return v
      end
   end
   return nil
end

function obj:focus_by_bundle_id(bundleID)
  -- find a window with that application name and jump to it
  --   print(' [' .. appName ..']')
  for i,v in ipairs(obj.currentWindows) do
    --      print('           [' .. v:application():name() .. ']')
    if string.find(v:application():bundleID(), bundleID) then
      --         print("Focusing window" .. v:title())
      v:focus()
      return v
    end
  end
  return nil
end


function obj:focus_by_app_and_title(appName, title)
  -- find a window with that application name and jump to it
  --   print(' [' .. appName ..']')
  for i,v in ipairs(obj.currentWindows) do
--     print('           [' .. v:application():name() .. ']')
    if (v:application():name() == appName) and string.find(v:title(), title) then
      --         print("Focusing window" .. v:title())
      v:focus()
      return v
    end
  end
  return nil
end


-- the hammerspoon tracking of windows seems to be broken
-- we do it ourselves

local function callback_window_created(w, appName, event)

   if event == "windowDestroyed" then
--      print("deleting from windows-----------------", w)
--      if w then
--         print("destroying window" .. w:title())
--      end
      for i,v in ipairs(obj.currentWindows) do
         if v == w then
            table.remove(obj.currentWindows, i)
            return
         end
      end
--      print("Not found .................. ", w)
--      obj:print_table0(obj.currentWindows)
--      print("Not found ............ :()", w)
      return
   end
   
   if event == "windowCreated" then
--      if w then
--         print("creating window" .. w:title())
--      end
--      print("inserting into windows.........", w)
      table.insert(obj.currentWindows, 1, w)
      return
   end
   if event == "windowFocused" then
      --otherwise is equivalent to delete and then create
--      if w then
--         print("Focusing window" .. w:title())
--      end
      callback_window_created(w, appName, "windowDestroyed")
      callback_window_created(w, appName, "windowCreated")
--      obj:print_table0(obj.currentWindows)
   end
end
theWindows:subscribe(hs.window.filter.windowCreated, callback_window_created)
theWindows:subscribe(hs.window.filter.windowDestroyed, callback_window_created)
theWindows:subscribe(hs.window.filter.windowFocused, callback_window_created)


function obj:count_app_windows(currentApp)
   local count = 0
   for i,w in ipairs(obj.currentWindows) do
      local app = w:application()
      if  (app == currentApp) then
          count = count + 1
      end
   end
   return count
end


function obj:list_window_choices(onlyCurrentApp, onlyCurrentSpace, currentWin)
   local windowChoices = {}
   local currentApp = currentWin:application()
   local currentSpace = hs.spaces.focusedSpace()
   --  print("\nstarting to populate")
   --  print(currentApp)

   for i,w in ipairs(obj.currentWindows) do
      if w ~= currentWin then
         local app = w:application()
         local appImage = nil
         local appName  = '(none)'
         if app then
           appName = app:name()
           -- add bundle id, to separate windows with same name, but different
           -- bundleID
            appBundleId = app:bundleID()
            appImage = appBundleId and hs.image.imageFromAppBundle(w:application():bundleID()) or nil
         end

         if (not onlyCurrentApp) or (app == currentApp) then
--            print("inserting...")
            if (not onlyCurrentSpace) or hs.fnutils.contains(hs.spaces.windowSpaces(w), currentSpace) then
               table.insert(windowChoices, {
                  text = w:title() .. "--" .. appName,
                  subText = appBundleId,
                  uuid = i,
                  image = appImage,
                  win = w
               })
            end
         end
      end
   end
   return windowChoices
end

function obj:windowActivate(w)
   if w then
      print("window detail: " .. hs.inspect.inspect(w))
      -- Switch to the space where the window is located (only if different from current space)
      local windowSpace = hs.spaces.windowSpaces(w)
      if windowSpace and #windowSpace > 0 then
         local currentSpace = hs.spaces.activeSpaceOnScreen(hs.screen.mainScreen())
         if windowSpace[1] ~= currentSpace then
            hs.spaces.gotoSpace(windowSpace[1])
            hs.timer.doAfter(hs.spaces.MCwaitTime, function()
               hs.spaces.closeMissionControl()
               -- this fixes a bug when the application is a different screen
               w:application():activate()
               w:focus()
            end)
         end
      end
      -- this fixes a bug when the application is a different screen
      w:application():activate()
      w:focus()
   else
      hs.alert.show("unable to focus " .. (name or "window"))
   end
end

function obj:selectWindow(onlyCurrentApp, onlyCurrentSpace, moveToCurrent)
--   print("\n\n\n--------------------------------------------------------Starting the process...\n\n")
   -- move it before... because the creation of the list of options sometimes is too slow
   -- that the window is not created before the user starts typing
   -- we need to pass the save the current window before hammerspoon becomes the active one
   local currentWin = hs.window.focusedWindow()

   local windowChooser = hs.chooser.new(function(choice)
       if not choice then
         -- hs.alert.show("Nothing to focus");
         return
       end
       local v = choice["win"]
       if v then
--         hs.alert.show("doing something, we have a v")
--         print(v)
         if moveToCurrent then
           hs.alert.show("move to current")
           -- we don't want to keep the window maximized
           -- move to the current space... so we leave that space alone
           if v:isFullScreen() then
             v:toggleFullScreen()
           end
           hs.spaces.moveWindowToSpace(v,
                hs.spaces.activeSpaceOnScreen(hs.screen.mainScreen())
           )
           v:moveToScreen(mainScreen)
         end
         self:windowActivate(v)
       else
         hs.alert.show("unable fo focus " .. name)
       end
   end)

   -- check if we have other windows
   if onlyCurrentApp then
      local nWindows = obj:count_app_windows(currentWin:application())
      if nWindows == 0 then
         hs.alert.show("no other window for this application ")
         return
      end
   end
   if #obj.currentWindows == 0 then
      hs.alert.show("no other window available ")
      return
   end

   -- show it, so we start catching keyboard events
   windowChooser:show()

   -- then fill fill it and let it do its thing
   local windowChoices = obj:list_window_choices(onlyCurrentApp, onlyCurrentSpace, currentWin)
   windowChooser:choices(windowChoices)
   windowChooser:rows(obj.rowsToDisplay)
   windowChooser:query(nil)
end

function obj:previousWindow()
   return obj.currentWindows[2]
end

-- find previous window of current application
function obj:previousAppWindow()
  local currentWin = hs.window.focusedWindow()
  local currentApp = currentWin and currentWin:application()

  if not currentApp  then
     return nil
  end

  for i, w in ipairs(obj.currentWindows) do
    if w ~= currentWin and w:application() == currentApp then
      return w
    end
  end
  return nil
end

function obj:choosePreviousWindow(onlyCurrentApp, moveToCurrent)
  local chooseWindow = self:previousWindow()
  if onlyCurrentApp then
    chooseWindow = self:previousAppWindow()
  end

  if chooseWindow then
    if moveToCurrent then
      if chooseWindow:isFullScreen() then
        chooseWindow:toggleFullScreen()
      end
      hs.spaces.moveWindowToSpace(chooseWindow, hs.spaces.activeSpaceOnScreen(hs.screen.mainScreen()))
      chooseWindow:moveToScreen(mainScreen)
    end
    self:windowActivate(chooseWindow)
  end
end

function obj:nextFullScreen()
  -- find a window by title.
  for i,v in ipairs(obj.currentWindows) do
    if v:isFullScreen() then
      if (obj.currentWindows[1] == v) then
         --        print("it is the currentn window")
         -- do nothing
      else
        v:focus()
        return
      end
    end
  end
  hs.alert("No next fullscreen window")
end

function obj:bindHotkeys(mapping)
   local def = {
      all_windows         = function() self:selectWindow(false,false,false) end,
      all_windows_current = function() self:selectWindow(false,false,true) end,
      all_windows_for_space = function() self:selectWindow(false,true,false) end,
      app_windows         = function() self:selectWindow(true, false, false) end,
      app_windows_for_space = function() self:selectWindow(true, true, false) end,
      previous_window         = function() self:choosePreviousWindow(false,false) end,
      previous_window_current = function() self:choosePreviousWindow(false,true) end,
      previous_app_window         = function() self:choosePreviousWindow(true, false) end
   }
   hs.spoons.bindHotkeysToSpec(def, mapping)
end



return obj

