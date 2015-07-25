local cpml = require "cpml"

local function move_entity(key, orientation, scale)
	if key == "kp4" then orientation.x = orientation.x - 1 end
	if key == "kp6" then orientation.x = orientation.x + 1 end
	if key == "kp8" then orientation.y = orientation.y - 1 end
	if key == "kp2" then orientation.y = orientation.y + 1 end
	if key == "kp1" then orientation.z = orientation.z - 1 end
	if key == "kp7" then orientation.z = orientation.z + 1 end
end

local function invoke(entities, world)

end

local function update(entities, world, dt)

end

local function keypressed(entities, world, key, isrepeat)
	for k, entity in pairs(entities) do
		if not entity.start_orientation then
			entity.start_orientation = entity.orientation:clone()
		end

		move_entity(key, entity.orientation)

		if key == "return" then
			entity.start_orientation = nil
			entity.orientation = entity.orientation:normalize()
		end

		if key == "escape" and entity.start_orientation then
			entity.orientation = entity.start_orientation
			entity.start_orientation = nil
		end

		-- Send over the network!
		entity.needs_update = true
	end
end

local function mousepressed(entities, world, x, y, button)

end

local function finalize(entities, world)
	for k, entity in pairs(entities) do
		if entity.start_orientation then
			entity.orientation = entity.start_orientation
			entity.start_orientation = nil
		end
	end
end

return {
	invoke       = invoke,
	update       = update,
	keypressed   = keypressed,
	mousepressed = mousepressed,
	finalize     = finalize,
}
