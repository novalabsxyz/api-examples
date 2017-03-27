---- The 4-20 Smart Sensor Adaptor main script
-- This main loop is what ships with the Helium 4-20 Smart Sensor
-- Adapter.
--
-- This script takes current readings and reports them to Helium using
-- the default `c` port or using the value of the config variable
-- `port`. The reading is linearly interpolated between a configured
-- `LOW` and `HIGH` value. This makes it easy to translate 4-20mA
-- readings to the final value that they represent.
--
-- The sampling interval is 5 minutes by default bu can be
-- overwritten by changing the script or using the configuration
-- feature of Helium by setting the config value `interval`.
--
-- If there is no active current loop this script sends an "open
-- loop"" event on port `ol` with a boolean value `true`.
--
-- @script ina219.main-ssa
-- @license MIT
-- @copyright 2017 Helium Systems, Inc.
-- @usage
-- # In semi-hosted mode over USB
-- $ helium-script -m main-ssa.lua ina219.lua config.lua
--
-- # Upload to device over USB
-- $ helium-script -up -m main-ssa.lua ina219.lua config.lua

config = require("config")
ina219 = require("ina219")

--- get sampling interval (default 5 minutes).
-- Can be configured using the Helium OTA configuration feature using
-- the `interval` key.
SAMPLE_INTERVAL = config.get("interval", 60000 * 5)
--- The low value that a 4mA current reading corresponds with (default 4).
-- Can be configured using the Helium OTA configuration feature using
-- the `low` key.
LOW = config.get("low", 4)
--- The high value that a 20mA current reading corresponds with (default 20).
-- Can be configured using the Helium OTA configuration feature using
-- the `high` key.
HIGH = config.get("high", 20)
--- the port to send current readings on (defaults `c`).
-- The configuration system currently only supports numbers and
-- booleans we support single character port names using their integer
-- value. This can be configured using the Helium OTA configuration
-- feature using the `interval` key.
PORT = config.get("port", 99) -- port "c"

function interpolate(value, low, high)
    return ((value - 4) * (high - low) / 16) + low
end

--construct sensor
sensor = assert(ina219:new())

-- get current time
local now = he.now()
--- main loop
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
