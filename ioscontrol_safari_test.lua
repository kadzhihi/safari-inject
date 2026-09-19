-- IOSControl Lua 5.4 unified test for the real, active MobileSafari page.
-- Install the tweak, force-close/reopen Safari, then run this script in IOSControl.

local BASE_URL = "http://127.0.0.1:17891"
local TEST_URL = "https://example.com"
local TEST_ID = "ioscontrol-bridge-test-input"
local TEST_VALUE = "bridge@example.com"
local passed, failed, first_failed_stage = 0, 0, nil

local function record(stage, name, ok, detail)
    if ok then
        passed = passed + 1
        log(string.format("[PASS] %02d %s", stage, name))
    else
        failed = failed + 1
        first_failed_stage = first_failed_stage or string.format("%02d %s", stage, name)
        log(string.format("[FAIL] %02d %s", stage, name))
        if detail then log("  " .. tostring(detail)) end
    end
    return ok
end

local function test(stage, name, fn)
    local ok, result, detail = pcall(fn)
    if not ok then return record(stage, name, false, "Lua exception: " .. tostring(result)) end
    return record(stage, name, result == true, detail)
end

local function decode(body, status)
    if status ~= 200 then return nil, "HTTP " .. tostring(status) .. ": " .. tostring(body) end
    local ok, data = pcall(jsonDecode, body)
    if not ok or type(data) ~= "table" then return nil, "invalid JSON: " .. tostring(body) end
    return data, nil
end

local function getJSON(path)
    local body, status = httpGet(BASE_URL .. path)
    return decode(body, status)
end

local function postText(path, source)
    local body, status = httpPost(BASE_URL .. path, source, { ["Content-Type"] = "text/plain; charset=utf-8" })
    return decode(body, status)
end

local function postJSON(path, value)
    local body, status = httpPost(BASE_URL .. path, jsonEncode(value), { ["Content-Type"] = "application/json; charset=utf-8" })
    return decode(body, status)
end

local function evalJS(source)
    return postText("/eval", source)
end

local function resultEquals(response, expected)
    return response and response.ok == true and tostring(response.result) == expected
end

openURL(TEST_URL)
sleep(3) -- Required once for Safari to create/load the real target tab.

test(1, "injection-bridge", function()
    local r, err = getJSON("/ping")
    return r and r.ok == true and r.bundle == "com.apple.mobilesafari", err or "unexpected ping response"
end)

test(2, "ping", function()
    local r, err = getJSON("/ping")
    return r and r.bridge == "IOSControlSafariHTTP" and r.port == 17891, err or "unexpected ping response"
end)

local statusResponse = nil
test(3, "status", function()
    local r, err = getJSON("/status")
    statusResponse = r
    return r ~= nil, err
end)

test(4, "page-discovery", function()
    return statusResponse and statusResponse.ok == true and statusResponse.webViewFound == true,
        statusResponse and (statusResponse.error or "webViewFound was false") or "status unavailable"
end)

test(5, "document.title", function()
    local r, err = evalJS("document.title")
    return resultEquals(r, "Example Domain"), err or (r and r.error)
end)

test(6, "location.href", function()
    local r, err = evalJS("location.href")
    return r and r.ok == true and string.find(tostring(r.result), "example.com", 1, true) ~= nil, err or (r and r.error)
end)

test(7, "structured-js-result", function()
    local r, err = evalJS("JSON.stringify({title:document.title,url:location.href,inputs:document.querySelectorAll('input').length})")
    local data = nil
    if r and r.ok then
        local decoded, parsed = pcall(jsonDecode, r.result)
        if decoded then data = parsed end
    end
    return type(data) == "table" and data.title == "Example Domain" and string.find(tostring(data.url), "example.com", 1, true), err or (r and r.error)
end)

test(8, "dom-create", function()
    local r, err = evalJS("(()=>{let e=document.getElementById('" .. TEST_ID .. "');if(!e){e=document.createElement('input');e.id='" .. TEST_ID .. "';e.name='ioscontrolEmail';document.body.appendChild(e)}return e.id})()")
    return resultEquals(r, TEST_ID), err or (r and r.error)
end)

test(9, "dom-scan", function()
    local r, err = getJSON("/scan")
    if not r or r.ok ~= true or type(r.fields) ~= "table" then return false, err or (r and r.error) end
    for _, field in ipairs(r.fields) do if field.id == TEST_ID then return true end end
    return false, "created input was not returned by /scan"
end)

test(10, "dom-fill", function()
    local r, err = postJSON("/fill", { selector = "#" .. TEST_ID, value = TEST_VALUE })
    return r and r.ok == true and r.value == TEST_VALUE, err or (r and r.error)
end)

test(11, "dom-verify", function()
    local r, err = evalJS("document.getElementById('" .. TEST_ID .. "').value")
    return resultEquals(r, TEST_VALUE), err or (r and r.error)
end)

test(12, "missing-element", function()
    local r, err = postJSON("/fill", { selector = "#ioscontrol-missing-element", value = "x" })
    return r and r.ok == false and r.error == "ELEMENT_NOT_FOUND", err or (r and r.error)
end)

test(13, "invalid-selector", function()
    local r, err = postJSON("/fill", { selector = "[", value = "x" })
    return r and r.ok == false and r.error == "INVALID_SELECTOR", err or (r and r.error)
end)

test(14, "invalid-js", function()
    local r, err = evalJS("(() => {")
    return r and r.ok == false and r.stage == "javascript", err or (r and r.error)
end)

test(15, "empty-body", function()
    local r, err = postText("/eval", "")
    return r and r.ok == false and r.error == "EMPTY_BODY", err or (r and r.error)
end)

test(16, "repeat-eval", function()
    for _ = 1, 3 do
        local r, err = evalJS("document.title")
        if not resultEquals(r, "Example Domain") then return false, err or (r and r.error) end
    end
    return true
end)

test(17, "page-reload", function()
    openURL(TEST_URL)
    sleep(3) -- Required to verify the bridge after a fresh real-Safari navigation.
    local r, err = evalJS("document.title")
    return resultEquals(r, "Example Domain"), err or (r and r.error)
end)

record(18, "final-summary", true)
log("===== SUMMARY =====")
log("passed=" .. tostring(passed))
log("failed=" .. tostring(failed))
log("first_failed_stage=" .. tostring(first_failed_stage or "none"))
