local tiny     = require "tiny"
local gui      = require "quickie"
local avatar   = require "avatar"
local material = require "material-love"
local lume     = require "lume"
local anim8    = require "anim8"

-- This state is active from username entry until we get account and realm info
return function()
	local gs = tiny.system()
	gs.name   = "character_select"

	function gs:enter(from, world, client, user)
		assert(world)
		assert(client)
		assert(user)

		self.world  = world
		self.active = true

		self.client = client
		self.user   = user

		self.greeting = lume.randomchoice {
			"Welcome back",
			"Hi",
			"Howdy",
			"What's up",
			"Stay fresh"
		}

		gui.keyboard.clearFocus()

		self.signals = {}

		-- self.platinum  = love.graphics.newImage("assets/textures/platinum 7x2.png", { srgb = true })
		-- local g = anim8.newGrid(self.platinum:getWidth()/7, self.platinum:getHeight()/2, self.platinum:getWidth(), self.platinum:getHeight())
		-- self.animation = anim8.newAnimation(g('1-7', 1, '1-7', 2), 1/13)

		-- local w, h = love.graphics.getDimensions()

		-- self.bg = {
		-- 	img  = love.graphics.newImage("assets/textures/CGUY4RyUIAA8LJX.png", { srgb = true })
		-- }
		-- self.bg.img:setWrap("repeat", "repeat")
		self:resize(love.graphics.getDimensions())

		-- this is dumb, but scoooooope
		function self:register()
			self.signals["connect"] = Signal.register("connect", function(s)
				if s == "realm" then
					print("asdf")
				end
			end)

			self.signals["disconnect"] = Signal.register("disconnect", function(s, transfer)
				if transfer and transfer.server_type == "quit" then
					return
				end

				assert(s == "login")
				if transfer then
					assert(transfer.server_type == "realm")
					assert(self.user.account)
					assert(self.user.character)
					console.i("Disconnected from login server; transferring to realm %s...", transfer.name)

					local client = require("systems.client_realm")(self.world)
					local ok, msg = client:connect(transfer.host, transfer.port)
					if not ok then
						console.e("Unable to connect to realm: %s", msg)
					else
						--[[
							TO: client_realm:send_identify

							Send Session Token and Character ID to Realm Client.

							TODO: Move this to a less stupid place in the code.
						--]]
						client:send_identify {
							token        = transfer.token,
							character_id = self.user.character.character_id
						}
						self.world:removeSystem(self.client)
						self.world:addSystem(client)
						console.i("Realm connected; entering game")
						Gamestate.switch(
							require("states.gameplay")(),
							self.world, client,
							self.user.account, self.user.character
						)
					end
				else
					self.world:removeSystem(self.client)
					console.i("Disconnected from %s server", s)
					self:unregister()
					self:register()
				end
			end)

			--[[
				FROM: client_login:recv_client_realm_handoff

				Populate local user with received data. Disconnect from Login Server and
				transfer to Realm Server.
			--]]
			self.signals["recv-client-realm-handoff"] = Signal.register("recv-client-realm-handoff", function(s, token)
				assert(s == "login")
				assert(self.user.realm)
				self.client:disconnect {
					server_type = "realm",
					name        = self.user.realm.name,
					host        = self.user.realm.host,
					port        = self.user.realm.port,
					token       = token
				}
			end)
		end

		function self:unregister()
			for k, v in pairs(self.signals) do
				Signal.remove(k, v)
			end
		end

		self:register()
		self:register_commands()
	end

	function gs:register_commands(unregister)
		if unregister then
			console.clearCommand("login")
			console.defineCommand("logout", "Log out of the game server")
			return
		end
		console.defineCommand("login", "Log into the game server", function(...) self:perform_login(...) end)
		console.clearCommand("logout")
	end

	function gs:leave()
		self:unregister()
		console.clearCommand("login")
	end

	function gs:perform_realm(choice)
		if not choice then
			console.e("No realm selected")
			return
		end
		choice = tonumber(choice)
		local realm = self.user.realms[choice]
		if realm then
			console.i("Selected realm %d (%s)", choice, realm.name)
			self.user.realm = realm
			SETTINGS.realm = realm.name
			SETTINGS.save()
		else
			console.e("Invalid realm selected")
		end
	end

	function gs:perform_character(choice)
		if not choice then
			console.e("No character selected")
			return
		end
		choice = tonumber(choice)
		local character = self.user.characters[choice]
		if character then
			console.i("Selected character %d (%s)", choice, character.alias)
			self.user.character = character
			SETTINGS.character = character.character_id
			SETTINGS.save()
		else
			console.e("Invalid character selected")
		end
	end

	function gs:perform_enter()
		assert(self.client)

		-- restore settings if needed
		if not self.user.character and SETTINGS.character then
			for _, character in ipairs(self.user.characters) do
				if tonumber(character.character_id) == tonumber(SETTINGS.character) then
					self.user.character = character
				end
			end
		end
		if not self.user.realm and SETTINGS.realm then
			for _, realm in ipairs(self.user.realms) do
				if realm.name == SETTINGS.realm then
					self.user.realm = realm
				end
			end
		end
		-- we'll just get rejected upon login without this stuff
		if not self.user.character then
			console.e("Please select a character")
			return
		end
		if not self.user.realm then
			console.e("Please select a realm")
			return
		end

		self.client:send_realm_login {
			character_id = self.user.character.character_id,
			realm_id     = self.user.realm.id,
		}
	end

	function gs:perform_logout()
		self.client:disconnect()
		SETTINGS.auto_login = false
		SETTINGS.save()
	end

	function gs:keypressed(key, scan, is_repeat)
		gui.keyboard.pressed(key)
	end

	function gs:resize(w, h)
		-- local bg = self.bg.img
		-- self.bg.quad = love.graphics.newQuad(0, 0, w, h, bg:getWidth(), bg:getHeight())
	end

	function gs:update(dt)
		local w, h = love.graphics.getDimensions()

		-- love.graphics.setColor(255, 255, 255, 10)
		-- love.graphics.draw(self.bg.img, self.bg.quad, 0, 0)
		love.graphics.setColor(255, 255, 255, 255)

		-- self.animation:update(dt)
		-- self.animation:draw(self.platinum, w - self.platinum:getWidth()/7 - 5, h - self.platinum:getHeight()/2)
		-- self.animation:flipH()
		-- self.animation:draw(self.platinum, 5, h - self.platinum:getHeight()/2)
		-- self.animation:flipH()

		-- Account status
		gui.group { grow = "down", pos = { 20, 20 }, function()
			local account = self.user.account
			love.graphics.setFont(material.noto("title"))

			gui.Label { text = string.format("%s, %s.", self.greeting, account.username) }

			love.graphics.setFont(material.noto("body1"))
			gui.Label { text = string.format("Last login: %s", os.date("%Y-%m-%d %H:%M:%S", account.last_login)) }
		end }

		-- Session controls
		gui.group { grow = "down", pos = { w - 170, 20 }, function()
			if gui.Button { text = "Play" } then
				self:perform_enter()
			end

			local account = self.user.account
			-- gui.group { grow = "down", function()
				-- if gui.Checkbox { text = "Show name", checked = account.show_name, size = { "tight" } } then
				-- 	account.show_name = not account.show_name
				-- end
				-- if gui.Checkbox { text = "Show stats", checked = account.show_stats, size = { "tight" } } then
				-- 	account.show_stats = not account.show_stats
				-- end
			-- end }

			gui.group.getRect {} -- #rekt

			if gui.Button { text = "Logout" } then
				self:perform_logout()
			end
			if gui.Button { text = "Exit" } then
				love.event.quit()
			end
		end }

		gui.group { grow = "down", pos = { 20, 100 }, function()
			-- character list
			love.graphics.setFont(material.noto("title"))
			gui.Label { text = "Characters" }
			love.graphics.setFont(material.noto("body1"))
			local spacing = 25
			for i, character in ipairs(self.user.characters) do
				local checked = self.user.character and self.user.character.character_id == character.character_id
				if character.avatar then
					love.graphics.draw(character.avatar, 200, 130+(i-1)*spacing, 0, 0.5, 0.5)
				end
				if not checked then
					checked = tonumber(SETTINGS.character) == character.character_id
				end
				if gui.Checkbox { checked = checked, text = character.alias } then
					self:perform_character(i)
				end
			end
			gui.group.getRect {}

			-- realm list
			love.graphics.setFont(material.noto("title"))
			gui.Label { text = "Realms" }
			love.graphics.setFont(material.noto("body1"))
			for i, realm in ipairs(self.user.realms) do
				local checked = self.user.realm and self.user.realm.name == realm.name
				if not checked then
					checked = SETTINGS.realm == realm.name
				end
				if gui.Checkbox { checked = checked, text = realm.name } then
					self:perform_realm(i)
				end
			end
		end }

		gui.core.draw()
	end

	return gs
end
