local MSG = require "messages"
local NODE = require "node"
local TREE = require "tree"

local refpolicy_defs_collect = {}

-------------------------------------------------------------------------------
local function list_to_set(list)
   local set = {}
   for i=1,#list do
	  set[list[i]] = true
   end
   return set
end

local function set_to_sorted_list(set)
   local list = {}
   for s,_ in pairs(set) do
	  list[#list+1] = s
   end
   table.sort(list)
   return list
end

local function expand_set(sets, name, inprogress, done, warnings)
   local found_set = false
   for e,_ in pairs(sets[name]) do
	  if sets[e] then
		 found_set = true
	  end
   end
   if found_set then
	  local new = {}
	  for e,_ in pairs(sets[name]) do
		 if sets[e] then
			if not done[e] then
			   if inprogress[e] then
				  local msg = "Recursive definition in set "..tostring(name).." involving "..tostring(e)
				  MSG.warnings_buffer_add(warnings, msg)
			   end
			   inprogress[e] = true
			   expand_set(sets, e, inprogress, done, warnings)
			   inprogress[e] = false
			end
			for e2,_ in pairs(sets[e]) do
			   new[e2] = true
			end
		 else
			new[e] = true
		 end
	  end
	  sets[name] = new
   end
   done[name] = true
end

local function sets_to_flattened_lists(sets)
   local lists = {}
   local done = {}
   for n,_ in pairs(sets) do
	  if not done[n] then
		 expand_set(sets, n, {[n]=true}, done)
	  end
   end
   for n,set in pairs(sets) do
	  lists[n] = set_to_sorted_list(set)
   end
   return lists
end

-------------------------------------------------------------------------------
local function collect_def(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local kind = node_data[1]
   local name = node_data[2]
   if kind == "class" then
	  if data.class_sets[name] then
		 local msg = "Duplicate definition of class obj_perm_set "..tostring(name)
		 MSG.warnings_buffer_add(data.warnings, msg)
	  end
	  data.class_sets[name] = list_to_set(node_data[3])
   elseif kind == "perm" then
	  if data.perm_sets[name] then
		 local msg = "Duplicate definition of permission obj_perm_set "..tostring(name)
		 MSG.warnings_buffer_add(data.warnings, msg)
	  end
	  data.perm_sets[name] = list_to_set(node_data[3])
   elseif kind == "cstr_exp" then
	  if data.cstr_defs[name] then
		 local msg = "Duplicate definition of  "..tostring(name)
		 MSG.warnings_buffer_add(data.warnings, msg)
	  end
	  data.cstr_defs[name] = node_data[3]
   else
	  local msg = "Found unknown def called "..tostring(name)
	  MSG.warnings_buffer_add(data.warnings, msg)
   end
end

-------------------------------------------------------------------------------
local function collect_defs(head, verbose)
   MSG.verbose_out("\nCollect defs", verbose, 0)

   local warnings = {}
   local def_data = {verbose=verbose, class_sets={}, perm_sets={}, cstr_defs={},
					 warnings=warnings}
   local def_action = {
	  ["def"] = collect_def,
   }

   TREE.walk_normal_tree(NODE.get_block_1(head), def_action, def_data)

   MSG.warnings_buffer_write(warnings)

   local class_sets_lists = sets_to_flattened_lists(def_data.class_sets)
   local perm_sets_lists = sets_to_flattened_lists(def_data.perm_sets)

   local defs = {}
   for n,v in pairs(class_sets_lists) do
	  defs[n] = v
   end
   for n,v in pairs(perm_sets_lists) do
	  defs[n] = v
   end
   for n,v in pairs(def_data.cstr_defs) do
	  defs[n] = v
   end

   return defs
end
refpolicy_defs_collect.collect_defs = collect_defs

return refpolicy_defs_collect
