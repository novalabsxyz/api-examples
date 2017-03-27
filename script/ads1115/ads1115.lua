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
    COMPARE_AIN0_AIN1  = 0,
    COMPARE_AIN0_AIN3  = 1,
    COMPARE_AIN1_AIN3  = 2,
    COMPARE_AIN2_AIN3  = 3,
    -- comparisons to ground
    COMPARE_AIN0_GND   = 4,
    COMPARE_AIN1_GND   = 5,
    COMPARE_AIN2_GND   = 6,
    COMPARE_AIN3_GND   = 7,

    cfg_bitfield = bitfield {
        comparator_queue = bitrange(0,1), -- how many high/low values before interrupt fires, default disabled
        comparator_latch = bitrange(2), -- if the interrupt latches, 0 is false and the default
        comparator_polarity = bitrange(3), -- interrupt pin high or low when active (0 is active low and the default)
        comparator_mode = bitrange(4), -- comparator in 'traditional' mode, or 'window' mode. 0 the default traditional mode
        data_rate = bitrange(5,7), -- data rate 128 samples/second is the default
        mode = bitrange(8), -- single shot mode (default) or continuous sample mode
        gain = bitrange(9,11), -- gain, default +/-2.048V
        pins = bitrange(12, 14), -- which pins to compare: default A0+ to A1-
        status = bitrange(15) -- 0 device is performing a single shot sample, 1 device is not currently sampling
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

--function ads1115:_cfg_bitfield(r)


function ads1115:set_comparison_pins(pins)
    assert(pins >= 0 and pins <= 7, "invalid pin selection")
    local update = function(r)
        local cfg = bitfield(self.cfg_bitfield, r)
        print(r)
        print(cfg)
        return r
    end

    self.update(self.CONFIG_REG, ">I2", update)
end


local adc = assert(ads1115:new())
adc:set_comparison_pins()
