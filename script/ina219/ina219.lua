-- INA219 analog board

i2c = he.i2c

SAMPLE_INTERVAL = 60000 -- 1 minute

ina219 = {
    DEFAULT_ADDRESS                  = 0x40,
    READ_ADDRESS                     = 0x01,

    REG_CONFIG                       = 0x00,
    REG_SHUNTVOLTAGE                 = 0x01,
    REG_BUSVOLTAGE                   = 0x02,
    REG_POWER                        = 0x03,
    REG_CURRENT                      = 0x04,
    REG_CALIBRATION                  = 0x05,
    
    CONFIG_RESET                     = 0x8000,  -- Reset Bit
    CONFIG_BVOLTAGERANGE_MASK        = 0x2000,  -- Bus Voltage Range Mask
    CONFIG_BVOLTAGERANGE_16V         = 0x0000,  -- 0-16V Range
    CONFIG_BVOLTAGERANGE_32V         = 0x2000,  -- 0-32V Range
    CONFIG_GAIN_MASK                 = 0x1800,  -- Gain Mask
    CONFIG_GAIN_1_40MV               = 0x0000,  -- Gain 1, 40mV Range
    CONFIG_GAIN_2_80MV               = 0x0800,  -- Gain 2, 80mV Range
    CONFIG_GAIN_4_160MV              = 0x1000,  -- Gain 4, 160mV Range
    CONFIG_GAIN_8_320MV              = 0x1800,  -- Gain 8, 320mV Range
    CONFIG_BADCRES_MASK              = 0x0780,  -- Bus ADC Resolution Mask
    CONFIG_BADCRES_9BIT              = 0x0080,  -- 9-bit bus res = 0..511
    CONFIG_BADCRES_10BIT             = 0x0100,  -- 10-bit bus res = 0..1023
    CONFIG_BADCRES_11BIT             = 0x0200,  -- 11-bit bus res = 0..2047
    CONFIG_BADCRES_12BIT             = 0x0400,  -- 12-bit bus res = 0..4097
    CONFIG_SADCRES_MASK              = 0x0078,  -- Shunt ADC Resolution and Averaging Mask
    CONFIG_SADCRES_9BIT_1S_84US      = 0x0000,  -- 1 x 9-bit shunt sample
    CONFIG_SADCRES_10BIT_1S_148US    = 0x0008,  -- 1 x 10-bit shunt sample
    CONFIG_SADCRES_11BIT_1S_276US    = 0x0010,  -- 1 x 11-bit shunt sample
    CONFIG_SADCRES_12BIT_1S_532US    = 0x0018,  -- 1 x 12-bit shunt sample
    CONFIG_SADCRES_12BIT_2S_1060US   = 0x0048,  -- 2 x 12-bit shunt samples averaged together
    CONFIG_SADCRES_12BIT_4S_2130US   = 0x0050,  -- 4 x 12-bit shunt samples averaged together
    CONFIG_SADCRES_12BIT_8S_4260US   = 0x0058,  -- 8 x 12-bit shunt samples averaged together
    CONFIG_SADCRES_12BIT_16S_8510US  = 0x0060, -- 16 x 12-bit shunt samples averaged together
    CONFIG_SADCRES_12BIT_32S_17MS    = 0x0068,  -- 32 x 12-bit shunt samples averaged together
    CONFIG_SADCRES_12BIT_64S_34MS    = 0x0070,  -- 64 x 12-bit shunt samples averaged together
    CONFIG_SADCRES_12BIT_128S_69MS   = 0x0078,  -- 128 x 12-bit shunt samples averaged together
    CONFIG_MODE_MASK                 = 0x0007,  -- Operating Mode Mask
    CONFIG_MODE_POWERDOWN            = 0x0000,
    CONFIG_MODE_SVOLT_TRIGGERED      = 0x0001,
    CONFIG_MODE_BVOLT_TRIGGERED      = 0x0002,
    CONFIG_MODE_SANDBVOLT_TRIGGERED  = 0x0003,
    CONFIG_MODE_ADCOFF               = 0x0004,
    CONFIG_MODE_SVOLT_CONTINUOUS     = 0x0005,
    CONFIG_MODE_BVOLT_CONTINUOUS     = 0x0006,
    CONFIG_MODE_SANDBVOLT_CONTINUOUS = 0x0007
}

function ina219:new(address)
    address = address or ina219.DEFAULT_ADDRESS
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

function ina219:is_connected()
    -- not sure what better to do here?
    local result = self:set_calibration_32v_2a()
    if not (self.CAL_VALUE > 0) then
        return false, "could not locate device"
    end
    return true
end

function ina219:_get(reg, pack_fmt, convert)
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

function ina219:_update(reg, pack_fmt, update)
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

function ina219:set_calibration_32v_2a() --default
    self.cal_value= 4096
    self.current_divider_ma = 10
    self.power_divider_mw = 2
    self:_update(self.REG_CALIBRATION, "I2", function(r) return r | self.cal_value end) -- set calibration register
    local config = self.CONFIG_BVOLTAGERANGE_32V | self.CONFIG_GAIN_8_320MV | self.CONFIG_BADCRES_12BIT | self.CONFIG_SADCRES_12BIT_1S_532US | self.CONFIG_MODE_SANDBVOLT_CONTINUOUS
    self:_update(self.REG_CONFIG, "I2", function(r) return r | config end) --set configuration register
end

function ina219:set_calibration_32v_1a()
    self.cal_value= 10240
    self.current_divider_ma = 25
    self.power_divider_mw = 1
    self:_update(self.REG_CALIBRATION, "I2", function(r) return r | self.cal_value end) -- set calibration register
    local config = self.CONFIG_BVOLTAGERANGE_32V | self.CONFIG_GAIN_8_320MV | self.CONFIG_BADCRES_12BIT | self.CONFIG_SADCRES_12BIT_1S_532US | self.CONFIG_MODE_SANDBVOLT_CONTINUOUS
    self:_update(self.REG_CONFIG, "I2", function(r) return r | config end) --set configuration register
end

function ina219:set_calibration_16v_400ma()
    self.cal_value= 8192
    self.current_divider_ma = 20
    self.power_divider_mw = 1
    self:_update(self.REG_CALIBRATION, "I2", function(r) return r | self.cal_value end) -- set calibration register
    local config = self.CONFIG_BVOLTAGERANGE_16V | self.CONFIG_GAIN_1_40MV | self.CONFIG_BADCRES_12BIT | self.CONFIG_SADCRES_12BIT_1S_532US | self.CONFIG_MODE_SANDBVOLT_CONTINUOUS
    self:_update(self.REG_CONFIG, "I2", function(r) return r | config end) --set configuration register
end

function ina219:get_bus_voltage()
    local result = self:_get(self.REG_BUSVOLTAGE, ">H")
    return ((result >> 3) * 4) * 0.001 --volts
end

function ina219:get_shunt_voltage()
    local result = self:_get(self.REG_SHUNTVOLTAGE, ">H")
    return result * 0.01 --millivolts
end

function ina219:get_current()
    self:_update(self.REG_CALIBRATION, "I2", function(r) return r | self.cal_value end) --set calibration register first as it sometimes gets reset
    local result = self:_get(self.REG_CURRENT, ">H")
    return result / self.current_divider_ma --milliamps
end

-- construct sensor on default address
sensor = assert(ina219:new())

-- get current time
local now = he.now()
while true do --main loop
    local shunt_voltage = assert(sensor:get_shunt_voltage()) --mV
    local bus_voltage = assert(sensor:get_bus_voltage()) --V
    local current = assert(sensor:get_current()) --mA

    -- send readings
    he.send("sv", now, "f", shunt_voltage) --send shunt voltage, as a float "f" on port "sv"
    he.send("bv", now, "f", bus_voltage) --send bus voltage as a float "f" on on port "bv"
    he.send("c", now, "f", current) --send current as a float "f" on port "c"

    -- Un-comment this line to see sampled values in semi-hosted mode
    print(shunt_voltage, bus_voltage, current)

    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end