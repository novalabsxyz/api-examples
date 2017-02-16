-- Development board VCNL4010 proximity sensor script

i2c = he.i2c

SAMPLE_INTERVAL = 60000 -- 1 minute

vcnl4010 = {
    DEFAULT_ADDRESS = 0x13,
    PRODUCTID       = 0x81,


    COMMAND           = 0x80, -- commmand register, table 1
    PROXIMITY_RATE    = 0x82, -- Proximity sample rate, table 3
    LED_CURRENT       = 0x83, -- LED power register, table 4
    AMBIENTPARAMETER  = 0x84,
    AMBIENTDATA       = 0x85,
    PROXIMITYDATA     = 0x87,
    INTERRUPT_CONTROL = 0x89, -- interrupt control, table 10
    LOW_THRESHOLD     = 0x8A,
    HIGH_THRESHOLD    = 0x8C,
    INTERRUPT_STATUS  = 0x8E,

    MEASUREAMBIENT    = 0x10,
    MEASUREPROXIMITY  = 0x08,
    AMBIENTREADY      = 0x40,
    PROXIMITYREADY    = 0x20,

    -- sample rate in measurements/second  See Table 3 in datasheet
    PROXIMITY_RATE_1_95  = 0,
    PROXIMITY_RATE_3_95  = 1,
    PROXIMITY_RATE_7_81  = 2,
    PROXIMITY_RATE_18_62 = 3,
    PROXIMITY_RATE_31_25 = 4,
    PROXIMITY_RATE_62_5  = 5,
    PROXIMITY_RATE_125   = 6,
    PROXIMITY_RATE_250   = 7,

    -- number of consecutive measurements above a threshold before an interrupt  See Table 10 in datasheet
    INTERRUPT_COUNT_1  = 0,
    INTERRUPT_COUNT_2  = 1,
    INTERRUPT_COUNT_4  = 2,
    INTERRUPT_COUNT_8  = 3,
    INTERRUPT_COUNT_16  = 4,
    INTERRUPT_COUNT_32  = 5,
    INTERRUPT_COUNT_64  = 6,
    INTERRUPT_COUNT_128  = 7
}

function vcnl4010:new(address)
    address = address or vcnl4010.DEFAULT_ADDRESS
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

function vcnl4010:is_connected()
    -- read the PRODUCT ID register - datasheet table 2
    local result = self:_get(self.PRODUCTID, "B")
    -- 0x21 is the current Product ID value as defined by the datasheet table 2
    if not (result == 0x21) then
        return false, "could not locate device"
    end
    return true
end

function vcnl4010:_get(reg, pack_fmt, convert)
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

function vcnl4010:set_led_current(current)
    -- set the LED current, table 4
    if current < 0 or current > 20 then
        return false, "VCNL4010 LED current value should be between 0 and 20"
    end
    local status = i2c.txn(i2c.tx(self.address, self.LED_CURRENT, current))
    return status
end

function vcnl4010:get_led_current()
    local status, buffer, reason = i2c.txn(i2c.tx(self.ADDRESS, self.LED_CURRENT), i2c.rx(self.ADDRESS, 1))
    if status == false then
        return false, "failed to get value from device"
    end
    local current = string.unpack("B", buffer)
    return current & 0x3f -- only the low 6 bits store the current
end

function vcnl4010:read_proximity()
    i2c.txn(i2c.tx(self.address, self.COMMAND, self.MEASUREPROXIMITY))
    while true do
        local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.COMMAND), i2c.rx(self.address, 1))
        local reg = string.unpack("B", buffer)
        if reg & self.PROXIMITYREADY then
            local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.PROXIMITYDATA), i2c.rx(self.address, 2))
            if status == false then
                return false, "failed to read register"
            end
            local proximity = string.unpack(">I2", buffer)
            return proximity
        end
        he.wait{time=1 + he.now()}
    end
end

function vcnl4010:read_ambient()
    i2c.txn(i2c.tx(self.address, self.COMMAND, self.MEASUREAMBIENT))
    while true do
        local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.COMMAND), i2c.rx(self.address, 1))
        local reg = string.unpack("B", buffer)
        if reg & self.AMBIENTREADY then
            local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.AMBIENTDATA), i2c.rx(self.address, 2))
            if status == false then
                return false
            end
            local ambient = string.unpack(">I2", buffer)
            return ambient
        end
        he.wait{time=1 + he.now()}
    end
end

function vcnl4010:set_proximity_sample_rate(rate)
    print(rate)

    local status, _, reason = i2c.txn(i2c.tx(self.address, self.PROXIMITY_RATE, rate))
    local status, _, reason = i2c.txn(i2c.tx(self.address, self.COMMAND, 1))
    local status, _, reason = i2c.txn(i2c.tx(self.address, self.COMMAND, 3))
    return status, reason
end

function vcnl4010:configure_interrupt(sample_type, low, high, count)
    if sample_type == "proximity" then
        sample_type = 0
    elseif sample_type == "ambient" then
        sample_type = 1
    else
        return false, "invalid sample type; must be ambient or proximity"
    end

    if count < self.INTERRUPT_COUNT_1 or count > self.INTERRUPT_COUNT_128 then
        return false, "invalid interrupt count"
    end

    -- set low and high thresholds

    local status, _, reason = i2c.txn(i2c.tx(self.address, self.LOW_THRESHOLD, string.pack(">I2", low)))
    if not status then
        return false, "failed to set low threshold register"
    end
    
    status, _, reason = i2c.txn(i2c.tx(self.address, self.HIGH_THRESHOLD, string.pack(">I2", high)))
    if not status then
        return false, "failed to set high threshold register"
    end

    print(count, sample_type)
    print((count << 5) | 2 | sample_type)
    status, _, reason = i2c.txn(i2c.tx(self.address, self.INTERRUPT_CONTROL, (count << 5) | 2 | sample_type))
    if not status then
        return status, "failed to set interrupt control register"
    end

    return true
end

he.interrupt_cfg("int0", "e", 10)
-- construct the sensor
sensor = assert(vcnl4010:new())
assert(sensor:set_led_current(20)) -- max current, 200ma
assert(sensor:set_proximity_sample_rate(sensor.PROXIMITY_RATE_250)) --sample 250 times a second
assert(sensor:configure_interrupt("proximity", 1000, 3000, sensor.INTERRUPT_COUNT_8)) -- if we see eight sensor readings lower than 1000 or higher than 3000, throw interrupt
i2c.txn(i2c.tx(sensor.address, sensor.INTERRUPT_STATUS, 0xff)) -- clear the interrupt register

-- get current time
local now = he.now()
while true do
    now, new_events, events = he.wait{time=now + SAMPLE_INTERVAL}
    if new_events then
        --print("interrupt!")
        status, buffer, reason = i2c.txn(i2c.tx(sensor.address, sensor.PROXIMITYDATA), i2c.rx(sensor.address, 2))
        dist = string.unpack(">I2", buffer)
        print("TOO CLOSE", dist)
        he.send_str("proximity", he.now(), "TOO CLOSE")
        now, new_events, events = he.wait{time=he.now() + 1000} -- chill for a second
        i2c.txn(i2c.tx(sensor.address, sensor.INTERRUPT_STATUS, 0xff)) -- clear the interrupt register
    end
end
