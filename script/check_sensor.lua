-- Check availability of the on-baord sensor
-- Datasheet: http://www.st.com/content/ccc/resource/technical/document/datasheet/bf/c1/4f/23/61/17/44/8a/DM00140895.pdf/files/DM00140895.pdf/jcr:content/translations/en.DM00140895.pdf

i2c = he.i2c

LPS22HBTR_ADDR = 0x5C

WHO_AM_I = 0x8F
WHO_AM_I_LEN = 1

function check_for_sensor()
   local status, buffer =
      i2c.txn(i2c.tx(LPS22HBTR_ADDR, WHO_AM_I),
              i2c.rx(LPS22HBTR_ADDR, WHO_AM_I_LEN))
   return (status and #buffer >= 1 and 0xB1 == string.unpack("B", buffer))
end

he.pwer_set(true)
if check_for_sensor() then
   print("FOUND")
else
   print("NOT FOUND")
end
he.power_set(false)
