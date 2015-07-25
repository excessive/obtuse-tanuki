local cpml = require "cpml"

local function move_relative_camera(position, vector, speed)
	local camera  = Gamestate.current().camera
	local side    = camera.direction:cross(camera.up)

	position = position + vector.x * side:normalize() * speed
	position = position + vector.y * camera.direction:normalize() * speed
	position = position + vector.z * camera.up:normalize() * speed

	return position
end

local function move_entity(key, position, increment)
	local vector = cpml.vec3()

	if key == "kp4" then vector.x = vector.x - 1 end
	if key == "kp6" then vector.x = vector.x + 1 end
	if key == "kp2" then vector.y = vector.y - 1 end
	if key == "kp8" then vector.y = vector.y + 1 end
	if key == "kp1" then vector.z = vector.z - 1 end
	if key == "kp7" then vector.z = vector.z + 1 end

	return move_relative_camera(position, vector, increment)
end

local function invoke(entities, world)

end

local function update(entities, world, dt)

end

local function keypressed(entities, world, key, isrepeat)
	for k, entity in pairs(entities) do
		if not entity.start_position then
			entity.start_position = entity.position:clone()
		end

		entity.position = move_entity(key, entity.position, 1)

		if key == "return" then
			entity.start_position = nil
		end

		if key == "escape" and entity.start_position then
			entity.position = entity.start_position
			entity.start_position = nil
		end

		-- Send over the network!
		entity.needs_update = true
	end
end

local function mousepressed(entities, world, x, y, button)

end

local function finalize(entities, world)
	for k, entity in pairs(entities) do
		if entity.start_position then
			entity.position = entity.start_position
			entity.start_position = nil
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
