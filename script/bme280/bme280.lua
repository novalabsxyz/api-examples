-- Helium Script for the AdaFruit BME280 breakout board

i2c = he.i2c

SAMPLE_INTERVAL = 10000 -- milliseconds


bme280 = {
    DEFAULT_ADDRESS = 0x77,

    HUMIDITY    = 0xFD,
    TEMPERATURE = 0xFA,
    PRESSURE    = 0xF7,
    ID          = 0xD0,
    CTRL_HUM    = 0xF2,
    CTRL_MEAS   = 0xF4,
    CONFIG      = 0xF5,
    CTRL_MEAS_MODE_SLEEP = 0x00,
    CTRL_MEAS_MODE_FORCED = 0x01,
    CTRL_MEAS_MODE_NORMAL = 0x03,

    OVERSAMPLE_SKIP = 0x00,
    OVERSAMPLE_X1   = 0x01,
    OVERSAMPLE_X2   = 0x02,
    OVERSAMPLE_X4   = 0x03,
    OVERSAMPLE_X8   = 0x04,
    OVERSAMPLE_X16  = 0x05,

    DIG_H1 = 0xA1,
    DIG_H2 = 0xE1,
    DIG_H3 = 0xE3,
    DIG_H4 = 0xE4,
    DIG_H5 = 0xE5,
    DIG_H6 = 0xE7,

    DIG_T1 = 0x88,
    DIG_T2 = 0x8A,
    DIG_T3 = 0x8C,

    DIG_P1 = 0x8E,
    DIG_P2 = 0x90,
    DIG_P3 = 0x92,
    DIG_P4 = 0x94,
    DIG_P5 = 0x96,
    DIG_P6 = 0x98,
    DIG_P7 = 0x9A,
    DIG_P8 = 0x9C,
    DIG_P9 = 0x9E
}

function bme280:new(address)
    address = address or bme280.DEFAULT_ADDRESS
    local o = { address = address }
    setmetatable(o, self)
    self.__index = self
    -- Check that the sensor is connected
    status, reason = o:is_connected()
    if not status then
        return status, reason
    end
    -- Configure sampling rates, by setting humidity first
    -- Datasheet section 7.4.3
    local status, buffer =
        i2c.txn(i2c.tx(address, bme280.CTRL_HUM, bme280.OVERSAMPLE_X16),
                i2c.rx(address, 1))

    if not (status and bme280.OVERSAMPLE_X16 == string.unpack("B", buffer)) then
        return false, "failed to set humidity oversampling"
    end

    -- Set up oversampling for temp and pressure which also commits the above
    -- Datasheet section 7.4.5
    measure_mode =
        bme280.OVERSAMPLE_X16 << 5 -- temp data oversampling
        | bme280.OVERSAMPLE_X16 << 2 -- pressure data oversampling
        | bme280.CTRL_MEAS_MODE_NORMAL
    local status, buffer =
        i2c.txn(i2c.tx(address, bme280.CTRL_MEAS, measure_mode),
                i2c.rx(address, 1))
    if (not status and measure_mode == string.unpack("B", buffer)) then
        return false, "failed to configure oversampling"
    end

    -- And read the calibration data
    local status, result = pcall(function() return o:_get_calibration() end)
    if not status then
        return status, result
    end
    o.calibration = result
    return o
end


function bme280:is_connected()
    status, device_id = self:_get(bme280.ID, "B")
    if not (status and device_id == 0x60) then
        return false, "could not locate device"
    end
    return true
end


function bme280:read_temperature()
    -- read the temperature fragments
    local status, result =
        self:_get(bme280.TEMPERATURE, "BBB",
                  function(t1, t2, t3)
                      return (t1 << 12) | (t2 << 4) | (t3 >> 4) end)
    if not status then
        return status, result
    end

    -- convert based on datasheet
    local cal = self.calibration
    local x1  = (result / 16384 - cal.t1 / 1024) * cal.t2
    local x2  = ((result / 131072 - cal.t1 / 8192)
            * (result / 131072 - cal.t1 / 8192)) * cal.t3
    -- stash calibrated temperature
    local t_fine   = x1 + x2
    return true, t_fine, t_fine / 5120 -- calibration temp, celsius
end


function bme280:read_pressure(t_fine)
    if not t_fine then
        return false, "reading pressure requires a calibration temperature"
    end
    -- read the pressure fragments
    local status, result =
        self:_get(bme280.PRESSURE, "BBB",
                  function(p1, p2, p3)
                      return (p1 << 12) | (p2 << 4) | (p3 >> 4) end)
    if not status then
        return status, result
    end
    -- convert to pressure based on data sheet, calibration data and temperature
    local cal = self.calibration
    local x1  = (t_fine / 2) - 64000
    local x2  = x1 * x1 * cal.p6 / 32768
    x2        = x2 + x1 * cal.p5 * 2
    x2        = (x2 / 4) + (cal.p4 * 65536)
    x1        = (cal.p3 * x1 * x1 / 524288 + cal.p2 * x1) / 524288
    x1        = (1 + (x1 / 32768)) * cal.p1
    local p   = 1048576 - result

    if (x1 ~= 0) then
        p = (p - (x2 / 4096)) * 6250 / x1
    else
        return true, 0
    end

    x1 = cal.p9 * p * p / 2147483648
    x2 = p * cal.p8 / 32768
    p  = p + (x1 + x2 + cal.p7) / 16

    return true, p -- pascals
end


function bme280:read_humidity(t_fine)
    if not t_fine then
        return false, "reading humidity requires a calibration temperature"
    end
    -- read humidity fragments
    local status, result =
        self:_get(bme280.HUMIDITY, "BB",
                  function(h1, h2) return h1 << 8 | h2 end)
    if not status then
        return status, result
    end
    -- convert to humidity based on data sheet, calibration data and temperature
    local cal = self.calibration
    local h = t_fine - 76800
    h = (result - (cal.h4 * 64 + cal.h5 / 16384 * h))
        * (cal.h2 / 65536 * (1 + cal.h6/ 67108864 * h * (1 + cal.h3 / 67108864 * h)))
    h = h * (1 - cal.h1 * h / 524288)

    if h > 100 then
        h = 100
    elseif h < 0 then
        h = 0
    end

    return true, h --percentage
end


function bme280:_get(reg, pack_fmt, convert)
    -- number of bytes to read based on the pack string
    local pack_size = string.packsize(pack_fmt)
    local status, buffer = i2c.txn(i2c.tx(self.address, reg),
                                   i2c.rx(self.address, pack_size))
    if not status then
        return false, "failed to get value from device"
    end
    -- get the values and capture them in a list
    values = {string.unpack(pack_fmt, buffer)}
    -- call conversion function if given
    if convert then
        values = {convert(table.unpack(values))}
    end
    -- return the values as an unpacked tuple
    return true, table.unpack(values)
end


function bme280:_get_calibration()
    --read calibration data from the BME
    local function _get(reg, pack)
        status, value = self:_get(reg, pack)
        if not status then
            error("failed to read calibration data")
        end
        return value
    end
    return {
        --temperature values
        t1 = _get(self.DIG_T1, "I2"),
        t2 = _get(self.DIG_T2, "i2"),
        t3 = _get(self.DIG_T3, "i2"),
        -- humidity values
        h1 = _get(self.DIG_H1, "B"),
        h2 = _get(self.DIG_H2, "i2"),
        h3 = _get(self.DIG_H3, "B"),
        h4 = _get(self.DIG_H4, "BB",
                  function(h1, h2) return (h1 << 4) | (h2 & 0x0F) end),
        h5 = _get(self.DIG_H5, "BB",
                  function(h1, h2) return (h1 << 4) | (h2 >> 4) end),
        h6 = _get(self.DIG_H6, "B"),
        -- pressure values
        p1 = _get(self.DIG_P1, "I2"),
        p2 = _get(self.DIG_P2, "i2"),
        p3 = _get(self.DIG_P3, "i2"),
        p4 = _get(self.DIG_P4, "i2"),
        p5 = _get(self.DIG_P5, "i2"),
        p6 = _get(self.DIG_P6, "i2"),
        p7 = _get(self.DIG_P7, "i2"),
        p8 = _get(self.DIG_P8, "i2"),
        p9 = _get(self.DIG_P9, "i2")
    }
end

-- turn on V_sw
he.power_set(true)
he.wait{time=he.now() + 100}

-- construct sensor on default address
sensor = assert(bme280:new())

-- get current time
local now = he.now()
while true do
    local _, calibration_temp, temperature = assert(sensor:read_temperature())
    local _, humidity = assert(sensor:read_humidity(calibration_temp))
    local _, pressure = assert(sensor:read_pressure(calibration_temp))

    -- turn power off to save battery
    he.power_set(false)

    -- send readings
    he.send("t", now, "f", temperature) --send temperature, as a float "f" on port "t"
    he.send("h", now, "f", humidity) --send humidity as a float "f" on on port "h"
    he.send("p", now, "f", pressure) --send pressure as a flot "f" on port "p"

    -- Un-comment this line to see sampled values in semi-hosted mode
    -- print(temperature, humidity, pressure)

    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
    -- done sleeping, turn power back on
    he.power_set(true)
end
