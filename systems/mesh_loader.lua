local tiny = require "tiny"
local iqm  = require "iqm"

return function(world)
	local ml = tiny.processingSystem()
	ml.filter = tiny.requireAll("needs_reload", "model")
	ml.world  = assert(world)
	ml.mesh_cache = {}

	-- if we process things here it crashes tiny...
	-- function ml:onAdd(entity) end

	-- happens late, but it's safe.
	function ml:update(dt)
		for _, entity in ipairs(self.entities) do
			local name = ""
			if entity.alias then
				name = " " .. entity.alias
			end
			local t = love.timer.getTime()
			if self.mesh_cache[entity.model] then
				entity.mesh = self.mesh_cache[entity.model]
			else
				local mesh_data = require("assets.models." .. entity.model)
				entity.mesh = iqm.load(mesh_data.model)
			end
			console.d("Loaded %s%s in %fs", entity.model, name, love.timer.getTime() - t)
			self.mesh_cache[entity.model] = entity.mesh

			-- now cycle the entity again, it's loaded.
			entity.needs_reload = nil
			self.world:removeEntity(entity)
			self.world:addEntity(entity)
		end
	end

	return ml
end
