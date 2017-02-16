-- Helium script for the PCF8593, a Real Time Clock/Pulse counter
-- This script only uses the PCF8593 in event counter mode

i2c = he.i2c

pcf8593 = {
    DEFAULT_ADDRESS   = 81,
    CONTROL_STATUS    = 0x0,
    COUNTER_DATA      = 0x1
}

function pcf8593:new(address)
    address = address or pcf8593.DEFAULT_ADDRESS
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

function pcf8593:is_connected()
    -- just make sure we can talk to the device
    local result = self:_get(self.CONTROL_STATUS, "B")
    return result
end

function pcf8593:_get(reg, pack_fmt, convert)
    -- number of bytes to read based on the pack string
    local pack_size = string.packsize(pack_fmt)
    local status, buffer, reason = i2c.txn(i2c.tx(self.address, reg),
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

function pcf8593:event_counter_mode()
    i2c.txn(i2c.tx(self.address, self.CONTROL_STATUS, 32))
end

function pcf8593:read_counter()
    -- the PCF8593 stores its counter in Binary Coded Decimal
    -- https://en.wikipedia.org/wiki/Binary-coded_decimal
    -- We turn it into a real number instead
    return self:_get(self.COUNTER_DATA, "<I3", function(a)
        return (a & 0xf) +
               ((a >> 4) & 0xf) * 10 +
               ((a >> 8) & 0xf) * 100 +
               ((a >> 12) & 0xf) * 1000 +
               ((a >> 16) & 0xf) * 10000 +
               ((a >> 20) & 0xf) * 100000
    end)
end

function pcf8593:set_counter(value)
    -- Turn the desired counter value into Binary Coded Decimal
    -- and store it to the register
    local bcd = (value % 10) +
                ((math.floor(value / 10) % 10) << 4) +
                ((math.floor(value / 100) % 10) << 8) +
                ((math.floor(value / 1000) % 10) << 12) +
                ((math.floor(value / 10000) % 10) << 16) +
                ((math.floor(value / 100000) % 10) << 20)
    i2c.txn(i2c.tx(self.address, self.COUNTER_DATA, string.pack("<I3", bcd)))
end

-- the RTC needs to be 'woken' (section 7.11), we abuse Vsw to do this for now
-- you can also solder a resistor and capacitor as specified in the datasheet
he.power_set(true)
he.wait{time=10 + he.now()}
he.power_set(false)
he.wait{time=10 + he.now()}
he.power_set(true)

clock = assert(pcf8593:new())
local count = 0
local oldcount = 0
local freq = 0
clock:event_counter_mode() -- put the PCF8593 into event counter mode
clock:set_counter(0) -- reset the counter to 0, could be in unknown state

now = he.now() --set current time

while true do --main loop
    -- sample every 1 second so we get Hertz
    now, new_events, events = he.wait{time=1000 + now}
    count = clock:read_counter()
    if count < oldcount then
        -- counter wrapped since last read, counter will wrap after 999,999 events
        freq = (count + 1000000) - oldcount
    else
        freq = count - oldcount
    end
    oldcount = count
    -- send as port 'freq' as an integer
    he.send("freq", now, "i", freq) -- number of events counted in this second, in Hz
end
