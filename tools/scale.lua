local function move_entity(key, scale, increment)
	if key == "kp4" then scale.x = scale.x - 1 * increment end
	if key == "kp6" then scale.x = scale.x + 1 * increment end
	if key == "kp8" then scale.y = scale.y - 1 * increment end
	if key == "kp2" then scale.y = scale.y + 1 * increment end
	if key == "kp1" then scale.z = scale.z - 1 * increment end
	if key == "kp7" then scale.z = scale.z + 1 * increment end
end

local function invoke(entities, world)

end

local function update(entities, world, dt)

end

local function keypressed(entities, world, key, isrepeat)
	for k, entity in pairs(entities) do
		if not entity.start_scale then
			entity.start_scale = entity.scale:clone()
		end

		move_entity(key, entity.scale, 1)

		if key == "return" then
			entity.start_scale = nil
		end

		if key == "escape" and entity.start_scale then
			entity.scale = entity.start_scale
			entity.start_scale = nil
		end

		-- Send over the network!
		entity.needs_update = true
	end
end

local function mousepressed(entities, world, x, y, button)

end

local function finalize(entities, world)
	for k, entity in pairs(entities) do
		if entity.start_scale then
			entity.scale = entity.start_scale
			entity.start_scale = nil
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
