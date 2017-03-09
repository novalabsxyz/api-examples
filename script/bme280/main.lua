bme280 = require("bme280")

SAMPLE_INTERVAL = 60000 -- 1 minute

-- construct sensor on default address
sensor = assert(bme280:new())

-- get current time
local now = he.now()
while true do
    local calibration_temp, temperature = assert(sensor:read_temperature())
    local humidity = assert(sensor:read_humidity(calibration_temp))
    local pressure = assert(sensor:read_pressure(calibration_temp))

    --send temperature, as a float "f" on port "t"
    he.send("t", now, "f", temperature)
    --send humidity as a float "f" on on port "h"
    he.send("h", now, "f", humidity)
    --send pressure as a flot "f" on port "p"
    he.send("p", now, "f", pressure)

    -- Print sampled values. These will show when running in
    -- semi-hosted mode
    print(temperature, humidity, pressure)

    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end
