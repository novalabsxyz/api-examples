--------------------------------------------------------------------------------
-- queue.lua: Simple in-memory queue for buffering up Helium Cloud samples.

-- Authors:  Brian Fink, Austin Seipp
-- Version:  0.0.0
-- Released: 16 March 2017
-- Keywords: queue, radio, cloud
-- License:  BSD3

--------------------------------------------------------------------------------
-- SECTION: Module Prelude

-- Exported module object
local queue = {}

--------------------------------------------------------------------------------
-- SECTION: Public API - Queue initialization

-- queue:new(max, ports):
--
-- Create a new in-memory `queue` object that send samples to the Helium Cloud
-- after ${max} number of samples have been accumulated.
--
-- TODO FIXME: Describe ${ports}.
--
-- If ${max} is `nil`, the default queue size is 1, so a sample is submitted
-- immediately once it is queued with ${queue:add}.
--
-- Returns:
--
--   - A `queue` object, for queuing sensor samples.
--
function queue:new(max, ports)
  local o = {
    max     = max or 1,-- Max number of buffered samples
    ports   = ports,   -- Port->type mapping
    entries = {},      -- State containing the current entries
    count   = 0,       -- The current number of entries
  }

  -- Set up Lua metatable object and return it
  setmetatable(o, self)
  self.__index = self
  return o
end

--------------------------------------------------------------------------------
-- SECTION: Public API - Entry queuing

-- queue:add(time, values)
--
-- Submit the samples in ${values} at timestamp ${time} into the queue. Once the
-- maximum number of queue entries has been reached, the results will be sent to
-- the Helium Cloud, and the queue entries will be flushed.
--
-- This function does not return any value.
--
function queue:add(time, values)
   self.count = self.count + 1
   self.entries[self.count] = { time, values }

   if self.count >= self.max then self:flush() end
end

-- queue:flush():
--
-- Flush the queue of any existing entries (if they exist) and submit them to
-- the Helium Cloud, even if the sample limit has not yet been hit.
--
-- This function does not return any value.
--
function queue:flush()
  for i=1,self.count do
    for k,v in ipairs(self.ports) do
      he.send(v[1], self.entries[i][1], v[2], self.entries[i][2][k])
    end
  end

  -- we'll just let queue:add overwrite instead of forcibly clearing
  -- the `self.entries` table
  self.count = 0
end

--------------------------------------------------------------------------------
-- SECTION: Finish - Return queue module object

return queue

-- Local Variables:
-- mode: lua-mode
-- fill-column: 80
-- indent-tabs-mode: nil
-- c-basic-offset: 2
-- buffer-file-coding-system: utf-8-unix
-- End:

-- queue.lua ends here
