local tiny     = require "tiny"
local json     = require "dkjson"
local errors   = require "errors"
local material = require "material-love"
local utils    = require "utils"
local lume     = require "lume"
local gui      = require "quickie"
gui.core.style = require "gui-style"
local basexx   = require "basexx"
local picker   = require "picker"

local function decode_avatar(avatar)
	assert(avatar)
	local data = avatar:sub(avatar:find(","),-1)
	local fd   = love.filesystem.newFileData(data, "avatar.png", "base64")
	local im   = love.graphics.newImage(love.image.newImageData(fd), {mipmaps=true, srgb=true})
	im:setFilter("linear", "linear", 16)
	im:setMipmapFilter("linear", 1)
	return im
end

local function encode_avatar(image, width, height)
	if not image then
		console.e("Avatar source image not found or invalid!")
		return
	end
	image:setFilter("linear", "linear", 16)
	image:setMipmapFilter("linear", 1)
	local c = love.graphics.newCanvas(width, height, "srgb")
	c:renderTo(function()
		local iw, ih = image:getDimensions()
		local s = math.max(width/iw, height/ih)
		love.graphics.draw(image, 0, 0, 0, s, s)
	end)
	local data = c:newImageData()
	data:encode("avatar-resized.png")
	local png = love.filesystem.read("avatar-resized.png")
	if png:len() < 16 then
		console.e("Invalid PNG!")
		return
	end
	local encoded = "data:image/png;base64," .. basexx.to_base64(png)
	local resized = love.graphics.newImage(data, {mipmaps=true, srgb=true})
	resized:setFilter("linear", "linear", 16)
	resized:setMipmapFilter("linear", 1)
	return encoded, resized
end

return function()
	local gs        = {}
	local user      = {}
	local av_ui     = {}
	local ui        = tiny.processingSystem()
	local active_ui = ui

	function av_ui:update(dt)
		local w, h = love.graphics.getDimensions()
		gui.group { grow = "down", pos = { 20, 20 }, function()
			if gui.Button { text = "Open" } then
				local path = picker.open("Select Avatar", { "Image Files (*.png)", "*.png" })
				if path then
					local f = io.open(path, "rb")
					-- copy avatar to save dir for easier use
					love.filesystem.write("avatar.png", f:read("*a"))
					f:close()
					local im = love.graphics.newImage("avatar.png", {mipmaps=true, srgb=true})
					self.encoded_av, self.av = encode_avatar(im, 64, 64)
				end
			end

			if gui.Button { text = "Done" } then
				active_ui = ui
				if self.encoded_av and self.encoded_av ~= self.original_av then
					Signal.emit("send-avatar", {
						avatar = self.encoded_av
					})
				end
				gs.world:addSystem(ui)
				gs.world:removeSystem(av_ui)
			end
		end }

		if self.av then
			love.graphics.draw(self.av, w/2-self.av:getWidth()/2, 20)
		end

		gui.core.draw()
	end

	local perform = {}
	function perform.login(name, password, save)
		gs.client = require("systems.client_login")(gs.world)
		gs.world:addSystem(gs.client)
		local ok, msg = gs.client:connect()
		if not ok then
			console.e("Connection error: %s", msg)
			return
		end
		save = save == "true" or tonumber(save or 0) > 0
		if name and name ~= "" then
			SETTINGS.username = name
			if save then
				SETTINGS.save()
			end
		elseif SETTINGS.username then
			name = SETTINGS.username
		else
			console.e("Please enter a username.")
			return
		end
		gs.client:send_login {
			username = name,
			password = password
		}

		local words = {
			"Welcome back",
			"Hi",
			"Howdy",
			"What's up",
			"Stay fresh"
		}
		gs.greeting = lume.randomchoice(words)
		gs.current_client = "login"
	end

	function perform.logout()
		assert(gs.client)
		assert(gs.world)
		gs.client:disconnect()
		gs.channel:disconnect()
		gs.current_client = "none"
	end

	function perform.realm(choice)
		if not choice then
			console.e("No realm selected")
			return
		end
		choice = tonumber(choice)
		local realm = user.realms[choice]
		if realm then
			console.i("Selected realm %d (%s)", choice, realm.name)
			user.realm = realm
			SETTINGS.realm = realm.name
			SETTINGS.save()
		else
			console.e("Invalid realm selected")
		end
	end

	function perform.character(choice)
		if not choice then
			console.e("No character selected")
			return
		end
		choice = tonumber(choice)
		local character = user.characters[choice]
		if character then
			console.i("Selected character %d (%s)", choice, character.alias)
			user.character = character
			SETTINGS.character = character.character_id
			SETTINGS.save()
		else
			console.e("Invalid character selected")
		end
	end

	--[[
		TO: client_login:send_realm_login

		Send chosen Character and Realm IDs to Login Client
	--]]
	function perform.enter()
		-- restore settings if needed
		if not user.character and SETTINGS.character then
			for _, character in ipairs(user.characters) do
				if tonumber(character.character_id) == tonumber(SETTINGS.character) then
					user.character = character
				end
			end
		end
		if not user.realm and SETTINGS.realm then
			for _, realm in ipairs(user.realms) do
				if realm.name == SETTINGS.realm then
					user.realm = realm
				end
			end
		end
		-- we'll just get rejected upon login without this stuff
		if not user.character then
			console.e("Please select a character")
			return
		end
		if not user.realm then
			console.e("Please select a realm")
			return
		end

		assert(gs.client)
		gs.client:send_realm_login {
			character_id = user.character.character_id,
			realm_id     = user.realm.id,
		}
	end

	-- join the party of another user
	function perform.join(user_alias)
		gs.client:send {
			type = "join",
			alias_id = user_alias
		}
	end

	-- invite a user to your party
	function perform.invite(user_alias)
		gs.client:send {
			type = "join",
			alias_id = user_alias
		}
	end

	-- leave party
	function perform.drop(party)
		gs.client:send {
			type = "drop"
		}
	end

	function perform.chat(cmd, channel, line)
		gs.client:send {
			type = "chat",
			command = cmd,
			channel = channel,
			message = line
		}
	end

	local register = {}
	function register.login(unregister)
		if unregister then
			console.clearCommand("login")
			return
		end
		console.defineCommand("login", "Log into the game server", perform.login)
	end

	function register.logout(unregister)
		if unregister then
			console.clearCommand("logout")
			console.clearCommand("show-realms")
			console.clearCommand("show-characters")
			console.clearCommand("show-account")
			return
		end
		console.defineCommand("logout", "Log out of the game server", perform.logout)
		console.defineCommand("show-realms", "Show available game realms", function()
			utils.print_r(user.realms)
		end)
		console.defineCommand("show-characters", "Show characters on your account", function()
			utils.print_r(user.characters)
		end)
		console.defineCommand("show-account", "Show your account information", function()
			utils.print_r(user.account)
		end)
	end

	function register.realm(unregister)
		if unregister then
			console.clearCommand("enter")
			console.clearCommand("realm")
			console.clearCommand("character")
			return
		end
		console.defineCommand("enter", "Enter game realm", perform.enter)
		console.defineCommand("realm", "Select game realm", perform.realm)
		console.defineCommand("character", "Select game character", perform.character)
	end

	function register.party(unregister)
		if unregister then
			console.clearCommand("join")
			console.clearCommand("invite")
			console.clearCommand("drop")
			return
		end
		console.defineCommand("join", "YOU ARE GOING TO LOVE ME", perform.join)
		console.defineCommand("invite", "GET OVER HERE", perform.invite)
		console.defineCommand("drop", "FUCK YOU!", perform.drop)
	end

	function register.chat(unregister)
		if unregister then
			console.clearCommand("global")
			console.clearCommand("area")
			console.clearCommand("say")
			console.clearCommand("yell")
			console.clearCommand("party")
			console.clearCommand("whisper")
			console.clearCommand("nick")
			return
		end

		local function concat_args(start, ...)
			local line = ""
			local n = select("#", ...)
			for i = start, n do
				line = line .. tostring(select(i, ...))
				if i < n then
					line = line .. " "
				end
			end
			return line
		end

		-- dupe dupe dupe dupe...
		local desc = "Shut the fuck out about motorcycles"
		console.defineCommand("global", desc, function(...)
			local line = concat_args(1, ...)
			perform.chat("global", "Global", line)
		end)

		console.defineCommand("area", desc, function(...)
			local line = concat_args(1, ...)
			perform.chat("area", "Planeptune City", line)
		end)

		console.defineCommand("say", desc, function(...)
			local line = concat_args(1, ...)
			perform.chat("say", "Say", line)
		end)

		console.defineCommand("yell", desc, function(...)
			local line = concat_args(1, ...)
			perform.chat("yell", "YELL", line)
		end)

		console.defineCommand("party", desc, function(...)
			local line = concat_args(1, ...)
			perform.chat("party", "Party", line)
		end)

		console.defineCommand("whisper", desc, function(...)
			local line = concat_args(2, ...)
			perform.chat("whisper", select(1, ...), line)
		end)

		console.defineCommand("nick", "Change your character alias", function(...)
			local line = concat_args(1, ...)
			gs.client:send_character_update {
				alias = line
			}
		end)
	end

	function gs:enter()
		self.world = tiny.world()
		self.world:addSystem(ui)
		self.channel = require("systems.client_channel")(self.world)
		self.world:addSystem(self.channel)
		self.channel.active = false

		self.users = {} --------------- MAKE ME INTO A SYSTEM!
		self.current_client = "none"
		self.chat_log = {}

		Signal.register("connect", function(server, connected)
			gs.server = server
			if server == "login" then
				register.login(true)
				register.logout()
				register.realm()
			end
			if server == "realm" then
				console.i("Connected to realm: %s", user.realm.name)
				register.chat()
				register.party()
			end
		end)
		Signal.register("disconnect", function(server, transfer)
			if not transfer then
				gs.world:removeSystem(gs.client)
				console.i("Disconnected from %s server", server)
				-- clear everything
				register.logout(true)
				register.realm(true)
				register.chat(true)
				register.party(true)
				register.login()
				while #self.users > 0 do
					table.remove(self.users)
					user.account = nil
					user.character = nil
				end
			end
			-- print(server, transfer and transfer.server_type or transfer)
			if server == "login" and transfer and transfer.server_type == "realm" then
				register.realm(true)
				register.chat(true)
				register.party(true)

				assert(user.account)
				assert(user.character)
				assert(gs.world)
				console.i("Disconnected from login server; transferring to realm %s...", transfer.name)

				local client = require("systems.client_realm")(gs.world)
				local ok, msg = client:connect(transfer.host, tonumber(transfer.port))
				if not ok then
					console.e("Unable to connect to realm: %s")
					return
				end

				--[[
					TO: client_realm:send_identify

					Send Session Token and Character ID to Realm Client.

					TODO: Move this to a less stupid place in the code.
				--]]
				client:send_identify {
					token        = transfer.token,
					character_id = user.character.character_id
				}
				gs.world:removeSystem(gs.client)
				gs.world:addSystem(client)
				gs.client = client
				self.current_client = "realm"
				-- something like this for realm-to-realm transfers
				-- if server == "realm" and transfer and transfer.server_type == "realm" then
				-- 	console.d("Transferring from realm %s to %s", user.realm.name, transfer.realm.name)
				-- end
				return
			end

			-- we're disconnected, safe to quit.
			if transfer and transfer.server_type == "quit" then
				console.i("Disconnected; shutting down...")
				SETTINGS.save()
				love.event.quit()
			end
		end)

		--[[
			FROM: client_login:recv_account

			Populate local user with received data.
		--]]
		Signal.register("recv-account", function(server, data)
			user.account    = data.account
			user.characters = data.characters
			for i, character in ipairs(user.characters) do
				if character.avatar then
					character.avatar = decode_avatar(character.avatar)
				end
			end
			console.i("Received account: %s", user.account.username)
		end)

		--[[
			FROM: client_login:recv_realm_list

			Populate local user with received data.
		--]]
		Signal.register("recv-realm-list", function(server, realms)
			user.realms = realms
		end)

		--[[
			FROM: client_login:recv_client_realm_handoff

			Populate local user with received data. Disconnect from Login Server and
			transfer to Realm Server.
		--]]
		Signal.register("recv-client-realm-handoff", function(server, token)
			gs.client:disconnect({
				server_type = "realm",
				name        = user.realm.name,
				host        = user.realm.host,
				port        = user.realm.port,
				token       = token
			})
			gs.current_client = "none"
		end)

		Signal.register("recv-client-channel-handoff", function(server, data)
			self.channel:connect(data.host, data.port)
			-- expected: token, host, port

			gs.channel:send_identify {
				token    = data.token,
				alias_id = user.character.alias_id
			}

			gs.current_client = "channel"
		end)

		--[[
			FROM: client_realm:recv_new_character

			Receive new character data.
		--]]
		Signal.register("recv-new-character", function(server, character)
			console.i("Received Character information from %s for %s", server, character.alias)

			if character.avatar then
				character.avatar = decode_avatar(character.avatar)
			end

			table.insert(self.users, character)

			if user.character.alias_id == character.alias_id then
				user.character = character
			end
		end)
		Signal.register("recv-remove-character", function(server, character)
			for i, user in ipairs(self.users) do
				if user.alias_id == character.alias_id then
					table.remove(self.users, i)
					break
				end
			end
		end)
		Signal.register("recv-account-update", function(server, account)

		end)
		Signal.register("recv-character-update", function(server, character)
			for _, user in ipairs(self.users) do
				if user.alias_id == character.old_alias_id or user.alias_id == character.alias_id then
					character.old_alias_id = nil

					if character.avatar then
						character.avatar = decode_avatar(character.avatar)
					end

					for i, item in pairs(character) do
						user[i] = item
					end

					break
				end
			end
		end)
		Signal.register("recv-chat", function(server, data)
			if data.channel == "YELL" then
				console.es("[%s] <%s> %s", data.channel, data.alias, data.line)
			else
				if data.id == user.character.alias_id then
					console.ds("[%s] <%s> %s", data.channel, data.alias, data.line)
				else
					console.is("[%s] <%s> %s", data.channel, data.alias, data.line)
				end
			end
			table.insert(gs.chat_log, data)
		end)
		Signal.register("recv-error", function(server, code)
			if code == errors.INVALID_LOGIN then
				register.logout(true)
				register.login()
			end
		end)
		Signal.register("send-avatar", function(data)
			user.avatar = data.avatar
			gs.client:send({
				type  = "character_update",
				avatar = data.avatar
			})
		end)

		register.login()
		if tonumber(SETTINGS.auto_login or 0) > 0 then
			self.auto_login = true
			self.login_timer = love.timer.getTime()
		end

		local w, h = love.graphics.getDimensions()
		local bg = love.graphics.newImage("assets/textures/CGUY4RyUIAA8LJX.png", { srgb = true })
		bg:setWrap("repeat", "repeat")
		local bg_quad = love.graphics.newQuad(0, 0, w, h, bg:getWidth(), bg:getHeight())

		function ui:update(dt)
			local w, h = love.graphics.getDimensions()

			if gs.current_client == "login" then
				love.graphics.setColor(255, 255, 255, 10)
				love.graphics.draw(bg, bg_quad, 0, 0)
				love.graphics.setColor(255, 255, 255, 255)
			end

			gui.group.default.size[1] = 150
			gui.group.default.size[2] = 25
			gui.group.default.spacing = 5

			-- status/info
			gui.group { grow = "down", pos = { 20, 20 }, function()
				love.graphics.setColor(255, 255, 255, 255)
				love.graphics.setFont(material.noto("body1"))

				if gs.auto_login then
					gui.Label { text = "Logging in..." }
					love.graphics.setFont(material.noto("title"))
					if love.timer.getTime() - gs.login_timer > 1 then
						perform.login()
						ui.show_user_settings = true
						gs.auto_login = false
					end
					return
				elseif console.hasCommand("login") then
					if gui.Button { text = "Login" } then
						perform.login()
						ui.show_user_settings = true
					end
					if gui.Button { text = "Exit" } then
						love.event.quit()
					end
					return
				end

				if not user.account then
					return
				end

				love.graphics.setFont(material.noto("title"))

				if gs.current_client == "channel" then
					if user.character and user.character.avatar then
						love.graphics.draw(user.character.avatar, 20, 20, 0, 1, 1)
					end
					gui.group.push { grow = "down", pos = { 84, 0 } }
				end
				gui.Label { text = console.hasCommand("enter") and string.format("%s, %s.", gs.greeting, user.account.username) or user.character.alias }
				love.graphics.setFont(material.noto("body1"))
				if console.hasCommand("logout") and not console.hasCommand("enter") then
					gui.group.push { grow = "down" }
					gui.Label { text = user.character.subtitle }
					gui.group.pop {}
				end
				if gs.current_client == "channel" then
					gui.group.pop {}
				end
			end }

			-- character list
			gui.group.push { grow = "down", pos = { 20, 80 } }
			if console.hasCommand("enter") and user.characters then
				love.graphics.setFont(material.noto("title"))
				gui.Label { text = "Characters" }
				love.graphics.setFont(material.noto("body1"))
				local spacing = 25
				for i, character in ipairs(user.characters) do
					local checked = user.character and user.character.character_id == character.character_id
					if character.avatar then
						love.graphics.draw(character.avatar, 200, 110+(i-1)*spacing, 0, 0.5, 0.5)
					end
					if not checked then
						checked = tonumber(SETTINGS.character) == character.character_id
					end
					if gui.Checkbox { checked = checked, text = character.alias } then
						perform.character(i)
					end
				end
				gui.group.getRect {}
			end

			-- character list
			if console.hasCommand("enter") and user.realms then
				love.graphics.setFont(material.noto("title"))
				gui.Label { text = "Realms" }
				love.graphics.setFont(material.noto("body1"))
				for i, realm in ipairs(user.realms) do
					local checked = user.realm and user.realm.name == realm.name
					if not checked then
						checked = SETTINGS.realm == realm.name
					end
					if gui.Checkbox { checked = checked, text = realm.name } then
						perform.realm(i)
					end
				end
			end
			gui.group.pop {}

			-- settings/session commands
			gui.group { grow = "down", pos = { w - 170, 20 }, function()
				if console.hasCommand("enter") then
					if gui.Button { text = "Enter" } then
						perform.enter()
						ui.show_user_settings = false
					end
				end
				if console.hasCommand("logout") then
					if gui.Button { text = "Settings" } then
						ui.show_user_settings = not ui.show_user_settings
					end
					if user.account and ui.show_user_settings then
						gui.group.push { grow = "down" }
						if gui.Checkbox { text = "Show name", checked = user.account.show_name, size = { "tight" } } then
							user.account.show_name = not user.account.show_name
						end
						if gui.Checkbox { text = "Show stats", checked = user.account.show_stats, size = { "tight" } } then
							user.account.show_stats = not user.account.show_stats
						end
						if gs.current_client == "channel" and gui.Button { text = "Change Avatar" } then
							active_ui = av_ui
							-- reset this every time it loads.
							av_ui.original_av = user.avatar
							av_ui.encoded_av  = nil
							av_ui.av          = nil
							gs.world:addSystem(av_ui)
							gs.world:removeSystem(ui)
						end
						gui.group.pop {}
					end

					gui.group.getRect {} -- #rekt

					if gui.Button { text = "Logout" } then
						perform.logout()
					end
					if gui.Button { text = "Exit" } then
						love.event.quit()
					end
				end
			end }

			-- character list
			gui.group { grow = "down", pos = { w - 400, 20 }, function()
				local i = 1
				for _, u in pairs(gs.users) do
					while true do -- pseudo-continue

					if u.alias_id == user.character.alias_id then
						break
					end

					local spacing = 20
					gui.Label { text = u.alias }
					if u.avatar then
						love.graphics.draw(u.avatar, w - 432 - 5, 20+(i-1)*spacing, 0, 0.5, 0.5)
					end
					i = i + 1
					break end
				end
			end}

			gui.group { grow = "down", pos = { 20, h - 300 }, function()
				if gs.chat_log then
					local text = ""
					local f = love.graphics.getFont()
					for i, line in ipairs(gs.chat_log) do
						text = text .. string.format("<%s> %s", line.alias, line.line)
						if i < #gs.chat_log then
							text = text .. "\n"
						end
					end
					local _, lines = f:getWrap(text, 380)
					local height = f:getHeight() * #lines
					love.graphics.setScissor(20, love.graphics.getHeight() - 240, 400, 200)
					for i, line in ipairs(lines) do
						love.graphics.print(line, 20, love.graphics.getHeight() - 80 - height + f:getHeight()*i)
					end
					-- love.graphics.printf(text, 40, love.graphics.getHeight() - 80 - height, 400, "left")
					love.graphics.setScissor()
				end
				-- for i = math.max(#gs.chat_log - 20, 1), #gs.chat_log do
				-- 	love.graphics.print()
				-- end
			end}

			gui.core.draw()
		end
	end

	function gs:keypressed(key, scan, is_repeat)
		if key == "escape" and love.keyboard.isDown("lshift") then
			love.event.quit()
		end
		if key == "f5" then
			local old = package.loaded["gui-style"]
			package.loaded["gui-style"] = nil
			local ok, new = pcall(require, "gui-style")
			if not ok then
				console.e(new)
			else
				gui.core.style = new
			end
		end
		gui.keyboard.pressed(key)
		-- ui:keypressed(key, scan, is_repeat)
	end
	function gs:textinput(t) end
	function gs:textedit(t, s, l) end
	function gs:focus(f) end
	function gs:mousemoved(x, y, dx, dy) end

	return gs
end
