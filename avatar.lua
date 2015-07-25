local basexx   = require "basexx"

local avatar = {}

function avatar.decode(avatar)
	assert(avatar)
	local data = avatar:sub(avatar:find(","),-1)
	local fd   = love.filesystem.newFileData(data, "avatar.png", "base64")
	local im   = love.graphics.newImage(love.image.newImageData(fd), {mipmaps=true, srgb=true})
	im:setFilter("linear", "linear", 16)
	im:setMipmapFilter("linear", 1)
	return im
end

function avatar.encode(image, width, height)
	if not image then
		console.e("Avatar source image not found or invalid!")
		return
	end
	image:setFilter("linear", "linear", 16)
	image:setMipmapFilter("linear", 1)
	local c = love.graphics.newCanvas(width, height, "srgb")
	c:renderTo(function()
		local iw, ih = image:getDimensions()
		local s = math.max(width/iw, height/ih)
		love.graphics.draw(image, 0, 0, 0, s, s)
	end)
	local data = c:newImageData()
	local name = "avatar-resized.png"
	data:encode(name)
	local png = love.filesystem.read("avatar-resized.png")
	if png:len() < 16 then
		console.e("Invalid PNG!")
		return
	end
	local encoded = "data:image/png;base64," .. basexx.to_base64(png)
	local resized = love.graphics.newImage(data, {mipmaps=true, srgb=true})
	love.filesystem.remove(name)
	resized:setFilter("linear", "linear", 16)
	resized:setMipmapFilter("linear", 1)
	return encoded, resized
end

return avatar
