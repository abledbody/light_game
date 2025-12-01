---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function srgb_to_linear(rgb)
	return vec(
		rgb.x < 0.04045 and rgb.x / 12.92 or ((rgb.x + 0.055) / 1.055) ^ 2.4,
		rgb.y < 0.04045 and rgb.y / 12.92 or ((rgb.y + 0.055) / 1.055) ^ 2.4,
		rgb.z < 0.04045 and rgb.z / 12.92 or ((rgb.z + 0.055) / 1.055) ^ 2.4
	)
end

local lms_mat = userdata("f64", 3, 3)
lms_mat:set(0, 0,
	0.4122214708, 0.2119034982, 0.0883024619,
	0.5363325363, 0.6806995451, 0.2817188376,
	0.0514459929, 0.1073969566, 0.6299787005
)

local oklab_mat = userdata("f64", 3, 3)
oklab_mat:set(0, 0,
	0.2104542553, 1.9779984951, 0.0259040371,
	0.7936177850, -2.4285922050, 0.7827717662,
	-0.0040720468, 0.4505937099, -0.8086757660
)

---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function linear_to_oklab(rgb)
	local lms = rgb:matmul(lms_mat) ---@cast lms userdata
	lms.x = lms.x ^ (1 / 3)
	lms.y = lms.y ^ (1 / 3)
	lms.z = lms.z ^ (1 / 3)
	
	---@diagnostic disable-next-line return-type-mismatch
	return lms:matmul(oklab_mat)
end

---@param palette userdata f64, 3x64
---@param rgb userdata f64, 3x1
---@return integer index
local function get_closest(palette, rgb)
	local best_dist, best_index = math.huge, 0
	for test_i = 0, 63 do
		local dist = (palette:row(test_i) - rgb):magnitude()
		
		if dist < best_dist then
			best_dist, best_index = dist, test_i
		end
	end
	return best_index
end

---@param u32_values userdata i32, 64x1
---@return userdata
local function rgba32_to_rgbf64(u32_values)
	local f64_values = userdata("f64", 3, 64)
	
	for i = 0, 63 do
		local col = u32_values[i]
		local srgb = vec(
			((col >> 16) & 0xFF),
			((col >> 8) & 0xFF),
			(col & 0xFF)
		) / 255
		
		f64_values:copy(srgb, true, 0, i * 3)
	end
	
	return f64_values
end

---@param input userdata f32, 3x64
---@param converter fun(rgb: userdata): userdata
---@return userdata output f32, 3x64
local function convert_colors(input, converter)
	local output = userdata("f64", 3, 64)
	
	for i = 0, 63 do
		---@diagnostic disable-next-line: param-type-mismatch
		output:copy(converter(input:row(i)), true, 0, i * 3)
	end
	
	return output
end

---@param func fun(draw_col: userdata, target_col: userdata, draw_i: integer, target_i: integer): userdata|integer
---@param space "srgb"|"linear"|"oklab"
---@param palette userdata i32, 64x1
---@return userdata color_table u8, 64x64
local function generate_coltab(func, space, palette)
	local srgb_values = rgba32_to_rgbf64(palette)
	local rgb_values = convert_colors(srgb_values, srgb_to_linear)
	local lab_values = convert_colors(rgb_values, linear_to_oklab)
	
	local color_table = userdata("u8", 64, 64)
	local col_values =
		space == "linear" and rgb_values
		or space == "oklab" and lab_values
		or srgb_values
		
	local to_oklab =
		space == "linear" and linear_to_oklab
		or space == "oklab" and function(rgb) return rgb end
		or function(rgb) return linear_to_oklab(srgb_to_linear(rgb)) end
		
	for draw_i = 0, 63 do
		for target_i = 0, 63 do
			local new_rgb = func(
				---@diagnostic disable-next-line param-type-mismatch
				col_values:row(draw_i), col_values:row(target_i),
				draw_i, target_i
			)
			
			if type(new_rgb) == "number" then
				color_table:set(target_i, draw_i, new_rgb)
				goto continue
			end
			---@cast new_rgb userdata
			
			local closest = get_closest(lab_values, to_oklab(new_rgb))
			color_table:set(target_i, draw_i, closest)
			::continue::
		end
	end
	
	return color_table
end

return {
	rgba32_to_rgbf64 = rgba32_to_rgbf64,
	srgb_to_linear = srgb_to_linear,
	linear_to_oklab = linear_to_oklab,
	get_closest = get_closest,
	convert_colors = convert_colors,
	generate_coltab = generate_coltab,
}
