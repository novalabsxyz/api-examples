local A = "5a65f622-9d91-4117-934e-0f7afac86fff"

local function mk(port,t,v)
  return {
    value = v,
    source = {sensor = A},
    port = port,
    timestamp = t * 60,
  }
end

local function addcreated(t)
  for i,x in ipairs(t) do
    t[i].meta = {created = 60*i+600}
  end
  return t
end

return addcreated {
  mk("m", 0, false),
  mk("l", 2, 50),
  mk("m", 4, false),
  mk("m", 6, false),

  -- choose your own ending
  mk("m", 7, true),   -- movement happens
  --mk("m", 7, false),  -- no movement
  --mk("l", 7, 0),      -- light turns off
  --mk("l", 7, 50),     -- light stays on
}
