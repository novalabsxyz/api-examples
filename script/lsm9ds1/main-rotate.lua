-- This script shows the sensor throwing interrupts for when it
-- detects rotation around the Z-axis

lsm9ds1 = require("lsm9ds1")

sensor = assert(lsm9ds1:new())

assert(sensor.acc:init_gyro(sensor.acc.RATE_14_9,
                            sensor.acc.GYRO_SCALE_245, 0,
                            sensor.acc.AXIS_ALL))

he.interrupt_cfg("int0", "f", 10)

sensor.acc:config_gyro_interrupt(sensor.acc.AXIS_Z, 10000)
sensor.acc:enable_gyro_interrupts()

now = he.now()
while true do
    now, events = he.wait{time=now + 10000}
    if events then
        local gx, gy, gz = sensor.acc:read_gyro()
        if gz > 0 then
            print("turned left")
        else
            print("turned right")
        end
    end
end
