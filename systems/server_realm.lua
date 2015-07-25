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
local client       = require "systems.client_realm_channel"
local actions      = require "action_enum"
local packet_types = require "packet_types"
local cdata        = packet_types.cdata
local packets      = packet_types.packets

return function(world)
	local server_system  = tiny.system()
	server_system.filter = tiny.requireAll("replicate")
	server_system.world  = world

	function server_system:onAdd(entity)
		self.cache[entity.id] = entity
	end

	function server_system:onRemove(entity)
		self.cache[entity.id] = nil
	end

	function server_system:update(dt)
		if not self.connection then
			return
		end

		self.connection:update(dt)

		for _, channel in ipairs(self.channels) do
			channel:update(dt)
		end
	end

	function server_system:connect(client_id)
		console.d("Client %d connected", tostring(client_id))
	end

	function server_system:disconnect(client_id)
		console.d("Client %d disconnected", tostring(client_id))
		local user = self.users.by_client_id[client_id]
		assert(user)

		self.users.by_client_id[client_id]     = nil
		self.users.by_alias_id[user.alias_id]  = nil

		if user.party_id then
			self.users.by_party_id[user.party_id]  = nil
		end

		local data = {
			type         = "logout_time",
			time         = os.time(),
			user_id      = user.id,
			character_id = user.character_id
		}
		self:send(data, self.login_server)

		-- no choice but to loop here.
		for i, u in ipairs(self.users) do
			if u.id == user.id then
				table.remove(self.users, i)
				break
			end
		end
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
		port = tonumber(port or 2807)
		self.connection = lube.enetServer()
		self.connection.handshake = magic.realm_handshake
		self.connection:setPing(true, 30, magic.ping)
		self.connection:listen(port)
		console.i("[Realm Server] Server listening on port %d", port)

		function self.connection.callbacks.recv(d, id)    self:recv(d, id)    end
		function self.connection.callbacks.connect(id)    self:connect(id)    end
		function self.connection.callbacks.disconnect(id) self:disconnect(id) end

		self.channels               = {}
		self.channels.by_channel_id = {}
		self.tokens                 = {}
		self.users                  = {}
		self.users.by_client_id     = {}
		self.users.by_alias_id      = {}
		self.users.by_party_id      = {}
	end

	function server_system:stop()
		self.shutdown = true
		for _, user in ipairs(self.users) do
			self:disconnect_peer(user.client_id)
		end
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

	--==[[ JSON SEND PACKETS ]]==--

	--[[
		FROM: self:recv_channels
		TO:   server_channel:recv_handshake

		Send a handshake to Channel Server
	--]]
	function server_system:send_handshake(channel)
		local data = {
			type = "handshake",
			hash = "some_hash"
		}
		channel:send(data)
	end

	--[[
		FROM: self:recv_server_realm_handoff
		TO:   server_login:recv_server_realm_handoff

		Reply to Login Server verifying data received for specific Player.
	--]]
	function server_system:send_server_realm_handoff(data, client_id)
		data.type = "server_realm_handoff"
		self:send(data, client_id)
	end

	--[[
		FROM: self:recv_identify
		TO:   server_channel:recv_server_channel_handoff

		Send Session Token and character data to Channel Server.
	--]]
	function server_system:send_server_channel_handoff(data, client_id)
		data.channel_id = lume.randomchoice(self.channels).id
		data.token      = lume.uuid()

		local d = {
			type         = "server_channel_handoff",
			show_name    = data.show_name,
			show_stats   = data.show_stats,
			character_id = data.character_id,
			alias_id     = data.alias_id,
			area_id      = data.area_id,
			party_id     = data.party_id,
			avatar_id    = data.avatar_id,
			avatar       = data.avatar,
			alias        = data.alias,
			subtitle     = data.subtitle,
			model        = data.model,
			position     = data.position,
			token        = data.token
		}

		self.channels.by_channel_id[data.channel_id]:send(d)
	end

	function server_system:send_client_channel_handoff(data, client_id)
		data.type = "client_channel_handoff"
		self:send(data, client_id)
	end

	function server_system:send_chat(data, client_id)
		data.type = "chat"
		self:send(data, client_id)
	end

	function server_system:send_error(error, client_id)
		local data = {
			type = "error",
			code = error,
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
		FROM: server_login:send_handshake

		Verify Login Server.
	--]]
	function server_system:recv_handshake(data, client_id)
		if data.hash == "some_hash" then
			self.login_server = client_id
		else
			console.e("Invalid handshake '%s'.", data.shake)
		end
	end

	--[[
		FROM: server_login:send_channels

		Receive available Channel Servers
	--]]
	function server_system:recv_channels(data, client_id)
		for _, channel_data in ipairs(data.channels) do
			local channel = client(self.world)

			table.insert(self.channels, channel)
			self.channels.by_channel_id[channel_data.id] = channel

			channel:connect(self, channel_data.id, channel_data.address, channel_data.port) -- reconnects until it works or the universe implodes
			self:send_handshake(channel)
		end
	end

	--[[
		FROM: server_login:send_server_realm_handoff
		TO:   self:send_server_realm_handoff

		Receive Session Token from Login Server and store Character data. Reply to
		Login Server verifying data received for specific Player.
	--]]
	function server_system:recv_server_realm_handoff(data, client_id)
		if not client_id == self.login_server then return end

		if not self.tokens[data.token] then
			console.d("New user: (%s) %s", data.token, data.username)

			self.tokens[data.token] = {
				id           = data.user_id,
				username     = data.username,
				show_name    = data.show_name,
				show_stats   = data.show_stats,
				character_id = data.character.character_id,
				alias_id     = data.character.alias_id,
				area_id      = data.character.area_id,
				party_id     = data.character.party_id,
				avatar_id    = data.character.avatar_id,
				avatar       = data.character.avatar,
				alias        = data.character.alias,
				subtitle     = data.character.subtitle,
				model        = data.character.model,
				last_login   = data.character.last_login,
				created_at   = data.character.created_at,
				position     = cpml.vec3(data.character.position)
			}

			local d = { user_id = data.user_id }
			self:send_server_realm_handoff(d, client_id)
		else
			-- error, disconnect
		end
	end

	--[[
		FROM: client_realm:send_identify
		TO:   self:send_server_channel_handoff
		TO:   self:send_new_character

		Receive Session Token and Character ID to verify client identity.
	--]]
	function server_system:recv_identify(data, client_id)
		local user = self.tokens[data.token]

		if user and user.character_id == data.character_id then
			console.d("Accepted user: %s", user.username)

			self.tokens[data.token] = nil

			user.client_id = client_id
			table.insert(self.users, user)

			self.users.by_client_id[client_id]    = user
			self.users.by_alias_id[user.alias_id] = user

			if user.party_id then
				self.users.by_party_id[user.party_id] = user
			end

			self:send_server_channel_handoff(user, client_id)
		else
			console.e("Invalid identification: %s", data.token)
			self:send_error(errors.INVALID_SESSION_ID, client_id)
			self:disconnect_peer(client_id)
		end
	end

	function server_system:recv_server_channel_handoff(data, client_id)
		for _, user in ipairs(self.users) do
			if user.character_id == data.character_id then
				local channel = self.channels.by_channel_id[user.channel_id]
				local d       = {
					token = user.token,
					host  = channel.host,
					port  = channel.port,
				}
				self:send_client_channel_handoff(d, user.client_id)

				return
			end
		end
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
			line     = data.message
		}

		--==[[ Send chat message to appropriate players ]]==--

		-- if global command, send message to errbody
		if data.command == "global" then
			for _, u in ipairs(self.users) do
				if u.client_id ~= self.login_server then
					self:send_chat(d, u.client_id)
				end
			end

			return
		end

		-- if area command, send message to errbody in same area
		if data.command == "area" then
			for _, u in ipairs(self.users) do
				if u == user or u.area == user.area then
					self:send_chat(d, u.client_id)
				end
			end

			return
		end

		-- if party command, send message to errbody in your party
		if data.command == "party" then
			for _, u in ipairs(self.users) do
				if user.party_id and (u == user or u.party_id == user.party_id) then
					self:send_chat(d, u.client_id)
				end
			end

			return
		end

		-- if whisper command, send your sweet nothings to only your sweetheart
		if data.command == "whisper" then
			console.e(data.channel)
			for _, u in ipairs(self.users) do
				if u == user or u.username == data.channel then
					self:send_chat(d, u.client_id)
				end
			end

			return
		end
	end

	-- join another user's party
	function server_system:recv_join(data, client_id)
		console.e("can't join the party yet ;_;")
		utils.print_r(data)
	end

	-- invite a user to party
	function server_system:recv_invite(data, client_id)
		console.e("can't invite people to the party yet ;_;")
		utils.print_r(data)
	end

	-- request to leave a party
	function server_system:recv_drop(data, client_id)
		console.e("can't stop partying ;_;")
		utils.print_r(data)
	end

	return server_system
end
