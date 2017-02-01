-- Development board on-board sensor production script
-- Datasheet: http://www.st.com/content/ccc/resource/technical/document/datasheet/bf/c1/4f/23/61/17/44/8a/DM00140895.pdf/files/DM00140895.pdf/jcr:content/translations/en.DM00140895.pdf

i2c = he.i2c

LPS22HBTR_ADDR = 0x5C
SAMPLE_INTERVAL = 60000 -- 1 minute

WHO_AM_I = 0x8F
WHO_AM_I_LEN = 1

CTRL_REG2 = 0x11
CTRL_REG2_LEN = 1
CTRL_REG2_ONESHOT = 0x11

TEMP_OUT_L = 0xAB
TEMP_OUT_LEN = 2

PRESS_OUT_L = 0x29
PRESS_OUT_H = 0x2A
PRESS_OUT_XL = 0x28
PRESS_OUT_LEN = 3

function check_for_sensor()
   local status, buffer =
      i2c.txn(i2c.tx(LPS22HBTR_ADDR, WHO_AM_I),
              i2c.rx(LPS22HBTR_ADDR, WHO_AM_I_LEN))
   return (status and #buffer >= 1 and 0xB1 == string.unpack("B", buffer))
end

function wait_for_conversion()
   local reg
   repeat
      local status, buffer =
         i2c.txn(i2c.tx(LPS22HBTR_ADDR, CTRL_REG2),
                 i2c.rx(LPS22HBTR_ADDR, CTRL_REG2_LEN))

      assert(status)
      assert(#buffer >= 1)

      reg = string.unpack("B", buffer)
   until (reg & 0x01) == 0
end

function read_pressure()
   local status, buffer =
       i2c.txn(i2c.tx(LPS22HBTR_ADDR, PRESS_OUT_XL),
               i2c.rx(LPS22HBTR_ADDR, PRESS_OUT_LEN))
   local pressure = string.unpack("i3", buffer)

   return (pressure / 4096) * 0.014503773773022; --psi
end

function read_temp()
   local status, buffer =
       i2c.txn(i2c.tx(LPS22HBTR_ADDR, TEMP_OUT_L),
               i2c.rx(LPS22HBTR_ADDR, TEMP_OUT_LEN))

   assert(status)
   assert(#buffer >= 1)

   return string.unpack("<i2", buffer) / 100.0 -- C
end

function sample_temp()
   local status =
      i2c.txn(i2c.tx(LPS22HBTR_ADDR, CTRL_REG2, CTRL_REG2_ONESHOT))

   assert(status)

   wait_for_conversion()

   return read_temp()
end

function sample_pressure()
   local status =
      i2c.txn(i2c.tx(LPS22HBTR_ADDR,
                     CTRL_REG2, CTRL_REG2_ONESHOT))

   assert(status)

   wait_for_conversion()

   return read_pressure()
end


-- Turn on power and delay for a short period
he.power_set(true)
he.wait{time=he.now() + 5}

assert(check_for_sensor())

local now = he.now()
while true do
   local pressure = sample_pressure()
   local temperature = sample_temp()
   he.send("t", now, "f", temperature)
   he.send("p", now, "f", pressure)

   local target = now + SAMPLE_INTERVAL
   now = he.wait{time=now + SAMPLE_INTERVAL}
end
