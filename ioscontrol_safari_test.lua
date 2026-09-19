-- IOSControl Lua 5.4: definitive MobileSafari ctor + localhost bridge probe.
-- Purpose: separate "tweak did not load" from "tweak loaded but HTTP failed".

local BASE_URL = "http://127.0.0.1:17891"
local CTOR_PREFIX = "IOSCONTROL_SAFARI_CTOR_OK"

local function contains(s, needle)
    return type(s) == "string" and string.find(s, needle, 1, true) ~= nil
end

local function checkPing(label)
    local body, status = httpGet(BASE_URL .. "/ping")
    log(label .. " status=" .. tostring(status) .. " body=" .. tostring(body))
    return status == 200, body, status
end

local function waitForClipboardMarker(seconds)
    local loops = math.floor((seconds or 6) * 2)
    for i = 1, loops do
        local value = clipText()
        if contains(value, CTOR_PREFIX) then
            return value
        end
        sleep(0.5)
    end
    return nil
end

local function waitForPing(seconds)
    local loops = math.floor((seconds or 5) * 2)
    local lastBody = nil
    local lastStatus = nil
    for i = 1, loops do
        local body, status = httpGet(BASE_URL .. "/ping")
        lastBody = body
        lastStatus = status
        if status == 200 then
            return true, body, status
        end
        sleep(0.5)
    end
    return false, lastBody, lastStatus
end

log("===== SAFARI CTOR + BRIDGE DEFINITIVE TEST =====")

-- Do not let an old marker create a false PASS.
clearPasteboard()
sleep(0.3)

log("[01] Kill MobileSafari")
appKill("com.apple.mobilesafari")
sleep(2)

log("[02] Launch MobileSafari explicitly")
appRun("com.apple.mobilesafari")

-- Check ctor proof immediately, before navigation/background timing can interfere.
local ctorMarker = waitForClipboardMarker(6)
local injectionOK = ctorMarker ~= nil

if injectionOK then
    log("[PASS] 03 CTOR / INJECTION")
    log("clipboard=" .. tostring(ctorMarker))
else
    log("[FAIL] 03 CTOR / INJECTION")
    log("clipboard=" .. tostring(clipText()))
end

-- Also test HTTP immediately after launch.
local bridgeOK, pingBody, pingStatus = waitForPing(5)
if bridgeOK then
    log("[PASS] 04 HTTP AFTER APP LAUNCH")
else
    log("[FAIL] 04 HTTP AFTER APP LAUNCH")
end
log("status=" .. tostring(pingStatus))
log("body=" .. tostring(pingBody))

-- Navigation test is secondary. It proves whether opening a real page changes anything.
log("[05] Open example.com")
openURL("https://example.com")
sleep(3)

local navBridgeOK, navBody, navStatus = checkPing("[05] ping-after-navigation")
if navBridgeOK then
    log("[PASS] 05 HTTP AFTER NAVIGATION")
else
    log("[FAIL] 05 HTTP AFTER NAVIGATION")
end

log("===== RESULT =====")
log("INJECTION=" .. (injectionOK and "PASS" or "FAIL"))
log("HTTP_AFTER_LAUNCH=" .. (bridgeOK and "PASS" or "FAIL"))
log("HTTP_AFTER_NAVIGATION=" .. (navBridgeOK and "PASS" or "FAIL"))

if injectionOK and (bridgeOK or navBridgeOK) then
    log("NEXT=BRIDGE_ALIVE_RUN_FULL_JS_TEST")
elseif injectionOK then
    log("NEXT=INJECTION_CONFIRMED_FIX_HTTPSERVER_ONLY")
else
    log("NEXT=INJECTION_NOT_CONFIRMED_CHECK_ELLEKIT_DYLD_LOAD")
end

log("===== END =====")
