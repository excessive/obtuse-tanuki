require "love.math"
local ffi          = require "ffi"
local tiny         = require "tiny"
local cpml         = require "cpml"
local json         = require "dkjson"
local lube         = require "lube"
local lume         = require "lume"
local errors       = require "errors"
local magic        = require "magic"
local utils        = require "utils"
local actions      = require "action_enum"
local packet_types = require "packet_types"
local cdata        = packet_types.cdata
local packets      = packet_types.packets

return function(world)
	local server_system  = tiny.system()
	server_system.filter = tiny.requireAll("replicate")
	server_system.world  = world
	server_system.cache  = {}

	function server_system:onAdd(entity)
		self.cache[entity.client_id] = entity
	end

	function server_system:onRemove(entity)
		self.cache[entity.client_id] = nil
	end

	function server_system:update(dt)
		if not self.connection then
			return
		end

		self.connection:update(dt)
	end

	function server_system:connect(client_id)
		console.d("Client %d connected", tostring(client_id))
	end

	function server_system:disconnect(client_id)
		console.d("Client %s disconnected", tostring(client_id))

		local entity = self.cache[client_id]
		assert(entity)

		self.world:removeEntity(entity)

		self.users.by_alias_id[entity.alias_id]  = nil

		if entity.party_id then
			self.users.by_party_id[entity.party_id]  = nil
		end

		for i, u in ipairs(self.users) do
			if u.id == entity.id then
				table.remove(self.users, i)
				break
			end
		end

		self:send_remove_character(entity.alias_id)
	end

	function server_system:disconnect_peer(client_id)
		local peer = self.connection.socket:get_peer(client_id)

		if peer then
			peer:disconnect_later()
		else
			console.e("Unable to disconnect client: %s", client_id)
		end
	end

	function server_system:start(port)
		self.active = true

		port = port or 2808
		self.connection = lube.enetServer()
		self.connection.handshake = magic.channel_handshake
		self.connection:setPing(true, 6, magic.ping)

		self.connection:listen(tonumber(port))
		console.i("[Channel Server] Server listening on port %d", port)

		function self.connection.callbacks.recv(d, id) self:recv(d, id) end
		function self.connection.callbacks.connect(id) self:connect(id) end
		function self.connection.callbacks.disconnect(id) self:disconnect(id) end

		self.tokens             = {}
		self.users              = {}
		self.users.by_alias_id  = {}
	end

	function server_system:stop()
		self.active = false
		the_heat_death_of_the_universe = true
	end

	--==[[ SEND DATA ]]==--

	function server_system:send(data, client_id, packet_type)
		local encoded

		if packet_type then
			data.type    = packets[packet_type]
			local struct = cdata:set_struct(packet_type, data)
			encoded      = cdata:encode(struct)
		else
			encoded = json.encode(data)
		end

		self.connection:send(encoded, client_id)
	end

	function server_system:send_server_channel_handoff(data, client_id)
		data.type = "server_channel_handoff"

		self:send(data, client_id)
	end

	--==[[ JSON SEND PACKETS ]]==--

	--[[
		FROM: self:recv_identify
		TO:   client_channel:recv_new_character

		Send character data to appropriate clients.
	--]]
	function server_system:send_new_character(data, client_id)
		-- send new client to users
		local d = {
			type       = "new_character",
			area_id    = data.area_id,
			party_id   = data.party_id,
			alias_id   = assert(data.alias_id),
			avatar_id  = assert(data.avatar_id),
			show_name  = assert(data.show_name),
			show_stats = assert(data.show_stats),
			subtitle   = assert(data.subtitle),
			model      = assert(data.model),
			alias      = assert(data.alias),
			avatar     = assert(data.avatar),
			position   = assert(data.position)
		}

		for _, user in ipairs(self.users) do
			if user.client_id ~= client_id then
				self:send(d, user.client_id)
			end
		end

		-- send users to new client
		for _, user in ipairs(self.users) do
			local d = {
				type       = "new_character",
				area_id    = user.area_id,
				party_id   = user.party_id,
				alias_id   = user.alias_id,
				avatar_id  = user.avatar_id,
				show_name  = user.show_name,
				show_stats = user.show_stats,
				subtitle   = user.subtitle,
				model      = user.model,
				alias      = user.alias,
				avatar     = user.avatar,
				position   = user.position
			}
			self:send(d, client_id)
		end
	end

	-- when a character DCs or whatever!
	function server_system:send_remove_character(alias_id)
		for _, user in ipairs(self.users) do
			if user.client_id ~= self.realm_server and user.alias_id ~= alias_id then
				local data = {
					type     = "remove_character",
					alias_id = alias_id
				}

				self:send(data, user.client_id)
			end
		end
	end

	function server_system:send_account_update(data, client_id)
		data.type = "account_update"

		for _, user in ipairs(self.users) do
			if user.client_id ~= self.realm_server then
				self:send(data, user.client_id)
			end
		end

		-- gather relevant list of people to send to

		-- self (client_id!)
		-- online friends
		-- people within dist range
	end

	function server_system:send_character_update(data, client_id)
		data.type = "character_update"

		for _, user in ipairs(self.users) do
			if user.client_id ~= self.realm_server then
				self:send(data, user.client_id)
			end
		end

		-- gather relevant list of people to send to

		-- self (client_id!)
		-- online friends
		-- people within dist range
	end

	function server_system:send_chat(data, client_id)
		data.type = "chat"
		self:send(data, client_id)
	end

	function server_system:send_error(code, client_id)
		local data = {
			type = "error",
			code = code
		}
		self:send(data, client_id)
	end

	--==[[ RECEIVE DATA ]]==--

	function server_system:recv(data, client_id)
		local header = cdata:decode("packet_type", data)
		local map    = packets[header.type]

		-- If CDATA detected
		if map then
			if self["recv_"..map.name] then
				local decoded = cdata:decode(map.name, data)
				self["recv_"..map.name](self, decoded, client_id)
			else
				console.e("Invalid packet type (%s) from client (%d)", header.type, client_id)
				console.d("Packet data: %s", data)
				return
			end
		-- Otherwise, assume JSON
		else
			local decoded = json.decode(data)

			if type(decoded) ~= "table" then
				console.e("Invalid packet from client (%d)", client_id)
				console.d("Packet data: %s", data)
				console.d("Decode data: %s", decoded)
				return
			end

			local type = decoded.type
			decoded.type = nil

			if type and self["recv_"..type] then
				self["recv_"..type](self, decoded, client_id)
			else
				console.e("Invalid packet type (%s) from client (%d)", type, client_id)
				console.d("Packet data: %s", data)
				return
			end
		end
	end

	--==[[ JSON RECEIVE PACKETS ]]==--

	--[[
		FROM: server_realm:send_handshake

		Verify Realm Server.
	--]]
	function server_system:recv_handshake(data, client_id)
		if data.hash == "some_hash" then
			self.realm_server = client_id
		else
			console.e("Invalid handshake '%s'.", data.shake)
		end
	end

	function server_system:recv_server_channel_handoff(data, client_id)
		if not client_id == self.realm_server then return end

		if not self.tokens[data.token] then
			console.d("New user: (%s) %s", data.token, data.alias)

			self.tokens[data.token] = {
				show_name    = assert(data.show_name),
				show_stats   = assert(data.show_stats),
				character_id = assert(data.character_id),
				alias_id     = assert(data.alias_id),
				avatar_id    = assert(data.avatar_id),
				area_id      = data.area_id,
				party_id     = data.party_id,
				avatar       = assert(data.avatar),
				alias        = assert(data.alias),
				subtitle     = assert(data.subtitle),
				model        = assert(data.model),
				position     = cpml.vec3(data.position),
				orientation  = cpml.quat(0, 0, 0, 1)
			}

			local d = { character_id = data.character_id }
			self:send_server_channel_handoff(d, client_id)
		else
			-- error, disconnect
		end
	end

	function server_system:recv_identify(data, client_id)
		local entity = self.tokens[data.token]

		if entity and entity.alias_id == data.alias_id then
			console.d("Accepted user: %s", entity.alias)

			self.tokens[data.token] = nil

			entity.client_id = client_id
			entity.replicate = true
			self.world:addEntity(entity)

			self.users.by_alias_id[entity.alias_id] = entity

			if entity.party_id then
				self.users.by_party_id[entity.party_id] = entity
			end

			table.insert(self.users, entity)

			self:send_new_character(entity, client_id)
		else
			console.e("Invalid identification: %s", data.token)
			self:send_error(errors.INVALID_SESSION_ID, client_id)
			self:disconnect_peer(client_id)
		end
	end



	function server_system:recv_account_update(data, client_id)
		-- verify data!
		local user = self.users.by_client_id[client_id]
		assert(user)

		local d = {}

		for i, item in pairs(data) do
			user[i]   = item
			d[i] = item
		end

		self:send_account_update(d, client_id)

		d.type = "account_update"
		self:send(d, self.realm_server)
	end

	function server_system:recv_character_update(data, client_id)
		-- verify data!
		local user = self.users.by_client_id[client_id]
		assert(user)

		local d = {}

		for i, item in pairs(data) do
			-- Don't update the name yet!
			if  i ~= "alias"
			and i ~= "avatar" then
				user[i] = item
				d[i]    = item
			end
		end

		-- Update clients
		self:send_character_update(d, self.realm_server)

		-- Update database
		d.character_id = user.character_id
		d.user_id      = user.id

		if data.alias then
			d.alias_id  = user.alias_id
			d.avatar_id = user.avatar_id
			d.alias     = data.alias
		end

		if data.avatar then
			d.alias_id  = user.alias_id
			d.avatar    = data.avatar

			-- no need to ask the server for this back, this is going to be the latest!
			-- saves 5-10kb from needing to round trip from login.
			user.avatar = data.avatar
		end

		d.type = "character_update"
		self:send(d, self.realm_server)
	end

	function server_system:recv_updated_alias(data, client_id)
		local user = self.users.by_alias_id[data.old_alias_id]
		assert(user)

		user.alias_id = data.alias_id
		user.alias    = data.alias

		self.users.by_alias_id[user.alias_id]     = user
		self.users.by_alias_id[data.old_alias_id] = nil

		local d = {
			alias_id     = user.alias_id,
			old_alias_id = data.old_alias_id,
			avatar_id    = user.avatar_id,
			alias        = user.alias
		}

		self:send_character_update(d, self.realm_server)
	end

	function server_system:recv_updated_avatar(data, client_id)
		local user = self.users.by_alias_id[data.alias_id]
		assert(user)

		user.avatar_id = data.avatar_id
		-- user.avatar    = data.avatar

		local d = {
			alias_id  = user.alias_id,
			avatar_id = user.avatar_id,
			avatar    = user.avatar
		}

		self:send_character_update(d, self.realm_server)
	end

	function server_system:recv_chat(data, client_id)
		local user

		if data.alias_id then
			user = self.users.by_alias_id[data.alias_id]
		else
			user = self.users.by_client_id[client_id]
		end

		assert(user)

		local alias   = tonumber(user.show_name) == 1 and user.alias or "Anon"
		local d = {
			alias_id = user.alias_id,
			command  = data.command,
			channel  = data.channel,
			alias    = alias,
			line     = data.message,
		}

		--==[[ Send chat message to appropriate players ]]==--

		-- if say command, send message to errbody nearby
		if data.command == "say" then
			for _, u in ipairs(self.users) do
				if u == user or u.position:dist(user.position) <= 20 then
					self:send_chat(d, u.client_id)
				end
			end

			return
		end

		-- if yell command, send message to errbody a bit further away
		if data.command == "yell" then
			for _, u in ipairs(self.users) do
				if u == user or u.position:dist(user.position) <= 100 then
					self:send_chat(d, u.client_id)
				end
			end

			return
		end

		if data.command == "global"
		or data.command == "area"
		or data.command == "party"
		or data.command == "whisper" then
			self:send_chat(d, self.realm_server)
		end
	end

	--==[[ CDATA RECEIVE PACKETS ]]==--

	function server_system:recv_client_action(data, client_id)
		if actions[data.action] then
			self["recv_action_"..actions[data.action]](self, data, client_id)
		else
			console.e("Invalid action: %d", data.action or 0)
		end
	end

	function server_system:recv_update_entity(data, client_id)
		local entity = self.cache[client_id]

		if not entity then return end

		-- Process data
		local position    = cpml.vec3(data.position_x,    data.position_y,    data.position_z)
		local orientation = cpml.quat(data.orientation_x, data.orientation_y, data.orientation_z, data.orientation_w)
		local velocity    = cpml.vec3(data.velocity_x,    data.velocity_y,    data.velocity_z)
		local scale       = cpml.vec3(data.scale_x,       data.scale_y,       data.scale_z)

		-- Determine latency
		local server = self.connection.socket
		local peer   = server:get_peer(client_id)
		local ping   = peer:round_trip_time() / 1000 / 2

		-- Compensate for latency
		position    = position + velocity * ping
		--orientation = orientation * ping
		--orientation = orientation:normalize()

		-- Assign data
		local rot_velocity  = orientation * entity.orientation:inverse()
		entity.position     = position
		entity.orientation  = orientation
		entity.velocity     = velocity
		entity.rot_velocity = rot_velocity
		entity.scale        = scale

		-- Prepare new data
		data.id             = entity.alias_id
		data.type           = packets.update_entity
		data.position_x     = position.x
		data.position_y     = position.y
		data.position_z     = position.z
		data.orientation_x  = orientation.x
		data.orientation_y  = orientation.y
		data.orientation_z  = orientation.z
		data.orientation_w  = orientation.w
		data.velocity_x     = velocity.x
		data.velocity_y     = velocity.y
		data.velocity_z     = velocity.z
		data.scale_x        = scale.x
		data.scale_y        = scale.y
		data.scale_z        = scale.z

		self:send(data, nil, "update_entity")
	end

	return server_system
end
