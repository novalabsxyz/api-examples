local Input  = require "input"
local Output = require "output"

-- Input / output
local A = Input.sensor "5a65f622-9d91-4117-934e-0f7afac86fff"
local B = Output.webhook "foo.com/alert"


local function callback(x)
  print("In the callback")

  if x.port == 'm' and x.value then
    B:emit {value = x}
  end
end

return {
  inputs = {A},
  outputs = {B},
  callback = callback,
}
