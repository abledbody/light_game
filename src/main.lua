include "src/require.lua"

-------------------------------------Dependencies--------------------------------------

local Lighting = require"src/lighting"

----------------------------------------Globals----------------------------------------

---@diagnostic disable-next-line lowercase-global
fmt = string.format

---------------------------------------App State---------------------------------------

local state ---@type AppState

----------------------------------Picotron Callbacks-----------------------------------

function _init()
	window()
	print("Loading...", nil, nil, 7)
	flip()
	
	local main_palette = fetch(DATP .. "pal/0.pal")
	local normal_palette = fetch(DATP .. "pal/normal.pal")
	
	local lighting = Lighting.new(main_palette, normal_palette)
	
	---@class AppState
	state = {
		lighting = lighting
	}
end

function _update()
	
end

function _draw()
	cls()
	-- Temporary. Displays generated color maps.
	local lighting = state.lighting
	blit(lighting.ct_dot)
	blit(lighting.ct_mul_light, nil, nil, nil, 64)
	blit(lighting.ct_color_light, nil, nil, nil, 128)
	blit(lighting.ct_mul, nil, nil, nil, 192)
	blit(lighting.ct_add, nil, nil, nil, 256)
end

include "src/error_explorer.lua"
