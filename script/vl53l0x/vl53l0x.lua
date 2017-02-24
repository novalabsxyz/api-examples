-- Development board INA219 analog board

i2c = he.i2c

SAMPLE_INTERVAL = 60000 -- 1 minute

vl53l0x = {
    DEFAULT_ADDRESS                             = 0x29,
    WHO_AM_I                                    = 0xC0,
    SYSTEM_SEQUENCE_CONFIG                      = 0x01,
    MSRC_CONFIG_CONTROL                         = 0x60,
    FINAL_RANGE_CONFIG_MIN_COUNT_RATE_RTN_LIMIT = 0x44,
    GLOBAL_CONFIG_SPAD_ENABLES_REF_0            = 0xB0,
    DYNAMIC_SPAD_REF_EN_START_OFFSET            = 0x4F,
    DYNAMIC_SPAD_NUM_REQUESTED_REF_SPAD         = 0x4E,
    GLOBAL_CONFIG_REF_EN_START_SELECT           = 0xB6,
    SYSTEM_INTERRUPT_CONFIG_GPIO                = 0x0A,
    GPIO_HV_MUX_ACTIVE_HIGH                     = 0x84,
    SYSTEM_INTERRUPT_CLEAR                      = 0x0B,

    sequence_step_enables = {
        tcc                             = false,
        msrc                            = false,
        dss                             = false,
        pre_range                       = false,
        final_range                     = false
    },
    sequence_step_timeouts = {
        pre_range_vcsel_period_pclks    = 0,
        final_range_vcsel_period_pclks  = 0,
        msrc_dss_tcc_mclks              = 0, 
        pre_range_mclks                 = 0,
        final_range_mclks               = 0,
        msrc_dss_tcc_us                 = 0,
        pre_range_us                    = 0,
        final_range_us                  = 0
    }
}

function vl53l0x:new(address)
    address = address or vl53l0x.DEFAULT_ADDRESS
    -- We use a simple lua object system as defined
    -- https://www.lua.org/pil/16.1.html
    -- construct the object table
    local o = { address = address, stop_variable = 0 }
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

function vl53l0x:is_connected()
    local result = self:_get(self.WHO_AM_I, "B")
    if not (result == 238) then
        return false, "could not locate device"
    end
    return true
end

function vl53l0x:_get(reg, pack_fmt, convert)
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

function vl53l0x:_update(reg, pack_fmt, update)
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

function vl53l0x:init()
    --intialize sensor using sequence based on STM sample code
    self:_update(0x88, "B", function(r) return 0x00 end)
    self:_update(0x80, "B", function(r) return 0x01 end)
    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x00, "B", function(r) return 0x00 end)
    self.stop_variable = self:_get(0x91, "B")
    self:_update(0x00, "B", function(r) return 0x01 end)
    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x80, "B", function(r) return 0x00 end)

    --disable SIGNAL_RATE_MSRC (bit 1) and SIGNAL_RATE_PRE_RANGE (bit 4) limit checks
    self:_update(self.MSRC_CONFIG_CONTROL, "B", function(r) return r | 0x12 end)    
    self.set_signal_rate_limit(0.25)

    self:_update(self.SYSTEM_SEQUENCE_CONFIG, "B", function(r) return 0xFF end)
    local spad_count, spad_type_is_aperture = self.get_spad_info()

    local ref_spad_map = {self:_get(self.GLOBAL_CONFIG_SPAD_ENABLES_REF_0, "BBBBBB")}
    table.remove(ref_spad_map, 7) --annoying string.unpack thing which adds something to the end of the array

    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(self.DYNAMIC_SPAD_REF_EN_START_OFFSET, "B", function(r) return 0x00 end)
    self:_update(self.DYNAMIC_SPAD_NUM_REQUESTED_REF_SPAD, "B", function(r) return 0x2C end)
    self:_update(0xFF, "B", function(r) return 0x00 end)

    first_spad_to_enable = spad_type_is_aperture
    spads_enabled = 0
    if first_spad_to_enable == 12 then
        first_spad_to_enable = 0 --12 is the first aperture spad
    end

    for i = 1,48 do
        if (i < first_spad_to_enable or spads_enabled == spad_count) then
            ref_spad_map[i / 8] = ref_spad_map[i / 8] & ~(1 << (i % 8))
        elseif ((ref_spad_map[i / 8] >> (i % 8)) & 0x1) then
            spads_enabled = spads_enabled + 1
        end
    end
    self:_update(self.GLOBAL_CONFIG_SPAD_ENABLES_REF_0, "BBBBBB", function(r) return ref_spad_map end)

    -- DefaultTuningSettings from vl53l0x_tuning.h
    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x00, "B", function(r) return 0x00 end)

    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x09, "B", function(r) return 0x00 end)
    self:_update(0x10, "B", function(r) return 0x00 end)
    self:_update(0x11, "B", function(r) return 0x00 end)
    self:_update(0x24, "B", function(r) return 0x01 end)
    self:_update(0x25, "B", function(r) return 0xFF end)
    self:_update(0x75, "B", function(r) return 0x00 end)

    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x4E, "B", function(r) return 0x2C end)
    self:_update(0x48, "B", function(r) return 0x00 end)
    self:_update(0x30, "B", function(r) return 0x20 end)

    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x30, "B", function(r) return 0x09 end)
    self:_update(0x54, "B", function(r) return 0x00 end)
    self:_update(0x31, "B", function(r) return 0x04 end)
    self:_update(0x32, "B", function(r) return 0x03 end)
    self:_update(0x40, "B", function(r) return 0x83 end)
    self:_update(0x46, "B", function(r) return 0x25 end)
    self:_update(0x60, "B", function(r) return 0x00 end)
    self:_update(0x27, "B", function(r) return 0x00 end)
    self:_update(0x50, "B", function(r) return 0x06 end)
    self:_update(0x51, "B", function(r) return 0x00 end)
    self:_update(0x52, "B", function(r) return 0x96 end)
    self:_update(0x56, "B", function(r) return 0x08 end)
    self:_update(0x57, "B", function(r) return 0x30 end)
    self:_update(0x61, "B", function(r) return 0x00 end)
    self:_update(0x62, "B", function(r) return 0x00 end)
    self:_update(0x64, "B", function(r) return 0x00 end)
    self:_update(0x65, "B", function(r) return 0x00 end)
    self:_update(0x66, "B", function(r) return 0xA0 end)

    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x22, "B", function(r) return 0x32 end)
    self:_update(0x47, "B", function(r) return 0x14 end)
    self:_update(0x49, "B", function(r) return 0xFF end)
    self:_update(0x4A, "B", function(r) return 0x00 end)

    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x7A, "B", function(r) return 0x0A end)
    self:_update(0x7B, "B", function(r) return 0x00 end)
    self:_update(0x78, "B", function(r) return 0x21 end)

    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x23, "B", function(r) return 0x34 end)
    self:_update(0x42, "B", function(r) return 0x00 end)
    self:_update(0x44, "B", function(r) return 0xFF end)
    self:_update(0x45, "B", function(r) return 0x26 end)
    self:_update(0x46, "B", function(r) return 0x05 end)
    self:_update(0x40, "B", function(r) return 0x40 end)
    self:_update(0x0E, "B", function(r) return 0x06 end)
    self:_update(0x20, "B", function(r) return 0x1A end)
    self:_update(0x43, "B", function(r) return 0x40 end)

    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x34, "B", function(r) return 0x03 end)
    self:_update(0x35, "B", function(r) return 0x44 end)

    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x31, "B", function(r) return 0x04 end)
    self:_update(0x4B, "B", function(r) return 0x09 end)
    self:_update(0x4C, "B", function(r) return 0x05 end)
    self:_update(0x4D, "B", function(r) return 0x04 end)

    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x44, "B", function(r) return 0x00 end)
    self:_update(0x45, "B", function(r) return 0x20 end)
    self:_update(0x47, "B", function(r) return 0x08 end)
    self:_update(0x48, "B", function(r) return 0x28 end)
    self:_update(0x67, "B", function(r) return 0x00 end)
    self:_update(0x70, "B", function(r) return 0x04 end)
    self:_update(0x71, "B", function(r) return 0x01 end)
    self:_update(0x72, "B", function(r) return 0xFE end)
    self:_update(0x76, "B", function(r) return 0x00 end)
    self:_update(0x77, "B", function(r) return 0x00 end)

    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x0D, "B", function(r) return 0x01 end)

    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x80, "B", function(r) return 0x01 end)
    self:_update(0x01, "B", function(r) return 0xF8 end)

    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x8E, "B", function(r) return 0x01 end)
    self:_update(0x00, "B", function(r) return 0x01 end)
    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x80, "B", function(r) return 0x00 end)

    self:_update(self.SYSTEM_INTERRUPT_CONFIG_GPIO, "B", function(r) return 0x04 end)
    self:_update(self.GPIO_HV_MUX_ACTIVE_HIGH, "B", function(r) return r & ~0x10 end)
    self:_update(self.SYSTEM_INTERRUPT_CLEAR, "B", function(r) return 0x01 end)

    local measurement_timing_budget_us = get_measurement_timing_budget()
end

function vl53l0x:set_signal_rate_limit(limit_mcps)
    --Set the return signal rate limit check value in units of MCPS (mega counts per second)
    if (limit_Mcps < 0 or limit_Mcps > 511.99) then 
        return false
    end

    self:_update(self.FINAL_RANGE_CONFIG_MIN_COUNT_RATE_RTN_LIMIT, ">H", function(r) return limit_mcps * (1 << 7) end)
    return true
end

function vl53l0x:get_spad_info()
    self:_update(0x80, "B", function(r) return 0x01 end)
    self:_update(0xFF, "B", function(r) return 0x01 end)    
    self:_update(0x00, "B", function(r) return 0x00 end)
    self:_update(0xFF, "B", function(r) return 0x06 end)
    self:_update(0x83, "B", function(r) return r | 0x04 end)
    self:_update(0xFF, "B", function(r) return 0x07 end)
    self:_update(0x81, "B", function(r) return 0x01 end)
    self:_update(0x80, "B", function(r) return 0x01 end)
    self:_update(0x94, "B", function(r) return 0x6b end)
    self:_update(0x83, "B", function(r) return 0x00 end)
    -- timeout thing should go here
    self:_update(0x83, "B", function(r) return 0x01 end)

    local tmp = self:_get(0x92, "B")
    count = tmp & 0x7f
    type_is_aperture = (tmp >> 7) & 0x01

    self:_update(0x81, "B", function(r) return 0x00 end)
    self:_update(0xFF, "B", function(r) return 0x06 end)
    self:_update(0x83, "B", function(r) return r & ~0x04 end)
    self:_update(0xFF, "B", function(r) return 0x01 end)
    self:_update(0x00, "B", function(r) return 0x01 end)
    self:_update(0xFF, "B", function(r) return 0x00 end)
    self:_update(0x80, "B", function(r) return 0x00 end)
    return count, type_is_aperture
end

function vl53l0x:get_measurement_timing_budget()
    local start_overhead          = 1910
    local end_overhead            = 960
    local msrc_overhead           = 660
    local tcc_overhead            = 590
    local dss_overhead            = 690
    local pre_range_overhead      = 660
    local final_range_overhead    = 550

    local budget_us = start_overhead + end_overhead
    self:get_sequence_step_enables()

end

function vl53l0x:get_sequence_step_enables()
    local sequence_config = self:_get(self.SYSTEM_SEQUENCE_CONFIG, "B")

    self.sequence_step_enables.tcc          = (sequence_config >> 4) & 0x1;
    self.sequence_step_enables.dss          = (sequence_config >> 3) & 0x1;
    self.sequence_step_enables.msrc         = (sequence_config >> 2) & 0x1;
    self.sequence_step_enables.pre_range    = (sequence_config >> 6) & 0x1;
    self.sequence_step_enables.final_range  = (sequence_config >> 7) & 0x1;
end

function vl53l0x:get_sequence_step_timeouts()
end

function decode_vcsel_period(reg_val)
    return (((reg_val) + 1) << 1)
end

-- construct sensor on default address
sensor = assert(vl53l0x:new())

-- get current time
local now = he.now()
--[[while true do --main loop
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
end]]--

