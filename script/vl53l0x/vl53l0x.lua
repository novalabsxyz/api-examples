--------------------------------------------------------------------------------
-- vl53l0x.lua: STMicroelectronics VL53L0X LiDAR Time-of-Flight sensor

-- Authors:  Amir Haleem, Andrew Thompson, Austin Seipp
-- Version:  0.0.0
-- Released: 13 March 2017
-- Keywords: lidar, distance, time-of-flight, adafruit
-- License:  BSD3

-- License (3-Clause BSD):
-- =============================================================================
--
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
--     * Redistributions of source code must retain the above copyright notice,
--       this list of conditions and the following disclaimer.
--
--     * Redistributions in binary form must reproduce the above copyright
--       notice, this list of conditions and the following disclaimer in the
--       documentation and/or other materials provided with the distribution.
--
--     * Neither the name of the authors or the names of other contributors may
--       be used to endorse or promote products derived from this software
--       without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES LOSS OF USE, DATA, OR PROFITS OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.

-- Introduction commentary and setup:
-- =============================================================================
--
-- The VL53L0X is a low-cost time-of-flight sensor with an absolute range of
-- ~1.2m-2m (depending on who's datasheet lies you believe) and a simple I²C
-- interface. This module works directly with the basic Helium Dev Board and the
-- included rainbow ribbon cable, no extras needed.
--
-- The pinout for the sensor vs the devkit rainbow cable colors is as follows:
--
--      Helium Atom Dev Board                             VL53L0X
--
--         (VDD) Yellow <--------------------------> VIN  (VCSEL Supply)
--         (GND) Blue <----------------------------> GND  (VCSEL Ground)
--         (SCL) Orange <--------------------------> SCL  (I²C Clock)
--         (SDA) Brown <---------------------------> SDA  (I²C Data)
--        (INT0) White <---------------------------> GPIO (Interrupt)
--
-- (From the above layout vs the devkit pins, you can see the rainbow cable for
-- the board converts the 2x 5-pin layout into a 10-pin "staggered" layout.)
--
-- A battery will be required for usage (even interactively; e.g. USB host power
-- isn't sufficient for both). Frequent sampling is probably going to annihilate
-- the included LiPo (especially with radio overhead, unless you buffer
-- samples) very quickly.
--
-- This library implementation is fairly optimized to reduce memory usage, so
-- that it can easily be used and tested without device upload -- but despite
-- that, it has very little room in general for anything else. It leaves enough
-- memory left over for the radio (he.send), some stats, debug printing,
-- (limited) stack traces -- and it still can do all of the above in interactive
-- mode with `helium-script -i`. You will have more memory available in
-- non-development mode when uploaded permanently on-device, so keep that in
-- mind.
--
-- Due to the size constraints, this library does little error handling (e.g.
-- no NVM validation for sensor reference calibration points). Thus, it tries
-- to simply be as perfect as it can be.
--
-- A good, simple piece of reference code for the VL53L0X is the Pololu Arduino
-- implementation: https://github.com/pololu/vl53l0x-arduino, an simple
-- alternative to the ST and Adafruit libraries (which can be found elsewhere).
--
-- Where otherwise unspecified or ambiguous, this library refers to and defaults
-- to whatever settings/pinouts/design are specified by the Adafruit VL53L0X
-- module.

-- Device notes:
-- =============================================================================
--
-- The VL53L0X sensor packs an array of "Single Photon Avalanche Diodes" (SPADs)
-- with a "Vertical Cavity Surface Emitting Laser" (VCSEL) on a single chip,
-- resulting in a sensor for reading distance measurements. SPADs detect
-- low-intensity light signals (such as single photons), including precise
-- time-of-arrival, combined with an "Avalance Diode" to conduct current (hence
-- the name) on this event. The VCSEL emits a laser which the SPADs detect
-- returning to them, from which (speed vs return time) you can calculate
-- distance. This is the "Time-of-Flight" for the photons emitted from the
-- laser, a form of "LiDAR" ('Light Detection And Ranging').
--
-- The sensor includes an on-board firmware which speaks to application code
-- over I²C, allowing SPAD calibration, accuracy configuration, mode selection,
-- and sensor start/stop.
--
-- Upon power being applied, the sensor starts in the "HW Standby" phase,
-- waiting for a high signal on the XSHUT pin, so it can begin booting the
-- firmware. After booting the firmware, the sensor enters "SW Standby" mode,
-- where it can enter one of three operating modes, for taking range
-- measurements. In SW Standby mode, if the XSHUT pin is set low, the firmware
-- shuts down and goes back into HW Standby.
--
-- Note that on the Adafruit model VL53L0X sensor, the XSHUT pin is attached to
-- the 'SHDN' pin, but it is pulled high by default. As a result, once power is
-- supplied, the sensor effectively immediately enters SW Standby (this is why
-- it is not included in the pinout mapping above). The Adafruit model has a
-- fixed I²C address of 0x29 which cannot be changed.
--
-- Once the user has initialized and set the device into selected mode, the
-- device begins taking range measurements, which the user application may then
-- sample at the rate they desire.
--
-- There are three operating modes:
--
--   - Single-shot range detection: A single range measurement is performed, and
--     the sensor returns to SW standby mode, so it can be reconfigured and
--     started again after the measurement is sampled.
--
--   - Continuous range detection: the sensor performs a range measurement, and
--     immediately returns to perform another measurement without returning to
--     any standby mode. The application samples continuously.
--
--   - Timed, continuous range detection: the sensor performs a range
--     measurement, then goes into 'inter-measurement standby mode', before
--     returning after a specified time to take another measurement. The
--     application samples continuously at this rate.
--
-- The datasheet claims some basic power usage stats (~23°C, @ 2.8V):
--
--   - Standby mode: HW standby ~5μA, SW standby ~6μA
--   - Continuous ranging averages at ~19mA to a max of 40mA (at ~33ms budget)
--   - Timed ranging: ~16μA in-between measurements (IM standby mode).
--
-- The Atom board supports a VDD switch 'VSW' which controls power to the VDD
-- pin. This switch can be controlled with the `he.power_{get,set}` APIs in
-- order to kill power and conserve battery when the device is in standby and
-- unneeded.
--
-- There are five phases to the initial VL53L0X setup:
--
--   - 1) Device initialization, done once after device reset.
--   - 2) SPAD calibration
--   - 3) Temperature calibration
--   - 4) Offset calibration
--
-- TODO FIXME: describe calibration.
--
-- Once you have initialized the device, chosen the operating mode, and begun
-- taking measurements, there are two options for getting device data from the
-- sensor:
--
--   - Polling: check an I²C register for the current status.
--   - Interrupt: a signal is sent on the GPIO1 pin upon range data being ready.
--
-- The Adafruit VL53L0X has GPIO1 mapped to the 'GPIO' pin which can be used for
-- detecting data readiness at 2.8V.
--
-- At the moment, interrupt support is limited. When GPIO1 is connected, an
-- interrupt will be delivered whenever a sample is ready. This can be used with
-- continuous timed mode in order to have Helium OS enter a sleep state, and be
-- woken on an interrupt when the sample is ready to be taken from the sensor.
-- Continuous timed mode with interrupts will save more power, as IM standby
-- mode allows deeper power savings. (You can alternatively fully power off the
-- device and use one-shot sensing, instead.)
--
-- However, you currently cannot configure range settings for interrupts; this
-- /would/ allow you to use timed continuous sensing to only interrupt when some
-- condition is met or threshold is reached.

-- Helium Script API and Programming Reference:
-- =============================================================================
--
-- Using the API from another module is simple -- simply import the module using
-- `local vl53l0x = require('vl53l0x')` to load it.
--
-- Once you have the vl53l0x library loaded, you must construct a sensor object,
-- which represents a connection to the attached VL53L0X. This will verify that
-- the attached I²C device is in fact a VL53L0X, but otherwise does no
-- initialization. There is one method for creating these sensor objects:
--
--   - vl53l0x:new(...)                -- return a connected VL53L0X I²C object
--
-- See the documentation for ${vl53l0x:new} below for more. Once you have the
-- resulting sensor object, you MUST initialize it before anything else. This
-- calibrates the sensor appropriately based on the default settings.
--
--   - vl53l0x:init()                  -- initialize/calibrate sensor
--
-- This calibrates the sensor and puts it in SW Standby mode.
--
-- Once the sensor is initialized, you may further configure it to set quality
-- and range options (this is optional):
--
--                      Measurement Timing budgets:
--
--   - vl53l0x:timing_budget()         -- get timing budget (in microseconds)
--   - vl53l0x:timing_budget(us)       -- set timing budget (in microseconds)
--
--                         Signal Rate Limits:
--
--   - vl53l0x:rate_limit()            -- get rate limit (in MCPS)
--   - vl53l0x:rate_limit(mcps)        -- set the rate limit (in MCPS)
--
--                         VCSEL Pulse Period:
--
--   - vl53l0x:vcsel_pulse(typ)        -- get VCSEL pulse period (in PCLKs)
--
-- Roughly: the timing budget refers to the amount of time allowed for a single
-- measurement (longer times allowing more accurate measurements); the rate
-- limit controls the limit for a measurement to report as a valid reading; and
-- the pulse peroid controls the pulse rate of the laser (a faster period
-- yielding increased range).
--
-- Once you've initialized the sensor and chosen settings (if any), you can
-- begin taking range measurements. You can take single measurements, or
-- enable continuous measurements, which you may then sample as you wish
-- (see the above documentation for information on operating modes).
--
-- To enable continuous sensing, use the ${vl53l0x:start_continuous} API:
--
--   - vl53l0x:continuous(true)   -- continuous ranging mode
--   - vl53l0x:continuous(period) -- timed, continuous ranging mode
--   - vl53l0x:continuous(false)  -- disable continuous ranging mode
--
-- Disabling continuous ranging returns to SW Standby mode.
--
-- Regardless of whether you have enabled continuous sensing, you can take
-- a range measurement from the sensor using ${vl53l0x:range}:
--
--   - vl53l0x:range()               -- get a distance reading in ms (float)
--
-- The ${vl53l0x:range} function determines how to properly get a range
-- measurement regardless of mode (e.g. continuous vs one-shot). The reading is
-- always returned in units of millimeters.
--
-- See the accompanying documentation, as well as the accompanying `main.lua`
-- for an example of setting up and performing sensor readings and sending them
-- into the Helium Cloud.

-- Hacking notes:
-- =============================================================================
--
-- See the accompanying README.org file for tips on hacking this module, memory
-- usage and efficiency in Helium Script, etc.

-- Module TODO items, in no particular order:
-- =============================================================================
--
--  * It /might/ still be possible to fit interrupt threshold support in on the
--    Atom Development Board. This is likely a better interface for continuous
--    sensing and unlocks one of the most powerful features.
--  * VCSEL pulse /control/ isn't yet exposed, though retrieving the current
--    pulse is. This should allow longer ranges on the sensor.
--  * XSHUT could be set low in order to go from SW Standby -> HW Standby,
--    but a pin write requires the Helium Digital Extension Board API.
--    - It's unclear how this device might operate under the Digital Extension
--      board, but it should be documented.
--  * Further optimization, at the expense of all sanity.
--    - It _might_ be profitable to explore conversion of *some* of the very
--      repetitive _set calls to use flat arrays/loops. Depends on object/GC
--      friendliness vs bytecode instruction size, in terms of memory use.
--      Strings can be used as flat arrays (hopefully without much overhead)

--------------------------------------------------------------------------------
-- SECTION: Module Prelude

-- API version check: 1.0.0+ for now. There should be a Helium API for this...
assert(he.version() == "1.0.0", "only compatible with Helium Script API v1.0.0")

-- Exported module object
local vl53l0x = {}

--------------------------------------------------------------------------------
-- SECTION: Public API - Sensor initialization

-- vl53l0x:new(timeout, address):
--
-- Create a new VL53L0X sensor object which can be sampled for range/distance
-- measurements. The argument ${timeout} specifies the amount of time to wait,
-- in milliseconds, for data reading on the I2C bus to occur before returning
-- an error. The ${address} argument specifies the default I2C address of the
-- attached sensor itself.
--
-- The attached I2C device will be probed (register 0xC0) for the device
-- identifier and confirmed as a VL53L0X before continuing. If the I2C device
-- is not present or is not the right sensor, this function fails.
--
-- Setting ${timeout} to 0 will cause reads on the I2C bus to potentially
-- wait forever.
--
--   - If no ${timeout} is specified, the default is 500ms before failing.
--   - If no ${address} is specified, the default I2C address is 0x29, which
--     corresponds to the I2C address of the Adafruit model VL53L0X sensor.
--
-- Returns:
--
--   - A `vl53l0x` object if a VL53L0X is attached on the given I2C address.
--   - `false, reason` if probing the sensor failed. `reason` is a string.
--
-- The returned vl53l0x object does NOT have to be re-initialized across
-- power on/off events. It only needs to be re-initialized if the address
-- or desired timeout changes.
--
-- You are advised to wrap this in a call to `assert`, e.g.
-- `assert(vl53l0x:new(500, 0x29))`
--
function vl53l0x:new(timeout, address)
  -- Set up a table for use as a simple Lua object, with default fields
  -- for the private VL53L0X member variables.
  local o = {
    -- The address of the I2C interface attached to the VL53L0X. 0x29
    -- corresponds to the default address for the Adafruit sensor.
    address       = address or 0x29,

    -- I2C polling timeout. Default of 500ms wait time before returning
    -- an error.
    timeout       = timeout or 500,

    -- VL53L0X stop variable. Internal. Do not use.
    stop_variable = 0
  }

  -- Meta table setup: first, set the metatable of 'o' to be 'self', which is
  -- the current object. This will cause lookups (`index` events) on 'o' to be
  -- forwarded to index events on `self` (AKA the vl53l0x object) when they
  -- cannot be found (e.g. `o.timeout` will not need to forward to `self` but
  -- `o:continuous` will). Second, set `self.__index` to point to `self`, which
  -- _actually_ specifies the index metamethod for the newly created object.
  setmetatable(o, self) -- set metatable of returned object
  self.__index = self   -- set metamethod of self

  -- Interrogate the attached sensor, and check the VL53L0X reference register
  -- '0xC0', which, upon entering SW Standby phase before configuration, has
  -- value 0xEE. Fail if it doesn't. Note that we can simply use _get from the
  -- constructed object to interrogate the device.
  --
  -- See VL53L0X Datasheet, section 3.2
  if not (o:_get(0xC0) == 0xEE) then
    return false, "no VL53L0X device (reg(0xC0) ~= OxEE) found"
  end
  return o
end

-- vl53l0x:init():
--
-- Initialize the attached VL53L0X sensor over I2C. This function MUST be called
-- before any others, after you are given a vl53l0x object from ${vl53l0x:new}.
--
-- This performs SPAD initialization, does default tuning, and sensor
-- calibration.
--
-- Note that sensor initialization takes perceivable time; about ~900ms in
-- practice on the Atom Development Board, before you can turn on any mode and
-- begin sampling.
--
-- This does not set a range measurement mode.
--
-- This function DOES NOT survive across power on/off events! The sensor
-- must be recalibrated upon every power-on.
--
-- Returns:
--
--   - `true` if initialization was successful.
--   - `false, reason` if initialization failed. `reason` is a string.
--
-- You are advised to wrap this in a call to `assert`, e.g.
-- `assert(vl53l0x:init())`
--
function vl53l0x:init()
  -- Initial setup of the sensor

  -- "Set I2C Standard Mode"
  self:_set(0x88, 0x00)

  -- Internal default settings
  self:_set(0x80, 0x01)
  self:_set(0xFF, 0x01)
  self:_set(0x00, 0x00)
  self.stop_variable = self:_get(0x91)
  self:_set(0x00, 0x01)
  self:_set(0xFF, 0x00)
  self:_set(0x80, 0x00)

  -- Disable SIGNAL_RATE_MSRC (bit 1) and SIGNAL_RATE_PRE_RANGE (bit 4) limit
  -- checks. 0x60 = MSRC_CONFIG_CONTROL
  self:_set(0x60, 0x12)

  -- Set the return signal rate limit check value in units of MCPS (mega
  -- counts per second): 0.25, as a 16-bit Q9.7 fixed point number
  -- 0x44 = FINAL_RANGE_CONFIG_MIN_COUNT_RATE_RTN_LIMIT
  self:rate_limit(0.25)

  self:_set(0x01, 0xFF) -- set 0x01 = SYSTEM_SEQUENCE_CONFIG

  -- Get the SPAD information
  self:_set(0x80, 0x01)
  self:_set(0xFF, 0x01)
  self:_set(0x00, 0x00)
  self:_set(0xFF, 0x06)
  self:_set(0x83, self:_get(0x83) | 0x04)
  self:_set(0xFF, 0x07)
  self:_set(0x81, 0x01)
  self:_set(0x80, 0x01)
  self:_set(0x94, 0x6B)
  self:_set(0x83, 0x00)

  local now = he.now()
  while self:_get(0x83) == 0x00 do
    if (self.timeout > 0 and (he.now() - now) > self.timeout) then
      return false
    end
    he.wait{time=he.now() + 1}
  end
  self:_set(0x83, 0x01)

  local spad_result = self:_get(0x92)
  self:_set(0x81, 0x00)
  self:_set(0xFF, 0x06)
  self:_set(0x83, self:_get(0x83) & ~0x04)
  self:_set(0xFF, 0x01)
  self:_set(0x00, 0x01)
  self:_set(0xFF, 0x00)
  self:_set(0x80, 0x00)

  -- 0xB0 = GLOBAL_CONFIG_SPAD_ENABLES_REF_0
  -- NOTE: string.unpack for an array returns an extra value at the end.
  -- remove it.
  local ref_spad_map = {self:_get(0xB0, "BBBBBB")}
  table.remove(ref_spad_map, 7)

  self:_set(0xFF, 0x01)
  self:_set(0x4F, 0x00) -- 0x4F = DYNAMIC_SPAD_REF_EN_START_OFFSET
  self:_set(0x4E, 0x2C) -- 0x4E = DYNAMIC_SPAD_NUM_REQUESTED_REF_SPAD
  self:_set(0xFF, 0x00)

  -- 12 is the first spad to enable
  local first_spad_to_enable = (((spad_result >> 7) & 0x01) == 1) and 12 or 0

  local spads_enabled = 0
  for i = 1,47 do
    local key = math.floor(i / 8) + 1
    if (i < first_spad_to_enable or spads_enabled == (spad_result & 0x7f)) then
      ref_spad_map[key] = ref_spad_map[key] & ~(1 << (i % 8))
    elseif ((ref_spad_map[key] >> (i % 8)) & 0x1) then
      spads_enabled = spads_enabled + 1
    end
  end

  -- 0xB0 = GLOBAL_CONFIG_SPAD_ENABLES_REF_0
  self:_set(0xB0, string.pack(
              "BBBBBB",
              ref_spad_map[1],
              ref_spad_map[2],
              ref_spad_map[3],
              ref_spad_map[4],
              ref_spad_map[5],
              ref_spad_map[6]),
            "c6")

  -- DefaultTuningSettings from vl53l0x_tuning.h
  self:_set(0xFF, 0x01)
  self:_set(0x00, 0x00)

  self:_set(0xFF, 0x00)
  self:_set(0x09, 0x00)
  self:_set(0x10, 0x00)
  self:_set(0x11, 0x00)
  self:_set(0x24, 0x01)
  self:_set(0x25, 0xFF)
  self:_set(0x75, 0x00)

  self:_set(0xFF, 0x01)
  self:_set(0x4E, 0x2C)
  self:_set(0x48, 0x00)
  self:_set(0x30, 0x20)

  self:_set(0xFF, 0x00)
  self:_set(0x30, 0x09)
  self:_set(0x54, 0x00)
  self:_set(0x31, 0x04)
  self:_set(0x32, 0x03)
  self:_set(0x40, 0x83)
  self:_set(0x46, 0x25)
  self:_set(0x60, 0x00)
  self:_set(0x27, 0x00)
  self:_set(0x50, 0x06)
  self:_set(0x51, 0x00)
  self:_set(0x52, 0x96)
  self:_set(0x56, 0x08)
  self:_set(0x57, 0x30)
  self:_set(0x61, 0x00)
  self:_set(0x62, 0x00)
  self:_set(0x64, 0x00)
  self:_set(0x65, 0x00)
  self:_set(0x66, 0xA0)
  he.wait{time=he.now() + 1} -- NB: please the scheduler god

  self:_set(0xFF, 0x01)
  self:_set(0x22, 0x32)
  self:_set(0x47, 0x14)
  self:_set(0x49, 0xFF)
  self:_set(0x4A, 0x00)

  self:_set(0xFF, 0x00)
  self:_set(0x7A, 0x0A)
  self:_set(0x7B, 0x00)
  self:_set(0x78, 0x21)

  self:_set(0xFF, 0x01)
  self:_set(0x23, 0x34)
  self:_set(0x42, 0x00)
  self:_set(0x44, 0xFF)
  self:_set(0x45, 0x26)
  self:_set(0x46, 0x05)
  self:_set(0x40, 0x40)
  self:_set(0x0E, 0x06)
  self:_set(0x20, 0x1A)
  self:_set(0x43, 0x40)

  self:_set(0xFF, 0x00)
  self:_set(0x34, 0x03)
  self:_set(0x35, 0x44)

  self:_set(0xFF, 0x01)
  self:_set(0x31, 0x04)
  self:_set(0x4B, 0x09)
  self:_set(0x4C, 0x05)
  self:_set(0x4D, 0x04)

  self:_set(0xFF, 0x00)
  self:_set(0x44, 0x00)
  self:_set(0x45, 0x20)
  self:_set(0x47, 0x08)
  self:_set(0x48, 0x28)
  self:_set(0x67, 0x00)
  self:_set(0x70, 0x04)
  self:_set(0x71, 0x01)
  self:_set(0x72, 0xFE)
  self:_set(0x76, 0x00)
  self:_set(0x77, 0x00)

  self:_set(0xFF, 0x01)
  self:_set(0x0D, 0x01)

  self:_set(0xFF, 0x00)
  self:_set(0x80, 0x01)
  self:_set(0x01, 0xF8)

  self:_set(0xFF, 0x01)
  self:_set(0x8E, 0x01)
  self:_set(0x00, 0x01)
  self:_set(0xFF, 0x00)
  self:_set(0x80, 0x00)

  -- Set interrupt config to "new sample ready"
  self:_set(0x0A, 0x04) -- 0x0A = SYSTEM_INTERRUPT_CONFIG_GPIO
  -- 0x84 = GPIO_HV_MUX_ACTIVE_HIGH
  self:_set(0x84, self:_get(0x84) & ~0x10)
  self:_set(0x0B, 0x01) -- 0x0B = SYSTEM_INTERRUPT_CLEAR

  local timing_budget_us = self:timing_budget()

  -- "Disable MSRC and TCC by default"
  -- MSRC = Minimum Signal Rate Check
  -- TCC = Target CentreCheck
  self:_set(0x01, 0xE8) -- 0x01 = SYSTEM_SEQUENCE_CONFIG

  -- "Recalculate timing budget"
  self:timing_budget(timing_budget_us)

  -- Calibrate
  self:_set(0x01, 0x01) -- 0x01 = SYSTEM_SEQUENCE_CONFIG
  -- VL53L0X_REG_SYSRANGE_MODE_START_STOP
  self:_set(0x00, 0x41)

  local now = he.now()
  he.wait{time=he.now() + 1}

  -- 0x13 = RESULT_INTERRUPT_STATUS
  while (self:_get(0x13) & 0x07) == 0 do
    if (self.timeout > 0 and (he.now() - now) > self.timeout) then
      return false
    end
    he.wait{time=he.now() + 1}
  end

  self:_set(0x0B, 0x01)
  self:_set(0x00, 0x00)

  -- Calibrate
  self:_set(0x01, 0x02) -- 0x01 = SYSTEM_SEQUENCE_CONFIG
  -- VL53L0X_REG_SYSRANGE_MODE_START_STOP
  self:_set(0x00, 0x01)

  local now = he.now()
  he.wait{time=he.now() + 1}

  -- 0x13 = RESULT_INTERRUPT_STATUS
  while (self:_get(0x13) & 0x07) == 0 do
    if (self.timeout > 0 and (he.now() - now) > self.timeout) then
      return false
    end
    he.wait{time=he.now() + 1}
  end

  self:_set(0x0B, 0x01)
  self:_set(0x00, 0x00)

  -- Restore config
  self:_set(0x01, 0xE8) -- 0x01 = SYSTEM_SEQUENCE_CONFIG

  return true
end

--------------------------------------------------------------------------------
-- SECTION: Public API - Reading range measurements

-- vl53l0x:range():
--
-- Read a distance/range value from the VL53L0X sensor. This function waits for
-- a measurement to be available, then reads it from the sensor. This wait is
-- controlled by the ${vl53l0x:new} timeout variable.
--
-- The measurement method (e.g. continuous vs single-shot range measurements)
-- is determined automatically.
--
-- The vl53l0x object MUST already be initialized by a call to ${vl53l0x:init}
-- before this function can be called.
--
-- Returns:
--
--   - `false`, if the function timed out while waiting for a range measurement
--     to be made available.
--   - A float value representing the range measurement, in millimeters, if a
--     value was successfully sampled.
--
function vl53l0x:range()
  -- One-shot mode requires reading the device similar to continuous mode,
  -- except the SYSRANGE_START register is set to SINGLESHOT first and
  -- we wait for the start bit to clear. Then we fall through to the
  -- same code path.
  if self:_get(0x00) == 0x00 then
    self:_set(0x80, 0x01)
    self:_set(0xFF, 0x01)
    self:_set(0x00, 0x00)
    self:_set(0x91, self.stop_variable)
    self:_set(0x00, 0x01)
    self:_set(0xFF, 0x00)
    self:_set(0x80, 0x00)

    -- 0x00 = SYSRANGE_START, 0x01 = VL53L0X_REG_SYSRANGE_MODE_SINGLESHOT
    self:_set(0x00, 0x01)

    -- Wait until start bit is cleared on SYSRANGE_START
    local now = he.now()
    while (self:_get(0x01) & 0x01) ~= 0 do
      if (self.timeout > 0 and (he.now() - now) > self.timeout) then
        return false
      end
      he.wait{time=he.now()+1}
    end

    -- Fall through to the same path as for continuous reads
  end

  local now = he.now()

  -- 0x13 = RESULT_INTERRUPT_STATUS
  while (self:_get(0x13) & 0x07) == 0 do
    if (self.timeout > 0 and (he.now() - now) > self.timeout) then
      return false
    end
    he.wait{time=he.now()+1}
  end

  -- assumptions: Linearity Corrective Gain is 1000 (default)
  -- fractional ranging is not enabled. 0x1E = RESULT_RANGE_STATUS + 10
  local range = self:_get(0x1E, ">I2")
  self:_set(0x0B, 0x01) -- 0xB0 = SYSTEM_INTERRUPT_CLEAR
  return range
end

--------------------------------------------------------------------------------
-- SECTION: Public API - (Timed) Continuous range measurement

-- vl53l0x:continuous(period):
--
-- Control VL53L0X continuous mode. The ${period} argument specifies what
-- action is taken.
--
-- The vl53l0x object MUST already be initialized by a call to ${vl53l0x:init}
-- before this function can be called.
--
-- If ${period} is `true`, this function turns on continuous ranging mode, which
-- continuously takes measurements as frequently as possible. This function does
-- not allow the sensor to return to SW Standby mode.
--
-- If ${period} is an intger value, then this function turns on timed-continuous
-- ranging mode. In this mode, the sensor takes range measurements at the
-- specified interval continuously and enters a wait period in between. During
-- this time, the application can sample the range measurement. Timed continuous
-- ranging allows you to save battery, but does not return the sensor to SW
-- standby mode.
--
-- If ${period} is `nil` or `false`, then continuous ranging mode is turned off,
-- and measurements are stopped. If the request occurs while a measurement is
-- being taken, then the measurement is completed before stopping. If the stop
-- command occurs in the middle of an inter-measurement standby period (i.e.
-- inbetween timed range measurements), then it stops immediately. In this case,
-- this function will wait until the measurements have stopped, or until the
-- given timeout specified in ${vl53l0x:new} occurs.
--
-- Returns:
--
--   - `true` if the sensor successfully entered or exited continuous mode
--   - `false` if the sensor couldn't stop continuous mode and wait for
--     the final measurement in the given timeout window.
--
function vl53l0x:continuous(period)

  -- turn on continuous ranging mode
  if period then
    self:_set(0x80, 0x01)
    self:_set(0xFF, 0x01)
    self:_set(0x00, 0x00)
    self:_set(0x91, self.stop_variable)
    self:_set(0x00, 0x01)
    self:_set(0xFF, 0x00)
    self:_set(0x80, 0x00)

    -- enable continuous back-to-back mode if no period is specified
    if period == true then
      -- 0x00 = SYSRANGE_START, 0x02 = VL53L0X_REG_SYSRANGE_MODE_BACKTOBACK
      self:_set(0x00, 0x02)
      return true
    end

    -- otherwise, enable continuous timed mode, by setting the
    -- inter-measurement standby period in milliseconds
    local calibrate = self:_get(0xF8, ">I2") -- 0xF8 = OSC_CALIBRATE_VAL

    -- 0x04 = SYSTEM_INTERMEASUREMENT_PERIOD
    self:_set(0x04, (calibrate ~= 0)
                and (period * calibrate)
                or  period,
              ">I4")
    -- VL53L0X_SetInterMeasurementPeriodMilliSeconds() end

    -- 0x00 = SYSRANGE_START, 0x04 = VL53L0X_REG_SYSRANGE_MODE_TIMED
    self:_set(0x00, 0x04)

    return true
  end
  -- otherwise: turn off continuous ranging mode

  -- 0x00 = SYSRANGE_START, 0x01 = VL53L0X_REG_SYSRANGE_MODE_SINGLESHOT
  self:_set(0x00, 0x01)

  self:_set(0xFF, 0x01)
  self:_set(0x00, 0x00)
  self:_set(0x91, 0x00)
  self:_set(0x00, 0x01)
  self:_set(0xFF, 0x00)

  local ending = false

  -- We have to poll now for the stop signal
  local now = he.now()
  while not ending do
    self:_set(0xFF, 0x01)
    ending = self:_get(0x04) == 0 -- 0x04 = SYSTEM_INTERMEASUREMENT_PERIOD
    self:_set(0xFF, 0x00)

    if ending then
      self:_set(0x80, 0x01)
      self:_set(0xFF, 0x01)
      self:_set(0x00, 0x00)
      self:_set(0x91, self.stop_variable)
      self:_set(0x00, 0x01)
      self:_set(0xFF, 0x00)
      self:_set(0x80, 0x00)
    else
      if (self.timeout > 0 and (he.now() - now) > self.timeout) then
        return false
      end
    end

    he.wait{time=he.now() + 1}
  end

  return true
end

--------------------------------------------------------------------------------
-- SECTION: Public API - VCSEL Pulse Period

-- vl53l0x:vcsel_pulse(typ, pclks):
--
-- Set or retrieve the VCSEL Pulse Period for the VL53L0X, for a given period
-- type ${typ}. Higher values indicate a faster pulse period, resulting
-- in increased sensor range potential.
--
-- The ${typ} parameter MUST be non-`nil` integer value. The ${typ} MUST be
-- either the constant value `0x01` or `0x02`, depending on if you want the
-- pre-range or final-range pulse period, respectively.
--
-- If ${pclks} is `nil`, or unspecified, the current pulse period for the
-- specified period ${typ} is retrieved and given back to the user in units of
-- PCLKs. If ${pclks} is non-`nil`, it must be a constant integer value, and the
-- pulse period for the period ${typ} is set to ${pclks}.
--
-- There are only a few valid ranges for the pulse periods. They are:
--
--   - Pre range:   Any EVEN number from 12 to 18
--   - Final range: Any EVEN number from  8 to 14
--
-- The default pulse periods after ${vl53l0x:init} are 14 and 10 for the
-- pre range and final range periods, respectively.
--
-- Returns:
--
--   - `pclk`, an integer value, if the current pulse period for ${typ}
--     was requested.
--   - `true` if the pulse period ${typ} was successfully set to ${pclks}
--   - `false, reason` if the period could not be successfully retrieved or set
--
function vl53l0x:vcsel_pulse(typ, pclks)

  -- 0x01 is PRE_RANGE_CONFIG_VCSEL_PERIOD
  if typ == 0x01 then
    -- fast case: do not need to set, only retrieve
    -- 0x50 = PRE_RANGE_CONFIG_VCSEL_PERIOD
    if not pclks then return ((self:_get(0x50) + 1) << 1) end

    -- otherwise: make sure the input is legitimate so we can
    -- set the value after this
    if not (pclks > 11 and pclks < 19 and (pclks % 2) == 0) then
      return false, "invalid pre range PCLK setting"
    end

  -- 0x02 is FINAL_RANGE_CONFIG_VCSEL_PERIOD
  elseif typ == 0x02 then
    -- fast case: do not need to set, only retrieve
    -- 0x70 = FINAL_RANGE_CONFIG_VCSEL_PERIOD
    if not pclks then return ((self:_get(0x70) + 1) << 1) end

    -- otherwise: make sure the input is legitimate so we can
    -- set the value after this
    if not (pclks > 7 and pclks < 15 and (pclks % 2) == 0) then
      return false, "invalid final range PCLK setting"
    end
  else
    -- bottom out with an error
    return false, "invalid VCSEL period: must be 0x01 or 0x02 (PRE/FINAL RANGE)"
  end

  -- otherwise, if we got to this point, we set pulse period
  -- TODO FIXME: implement
  return false, "Not Invented Here"
end

--------------------------------------------------------------------------------
-- SECTION: Public API - Signal Rate Limit

-- vl53l0x:rate_limit(limit_mcps):
--
-- Set or retrieve the VL53L0X signal rate limit, representing the amplitude of
-- the signal reflected from the target and detected by the device, in "Mega
-- Counts Per Second" (MCPS).
--
-- If ${limit_mcps} is unspecified or `nil`, the current signal rate limit
-- is returned. If ${limit_mcps} is non-`nil`, the current rate limit is set
-- to the specified float value in MCPS.
--
-- If the user attempts to set a rate limit, ${limit_mcps} MUST be above zero,
-- and a float value below 511.99. Otherwise, this function will fail.
--
-- Setting this limit presumably determines the minimum measurement necessary
-- for the sensor to report a valid reading. Setting a lower limit increases the
-- potential range of the sensor but also seems to increase the likelihood of
-- getting an inaccurate reading because of unwanted reflections from objects
-- other than the intended target.
--
-- Defaults to 0.25 MCPS after ${vl53l0x:init}.
--
-- NOTE: The usual caveats about floating point apply. Namely, imprecise float
-- values converted to/from Q9.7 format will lose some precision, meaning you
-- may not exactly get back the same float that you set, when asked.
--
-- Returns:
--
--   - `limit`, a float value, if the current rate limit was requested, in MCPS
--   - `true` if the rate limit was successfully set to ${limit_mcps}, in MCPS
--   - `false, reason` if the limit could not be successfully retrieved or set
--
function vl53l0x:rate_limit(limit_mcps)

  -- in this case, set the rate limit
  if limit_mcps then
    if (limit_mcps < 0 or limit_mcps > 511.99) then
      return false, "invalid rate limit"
    end

    -- Okay... Annoyingly, the signal rate limit is a floating point number
    -- encoded as a 16-bit number in Q9.7 format (Q9.7 == "9+7 total bits, 9
    -- bits for the integral, 7 bits for the fractional"). We can retrieve that
    -- just fine, but Lua can't _encode_ an imprecise decimal point to a 16 bit
    -- big-endian word easily. We use a trick from the Adafruit library, which
    -- is to first convert the float to a truncated Q16.16 number (by
    -- multiplying by 65536 and floor'ing) and then convert that to Q9.7.

    -- 0x44 = FINAL_RANGE_CONFIG_MIN_COUNT_RATE_RTN_LIMIT
    return self:_set(0x44, (math.floor(limit_mcps * 65536) >> 9) & 0xFFFF, ">H")

  -- otherwise, get the rate limit
  else
    -- 0x44 = FINAL_RANGE_CONFIG_MIN_COUNT_RATE_RTN_LIMIT
    return self:_get(0x44, ">H") / (1 << 7)
  end
end

--------------------------------------------------------------------------------
-- SECTION: Public API - Measurement timing budget management

-- vl53l0x:timing_budget(budget_us):
--
-- Set or retrieve the VL53L0X timing budget, which is the time allowed for a
-- single measurement; the ST API and this library take care of splitting the
-- timing budget among the sub-steps in the ranging sequence. A longer timing
-- budget allows for more accurate measurements. Increasing the budget by a
-- factor of N decreases the range measurement standard deviation by a factor of
-- `sqrt(N)`.
--
-- If ${budget_us} is `nil` or unspecified, the current timing budget is
-- returned in microseconds. If ${budget_us} is non-`nil`, the timing budget is
-- set to the specified float value in microseconds.
--
-- Defaults to ~33 milliseconds on startup; the minimum is 20 ms.
--
-- Returns:
--
--   - `budget`, a float value, if the current budget was requested, in
--     microseconds
--   - `true` if the budget was successfully set to ${budget_us}, in
--     microseconds
--   - `false` if the budget could not be successfully retrieved or set
--
function vl53l0x:timing_budget(budget_us)
  local sequence_config = self:_get(0x01)

  local timeout_mclks2ms = function(timeout_period_mclks, vcsel_period_pclks)
    local macro_period_ns
      = math.floor(((2304 * vcsel_period_pclks * 1655) + 500) / 1000)

    return math.floor(((timeout_period_mclks * macro_period_ns) + (macro_period_ns / 2)) / 1000)
  end

  local ss_timeouts_pre_range_vcsel_period_pclks = self:vcsel_pulse(0x01)
  local ss_timeouts_msrc_dss_tcc_mclks = self:_get(0x46)+1
  local ss_timeouts_msrc_dss_tcc_us
    = timeout_mclks2ms(
      ss_timeouts_msrc_dss_tcc_mclks,
      ss_timeouts_pre_range_vcsel_period_pclks)

  local ss_timeouts_pre_range_mclks = self:_get(0x51, ">I2")
  ss_timeouts_pre_range_mclks = (ss_timeouts_pre_range_mclks &
      0x00FF << ((ss_timeouts_pre_range_mclks & 0xFF00) >> 8)) + 1

  local ss_timeouts_pre_range_us =
    timeout_mclks2ms(
      ss_timeouts_pre_range_mclks,
      ss_timeouts_pre_range_vcsel_period_pclks)

  local ss_timeouts_final_range_vcsel_period_pclks = self:vcsel_pulse(0x02)
  local ss_timeouts_final_range_mclks = self:_get(0x71, ">I2")
  ss_timeouts_final_range_mclks = (ss_timeouts_final_range_mclks &
      0x00FF << ((ss_timeouts_final_range_mclks & 0xFF00) >> 8)) + 1

  if (sequence_config >> 6) & 0x1 then
    ss_timeouts_final_range_mclks =
      ss_timeouts_final_range_mclks - ss_timeouts_pre_range_mclks
  end

  local ss_timeouts_final_range_us =
    timeout_mclks2ms(
      ss_timeouts_final_range_mclks,
      ss_timeouts_final_range_vcsel_period_pclks)

  -- We need to set the timing budget, in this case...
  if budget_us then
    if budget_us < 20000 then
      return false
    end

    local used_budget_us = 2280 -- 1320 + 960

    -- tcc
    if (sequence_config >> 4) & 0x1 then
      used_budget_us =
        used_budget_us + (ss_timeouts_msrc_dss_tcc_us + 590)
    end

    -- dss
    if (sequence_config >> 3) & 0x1 then
      used_budget_us
        = used_budget_us + (2 * (ss_timeouts_msrc_dss_tcc_us + 690))

    -- msrc
    elseif (sequence_config >> 2) & 0x1 then
      used_budget_us
        = used_budget_us + (ss_timeouts_msrc_dss_tcc_us + 660)
    end

    -- pre_range
    if (sequence_config >> 6) & 0x1 then
      used_budget_us
        = used_budget_us + (ss_timeouts_pre_range_us + 660)
    end

    -- final_range
    if (sequence_config >> 7) & 0x1 then

      -- "Note that the final range timeout is determined by the timing budget
      -- and the sum of all other timeouts within the sequence. If there is no
      -- room for the final range timeout, then an error will be set. Otherwise
      -- the remaining time will be applied to the final range."
      if (used_budget_us + 550) > budget_us then
        -- requested timeout too big
        return false
      end

      -- "For the final range timeout, the pre-range timeout must be added. To
      -- do this both final and pre-range timeouts must be expressed in macro
      -- periods MClks because they have different vcsel periods."
      local timeout_ms2mclks = function(timeout_period_us, vcsel_period_pclks)
        local macro_period_ns
          = math.floor(((2304 * vcsel_period_pclks * 1655) + 500) / 1000)

        return math.floor(((timeout_period_us * 1000) + (macro_period_ns / 2)) / macro_period_ns)
      end

      local final_range_timeout_mclks = timeout_ms2mclks(
        budget_us - (used_budget_us + 550),
        ss_timeouts_final_range_vcsel_period_pclks)

      if (sequence_config >> 6) & 0x1 then
        final_range_timeout_mclks = final_range_timeout_mclks + ss_timeouts_pre_range_mclks
      end

      if final_range_timeout_mclks > 0 then
        local ls_byte = final_range_timeout_mclks - 1;
        local ms_byte = 0

        while ((ls_byte & 0xFFFFFF00) > 0) do
          ls_byte = ls_byte >> 1;
          ms_byte = ms_byte + 1;
        end

        self:_set(0x71, (ms_byte << 8) | (ls_byte & 0xFF), ">I2")
      else
        self:_set(0x71, 0, ">I2")
      end
    end
    return true

  -- Otherwise: get the budget
  else
    local budget_us = 2870 -- 1910 + 960

    -- tcc
    if (sequence_config >> 4) & 0x1 then
      budget_us = budget_us + (ss_timeouts_msrc_dss_tcc_us + 590)
    end

    -- dss
    if (sequence_config >> 3) & 0x1 then
      budget_us = budget_us + (2 * (ss_timeouts_msrc_dss_tcc_us + 960))
      -- msrc
    elseif (sequence_config >> 2) & 0x1 then
      budget_us = budget_us + (ss_timeouts_msrc_dss_tcc_us + 660)
    end

    -- pre_range
    if (sequence_config >> 6) & 0x1 then
      budget_us = budget_us + (ss_timeouts_pre_range_us + 660)
    end

    -- final_range
    if (sequence_config >> 7) & 0x1 then
      budget_us = budget_us + (ss_timeouts_final_range_us + 550)
    end

    return budget_us
  end
end

--------------------------------------------------------------------------------
-- SECTION: Private API - Primitive Utilities

-- These should all be part of he.i2c in the future or something, perhaps?

-- vl53l0x:_get(reg, fmt):
--
-- Read the VL53L0X register ${reg} and return it in the given format specified
-- by ${fmt}, ${reg} CAN NOT be `nil`.
--
-- The format value ${fmt} is the same format used by ${string.unpack}, and the
-- returned value is in the form specified by ${fmt}. If ${fmt} is `nil` or
-- left unspecified, the default format value is "B" for reading bytes. This
-- makes the common case of reading bytes from I2C very easy and reduces
-- code size for this common case.
--
-- Returns:
--
--   - an arbitrary value `x`, read from the I2C address, in the form specified
--     by ${fmt} (see the Lua documentation for ${string.unpack} for more).
--   - `false, reason` if reading the register failed. `reason` is a string.
--
function vl53l0x:_get(reg, fmt)
  -- number of bytes to read based on the pack string
  local status, buffer =
    he.i2c.txn(he.i2c.tx(self.address, reg),
               he.i2c.rx(self.address, string.packsize(fmt or "B")))
  if not status then
    return false, "failed to get value from device"
  end

  return string.unpack(fmt or "B", buffer)
end

-- vl53l0x:_set(reg, value, fmt)
--
-- Write the Lua term ${value} to the VL53L0X I2C register ${reg}, specified by
-- the format string ${fmt}. Both ${reg} and ${value} CAN NOT be `nil`.
--
-- The format value ${fmt} is the same format used by ${string.pack}, and is
-- used to serialize the Lua term ${value} before writing. If ${fmt} is `nil` or
-- left unspecified, the default value is "B" for writing bytes. This makes the
-- common case of writing bytes to registers easy and reduces code size for this
-- common case.
--
-- Returns:
--
--   - `true` if the value was written.
--   - `false, reason` if the value could not be written. `reason` is a string.
--
-- NOTE: In theory you should wrap calls to this function with `assert`, but in
-- practice this will dramatically increase code size and reduce speed to
-- impractical levels for most sensors. You are responsible for validing I2C
-- device configuration, post-write, in whatever way you must. (You can
-- alternatively wrap this in another function to at least reduce size
-- overhead.)
--
function vl53l0x:_set(reg, value, fmt)
  return he.i2c.txn(
    he.i2c.tx(self.address, reg, string.pack(fmt or "B", value)))
end

--------------------------------------------------------------------------------
-- SECTION: Finish - Return vl53l0x module object

return vl53l0x

-- Local Variables:
-- mode: lua-mode
-- fill-column: 80
-- indent-tabs-mode: nil
-- c-basic-offset: 2
-- buffer-file-coding-system: utf-8-unix
-- End:

-- vl53l0x.lua ends here
