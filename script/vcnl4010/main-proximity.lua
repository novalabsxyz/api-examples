-- Development board VCNL4010 proximity sensor script

-- Bring in the library
vcnl4010 = require("vcnl4010")

-- Set sample interval for readings
SAMPLE_INTERVAL = 60000 -- 1 minute
-- Enter sampling loop. Set to false to go into interactive mode
LOOP = true

-- only trigger on falling edges
he.interrupt_cfg { pin = "int0", edge = "falling", debounce = 10 }

-- construct the sensor
sensor = assert(vcnl4010:new())
-- configure max current, 200ma
assert(sensor:set_led_current(20))
-- sample proximity 250 times a second
assert(sensor:set_proximity_sample_rate(sensor.PROXIMITY_RATE_250))

-- Configure the proximity interrupt. If we see eight proximity
-- readings lower than 2500 or higher than 3500, throw interrupt.  If
-- you set this to something lower than 2000 is actually lower than
-- the device reports, you effectively are disabling the lower limit
-- (when something is too far away)
assert(sensor:configure_interrupt(true, sensor.PROXIMITY_INTERRUPT, 2500, 3500,
                                  sensor.INTERRUPT_COUNT_8))
-- clear the interrupt register
i2c.txn(i2c.tx(sensor.address, sensor.INTERRUPT_STATUS, 0xff))

-- get current time
local now = he.now()
while LOOP do
    now, events = he.wait{time=now + SAMPLE_INTERVAL}
    -- read proximity and transmit to Helium
    local prox = sensor:read_proximity()
    he.send("pr", now, "I", prox)
    if events then
        status = sensor:get_interrupt_status()
        -- figure out what kind of interrupt it was and log it
        if status.low_threshold then
            print("TOO FAR", prox)
            he.send("pr_int", now, "b", false)
        elseif status.high_threshold then
            print("TOO CLOSE", prox)
            he.send("pr_int", now, "b", true)
        end
        -- chill for a second
        now, events = he.wait{time=he.now() + 5000}
        -- clear the interrupt register
        i2c.txn(i2c.tx(sensor.address, sensor.INTERRUPT_STATUS, 0xff))
    end
end
