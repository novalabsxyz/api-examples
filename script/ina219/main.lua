-- Main loop for taking readings from the Helium Analog Board
-- Requires helium-script 2.x and the ina219.lua library

ina219 = require("ina219")


SAMPLE_INTERVAL = 6000 -- 10 seconds

--construct sensor on default address
sensor = assert(ina219:new())

-- get current time
local now = he.now()
while true do --main loop
    local voltage = assert(sensor:get_voltage()) --V
    local current = assert(sensor:get_current()) --mA

    -- send readings
    he.send("v", now, "f", voltage) --send voltage as a float "f" on on port "v"
    he.send("c", now, "f", current) --send current as a float "f" on port "c"

    -- Un-comment this line to see sampled values in semi-hosted mode
    print(voltage, current)

    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end
