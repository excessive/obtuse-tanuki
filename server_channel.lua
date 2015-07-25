require "love.filesystem"
require "love.timer"
require "thread-print"
require "settings"
Signal        = require "hump.signal"
local tiny    = require "tiny"
local world   = tiny.world()
local output  = love.thread.getChannel("output")
local command = love.thread.getChannel("server-command")

local function error_printer(msg, layer)
	print((debug.traceback("Error: " .. tostring(msg), 1+(layer or 1)):gsub("\n[^\n]+$", "")))
end

function errhand(msg)
	msg = tostring(msg)
	error_printer(msg, 2)
end

local function main()
	local server = require("systems.server_channel")(world)
	world:addSystem(server)
	world:addSystem(require("systems.cache")(world))
	world:addSystem(require("systems.movement")(world))

	server:start()
	output:push("started")

	local _then = love.timer.getTime()
	repeat
		local now = love.timer.getTime()
		local dt = now - _then
		_then = now

		xpcall(function() world:update(dt) end, errhand)
		love.timer.sleep(1/100)

		-- we still need to poll for events for a bit when a shutdown is queued
		if not shutdown then
			local cmd = command:pop()
			while cmd do
				if cmd == "shutdown" then
					server:stop()
					the_heat_death_of_the_universe = true
					break
				end
				cmd = command:pop()
			end
		end
	until the_heat_death_of_the_universe
end

main()
