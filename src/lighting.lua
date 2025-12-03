local Color = require"src/color"
local atan = math.atan
local eta = math.pi * 0.5
local tau = math.pi * 2

---@param position userdata f64, 3x1
---@param color integer
---@return Light
local function new_light(position, color)
	---@class Light
	local light = {
		position = position,
		color = color,
	}
	return light
end

------------------------------------Procedural maps------------------------------------

local elevation_steps = {1, 8, 8, 12, 16, 19}
local elevation_offsets = {0, 1, 9, 17, 29, 45}

---@param size integer
---@param z integer
---@param noise userdata f64
local function generate_light_normals(size, z, noise)
	local ud = userdata("u8", size, size)
	
	for y = 0, size - 1 do
		local cy = y - size * 0.5
		for x = 0, size - 1 do
			local cx = x - size * 0.5
			
			local angle_noise_sample = noise:get(
				x % noise:width(),
				y % noise:height(),
				1
			)
			local elevation_noise_sample = noise:get(
				(y + 4) % noise:width(),
				(x + 4) % noise:height(),
				1
			)
			
			local elevation = atan((cx * cx + cy * cy)^0.5, z) / eta
			elevation = flr(elevation * (#elevation_steps - 1) + elevation_noise_sample)
			elevation = min(elevation, #elevation_steps - 1) + 1
			
			local steps = elevation_steps[elevation] or elevation_steps[#elevation_steps]
			local offset = elevation_offsets[elevation] or elevation_offsets[#elevation_offsets]
			
			local angle = atan(-cy, -cx)
			local step = (angle / tau * steps + angle_noise_sample) % steps
			ud:set(x, y, offset + step)
		end
	end
	
	return ud
end

---@param z number
---@param threshold number
---@param noise userdata f64
local function generate_light_luminance(z, threshold, noise)
	threshold = max(threshold, 1)
	
	local zz = z * z
	local normalizing_scale = (63 + threshold) * zz
    local distance_squared = normalizing_scale / (1 - 63/64 + threshold)
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
	local lums_63 = (lums * normalizing_scale - threshold):max(0):min(63)
	
	
	local tiled_noise = userdata("f64", size, size)
	for y = 0, size - 1, noise:height() or 1 do
		for x = 0, size - 1, noise:width() do
			blit(noise, tiled_noise, 0, 0, x, y)
		end
	end
	
	local ud = (lums_63 + tiled_noise):convert("u8")
	
	return ud
end

---------------------------------------Rendering---------------------------------------

---@class Lighting
local m_lighting = {}
m_lighting.__index = m_lighting

---@param normal userdata
---@param lights Light[]
function m_lighting:light(normal, lights)
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
---@param light_distance number
---@param light_threshold number
---@param noise userdata f64
---@return Lighting
local function new(main_palette, normal_palette, light_distance, light_threshold, noise)
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
	
	local light_luminance_map = generate_light_luminance(light_distance, light_threshold, noise)
	local light_normal_map = generate_light_normals(light_luminance_map:width(), light_distance, noise)
	
	---@class Lighting
	local lighting = {
		ct_dot = ct_dot,
		ct_mul_light = ct_mul_light,
		ct_color_light = ct_color_light,
		ct_mul = ct_mul,
		ct_add = ct_add,
		light_luminance = light_luminance_map,
		light_normal_map = light_normal_map,
	}
	return setmetatable(lighting, m_lighting)
end

return {
	new = new,
	new_light = new_light
}