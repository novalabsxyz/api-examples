-- Development board INA219 analog board

i2c = he.i2c

SAMPLE_INTERVAL = 1000 -- 1 minute

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

    SYSRANGE_START = 0x00,
     RESULT_INTERRUPT_STATUS = 0x13,
     RESULT_RANGE_STATUS = 0x14,

    PRE_RANGE_CONFIG_VCSEL_PERIOD = 0x50,
    PRE_RANGE_CONFIG_TIMEOUT_MACROP_HI = 0x51,
    MSRC_CONFIG_TIMEOUT_MACROP = 0x46,
    FINAL_RANGE_CONFIG_TIMEOUT_MACROP_HI = 0x71,

    VCSEL_PERIOD_PRE_RANGE                      = 0x01,
    VCSEL_PERIOD_FINAL_RANGE                    = 0x02,

    timeout = 0,

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

function vl53l0x:_set(reg, pack_fmt, value)
    -- call update function
    local status, buffer =
        i2c.txn(i2c.tx(self.address, reg, string.pack(pack_fmt, value)))
    if not status then
        return false, "unable to set value"
    end
    return true
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
    self:_set(0x88, "B", 0x00)
    self:_set(0x80, "B", 0x01)
    self:_set(0xFF, "B", 0x01)
    self:_set(0x00, "B", 0x00)
    self.stop_variable = self:_get(0x91, "B")
    self:_set(0x00, "B", 0x01)
    self:_set(0xFF, "B", 0x00)
    self:_set(0x80, "B", 0x00)

    --disable SIGNAL_RATE_MSRC (bit 1) and SIGNAL_RATE_PRE_RANGE (bit 4) limit checks
    self:_set(self.MSRC_CONFIG_CONTROL, "B", 0x12)
    self:set_signal_rate_limit(0.25)

    self:_set(self.SYSTEM_SEQUENCE_CONFIG, "B", 0xFF)
    local spad_count, spad_type_is_aperture = self:get_spad_info()

    local ref_spad_map = {self:_get(self.GLOBAL_CONFIG_SPAD_ENABLES_REF_0, "BBBBBB")}
    table.remove(ref_spad_map, 7) --annoying string.unpack thing which adds something to the end of the array

    self:_set(0xFF, "B", 0x01)
    self:_set(self.DYNAMIC_SPAD_REF_EN_START_OFFSET, "B", 0x00)
    self:_set(self.DYNAMIC_SPAD_NUM_REQUESTED_REF_SPAD, "B", 0x2C)
    self:_set(0xFF, "B", 0x00)

    first_spad_to_enable = spad_type_is_aperture
    spads_enabled = 0
    if first_spad_to_enable == 12 then
        first_spad_to_enable = 0 --12 is the first aperture spad
    end

    for i = 1,47 do
        local key = math.floor(i / 8) + 1
        if (i < first_spad_to_enable or spads_enabled == spad_count) then
            ref_spad_map[key] = ref_spad_map[key] & ~(1 << (i % 8))
        elseif ((ref_spad_map[key] >> (i % 8)) & 0x1) then
            spads_enabled = spads_enabled + 1
        end
    end
    self:_set(self.GLOBAL_CONFIG_SPAD_ENABLES_REF_0, "c6", string.pack("BBBBBB", ref_spad_map[1], ref_spad_map[2], ref_spad_map[3], ref_spad_map[4], ref_spad_map[5], ref_spad_map[6]))

    -- DefaultTuningSettings from vl53l0x_tuning.h
    self:_set(0xFF, "B", 0x01)
    self:_set(0x00, "B", 0x00)

    self:_set(0xFF, "B", 0x00)
    self:_set(0x09, "B", 0x00)
    self:_set(0x10, "B", 0x00)
    self:_set(0x11, "B",  0x00)
    self:_set(0x24, "B",  0x01)
    self:_set(0x25, "B",  0xFF)
    self:_set(0x75, "B",  0x00)

    self:_set(0xFF, "B",  0x01)
    self:_set(0x4E, "B",  0x2C)
    self:_set(0x48, "B",  0x00)
    self:_set(0x30, "B",  0x20)

    self:_set(0xFF, "B",  0x00)
    self:_set(0x30, "B",  0x09)
    self:_set(0x54, "B",  0x00)
    self:_set(0x31, "B",  0x04)
    self:_set(0x32, "B",  0x03)
    self:_set(0x40, "B",  0x83)
    self:_set(0x46, "B",  0x25)
    self:_set(0x60, "B",  0x00)
    self:_set(0x27, "B",  0x00)
    self:_set(0x50, "B",  0x06)
    self:_set(0x51, "B",  0x00)
    self:_set(0x52, "B",  0x96)
    self:_set(0x56, "B",  0x08)
    self:_set(0x57, "B",  0x30)
    self:_set(0x61, "B",  0x00)
    self:_set(0x62, "B",  0x00)
    self:_set(0x64, "B",  0x00)
    self:_set(0x65, "B",  0x00)
    self:_set(0x66, "B",  0xA0)
    he.wait{time=he.now() + 1}

    self:_set(0xFF, "B",  0x01)
    self:_set(0x22, "B",  0x32)
    self:_set(0x47, "B",  0x14)
    self:_set(0x49, "B",  0xFF)
    self:_set(0x4A, "B",  0x00)

    self:_set(0xFF, "B",  0x00)
    self:_set(0x7A, "B",  0x0A)
    self:_set(0x7B, "B",  0x00)
    self:_set(0x78, "B",  0x21)

    self:_set(0xFF, "B",  0x01)
    self:_set(0x23, "B",  0x34)
    self:_set(0x42, "B",  0x00)
    self:_set(0x44, "B",  0xFF)
    self:_set(0x45, "B",  0x26)
    self:_set(0x46, "B",  0x05)
    self:_set(0x40, "B",  0x40)
    self:_set(0x0E, "B",  0x06)
    self:_set(0x20, "B",  0x1A)
    self:_set(0x43, "B",  0x40)

    self:_set(0xFF, "B",  0x00)
    self:_set(0x34, "B",  0x03)
    self:_set(0x35, "B",  0x44)


    self:_set(0xFF, "B",  0x01)
    self:_set(0x31, "B",  0x04)
    self:_set(0x4B, "B",  0x09)
    self:_set(0x4C, "B",  0x05)
    self:_set(0x4D, "B",  0x04)

    self:_set(0xFF, "B",  0x00)
    self:_set(0x44, "B",  0x00)
    self:_set(0x45, "B",  0x20)
    self:_set(0x47, "B",  0x08)
    self:_set(0x48, "B",  0x28)
    self:_set(0x67, "B",  0x00)
    self:_set(0x70, "B",  0x04)
    self:_set(0x71, "B",  0x01)
    self:_set(0x72, "B",  0xFE)
    self:_set(0x76, "B",  0x00)
    self:_set(0x77, "B",  0x00)

    self:_set(0xFF, "B",  0x01)
    self:_set(0x0D, "B",  0x01)

    self:_set(0xFF, "B",  0x00)
    self:_set(0x80, "B",  0x01)
    self:_set(0x01, "B",  0xF8)

    self:_set(0xFF, "B",  0x01)
    self:_set(0x8E, "B",  0x01)
    self:_set(0x00, "B",  0x01)
    self:_set(0xFF, "B",  0x00)
    self:_set(0x80, "B",  0x00)


    self:_set(self.SYSTEM_INTERRUPT_CONFIG_GPIO, "B", 0x04)
    self:_update(self.GPIO_HV_MUX_ACTIVE_HIGH, "B", function(r) return r & ~0x10 end)
    self:_set(self.SYSTEM_INTERRUPT_CLEAR, "B", 0x01)

    local measurement_timing_budget_us = self:get_measurement_timing_budget()


    -- "Disable MSRC and TCC by default"
    -- MSRC = Minimum Signal Rate Check
    -- TCC = Target CentreCheck
    self:_set(self.SYSTEM_SEQUENCE_CONFIG, "B", 0xE8)

    -- "Recalculate timing budget"
    self:set_measurement_timing_budget(measurement_timing_budget_us);


    self:_set(self.SYSTEM_SEQUENCE_CONFIG, "B", 0x01)
    if not self:perform_single_ref_calibration(0x40) then
        return false
    end

    self:_set(self.SYSTEM_SEQUENCE_CONFIG, "B", 0x02)
    if not self:perform_single_ref_calibration(0x00) then
        return false
    end

    -- restore config
    self:_set(self.SYSTEM_SEQUENCE_CONFIG, "B", 0xE8)

    return true
end

function vl53l0x:set_signal_rate_limit(limit_mcps)
    --Set the return signal rate limit check value in units of MCPS (mega counts per second)
    if (limit_mcps < 0 or limit_mcps > 511.99) then 
        return false
    end

    self:_update(self.FINAL_RANGE_CONFIG_MIN_COUNT_RATE_RTN_LIMIT, ">H", function(r) return limit_mcps * (1 << 7) end)
    return true
end

function vl53l0x:get_spad_info()
    self:_set(0x80, "B", 0x01)
    self:_set(0xFF, "B", 0x01)    
    self:_set(0x00, "B", 0x00)
    self:_set(0xFF, "B", 0x06)
    self:_update(0x83, "B", function(r) return r | 0x04 end)
    self:_set(0xFF, "B", 0x07)
    self:_set(0x81, "B", 0x01)
    self:_set(0x80, "B", 0x01)
    self:_set(0x94, "B", 0x6B)
    self:_set(0x83, "B", 0x00)
    local now = he.now()
    while self:_get(0x83, "B") == 0x00 do
        if self:check_timeout(now) then
            return false
        end
        he.wait{time=he.now() + 1}
    end
    self:_set(0x83, "B", 0x01)

    local tmp = self:_get(0x92, "B")
    count = tmp & 0x7f
    type_is_aperture = (tmp >> 7) & 0x01

    self:_set(0x81, "B", 0x00)
    self:_set(0xFF, "B", 0x06)
    self:_update(0x83, "B", function(r) return r & ~0x04 end)
    self:_set(0xFF, "B", 0x01)
    self:_set(0x00, "B", 0x01)
    self:_set(0xFF, "B", 0x00)
    self:_set(0x80, "B", 0x00)
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
    self:get_sequence_step_timeouts()

    if self.sequence_step_enables.tcc then
        budget_us = budget_us + (self.sequence_step_timeouts.msrc_dss_tcc_us + tcc_overhead)
    end

    if self.sequence_step_enables.dss then
        budget_us = budget_us + (2 * (self.sequence_step_timeouts.msrc_dss_tcc_us + dss_overhead))
    elseif self.sequence_step_enables.msrc then
        budget_us = budget_us + (self.sequence_step_timeouts.msrc_dss_tcc_us + msrc_overhead)
    end

    if self.sequence_step_enables.pre_range then
        budget_us = budget_us + (self.sequence_step_timeouts.pre_range_us + pre_range_overhead)
    end

    if self.sequence_step_enables.final_range then
        budget_us = budget_us + (self.sequence_step_timeouts.final_range_us + final_range_overhead)
    end

    return budget_us;
end

function vl53l0x:set_measurement_timing_budget(budget_us)
    local start_overhead          = 1320 -- different from the value in _get
    local end_overhead            = 960
    local msrc_overhead           = 660
    local tcc_overhead            = 590
    local dss_overhead            = 690
    local pre_range_overhead      = 660
    local final_range_overhead    = 550


    local min_timing_budget = 20000

    if budget_us < min_timing_budget then
        return false
    end

    local used_budget_us = start_overhead + end_overhead

    self:get_sequence_step_enables()
    self:get_sequence_step_timeouts()


    if self.sequence_step_enables.tcc then
        used_budget_us = used_budget_us + (self.sequence_step_timeouts.msrc_dss_tcc_us + tcc_overhead)
    end

    if self.sequence_step_enables.dss then
        used_budget_us = used_budget_us + (2 * (self.sequence_step_timeouts.msrc_dss_tcc_us + dss_overhead))
    elseif self.sequence_step_enables.msrc then
        used_budget_us = used_budget_us + (self.sequence_step_timeouts.msrc_dss_tcc_us + msrc_overhead)
    end

    if self.sequence_step_enables.pre_range then
        used_budget_us = used_budget_us + (self.sequence_step_timeouts.pre_range_us + pre_range_overhead)
    end

    if self.sequence_step_enables.final_range then
        used_budget_us = used_budget_us + final_range_overhead

        -- "Note that the final range timeout is determined by the timing
        -- budget and the sum of all other timeouts within the sequence.
        -- If there is no room for the final range timeout, then an error
        -- will be set. Otherwise the remaining time will be applied to
        -- the final range."
        if used_budget_us > budget_us then
            -- requested timeout too big
            return false
        end

        local final_range_timeout_us = budget_us - used_budget_us

        -- "For the final range timeout, the pre-range timeout
        --  must be added. To do this both final and pre-range
        --  timeouts must be expressed in macro periods MClks
        --  because they have different vcsel periods."
        
        local final_range_timeout_mclks = self:timeout_microseconds_to_mclks(final_range_timeout_us, self.sequence_step_timeouts.final_range_vcsel_period_pclks)

        if self.sequence_step_enables.pre_range then
            final_range_timeout_mclks = final_range_timeout_mclks + self.sequence_step_timeouts.pre_range_mclks
        end

        self:_set(self.FINAL_RANGE_CONFIG_TIMEOUT_MACROP_HI, ">I2", self:encode_timeout(final_range_timeout_mclks))

    end
    return true
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
    self.sequence_step_timeouts.pre_range_vcsel_period_pclks = self:get_vcsel_pulse_period(self.VCSEL_PERIOD_PRE_RANGE)
    self.sequence_step_timeouts.msrc_dss_tcc_mclks = self:_get(self.MSRC_CONFIG_TIMEOUT_MACROP, "B", function(r) return r+1 end)
    self.sequence_step_timeouts.msrc_dss_ts_us = self:timeout_mclks_to_microseconds(self.sequence_step_timeouts.msrc_dss_tcc_mclks, self.sequence_step_timeouts.pre_range_vcsel_period_pclks)

    self.sequence_step_timeouts.pre_range_mclks = self:decode_timeout(self:_get(self.PRE_RANGE_CONFIG_TIMEOUT_MACROP_HI, ">I2"))

    self.sequence_step_timeouts.pre_range_us =
    self:timeout_mclks_to_microseconds(self.sequence_step_timeouts.pre_range_mclks,
                               self.sequence_step_timeouts.pre_range_vcsel_period_pclks)

    self.sequence_step_timeouts.final_range_vcsel_period_pclks = self:get_vcsel_pulse_period(self.VCSEL_PERIOD_PRE_RANGE)

    self.sequence_step_timeouts.final_range_mclks =
    self:decode_timeout(self:_get(self.FINAL_RANGE_CONFIG_TIMEOUT_MACROP_HI, ">I2"))

  if self.sequence_step_enables.pre_range then
      self.sequence_step_timeouts.final_range_mclks = self.sequence_step_timeouts.final_range_mclks - self.sequence_step_timeouts.pre_range_mclks
  end

  self.sequence_step_timeouts.final_range_us =
    self:timeout_mclks_to_microseconds(self.sequence_step_timeouts.final_range_mclks,
                               self.sequence_step_timeouts.final_range_vcsel_period_pclks)

end

function vl53l0x:get_vcsel_pulse_period(range_type)
    if range_type == self.VCSEL_PERIOD_PRE_RANGE then
        return self:decode_vcsel_period(self:_get(self.PRE_RANGE_CONFIG_VCSEL_PERIOD, "B"))
    elseif range_type == self.VCSEL_PERIOD_FINAL_RANGE then
        return self:decode_vcsel_period(self:_get(self.FINAL_RANGE_CONFIG_VCSEL_PERIOD, "B"))
    else
        assert(false, "invalid pulse period")
    end
end

function vl53l0x:timeout_mclks_to_microseconds(timeout_period_mclks, vcsel_period_pclks)
    local macro_period_ns = self:calc_macro_period(vcsel_period_pclks)

    return math.floor(((timeout_period_mclks * macro_period_ns) + (macro_period_ns / 2)) / 1000)
end

function vl53l0x:timeout_microseconds_to_mclks(timeout_period_us, vcsel_period_pclks)
    local macro_period_ns = self:calc_macro_period(vcsel_period_pclks)

    return math.floor(((timeout_period_us * 1000) + (macro_period_ns / 2)) / macro_period_ns)
end


function vl53l0x:calc_macro_period(vcsel_period_pclks)
    return math.floor(((2304 * vcsel_period_pclks * 1655) + 500) / 1000)
end

function vl53l0x:decode_vcsel_period(reg_val)
    return (((reg_val) + 1) << 1)
end

function vl53l0x:decode_timeout(value)
    return (value & 0x00FF <<
           ((value & 0xFF00) >> 8)) + 1;
end


function vl53l0x:encode_timeout(timeout_mclks)
    -- format: "(LSByte * 2^MSByte) + 1"

    local ls_byte = 0
    local ms_byte = 0

    if timeout_mclks > 0 then
        ls_byte = timeout_mclks - 1;

        while ((ls_byte & 0xFFFFFF00) > 0) do
            ls_byte = ls_byte >> 1;
            ms_byte = ms_byte + 1;
        end

        return (ms_byte << 8) | (ls_byte & 0xFF)
    else
        return 0
    end
end

function vl53l0x:check_timeout(time)
    local now = he.now()
    print("timeout", now - time)
    return self.timeout > 0 and (now - time) > self.timeout
end

function vl53l0x:set_timeout(timeout)
    self.timeout = timeout
end

function vl53l0x:perform_single_ref_calibration(vhv_init_byte)
    self:_set(self.SYSRANGE_START, "B", 0x01 | vhv_init_byte) -- VL53L0X_REG_SYSRANGE_MODE_START_STOP

    local now = he.now()
    he.wait{time=he.now() + 1}
    while self:_get(self.RESULT_INTERRUPT_STATUS, "B", function(r) return r & 0x07 end) == 0 do
        if self:check_timeout(now) then
            return false
        end
        he.wait{time=he.now() + 1}
    end
    self:_set(self.SYSTEM_INTERRUPT_CLEAR, "B", 0x01)
    self:_set(self.SYSRANGE_START, "B", 0x00)
    return true;
end

function vl53l0x:start_continuous(period_ms)
    self:_set(0x80, "B", 0x01)
    self:_set(0xFF, "B", 0x01)
    self:_set(0x00, "B", 0x00)
    self:_set(0x91, "B", self.stop_variable)
    self:_set(0x00, "B", 0x01)
    self:_set(0xFF, "B", 0x00)
    self:_set(0x80, "B", 0x00)

    period_ms = period_ms or 0

    if period_ms ~= 0 then
        -- continuous timed mode

        -- VL53L0X_SetInterMeasurementPeriodMilliSeconds() begin

        local osc_calibrate_val = self._get(self.OSC_CALIBRATE_VAL, ">I2");

        if osc_calibrate_val ~= 0 then
            period_ms =  period_ms * osc_calibrate_val
        end

        self:_set(self.SYSTEM_INTERMEASUREMENT_PERIOD, ">I4", period_ms)

        -- VL53L0X_SetInterMeasurementPeriodMilliSeconds() end

        self:_set(SYSRANGE_START, "B", 0x04); -- VL53L0X_REG_SYSRANGE_MODE_TIMED
    else
        -- continuous back-to-back mode
        self:_set(self.SYSRANGE_START, "B", 0x02); -- VL53L0X_REG_SYSRANGE_MODE_BACKTOBACK
    end
end

function vl53l0x:read_range_continuous_millimeters()
    local now = he.now()
    while self:_get(self.RESULT_INTERRUPT_STATUS, "B", function(r) return r & 0x07 end) == 0 do
    if self:check_timeout(now) then
        return false
    end
    end

  -- assumptions: Linearity Corrective Gain is 1000 (default)
  -- fractional ranging is not enabled
  local range = self:_get(self.RESULT_RANGE_STATUS + 10, ">I2", function(r) return r  end)

  self:_set(self.SYSTEM_INTERRUPT_CLEAR, "B", 0x01)

  return range;

end

-- construct sensor on default address
sensor = assert(vl53l0x:new())

sensor:set_timeout(500)

sensor:init()

sensor:start_continuous()

-- get current time
local now = he.now()
while true do --main loop
    he.send("proximity", now, "f", sensor:read_range_continuous_millimeters() / 25.4)
    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end

