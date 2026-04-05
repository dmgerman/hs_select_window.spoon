-- Integration tests for hs_select_window.spoon
-- Run with: hs -c "dofile('/Users/dmg/.hammerspoon/Spoons/hs_select_window.spoon/tests/test.lua')"

local passed = 0
local failed = 0
local errors = {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    table.insert(errors, name .. ": " .. tostring(err))
    print("  FAIL: " .. name .. " — " .. tostring(err))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a))
  end
end

local function assert_truthy(v, msg)
  if not v then error(msg or "expected truthy value") end
end

local function assert_nil(v, msg)
  if v ~= nil then error(msg or "expected nil, got " .. tostring(v)) end
end

print("\n=== hs_select_window.spoon tests ===\n")

local sw = spoon.hs_select_window

-- API existence
test("API: findByTitle exists", function()
  assert_eq(type(sw.findByTitle), "function")
end)
test("API: focusByTitle exists", function()
  assert_eq(type(sw.focusByTitle), "function")
end)
test("API: focusByApp exists", function()
  assert_eq(type(sw.focusByApp), "function")
end)
test("API: focusByAppAndTitle exists", function()
  assert_eq(type(sw.focusByAppAndTitle), "function")
end)
test("API: selectWindow exists", function()
  assert_eq(type(sw.selectWindow), "function")
end)
test("API: selectAppWindow exists", function()
  assert_eq(type(sw.selectAppWindow), "function")
end)
test("API: selectWindowAndMove exists", function()
  assert_eq(type(sw.selectWindowAndMove), "function")
end)
test("API: selectApp exists", function()
  assert_eq(type(sw.selectApp), "function")
end)
test("API: choosePreviousWindow exists", function()
  assert_eq(type(sw.choosePreviousWindow), "function")
end)
test("API: previousWindow exists", function()
  assert_eq(type(sw.previousWindow), "function")
end)
test("API: nextFullScreen exists", function()
  assert_eq(type(sw.nextFullScreen), "function")
end)
test("API: windowChoices exists", function()
  assert_eq(type(sw.windowChoices), "function")
end)
test("API: stop exists", function()
  assert_eq(type(sw.stop), "function")
end)
test("API: bindHotkeys exists", function()
  assert_eq(type(sw.bindHotkeys), "function")
end)

-- Removed methods should not exist
test("API: focus_by_bundle_id removed", function()
  assert_nil(sw.focus_by_bundle_id)
end)
test("API: focus_by_title removed (snake_case)", function()
  assert_nil(sw.focus_by_title)
end)
test("API: focus_by_app removed (snake_case)", function()
  assert_nil(sw.focus_by_app)
end)
test("API: selectFirstAppWindow removed", function()
  assert_nil(sw.selectFirstAppWindow)
end)

-- No global leaks
test("No global: theWindows", function()
  assert_nil(_G["theWindows"], "theWindows leaked to global")
end)
test("No global: display_currently_selected_window_callback", function()
  assert_nil(_G["display_currently_selected_window_callback"])
end)
test("No global: list_window_first_choices", function()
  assert_nil(_G["list_window_first_choices"])
end)

-- currentWindows state
test("currentWindows is non-empty", function()
  assert_truthy(#sw.currentWindows > 0,
    "expected windows, got " .. #sw.currentWindows)
end)

test("currentWindows entries have valid applications", function()
  local stale = 0
  for _, w in ipairs(sw.currentWindows) do
    if not w:application() then stale = stale + 1 end
  end
  -- Allow some stale (window filter bug), but flag if > 25%
  local ratio = stale / #sw.currentWindows
  if ratio > 0.25 then
    error(string.format("%d/%d windows are stale (%.0f%%)",
      stale, #sw.currentWindows, ratio * 100))
  end
end)

-- windowFilter is on obj (not leaked as global)
test("windowFilter is on obj", function()
  assert_truthy(sw.windowFilter, "windowFilter should be set")
end)

-- previousWindow
test("previousWindow returns currentWindows[2]", function()
  if #sw.currentWindows >= 2 then
    assert_eq(sw:previousWindow(), sw.currentWindows[2])
  end
end)

-- findByTitle
test("findByTitle returns nil for nonexistent", function()
  assert_nil(sw:findByTitle("__nonexistent_window_title_12345__"))
end)

test("findByTitle finds a real window", function()
  -- Use a window we know exists and has a safe title (no pattern chars)
  for _, w in ipairs(sw.currentWindows) do
    local title = w:title()
    if title and #title > 3 and not title:match("[%(%)%.%%%+%-%*%?%[%]%^%$]") then
      local found = sw:findByTitle(title)
      assert_truthy(found, "should find window with title: " .. title)
      return
    end
  end
  -- If all titles have pattern chars, skip
  print("    (skipped: no safe title found)")
end)

-- windowChoices
test("windowChoices returns table with expected fields", function()
  local currentWin = hs.window.focusedWindow()
  local choices = sw:windowChoices(false, currentWin)
  assert_truthy(type(choices) == "table", "should return table")
  if #choices > 0 then
    local c = choices[1]
    assert_truthy(c.text, "choice should have text field")
    assert_truthy(c.uuid, "choice should have uuid field")
  end
end)

test("windowChoices excludes current window", function()
  local currentWin = hs.window.focusedWindow()
  local choices = sw:windowChoices(false, currentWin)
  for _, c in ipairs(choices) do
    if c.win then
      assert_truthy(c.win ~= currentWin, "should not include current window")
    end
  end
end)

-- Summary
print(string.format("\n=== Results: %d passed, %d failed ===", passed, failed))
if #errors > 0 then
  print("\nFailures:")
  for _, e in ipairs(errors) do
    print("  - " .. e)
  end
end

return failed == 0
