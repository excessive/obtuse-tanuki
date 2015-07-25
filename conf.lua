local headless = love.filesystem.isFile("headless")

function love.conf(t)
	t.identity              = nil
	t.version               = "0.10.0"
	t.console               = false

	t.window = false
	t.modules.audio         = not headless
	t.modules.sound         = true

	t.modules.graphics      = not headless
	t.modules.window        = not headless
	t.modules.image         = true

	t.modules.event         = true
	t.modules.timer         = true
	t.modules.system        = true

	t.modules.joystick      = not headless
	t.modules.keyboard      = not headless
	t.modules.mouse         = not headless

	t.modules.math          = true
	t.modules.physics       = false

	io.stdout:setvbuf("no")
end
