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
		if not entity.id then
			utils.print_r(entity)
			assert(entity.id)
		end
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
		self.connection.handshake = magic.realm_handshake
		self.connection:setPing(true, 30, magic.ping)
		self.host = host or "localhost"
		self.port = port or 2807

		if SETTINGS.host_override then
			self.host = SETTINGS.host_override
		end

		console.i("Connecting to realm server at %s:%s", self.host, self.port)
		local connected, err = self.connection:connect(self.host, tonumber(self.port), true)

		if connected then
			self.transferred = false
			Signal.emit("connect", "realm")
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
		Signal.emit("disconnect", "realm", transfer)
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
		FROM: Game Client
		TO:   server_realm:recv_idenfity

		Send Session Token and Character ID to Realm Server to verify your identity.
	--]]
	function client_system:send_identify(data)
		data.type = "identify"
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

	function client_system:recv_client_channel_handoff(data)
		Signal.emit("recv-client-channel-handoff", "realm", data)
	end

	function client_system:recv_chat(data)
		Signal.emit("recv-chat", "realm", data)
	end

	function client_system:recv_error(data)
		console.e("Server error: %s", errors[data.code])
		self:disconnect()

		Signal.emit("recv-error", "realm", data.code)
	end

	return client_system
end
