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
local sql          = require "queries"
local actions      = require "action_enum"
local packet_types = require "packet_types"
local cdata        = packet_types.cdata
local packets      = packet_types.packets

return function(world)
	local client_system  = tiny.system()
	client_system.filter = tiny.requireAll("replicate")
	client_system.world  = world

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

	function client_system:connect(server, id, name, host, port, db)
		self.connection = lube.enetClient()
		self.connection.handshake = magic.realm_handshake
		self.connection:setPing(true, 30, magic.ping)

		self.server = server
		self.id     = id
		self.name   = name or "It is a mystery"
		self.host   = host or "localhost"
		self.port   = port or 2807

		if SETTINGS.host_override then
			self.host = SETTINGS.host_override
		end

		console.i("[Login->Realm] Connecting to %s:%s", self.host, self.port)
		local connected, err = self.connection:connect(self.host, tonumber(self.port), true)

		if connected then
			self.connected = connected
			self.db        = db
			console.i("[Login->Realm] Connected.")
			Signal.emit("connect", "Login->Realm")
		else
			console.e("%s", err)
			return self:connect(server, id, name, host, port, db)
		end

		function self.connection.callbacks.recv(d) self:recv(d) end

		return connected, err
	end

	function client_system:disconnect()
		if not self.connection then return end

		self.connection:disconnect()
		console.i("[Login->Realm] Disconnected.")
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

	function client_system:recv_server_realm_handoff(data)
		self.server:recv_server_realm_handoff(data)
	end

	function client_system:recv_logout_time(data)
		assert(data.user_id,      "user_id is nil!")
		assert(data.character_id, "character_id is nil!")
		assert(data.time,         "time is nil!")

		local stmt = sql.prepared.login_realm.update_character_last_login
		stmt:reset(true)
		stmt:bind {
			{ data.time,    "int" },
			{ data.character_id, "int" },
			{ data.user_id, "int" },
		}

		local success, err = stmt:run()
		if not success then
			console.e("Database error: %s", err)
			return
		end

		-- Update user's last login
		local stmt = sql.prepared.login_realm.update_user_last_login
		stmt:reset(true)
		stmt:bind {
			{ data.time,    "int" },
			{ data.user_id, "int" },
		}

		local success, err = stmt:run()
		if not success then
			console.e("Database error: %s", err)
		end
	end

	function client_system:update_character_alias(data)
		assert(data.user_id,      "user_id is nil!")
		assert(data.character_id, "character_id is nil!")
		assert(data.avatar_id,    "avatar_id is nil!")
		assert(data.alias,        "alias is nil!")

		-- Insert new Alias into DB
		local stmt = sql.prepared.login_realm.insert_alias
		stmt:reset(true)
		stmt:bind {
			{ data.user_id,   "int"  },
			{ data.avatar_id, "int"  },
			{ data.alias,     "text" },
			{ os.time(),      "int"  }
		}
		local success, err = stmt:run()
		if not success then
			console.e("Database error: %s", err)
			return
		end

		local new_alias_id = tonumber(self.db:getLastRowID())

		-- Update Character with new Alias
		local stmt = sql.prepared.login_realm.update_character_alias
		stmt:reset(true)
		stmt:bind {
			{ new_alias_id,      "int64" },
			{ data.character_id, "int"   },
			{ data.user_id,      "int"   }
		}

		local success, err = stmt:run()
		if not success then
			console.e("Database error: %s", err)
			return
		end

		-- No need to do a select, we already know the new ID!
		local d = {
			type         = "updated_alias",
			alias_id     = new_alias_id,
			old_alias_id = data.alias_id,
			alias        = data.alias
		}
		self:send(d)
	end

	-- Input:
	-- character_id, image (base64), alias_id
	-- Output:
	function client_system:update_character_avatar(data)
		assert(data.character_id, "character_id is nil!")
		assert(data.alias_id,     "alias_id is nil!")
		assert(data.avatar,       "avatar is nil!")

		local stmt = sql.prepared.login_realm.insert_avatar
		stmt:reset(true)
		stmt:bind {
			{ os.time(),         "int"  },
			{ data.character_id, "int"  },
			{ data.avatar,       "text" } -- base64 PNG data, not binary
		}
		local success, err = stmt:run()
		if not success then
			console.e("Database error: %s")
			return
		end

		local new_avatar_id = tonumber(self.db:getLastRowID())

		local stmt = sql.prepared.login_realm.update_character_avatar
		stmt:reset(true)
		stmt:bind {
			{ new_avatar_id, "int64" },
			{ data.alias_id, "int"   }
		}
		local success, err = stmt:run()
		if not success then
			console.e("Database error: %s")
			return
		end

		local d = {
			type      = "updated_avatar",
			avatar_id = new_avatar_id,
			alias_id  = data.alias_id
		}
		self:send(d)
	end

	function client_system:recv_character_update(data)
		--utils.print_r(data)
		-- Do magic if we need to update the alias
		if data.alias then
			self:update_character_alias(data)
		end

		-- Insert new avatar into the database
		if data.avatar then
			self:update_character_avatar(data)
		end

		-- Update other stuff too!
	end

	return client_system
end
