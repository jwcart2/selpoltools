local MSG = require "messages"
local NODE = require "node"
local TREE = require "tree"

local refpolicy_defs_process = {}

-------------------------------------------------------------------------------

local function expand_set_list(list, sets)
   local i = 1
   local last = #list
   while i <= last do
	  local e = list[i]
	  if type(e) ~= "table" then
		 if sets[e] then
			table.remove(list, i)
			for j=1,#sets[e] do
			   table.insert(list, i, sets[e][j])
			   i = i + 1
			end
			last = #list
		 else
			i = i + 1
		 end
	  else
		 expand_set_list(e, sets)
		 i = i + 1
	  end
   end
end

local function expand_sets(value, sets)
   if type(value) ~= "table" then
	  if sets[value] then
		 new_value = {value}
		 expand_set_list(new_value, sets)
		 value = new_value
	  end
   else
	  expand_set_list(value, sets)
   end
   return value
end

-------------------------------------------------------------------------------
local function process_classpermset_rule(node, kind, do_action, do_block, data)
   MSG.warnings_buffer_add(data.warnings, "No support for classpermset")
end

local function process_constrain_rule(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local class = node_data[1]
   local perms = node_data[2]
   local cexpr = node_data[3]
   class = expand_sets(class, data.defs)
   perms = expand_sets(perms, data.defs)
   cexpr = expand_sets(cexpr, data.defs)
   node_data[1] = class
   node_data[2] = perms
   node_data[3] = cexpr
end

local function process_av_rule(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local class = node_data[3]
   local perms = node_data[4]
   class = expand_sets(class, data.defs)
   perms = expand_sets(perms, data.defs)
   node_data[3] = class
   node_data[4] = perms
end

local function process_avx_rule(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local class = node_data[3]
   local perms = node_data[4]
   class = expand_sets(class, data.defs)
   perms = expand_sets(perms, data.defs)
   node_data[3] = class
   node_data[4] = perms
end

-------------------------------------------------------------------------------
local function process_defs(head, verbose, defs)
   MSG.verbose_out("\nProcess defs", verbose, 0)

   local warnings = {}
   local def_data = {verbose=verbose, defs=defs, warnings=warnings}
   local def_action = {
	  ["classpermset"] = process_classpermset_rule,
	  ["constrain"] = process_constrain_rule,
	  ["mlsconstrain"] = process_constrain_rule,
	  ["allow"] = process_av_rule,
	  ["auditallow"] = process_av_rule,
	  ["dontaudit"] = process_av_rule,
	  ["neverallow"] = process_av_rule,
	  ["allowxperm"] = process_avx_rule,
	  ["auditallowxperm"] = process_avx_rule,
	  ["dontauditxperm"] = process_avx_rule,
	  ["neverallowxperm"] = process_avx_rule,

   }

   TREE.walk_normal_tree(NODE.get_block_1(head), def_action, def_data)

   MSG.warnings_buffer_write(warnings)
end
refpolicy_defs_process.process_defs = process_defs

return refpolicy_defs_process
