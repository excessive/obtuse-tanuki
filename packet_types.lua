local cdata   = require "cdata"
local packets = {}

-- all structs get a type field so we don't lose our minds.
function add_struct(name, fields, map)
	local struct = string.format("typedef struct { uint8_t type; %s } %s;", fields, name)
	cdata:new_struct(name, struct)

	-- the packet_type struct isn't a real packet, so don't index it.
	if map then
		map.name = name
		table.insert(packets, map)
		packets[name] = #packets
	end
end

-- Slightly special, I guess.
add_struct("packet_type", "")

add_struct(
	"client_action", [[
		uint64_t id;
		uint16_t action;
		uint64_t target;
	]], {
		"id",
		"action",
		"target",
	}
)

add_struct(
	"update_entity", [[
		uint64_t id;
		float position_x,    position_y,    position_z;
		float orientation_x, orientation_y, orientation_z, orientation_w;
		float velocity_x,    velocity_y,    velocity_z;
		float scale_x,       scale_y,       scale_z;
	]], {
		"id",
		"position_x",    "position_y",    "position_z",
		"orientation_x", "orientation_y", "orientation_z", "orientation_w",
		"velocity_x",    "velocity_y",    "velocity_z",
		"scale_x",       "scale_y",       "scale_z",
	}
)

return { cdata=cdata, packets=packets }
