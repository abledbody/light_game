include "src/require.lua"

-------------------------------------Dependencies--------------------------------------



---------------------------------------App State---------------------------------------

local state --- @type AppState

---@return AppState
local function new_app_state()
	--- @class AppState
	---@diagnostic disable-next-line: redefined-local
	local state = {}
	return state
end

----------------------------------Picotron Callbacks-----------------------------------

function _init()
	state = new_app_state()
end

function _update()
	
end

function _draw()

end

include "src/error_explorer.lua"
