local MSG = require "messages"
local MACRO = require "node_macro"
local TREE = require "tree"

local refpolicy_macros_avoid = {}

-------------------------------------------------------------------------------
local function check_calls(mdefs, inactive_mdefs, calls, verbose, warnings)
   for name, call_list in pairs(calls) do
	  local macro_def = mdefs[name] or inactive_mdefs[name]
	  if macro_def then
		 local flags = MACRO.get_def_flags(macro_def)
		 if type(flags) == "table" then
			if flags[1] then
			   local msg = TREE.compose_msg("Call to deprecated macro   : "..tostring(name), macro_def)
			   MSG.warnings_buffer_add(warnings, msg)
			end
			if verbose >= 3 then
			   if flags[2] then
				  local msg = TREE.compose_msg("Call to unimplemented macro: "..tostring(name), macro_def)
				  MSG.warnings_buffer_add(warnings, msg)
			   end
			end
		 end
	  end
   end
end

-------------------------------------------------------------------------------
local function check_for_macros_to_avoid(mdefs, inactive_mdefs, calls, verbose)
   MSG.verbose_out("\nCheck for deprecated or unimplemented macros", verbose, 0)
   if verbose >= 1 then
	  local warnings = {}
	  check_calls(mdefs, inactive_mdefs, calls, verbose, warnings)
	  MSG.warnings_buffer_write(warnings)
   end
end
refpolicy_macros_avoid.check_for_macros_to_avoid = check_for_macros_to_avoid

-------------------------------------------------------------------------------
return refpolicy_macros_avoid
