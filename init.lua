---
--- dmg hammerspoon
---

local obj={}
obj.__index = obj

-- metadata

obj.name = "selectWindow"
obj.version = "0.1"
obj.author = "dmg <dmg@turingmachine.org>"
obj.homepage = "https://github.com/dmgerman/selectWindow.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- things to configure

obj.rowsToDisplay = 14 -- how many rows to display in the chooser


-- for debugging purposes
function obj:print_table(t, f)
   for i,v in ipairs(t) do
      print(i, f(v))
   end
end

-- for debugging purposes

function obj:print_windows()
   function w_info(w)
      return w:title() .. w:application():name()
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


function obj:list_window_choices(onlyCurrentApp)
   local windowChoices = {}
   local currentWin = hs.window.focusedWindow()
   local currentApp = currentWin:application()
   print("\nstarting to populate")
   print(currentApp)
   for i,w in ipairs(obj.currentWindows) do
      if w ~= currentWin then
         local app = w:application()
         local appImage = nil
         local appName  = '(none)'
         if app then
            appName = app:name()
            appImage = hs.image.imageFromAppBundle(w:application():bundleID())
         end
         print("To insert",appName, currentApp)
         if (not onlyCurrentApp) or (app == currentApp) then
            print("inserting...")
            table.insert(windowChoices, {
                            text = w:title() .. "--" .. appName,
                            subText = appName,
                            uuid = i,
                            image = appImage,
                            win=w})
         end
      end
   end
   return windowChoices;
end

local windowChooser = hs.chooser.new(function(choice)
      if not choice then
         hs.alert.show("Nothing to focus");
         return
      end
      local v = choice["win"]
      if v then
         v:focus()
      else
         hs.alert.show("unable fo focus " .. name)
      end
end)

function obj:selectWindow(onlyCurrentApp)
   local windowChoices = obj:list_window_choices(onlyCurrentApp)
   if #windowChoices == 0 then
      if onlyCurrentApp then
         hs.alert.show("no other window for this application ")
      else
         hs.alert.show("no other window available ")
      end
      return
   end
   windowChooser:choices(windowChoices)
   --windowChooser:placeholderText('')
   windowChooser:rows(obj.rowsToDisplay)         
   windowChooser:query(nil)         
   windowChooser:show()
end

function obj:previousWindow()
   return obj.currentWindows[2]
end

-- select any other window
hs.hotkey.bind({"alt"}, "b", function()
      obj:selectWindow(false)
end)

-- select any window for the same application
hs.hotkey.bind({"alt", "shift"}, "b", function()
      obj:selectWindow(true)
end)


return obj

