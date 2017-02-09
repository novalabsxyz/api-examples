-- Development board on-board lps22hb sensor script

i2c = he.i2c

SAMPLE_INTERVAL = 60000 -- 1 minute

lps22hb = {
    DEFAULT_ADDRESS = 0x5C,
    WHO_AM_I        = 0x8F,

    CTRL_REG2         = 0x11,
    CTRL_REG2_ONESHOT = 0x11,

    PRESS_OUT_XL = 0x28,
    TEMP_OUT_L   = 0xAB
}


function lps22hb:new(address)
    address = address or lps22hb.DEFAULT_ADDRESS
    -- We use a simple lua object system as defined
    -- https://www.lua.org/pil/16.1.html
    -- construct the object table
    local o = { address = address }
    -- ensure that the "class" is the metatable
    setmetatable(o, self)
    -- and that the metatable's index function is set
    -- Refer to https://www.lua.org/pil/16.1.html
    self.__index = self
    -- Check that the sensor is connected
    status, reason = o:is_connected()
    if not status then
        return status, reason
    end
    return o
end


function lps22hb:is_connected()
    -- get the WHO_AM_I byte - datasheet section 8, table 16
    local result = self:_get(self.WHO_AM_I, "B")
    -- 0xB1 is the WHO_AM_I value as defined by the datasheet table 16
    if not (result == 0xB1) then
        return false, "could not locate device"
    end
    return true
end


function lps22hb:read_temperature()
    -- perform a oneshot reading and get the temperature
    return self:_oneshot_read(self._temp_get)
end


function lps22hb:read_pressure()
    -- perform a oneshot reading and get the pressure
    return self:_oneshot_read(self._pressure_get)
end


function lps22hb:_get(reg, pack_fmt, convert)
    -- number of bytes to read based on the pack string
    local pack_size = string.packsize(pack_fmt)
    local status, buffer = i2c.txn(i2c.tx(self.address, reg),
                                   i2c.rx(self.address, pack_size))
    if not status then
        return false, "failed to get value from device"
    end
    -- call conversion function if given
    if convert then
        return convert(string.unpack(pack_fmt, buffer))
    end
    return string.unpack(pack_fmt, buffer)
end


function lps22hb:_pressure_get()
    -- get the pressure data - datasheet section 9.18
    -- read 24 bits, the part will conveniently increment the register
    -- to do this in one go to cover PRESS_OUT_L and PRESS_OUT_H
    local result, reason = self:_get(self.PRESS_OUT_XL, "<i3")
    if not result then
        return result, reason
    end

    return result / 40.96 --pascals
end

function lps22hb:_temp_get()
    -- get the temperature data - datasheet section 9.19
    -- read 16 bits, the part will conveniently increment the register
    -- to do this in one go to cover TEMP_OUT_L and TEMP_OUT_H
    local result, reason = self:_get(self.TEMP_OUT_L, "<i2")
    if not result then
        return result, reason
    end

    return result / 100.0 -- C
end

function lps22hb:_oneshot_read(func)
    -- request a one shot reading
    -- datasheet section 9.6
    local status =
        i2c.txn(i2c.tx(self.address, self.CTRL_REG2, self.CTRL_REG2_ONESHOT))
    if not status then
        return false, "failed to start reading"
    end

    -- now loop reading the CTRL_REG2 register
    -- until the oneshot bit clears
    -- datasheet section 9.6 ONE_SHOT documentation
    repeat
        local result, reason = self:_get(self.CTRL_REG2, "B")
        if not result then
            return result, reason
        end
    until (result & 0x01) == 0

    -- call the passed in function to actually get the specific
    return func(self)
end


-- turn on power to V_sw to turn the sensor on
he.power_set(true)
-- construct the sensor
sensor = assert(lps22hb:new())
-- get current time
local now = he.now()
while true do
    -- take readings
    local pressure = assert(sensor:read_pressure())
    local temperature = assert(sensor:read_temperature())

    -- turn power of to save battery
    he.power_set(false)
    -- send temperature as a float "f" on port "t"
    he.send("t", now, "f", temperature)
    -- send pressure as a float "f" on port "p"
    he.send("p", now, "f", pressure)

    -- Un-comment the following line to see results in semi-hosted mode
    -- print(temperature, pressure)

    -- wait for SAMPLE_INTERVAL time
    now = he.wait{time=now + SAMPLE_INTERVAL}
    -- turn switched power V_sw back on
    he.power_set(true)
end
