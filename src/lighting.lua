local Color = require"src/color"
local atan = math.atan
local pi = math.pi
local tau = pi * 2

local blue_noise = get_spr(192):convert("f64") / 64

local function dither(data, w, h)
	local tiled_noise = userdata("f64", w, h)
	for y = 0, h - 1, blue_noise:height() or 1 do
		for x = 0, w - 1, blue_noise:width() do
			blit(blue_noise, tiled_noise, 0, 0, x, y)
		end
	end
	
	return data + tiled_noise
end

local elevation_steps = {1, 8, 8, 12, 16, 19}
local elevation_offsets = {0, 1, 9, 17, 29, 45}

---@param size integer
---@param z integer
local function generate_light_normals(size, z)
	local zz = z * z
	
	local x_all = userdata("f64", size, size)
	-- Initialize first row with [-size * 0.5, 1, ..., 1]
	x_all:set(0, 0, -size * 0.5)
	x_all:copy(1, true, 0, 1, size - 1)
		-- Prefix sum first row
		:add(x_all, true, 0, 1, 1, 1, 1, size - 1)
	
	local x_sqr = x_all
		-- Square first row
		:mul(x_all, false, 0, 0, 1, 1, 1, size)
	
	-- Copy first row to all others
	x_all:copy(x_all, true, 0, size, size, 0, size, size - 1)
	x_sqr:copy(x_sqr, true, 0, size, size, 0, size, size - 1)
	
	local inverse_magnitudes = 1 / (x_sqr + x_sqr:transpose() + zz):pow(0.5)
	local z_normalized = z * inverse_magnitudes
	
	local ud = userdata("u8", size, size)
	
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local angle_noise_sample = blue_noise:get(
				x % blue_noise:width(),
				y % blue_noise:height(),
				1
			)
			local elevation_noise_sample = blue_noise:get(
				(y + 4) % blue_noise:width(),
				(x + 4) % blue_noise:height(),
				1
			)
			
			local elevation = min(
				flr((1 - z_normalized:get(x, y)) * (#elevation_steps - 1) + elevation_noise_sample),
				#elevation_steps - 1
			) + 1
			
			local steps = elevation_steps[elevation] or elevation_steps[#elevation_steps]
			local offset = elevation_offsets[elevation] or elevation_offsets[#elevation_offsets]
			
			local angle = atan(size * 0.5 - y, size * 0.5 - x)
			local step = (angle / tau * steps + angle_noise_sample) % steps
			ud:set(x, y, offset + step)
		end
	end
	
	return ud
end

---@param z number
---@param clamp_low number
---@param clamp_high number
local function generate_light_luminance(z, clamp_low, clamp_high)
	clamp_low = max(clamp_low, 1)
	
	local zz = z * z
	local normalizing_scale = (63 + clamp_low) * (zz + clamp_high)
    local distance_squared = normalizing_scale / (1 - 63/64 + clamp_low)
    local radius = sqrt(distance_squared)
    local size = ceil(radius * 2) + 1
	
	local x_all = userdata("f64", size, size)
	-- Initialize first row with [-size * 0.5, 1, ..., 1]
	x_all:set(0, 0, -size * 0.5)
	x_all:copy(1, true, 0, 1, size - 1)
		-- Prefix sum first row
		:add(x_all, true, 0, 1, 1, 1, 1, size - 1)
		-- Square first row
		:mul(x_all, true, 0, 0, 1, 1, 1, size)
		-- Copy first row to all others
		:copy(x_all, true, 0, size, size, 0, size, size - 1)
	
	-- Inverse squared distance
	local lums = x_all.div(1, x_all + x_all:transpose() + zz)
	local lums_63 = (lums * normalizing_scale - clamp_low):max(0):min(63)
	
	
	local tiled_noise = userdata("f64", size, size)
	for y = 0, size - 1, blue_noise:height() or 1 do
		for x = 0, size - 1, blue_noise:width() do
			blit(blue_noise, tiled_noise, 0, 0, x, y)
		end
	end
	
	local ud = (lums_63 + tiled_noise):convert("u8")
	
	return ud
end

---@class Lighting
local m_lighting = {}
m_lighting.__index = m_lighting

---@class Light
---@field color integer
---@field position userdata f64, 3x1

---@param normal userdata
---@param lights Light[]
function m_lighting:dispatch(normal, lights)
	local prev_draw_target = get_draw_target()
	local cx, cy = camera()
	local w, h = prev_draw_target:width(), prev_draw_target:height() or 1
	local light_size = vec(self.light_luminance:width(), self.light_luminance:height() or 1)
	local center = light_size * 0.5
	
	local color_buffer = userdata("u8", w, h)
	poke(0x550b, 0x3f)
	for _, light in ipairs(lights) do
		local buffer = self.light_normal_map:copy()
		set_draw_target(buffer)
		
		camera(light.position.x - cx - center.x, light.position.y - cy - center.y)
		
		memmap(self.ct_dot, 0x8000)
		spr(normal)
		unmap(self.ct_dot)
		
		camera()
		
		memmap(self.ct_mul_light, 0x8000)
		spr(self.light_luminance)
		unmap(self.ct_mul_light)
		
		memmap(self.ct_color_light, 0x8000)
		rectfill(0, 0, light_size.x, light_size.y, light.color)
		unmap(self.ct_color_light)
		
		camera(cx, cy)
		set_draw_target(color_buffer)
		memmap(self.ct_add, 0x8000)
		spr(buffer, light.position.x - center.x, light.position.y - center.y)
		unmap(self.ct_add)
	end
	poke(0x550b, 0x00)
	set_draw_target(prev_draw_target)
	
	memmap(self.ct_mul, 0x8000)
	spr(color_buffer)
	unmap(self.ct_mul)
	camera(cx, cy)
end

---@param main_palette userdata i32, 64x1
---@param normal_palette userdata i32, 64x1
---@return Lighting
local function new(main_palette, normal_palette, light_distance)
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
		function(draw_col, _, _, target_i)
			-- Doubles the effective light.
			return target_i / 31.5 * draw_col
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
	
	local light_luminance_map = generate_light_luminance(light_distance, 1, 35)
	local light_normal_map = generate_light_normals(light_luminance_map:width(), light_distance)
	
	---@class Lighting
	local lighting = {
		ct_dot = ct_dot,
		ct_mul_light = ct_mul_light,
		ct_color_light = ct_color_light,
		ct_mul = ct_mul,
		ct_add = ct_add,
		light_luminance = light_luminance_map,
		light_normal_map = light_normal_map
	}
	return setmetatable(lighting, m_lighting)
end

return {
	new = new
}