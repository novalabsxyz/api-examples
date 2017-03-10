lps22hb = require('lps22hb')

SAMPLE_INTERVAL = 60000 -- 1 minute

-- construct the sensor
sensor = assert(lps22hb:new())
-- get current time
local now = he.now()
while true do
    -- take readings
    local pressure = assert(sensor:read_pressure())
    local temperature = assert(sensor:read_temperature())

    -- send temperature as a float "f" on port "t"
    he.send("t", now, "f", temperature)
    -- send pressure as a float "f" on port "p"
    he.send("p", now, "f", pressure)

    print(temperature, pressure)

    -- wait for SAMPLE_INTERVAL time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end
