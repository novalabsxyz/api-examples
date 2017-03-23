-- This script shows the sensor throwing interrupts for when it
-- detects rotation around the Z-axis
-- NOTE: This script requires helium-script 2.x

lsm9ds1 = require("lsm9ds1")

sensor = assert(lsm9ds1:new())

assert(sensor.acc:init_gyro(sensor.acc.RATE_952,
                            sensor.acc.GYRO_SCALE_245, 3,
                            sensor.acc.AXIS_ALL))
assert(sensor.acc:init_accel(sensor.acc.RATE_952,
                            sensor.acc.ACCEL_SCALE_4G, 3,
                            sensor.acc.AXIS_ALL))

assert(sensor.mag:init(sensor.mag.MODE_CONTINUOUS,
                       true, sensor.mag.RATE_80,
                       sensor.mag.SCALE_16_GAUSS,
                       3, 3))


now = he.now()
while true do
    now, events = he.wait{time=now + 10}
    local ax, ay, az = sensor.acc:read_accel()
    local gx, gy, gz = sensor.acc:read_gyro()
    local mx, my, mz = sensor.mag:read()
    local temp = sensor.acc:read_temp()
    print(ax, ay, az, gx, gy, gz, mx, my, mz, temp, 0)
end
