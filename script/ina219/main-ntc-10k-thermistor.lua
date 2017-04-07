--- Example main loop for the Helium Analog Extension Board
--
-- Requires helium-script 2.x and the ina219.lua library. This main
-- loop uses the 'thermistor' mode of the Analog Extension board. The
-- mode jumper is set to 'Therm' and a NTC 10k thermistor is connected across
-- the V(T) screw terminals. The resistance/temperature curve is for a
-- US Sensors Thermistor (ussensors.com). In this jumper mode, the thermistor
-- is coupled with a 10k resistor to form a voltage divider.
--
-- @script ina219.main
-- @license MIT
-- @copyright 2017 Helium Systems, Inc.
-- @usage
-- # In semi-hosted mode over USB
-- $ helium-script -m main-NTC-10k-thermistor.lua ina219.lua
--
-- # Upload to device over USB
-- $ helium-script -up -m main-NTC-10k-thermistor.lua ina219.lua

ina219 = require("ina219")

--- Sampling interval (Set to 10 seconds).
SAMPLE_INTERVAL = 10000 -- 10 seconds

-- resistance/temperature lookup table
LOOKUP = {
    [336479] = -40, [314904] = -39, [294848] = -38, [276194] = -37, [258838] = -36,
    [242681] = -35, [227632] = -34, [213610] = -33, [200539] = -32, [188349] = -31,
    [176974] = -30, [166356] = -29, [156441] = -28, [147177] = -27, [138518] = -26,
    [130421] = -25, [122847] = -24, [115759] = -23, [109122] = -22, [102906] = -21,
    [97081] = -20, [91621] = -19, [86501] = -18, [81698] = -17, [77190] = -16,
    [72957] = -15, [68982] = -14, [65246] = -13, [61736] = -12, [58434] = -11,
    [55329] = -10, [52407] = -9, [49656] = -8, [47066] = -7, [44626] = -6,
    [42327] = -5, [40159] = -4, [38115] = -3, [36187] = -2, [34368] = -1,
    [32650] = 0, [31029] = 1, [29498] = 2, [28052] = 3, [26685] = 4,
    [25392] = 5, [24170] = 6, [23013] = 7, [21918] = 8, [20882] = 9,
    [19901] = 10, [18971] = 11, [18090] = 12, [17255] = 13, [16463] = 14,
    [15712] = 15,  [14999] = 16,  [14323] = 17, [13681] = 18, [13072] = 19,
    [12493] = 20, [11942] = 21, [11419] = 22, [10922] = 23, [10450] = 24,
    [10000] = 25, [9572] = 26, [9165] = 27, [8777] = 28, [8408] = 29,
    [8057] = 30, [7722] = 31, [7402] = 32, [7098] = 33, [6808] = 34,
    [6531] = 35, [6267] = 36, [6015] = 37, [5775] = 38, [5545] = 39,
    [5326] = 40, [5117] = 41, [4917] = 42, [4725] = 43, [4543] = 44,
    [4368] = 45, [4201] = 46, [4041] = 47, [3888] = 48, [3742] = 49,
    [3602] = 50, [3468] = 51, [3340] = 52, [3217] = 53, [3099] = 54,
    [2986] = 55, [2878] = 56, [2774] = 57, [2675] = 58, [2579] = 59,
    [2488] = 60, [2400] = 61, [2316] = 62, [2235] = 63, [2157] = 64,
    [2083] = 65, [2011] = 66, [1942] = 67, [1876] = 68, [1813] = 69,
    [1752] = 70, [1693] = 71, [1637] = 72, [1582] = 73, [1530] = 74,
    [1480] = 75, [1432] = 76, [1385] = 77, [1340] = 78, [1297] = 79,
    [1255] = 80, [1215] = 81, [1177] = 82, [1140] = 83, [1104] = 84,
    [1070] = 85, [1037] = 86, [1005] = 87, [973] = 88, [944] = 89,
    [915] = 90, [887] = 91, [861] = 92, [835] = 93, [810] = 94,
    [786] = 95, [763] = 96, [741] = 97, [719] = 98, [698] = 99,
    [678] = 100, [659] = 101, [640] = 102, [622] = 103, [604] = 104,
    [587] = 105,
}

--construct sensor on default address
sensor = assert(ina219:new())

sensor:set_calibration_16v_400ma()

local keys = {}
for k in pairs(LOOKUP) do
    keys[#keys+1] = k
end
table.sort(keys)

function dither(res1, res2, resistance, temp1, temp2)
    local interval = res2 - res1
    local percentage = ((res2 - resistance) / interval)
    return temp1 + ((temp2 - temp1) * (1+percentage))
end

-- get current time
local now = he.now()
local voltage
local resistance
local temp
local k
local v
local nxt
local curval
local nxtval

while true do --main loop
    local voltage = assert(sensor:get_voltage()) --v
    local resistance =  10000 * (1/((3.3/voltage) - 1.0))

    if resistance < keys[1] or resistance > keys[#keys] then
        print("resistance out of range", resistance, keys[1], keys[#keys])
    else
        if LOOKUP[resistance] then
            -- we have an exact match in the lookup table, awesome!
            temp = LOOKUP[resistance]
        else
            -- we don't have an exact match, so we have to dither
            for k, v in pairs(keys) do
                nxt = keys[k+1]
                if resistance > v and resistance < nxt then
                    curval = LOOKUP[v]
                    nxtval = LOOKUP[keys[k+1]]
                    temp = dither(v, nxt, resistance, curval, nxtval)
                    break
                end
            end
        end
        print(temp)
        he.send("t", now, "f", temp)
    end

    -- sleep until next time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end
