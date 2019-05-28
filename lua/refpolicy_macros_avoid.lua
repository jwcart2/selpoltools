local MSG = require "messages"
local MACRO = require "node_macro"
local TREE = require "tree"

local refpolicy_macros_avoid = {}

-------------------------------------------------------------------------------
local function check_calls(defs, inactive_defs, calls, verbose)
   for name, call_list in pairs(calls) do
      local macro_def = defs[name] or inactive_defs[name]
      if macro_def then
	 local flags = MACRO.get_def_flags(macro_def)
	 if type(flags) == "table" then
	    if flags[1] then
	       TREE.warning("Call to deprecated macro   : "..tostring(name), macro_def)
	    end
	    if verbose >= 3 then
	       if flags[2] then
		  TREE.warning("Call to unimplemented macro: "..tostring(name), macro_def)
	       end
	    end
	 end
      end
   end
end

-------------------------------------------------------------------------------
local function check_for_macros_to_avoid(defs, inactive_defs, calls, verbose)
   MSG.verbose_out("\nCheck for deprecated or unimplemented macros", verbose, 0)
   if verbose >= 1 then
      check_calls(defs, inactive_defs, calls, verbose)
   end
end
refpolicy_macros_avoid.check_for_macros_to_avoid = check_for_macros_to_avoid

-------------------------------------------------------------------------------
return refpolicy_macros_avoid
