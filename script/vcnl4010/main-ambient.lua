-- Development board VCNL4010 ambient sensor script

vcnl4010 = require("vcnl4010")

SAMPLE_INTERVAL = 60000 -- 1 minute
LOOP = true -- should we enter the sampling loop or go into interactive mode

-- only trigger on falling edges
he.interrupt_cfg("int0", "f", 10)
-- construct the sensor
sensor = assert(vcnl4010:new())
-- max current, 200ma
assert(sensor:set_led_current(20))
--sample ambient light 2 times a second
assert(sensor:set_ambient_sample_rate(sensor.AMBIENT_RATE_2))

-- Set up the ambient light interrupt. Iif we see two light readings
-- lower than 10 or higher than 5000, throw interrupt
assert(sensor:configure_interrupt(true, sensor.AMBIENT_INTERRUPT, 10, 5000,
                                  sensor.INTERRUPT_COUNT_2))

-- clear the interrupt register
i2c.txn(i2c.tx(sensor.address, sensor.INTERRUPT_STATUS, 0xff))

-- get current time
local now = he.now()
while LOOP do
    now, events = he.wait{time=now + SAMPLE_INTERVAL}
    -- read ambient light and transmit to Helium
    local amb = sensor:read_ambient()
    he.send("l", now, "I", amb)
    if events then
        -- figure out what kind of interrupt it was and log it
        status = sensor:get_interrupt_status()
        if status.low_threshold then
            print("TOO DARK", amb)
            he.send("l_int", now, "b", false)
        elseif status.high_threshold then
            print("TOO BRIGHT", amb)
            he.send("l_int", now, "b", true)
        end
        -- chill for a second
        now, events = he.wait{time=he.now() + 5000}
        -- clear the interrupt register
        i2c.txn(i2c.tx(sensor.address, sensor.INTERRUPT_STATUS, 0xff))
    end
end
