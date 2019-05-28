local NODE = require "node"

local node_macro = {}

-------------------------------------------------------------------------------
local node_get_data = NODE.get_data
local node_set_data = NODE.set_data

-------------------------------------------------------------------------------
-- Macro Call Functions
-------------------------------------------------------------------------------

--------------------------------------------------
-- Macro Def Data
-- 1 - Name
-- 2 - Orig Flavors (Flavors of $1, $2, $3, etc, but not compound)
-- 3 - Expanded Args
-- 4 - Compound Args ($1_t, $1_foo_$2_t, etc)
-- 5 - Declarations
-- 6 - Used
-- 7 - Requires
-- 8 - Param info ({# optional params, # unusd params})
-- 9 - Flags ({Deprecated, Future, ...})
---------------------------------------------------

local function get_def_name(def)
   local data = node_get_data(def)
   return data and data[1]
end
node_macro.get_def_name = get_def_name

local function set_def_name(def, name)
   if not def or not name then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def, {name, false, false, false, false, false, false, false, false})
   else
      data[1] = name
   end
end
node_macro.set_def_name = set_def_name

local function get_def_orig_flavors(def)
   local data = node_get_data(def)
   return data and data[2]
end
node_macro.get_def_orig_flavors = get_def_orig_flavors

local function set_def_orig_flavors(def, flavors)
   if not def or not flavors then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def, {false, flavors, false, false, false, false, false, false,
			  false})
   else
      data[2] = flavors
   end
end
node_macro.set_def_orig_flavors = set_def_orig_flavors

local function get_def_exp_args(def)
   local data = node_get_data(def)
   return data and data[3]
end
node_macro.get_def_exp_args = get_def_exp_args

local function set_def_exp_args(def, args)
   if not def or not args then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def, {false, false, args, false, false, false, false, false, false})
   else
      data[3] = args
   end
end
node_macro.set_def_exp_args = set_def_exp_args

local function get_def_compound_args(def)
   local data = node_get_data(def)
   return data and data[4]
end
node_macro.get_def_compound_args = get_def_compound_args

local function set_def_compound_args(def, cmpd_args)
   if not def or not cmpd_args then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def, {false, false, false, cmpd_args, false, false, false, false,
			  false})
   else
      data[4] = cmpd_args
   end
end
node_macro.set_def_compound_args = set_def_compound_args

local function get_def_decls(def)
   local data = node_get_data(def)
   return data and data[5]
end
node_macro.get_def_decls = get_def_decls

local function set_def_decls(def, decls)
   if not def or not decls then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def, {false, false, false, false, decls, false, false, false, false})
   else
      data[5] = decls
   end
end
node_macro.set_def_decls = set_def_decls

local function get_def_used(def)
   local data = node_get_data(def)
   return data and data[6]
end
node_macro.get_def_used = get_def_used

local function set_def_used(def, used)
   if not def or not used then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def, {false, false, false, false, false, used, false, false, false})
   else
      data[6] = used
   end
end
node_macro.set_def_used = set_def_used

local function get_def_requires(def)
   local data = node_get_data(def)
   return data and data[7]
end
node_macro.get_def_requires = get_def_requires

local function set_def_requires(def, requires)
   if not def or not requires then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def,{false, false, false, false, false, false, requires, false,
			 false})
   else
      data[7] = requires
   end
end
node_macro.set_def_requires = set_def_requires

local function get_def_param_info(def)
   local data = node_get_data(def)
   return data and data[8]
end
node_macro.get_def_param_info = get_def_param_info

local function set_def_param_info(def, param_info)
   if not def or not param_info then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def,{false, false, false, false, false, false, false, param_info,
			 false})
   else
      data[8] = param_info
   end
end
node_macro.set_def_param_info = set_def_param_info

local function get_def_flags(def)
   local data = node_get_data(def)
   return data and data[9]
end
node_macro.get_def_flags = get_def_flags

local function set_def_flags(def, flags)
   if not def or not flags then
      return
   end
   local data = node_get_data(def)
   if not data then
      node_set_data(def,{false, false, false, false, false, false, false, false, flags})
   else
      data[9] = flags
   end
end
node_macro.set_def_flags = set_def_flags

local function set_def_data(def, name, orig_flavors, exp_args, cmpd_args, decls, used,
			    requires, param_info, flags)
   orig_flavors = orig_flavors or false
   exp_args = exp_args or false
   cmpd_args = cmpd_args or false
   decls = decls or false
   used = used or false
   requires = requires or false
   param_info = param_info or {0,0}
   flags = flags or {false, false}
   node_set_data(def, {name, orig_flavors, exp_args, cmpd_args, decls, used, requires,
		       param_info, flags})
end
node_macro.set_def_data = set_def_data

-------------------------------------------------------------------------------
-- Macro Call Functions
-------------------------------------------------------------------------------

-----------------------------------
-- Macro Call Data
-- 1 - Name
-- 2 - Original Args
-- 3 - Expanded Args
-- 4 - Declarations

-----------------------------------

local function get_call_name(call)
   local data = node_get_data(call)
   return data and data[1]
end
node_macro.get_call_name = get_call_name

local function set_call_name(call, name)
   if not call or not name then
      return
   end
   local data = node_get_data(call)
   if not data then
      node_set_data(call, {name, false, false, false})
   else
      data[1] = name
   end
end
node_macro.set_call_name = set_call_name

local function get_call_orig_args(call)
   local data = node_get_data(call)
   return data and data[2]
end
node_macro.get_call_orig_args = get_call_orig_args

local function set_call_orig_args(call, args)
   if not call or not args then
      return
   end
   local data = node_get_data(call)
   if not data then
      node_set_data(call, {false, args, false, false})
   else
      data[2] = args
   end
end
node_macro.set_call_orig_args = set_call_orig_args

local function get_call_exp_args(call)
   local data = node_get_data(call)
   return data and data[3]
end
node_macro.get_call_exp_args = get_call_exp_args

local function set_call_exp_args(call, exp_args)
   if not call or not exp_args then
      return
   end
   local data = node_get_data(call)
   if not data then
      node_set_data(call, {false, false, exp_args, false})
   else
      data[3] = exp_args
   end
end
node_macro.set_call_exp_args = set_call_exp_args

local function get_call_decls(call)
   local data = node_get_data(call)
   return data and data[4]
end
node_macro.get_call_decls = get_call_decls

local function set_call_decls(call, decls)
   if not call or not decls then
      return
   end
   local data = node_get_data(call)
   if not data then
      node_set_data(call, {false, false, false, decls})
   else
      data[4] = decls
   end
end
node_macro.set_call_decls = set_call_decls

local function set_call_data(call, name, orig_args, exp_args, decls)
   orig_args = orig_args or false
   exp_args = exp_args or false
   decls = decls or false
   node_set_data(call, {name, orig_args, exp_args, decls})
end
node_macro.set_call_data = set_call_data

return node_macro
