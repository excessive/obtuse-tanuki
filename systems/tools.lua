local tiny = require "tiny"
local cpml = require "cpml"

return function(world)
	local tool_system  = tiny.system()
	tool_system.filter = tiny.requireAll("replicate")
	tool_system.world  = world

	tool_system.tools = {}
	tool_system.active_tool = false
	tool_system.controls = {
		-- Keyboard
		["g"]      = "translate",
		["r"]      = "rotate",
		["s"]      = "scale",
		["delete"] = "delete",

		-- Mouse
		["m1"]     = "",
		["m2"]     = "",
		["m3"]     = "",
	}

	function tool_system:update(dt)
		local locked = Gamestate.current().locked

		if self.active_tool then
			if self.tools[self.active_tool].update then
				self.tools[self.active_tool].update(locked, world, dt)
			else
				self.tools[self.active_tool].finalize(locked, world)
				self.active_tool = false
			end
		end
	end

	function tool_system:keypressed(key, isrepeat)
		local locked = Gamestate.current().locked

		if self.controls[key] then
			-- Finalize active_tool tool
			if self.active_tool then
				self.tools[self.active_tool].finalize(locked, world)
			end

			-- Set new tool to active_tool
			self.active_tool = self.controls[key]

			-- Invoke new tool
			self.tools[self.active_tool].invoke(locked, world)
		elseif self.active_tool then
			-- Pass key to active tool
			if self.tools[self.active_tool].keypressed then
				self.tools[self.active_tool].keypressed(locked, self.world, key, isrepeat)
			end
		end
	end

	function tool_system:mousepressed(x, y, button)
		local button = string.format("m%s", button)

		if self.controls[button] then
			--self.active = self.controls[button]
		end
	end

	function tool_system:define_tool(tool)
		self.tools[tool] = require(string.format("tools.%s", tool))
	end

	local tools = {
		"add", "delete",
		"translate", "rotate", "scale",
	}

	for _, tool in ipairs(tools) do
		tool_system:define_tool(tool)
	end

	return tool_system
end
