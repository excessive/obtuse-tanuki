local noto = {}

local ps = love.window.getPixelScale()
local OS = love.system.getOS()

local n = OS == "Android" and OS == "iOS" and 0 or 1

local lineheight = {
	display2	= 48/45,
	display1	= 40/34,
	headline	= 32/24,
	subhead		= 28/(16 - n),
	body2		= 24/(14 - n),
	body1		= 20/(14 - n),
}

local load = function (a)
	local a = a.."/NotoSans"
	local bold, regular = a.."-Bold.ttf", a.."-Regular.ttf"

	fonts = {
		regular = a .. "-Regular.ttf",
		bold    = a .. "-Bold.ttf"
	}

	fallbacks = {
		regular = { a .. "Symbols-Regular.ttf", a .. "CJKjp-Regular.otf", a .. "Hebrew-Regular.ttf" },
		bold    = { a .. "Symbols-Regular.ttf", a .. "CJKjp-Regular.otf", a .. "Hebrew-Bold.ttf" }
	}

	function lf(class, size)
		local f = love.graphics.newFont(fonts[class], size)
		local fb = {}
		for i, v in ipairs(fallbacks[class]) do
			fb[i] = love.graphics.newFont(v, size)
		end
		f:setFallbacks(unpack(fb))
		return f
	end

	noto = {
		-- display4	= lf("regular", 	112 * ps),
		-- display3	= lf("regular", 	56  * ps),
		-- display2	= lf("regular", 	45  * ps),
		-- display1	= lf("regular", 	34  * ps),
		-- headline	= lf("regular", 	24  * ps),
		title		= lf("bold", 		20  * ps),
		subhead	= lf("regular",	(16 - n) * ps),
		body2		= lf("bold", 		(14 - n) * ps),
		body1		= lf("regular", 	(14 - n) * ps),
		caption	= lf("regular", 	12  * ps),
		button	= lf("bold", 		15  * ps)
	}

	for k,v in pairs(lineheight) do
		if noto[k] then
			noto[k]:setLineHeight(lineheight[k])
		end
	end

	local get = function (noto, font)
		return noto[font]
	end

	setmetatable(noto, {__call = get})

	return noto
end

return load
