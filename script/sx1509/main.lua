--- Example main loop for the Helium Digital Extension Board.
--
-- Requires helium-script 2.x and the sx1509.lua library.
--
-- This main loop cycles the LED on board the Digital Extension Board
-- on a timer and listens for any interrupts on INT0 coming from pin
-- 1. Then the interrupt is detected the LED colors are changed to
-- another random set of RGB values.
--
-- @script sx1509.main
-- @license MIT
-- @copyright 2017 Helium Systems, Inc.
-- @usage
-- # In semi-hosted mode over USB
-- $ helium-script -m main.lua sx1509.lua
--
-- # Upload to device over USB
-- $ helium-script -up -m main.lua sx1509.lua

sx1509 = require("sx1509")

now = he.now() --set current time
he.interrupt_cfg { pin = "int0", edge = "either", debounce = 10 }
digital = assert(sx1509:new())
digital:reset()
-- debounce and LED driver need the clock enabled
digital:set_clock(true)
-- turn on the LED driver
digital:enable_led_driver(true)
digital:set_pin_direction(13, "output") --set pin 13 (red LED) as an output pin
digital:set_pin_direction(14, "output") --set pin 14 (green LED) as an output pin
digital:set_pin_direction(15, "output") --set pin 15 (blue LED) as an output pin
digital:set_led_driver(13, true) -- connect them to the LED driver so we can use PWM
digital:set_led_driver(14, true)
digital:set_led_driver(15, true)

digital:set_pin_direction(1, "input") --set pin 1 as an input pin

-- enable interrupts on pin 1. Like he.interrupt, takes rising, falling or either
digital:set_pin_interrupt(1, true, "falling")
-- require 2 consecutive samples to be the same 32ms apart before
-- firing an interrupt
digital:set_debounce_rate(digital.DEBOUNCE_RATE_32ms)
digital:set_pin_debounce(1, true) -- enable debounce on pin 1

-- pick a random starting point for the LED colors
local i = math.random(0, 255)
local j = math.random(0, 255)
local k = math.random(0, 255)
digital:set_pin_pwm(13, digital.pwm.ION, i)
digital:set_pin_pwm(14, digital.pwm.ION, j)
digital:set_pin_pwm(15, digital.pwm.ION, k)

-- process around the color space, if we get an interrupt, jump to a new random RGB coordinate
while true do --main loop
    now, events = he.wait{time=500 + now}
    if events then
        -- switch on pin 1 triggered
        -- clear the LEDs so they blink off
        digital:set_pin_pwm(13, digital.pwm.ION, 255)
        digital:set_pin_pwm(14, digital.pwm.ION, 255)
        digital:set_pin_pwm(15, digital.pwm.ION, 255)
        -- set the LEDs to a new random color
        i = math.random(0, 255)
        j = math.random(0, 255)
        k = math.random(0, 255)
    else
        -- just increment the colors
        i = (i+5) & 0xff
        j = (j+5) & 0xff
        k = (k+5) & 0xff
    end
    -- Clearing all events regardless to work around a firmware bug
    digital:clear_events()
    digital:set_pin_pwm(13, digital.pwm.ION, i)
    digital:set_pin_pwm(14, digital.pwm.ION, j)
    digital:set_pin_pwm(15, digital.pwm.ION, k)
end
