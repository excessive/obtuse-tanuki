local winapi, zenity
if love.system.getOS() == "Windows" then
	winapi = require "winapi"
	require "winapi.filedialogs"
elseif love.system.getOS() == "Linux" then
	zenity = io.popen("which zenity", "r"):read()
end

local picker = {}

function picker.open(title, filter)
	local ok, info = false, {}
	if winapi then
		ok, info = winapi.GetOpenFileName {
			title = title,
			filter = filter,
			filter_index = 1,
			flags = "OFN_EXPLORER|OFN_FILEMUSTEXIST"
		}
	elseif zenity then
		info.filepath = io.popen(string.format(
			"zenity --file-selection --title='%s' --file-filter='%s'",
			title,
			("%s|%s"):format(filter[1], filter[2])
		)):read()
		if info.filepath then
			ok = true
		end
	end
	if ok then
		return info.filepath
	end
	return false
end

return picker
