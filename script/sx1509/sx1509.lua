-- Helum script for the Digital Expansion Board

-- Address jumpers
-- 00 => 0x3E
-- 01 => 0x3F
-- 10 => 0x70
-- 11 => 0x71

i2c = he.i2c

sx1509 = {
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
    MISC              = 0x1F
}

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

function sx1509:set_pin_direction(pin, val)
    local update = function(r)
        return bit_set(pin, r, not (val == "output"))
    end
    return self:_update(self.DIRB, ">I2", update)
end

-- set a pin's pull direction, can be "up", "down" or "none"
function sx1509:set_pin_pull(pin, val)
    local update = function(r)
        return bit_set(pin, r, val == "up")
    end
    local state = self:_update(self.PULLUPB, ">I2", update)
    if not state then
        return state "unable to set pin pull direction"
    end
    update = function(r)
        return bit_set(pin, r, val == "down")
    end
    return self:_update(self.PULLDOWNB, ">I2", update)
end

-- interrupts and edge events are 2 different things, the sx1509 can
-- apparently watch for edge events and record them independently of
-- throwing an interrupt
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

function sx1509:set_pin_event(pin, direction)
    -- we need to calculate which of the 4 interrupt registers we need to tweak
    local register_offset = 4 - (math.floor(pin / 4) + 1)
    local reg = self.SENSEHIGHB + register_offset
    local dirvalue = 0
    if direction == "r" then
        dirvalue = 1
    elseif direction == "f" then
        dirvalue = 2
    elseif direction == "e" then
        dirvalue = 3
    else
        return false, "unknown event direction"
    end
    -- now bitshift the value into the right offset inside the register
    dirvalue = dirvalue << ((pin % 4) * 2)
    return self:_update(reg, "B", function(r) return r | dirvalue end)
end

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

function sx1509:set_pin_debounce(pin, val)
    local update = function(r)
        return bit_set(pin, r, val)
    end
    return self:_update(self.DEBOUNCEB, ">I2", update)
end

function sx1509:event_status(pin)
    return self:_get(self.EVENTSTATUS, ">I2",
                     function(r) return r & (1 << pin) > 0 end)
end

function sx1509:interrupt_status(pin)
    return self:_get(self.INTERRUPTSOURCE, ">I2",
                     function(r) return r & (1 << pin) > 0 end)
end

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

function sx1509:set_led_driver(pin, val)
    local update = function(r)
        return bit_set(pin, r, val)
    end
    return self:_update(self.LEDDRIVERENABLE, ">I2", update)
end

function sx1509:set_debounce_rate(rate)
    -- 3 bit value
    i2c.txn(i2c.tx(self.address, self.DEBOUNCECONFIG, rate & 0x7))
end

function sx1509:read_pin(pin)
    return self:_get(self.DATAB, ">I2",
                     function(r) return (r & (1 << pin)) > 1 end)
end

function sx1509:write_pin(pin, val)
    local update = function(r)
        return bit_set(pin, r, val)
    end
    return self:_update(self.DATAB, ">I2", update)
end

function sx1509:toggle_pin(pin)
    local mask = (1 << pin)
    return self:_update(self.DATAB, ">I2", function(r) return r ~ mask end)
end

--Turns on the internal clock, must be on for PWM/debounce to work
function sx1509:set_clock(val)
    local update = function(r)
        if val then
            return r | 0x40
        else
            return r & ~0x40
        end
    end
    return self:_update(self.MISC, "B", update)
end

function sx1509:set_clock(val)
    if not val then
        i2c.txn(i2c.tx(self.address, self.CLOCK, 0x00))
    else
        i2c.txn(i2c.tx(self.address, self.CLOCK, 0x40))
    end
end

--resets all registers
function sx1509:reset()
    i2c.txn(i2c.tx(self.address, self.RESET, 0x12))
    i2c.txn(i2c.tx(self.address, self.RESET, 0x34))
    -- zero out the data registers, for some reason they default to
    -- high, which we have deemed silly
    i2c.txn(i2c.tx(self.address, self.DATAB, 0, 0))
end

return sx1509
