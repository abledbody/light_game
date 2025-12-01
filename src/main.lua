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
	
	local lighting = Lighting.new(main_palette, normal_palette, 12)
	
	--normal_palette:poke(0x5000)
	--fetch(DATP .. "pal/value.pal"):poke(0x5000)
	
	---@class AppState
	state = {
		lighting = lighting,
		map = fetch(DATP .. "map/0.map"),
		mouse_pos = vec(0, 0)
	}
end

function _update()
	local mx, my = mouse()
	state.mouse_pos = vec(mx, my)
end

function _draw()
	cls()
	local display = get_display()
	local normals = userdata("u8", display:width(), display:height() or 1)
	local lighting = state.lighting
	
	map(state.map[1].bmp)
	set_draw_target(normals)
	map(state.map[1].bmp + 256)
	set_draw_target(display)
	
	lighting:dispatch(normals, {
		{position = state.mouse_pos, color = 7},
		{position = vec(cos(t() * 0.04) * 240 + 240, sin(t() * 0.02) * 135 + 135), color = 8},
		{position = vec(cos(t() * 0.046) * 240 + 240, sin(t() * 0.034) * 135 + 135), color = 11},
		{position = vec(cos(t() * 0.042) * 240 + 240, sin(t() * 0.006) * 135 + 135), color = 16}
	})
	
	print(fmt("\^o0ffCPU: %.2f%%", stat(1) * 100), 1, 1, 7)
end

include "src/error_explorer.lua"
