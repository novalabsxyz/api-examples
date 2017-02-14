-- Helum script for the Digital Expansion Board

-- Address jumpers
-- 00 => 0x3E
-- 01 => 0x3F
-- 10 => 0x70
-- 11 => 0x71

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

i2c = he.i2c

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
    print(o)
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

function sx1509:set_pin_direction(pin, val)
    local mask = (1 << pin)
    if (val == "output") then
        return self:_update_register(self.DIRB, ">I2", function(r) return r & ~mask end)
    else
        return self:_update_register(self.DIRB, ">I2", function(r) return r | mask end)
    end
end

-- interrupts and edge events are 2 different things, the sx1509 can apparently watch for edge events
-- and record them independently of throwing an interrupt
function sx1509:set_pin_interrupt(pin, val, direction)
    local mask = (1 << pin)
    local status = false
    if (val == true) then
        status = self:_update_register(self.INTERRUPTB, ">I2", function(r) return r & ~mask end)
    else
        status = self:_update_register(self.INTERRUPTB, ">I2", function(r) return r | mask end)
    end
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
    return self:_update_register(reg, "B", function(r) return r | dirvalue end)
end

function sx1509:_update_register(reg, pack_fmt, update)
    -- read register, apply a function to the result and write it back
    -- number of bytes to read based on the pack string
    if not update then
        return false, "you must supply an update function"
    end
    local pack_size = string.packsize(pack_fmt)
    local status, buffer = i2c.txn(i2c.tx(self.address, reg), i2c.rx(self.address, pack_size))
    if not status then
        return false, "failed to get value from device"
    end
    -- call update function
    local newvalue = string.unpack(pack_fmt, buffer)
    newvalue = update(newvalue)
    status, buffer, reason =
    i2c.txn(i2c.tx(self.address, reg, string.pack(pack_fmt, newvalue)))
    if not status then
        return false, "unable to set value"
    end
    return newvalue
end

function sx1509:set_pin_debounce(pin, val)
    local mask = (1 << pin)
    if (val == false) then
        return self:_update_register(self.DEBOUNCEB, ">I2", function(r) return r & ~mask end)
    else
        return self:_update_register(self.DEBOUNCEB, ">I2", function(r) return r | mask end)
    end
end

function sx1509:event_status(pin)
    return self:_get(self.EVENTSTATUS, ">I2", function(r) print(r); return r & (1 << pin) > 0 end)
end

function sx1509:interrupt_status(pin)
    return self:_get(self.INTERRUPTSOURCE, ">I2", function(r) print(r); return r & (1 << pin) > 0 end)
end

function sx1509:clear_events()
    he.i2c.txn(he.i2c.tx(self.address, self.EVENTSTATUS, 0xff, 0xff)) --clears eventstatus register, which also clears the interruptsource register
    he.i2c.txn(he.i2c.tx(self.address, self.INTERRUPTSOURCE, 0xff, 0xff)) --clears eventstatus register, which also clears the interruptsource register
end

-- configure if we want the interrupt and event registers to be autocleared on read from the DATA registers. Autoclear defaults to on
function sx1509:set_autoclear(val)
    if (val == true) then
        -- 0 is on, oddly
        return self:_update_register(self.MISC, "B", function(r) return r & ~1 end)
    else
        return self:_update_register(self.MISC, "B", function(r) return r | 1 end)
    end
end

function sx1509:enable_led_driver(val)
    if (val == false) then
        return self:_update_register(self.MISC, "B", function(r) return r & ~0x60 end)
    else
        return self:_update_register(self.MISC, "B", function(r) return r | 0x60 end)
    end
end

function sx1509:set_led_driver(pin, val)
    local mask = (1 << pin)
    if (val == false) then
        return self:_update_register(self.LEDDRIVERENABLE, ">I2", function(r) return r & ~mask end)
    else
        return self:_update_register(self.LEDDRIVERENABLE, ">I2", function(r) return r | mask end)
    end
end

function sx1509:set_debounce_rate(rate)
    -- 3 bit value
    i2c.txn(i2c.tx(self.address, self.DEBOUNCECONFIG, rate & 0x7))
end

function sx1509:read_pin(pin)
    local res = self:_get(self.DATAB, ">I2")
    local mask = (1 << pin)
    if (res & mask) > 1 then
        return true
    else
        return false
    end
end

function sx1509:write_pin(pin, val)
    local mask = (1 << pin)
    if (val == false) then
        return self:_update_register(self.DATAB, ">I2", function(r) return r & ~mask end)
    else
        return self:_update_register(self.DATAB, ">I2", function(r) return r | mask end)
    end
end

function sx1509:toggle_pin(pin)
    local mask = (1 << pin)
    return self:_update_register(self.DATAB, ">I2", function(r) return r ~ mask end)
end

--Turns on the internal clock, must be on for PWM/debounce to work
function sx1509:set_clock(val)
    if (val == false) then
        return self:_update_register(self.MISC, "B", function(r) return r & ~0x40 end)
    else
        return self:_update_register(self.MISC, "B", function(r) return r | 0x40 end)
    end
end

function sx1509:set_clock(val)
    if not val then
        i2c.txn(i2c.tx(self.address, self.CLOCK, 0x00))
    else      
        i2c.txn(i2c.tx(self.address, self.CLOCK, 64))      
    end
end

--resets all registers
function sx1509:reset()
    i2c.txn(i2c.tx(self.address, self.RESET, 0x12))
    i2c.txn(i2c.tx(self.address, self.RESET, 0x34))
    -- zero out the data registers, for some reason they default to high, which we have deemed silly
    i2c.txn(i2c.tx(self.address, self.DATAB, 0, 0))
end

now = he.now() --set current time
he.interrupt_cfg("int0", "e", 10)
digital = assert(sx1509:new())
digital:reset()
digital:set_clock(true)
digital:enable_led_driver(true)
digital:set_pin_direction(13, "output") --set pin 13 (red LED) as an output pin
digital:set_pin_direction(14, "output") --set pin 14 (green LED) as an output pin
digital:set_pin_direction(15, "output") --set pin 15 (blue LED) as an output pin
digital:set_led_driver(13, true) -- connect them to the LED driver so we can use PWM
digital:set_led_driver(14, true)
digital:set_led_driver(15, true)


-- hook up switches to both pin 1 and pin 2
digital:set_pin_direction(1, "input") --set pin 1 as an input pin
digital:set_pin_direction(2, "input") --set pin 2 as an input pin

digital:set_pin_interrupt(1, true, "e") -- like he.interrupt, takes r, f or e
digital:set_pin_event(2, "e") -- just monitor the pin for an event, don't interrupt when it happens
digital:set_pin_debounce(1, true)
digital:set_debounce_rate(7) -- the max

-- turn off all the LED colors
i2c.txn(i2c.tx(digital.address, 0x5B, 255))
i2c.txn(i2c.tx(digital.address, 0x60, 255))
i2c.txn(i2c.tx(digital.address, 0x65, 255))

while true do --main loop
    now, new_events, events = he.wait{time=5000 + now}
    if new_events then
        -- unless autoclear is disabled, we need to check the interrupt/event status first
        print(digital:interrupt_status(1)) -- pin 1 will always be true here
        print(digital:interrupt_status(2)) -- pin 2 will NEVER be true here
        print(digital:event_status(1)) -- pin 1 will always have an event here
        print(digital:event_status(2)) -- if the switch on pin 2 was pressed since the last interrupt, this will be true
        print("interrupted")
        digital:clear_events()
        -- set the LEDs to a random color
        i2c.txn(i2c.tx(digital.address, 0x5B, math.random(0, 255)))
        i2c.txn(i2c.tx(digital.address, 0x60, math.random(0, 255)))
        i2c.txn(i2c.tx(digital.address, 0x65, math.random(0, 255)))
    end
end
