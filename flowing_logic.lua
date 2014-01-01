-- This file provides the actual flow logic that makes liquids
-- move through the pipes.

local finite_liquids = minetest.setting_getbool("liquid_finite")
local pipe_liquid_max = 64
local pipe_liquid_shows_loaded = 4

-- Evaluate and balance liquid in all regular pipes in the area

minetest.register_abm({
	nodenames = pipeworks.pipe_nodenames,
	interval = 2,
	chance = 1,
	action = function(pos, node, active_object_count, active_object_count_wider)
		local coords = {
			{x = pos.x,   y = pos.y,   z = pos.z},
			{x = pos.x,   y = pos.y-1, z = pos.z},
			{x = pos.x,   y = pos.y+1, z = pos.z},
			{x = pos.x-1, y = pos.y,   z = pos.z},
			{x = pos.x+1, y = pos.y,   z = pos.z},
			{x = pos.x,   y = pos.y,   z = pos.z-1},
			{x = pos.x,   y = pos.y,   z = pos.z+1},
		}

		local num_connections = 0
		local connection_list = {}
		local node_level = 0
		local total_level = 0
		
		for _,adjacentpos in ipairs(coords) do
			local adjacent_node = minetest.get_node(adjacentpos)
			if adjacent_node and string.find(adjacent_node.name, "pipeworks:pipe_") then
				node_level = minetest.get_meta(adjacentpos):get_float("liquid_level")	
				if node_level == nil then node_level = 0 end
				total_level = total_level + node_level
				num_connections = num_connections + 1
				table.insert(connection_list, adjacentpos)
			end
		end

		local average_level = total_level / num_connections

		for _,connected_pipe_pos in ipairs(connection_list) do
			local connected_pipe = minetest.get_node(connected_pipe_pos)
			local newnode = nil
			minetest.get_meta(connected_pipe_pos):set_float("liquid_level", average_level)
			if average_level > pipe_liquid_shows_loaded then
				if string.find(connected_pipe.name, "_empty") then
					newnode = string.gsub(connected_pipe.name, "empty", "loaded")
				end
			else
				if string.find(connected_pipe.name, "_loaded") then
					newnode = string.gsub(connected_pipe.name, "loaded", "empty")
				end
			end
			if newnode then 
				minetest.swap_node(connected_pipe_pos, {name = newnode, param2 = connected_pipe.param2}) 
			end
		end
	end
})

-- Process all pumps in the area and add their pressure to the connected pipes

minetest.register_abm({
	nodenames = {"pipeworks:pump_on"},
	interval = 1,
	chance = 1,
	action = function(pos, node, active_object_count, active_object_count_wider)
		local minp =		{x = pos.x-1, y = pos.y-1, z = pos.z-1}
		local maxp =		{x = pos.x+1, y = pos.y, z = pos.z+1}
		local pos_above =	{x = pos.x, y = pos.y+1, z = pos.z}
		local node_above = minetest.get_node(pos_above)
		if not node_above then return end

		local node_level_above = minetest.get_meta(pos_above):get_float("liquid_level")
		if node_level_above == nil then node_level_above = 0 end

		local water_nodes = minetest.find_nodes_in_area(minp, maxp, 
										{"default:water_source", "default:water_flowing"})

		if table.getn(water_nodes) > 1 then -- must be at least least 1 water source near the pump
			if string.find(node_above.name, "pipeworks:pipe_") then
				if node_level_above < pipe_liquid_max then
					minetest.get_meta(pos_above):set_float("liquid_level", node_level_above + 8) -- add water to the pipe
					if string.find(node_above.name, "pipeworks:pipe_*empty") then
						local newnode = string.gsub(node_above.name, "empty", "loaded")
						minetest.swap_node(pos_above, {name=newnode, param2 = node.param2}) 
					end
				end
			end
		end
	end
})

-- Process all fountainheads in the area and subtract water from their feed pipes

minetest.register_abm({
	nodenames = {"pipeworks:fountainhead"},
	interval = 1,
	chance = 1,
	action = function(pos, node, active_object_count, active_object_count_wider)
		local pos_above = {x = pos.x, y = pos.y+1, z = pos.z}
		local node_above = minetest.get_node(pos_above)
		if not node_above then return end

		local pos_below = {x = pos.x, y = pos.y-1, z = pos.z}
		local node_below = minetest.get_node(pos_below)
		if not node_below then return end

		local node_level_below = minetest.get_meta(pos_below):get_float("liquid_level")

		if node_level_below then
			if node_level_below > 16 then -- if pipe has more than 2 water sources in it, pressure is high enough, turn fountain on
				if node_above.name == "air" then
					minetest.set_node(pos_above, {name = "default:water_source"})
					minetest.get_meta(pos_below):set_float("liquid_level", node_level_below - 8) -- subtract water from the pipe
				end
			elseif node_level_below <= 8 then -- if pipe has 1 water source or less, pressure is too low, turn fountain off
				if node_above.name == "default:water_source" then
					minetest.set_node(pos_above, {name = "air"})
				end
			end
		end
	end
})

-- Do the same thing for spigots

minetest.register_abm({
	nodenames = {"pipeworks:spigot","pipeworks:spigot_pouring"},
	interval = 1,
	chance = 1,
	action = function(pos, node, active_object_count, active_object_count_wider)
		local pos_below = {x = pos.x, y = pos.y-1, z = pos.z}
		local below_node = minetest.get_node(pos_below)
		if not below_node then return end

		if below_node.name == "air" or below_node.name == "default:water_flowing" or below_node.name == "default:water_source" then 
			local fdir = node.param2
			local fdir_to_pos = {
				{x = pos.x,   y = pos.y, z = pos.z+1},
				{x = pos.x+1, y = pos.y, z = pos.z  },
				{x = pos.x,   y = pos.y, z = pos.z-1},
				{x = pos.x-1, y = pos.y, z = pos.z  }
			}

			local pos_adjacent = fdir_to_pos[fdir+1]
			local adjacent_node = minetest.get_node(pos_adjacent)
			if not adjacent_node then return end

			if string.find(adjacent_node.name, "pipeworks:pipe_") then

				local adjacent_node_level = minetest.get_meta(pos_adjacent):get_float("liquid_level")
				if adjacent_node_level > 16 then -- pressure high enough, turn spigot on
					if below_node.name == "air" then
						minetest.add_node(pos, {name = "pipeworks:spigot_pouring", param2 = fdir})
						minetest.set_node(pos_below, {name = "default:water_source"})
						minetest.get_meta(pos_adjacent):set_float("liquid_level", adjacent_node_level - 8) -- subtract water from pipe
					end
				elseif adjacent_node_level <= 8 then -- pressure too low, turn off spigot
					if below_node.name == "default:water_source" then
						minetest.add_node(pos,{name = "pipeworks:spigot", param2 = fdir})
						minetest.set_node(pos_below, {name = "air"})
					end
				end
			end
		end
	end
})


--[[
other nodes that need processed separately:
table.insert(pipeworks.pipe_nodenames,"pipeworks:valve_on_empty")
table.insert(pipeworks.pipe_nodenames,"pipeworks:valve_off_empty")
table.insert(pipeworks.pipe_nodenames,"pipeworks:entry_panel_empty")
table.insert(pipeworks.pipe_nodenames,"pipeworks:flow_sensor_empty")
table.insert(pipeworks.pipe_nodenames,"pipeworks:valve_on_loaded")
table.insert(pipeworks.pipe_nodenames,"pipeworks:entry_panel_loaded")
table.insert(pipeworks.pipe_nodenames,"pipeworks:flow_sensor_loaded")
]]--
