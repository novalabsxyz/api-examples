local SAMPLE_INTERVAL = 60000 -- 1 minute

-- number of samples to bundle up locally before sending.
-- if the device loses power before submitting these samples
-- then they are lost forever. too many samples may reduce
-- memory usage, require he.wait calls, and increases the
-- amount of data you will lose.
local SAMPLE_BUNDLE = 10

local lps22hb = require('lps22hb')
local sensor  = assert(lps22hb:new())

local tbl = {}
local idx = 1

local now = he.now()
while true do
    local pressure = assert(sensor:read_pressure())
    local temperature = assert(sensor:read_temperature())

    tbl[idx] = {now, pressure, temperature}
    print("stored temporary sample #"..idx)

    if idx == SAMPLE_BUNDLE then
      print("sending "..SAMPLE_BUNDLE.." stored samples")
      for i=1,SAMPLE_BUNDLE do
        print(tbl[i][1],tbl[i][2],tbl[i][3])
        he.send("p", tbl[i][1], "f", tbl[i][2])
        he.send("t", tbl[i][1], "f", tbl[i][3])

        -- if we bundle a lot of samples, just wait for a tiny
        -- bit so the scheduler is happy
        if (i % 10) == 0 then
          he.wait{time=he.now()+1}
        end
      end
      tbl = {}
      idx = 1
    else
      idx = idx + 1
    end

    now = he.wait{time=now + SAMPLE_INTERVAL}
end
