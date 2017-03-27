
ads1115 = require("ads1115")

local adc = assert(ads1115:new())
-- do a differential compare between pins A0 and A1
adc:set_comparison_pins(adc.COMPARE_AIN0_AIN1)
-- sample at 860 samples per second
adc:set_rate(adc.RATE_860SPS)
-- set the gain to 16
adc:set_gain(adc.GAIN_16)
-- continuously sample
adc:set_continuous(true)

-- set the high/low thresholds
adc:set_high_threshold(200)
adc:set_low_threshold(0)
-- set the comparator trigger threshold to one sample
adc:set_comparator_queue(adc.ASSERT_ONE)
-- latch the interrupt pin until the conversion register is read
adc:set_comparator_latch(true)
-- windowed mode triggers an interrupt if the value is above the high,
-- or below the low threshold. In traditional mode, the interrupt
-- won't be thrown again until the value goes under the low threshold
adc:set_comparator_window_mode(true)

-- set up our interrupt pin
he.interrupt_cfg{pin="int0", edge="either", pull="up", debounce=10}

while true do
    local now, new_events = he.wait{time=he.now() + 1000}
    if new_events then
        print("interrupt")
    end
    print(adc:read())
end
