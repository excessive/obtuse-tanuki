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
local sqlite       = require "sqlite-ffi"
local sql          = require "queries"
local client       = require "systems.client_login_realm"
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

		for _, realm in ipairs(self.realms) do
			realm:update(dt)
		end
	end

	function server_system:connect(client_id)
		console.d("Client %d connected", tostring(client_id))
	end

	function server_system:disconnect(client_id)
		console.d("Client %d disconnected", tostring(client_id))
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
		-- if there's no database, copy the template file.
		if not love.filesystem.isFile("user.db") then
			love.filesystem.write("user.db", love.filesystem.read("db-template.sqlite"))
		end
		local db, err = sqlite.DBConnection(love.filesystem.getSaveDirectory() .. "/user.db")
		if db then
			console.i("[Login Server] Connected to database.")
			self.db = db
		else
			console.e("Could not connect to database: %s", err)
			return
		end

		local processed = {}
		local num_processed = 0
		local failed = false
		console.i("[Login Server] Compiling queries...")

		for server, set in pairs(sql) do
			processed[server] = {}
			for name, query in pairs(set) do
				local q, msg = self.db:prepare(query)
				if q then
					processed[server][name] = q
					num_processed = num_processed + 1
				else
					console.e("Failed to compile query: %s.%s (%s)", server, name, msg)
					failed = true
				end
			end
		end

		if failed then return end

		sql.prepared = processed
		console.i("[Login Server] %d queries compiled.", num_processed)

		port = tonumber(port or 2806)
		self.connection = lube.enetServer()
		self.connection.handshake = magic.login_handshake
		self.connection:setPing(true, 30, magic.ping)
		self.connection:listen(port)
		console.i("[Login Server] Login server listening on port %d", port)

		self.realms = {}
		self.realms.by_realm_id = {}
		self.users  = {}

		-- Build table of, and connect to realms
		local stmt = sql.prepared.login.select_realms
		stmt:reset(true)

		for row in stmt:results() do
			local realm_data = row:getTable()
			local realm = client(self.world)

			table.insert(self.realms, realm)
			self.realms.by_realm_id[realm_data.id] = realm

			realm:connect(self, realm_data.id, realm_data.name, realm_data.address, realm_data.port, self.db) -- reconnects until it works or the universe implodes
			self:send_handshake(realm)
		end

		-- Build table of channels and send to realms
		local stmt = sql.prepared.login.select_channels
		for realm_id, realm in ipairs(self.realms) do
			stmt:reset(true)
			stmt:bind(realm_id, "int64")

			local channels = {}
			for row in stmt:results() do
				local channel_data = row:getTable()
				table.insert(channels, channel_data)
			end

			self:send_channels(realm, channels)
		end

		function self.connection.callbacks.recv(d, id)    self:recv(d, id)    end
		function self.connection.callbacks.connect(id)    self:connect(id)    end
		function self.connection.callbacks.disconnect(id) self:disconnect(id) end
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
		FROM: self:start
		TO:   server_realm:recv_handshake

		Send a handshake to Realm Server
	--]]
	function server_system:send_handshake(realm)
		local data = {
			type = "handshake",
			hash = "some_hash"
		}
		realm:send(data)
	end

	--[[
		FROM: self:start
		TO:   server_realm:recv_channels

		Send available Channel Servers to Realm Server
	--]]
	function server_system:send_channels(realm, channels)
		local data = {
			type     = "channels",
			channels = channels
		}

		realm:send(data)
	end

	--[[
		FROM: server:recv_login
		TO:   client_login:recv_account

		Send account and character data to Player.
	--]]
	function server_system:send_account(data, client_id)
		local data = {
			type       = "account",
			account    = data.account,
			characters = data.characters
		}
		self:send(data, client_id)
	end

	--[[
		FROM: server:recv_login
		TO:   client_login:recv_realm_list

		Send list of available realms to Player.
	--]]
	function server_system:send_realms(client_id)
		local data = {}
		data.type = "realm_list"
		for r, realm in ipairs(self.realms) do
			table.insert(data, {
				id   = r,
				name = realm.name,
				host = realm.host,
				port = realm.port
			})
		end
		self:send(data, client_id)
	end

	--[[
		FROM: self:recv_realm_login
		TO:   server_realm:recv_server_realm_handoff

		Send Session Token and character data to Realm Server.
	--]]
	function server_system:send_server_realm_handoff(data, client_id)
		local realm = data.realm
		data.type   = "server_realm_handoff"
		data.realm  = nil

		self.realms[realm]:send(data)
	end

	--[[
		FROM: self:recv_server_realm_handoff
		TO:   client_login:recv_client_realm_handoff

		Send Session Token to Login Client.
	--]]
	function server_system:send_client_realm_handoff(data, client_id)
		data.type = "client_realm_handoff"
		self:send(data, client_id)

		for u, user in ipairs(self.users) do
			if user.client_id == client_id then
				self.users[u] = nil
				return
			end
		end
	end

	--[[
		TO: client_login:recv_error

		Send Login Client an error code.
	--]]
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
		FROM: client_login:send_login
		TO:   self:send_account
		TO:   self:send_realms

		Player attempts to log in using their credentials. If login is successful, we
		send Player back some account information, character information, and a list
		of available realms.
	--]]
	function server_system:recv_login(data, client_id)
		local stmt = sql.prepared.login.recv_credentials
		stmt:reset(true)
		stmt:bind {
			{ data.username, "text" },
			{ data.password, "text" }
		}

		-- Get result
		local row = stmt:results()()

		if row then
			local result = row:getTable()
			local user = {}

			user.client_id = client_id

			user.account = {
				user_id       = result.id,
				username      = result.username,
				show_name     = result.show_name,
				show_stats    = result.show_stats,
				status        = result.status,
				last_login    = result.last_login,
				last_realm_id = result.last_realm_id,
				created_at    = result.created_at
			}

			local stmt = sql.prepared.login.select_characters
			stmt:reset(true)
			stmt:bind(result.id, "int")

			user.characters = {}
			for row in stmt:results() do
				local character = row:getTable()

				table.insert(user.characters, {
					character_id = character.character_id,
					alias_id     = character.alias_id,
					area_id      = character.area_id,
					party_id     = character.party_id,
					avatar_id    = character.avatar_id,
					alias        = character.alias,
					subtitle     = character.subtitle,
					model        = character.model,
					last_login   = character.last_login,
					created_at   = character.created_at,
					avatar       = character.avatar, -- I HOPE YOU LIKE DATA
					position     = cpml.vec3(
						character.position_x,
						character.position_y,
						character.position_z
					)
				})
			end

			table.insert(self.users, user)

			self:send_account(user, client_id)
			self:send_realms(client_id)
		else
			console.e("Attempted login to account '%s'", data.username)
			self:send_error(errors.INVALID_LOGIN, client_id)
			self:disconnect_peer(client_id)
		end
	end

	--[[
		FROM: client_login:send_realm_login
		TO:   self:send_realm_handoff

		Verify Client and Realm IDs then execute server handoff process.
	--]]
	function server_system:recv_realm_login(data, client_id)
		for _, user in ipairs(self.users) do
			for c, character in ipairs(user.characters) do
				if data.character_id == character.character_id then
					user.token = lume.uuid()

					local d     = user.account
					d.character = user.characters[c]
					d.realm     = data.realm_id
					d.token     = user.token

					self:send_server_realm_handoff(d, client_id)

					return
				end
			end
		end
	end

	--[[
		FROM: server_realm:send_server_realm_handoff
		TO:   self:send_client_realm_handoff

		Receive verification of handoff from Realm Server.
	--]]
	function server_system:recv_server_realm_handoff(data)
		for _, user in ipairs(self.users) do
			if user.account.user_id == data.user_id then
				local d = { token = user.token }
				self:send_client_realm_handoff(d, user.client_id)

				return
			end
		end
	end

	return server_system
end
