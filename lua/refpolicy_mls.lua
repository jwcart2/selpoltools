local MSG = require "messages"
local NODE = require "node"
local TREE = require "tree"

local refpolicy_mls = {}

-------------------------------------------------------------------------------
local level_alias_names = {
   ["mls_systemhigh"] = true,
   ["mls_systemlow"] = true,
   ["mcs_systemhigh"] = true,
   ["mcs_systemlow"] = true,
   ["systemhigh"] = true,
   ["systemlow"] = true,
}
refpolicy_mls.level_alias_names = level_alias_names

local function get_level_aliases(num_sens, num_cats)
   local low_sens = "s0"
   local high_sens = "s"..tostring(num_sens-1)
   local low_cat = "c0"
   local high_cat = "c"..tostring(num_cats-1)
   local level_aliases = {
	  ["mls_systemhigh"] = {high_sens, {{low_cat, high_cat}}},
	  ["mls_systemlow"] = {low_sens, {}},
	  ["mcs_systemhigh"] = {low_sens, {{low_cat, high_cat}}},
	  ["mcs_systemlow"] = {low_sens, {}},
	  ["systemhigh"] = {high_sens, {{low_cat, high_cat}}},
	  ["systemlow"] = {low_sens, {}},
   }

   return level_aliases
end
refpolicy_mls.get_level_aliases = get_level_aliases

-------------------------------------------------------------------------------
local function create_sens(num_sens, parent, file, lineno)
   local first, last
   local node = NODE.create("sensitivity", parent, file, lineno)
   first = node
   for i=1,num_sens do
	  local s = "s"..tostring(i-1)
	  NODE.set_data(node, {s, false})
	  last = TREE.add_node(last, node)
	  node = NODE.create("sensitivity", parent, file, lineno)
   end
   return first, last
end
refpolicy_mls.create_sens = create_sens

local function create_cats(num_cats, parent, file, lineno)
   local first, last
   local node = NODE.create("category", parent, file, lineno)
   first = node
   for i=1,num_cats do
	  local c = "c"..tostring(i-1)
	  NODE.set_data(node, {c, false})
	  last = TREE.add_node(last, node)
	  node = NODE.create("category", parent, file, lineno)
   end
   return first, last
end
refpolicy_mls.create_cats = create_cats

local function create_dominance(num_sens, parent, file, lineno)
   local node = NODE.create("dominance", parent, file, lineno)
   local dominance = {}
   for i=1,num_sens do
	  local s = "s"..tostring(i-1)
	  dominance[#dominance+1] = s
   end
   NODE.set_data(node, {dominance})
   return node
end
refpolicy_mls.create_dominance = create_dominance

local function create_levels(num_sens, num_cats, parent, file, lineno)
   local first, last
   local node = NODE.create("level", parent, file, lineno)
   first = node
   local low_cat = "c0"
   local high_cat = "c"..tostring(num_cats-1)
   for i=1,num_sens do
	  local s = "s"..tostring(i-1)
	  NODE.set_data(node, {{s, {{low_cat, high_cat}}}})
	  last = TREE.add_node(last, node)
	  node = NODE.create("level", parent, file, lineno)
   end
   return first, last
end
refpolicy_mls.create_levels = create_levels

-------------------------------------------------------------------------------
local function create_default_mls(num_sens, num_cats, file_parent)
   local file_name = "File Added for Default MLS Rules"
   local lineno = 0
   local file_node = NODE.create("file", file_parent, file_name, lineno)
   NODE.set_data(file_node, {file_name})
   local top = NODE.create(false, false, false, false)
   local cur = top
   local first, last
   first, last = create_sens(num_sens, file_node, file_name, lineno)
   TREE.add_node(cur, first)
   cur = last
   first, last = create_cats(num_cats, file_node, file_name, lineno)
   TREE.add_node(cur, first)
   cur = last
   first = create_dominance(num_sens, file_node, file_name, lineno)
   cur = TREE.add_node(cur, first)
   first, last = create_levels(num_sens, num_cats, file_node, file_name, lineno)
   TREE.add_node(cur, first)
   cur = last
   if TREE.next_node(top) then
	  NODE.set_block(file_node, TREE.next_node(top))
   end
   return file_node
end
refpolicy_mls.create_default_mls = create_default_mls

-------------------------------------------------------------------------------
return refpolicy_mls
