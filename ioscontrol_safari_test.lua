-- IOSControl Lua 5.4
-- One-shot runtime test for IOSControl Safari Bridge v0.2.0.
-- It identifies the exact stage: bootstrap injection -> payload dlopen -> socket -> JS.

local BASE = "http://127.0.0.1:17891"
local PREFIX = "IOSCONTROL_SAFARI_"
local TEST_URL = "https://example.com"
local TMP_NAME = "__ioscontrol_safari_v2_tmp.txt"
local TMP_PATH = "/var/mobile/Library/IOSControl/Scripts/" .. TMP_NAME

local passed, failed, skipped = 0, 0, 0
local firstFailed = nil

local function has(s, needle)
    return type(s) == "string" and string.find(s, needle, 1, true) ~= nil
end

local function pass(name)
    passed = passed + 1
    log("[PASS] " .. name)
end

local function fail(name, detail)
    failed = failed + 1
    if not firstFailed then firstFailed = name end
    log("[FAIL] " .. name)
    if detail then log("       " .. tostring(detail)) end
end

local function skip(name, detail)
    skipped = skipped + 1
    log("[SKIP] " .. name)
    if detail then log("       " .. tostring(detail)) end
end

local function shell(cmd)
    execute(cmd .. " > " .. TMP_PATH .. " 2>&1")
    sleep(0.2)
    local out = readFile(TMP_NAME)
    execute("rm -f " .. TMP_PATH)
    return out
end

local function decode(body)
    if not body or body == "" then return nil end
    local ok, value = pcall(jsonDecode, body)
    if ok then return value end
    return nil
end

local function httpGetJSON(path)
    local body, status = httpGet(BASE .. path)
    return body, status, decode(body)
end

local function httpPostText(path, text)
    local body, status = httpPost(
        BASE .. path,
        text or "",
        { ["Content-Type"] = "text/plain; charset=utf-8" }
    )
    return body, status, decode(body)
end

local function waitRuntime(seconds)
    local loops = math.floor((seconds or 10) * 4)
    local last = nil
    for i = 1, loops do
        local v = clipText()
        if has(v, PREFIX) then
            if v ~= last then
                log("[RUNTIME] " .. tostring(v))
                last = v
            end
            if has(v, "HTTP_LISTENING") or
               has(v, "FAIL") or
               has(v, "WRONG_PROCESS") or
               has(v, "START_RETURNED_FALSE") then
                return v
            end
        end
        sleep(0.25)
    end
    return last
end

local function resultValue(data, body)
    if type(data) == "table" and data.result ~= nil then
        return data.result
    end
    return body
end

log("===== IOSCONTROL SAFARI V2 RUNTIME TEST =====")

execute("rm -f " .. TMP_PATH)

log("")
log("----- PACKAGE -----")
local pkg = shell("dpkg-query -W -f='${Version}\\n' com.ioscontrol.safarihttp 2>&1")
log("installed_version=" .. tostring(pkg))
if has(pkg, "0.2.0-1") then pass("01 PACKAGE VERSION") else fail("01 PACKAGE VERSION", pkg) end

local files = shell(
    "ls -l /var/jb/usr/lib/TweakInject/IOSControlSafariBootstrap.dylib " ..
    "/var/jb/usr/lib/TweakInject/IOSControlSafariBootstrap.plist " ..
    "/var/jb/usr/lib/TweakInject/IOSControlSafariPayload.dylib " ..
    "/var/jb/usr/lib/TweakInject/IOSControlSafariPayload.plist 2>&1"
)
if has(files, "IOSControlSafariBootstrap.dylib") and has(files, "IOSControlSafariPayload.dylib") then
    pass("02 BOOTSTRAP + PAYLOAD INSTALLED")
else
    fail("02 BOOTSTRAP + PAYLOAD INSTALLED", files)
end

log("")
log("----- START SAFARI -----")
clearPasteboard()
appKill("com.apple.mobilesafari")
sleep(2)
appRun("com.apple.mobilesafari")

local runtime = waitRuntime(8)
local bootstrapOK = runtime ~= nil

if bootstrapOK then
    pass("03 BOOTSTRAP INJECTION")
else
    fail("03 BOOTSTRAP INJECTION", "No " .. PREFIX .. " runtime status appeared")
end

if runtime and has(runtime, "PAYLOAD_DLOPEN_FAIL") then
    fail("04 PAYLOAD DLOPEN", runtime)
elseif runtime and has(runtime, "PAYLOAD_DLSYM_FAIL") then
    fail("04 PAYLOAD SYMBOL", runtime)
elseif runtime and has(runtime, "HTTP_SOCKET_FAIL") then
    fail("05 HTTP SOCKET", runtime)
elseif runtime and has(runtime, "HTTP_BIND_FAIL") then
    fail("05 HTTP BIND", runtime)
elseif runtime and has(runtime, "HTTP_LISTEN_FAIL") then
    fail("05 HTTP LISTEN", runtime)
end

local pingBody, pingStatus, pingData = httpGetJSON("/ping")
local bridgeOK = pingStatus == 200 and type(pingData) == "table" and pingData.ok == true
if bridgeOK then
    pass("05 HTTP PING")
    log("ping=" .. tostring(pingBody))
else
    fail("05 HTTP PING", "status=" .. tostring(pingStatus) .. " body=" .. tostring(pingBody) .. " runtime=" .. tostring(runtime))
end

if bridgeOK then
    log("")
    log("----- REAL SAFARI PAGE -----")
    openURL(TEST_URL)
    sleep(4)

    local body, status, data = httpGetJSON("/status")
    if status == 200 and type(data) == "table" and data.ok == true then
        pass("06 ACTIVE SAFARI PAGE")
        log("status=" .. tostring(body))
    else
        fail("06 ACTIVE SAFARI PAGE", "status=" .. tostring(status) .. " body=" .. tostring(body))
    end

    body, status, data = httpPostText("/eval", "document.title")
    local title = resultValue(data, body)
    if status == 200 and has(tostring(title), "Example Domain") then
        pass("07 JAVASCRIPT document.title")
    else
        fail("07 JAVASCRIPT document.title", "status=" .. tostring(status) .. " result=" .. tostring(title) .. " body=" .. tostring(body))
    end

    body, status, data = httpPostText("/eval", "location.href")
    local href = resultValue(data, body)
    if status == 200 and has(tostring(href), "example.com") then
        pass("08 JAVASCRIPT location.href")
    else
        fail("08 JAVASCRIPT location.href", tostring(body))
    end

    body, status, data = httpPostText("/eval", [[
(() => {
  let e = document.querySelector('#ioscontrol_test');
  if (!e) {
    e = document.createElement('input');
    e.id = 'ioscontrol_test';
    document.body.appendChild(e);
  }
  return 'CREATED';
})()
]])
    if status == 200 and has(tostring(body), "CREATED") then pass("09 CREATE DOM INPUT") else fail("09 CREATE DOM INPUT", body) end

    local fillBody, fillStatus = httpPost(
        BASE .. "/fill",
        jsonEncode({ selector = "#ioscontrol_test", value = "ABC123456" }),
        { ["Content-Type"] = "application/json" }
    )
    local fillData = decode(fillBody)
    if fillStatus == 200 and type(fillData) == "table" and fillData.ok == true then pass("10 FILL DOM INPUT") else fail("10 FILL DOM INPUT", fillBody) end

    body, status, data = httpPostText("/eval", "document.querySelector('#ioscontrol_test').value")
    local value = resultValue(data, body)
    if status == 200 and has(tostring(value), "ABC123456") then pass("11 VERIFY DOM VALUE") else fail("11 VERIFY DOM VALUE", tostring(body)) end

    local repeatOK = true
    for i = 1, 5 do
        body, status, data = httpPostText("/eval", "1+1")
        local v = resultValue(data, body)
        if status ~= 200 or tostring(v) ~= "2" then
            repeatOK = false
            fail("12 REPEATED EVAL x5", "iteration=" .. tostring(i) .. " status=" .. tostring(status) .. " result=" .. tostring(v))
            break
        end
    end
    if repeatOK then pass("12 REPEATED EVAL x5") end
else
    skip("06-12 SAFARI/JS TESTS", "bridge is not listening")
end

log("")
log("===== FINAL SUMMARY =====")
log("passed=" .. tostring(passed))
log("failed=" .. tostring(failed))
log("skipped=" .. tostring(skipped))
log("first_failed_stage=" .. tostring(firstFailed or "NONE"))
log("runtime=" .. tostring(runtime))
if bridgeOK then
    log("RESULT=BRIDGE_RUNNING")
else
    log("RESULT=BRIDGE_NOT_RUNNING")
end
log("===== END =====")

execute("rm -f " .. TMP_PATH)
