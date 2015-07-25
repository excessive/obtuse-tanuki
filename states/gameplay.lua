local tiny     = require "tiny"
local gui      = require "quickie"
local material = require "material-love"
local errors   = require "errors"
local avatar   = require "avatar"
local utils    = require "utils"
local cpml     = require "cpml"
local utils    = require "utils"
local camera   = require "camera3d"

return function()
	local gs = tiny.system()
	gs.name  = "gameplay"

	function gs:enter(from, world, client, account, character)

		print(cpml.quat(0, 0, 0, 1) * cpml.quat.rotate(3.14/2, cpml.vec3(0, 0, 1)))


		self.client    = assert(client)
		self.world     = assert(world)
		self.realm     = assert(client)
		self.account   = assert(account)
		self.character = assert(character)

		self.dx, self.dy = 0, 0

		self.channel = require("systems.client_channel")(self.world)
		self.channel.active = false

		self.users = {}
		self.chat_log = {}

		self.show_user_settings = false

		gui.keyboard.clearFocus()

		self.camera  = camera(cpml.vec3(0, 0, 0))

		self.world:addSystem(require("systems.mesh_loader")(self.world))
		self.world:addSystem(require("systems.input")(self.world))
		self.world:addSystem(require("systems.movement")(self.camera))
		self.world:addSystem(require("systems.hit")(self.camera))
		self.world:addSystem(require("systems.render")(self.camera))

		-- queue object updates for the next frame
		self.world:addSystem(require("systems.cache")(self.world))

		self.signals = {}

		function self:register()
			self.signals["connect"] = Signal.register("connect", function(s)
				assert(s == "channel")
				self.channel.active = true

				console.i("Connected to channel server")
			end)

			self.signals["disconnect"] = Signal.register("disconnect", function(s, transfer)
				console.i("Disconnected from %s server", s)
				love.event.quit()
				-- if s == "channel" then
				-- 	-- TODO: change to another channel, we have a problem
				-- 	console.e("Disconnected from channel server!")
				-- 	return
				-- end
				--
				-- error(s)
			end)

			self.signals["recv-client-channel-handoff"] = Signal.register("recv-client-channel-handoff", function(server, data)
				assert(data.token)
				assert(data.host)
				assert(data.port)

				self.world:addSystem(self.channel)

				self.channel:connect(data.host, data.port)
				self.channel:send_identify {
					token    = data.token,
					alias_id = self.character.alias_id
				}
			end)

			--[[
				FROM: client_realm:recv_new_character

				Receive new character data.
			--]]
			self.signals["recv-new-character"] = Signal.register("recv-new-character", function(server, character)
				console.i("Received Character information from %s for %s", server, character.alias)

				assert(character.avatar)
				assert(character.avatar_id)
				assert(character.alias)
				assert(character.alias_id)
				assert(character.position)

				character.avatar_base64 = character.avatar
				character.avatar = avatar.decode(character.avatar_base64)

				character.replicate    = true
				character.id           = character.alias_id
				character.position     = cpml.vec3(character.position)
				character.orientation  = cpml.quat(0, 0, 0, 1)
				character.velocity     = cpml.vec3()
				character.rot_velocity = cpml.quat(0, 0, 0, 1)
				character.scale        = cpml.vec3(1, 1, 1)
				character.needs_reload = true

				if self.character.alias_id == character.alias_id then
					self.character = character
					character.possessed = true

					local plane = {
						id           = -2,
						position     = cpml.vec3(0, 0, -0.1),
						orientation  = cpml.quat(0, 0, 0, 1),
						velocity     = cpml.vec3(),
						rot_velocity = cpml.quat(0, 0, 0, 1),
						scale        = cpml.vec3(1, 1, 1),
						model        = "plane",
						needs_reload = true
					}
					self.world:addEntity(plane)

					debug_arrow = {
						id           = -1,
						position     = cpml.vec3(0, 5, 0),
						orientation  = cpml.quat(0, 0, 0, 1),
						velocity     = cpml.vec3(),
						rot_velocity = cpml.quat(0, 0, 0, 1),
						scale        = cpml.vec3(1, 1, 1),
						model        = "arrow",
						needs_reload = true
					}

					self.world:addEntity(debug_arrow)
				end

				self.world:addEntity(character)
				table.insert(self.users, character)
			end)

			self.signals["recv-remove-character"] = Signal.register("recv-remove-character", function(server, character)
				-- print("received character remove")
				for i, user in ipairs(self.users) do
					if user.alias_id == character.alias_id then
						self.world:removeEntity(user)
						table.remove(self.users, i)
						break
					end
				end
			end)

			self.signals["recv-character-update"] = Signal.register("recv-character-update", function(server, character)
				for _, user in ipairs(self.users) do
					if user.alias_id == character.old_alias_id or user.alias_id == character.alias_id then
						character.old_alias_id = nil

						if character.avatar then
							character.avatar_base64 = character.avatar
							character.avatar = avatar.decode(character.avatar)
						end

						for i, item in pairs(character) do
							user[i] = item
						end

						break
					end
				end
			end)

			self.signals["recv-chat"] = Signal.register("recv-chat", function(server, data)
				if data.channel == "YELL" then
					console.es("[%s] <%s> %s", data.channel, data.alias, data.line)
				else
					if data.id == self.character.alias_id then
						console.ds("[%s] <%s> %s", data.channel, data.alias, data.line)
					else
						console.is("[%s] <%s> %s", data.channel, data.alias, data.line)
					end
				end
				table.insert(self.chat_log, data)
			end)

			self.signals["recv-error"] = Signal.register("recv-error", function(server, code)
				-- this should reset the world automatically, I think
				-- if code == errors.INVALID_LOGIN then
				-- 	register.logout(true)
				-- 	register.login()
				-- end
			end)

			self.signals["send-avatar"] = Signal.register("send-avatar", function(data)
				self.character.avatar_base64 = assert(data.avatar)
				self.character.avatar = assert(data.encoded)
				self.client:send({
					type   = "character_update",
					avatar = data.avatar
				})
			end)
		end

		function self:unregister()
			for k, v in pairs(self.signals) do
				Signal.remove(k, v)
			end
		end

		self:register()
	end

	function gs:resume(from, ...)
		-- if from.name == "change_avatar" then
		-- 	local avatar = select(1, ...)
		-- 	if avatar then
		-- 		self.character.avatar = avatar
		-- 	end
		-- end
	end

	function gs:leave()
		self:unregister()
	end

	function gs:update(dt)
		if not self.channel.active then
			gui.group { grow = "down", pos = { 20, 20 }, function()
				love.graphics.setFont(material.noto("body1"))
				gui.Label { text = "Connecting..." }
			end }
			gui.core.draw()
			return
		end

		local w, h = love.graphics.getDimensions()

		gui.group { grow = "down", pos = { 20, 20 }, function()
			love.graphics.setFont(material.noto("title"))

			if self.character.avatar then
				love.graphics.draw(self.character.avatar, 20, 20, 0, 1, 1)
			end
			gui.group.push { grow = "down", pos = { 84, 0 } }

			gui.Label { text = self.character.alias }
			love.graphics.setFont(material.noto("body1"))

			gui.group.push { grow = "down" }
			gui.Label { text = self.character.subtitle }
			gui.group.pop {}

			gui.group.pop {}
		end}

		-- character list
		gui.group { grow = "down", pos = { w - 400, 20 }, function()
			local i = 1
			for _, u in pairs(gs.users) do
				while true do -- pseudo-continue

				if u.alias_id == self.character.alias_id then
					break
				end

				gui.Label { text = u.alias }
				if u.avatar then
					local spacing = 20
					love.graphics.draw(u.avatar, w - 432 - 5, 20+(i-1)*spacing, 0, 0.5, 0.5)
				end
				i = i + 1
				break end
			end
		end}

		-- settings/session commands
		gui.group { grow = "down", pos = { w - 170, 20 }, function()
			if gui.Button { text = "Settings" } then
				self.show_user_settings = not self.show_user_settings
			end
			if self.show_user_settings then
				gui.group.push { grow = "down" }
				gui.Label { text = "Nick" }
				gui.Input { info = { text = self.character.alias } }
				if gui.Checkbox { text = "Show name", checked = self.account.show_name, size = { "tight" } } then
					self.account.show_name = not self.account.show_name
				end
				if gui.Checkbox { text = "Show stats", checked = self.account.show_stats, size = { "tight" } } then
					self.account.show_stats = not self.account.show_stats
				end
				if gui.Button { text = "Change Avatar" } then
					Gamestate.push(require("states.change_avatar")(), self.world, self.character.avatar_base64)
				end
				gui.group.pop {}
			end

			-- gui.group.getRect {} -- #rekt

			-- if gui.Button { text = "Logout" } then
			-- 	perform.logout()
			-- end
			-- if gui.Button { text = "Exit" } then
			-- 	love.event.quit()
			-- end
		end }

		gui.core.draw()
	end

	function gs:textinput(s)
		gui.keyboard.textinput(s)
	end

	function gs:mousemoved(x, y, dx, dy)
		self.dx, self.dy = -dx, -dy
	end

	function gs:keypressed(key, scan, is_repeat)
		gui.keyboard.pressed(key)

		if key == "g" then
			love.mouse.setRelativeMode(not love.mouse.getRelativeMode())
		end
	end

	return gs
end
