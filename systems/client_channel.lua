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
	client_system.dt     = 0
	client_system.cache  = {}

	function client_system:onAdd(entity)
		self.cache[entity.id] = entity

		if entity.possessed then
			self.possessed = entity
		end
	end

	function client_system:onRemove(entity)
		self.cache[entity.id] = nil

		if entity.possessed then
			self.possessed = nil
		end
	end

	function client_system:update(dt)
		if not self.connection or not self.connection.connected then
			self.dt = 0
			return
		end

		self.connection:update(dt)

		self.dt = self.dt + dt

		if self.dt >= 1/20 then
			self.dt = self.dt - 1/20

			if self.possessed then
				local entity = self.possessed
				local data   = {
					type           = packets.update_entity,
					id             = entity.id,
					position_x     = entity.position.x,
					position_y     = entity.position.y,
					position_z     = entity.position.z,
					orientation_x  = entity.orientation.x,
					orientation_y  = entity.orientation.y,
					orientation_z  = entity.orientation.z,
					orientation_w  = entity.orientation.w,
					velocity_x     = entity.velocity.x,
					velocity_y     = entity.velocity.y,
					velocity_z     = entity.velocity.z,
					rot_velocity_x = entity.rot_velocity.x,
					rot_velocity_y = entity.rot_velocity.y,
					rot_velocity_z = entity.rot_velocity.z,
					rot_velocity_w = entity.rot_velocity.w,
					scale_x        = entity.scale.x,
					scale_y        = entity.scale.y,
					scale_z        = entity.scale.z
				}

				self:send(data, "update_entity")
			end
		end
	end

	function client_system:connect(host, port)
		self.world:clearEntities()

		self.connection = lube.enetClient()
		self.connection.handshake = magic.channel_handshake
		self.connection:setPing(true, 2, magic.ping)
		self.host = host or "excessive.moe"
		self.port = port or 2808

		if SETTINGS.host_override then
			self.host = SETTINGS.host_override
		end

		console.i("Connecting to channel server at %s:%s", self.host, self.port)
		local connected, err = self.connection:connect(self.host, tonumber(self.port), true)

		if connected then
			Signal.emit("connect", "channel")
		else
			console.i("%s", err)
		end

		function self.connection.callbacks.recv(d) self:recv(d) end

		return connected, err
	end

	function client_system:disconnect()
		if not self.connection then return end

		self.connection:disconnect()
		Signal.emit("disconnect", "channel")
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

	function client_system:send_identify(data)
		data.type = "identify"
		self:send(data)
	end

	--==[[ JSON SEND PACKETS ]]==--

	function client_system:send_account_update(data)
		data.type = "account_update"
		self:send(data)
	end

	function client_system:send_character_update(data)
		data.type = "character_update"
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
		FROM: server_channel:send_new_character
		TO:   Game Client

		Receive character data from server.
	--]]
	function client_system:recv_new_character(data)
		Signal.emit("recv-new-character", "channel", data)
	end

	function client_system:recv_remove_character(data)
		Signal.emit("recv-remove-character", "channel", data)
	end

	function client_system:recv_account_update(data)
		Signal.emit("recv-account-update", "channel", data)
	end

	function client_system:recv_character_update(data)
		Signal.emit("recv-character-update", "channel", data)
	end

	function client_system:recv_error(data)
		console.e("Channel server error: %s", errors[data.code])
		self:disconnect()

		Signal.emit("recv-error", "channel", data.code)
	end

	--==[[ CDATA RECEIVE PACKETS ]]==--

	function client_system:recv_client_action(data)
		if actions[data.action] then
			self["recv_action_"..actions[data.action]](self, data)
		else
			console.e("Invalid action: %d", data.action)
		end
	end

	function client_system:recv_update_entity(data)
		local entity = self.cache[tonumber(data.id)]

		-- If already updated locally, ignore
		if not entity or entity == self.possessed then return end

		-- Process data
		local position     = cpml.vec3(data.position_x,     data.position_y,     data.position_z)
		local orientation  = cpml.quat(data.orientation_x,  data.orientation_y,  data.orientation_z,  data.orientation_w)
		local velocity     = cpml.vec3(data.velocity_x,     data.velocity_y,     data.velocity_z)
		local scale        = cpml.vec3(data.scale_x,        data.scale_y,        data.scale_z)

		-- Determine latency
		local peer   = self.connection.peer
		local ping   = peer:round_trip_time() / 1000 / 2

		-- Compensate for latency
		position    = position + velocity * ping
		--orientation = orientation * ping
		--orientation = orientation:normalize()

		-- Assign data
		local rot_velocity      = orientation * entity.orientation:inverse()
		entity.real_position    = position
		entity.real_orientation = orientation
		entity.velocity         = velocity
		entity.rot_velocity     = rot_velocity
		entity.scale            = scale
	end

	return client_system
end
