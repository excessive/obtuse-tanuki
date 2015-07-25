local ffi          = require "ffi"
local tiny         = require "tiny"
local cpml         = require "cpml"
local json         = require "dkjson"
local lube         = require "lube"
local lume         = require "lume"
local errors       = require "errors"
local magic        = require "magic"
local utils        = require "utils"
local Entity       = require "entity"
local actions      = require "action_enum"
local packet_types = require "packet_types"
local cdata        = packet_types.cdata
local packets      = packet_types.packets

return function(world)
	local client_system  = tiny.system()
	client_system.filter = tiny.requireAll("replicate")
	client_system.world  = world
	client_system.cache  = {}

	function client_system:onAdd(entity)
		self.cache[entity.id] = entity
	end

	function client_system:onRemove(entity)
		self.cache[entity.id] = nil
	end

	function client_system:update(dt)
		if not self.connection or not self.connection.connected then return end

		self.connection:update(dt)
	end

	function client_system:connect(host, port)
		self.connection = lube.enetClient()
		self.connection.handshake = magic.login_handshake
		self.connection:setPing(true, 15, magic.ping)
		self.host = host or "excessive.moe"
		self.port = port or 2806

		if SETTINGS.host_override then
			self.host = SETTINGS.host_override
		end

		console.i("Connecting to login server at %s:%s", self.host, self.port)
		local connected, err = self.connection:connect(self.host, tonumber(self.port), true)

		if connected then
			self.transferred = false
			Signal.emit("connect", "login")
		else
			console.e("%s", err)
		end

		function self.connection.callbacks.recv(d) self:recv(d) end

		return connected, err
	end

	function client_system:disconnect(transfer)
		if not self.connection then return end

		self.connection:disconnect()
		self.transferred = transfer
		Signal.emit("disconnect", "login", transfer)
	end

	--==[[ SEND DATA ]]==--

	function client_system:send(data, packet_type)
		if not self.connection or not self.connection.connected then return end

		local encoded

		if packet_type then
			data.type    = packets[packet_type]
			local struct = cdata:set_struct(packet_type, data)
			encoded      = cdata:encode(struct)
		else
			encoded = json.encode(data)
		end

		self.connection:send(encoded)
	end

	--==[[ JSON SEND PACKETS ]]==--

	--[[
		FROM: Player
		TO:   server_login:recv_login

		This is where networking begins. Player attempts to log in to Login Server by
		sending their username and password.

		TODO: Send only username, receive salt, hash password, send username and
		password. This is safe because Login Server will have a private pepper which
		renders a database dump useless.
	--]]
	function client_system:send_login(data)
		data.type = "login"
		self:send(data)
	end

	--[[
		FROM: Player
		TO:   server_login:recv_realm_login

		Send chosen Character and Realm IDs to Login Server.
	--]]
	function client_system:send_realm_login(data)
		data.type = "realm_login"
		self:send(data)
	end

	--==[[ RECEIVE DATA ]]==--

	function client_system:recv(data)
		local header = cdata:decode("packet_type", data)
		local map    = packets[header.type]

		-- If CDATA detected
		if map then
			if self["recv_"..map.name] then
				local decoded = cdata:decode(map.name, data)
				self["recv_"..map.name](self, decoded)
			else
				console.e("Invalid packet type (%s) from server", header.type)
				console.d("Packet data: %s", data)
				return
			end
		-- Otherwise, assume JSON
		else
			local decoded = json.decode(data)

			if type(decoded) ~= "table" then
				console.e("Invalid packet from server")
				console.d("Packet data: %s", data)
				console.d("Decode data: %s", decoded)
				return
			end

			local type = decoded.type
			decoded.type = nil

			if type and self["recv_"..type] then
				self["recv_"..type](self, decoded)
			else
				console.e("Invalid packet type (%s) from server", type)
				console.d("Packet data: %s", data)
				return
			end
		end
	end

	--==[[ JSON RECEIVE PACKETS ]]==--

	--[[
		FROM: server_login:send_account
		TO:   Game Client
		TO:   self:send_realm_login

		Receive account and character data.
	--]]
	function client_system:recv_account(data)
		console.d("User '%s' verified.", data.account.username)

		-- convert this shit to numerical keys. argh.
		local keys = lume.keys(data.characters)
		for _, v in ipairs(keys) do
			local tmp = data.characters[v]
			tmp.id = tonumber(tmp.id)
			data.characters[v] = nil
			data.characters[tonumber(v)] = tmp
		end

		Signal.emit("recv-account", "login", data)
	end

	--[[
		FROM: server_login:send_realm_list
		TO:   Game Client
		TO:   self:send_realm_login

		Receive list of realms.
	--]]
	function client_system:recv_realm_list(data)
		self.realms = data
		self.realms.type = nil

		-- convert this shit to numerical keys. argh.
		local keys = lume.keys(self.realms)
		for _, v in ipairs(keys) do
			local tmp = self.realms[v]
			self.realms[v] = nil
			self.realms[tonumber(v)] = tmp
		end

		Signal.emit("recv-realm-list", "login", self.realms)
	end

	--[[
		FROM: server_login:send_client_handoff
		TO:   Game Client
		TO:   server_realm:recv_identify

		Receive Session Token.
	--]]
	function client_system:recv_client_realm_handoff(data)
		Signal.emit("recv-client-realm-handoff", "login", data.token)
	end

	--[[
		FROM: server_login:send_error
		TO:   Game Client

		Receive error code from Login Server.
	--]]
	function client_system:recv_error(data)
		console.e("Login server error: %s", errors[data.code])
		self:disconnect()

		Signal.emit("recv-error", "login", data.code)
	end

	return client_system
end
