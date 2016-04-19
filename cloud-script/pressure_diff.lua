local Input  = require "input"
local Output = require "output"

-- Input / output
local A = Input.sensor "5a65f622-9d91-4117-934e-0f7afac86fff"
local B = Input.sensor "6a65f622-9d91-4117-934e-0f7afac86fff"
local C = Output.sensor("7a65f622-9d91-4117-934e-0f7afac86fff", "diff_p")

-- State
local lastA
local lastB


local function callback(x)

  print("In the callback")

  -- Remember the most recent values
  if     x.source == A then lastA = x
  elseif x.source == B then lastB = x
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
