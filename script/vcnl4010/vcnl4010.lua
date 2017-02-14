-- Development board VCNL4010 proximity sensor script

i2c = he.i2c

SAMPLE_INTERVAL = 60000 -- 1 minute

vcnl4010 = {
    DEFAULT_ADDRESS = 0x13,
    PRODUCTID       = 0x81,


    COMMAND           = 0x80, -- commmand register, table 1
    LED_CURRENT       = 0x83, -- LED power register, table 4
    AMBIENTPARAMETER  = 0x84,
    AMBIENTDATA       = 0x85,
    PROXIMITYDATA     = 0x87,
    PROXINITYADJUST   = 0x8A,
    MEASUREAMBIENT    = 0x10,
    MEASUREPROXIMITY  = 0x08,
    AMBIENTREADY      = 0x40,
    PROXIMITYREADY    = 0x20
}

function vcnl4010:new(address)
    address = address or vcnl4010.DEFAULT_ADDRESS
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

function vcnl4010:is_connected()
    -- read the PRODUCT ID register - datasheet table 2
    local result = self:_get(self.PRODUCTID, "B")
    -- 0x21 is the current Product ID value as defined by the datasheet table 2
    if not (result == 0x21) then
        return false, "could not locate device"
    end
    return true
end

function vcnl4010:_get(reg, pack_fmt, convert)
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

function vncl4010:set_led_current(current)
    -- set the LED current, table 4
    if current < 0 or current > 20 then
        return false, "VCNL4010 LED current value should be between 0 and 20"
    end
    local status = i2c.txn(i2c.tx(self.address, LED_CURRENT, current))
    return status
end

local function vncl4010:get_led_current()
    local status, buffer, reason = i2c.txn(i2c.tx(self.ADDRESS, self.LED_CURRENT), i2c.rx(self.ADDRESS, 1))
    if status == false then
        return false, "failed to get value from device"
    end
    local current = string.unpack("B", buffer)
    return current & 0x3f -- only the low 6 bits store the current
end

function vcnl4010:read_proximity()
    i2c.txn(i2c.tx(self.address, self.COMMAND, self.MEASUREPROXIMITY))
    while true do
        local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.COMMAND), i2c.rx(self.address, 1))
        local reg = string.unpack("B", buffer)
        if reg & self.PROXIMITYREADY then
            local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.PROXIMITYDATA), i2c.rx(self.address, 2))
            if status == false then
                return false, "failed to read register"
            end
            local proximity = string.unpack(">I2", buffer)
            return proximity
        end
        he.wait{time=1 + he.now()}
    end
end

local function vcnl4010:read_ambient()
    i2c.txn(i2c.tx(self.address, self.COMMAND, self.MEASUREAMBIENT))
    while true do
        local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.COMMAND), i2c.rx(self.address, 1))
        local reg = string.unpack("B", buffer)
        if reg & self.AMBIENTREADY then
            local status, buffer, reason = i2c.txn(i2c.tx(self.address, self.AMBIENTDATA), i2c.rx(self.address, 2))
            if status == false then
                return false
            end
            local ambient = string.unpack(">I2", buffer)
            return ambient
        end
        he.wait{time=1 + he.now()}
    end
end

-- construct the sensor
sensor = assert(vcnl4010:new())
-- get current time
local now = he.now()
while true do
    -- turn on the IR LED
    sensor:set_led_current(20) -- max current, 200ma
    -- take readings
    local ambient = assert(sensor:read_ambient())
    local proximity = assert(sensor:read_proximity())

    -- send ambient light level as a float "f" on port "l"
    he.send("l", now, "f", ambient)
    -- send pressure as a float "f" on port "pr"
    he.send("pr", now, "f", proximity)

    -- Un-comment the following line to see results in semi-hosted mode
    -- print(ambient, proximity)

    -- turn the IR LED back off
    sensor:set_led_current(20) -- max current, 200ma

    -- wait for SAMPLE_INTERVAL time
    now = he.wait{time=now + SAMPLE_INTERVAL}
end
