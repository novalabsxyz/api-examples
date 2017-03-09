-- Development board VCNL4010 proximity sensor script

i2c = he.i2c

vcnl4010 = {
    DEFAULT_ADDRESS   = 0x13,
    PRODUCTID         = 0x81,

    COMMAND           = 0x80, -- commmand register, table 1
    PROXIMITY_RATE    = 0x82, -- Proximity sample rate, table 3
    LED_CURRENT       = 0x83, -- LED power register, table 4
    AMBIENT_RATE      = 0x84,
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

    -- sample rate in measurements/second  See Table 5 in datasheet
    AMBIENT_RATE_1       = 0,
    AMBIENT_RATE_2       = 1,
    AMBIENT_RATE_3       = 2,
    AMBIENT_RATE_4       = 3,
    AMBIENT_RATE_5       = 4,
    AMBIENT_RATE_6       = 5,
    AMBIENT_RATE_8       = 6,
    AMBIENT_RATE_10      = 7,

    -- number of consecutive measurements above a threshold before an interrupt
    -- See Table 10 in datasheet
    INTERRUPT_COUNT_1    = 0,
    INTERRUPT_COUNT_2    = 1,
    INTERRUPT_COUNT_4    = 2,
    INTERRUPT_COUNT_8    = 3,
    INTERRUPT_COUNT_16   = 4,
    INTERRUPT_COUNT_32   = 5,
    INTERRUPT_COUNT_64   = 6,
    INTERRUPT_COUNT_128  = 7,

    -- types of interrupt
    PROXIMITY_INTERRUPT = 0,
    AMBIENT_INTERRUPT   = 1,

    -- table 15
    PROXIMITY_READY_INTERRUPT = 8,
    AMBIENT_READY_INTERRUPT   = 4,
    THRESHOLD_LOW_INTERRUPT   = 2,
    THRESHOLD_HIGH_INTERRUPT  = 1
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

function vcnl4010:_update(reg, pack_fmt, update)
    -- read register, apply a function to the result and write it back
    -- number of bytes to read based on the pack string
    assert(update, "you must supply an update function")
    local pack_size = string.packsize(pack_fmt)
    local status, buffer =
        i2c.txn(i2c.tx(self.address, reg), i2c.rx(self.address, pack_size))
    if not status then
        return false, "failed to get value from device"
    end
    -- call update function
    local newvalue = string.unpack(pack_fmt, buffer)
    newvalue = update(newvalue)
    status, buffer =
        i2c.txn(i2c.tx(self.address, reg, string.pack(pack_fmt, newvalue)))
    if not status then
        return false, "unable to set value"
    end
    return newvalue
end

function vcnl4010:set_led_current(current)
    -- set the LED current, table 4
    assert(current >= 0 or current <= 20,
           "VCNL4010 LED current value should be between 0 and 20")
    local status = i2c.txn(i2c.tx(self.address, self.LED_CURRENT, current))
    return status
end

function vcnl4010:get_led_current()
    -- only the low 6 bits store the current
    return self:_get(self.LED_CURRENT, "B", function(r) return r & 0x3f end)
end

function vcnl4010:read_proximity()
    -- if the self-timed mode is enabled, we don't need to do a oneshot
    self:_update(self.COMMAND, "B", function(r)
        if r & 1 == 0 then
            return r | self.MEASUREPROXIMITY
        else
            return r
        end
    end)
    while true do
        local reg = self:_get(self.COMMAND, "B")
        if reg & self.PROXIMITYREADY then
            local res = self:_get(self.PROXIMITYDATA, ">I2")
            return res
        end
        he.wait{time=1 + he.now()}
    end
end


function vcnl4010:read_ambient()
    -- if the self-timed mode is enabled, we don't need to do a oneshot
    self:_update(self.COMMAND, "B", function(r)
        if r & 1 == 0 then
            return r | self.MEASUREAMBIENT
        else
            return r
        end
    end)
    while true do
        local reg = self:_get(self.COMMAND, "B")
        if reg & self.AMBIENTREADY then
            local res = self:_get(self.AMBIENTDATA, ">I2")
            return res
        end
        he.wait{time=1 + he.now()}
    end
end

function vcnl4010:set_ambient_sample_rate(rate)
    local status = self:_update(self.AMBIENT_RATE, "B",
                                function(r) return r | (rate << 4) end)
    if not status then
        return false, "unable to set ambient sample rate"
    end
    -- enable self sampling and ambient interrupts (third and first bits)
    return self:_update(self.COMMAND, "B", function(r) return r | 5 end)
end

function vcnl4010:set_proximity_sample_rate(rate)
    local status, _, reason =
        i2c.txn(i2c.tx(self.address, self.PROXIMITY_RATE, rate))
    if not status then
        return false, "unable to proximity sample rate"
    end
    -- enable self sampling and proximity interrupts (two low bits)
    return self:_update(self.COMMAND, "B", function(r) return r | 3 end)
end

function vcnl4010:get_interrupt_status()
    local int_status = function(r)
        return {
            proximity_ready=(r & self.PROXIMITY_READY_INTERRUPT) > 0,
            ambient_ready=(r & self.AMBIENT_READY_INTERRUPT) > 0,
            low_threshold=(r & self.THRESHOLD_LOW_INTERRUPT) > 0,
            high_threshold=(r & self.THRESHOLD_HIGH_INTERRUPT) > 0
        }
    end
    return self:_get(self.INTERRUPT_STATUS, "B", int_status)
end

function vcnl4010:configure_interrupt(enable, sample_type, low, high, count)
    assert(sample_type == self.PROXIMITY_INTERRUPT or
      sample_type == self.AMBIENT_INTERRUPT,
      "invalid interrupt type; must be AMBIENT_INTERRUPT or PROXIMITY_INTERRUPT")

    assert(count >= self.INTERRUPT_COUNT_1 and
      count <= self.INTERRUPT_COUNT_128,
      "invalid interrupt count")

    -- set low and high thresholds
    local status, _, reason =
        i2c.txn(i2c.tx(self.address, self.LOW_THRESHOLD, string.pack(">I2", low)))
    if not status then
        return false, "failed to set low threshold register"
    end

    status, _, reason =
        i2c.txn(i2c.tx(self.address, self.HIGH_THRESHOLD, string.pack(">I2", high)))
    if not status then
        return false, "failed to set high threshold register"
    end

    -- whether to set the high/low threshold enable bit
    if enable then
        enable = 2
    else
        enable = 0
    end

    -- leave alone bits 3 and 4, they are used seperately
    return self:_update(self.INTERRUPT_CONTROL, "B",
                        function(r) return (count << 5) + (r & 0xC) + enable + sample_type end)
end


return vcnl4010
