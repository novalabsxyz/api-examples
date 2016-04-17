local Input  = require "input"
local Output = require "output"

-- Input / output
local A = Input.sensor "5a65f622-9d91-4117-934e-0f7afac86fff"
local B = Output.webhook "foo.com/alert"

-- Parameters
local IDLE_THRESHOLD = 5 * 60

-- State
local idle_time = 0   -- how long has there been no movement?
local last_light      -- most recent light reading
local last_reading    -- most recent reading (any port)


local function light_on(val)
   return val > 10   -- made-up threshold
end

local function callback(x)

  print("In the callback")

  -- Update state

  if x.port == "m" and x.value then  -- there was movement
    idle_time = 0
  else
    if last_reading then
      local elapsed = x.timestamp - last_reading.timestamp
      idle_time = idle_time + elapsed
    end
  end

  if (x.port == "l") then
    last_light = x
  end

  last_reading = x  -- must come after updating `idle_time`


  -- Bail if no light readings yet
  if last_light==nil then return end

  local should_notify =
    idle_time > IDLE_THRESHOLD        -- no movement for too long
    and light_on(last_light.value)

  if should_notify then
    local info = {
      idle_duration      = idle_time,
      last_light_reading = last_light,
      occurrence_time    = x.timestamp,
    }

    -- This is a webhook, so `timestamp` is not needed. If the webhook
    -- cares about any timestamps, put them in the `value` argument.
    --
    B:emit { value = info }
  end
end

return {
  inputs = {A},
  outputs = {B},
  callback = callback,
}
