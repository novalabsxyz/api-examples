--------------------------------------------------------------------------------
-- VL53L0X LiDAR interrupt example. See 'License' in vl53l0x.lua for Copyright.

-- This example demonstrates the GPIO interrupt facilities of the VL53L0X
-- module. The board sits in a wait loop while the sensor is in timed continuous
-- mode, and interrupts occur on int0 whenever readings are ready to be sampled.
-- Samples are buffered up into a queue before sending to help conserve power.

--------------------------------------------------------------------------------
-- Configuration

-- Sampling interval for continuous mode. In milliseconds.
local SAMPLE_INTERVAL = 10000 -- 10 seconds

-- Port to submit data to with he.send. Submitted as a float.
local SAMPLE_PORT = "proximity"

-- Number of samples to bundle up locally before sending. If the device loses
-- power before submitting these samples then they are lost forever. Too many
-- samples may reduce memory usage, require he.wait calls, and increases the
-- amount of data you will lose.
local SAMPLE_BUNDLE = 5

--------------------------------------------------------------------------------
-- Sensor setup

local queue   = require('queue')
local vl53l0x = require('vl53l0x')
local sensor  = assert(vl53l0x:new(5000)) -- 5s timeout for I2C polling

assert(sensor:init())                     -- calibrate/initialize
assert(sensor:continuous(2000))           -- 2s continuous timed ranging
he.interrupt_cfg("int0", "f", 10)         -- wake on INT0 fall (10ms debounce)

--------------------------------------------------------------------------------
-- Main loop

print("Helium Script Interrupt example @ "..SAMPLE_INTERVAL.."ms")

local q           = queue:new(SAMPLE_BUNDLE, {{SAMPLE_PORT,"f"}})
local interrupted = nil
local events      = nil
local now         = he.now()
while true do
  -- sample and buffer the event. after sampling, the sensor will go into
  -- IM standby mode to use less power, and interrupt us when a new sample
  -- is ready.
  q:add(now, {sensor:range() / 25.4}) -- millimeters to inches

  -- wait for the specified interval, and wake when interrupts come in. we're
  -- expecting them, so assert the right configuration on the event table.
  now, interrupted, events = he.wait{time=now + SAMPLE_INTERVAL}
  assert(interrupted and (events.int0 == "f"))
end
