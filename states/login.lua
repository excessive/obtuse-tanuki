local tiny     = require "tiny"
local gui      = require "quickie"
local avatar   = require "avatar"
local material = require "material-love"

-- This state is active from username entry until we get account and realm info
return function()
	local gs = tiny.system()
	gs.name  = "login"

	function gs:enter(from, world)
		assert(world)
		self.world  = world
		self.active = true
		self.world:addSystem(self)

		self.auto_login = SETTINGS.auto_login
		self.user_info  = {
			text = SETTINGS.username or ""
		}
		if self.auto_login then
			self.login_timer = love.timer.getTime()
		end

		self.user = {}

		gui.group.default.size[1] = 150
		gui.group.default.size[2] = 25
		gui.group.default.spacing = 5
		gui.keyboard.clearFocus()

		self.signals = {}

		function self:register()
			self.signals["connect"] = Signal.register("connect", function(s)
				if s == "login" then
					self:register_commands(true)
				end
			end)

			--[[
				FROM: client_login:recv_account

				Populate local user with received data.
			--]]
			self.signals["recv-account"] = Signal.register("recv-account", function(s, data)
				assert(s == "login")
				assert(data)
				assert(data.account)
				assert(data.characters)

				self.user.account    = data.account
				self.user.characters = data.characters

				for i, character in ipairs(self.user.characters) do
					if character.avatar then
						character.avatar = avatar.decode(character.avatar)
					end
				end

				console.i("Received account: %s", data.account.username)
			end)

			--[[
				FROM: client_login:recv_realm_list

				Populate local user with received data.
			--]]
			self.signals["recv-realm-list"] = Signal.register("recv-realm-list", function(s, realms)
				assert(s == "login")
				assert(realms)
				self.user.realms = realms

				console.i("Received %d realm(s)", #realms)
				-- for i, realm in ipairs(realms) do
				-- 	console.d("Realm %d: %s", i, realm.name)
				-- end
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
		self:register_commands(true)
	end

	function gs:perform_login(name, password, save)
		self.client = require("systems.client_login")(self.world)
		self.world:addSystem(self.client)
		local ok, msg = self.client:connect()
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
		self.client:send_login {
			username = name,
			password = password
		}
	end

	function gs:textinput(s)
		gui.keyboard.textinput(s)
	end

	function gs:keypressed(key, scan, is_repeat)
		gui.keyboard.pressed(key)
	end

	function gs:update(dt)
		if self.user.account and self.user.characters and self.user.realms then
			console.i("Account info received; loading character select")
			Gamestate.switch(require("states.character_select")(), self.world, self.client, self.user)
		end

		gui.group { grow = "down", pos = { 20, 20 }, function()
			love.graphics.setColor(255, 255, 255, 255)
			love.graphics.setFont(material.noto("body1"))

			if self.auto_login then
				gui.Label { text = "Logging in..." }
				love.graphics.setFont(material.noto("title"))
				if love.timer.getTime() - self.login_timer > 1 then
					self:perform_login()
					self.auto_login = false
				end
			elseif console.hasCommand("login") then
				gui.Label { text = "Username" }
				gui.Input { info = self.user_info, size = { 305 } }
				gui.group { grow = "right", function()
					if gui.Button { text = "Login" } then
						self:perform_login(self.user_info.text)
					end
					if gui.Checkbox { checked = SETTINGS.auto_login, text = "Remember Me" } then
						SETTINGS.auto_login = not SETTINGS.auto_login
					end
				end }
				gui.group.getRect()
				if gui.Button { text = "Exit" } then
					love.event.quit()
				end
			end
		end }

		gui.core.draw()
	end

	return gs
end
