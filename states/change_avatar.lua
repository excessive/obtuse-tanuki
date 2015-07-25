local avatar = require "avatar"
local tiny   = require "tiny"
local gui    = require "quickie"
local picker = require "picker"

-- copy from a real FS path to VFS
local function copy_from_fs(from, to)
	local f = assert(io.open(from, "rb"))
	love.filesystem.write(to, f:read("*a"))
	f:close()
end

return function()
	local gs  = tiny.system()
	gs.name   = "change_avatar"

	function gs:enter(from, world, original_av)
		self.world       = assert(world)
		self.av          = false
		self.encoded_av  = false
		self.original_av = assert(original_av)
	end

	function gs:update(dt)
		local w, h = love.graphics.getDimensions()
		gui.group { grow = "down", pos = { 20, 20 }, function()
			if gui.Button { text = "Open" } then
				local path = picker.open("Select Avatar", { "Image Files (*.png)", "*.png" })
				if path then
					local name = "avatar.png"
					-- temporarily copy avatar to save dir
					copy_from_fs(path, name)
					local im = love.graphics.newImage(name, {
						mipmaps = true,
						srgb    = true
					})
					love.filesystem.remove(name)
					self.encoded_av, self.av = avatar.encode(im, 64, 64)
				end
			end

			if gui.Button { text = "Done" } then
				if self.encoded_av and self.encoded_av ~= self.original_av then
					Signal.emit("send-avatar", {
						avatar  = self.encoded_av,
						encoded = self.av
					})
				end
				Gamestate.pop()
			end
		end }

		if self.av then
			love.graphics.draw(self.av, w/2-self.av:getWidth()/2, 20)
		end

		gui.core.draw()
	end

	return gs
end
