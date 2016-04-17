local A = "5a65f622-9d91-4117-934e-0f7afac86fff"
local B = "6a65f622-9d91-4117-934e-0f7afac86fff"


local function mk(id,t,v)
  return {
    value = v,
    source = {sensor = id},
    port = "p",
    timestamp = t,
  }
end

local function addcreated(t)
  for i,x in ipairs(t) do
    t[i].meta = {created = i+10}
  end
  return t
end

return addcreated {
  mk(A, 2, 100),
  mk(B, 4, 150),
  mk(B, 5, 130),
  mk(A, 6, 140),
  mk(A, 7, 140),
}
