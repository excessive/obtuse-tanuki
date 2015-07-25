local tiny  = require "tiny"
local cpml  = require "cpml"
local utils = require "utils"

return function(camera)
	local render_system  = tiny.system()
	render_system.filter = tiny.requireAll("model_matrix", "mesh", tiny.rejectAny("needs_reload"))
	render_system.camera = camera
	Signal.register('client-network-id', function(id) render_system.id = id end)

	local bounds = love.graphics.newShader("assets/shaders/shader.glsl")
	local shader = love.graphics.newShader("assets/shaders/shader.glsl")

	function render_system:update(dt)
		local cc = love.math.gammaToLinear
		-- local color = cpml.vec3(cc(unpack(cpml.color.darken({255,255,255,255}, 0.75))))
		-- love.graphics.setBackgroundColor(color.x, color.y, color.z, color:dot(cpml.vec3(0.299, 0.587, 0.114)))

		love.graphics.clearDepth()
		love.graphics.setDepthTest("less")
		love.graphics.setCulling("back")
		love.graphics.setFrontFace("cw")
		love.graphics.setBlendMode("replace")

		love.graphics.setShader(shader)
		-- shader:send("u_Ka", { 0.1, 0.1, 0.1 })
		-- shader:send("u_Kd", { 1, 1, 1 })
		-- shader:send("u_Ks", { 0, 0, 0 })
		-- shader:send("u_Ns", 0)
		-- shader:sendInt("u_shading", 1)
		shader:sendInt("use_color", 1)
		self.camera:send(shader)

		local entities = self.entities
		for _, entity in ipairs(entities) do
			while true do
				if entity.possessed then
					break
				end
				local model = entity.model_matrix:to_vec4s()
				shader:send("u_model", model)

				for _, buffer in ipairs(entity.mesh) do
					-- local texture = entity.mesh.textures[buffer.material]
					-- entity.mesh.mesh:setTexture(texture) -- nil is OK
					entity.mesh.mesh:setDrawRange(buffer.first, buffer.last)
					love.graphics.draw(entity.mesh.mesh)
				end

				-- for _, buffer in ipairs(entity.mesh.vertex_buffer) do
				-- 	-- utils.print_r(buffer)
				-- 	love.graphics.draw(buffer.mesh)
				-- end

				-- entity:draw()
				-- love.graphics.setShader(bounds)
				-- love.graphics.setWireframe(true)
				--
				-- if entity.closest then
				-- 	love.graphics.setColor(0, 255, 0, 255)
				-- 	entity.closest = nil
				-- elseif entity.highlight then
				-- 	love.graphics.setColor(255, 0, 0, 255)
				-- 	entity.highlight = nil
				-- else
				-- 	love.graphics.setColor(cc(80, 80, 80, 255))
				-- end
				--
				-- if entity.locked then
				-- 	if entity.locked == self.id then
				-- 		love.graphics.setColor(0, 0, 255, 255)
				-- 	elseif entity.locked ~= self.id then
				-- 		love.graphics.setColor(255, 0, 255, 255)
				-- 	end
				-- end
				--
				-- if entity.bounds then
				-- 	self.camera:send(bounds)
				-- 	bounds:sendInt("u_shading", 1)
				-- 	bounds:send("u_Ka", { 1, 0, 0 })
				-- 	bounds:send("u_model", cpml.mat4():to_vec4s())
				-- 	love.graphics.draw(entity.bounds)
				-- end
				-- love.graphics.setColor(255, 255, 255, 255)
				-- love.graphics.setWireframe(false)
				break
			end
		end
		love.graphics.setShader()
		love.graphics.setDepthTest()
		love.graphics.setCulling()
		love.graphics.setFrontFace()
		love.graphics.setBlendMode("alpha")

		love.graphics.print(string.format("POS: %s", self.camera.position),    20, 100)
		love.graphics.print(string.format("DIR: %s", self.camera.direction),   20, 124)
		love.graphics.print(string.format("ROT: %s", self.camera.orientation), 20, 148)
		local spacing = 24
		local stats = love.graphics.getStats()
		local i = 0
		for k, v in pairs(stats) do
			love.graphics.print(string.format("%s: %d", k, v), 20, 180 + i * spacing)
			i = i + 1
		end
	end

	return render_system
end
