local Color = require"src/color"

---@class Lighting
local m_lighting = {}
m_lighting.__index = m_lighting

---@param main_palette userdata i32, 64x1
---@param normal_palette userdata i32, 64x1
---@return Lighting
local function new(main_palette, normal_palette)
	local ct_dot = Color.generate_coltab(
		function(draw_col, target_col)
			draw_col = draw_col * 2 - 1
			target_col = target_col * 2 - 1
			return max(draw_col:dot(target_col), 0) * 63
		end,
		normal_palette, "srgb"
	)
	
	local ct_mul_light = Color.generate_coltab(
		function(draw_i, target_i)
			return draw_i * target_i // 63
		end,
		true
	)
	
	local ct_color_light = Color.generate_coltab(
		function(_, target_col, draw_i)
			-- Doubles the effective light.
			return draw_i / 31.5 * target_col
		end,
		main_palette
	)
	
	local ct_mul = Color.generate_coltab(
		function(draw_col, target_col)
			return draw_col * target_col
		end,
		main_palette
	)
	
	local ct_add = Color.generate_coltab(
		function(draw_col, target_col)
			return draw_col + target_col
		end,
		main_palette
	)
	
	---@class Lighting
	local lighting = {
		ct_dot = ct_dot,
		ct_mul_light = ct_mul_light,
		ct_color_light = ct_color_light,
		ct_mul = ct_mul,
		ct_add = ct_add,
	}
	return setmetatable(lighting, m_lighting)
end

return {
	new = new
}