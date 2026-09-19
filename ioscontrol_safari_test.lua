-- IOSControl Lua 5.4 diagnostic for MobileSafari injection and the localhost bridge.

local BASE_URL = "http://127.0.0.1:17891"

log("===== SAFARI INJECTION + BRIDGE TEST =====")

execute("rm -f /var/mobile/Library/IOSControl/Scripts/safari_ctor_marker.txt")
appKill("com.apple.mobilesafari")
sleep(1)
openURL("https://example.com")
sleep(5)

local marker = readFile("safari_ctor_marker.txt")
local injectionOK = type(marker) == "string" and string.find(marker, "IOSCONTROL_SAFARI_CTOR_OK", 1, true) ~= nil
if injectionOK then
    log("[PASS] 01 INJECTION")
    log(marker)
else
    log("[FAIL] 01 INJECTION")
    log("marker=" .. tostring(marker))
end

local body, status = httpGet(BASE_URL .. "/ping")
local bridgeOK = status == 200
if bridgeOK then
    log("[PASS] 02 HTTP BRIDGE")
else
    log("[FAIL] 02 HTTP BRIDGE")
end
log("status=" .. tostring(status))
log("body=" .. tostring(body))

log("===== RESULT =====")
log("INJECTION=" .. (injectionOK and "PASS" or "FAIL"))
log("HTTP=" .. (bridgeOK and "PASS" or "FAIL"))
if not injectionOK then
    log("NEXT=FIX_TWEAK_INJECTION")
elseif not bridgeOK then
    log("NEXT=FIX_HTTP_SERVER_ONLY")
else
    log("NEXT=TEST_PAGE_AND_JAVASCRIPT")
end

execute("rm -f /var/mobile/Library/IOSControl/Scripts/safari_ctor_marker.txt")
