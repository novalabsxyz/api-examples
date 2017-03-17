config = require("config")
ina219 = require("ina219")

-- get sampling interval, default to 5 minutes
SAMPLE_INTERVAL = config.get("interval", 60000 * 5)
LOW = config.get("low", 4)
HIGH = config.get("high", 20)
-- config currently only supports numbers and booleans
-- we support single character port names using their integer value
PORT = config.get("port", 99) -- port "c"

function interpolate(value, low, high)
    return ((value - 4) * (high - low) / 16) + low
end

--construct sensor
sensor = assert(ina219:new())

-- get current time
local now = he.now()
-- main loop
while true do
    -- take a current reading
    local current = assert(sensor:get_current()) --mA
    -- check for an open loop
    if current <= 0 then
        he.send("ol", now, "b", true)
        print("open loop")
    else
        -- interpolate between configured low and high values
        local current_adjusted = interpolate(current, LOW, HIGH)
        -- send current as a float "f" on port "c"
        he.send(string.char(PORT), now, "f", current_adjusted)
        -- print measured and interpolated value
        -- visible in semi-hosted mode
        print(current, current_adjusted)
    end
    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end
