config = {}

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
