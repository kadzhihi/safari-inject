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
appKill("com.apple.mobilesafari")
sleep(2)
appRun("com.apple.mobilesafari")
sleep(3)

local diagnostic = clipText()
if has(diagnostic, PREFIX) then
    log("bootstrap_diagnostic=" .. tostring(diagnostic))
end

local safariProcess = shell("pgrep -x MobileSafari 2>&1")
if tonumber(safariProcess) then
    pass("03 MOBILESAFARI PROCESS EXISTS")
else
    fail("03 MOBILESAFARI PROCESS EXISTS", safariProcess)
end

local pingBody, pingStatus, pingData = httpGetJSON("/ping")
local bridgeOK = pingStatus == 200 and type(pingData) == "table" and pingData.ok == true
if bridgeOK then
    pass("04 HTTP PING")
    log("ping=" .. tostring(pingBody))
else
    fail("04 HTTP PING", "status=" .. tostring(pingStatus) .. " body=" .. tostring(pingBody))
end

if bridgeOK then
    log("")
    log("----- REAL SAFARI PAGE -----")
    openURL(TEST_URL)
    sleep(4)

    local body, status, data = httpGetJSON("/status")
    if status == 200 and type(data) == "table" and data.ok == true then
        pass("05 ACTIVE SAFARI PAGE")
        log("status=" .. tostring(body))
    else
        fail("05 ACTIVE SAFARI PAGE", "status=" .. tostring(status) .. " body=" .. tostring(body))
    end

    body, status, data = httpPostText("/eval", "document.title")
    local title = resultValue(data, body)
    if status == 200 and has(tostring(title), "Example Domain") then
        pass("06 JAVASCRIPT document.title")
    else
        fail("06 JAVASCRIPT document.title", "status=" .. tostring(status) .. " result=" .. tostring(title) .. " body=" .. tostring(body))
    end

    body, status, data = httpPostText("/eval", "location.href")
    local href = resultValue(data, body)
    if status == 200 and has(tostring(href), "example.com") then
        pass("07 JAVASCRIPT location.href")
    else
        fail("07 JAVASCRIPT location.href", tostring(body))
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
    if status == 200 and has(tostring(body), "CREATED") then pass("08 CREATE DOM INPUT") else fail("08 CREATE DOM INPUT", body) end

    local fillBody, fillStatus = httpPost(
        BASE .. "/fill",
        jsonEncode({ selector = "#ioscontrol_test", value = "ABC123456" }),
        { ["Content-Type"] = "application/json" }
    )
    local fillData = decode(fillBody)
    if fillStatus == 200 and type(fillData) == "table" and fillData.ok == true then pass("09 FILL DOM INPUT") else fail("09 FILL DOM INPUT", fillBody) end

    body, status, data = httpPostText("/eval", "document.querySelector('#ioscontrol_test').value")
    local value = resultValue(data, body)
    if status == 200 and has(tostring(value), "ABC123456") then pass("10 VERIFY DOM VALUE") else fail("10 VERIFY DOM VALUE", tostring(body)) end

    body, status, data = httpPostText("/eval", "(() => {")
    if status == 200 and type(data) == "table" and data.ok == false then
        pass("11 INVALID JAVASCRIPT")
    else
        fail("11 INVALID JAVASCRIPT", "status=" .. tostring(status) .. " body=" .. tostring(body))
    end

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
    skip("05-12 SAFARI/JS TESTS", "bridge is not listening")
end

log("")
log("===== FINAL SUMMARY =====")
log("passed=" .. tostring(passed))
log("failed=" .. tostring(failed))
log("skipped=" .. tostring(skipped))
log("first_failed_stage=" .. tostring(firstFailed or "NONE"))
log("bootstrap_diagnostic=" .. tostring(diagnostic))
if bridgeOK then
    log("RESULT=BRIDGE_RUNNING")
else
    log("RESULT=BRIDGE_NOT_RUNNING")
end
log("===== END =====")

execute("rm -f " .. TMP_PATH)
