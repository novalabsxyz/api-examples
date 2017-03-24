----
-- The configuration abstraction layer.
-- Helium will soon expose a configuration API that enables you to
-- send configuration values over the air from the API to the Atom
-- Board.
--
-- @module ina219.config
-- @license MIT
-- @copyright 2017 Helium Systems, Inc

config = {}

--- Get a configuration value
-- @string key the key to get the config value for
-- @tparam[opt=nil] number|boolean default the default value to return
-- @treturn number|boolean the value stored in the configuration store. If the `he.config` module is not present on the device the default value is returned.
function config.get(key, default)
    -- check if system supports config
    if he.config then
        return he.config.get(key, default)
    else
        -- emulate config support
        assert(type(default) == "boolean" or type(default) == "number",
               "default should be a boolean or number ")
        return default
    end

end

return config
