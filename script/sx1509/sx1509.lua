----
-- SX1509 Helium Digital Extension Board
-- This is the library class for configuration and using the SX1509
-- part used on the Helium Digital Extension Board
--
-- @module sx1509
-- @license MIT
-- @copyright 2017 Helium Systems, Inc.
-- @usage
-- sx1509 = require("sx1509")
-- digital = sx1509:new()
-- --- Let's turn on the LED
-- digital:set_clock(true)
-- -- turn on the LED driver
-- digital:enable_led_driver(true)
-- digital:set_pin_direction(13, "output") --set pin 13 (red LED) as an output pin
-- digital:set_pin_direction(14, "output") --set pin 14 (green LED) as an output pin
-- digital:set_pin_direction(15, "output") --set pin 15 (blue LED) as an output pin
-- digital:set_led_driver(13, true) -- connect them to the LED driver so we can use PWM
-- digital:set_led_driver(14, true)
-- digital:set_led_driver(15, true)
-- -- Let's make it all white (r, g, b)
-- digital:set_pin_pwm(13, digital.pwm.ION, 255)
-- digital:set_pin_pwm(14, digital.pwm.ION, 255)
-- digital:set_pin_pwm(15, digital.pwm.ION, 255)

i2c = he.i2c

sx1509 = {
    --- Default I2C address for module
    DEFAULT_ADDRESS   = 0x3E,
    INPUTDISABLEB     = 0x00,
    INPUTDISABLEA     = 0x01,
    LONGSLEWB         = 0x02,
    LONGSLEWA         = 0x03,
    LOWDRIVEB         = 0x04,
    LOWDRIVEA         = 0x05,
    PULLUPB           = 0x06,
    PULLUPA           = 0x07,
    PULLDOWNB         = 0x08,
    PULLDOWNA         = 0x09,
    OPENDRAINB        = 0x0A,
    OPENDRAINA        = 0x0B,
    POLARITYB         = 0x0C,
    POLARITYA         = 0x0D,
    DIRB              = 0x0E,
    DIRA              = 0x0F,
    DATAB             = 0x10,
    DATAA             = 0x11,
    INTERRUPTB        = 0x12,
    INTERRUPTA        = 0x13,
    SENSEHIGHB        = 0x14,
    SENSELOWB         = 0x15,
    SENSEHIGHA        = 0x16,
    SENSELOWA         = 0x17,
    INTERRUPTSOURCE   = 0x18,
    EVENTSTATUS       = 0x1A,
    LEDDRIVERENABLE   = 0x20,
    DEBOUNCECONFIG    = 0x22,
    DEBOUNCEB         = 0x23,
    DEBOUNCEA         = 0x24,
    RESET             = 0x7D,
    CLOCK             = 0x1E,
    MISC              = 0x1F,

    --- 0.5 ms debounce rate
    DEBOUNCE_RATE_0_5ms = 0,
    --- 1 ms debounce rate
    DEBOUNCE_RATE_1ms   = 1,
    --- 2 ms debounce rate
    DEBOUNCE_RATE_2ms   = 2,
    --- 4 ms debounce rate
    DEBOUNCE_RATE_4ms   = 3,
    --- 8 ms debounce rate
    DEBOUNCE_RATE_8ms   = 4,
    --- 16 ms debounce rate
    DEBOUNCE_RATE_16ms  = 5,
    --- 32 ms debounce rate
    DEBOUNCE_RATE_32ms  = 6,
    --- 64 ms debounce rate
    DEBOUNCE_RATE_64ms  = 7
}


---- PWM configuration settings.
-- All GPIO pins can be independently configured for PWM `ION`, `TON`,
-- and the corresponsing `OFF`.
--
-- Only pins 4-7 and 12-15 support `RISE` and `FALL` fade (aka
-- "breahting") features.
--
-- Configuring any of the pins for PWM use enabling the SX1509 clock
-- using the @{set_clock} function.
--
-- @field TON Time for a PWM configured pin to be on.
-- @field ION Intensity for a PWM configured pin when on.
-- @field OFF Time or intensity when a configured PWM pin is OFF.
-- @field RISE  Time to a PWM configured pin to fade to on.
-- @field FALL Time to a PWM configured pin to fade to off.
-- @table pwm
-- @see set_clock
-- @usage
-- digital = sx1509:new()
-- -- set intensity when on to maximum value
-- digital.set_pin_pwm(13, digital.pwm.ION, 255)
local pwm = {
    TON  = 0x01,
    ION  = 0x02,
    OFF  = 0x04,
    RISE = 0x08,
    FALL = 0x0F,
}

pwm.CORE = pwm.TON | pwm.ION | pwm.OFF
pwm.ALL = pwm.CORE | pwm.RISE | pwm.FALL
pwm.descriptors = {
    {0x29, pwm.CORE}, -- pin 0
    {0x2C, pwm.CORE}, -- pin 1
    {0x2F, pwm.CORE}, -- pin 2
    {0x32, pwm.CORE}, -- pin 3
    {0x35, pwm.ALL }, -- pin 4
    {0x3A, pwm.ALL }, -- pin 5
    {0x3F, pwm.ALL }, -- pin 6
    {0x44, pwm.ALL }, -- pin 7
    {0x49, pwm.CORE}, -- pin 8
    {0x4C, pwm.CORE}, -- pin 9
    {0x4F, pwm.CORE}, -- pin 10
    {0x52, pwm.CORE}, -- pin 11
    {0x55, pwm.ALL }, -- pin 12
    {0x5A, pwm.ALL }, -- pin 13
    {0x5F, pwm.ALL }, -- pin 14
    {0x64, pwm.ALL }, -- pin 15
}

sx1509.pwm = pwm

--- Construct a new SX1509 sensor object.
--
-- @usage local sensor = sx1509:new()
-- @param[opt=DEFAULT_ADDRESS] address I2C address to use
-- @treturn sx1509 a verified connected sensor object
function sx1509:new(address)
    address = address or sx1509.DEFAULT_ADDRESS
    -- We use a simple lua object system as defined
    -- https://www.lua.org/pil/16.1.html
    -- construct the object table
    local o = { address = address }
    -- ensure that the "class" is the metatable
    setmetatable(o, self)
    -- and that the metatable's index function is set
    -- Refer to https://www.lua.org/pil/16.1.html
    self.__index = self
    -- Check that the sensor is connected
    status, reason = o:is_connected()
    if not status then
        return status, reason
    end
    return o
end

--- Check sensor connectivity
-- Checks whether the sensor is actually connected to the Atom Board.
--
-- @return true if the sensor is connected to the board
function sx1509:is_connected()
    -- read the RESET register, should always be 0
    -- not sure what better to do here?
    local result = self:_get(self.RESET, "B")
    if not (result == 0) then
        return false, "could not locate device"
    end
    return true
end

function sx1509:_get(reg, pack_fmt, convert)
    -- number of bytes to read based on the pack string
    local pack_size = string.packsize(pack_fmt)
    local status, buffer = i2c.txn(i2c.tx(self.address, reg),
    i2c.rx(self.address, pack_size))
    if not status then
        return false, "failed to get value from device"
    end
    -- call conversion function if given
    if convert then
        return convert(string.unpack(pack_fmt, buffer))
    end
    return string.unpack(pack_fmt, buffer)
end

function sx1509:_update(reg, pack_fmt, update)
    -- read register, apply a function to the result and write it back
    -- number of bytes to read based on the pack string
    if not update then
        return false, "you must supply an update function"
    end
    local pack_size = string.packsize(pack_fmt)
    local status, buffer =
        i2c.txn(i2c.tx(self.address, reg), i2c.rx(self.address, pack_size))
    if not status then
        return false, "failed to get value from device"
    end
    -- call update function
    local newvalue = string.unpack(pack_fmt, buffer)
    newvalue = update(newvalue)
    status, buffer =
        i2c.txn(i2c.tx(self.address, reg, string.pack(pack_fmt, newvalue)))
    if not status then
        return false, "unable to set value"
    end
    return newvalue
end

local function bit_set(bit, value, condition)
    local mask = (1 << bit)
    if condition then
        return value | mask
    else
        return value & ~mask
    end
end

--- Sets the GPIO direction of a given pin
--
-- @param pin the pin number to get.
-- @param val the direction of the pin. One of 'input' or 'output'.
function sx1509:set_pin_direction(pin, val)
    local update = function(r)
        return bit_set(pin, r, not (val == "output"))
    end
    return self:_update(self.DIRB, ">I2", update)
end

--- Set the pull up/down resistors for a given pin
--
-- @param pin pin to configure the pull direction for
-- @param val The pull direction. One of 'up', 'down', or 'none'
-- set a pin's pull direction, can be "up", "down" or "none"
function sx1509:set_pin_pull(pin, val)
    local update = function(r)
        return bit_set(pin, r, val == "up")
    end
    local state = self:_update(self.PULLUPB, ">I2", update)
    if not state then
        return state, "unable to set pin pull direction"
    end
    update = function(r)
        return bit_set(pin, r, val == "down")
    end
    return self:_update(self.PULLDOWNB, ">I2", update)
end

--- Configure a given pin to open drain mode.
--
-- @param pin pin number to configure.
-- @param val true to set to open drain mode, false otherwise
function sx1509:set_open_drain(pin, val)
    local update = function(r)
        return bit_set(pin, r, val == true)
    end
    return self:_update(self.OPENDRAINB, ">I2", update)
end

--- Configure interrupts for a given pin.
--
-- The SX1509 can watch and record edge events independently from
-- throwing interrupts. This interrupt configuration sets up both the
-- interrupt and the edge event detection.
--
-- @param pin pin number to configure
-- @param val true to enable the interrupt, false to disable it
-- @param direction direction of the edge to interrupt on.
-- One of `rising` `falling` or `either`.
function sx1509:set_pin_interrupt(pin, val, direction)
    local update = function(r)
        return bit_set(pin, r, not val)
    end
    local status = self:_update(self.INTERRUPTB, ">I2", update)
    if not status then
        return false, "unable to enable interrupt"
    end
    -- set up the edge detection
    return self:set_pin_event(pin, direction)
end


--- Configures edge event detection for a given pin.
--
-- Edge events can be detected without throwing interrupts. This
-- configures edge event detection for a given pin and direction.
--
-- @param pin pin number to configure
-- @param direction the direction of the edge event to detect. One of
-- `rising`, `falling`, or `either`
function sx1509:set_pin_event(pin, direction)
    -- we need to calculate which of the 4 interrupt registers we need to tweak
    local register_offset = 4 - (math.floor(pin / 4) + 1)
    local reg = self.SENSEHIGHB + register_offset
    local dirvalue = 0
    if direction == "r" or direction == "rising" then
        dirvalue = 1
    elseif direction == "f" or direction == "falling" then
        dirvalue = 2
    elseif direction == "e" or direction == "either" then
        dirvalue = 3
    else
        return false, "unknown event direction"
    end
    -- now bitshift the value into the right offset inside the register
    dirvalue = dirvalue << ((pin % 4) * 2)
    return self:_update(reg, "B", function(r) return r | dirvalue end)
end

---- Configure PWM for a given pin.
--
-- @param pin pin to configure for PWM.
-- @param operation one of the `pwm` constants.
-- @param value the pwm value to use. Between 0 and 255.
function sx1509:set_pin_pwm(pin, operation, value)
    -- get the pwm descriptor
    local descriptor = self.pwm.descriptors[pin + 1]
    local register, operations = table.unpack(descriptor)
    -- validate the the rqeuested operation is supported
    if operations & operation ~= operation then
        return false, "unsupprted operation"
    end
    -- calculate the number to add to the base address this relies on
    -- the operations being defined in order in the datasheet and the
    -- definition of the constants in pwm having a matching set of
    -- trailing 0s after the bit that defines them
    offset = 0
    while operation > 1 do
        operation = operation >> 1
        offset = offset + 1
    end
    register = register + offset
    -- and finally set the register to the requested value
    return i2c.txn(i2c.tx(self.address, register, value))
end

--- Configure the debounce rate for all pins.
--
-- Debounce is configured globally for the SX1509 but can then be
-- turned on or of for individual pins.
--
-- @param rate one of the `DEBOUNCE_` constants
-- @see set_pin_debounce
-- @see set_clock
-- @usage
-- digital = sx1509:new()
-- digital:set_debounce_rate(digital.DEBOUNCE_16ms)
-- -- turn on configured debounce for pin 1
-- digital.set_pin_debounce(1, true)
function sx1509:set_debounce_rate(rate)
    -- 3 bit value
    i2c.txn(i2c.tx(self.address, self.DEBOUNCECONFIG, rate & 0x7))
end

--- Enable or disable debounce for a given pin.
-- The actual debounce rate is configured once for the whole system.
--
-- @param pin pin to configure debounce for.
-- @param val true to enable, false to disable debounce.
-- @see set_debounce_rate
-- @see set_clock
function sx1509:set_pin_debounce(pin, val)
    local update = function(r)
        return bit_set(pin, r, val)
    end
    return self:_update(self.DEBOUNCEB, ">I2", update)
end

--- Get the current event status for a given pin.
--
-- The SX1509 can detect edge events without throwing interrupts. This
-- returns whether an edge event was seen since the last time the
-- events status was cleared.
--
-- @param pin the pin to get the event status for.
-- @return true if an edge event was seen for the given pin, false otherwise.
function sx1509:event_status(pin)
    return self:_get(self.EVENTSTATUS, ">I2",
                     function(r) return r & (1 << pin) > 0 end)
end

--- Get the interrupt status for a given pin.
--
-- The script will receive interrupts on the sensor bus INT0 or INT1
-- lines for any pin that was configured to throw interrupts. In order
-- to know if a given pin caused an interrupt since the interrupt was
-- last cleared, you can use this function.
--
-- @param pin pin to request interrupt status for.
-- @return true if the given pin threw an interrupt, false otherwise.
function sx1509:interrupt_status(pin)
    return self:_get(self.INTERRUPTSOURCE, ">I2",
                     function(r) return r & (1 << pin) > 0 end)
end

--- Clear all events and interrupts.
--
-- After detecting an interrupt, call this function to clear the
-- interrupt and event flags for all pins to get set up for the next
-- interrupt or event.
function sx1509:clear_events()
    -- clears eventstatus register, which also clears the
    -- interruptsource register
    i2c.txn(i2c.tx(self.address, self.EVENTSTATUS, 0xff, 0xff))
    --clears eventstatus register, which also clears the
    --interruptsource register
    i2c.txn(i2c.tx(self.address, self.INTERRUPTSOURCE, 0xff, 0xff))
end

-- configure if we want the interrupt and event registers to be
-- autocleared on read from the DATA registers. Autoclear defaults to
-- on
function sx1509:set_autoclear(val)
    local update = function(r)
        return bit_set(0, r, not val)
    end
    return self:_update(self.MISC, "B", update)
end

--- Enable the LED driver.
--
-- In order to configure and use PWM for any given pin, the LED driver
-- needs to be enabled. Use this function to enable or disable the LED
-- driver.
--
-- @param val true to enable the LED driver, false to disable it.
function sx1509:enable_led_driver(val)
    local update = function(r)
        if val then
            return r | 0x60
        else
            return r & ~0x60
        end
    end
    return self:_update(self.MISC, "B", update)
end

--- Configure the given pin to be driven by the LED driver to use PWM
--
-- @param pin pin to configure for PWM use.
-- @param val true to enable PWM use, false if not.
function sx1509:set_led_driver(pin, val)
    local update = function(r)
        return bit_set(pin, r, val)
    end
    return self:_update(self.LEDDRIVERENABLE, ">I2", update)
end

function sx1509:read_pin(pin)
    return self:_get(self.DATAB, ">I2",
                     function(r) return (r & (1 << pin)) > 0 end)
end

--- Set a given pin to high or low.
--
-- @param pin pin to set high or low.
-- @param val true to set pin high, 0 to set pin low.
function sx1509:write_pin(pin, val)
    local update = function(r)
        return bit_set(pin, r, val)
    end
    return self:_update(self.DATAB, ">I2", update)
end

--- Toggle a given pin to the opposite state.
-- If the given pin is high then set it to low or vice versa.
--
-- @param pin to toggle based on it's current state.
function sx1509:toggle_pin(pin)
    local mask = (1 << pin)
    return self:_update(self.DATAB, ">I2", function(r) return r ~ mask end)
end

--- Turn on the internal clock
--
-- For PWM and debounce to work the internal clock must be turned on
--
-- @param val true to turn the clock on, false to turn it of.
function sx1509:set_clock(val)
    if not val then
        i2c.txn(i2c.tx(self.address, self.CLOCK, 0x00))
    else
        i2c.txn(i2c.tx(self.address, self.CLOCK, 0x40))
    end
end

--- Reset all I2C registers
--
-- Useful for library development purposes since the registers will
--hold state that may nee to be reset for a clean start.
function sx1509:reset()
    i2c.txn(i2c.tx(self.address, self.RESET, 0x12))
    i2c.txn(i2c.tx(self.address, self.RESET, 0x34))
    -- zero out the data registers, for some reason they default to
    -- high, which we have deemed silly
    i2c.txn(i2c.tx(self.address, self.DATAB, 0, 0))
end

return sx1509
