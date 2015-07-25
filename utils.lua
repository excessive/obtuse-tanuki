local function print_r(t, level)
	level = level or 0
	local indent = string.rep(" ", level * 2)
	for k, v in pairs(t) do
		print(string.format("%s%s (%s) = %s (%s)", indent, k, type(k), v, type(v)))
		if type(v) == "table" then
			print_r(v, level + 1)
		end
	end
end

return {
	print_r = print_r
}
