-- Helum script for the ADS1115, a 16 bit ADC

i2c = he.i2c
local bf = require("bitfield")
bitfield = bf.bitfield
bitrange = bf.bitrange

ads1115 = {
    DEFAULT_ADDRESS = 0x48,

    CONVERSION_REG     = 0,
    CONFIG_REG         = 1,
    LOW_THRESHOLD_REG  = 2,
    HIGH_THRESHOLD_REG = 3,

    -- set pins to compare, single or double ended
    -- positive pin comes first, when doing a differential compare

    -- differential compares
    COMPARE_AIN0_AIN1  = 0, -- default
    COMPARE_AIN0_AIN3  = 1,
    COMPARE_AIN1_AIN3  = 2,
    COMPARE_AIN2_AIN3  = 3,
    -- comparisons to ground
    COMPARE_AIN0_GND   = 4,
    COMPARE_AIN1_GND   = 5,
    COMPARE_AIN2_GND   = 6,
    COMPARE_AIN3_GND   = 7,

    GAIN_0_6 = 0, -- two thirds gain +/- 6.144V
    GAIN_1   = 1, -- +/- 4.096V
    GAIN_2   = 2, -- default +/- 2.048V
    GAIN_4   = 3, -- +/- 1.024V
    GAIN_8   = 4, -- +/- 0.512V
    GAIN_16  = 5, -- +/- 0.256V

    -- in continuous mode, how many samples/second
    RATE_8SPS   = 0,
    RATE_16SPS  = 1,
    RATE_32SPS  = 2,
    RATE_64SPS  = 3,
    RATE_128SPS = 4, -- default
    RATE_250SPS = 5,
    RATE_475SPS = 6,
    RATE_860SPS = 7,

    --- how many successive samples over/under threshold before comparator interrupts
    ASSERT_ONE  = 0,
    ASSERT_TWO  = 1,
    ASSERT_FOUR = 2,
    ASSERT_NONE = 3, -- default

    cfg_bitfield = bitfield {
        comparator_queue = bitrange(1,2), -- how many high/low values before interrupt fires, default disabled
        comparator_latch = bitrange(3), -- if the interrupt latches, 0 is false and the default
        comparator_polarity = bitrange(4), -- interrupt pin high or low when active (0 is active low and the default)
        comparator_mode = bitrange(5), -- comparator in 'traditional' mode, or 'window' mode. 0 the default traditional mode
        data_rate = bitrange(6,8), -- data rate 128 samples/second is the default
        mode = bitrange(9), -- single shot mode (default) or continuous sample mode
        gain = bitrange(10,12), -- gain, default +/-2.048V
        pins = bitrange(13, 15), -- which pins to compare: default A0+ to A1-
        status = bitrange(16) -- 0 device is performing a single shot sample, 1 device is not currently sampling
                              -- set this field to 1 to perform a single shot sample
    }
}

function ads1115:new(address)
    address = address or ads1115.DEFAULT_ADDRESS
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

function ads1115:is_connected()
    -- just try to read the conversion register, why not?
    local result = self:_get(self.CONVERSION_REG, "B")
    if not result then
        return false, "could not locate device"
    end
    return true
end

function ads1115:_get(reg, pack_fmt, convert)
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

function ads1115:_update(reg, pack_fmt, update)
    -- read register, apply a function to the result and write it back
    -- number of bytes to read based on the pack string
    if not update then
        return false, "you must supply an update function"
    end
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

function ads1115:_update_cfg(key, value)
    local update = function(r)
        local cfg = bitfield(self.cfg_bitfield, r)
	cfg[key] = value
        return cfg[bitrange("unsigned", 1, 16)]
    end

    return self:_update(self.CONFIG_REG, ">I2", update)
end

function ads1115:set_comparison_pins(pins)
    assert(pins >= 0 and pins <= 7, "invalid pin selection")
    return self:_update_cfg("pins", pins)
end

function ads1115:set_gain(gain)
    assert(gain >= 0 and gain <= 5, "invalid sample rate")
    return self:_update_cfg("gain", gain)
end

function ads1115:set_rate(rate)
    assert(rate >= 0 and rate <= 7, "invalid gain level")
    return self:_update_cfg("data_rate", rate)
end

function ads1115:set_continuous(val)
    return self:_update_cfg("mode", val == false)
end

function ads1115:set_comparator_queue(count)
    assert(count >= 0 and count <= 3, "invalid comparator queue count")
    return self:_update_cfg("comparator_queue", count)
end

function ads1115:set_comparator_latch(val)
    return self:_update_cfg("comparator_latch", val)
end

function ads1115:set_comparator_window_mode(val)
    return self:_update_cfg("comparator_mode", val)
end

function ads1115:read()
    return self:_get(self.CONVERSION_REG, ">i2")
end

function ads1115:get_config()
    return self:_get(self.CONFIG_REG, ">I2",
        function(r)
            return bitfield(self.cfg_bitfield, r)
        end)
end

function ads1115:oneshot_sample()
    self:_update_cfg("status", true)
    local cfg = self:get_config()
    while not cfg.status do
        -- TODO fix this once we can avoid flushing interrupt events in waits
        he.wait{time=he.now()+10}
    end
    return self:read()
end

function ads1115:set_high_threshold(value)
     local status = i2c.txn(i2c.tx(self.address, self.HIGH_THRESHOLD_REG, string.pack(">i2", value)))
     if not status then
        return false, "unable to set high threshold value"
    end
    return true
end

function ads1115:set_low_threshold(value)
     local status = i2c.txn(i2c.tx(self.address, self.LOW_THRESHOLD_REG, string.pack(">i2", value)))
     if not status then
        return false, "unable to set high threshold value"
    end
    return true
end

return ads1115
