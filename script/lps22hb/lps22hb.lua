-- Development board on-board lps22hb sensor script

i2c = he.i2c

SAMPLE_INTERVAL = 5000 -- 1 minute

lps22hb = {
    DEFAULT_ADDRESS = 0x5C,
    ID              = 0x8F,

    CTRL_REG2         = 0x11,
    CTRL_REG2_ONESHOT = 0x11,

    PRESS_OUT_XL = 0x28,
    TEMP_OUT_L   = 0xAB
}


function lps22hb:new(address)
    address = address or lps22hb.DEFAULT_ADDRESS
    local o = { address = address }
    setmetatable(o, self)
    self.__index = self
    -- Check that the sensor is connected
    status, reason = o:is_connected()
    if not status then
        return status, reason
    end
    return o
end


function lps22hb:is_connected()
    local status, result = self:_get(self.ID, "B")
    if not (status and result == 0xB1) then
        return false, "could not locate device"
    end
    return true
end


function lps22hb:read_temperature()
    return self:_oneshot_read(self._temp_get)
end


function lps22hb:read_pressure()
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
    -- get the values and capture them in a list
    values = {string.unpack(pack_fmt, buffer)}
    -- call conversion function if given
    if convert then
        values = {convert(table.unpack(values))}
    end
    -- return the values as an unpacked tuple
    return true, table.unpack(values)
end


function lps22hb:_pressure_get()
    local status, result = self:_get(self.PRESS_OUT_XL, "i3")
    if not status then
        return status, result
    end

    return true, result / 4096 --pascals
end

function lps22hb:_temp_get()
    local status, result = self:_get(self.TEMP_OUT_L, "<i2")
    if not status then
        return status, result
    end

    return true, result / 100.0 -- C
end

function lps22hb:_oneshot_read(func)
    -- request one shot reading
    local status =
        i2c.txn(i2c.tx(self.address, self.CTRL_REG2, self.CTRL_REG2_ONESHOT))
    if not status then
        return false, "failed to start reading"
    end

    -- now loop reading the result register waiting for a response
    repeat
        local status, result = self:_get(self.CTRL_REG2, "B")
        if not status then
            return status, result
        end
    until (result & 0x01) == 0

    return func(self)
end


-- Turn on power
he.power_set(true)

sensor = assert(lps22hb:new())

local now = he.now()
while true do
    local _, pressure = assert(sensor:read_pressure())
    local _, temperature = assert(sensor:read_temperature())

    he.power_set(false)
    he.send("t", now, "f", temperature)
    he.send("p", now, "f", pressure)

    -- Un-comment the following line to see results in semi-hosted mode
    -- print(temperature, pressure)

    now = he.wait{time=now + SAMPLE_INTERVAL}
    he.power_set(true)
end
