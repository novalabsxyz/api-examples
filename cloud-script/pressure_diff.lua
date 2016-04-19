local Input  = require "input"
local Output = require "output"

-- Input / output
local idA = "5a65f622-9d91-4117-934e-0f7afac86fff"
local idB = "6a65f622-9d91-4117-934e-0f7afac86fff"
local idC = "7a65f622-9d91-4117-934e-0f7afac86fff"
local A = Input.sensor(idA)
local B = Input.sensor(idB)
local C = Output.sensor(idC,"diff_p")

-- State
local lastA
local lastB


local function callback(x)

  print("In the callback")

  -- Remember the most recent values
  local src = x.source.sensor
  if src == idA then
    lastA = x
  elseif src == idB then
    lastB = x
  end

  -- Proceed only if we've heard from both previously
  if lastA==nil or lastB==nil then return end

  local diff = lastA.value - lastB.value
  local occurred = math.max(lastA.timestamp, lastB.timestamp)
  C:emit {value = diff, timestamp = occurred}
end

return {
  inputs = {A,B},
  outputs = {C},
  callback = callback,
}
