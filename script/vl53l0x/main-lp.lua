--------------------------------------------------------------------------------
-- VL53L0X LiDAR low-power example. See 'License' in vl53l0x.lua for Copyright.

-- This example demonstrates a 'low-power' example of the VL53L0X module. The
-- sensor takes one-shot readings, and is immediately powered off, to be
-- re-initialized after wakeup. Furthermore, samples are bundled in order to
-- limit radio and battery usage further.

--------------------------------------------------------------------------------
-- Configuration

-- Sampling interval for one-shot measurements. In milliseconds.
local SAMPLE_INTERVAL = 10000 -- 10 seconds

-- Port to submit data to with he.send. Submitted as a float.
local SAMPLE_PORT = "proximity"

-- Number of samples to bundle up locally before sending. If the device loses
-- power before submitting these samples then they are lost forever. Too many
-- samples may reduce memory usage, require he.wait calls, and increases the
-- amount of data you will lose.
local SAMPLE_BUNDLE = 3

--------------------------------------------------------------------------------
-- Sensor setup

local queue   = require('queue')
local vl53l0x = require('vl53l0x')
local sensor  = assert(vl53l0x:new()) -- 500ms timeout for I2C polling

assert(sensor:init())

--------------------------------------------------------------------------------
-- Main loop

print("VL53L0X ok (single-shot, low power @ "..SAMPLE_INTERVAL.."ms)")

local q = queue:new(SAMPLE_BUNDLE, {{SAMPLE_PORT,"f"}})
while true do
  -- sample, and turn off power as soon as possible
  q:add(he.now(), {sensor:range() / 25.4}) -- millimeters to inches
  he.power_set(false)

  -- wait, turn the device back on, and reinitialize it. reinitialization and
  -- calibration will take some time anyway. use the current timestamp for the
  -- wait interval; radio and sensor invocations may have taken some time...
  he.wait{time=he.now() + SAMPLE_INTERVAL}

  he.power_set(true)
  assert(sensor:init())
end
