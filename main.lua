love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";libs/?.lua;libs/?/init.lua")

require "settings"
Gamestate  = require "hump.gamestate"
Signal     = require "hump.signal"
console    = require "console"
local tiny = require "tiny"
local lume = require "lume"

local output = love.thread.getChannel("output")
local command = love.thread.getChannel("server-command")

local flags = {
	["debug"]       = false,
	["headless"]    = love.filesystem.isFile("headless"),
	["login"]       = false,
	["realm"]       = false,
	["channel"]     = false,
	["all-servers"] = false,
}

local servers = {}
local queued_shutdown = false
local servers_up = 0
local all_up = false

local function reload_gui_style()
	local gui = require "quickie"
	local old = package.loaded["gui-style"]
	package.loaded["gui-style"] = nil
	local ok, new = pcall(require, "gui-style")
	if not ok then
		console.e(new)
	else
		gui.core.style = new
	end
end

function love.load(args)
	for _, arg in pairs(args) do
		if arg:sub(1,2) == "--" then
			local flag = arg:sub(3)
			flags[arg:sub(3)] = true
		end
	end

	if not flags.headless then
		local window = {
			width  = 1280,
			height = 720,
			title  = "User Test",
			icon   = nil,
			flags  = {
				resizable  = true,
				vsync      = true,
				msaa       = 4,
				minwidth   = 960,
				minheight  = 540,
				srgb       = true,
				fullscreentype = "desktop",
				fullscreen = false,
				borderless = false,
				display    = 1,
				highdpi    = false
			}
		}
		love.window.setMode(window.width, window.height, window.flags)
		love.window.setTitle(window.title)
		if window.icon then
			love.window.setIcon(window.icon)
		end
		require("love3d").import(true) -- prepare your body, love2d

		console.load(love.graphics.newFont("assets/fonts/unifont-7.0.06.ttf", 16), true)
	end

	if flags["all-servers"] then
		flags.login   = true
		flags.realm   = true
		flags.channel = true
	end

	if flags.login then
		local login_server = love.thread.newThread("server_login.lua")
		login_server:start()
		servers[login_server] = "login"
		table.insert(servers, login_server)
	end

	if flags.realm then
		local realm_server = love.thread.newThread("server_realm.lua")
		realm_server:start()
		servers[realm_server] = "realm"
		table.insert(servers, realm_server)
	end

	if flags.channel then
		local channel_server = love.thread.newThread("server_channel.lua")
		channel_server:start()
		servers[channel_server] = "channel"
		table.insert(servers, channel_server)
	end

	if not flags.headless then
		console.clearCommand("quit")
		console.defineCommand(
			"quit",
			"Disconnect and exit the game",
			function()
				love.event.quit()
			end
		)
		console.defineCommand(
			"open-save-folder",
			"Open the save folder in your system file manager",
			function()
				love.system.openURL("file://"..love.filesystem.getSaveDirectory())
			end
		)
		console.defineCommand(
			"setting",
			"View or change a setting",
			function(...)
				local setting = select(1, ...)
				local value = select(2, ...)
				if not setting then
					console.i("Usage: setting <name> [value]")
					return
				end
				if value then
					SETTINGS[setting] = value
					SETTINGS.save()
					console.i("Saved setting: %s = %s", setting, value)
				else
					console.i("%s: %s", setting, SETTINGS[setting])
				end
			end
		)
		if flags.debug then
			--THIS IS A REALLY DANGEROUS FUNCTION, REMOVE IT IF YOU DONT NEED IT
			console.defineCommand(
				"lua",
				"Lets you run lua code from the terminal",
				function(...)
					local cmd = ""
					for i = 1, select("#", ...) do
						cmd = cmd .. tostring(select(i, ...)) .. " "
					end
					if cmd == "" then
						console.i("This command lets you run lua code from the terminal.")
						console.i("It's a really dangerous command. Don't use it!")
						return
					end
					xpcall(loadstring(cmd), console.e)
				end,
				true
			)
			console.defineCommand(
				"host",
				"Override all server connections with a specified host",
				function(...)
					local host = select(1, ...)
					if host == "none" then
						console.i("Removed host override.")
						SETTINGS.host_override = false
						SETTINGS.save()
					elseif host and host ~= "" then
						console.i("Set host override to %s", host)
						SETTINGS.host_override = host
						SETTINGS.save()
					else
						console.i("Usage: host <hostname|none>")
						console.i("Current host: %s", SETTINGS.host_override or "none")
					end
				end
			)
		end

		-- Don't show line information unless you're in debug mode
		if not flags.debug then
			-- ...and don't show debug prints at all!
			console.d  = function() end
			console.ds = function() end
			console.i  = console.is
			console.e  = console.es
		end

		local function reset_the_world(fresh)
			local world
			if fresh then
				world = tiny.world()
			else
				world = Gamestate.current().world
				world:clearEntities()
				world:clearSystems()
				world:update(0)
			end
			Gamestate.switch(require("states.login")(), world)
		end

		-- Global disconnect handler, do *NOT* clear it!
		Signal.register("disconnect", function(s, transfer)
			-- we're disconnected, safe to quit.
			if transfer and transfer.server_type == "quit" then
				console.i("Disconnected; shutting down...")
				SETTINGS.save()
				love.event.quit()
				return
			end

			if not transfer then
				console.i("Disconnected from %s server; resetting the world", s)
				reset_the_world()
			end
		end)

		Gamestate.registerEvents()
		reload_gui_style()
		reset_the_world(true)
	end
end

-- Don't quit until we've cleaned up all of our network connections.
-- This prevents a lot of weird minor issues from being apparent, e.g. last
-- login times not being up to date if you close the client and start it again
-- before the server has timed you out.
function love.quit()
	local cancel = false
	if not flags.headless then
		local gs = Gamestate.current()

		if gs.client and gs.client.connection and gs.client.connection.connected then
			gs.client:disconnect { server_type="quit" }
			cancel = true
		end
	end

	if #servers > 0 then
		if not queued_shutdown then
			for i=1,#servers do
				command:push("shutdown")
			end
		end
		queued_shutdown = true
		cancel = true
	end

	if not cancel then
		console.i("Goodbye!")
		console.update(0)
		return false
	end

	return true
end

-- Painfully, we can't get a thread backtrace from here. The only way to get
-- one is if you xpcall everything in a thread yourself to gather the trace
-- and push the results over a channel...
function love.threaderror(t, e)
	console.e("%s: %s", t, e)
end

function love.keypressed(key, scan, is_repeat)
	if key == "escape" and love.keyboard.isDown("lshift") then
		love.event.quit()
		return true
	end
	if key == "f5" then
		reload_gui_style()
		return true
	end
end

function love.update(dt)
	local state
	if not flags.headless then
		state = Gamestate.current()
		if Gamestate.current().next then
			Gamestate.switch(Gamestate.current().next)
			state = Gamestate.current()
			state.first_update = true
		end
		love.window.setTitle(string.format("User Test (FPS: %0.2f, MSPF: %0.3f)", love.timer.getFPS(), love.timer.getAverageDelta() * 1000))
	end
	local s = output:pop()
	while s do
		local f = s:sub(1,1) .. "s"
		local line = s:sub(2)
		-- console.ps is special
		if not console[f] or f == "ps" then
			f = "es"
		end
		if s == "started" then
			servers_up = servers_up + 1
			if servers_up == #servers then
				all_up = true
			end
		else
			console[f](line)
		end
		s = output:pop()
	end
	for i, server in lume.ripairs(servers) do
		if not server:isRunning() then
			console.i("Server %d dead (%s)", i, servers[server])
			table.remove(servers, i)
		end
	end
	if not flags.headless then
		if state.world then
			state.world:update(dt)
			if state.first_update then
				state.first_update = false
			end
		end
	end
end

function love.run()
	if love.math then
		love.math.setRandomSeed(os.time())
		for i=1,3 do love.math.random() end
	end

	if love.event then
		love.event.pump()
	end

	if love.load then love.load(arg) end

	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then love.timer.step() end

	local dt = 0

	-- Main loop time.
	while true do
		-- Process events.
		if love.event then
			love.event.pump()
			for name, a,b,c,d,e,f in love.event.poll() do
				if name == "quit" then
					if not love.quit or not love.quit() then
						return
					end
				end
				if not console[name] or not console[name](a,b,c,d,e,f) then
					love.handlers[name](a,b,c,d,e,f)
				end
			end
		end

		if queued_shutdown and #servers == 0 then
			console.update(0)
			love.event.quit()
		end

		-- Update dt, as we'll be passing it to update
		if love.timer then
			love.timer.step()
			dt = love.timer.getDelta()
		end

		-- Call update and draw
		if love.graphics and love.graphics.isActive() and not flags.headless then
			love.graphics.clear(love.graphics.getBackgroundColor())
			love.graphics.origin()

			console.update(dt) -- make sure the console is always updated
			love.update(dt) -- will pass 0 if love.timer is disabled

			if console then console.draw() end
			love.graphics.present()

			-- surrender just a little bit of CPU time to the OS
			if love.timer then love.timer.sleep(0.001) end

			-- Run a fast GC cycle so that it happens at predictable times.
			collectgarbage("step")
		elseif flags.headless then
			-- main thread doesn't need to go fast if we're headless.
			love.timer.sleep(0.01)
			console.update(dt) -- make sure the console is always updated
			love.update(dt) -- will pass 0 if love.timer is disabled
		end
	end
end
