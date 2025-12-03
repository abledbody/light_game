--------------------------------Color space conversion---------------------------------

---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function srgb_to_linear(rgb)
	return vec(
		rgb.x < 0.04045 and rgb.x / 12.92 or ((rgb.x + 0.055) / 1.055) ^ 2.4,
		rgb.y < 0.04045 and rgb.y / 12.92 or ((rgb.y + 0.055) / 1.055) ^ 2.4,
		rgb.z < 0.04045 and rgb.z / 12.92 or ((rgb.z + 0.055) / 1.055) ^ 2.4
	)
end

---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function linear_to_srgb(rgb)
	return vec(
		rgb.x >= 0.0031308 and 1.055 * (rgb.x ^ (1.0 / 2.4)) - 0.055 or 12.92 * rgb.x,
		rgb.y >= 0.0031308 and 1.055 * (rgb.y ^ (1.0 / 2.4)) - 0.055 or 12.92 * rgb.y,
		rgb.z >= 0.0031308 and 1.055 * (rgb.z ^ (1.0 / 2.4)) - 0.055 or 12.92 * rgb.z
	)
end

local rgb_lms_mat = userdata("f64", 3, 3)
rgb_lms_mat:set(0, 0,
	0.4122214708, 0.2119034982, 0.0883024619,
	0.5363325363, 0.6806995451, 0.2817188376,
	0.0514459929, 0.1073969566, 0.6299787005
)

local lms_oklab_mat = userdata("f64", 3, 3)
lms_oklab_mat:set(0, 0,
	0.2104542553, 1.9779984951, 0.0259040371,
	0.7936177850, -2.4285922050, 0.7827717662,
	-0.0040720468, 0.4505937099, -0.8086757660
)

---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function linear_to_oklab(rgb)
	local lms = rgb:matmul(rgb_lms_mat) ---@cast lms userdata
	lms.x = lms.x ^ (1 / 3)
	lms.y = lms.y ^ (1 / 3)
	lms.z = lms.z ^ (1 / 3)
	
	---@diagnostic disable-next-line return-type-mismatch
	return lms:matmul(lms_oklab_mat)
end

local oklab_lms_mat = userdata("f64", 3, 3)
oklab_lms_mat:set(0, 0,
	1.0000000000, 1.0000000000, 1.0000000000,
	0.3963377774, -0.1055613458, -0.0894841775,
	0.2158037573, -0.0638541728, -1.2914855480
)

local lms_rgb_mat = userdata("f64", 3, 3)
lms_rgb_mat:set(0, 0,
	4.0767416621, -1.2684380046, -0.0041960863,
	-3.3077115913, 2.6097574011, -0.7034186147,
	0.2309699292, -0.3413193965, 1.7076147010
)

---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function oklab_to_linear(rgb)
	local lms = rgb:matmul(oklab_lms_mat) ---@cast lms userdata
	lms.x = lms.x ^ 3
	lms.y = lms.y ^ 3
	lms.z = lms.z ^ 3
	
	---@diagnostic disable-next-line return-type-mismatch
	return lms:matmul(lms_rgb_mat)
end

---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function srgb_to_oklab(rgb) return linear_to_oklab(srgb_to_linear(rgb)) end
---@param rgb userdata f64, 3x1
---@return userdata rgb f64, 3x1
local function oklab_to_srgb(rgb) return linear_to_srgb(oklab_to_linear(rgb)) end

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

local space_convert = {
	srgb = {
		linear = srgb_to_linear,
		oklab = srgb_to_oklab,
	},
	linear = {
		srgb = linear_to_srgb,
		oklab = linear_to_oklab,
	},
	oklab = {
		srgb = oklab_to_srgb,
		linear = oklab_to_linear
	}
}

--------------------------------------Color data---------------------------------------

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

--------------------------------Color table generation---------------------------------

---@alias ColorBlender fun(draw_col: userdata, target_col: userdata, draw_i: integer, target_i: integer): userdata|integer
---@alias IndexBlender fun(draw_i: integer, target_i: integer): integer

---@param func ColorBlender
---@param palette userdata i32, 64x1
---@param space "srgb"|"linear"|"oklab"|nil Defaults to linear.
---@param proximity_space "srgb"|"linear"|"oklab"|nil Defaults to oklab.
---@return userdata color_table u8, 64x64
---@overload fun(func: IndexBlender, palette: true): userdata
local function generate_coltab(func, palette, space, proximity_space)
	local color_table = userdata("u8", 64, 64)
	
	if palette == true then
		---@cast func fun(draw_i: integer, target_i: integer): integer
		for draw_i = 0, 63 do
			for target_i = 0, 63 do
				color_table:set(target_i, draw_i, func(draw_i, target_i))
			end
		end
		
		return color_table
	end
	---@cast palette userdata LuaLS has an issue with type narrowing booleans.
	
	if not space then space = "linear" end
	if not proximity_space then proximity_space = "oklab" end
	
	local colors = {}
	colors.srgb = rgba32_to_rgbf64(palette)
	colors.linear = convert_colors(colors.srgb, srgb_to_linear)
	colors.oklab = convert_colors(colors.linear, linear_to_oklab)
	
	local evaluation_colors = colors[space]
	local proximity_colors = colors[proximity_space]
		
	local to_proximity_space = space_convert[space][proximity_space]
		or function(rgb) return rgb end
	
	for draw_i = 0, 63 do
		for target_i = 0, 63 do
			local new_rgb = func(
			---@diagnostic disable-next-line param-type-mismatch
				evaluation_colors:row(draw_i), evaluation_colors:row(target_i),
				draw_i, target_i
			)
			
			if type(new_rgb) == "number" then
				color_table:set(target_i, draw_i, new_rgb)
				goto continue
			end
			---@cast new_rgb userdata
			
			local closest = get_closest(proximity_colors, to_proximity_space(new_rgb))
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
	srgb_to_oklab = srgb_to_oklab,
	oklab_to_linear = oklab_to_linear,
	linear_to_srgb = linear_to_srgb,
	oklab_to_srgb = oklab_to_srgb,
	
	get_closest = get_closest,
	convert_colors = convert_colors,
	generate_coltab = generate_coltab,
}
