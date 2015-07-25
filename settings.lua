require "love.filesystem" -- needed in threads
local json = require "dkjson"

local file = "settings.json"
local defaults = {
	host_override = false,
}
local save
local reset

SETTINGS = {}

function save()
	SETTINGS.save = nil
	SETTINGS.reset = nil
	love.filesystem.write(file, json.encode(SETTINGS))

	SETTINGS.save = save
	SETTINGS.reset = reset
end

function reset()
	-- encode->decode is wasteful, but makes sure the types line up w/loaded
	SETTINGS = json.decode(json.encode(defaults))
	SETTINGS.save = save
	SETTINGS.reset = reset
end

if love.filesystem.isFile(file) then
	local data = love.filesystem.read(file)
	SETTINGS = json.decode(data)
	SETTINGS.save = save
	SETTINGS.reset = reset
else
	reset()
	save()
end
