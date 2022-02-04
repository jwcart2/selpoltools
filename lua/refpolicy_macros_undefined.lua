local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"
local TREE = require "tree"

local refpolicy_macros_undefined = {}

-------------------------------------------------------------------------------
local function get_last_node(head)
   local node = NODE.get_block(head)
   return TREE.get_last_node(node)
end

-------------------------------------------------------------------------------
local function find_and_add_undefined_macros(mdefs, inactive_mdefs, calls, file_parent,
											 verbose)
   local file_name = "File Added for Undefined Macros"
   local lineno = 0 -- It's generated, so just leave at 0
   local file_node = NODE.create("file", file_parent, file_name, lineno)
   NODE.set_data(file_node, {file_name})
   local top = NODE.create(false, false, false, false)
   local cur = top
   local warnings = {}
   for name, call_list in pairs(calls) do
	  if not mdefs[name] and not inactive_mdefs[name] then
		 local msg = "Creating macro definition for "..tostring(name).."()"
		 MSG.warnings_buffer_add(warnings, msg)
		 local mdef = NODE.create("macro", file_node, file_name, lineno)
		 mdefs[name] = mdef
		 local num_args = -1
		 for _,call in pairs(call_list) do
			local args = MACRO.get_call_orig_args(call)
			if #args > num_args then
			   num_args = #args
			end
		 end
		 local used = {}
		 used["string"] = {}
		 for i=1,num_args do
			local arg = "$"..tostring(i)
			used["string"][arg] = true
		 end
		 -- Really don't want warnings about too many or too few params
		 local optional = 1
		 local unused = 1
		 MACRO.set_def_data(mdef, name, false, false, false, {}, used, false,
							{optional, unused}, false)
		 cur = TREE.add_node(cur, mdef)
	  end
   end
   if TREE.next_node(top) then
	  NODE.set_block(file_node, TREE.next_node(top))
   end
   MSG.warnings_buffer_write2(verbose, warnings)
   return file_node
end

-------------------------------------------------------------------------------
local function add_undefined_macros(head, mdefs, inactive_mdefs, calls, verbose)
   MSG.verbose_out("\nAdd undefined macros", verbose, 0)

   local undefined = find_and_add_undefined_macros(mdefs, inactive_mdefs, calls, head,
												   verbose)
   local last = get_last_node(head)
   TREE.add_node(last, undefined)
end
refpolicy_macros_undefined.add_undefined_macros = add_undefined_macros

-------------------------------------------------------------------------------
return refpolicy_macros_undefined
