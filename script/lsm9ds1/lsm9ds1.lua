-- Helium library for LSM9DS1 9axis accelerometer/magnetometer/gyroscope

i2c = he.i2c

lsm9ds1_acc = {
    DEFAULT_ADDRESS = 0x6B, -- alternative is 0x6A

    INT1_CTRL = 0x0C,
    WHO_AM_I = 0x0f,
    OUT_TEMP = 0x15, -- section 7.17
    CTRL_REG1_G = 0x10,
    CTRL_REG4 = 0x1E,
    CTRL_REG5_XL = 0x1F,
    CTRL_REG6_XL = 0x20,

    OUT_X_G = 0x18,
    OUT_Y_G = 0x1A,
    OUT_Z_G = 0x1C,

    STATUS_REG = 0x27,

    OUT_X_XL = 0x28,
    OUT_Y_XL = 0x2A,
    OUT_Z_XL = 0x2C,

    -- table 89
    INT_GEN_CFG_G = 0x30,

    -- table 90
    INT_GEN_THS_X_G = 0x31,
    INT_GEN_THS_Y_G = 0x33,
    INT_GEN_THS_Z_G = 0x35,

    -- table 45
    GYRO_SCALE_245 = 0x00,
    GYRO_SCALE_500 = 0x01,
    GYRO_SCALE_2000 = 0x03,

    -- table 46 & table 68
    RATE_OFF = 0x00,
    RATE_14_9 = 0x01,
    RATE_59_5 = 0x02,
    RATE_119 = 0x03,
    RATE_238 = 0x04,
    RATE_476 = 0x05,
    RATE_952 = 0x06,

    AXIS_X = 0x01,
    AXIS_Y = 0x02,
    AXIS_Z = 0x04,
    AXIS_ALL = 0x07,

    ACCEL_SCALE_2G = 0x00,
    ACCEL_SCALE_16G = 0x01,
    ACCEL_SCALE_4G = 0x02,
    ACCEL_SCALE_8G = 0x03,
}


lsm9ds1_mag = {
    DEFAULT_ADDRESS = 0x1e, -- alternative is 0x1c
    OFFSET_X_REG_L_M = 0x05,
    WHO_AM_I = 0x0F,

    CTRL_REG1_M = 0x20,
    CTRL_REG2_M = 0x21,
    CTRL_REG3_M = 0x22,
    CTRL_REG4_M = 0x23,
    OUT_X_L_M = 0x28,

    -- table 111
    RATE_0_625 = 0x00,
    RATE_1_25 = 0x01,
    RATE_2_5  = 0x02,
    RATE_5  = 0x03,
    RATE_10 = 0x04,
    RATE_20 = 0x05,
    RATE_40 = 0x06,
    RATE_80 = 0x07,

    -- table 114
    SCALE_4_GAUSS = 0x00,
    SCALE_8_GAUSS = 0x01,
    SCALE_12_GAUSS = 0x02,
    SCALE_16_GAUSS = 0x03,

    -- table 110
    PERF_LOW = 0x00,
    PERF_MEDIUM = 0x01,
    PERF_HIGH = 0x02,
    PERF_ULTRA = 0x03,

    --table 117
    MODE_CONTINUOUS = 0x00,
    MODE_SINGLE = 0x01,
    MODE_OFF = 0x02,
}

lsm9ds1 = {}


function lsm9ds1_acc:new(address)
    address = address or lsm9ds1_acc.DEFAULT_ADDRESS
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

function lsm9ds1_acc:is_connected()
    -- read the WHO_AM_I register - datasheet section 7.11
    local result = self:_get(self.WHO_AM_I, "B")
    -- 0x21 is the current Product ID value as defined by the datasheet table 2
    if not (result == 0x68) then
        return false, "could not locate device"
    end
    return true
end

function lsm9ds1_acc:read_temp()
    return self:_get(self.OUT_TEMP, "<i2")
end

function lsm9ds1_acc:init_gyro(rate, scale, bandwidth, axes)
    assert(rate >= self.RATE_OFF and rate <= self.RATE_952,
           "invalid gyroscope data rate")
    assert(scale == self.GYRO_SCALE_245 or scale == self.GYRO_SCALE_500 or scale == self.GYRO_SCALE_2000,
          "invalid gyroscope scale")
    assert(bandwidth >=0 and bandwidth <= 3,
           "invalid gyroscope bandwidth: 0-3")
    assert(axes >= 0 and axes <= 7,
           "invalid gyroscope axes")

    local status = i2c.txn(i2c.tx(self.address, self.CTRL_REG1_G,
                                  (rate << 5) | (scale << 3) | bandwidth))
    if not status then
        return false, "unable to configure gyroscope rate, scale and bandwidth"
    end

    status = i2c.txn(i2c.tx(self.address, self.CTRL_REG4, axes << 3))
    if not status then
        return false, "unable to configure gyroscope axes"
    end
    return true
end

function lsm9ds1_acc:read_gyro()
    local x, y, z = self:_get(self.OUT_X_G, "<i2i2i2")
    --local y = self:_get(self.OUT_Y_XL, "<i2")
    --local z = self:_get(self.OUT_Z_XL, "<i2")
    return x, y, z
end

function lsm9ds1_acc:set_gyro_interrupt_threshold(axis, threshold)
    assert(threshold < 16384 and threshold > -16385,
           "threshold value out of range")
    assert(axis == self.AXIS_X or axis == self.AXIS_Y or axis == self.AXIS_Z,
           "invalid axis")

    local reg = self.INT_GEN_THS_X_G
    if axis == self.AXIS_Y then
        reg = self.INT_GEN_THS_Y_G
    elseif axis == self.AXIS_Z then
        reg = self.INT_GEN_THS_Z_G
    end

    -- ok, put the threshold into the value
    -- the thresholds are stored as 15 bit two's complement, so we have to
    -- do some magic here
    local a, b = string.byte(string.pack(">i2", threshold), 1, 2)
    return self:_update(reg, ">i2",
                        function(r) return (r & 0x8000) | ((a & 0x7f) << 8) | b end)
end


function lsm9ds1_acc:get_gyro_interrupt_threshold(axis)
    assert(axis == self.AXIS_X or axis == self.AXIS_Y or axis == self.AXIS_Z,
           "invalid axis")

    local reg = self.INT_GEN_THS_X_G
    if axis == self.AXIS_Y then
        reg = self.INT_GEN_THS_Y_G
    elseif axis == self.AXIS_Z then
        reg = self.INT_GEN_THS_Z_G
    end
    -- even though it is two's complement, we need to pretend it is unsigned for now
    -- because the high bit is not actually part of the number, it is a 15 bit number
    return self:_get(reg, ">I2", function(r)
        -- 15 bit two's complement
        -- chop off the high bit, it is a troll
        r = r & 0x7fff
        if r & 0x4000 > 0 then
            -- high bit is 1, this is a negative number
            -- set the highest bit to 1
            r = r | 0x8000
            r = string.unpack(">i2", string.pack(">I2", r))
            return r
        else
            return r
        end
    end)
end

function lsm9ds1_acc:config_gyro_interrupt(axis, threshold, low)
    assert(axis == self.AXIS_X or axis == self.AXIS_Y or axis == self.AXIS_Z,
           "invalid axis")
    local result = self:set_gyro_interrupt_threshold(axis, threshold)
    if not result then
        return false, "unable to set interrupt threshold"
    end

    -- This relies on the definition of AXIS
    int_cfg = 1 << axis
    if not low then
        int_cfg = int_cfg << 1
    end
    return self:_update(self.INT_GEN_CFG_G, "B", function(r) return r | int_cfg end)
end

function lsm9ds1_acc:enable_gyro_interrupts()
    return self:_update(self.INT1_CTRL, "B", function(r) return r | (1 << 7) end)
end

function lsm9ds1_acc:init_accel(rate, scale, bandwidth, axes)
    assert(rate >= self.RATE_OFF and rate <= self.RATE_952,
           "invalid accelerometer data rate")
    assert(scale >= self.ACCEL_SCALE_2G and scale <= self.ACCEL_SCALE_8G,
           "invalid accelerometer scale")
    assert(bandwidth >=0 and bandwidth <= 3,
           "invalid accelerometer bandwidth: 0-3")
    assert(axes >= 0 and axes <= 7,
           "invalid accelerometer axes")

    status = i2c.txn(i2c.tx(self.address, self.CTRL_REG5_XL, axes << 3))
    if not status then
        return false, "unable to configure acclerometer axes"
    end

    local bw = 0
    if bandwidth > 0 then
        bw = 1
    end
    status = i2c.txn(i2c.tx(self.address, self.CTRL_REG6_XL,
                            (rate << 5) | (scale << 3) | (bw << 2 )| bandwidth))
    if not status then
        return false, "unable to configure accelerometer rate, scale and bandwidth"
    end
    return true
end

function lsm9ds1_acc:read_accel()
    local x, y, z = self:_get(self.OUT_X_XL, "<i2i2i2")
    return x, y, z
end

function lsm9ds1_acc:_get(reg, pack_fmt, convert)
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

function lsm9ds1_acc:_update(reg, pack_fmt, update)
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

function lsm9ds1_mag:new(address)
    address = address or lsm9ds1_mag.DEFAULT_ADDRESS
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

function lsm9ds1_mag:is_connected()
    -- read the WHO_AM_I register - datasheet section 7.11
    local result = self:_get(self.WHO_AM_I, "B")
    -- 0x21 is the current Product ID value as defined by the datasheet table 2
    if not (result == 0x3d) then
        return false, "could not locate device"
    end
    return true
end

function lsm9ds1_mag:init(mode, temp_comp, rate, scale, xy_performance, z_performance)
    assert(mode >= self.MODE_CONTINUOUS and mode <= self.MODE_OFF,
           "invalid magnetometer mode")
    assert(rate >= self.RATE_0_625 and rate <= self.RATE_80,
           "invalid magnetometer data rate")
    assert(scale >= self.SCALE_4_GAUSS and scale <= self.SCALE_16_GAUSS,
           "invalid magnetometer scale")
    assert(xy_performance >= self.PERF_LOW and xy_performance <= self.PERF_ULTRA,
           "invalid magnetometer X/Y performance value")
    assert(z_performance >= self.PERF_LOW and z_performance <= self.PERF_ULTRA,
           "invalid magnetometer Z performance value")

    if temp_comp then
        temp_comp = 1
    else
        temp_comp = 0
    end
    local status = i2c.txn(i2c.tx(self.address, self.CTRL_REG1_M,
                                  (temp_comp << 7) | (xy_performance << 5) | (rate << 2)))
    if not status then
        return false, "unable to configure magnetometer"
    end
    status = i2c.txn(i2c.tx(self.address, self.CTRL_REG2_M, scale << 5))
    if not status then
        return false, "unable to configure magnetometer"
    end
    status = i2c.txn(i2c.tx(self.address, self.CTRL_REG3_M, mode))
    if not status then
        return false, "unable to configure magnetometer"
    end
    status = i2c.txn(i2c.tx(self.address, self.CTRL_REG4_M, z_performance << 2))
    if not status then
        return false, "unable to configure magnetometer"
    end
    return true
end

function lsm9ds1_mag:read()
    local x, y, z = self:_get(self.OUT_X_L_M, "<i2i2i2")
    return x, y, z
end

function lsm9ds1_mag:read_offsets()
    local x, y, z = self:_get(self.OFFSET_X_REG_L_M, "<i2i2i2")
    return x, y, z
end

function lsm9ds1_mag:set_offsets(x, y, z)
    local status = i2c.txn(i2c.tx(self.address, self.OFFSET_X_REG_L_M,
                                  string.pack("<i2i2i2", x, y, z)))
    return status
end

function lsm9ds1_mag:_get(reg, pack_fmt, convert)
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

function lsm9ds1:new(acc_address, mag_address)
    acc_address = acc_address or lsm9ds1_acc.DEFAULT_ADDRESS
    mag_address = mag_address or lsm9ds1_mag.DEFAULT_ADDRESS
    -- We use a simple lua object system as defined
    -- https://www.lua.org/pil/16.1.html
    -- construct the object table
    local acc, reason = lsm9ds1_acc:new(acc_address)
    if not acc then
        return acc, reason
    end
    local mag, reason = lsm9ds1_mag:new(mag_address)
    if not mag then
        return mag, reason
    end
    local o = { acc = acc, mag = mag }
    -- ensure that the "class" is the metatable
    setmetatable(o, self)
    -- and that the metatable's index function is set
    -- Refer to https://www.lua.org/pil/16.1.html
    self.__index = self
    return o
end

return lsm9ds1
