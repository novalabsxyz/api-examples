--------------------------------------------------------------------------------
-- VL53L0X LiDAR sampling module. See 'License' in vl53l0x.lua for Copyright.

-- Usage:
--
-- To upload to your board, and take samples continuously:
--
--     $ helium-script -u -p -m main.lua vl53l0x.lua
--
-- Once you have samples being sent upstream, you can read them out in real time
-- and format them nicely. The following example uses 'jq' and 'figlet':
--
--     $ export SID=<helium sensor UUID>
--     $ helium --format json sensor timeseries live $SID --port proximity \
--       | jq -c --unbuffered -r --stream \
--           'fromstream(1|truncate_stream(inputs)).value' \
--       | (while read x; do clear; figlet -f big "${x} in"; done)
--
-- This module has enough memory available to be used in semi-hosting mode as
-- well. This will give you diagnostics and allows testing without the radio
-- (which will use more power, memory, and battery). Run:
--
--     $ helium-script -m main.lua vl53l0x.lua
--     VL53L0X initialized (continuous @ 500ms); took 955.0ms
--     proximity at 1489424599983.0 is 5.9055118110236in
--     proximity at 1489424600483.0 is 5.8661417322835in
--     proximity at 1489424600983.0 is 5.9055118110236in
--     proximity at 1489424601483.0 is 5.9055118110236in
--     ...
--
-- You can also use this library interactively at the REPL:
--
--     $ helium-script -i vl53l0x.lua
--     helium-script 2.0.1
--     > vl53l0x = require('vl53l0x')
--     > sensor = assert(vl53l0x:new(500))
--     > assert(sensor:init())
--     true
--     > assert(sensor:start_continuous())
--     true
--     > sensor:read_range() / 25.4
--     5.8267716535433
--     > sensor:read_range() / 25.4
--     5.9055118110236
--     > ^D
--
--     $
--
-- Configure `SAMPLE_INTERVAL` to control how frequently the sensor is sampled
-- for range data. Configure `SAMPLE_PORT` for the port name. Values are always
-- submitted as floats.
--
-- You can save some extra memory by removing the diagnostic (startup time) code
-- as well if you're willing to only rely on the radio and he.send. Further
-- savings can be had by always uploading to device (although this is more
-- difficult, as its and harder to debug crashes).
--
-- A further optimization for power use may be to buffer samples in memory and
-- bulk submit multiple samples after a small period; this will cause the radio
-- to be less chattery, at the expense of possible, full radio wakeups (e.g.
-- power-on) on occasion, depending on the sample/submission rate.

--------------------------------------------------------------------------------
-- Configuration

-- Sampling interval for continuous mode. In milliseconds.
local SAMPLE_INTERVAL = 500

-- Port to submit data to with he.send. Submitted as a float.
local SAMPLE_PORT = "proximity"

--------------------------------------------------------------------------------
-- Sensor setup

local memstart = collectgarbage("count")
local begin    = he.now()
local vl53l0x  = require('vl53l0x')
local sensor   = assert(vl53l0x:new())   -- 500ms timeout for I2C polling
assert(sensor:init())                    -- calibrate/initialize
assert(sensor:continuous(true))          -- continuous, non-timed ranging
local now      = he.now()-begin
local memused  = collectgarbage("count")-memstart

--------------------------------------------------------------------------------
-- Main loop

print("VL53L0X ok (continuous @ "..SAMPLE_INTERVAL.."ms), "..
        "took "..now.."ms; mem used = "..memused.."kb")

local now = he.now() -- reset for more accurate timestamp, post initialization
while true do
  local range = sensor:range() / 25.4 -- millimeters to inches
  print("proximity at "..now.." is "..range.."in")
  he.send(SAMPLE_PORT, now, "f", range)
  now = he.wait{time=now + SAMPLE_INTERVAL}
end
