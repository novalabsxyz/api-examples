--- Example main loop for the Helium Analog Extension Board
--
-- Requires helium-script 2.x and the ina219.lua library. This main
-- loop takes a voltage and current reading every `SAMPLE_INTERVAL`,
-- and sends voltage on port `v`, current on port `c` to Helium. In
-- semi-hosted mode the script will also print out the readings on the
-- console.
--
-- @script ina219.main
-- @license MIT
-- @copyright 2017 Helium Systems, Inc.
-- @usage
-- # In semi-hosted mode over USB
-- $ helium-script -m main.lua ina219.lua
--
-- # Upload to device over USB
-- $ helium-script -m main.lua ina219.lua

ina219 = require("ina219")

--- Sampling interval (Set to 10 seconds).
SAMPLE_INTERVAL = 10000 -- 10 seconds

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
