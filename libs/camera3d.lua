local Class = require "hump.class"
local cpml = require "cpml"

local Camera = Class {}

-- Camera assumes Y-forward, Z-up
function Camera:init(position)
	self.fov  = 45
	self.near = 0.1    -- 1cm
	self.far  = 1000.0 -- 1km

	self.view       = cpml.mat4()
	self.projection = cpml.mat4()

	self.position    = position or cpml.vec3(0, 0, 0)
	self.direction   = cpml.vec3(0, 1, 0)
	self.orientation = cpml.quat(0, 0, 0, 1)
	self.pre_offset  = cpml.vec3(0, 0, 0)
	self.offset      = cpml.vec3(0, 0, 0)
	self.up          = cpml.vec3(0, 0, 1)

	-- up/down limit (radians)
	self.pitch_limit_up    = math.pi / 2.25
	self.pitch_limit_down  = math.pi / 2.25
	self.current_pitch     = 0
	self.mouse_sensitivity = 1 / 15 -- radians/px

	-- position vector to track
	self.tracking = false

	self:update()
end

function Camera:grab(grabbing)
	local w, h = love.graphics.getDimensions()
	love.mouse.setGrabbed(grabbing)
	love.mouse.setVisible(not grabbing)
end

function Camera:move(vector, speed)
	local side    = self.direction:cross(self.up)
	self.position = self.position + vector.x * side:normalize() * speed

	self.position = self.position + vector.y * self.direction:normalize() * speed
	self.position = self.position + vector.z * self.up:normalize() * speed
end

function Camera:move_to(vector)
	self.position.x = vector.x
	self.position.y = vector.y
	self.position.z = vector.z
end

-- TODO: API WARNING: rotateXY should probably be rotate_xy or rotate_XY
function Camera:rotate_xy(mx, my)
	local mouse_direction = {
		x = math.rad(mx * self.mouse_sensitivity),
		y = math.rad(my * self.mouse_sensitivity)
	}
	--print("mouse move in radians: " .. tostring(mouse_direction.x) .. tostring(mouse_direction.y))
	self.current_pitch = self.current_pitch + mouse_direction.y

	-- don't rotate up/down more than self.pitch_limit
	if self.current_pitch > self.pitch_limit_up then
		self.current_pitch = self.pitch_limit_up
		mouse_direction.y  = 0
	elseif self.current_pitch < -self.pitch_limit_down then
		self.current_pitch = -self.pitch_limit_down
		mouse_direction.y  = 0
	end

	-- get the axis to rotate around the x-axis.
	local axis = self.direction:cross(self.up)
	axis = axis:normalize()

	-- NB: For quaternions a, b, a*b means "first apply rotation a, then apply rotation b".
	-- NB: This is the reverse of how matrices are applied.

	-- First, we apply a left/right rotation.
	-- NB: "self.up" is somewhat misleading. "self.up" is really just the world up vector, it is
	-- NB: independent of the cameras pitch. Since left/right rotation is around the worlds up-vector
	-- NB: rather than around the cameras up-vector, it always has to be applied first.
	self.orientation = cpml.quat.rotate(mouse_direction.x, self.up) * self.orientation

	-- Next, we apply up/down rotation.
	-- up/down rotation is applied after any other rotation (so that other rotations are not affected by it),
	-- hence we post-multiply it.
	self.orientation = self.orientation * cpml.quat.rotate(mouse_direction.y, cpml.vec3(1, 0, 0))

	-- Apply rotation to camera direction
	self.direction = self.orientation * cpml.vec3(0, 1, 0)
end

-- Figure out the view matrix
function Camera:update()
	local w, h = love.graphics.getDimensions()

	if not self.forced_transforms and not self.tracking then
		self.view = cpml.mat4()
			:translate(self.pre_offset)
			--:translate(self.position)
			--:rotate(self.orientation)
			:look_at(self.position, self.position + self.direction, self.up)
			:translate(self.offset)
	elseif self.tracking then
		self.view = cpml.mat4()
			:translate(self.pre_offset)
			:look_at(self.position, self.tracking, self.up)
			:translate(self.offset)
	end

	self.projection = self.projection:identity()
	self.projection = self.projection:perspective(self.fov, w/h, self.near, self.far)
end

function Camera:track(position)
	self.tracking = position
end

function Camera:send(shader, view_name, proj_name)
	shader:send(view_name or "u_view", self.view:to_vec4s())
	shader:send(proj_name or "u_projection", self.projection:to_vec4s())
end

function Camera:to_view_matrix()
	return self.view
end

function Camera:to_projection_matrix()
	return self.projection
end

function Camera:set_range(near, far)
	self.near = near
	self.far  = far
end

function Camera:add_fov(fov)
	self.fov = self.fov + fov
end

function Camera:set_fov(fov)
	self.fov = fov
end

return Camera
