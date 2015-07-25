local function invoke(entities, world)

end

local function finalize(entities, world)
	for k, entity in pairs(entities) do
		world:removeEntity(entity)
		Signal.emit("client-send", { id = entity.id }, "despawn_entity")
	end
end

return {
	invoke   = invoke,
	finalize = finalize,
}
