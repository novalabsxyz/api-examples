ads1115 = require("ads1115")

local adc = assert(ads1115:new())
-- do a differential compare between pins A0 and A1
adc:set_comparison_pins(adc.COMPARE_AIN0_AIN1)
-- set the gain to 4
adc:set_gain(adc.GAIN_8)
-- power down when not sampling
adc:set_continuous(false)

while true do
    he.wait{time=he.now() + 1000}
    print(adc:oneshot_sample())
end
