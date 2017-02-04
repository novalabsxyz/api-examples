-- Helium Script for the AdaFruit BME280 breakout board
-- Datasheet: https://ae-bst.resource.bosch.com/media/_tech/media/datasheets/BST-BME280_DS001-11.pdf
i2c = he.i2c

BME280_ADDR = 0x77
SAMPLE_INTERVAL = 60000 -- milliseconds

BME280_HUMIDITY    = 0xFD
BME280_TEMPERATURE = 0xFA
BME280_PRESSURE    = 0xF7

BME280_DIG_H1 = 0xA1
BME280_DIG_H2 = 0xE1
BME280_DIG_H3 = 0xE3
BME280_DIG_H4 = 0xE4
BME280_DIG_H5 = 0xE5
BME280_DIG_H6 = 0xE7

BME280_DIG_T1 = 0x88
BME280_DIG_T2 = 0x8A
BME280_DIG_T3 = 0x8C

BME280_DIG_P1 = 0x8E
BME280_DIG_P2 = 0x90
BME280_DIG_P3 = 0x92
BME280_DIG_P4 = 0x94
BME280_DIG_P5 = 0x96
BME280_DIG_P6 = 0x98
BME280_DIG_P7 = 0x9A
BME280_DIG_P8 = 0x9C
BME280_DIG_P9 = 0x9E

-- Assert that sensor is available
function check_for_sensor()
    local status, buffer, reason =
        i2c.txn(i2c.tx(BME280_ADDR, 0xF2, 0x05), i2c.rx(BME280_ADDR, 1))

    assert(status and #buffer >= 1 and 0x05 == string.unpack("B", buffer))

    local status, buffer, reason =
        i2c.txn(i2c.tx(BME280_ADDR, 0xF4, 0xB7), i2c.rx(BME280_ADDR, 1))
    assert(status and #buffer >= 1 and 0xB7 == string.unpack("B", buffer))
end

-- Convenience function to get bme data from a given address
local function bme_get(reg, pack_fmt, convert)
    local pack_size = string.packsize(pack_fmt) -- number of bytes to read
    local _, buffer = i2c.txn(i2c.tx(BME280_ADDR, reg),
                              i2c.rx(BME280_ADDR, pack_size))
    -- get the values and capture them in a list
    values = {string.unpack(pack_fmt, buffer)}
    -- call conversion function if given
    if convert then
        values = {convert(table.unpack(values))}
    end
    -- return the values as an unpacked tuple
    return table.unpack(values)
end

function read_temperature(cal)
    -- read the temperature fragments
    local temp = bme_get(BME280_TEMPERATURE, "BBB",
                         function(t1, t2, t3)
                             return (t1 << 12) | (t2 << 4) | (t3 >> 4) end)

    -- convert based on datasheet
    local x1 = (temp / 16384 - cal.t1 / 1024) * cal.t2
    local x2 = ((temp / 131072 - cal.t1 / 8192)
            * (temp / 131072 - cal.t1 / 8192)) * cal.t3
    -- calibrated temperature
    local t_fine   = x1 + x2
    return t_fine, t_fine / 5120 -- calibrated temperature, celsius
end

function read_pressure(cal, t_fine)
    -- read the pressure fragments
    local pres = bme_get(BME280_PRESSURE, "BBB",
                         function(p1, p2, p3)
                             return (p1 << 12) | (p2 << 4) | (p3 >> 4) end)
    -- convert to pressure based on data sheet, calibration data and temperature
    local x1 = (t_fine / 2) - 64000
    local x2 = x1 * x1 * cal.p6 / 32768
    x2       = x2 + x1 * cal.p5 * 2
    x2       = (x2 / 4) + (cal.p4 * 65536)
    x1       = (cal.p3 * x1 * x1 / 524288 + cal.p2 * x1) / 524288
    x1       = (1 + (x1 / 32768)) * cal.p1
    local p  = 1048576 - pres

    if (x1 ~= 0) then
        p = (p - (x2 / 4096)) * 6250 / x1
    else
        return 0
    end

    x1 = cal.p9 * p * p / 2147483648
    x2 = p * cal.p8 / 32768
    p  = p + (x1 + x2 + cal.p7) / 16

    return p -- pascals
end

function read_humidity(cal, t_fine)
    -- read humidity fragments
    local humidity = bme_get(BME280_HUMIDITY, "BB",
                             function(h1, h2) return h1 << 8 | h2 end)
    -- convert to humidity based on data sheet, calibration data and temperature
    local h = t_fine - 76800
    h = (humidity - (cal.h4 * 64 + cal.h5 / 16384 * h))
        * (cal.h2 / 65536 * (1 + cal.h6/ 67108864 * h * (1 + cal.h3 / 67108864 * h)))
    h = h * (1 - cal.h1 * h / 524288)

    if h > 100 then
        h = 100
    elseif h < 0 then
        h = 0
    end

    return h --percentage
end

function read_calibration()
    --read calibration data from the BME
    return {
        --temperature values
        t1 = bme_get(BME280_DIG_T1, "I2"),
        t2 = bme_get(BME280_DIG_T2, "i2"),
        t3 = bme_get(BME280_DIG_T3, "i2"),

        -- humidity values
        h1 = bme_get(BME280_DIG_H1, "B"),
        h2 = bme_get(BME280_DIG_H2, "i2"),
        h3 = bme_get(BME280_DIG_H3, "B"),
        h4 = bme_get(BME280_DIG_H4, "BB",
                     function(h1, h2) return (h1 << 4) | (h2 & 0x0F) end),
        h5 = bme_get(BME280_DIG_H5, "BB",
                     function(h1, h2) return (h1 << 4) | (h2 >> 4) end),
        h6 = bme_get(BME280_DIG_H6, "B"),

        -- pressure values
        p1 = bme_get(BME280_DIG_P1, "I2"),
        p2 = bme_get(BME280_DIG_P2, "i2"),
        p3 = bme_get(BME280_DIG_P3, "i2"),
        p4 = bme_get(BME280_DIG_P4, "i2"),
        p5 = bme_get(BME280_DIG_P5, "i2"),
        p6 = bme_get(BME280_DIG_P6, "i2"),
        p7 = bme_get(BME280_DIG_P7, "i2"),
        p8 = bme_get(BME280_DIG_P8, "i2"),
        p9 = bme_get(BME280_DIG_P9, "i2")
    }
end

-- turn on V_sw
he.power_set(true)
-- check sensor is connected
check_for_sensor()
-- read bme sensor calibration data once
cal = read_calibration()

--get current time
local now = he.now()
while true do
    local temp_cal, temperature = read_temperature(cal)
    local humidity = read_humidity(cal, temp_cal)
    local pressure = read_pressure(cal, temp_cal)
    -- turn power off to save battery
    he.power_set(false)

    -- send readings
    he.send("t", now, "f", temperature) --send temperature, as a float "f" on port "t"
    he.send("h", now, "f", humidity) --send humidity as a float "f" on on port "h"
    he.send("p", now, "f", pressure) --send pressure as a flot "f" on port "p"

    -- Uncomment this line to see sampled values in semi-hosted mode
    -- print(temperature, humidity, pressure)

    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
    -- done sleeping, turn power back on
    he.power_set(true)
end
