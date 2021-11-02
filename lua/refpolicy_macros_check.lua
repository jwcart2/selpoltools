local MSG = require "messages"
local NODE = require "node"
local TREE = require "tree"

local refpolicy_macros_check = {}

-------------------------------------------------------------------------------

local function in_optional(node)
   local parent = NODE.get_parent(node)
   while parent do
	  if NODE.get_kind(parent) == "optional" then
		 return true
	  end
	  parent = NODE.get_parent(parent)
   end
   return false
end

local function check_for_undefined_calls(mdefs, inactive_mdefs, calls, verbose)
   for name, call_list in pairs(calls) do
	  if not mdefs[name] then
		 if not inactive_mdefs[name] then
			TREE.warning("No macro definition for "..tostring(name).."()", nil)
			if verbose > 0 then
			   for _,call in pairs(call_list) do
				  TREE.warning("  Called", call)
			   end
			end
		 else
			local nodes = {}
			for _,call in pairs(call_list) do
			   if not in_optional(call) then
				  nodes[#nodes+1] = call
			   end
			end
			if next(nodes) or verbose > 1 then
			   TREE.warning("Macro definition for "..tostring(name)..
							"() is defined in inactive policy", nil)
			   if next(nodes) then
				  for _, node in pairs(nodes) do
					 TREE.warning("  Called outside optional", node)
				  end
			   end
			end
		 end
	  end
   end
end

-------------------------------------------------------------------------------
local function check_macros(mdefs, inactive_mdefs, calls, verbose)
   MSG.verbose_out("\nCheck macros", verbose, 0)

   check_for_undefined_calls(mdefs, inactive_mdefs, calls, verbose)
end
refpolicy_macros_check.check_macros = check_macros

-------------------------------------------------------------------------------
return refpolicy_macros_check
