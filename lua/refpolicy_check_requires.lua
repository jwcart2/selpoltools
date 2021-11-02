local MSG = require "messages"
local TREE = require "tree"
local NODE = require "node"
local MACRO = require "node_macro"
local DECLS = require "refpolicy_declarations"

local refpolicy_check_requires = {}

------------------------------------------------------------------------------
local function check_if_file(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local path = node_data[1]
   local s,e,name,suffix = string.find(path,"/([%w%_%-]+)%.(%w%w)$")

   if suffix ~= "if" then
	  return
   end
   data.name = name
   local block = NODE.get_block(node)
   TREE.walk_normal_tree(block, data.file_action, data)
   data.name = nil
end

------------------------------------------------------------------------------
-- Arguments and things derived from arguments do not have to be declared
-- M4 defines such as enable_mls are treated as a tunable but are not declared
--   so don't check tunables
local function check_macro_used_not_declared(node, kind, do_action, do_block, data)
   local used = MACRO.get_def_used(node) or {}
   local exp_args = MACRO.get_def_exp_args(node) or {}
   local decls = data.all_decls or {}
   local all_tunables = decls["tunable"] or {}

   for flavor,values in pairs(used) do
	  if flavor == "class" or flavor == "perm" or flavor == "string" or
		 flavor == "tunable" or flavor == "level" or flavor == "range" then
		 -- skipping for now
	  else
		 local d = decls[flavor] or {}
		 for val,_ in pairs(values) do
			if not d[val] and not exp_args[val] and val ~= "object_r" then
			   if flavor ~= "bool" or not all_tunables[val] then
				  TREE.warning("Used but not declared: "..
							   tostring(flavor).." "..tostring(val), node)
			   end
			end
		 end
	  end
   end
end

local function check_used_not_declared(head, all_decls, verbose)
   MSG.verbose_out("\nChecking for used but not declared", verbose, 0)

   local do_action = {
	  ["file"] = check_if_file,
   }

   local file_action = {
	  ["macro"] = check_macro_used_not_declared,
   }

   local data = {file_action=file_action, all_decls=all_decls}
   TREE.walk_normal_tree(head, do_action, data)
end
refpolicy_check_requires.check_used_not_declared = check_used_not_declared

------------------------------------------------------------------------------
local function check_macro_required_not_declared(node, kind, do_action, do_block, data)
   local required = MACRO.get_def_requires(node) or {}
   local exp_args = MACRO.get_def_exp_args(node) or {}
   local decls = data.all_decls or {}
   local all_tunables = decls["tunable"] or {}

   for flavor,values in pairs(required) do
	  if flavor == "class" or flavor == "perm" or flavor == "string" then
		 -- skipping for now
	  else
		 local d = decls[flavor] or {}
		 for val,_ in pairs(values) do
			if not d[val] and not exp_args[val] then
			   if flavor ~= "bool" or not all_tunables[val] then
				  TREE.warning("Required but not declared: "..
							   tostring(flavor).." "..tostring(val), node)
			   end
			end
		 end
	  end
   end
end

local function check_required_not_declared(head, all_decls, verbose)
   MSG.verbose_out("\nChecking for required but not declared", verbose, 0)

   local do_action = {
	  ["file"] = check_if_file,
   }

   local file_action = {
	  ["macro"] = check_macro_required_not_declared,
   }

   local data = {file_action=file_action, all_decls=all_decls}
   TREE.walk_normal_tree(head, do_action, data)
end
refpolicy_check_requires.check_required_not_declared = check_required_not_declared

------------------------------------------------------------------------------
-- Arguments and things derived from arguments do not have to be required
-- Anything that is declared within an interface does not have to be required
-- The role "system_r" should be required, but usually is not, so skip for now
-- Tunables do not need to be required because they should be resolved earlier
local function check_macro_used_not_required(node, kind, do_action, do_block, data)
   local required = MACRO.get_def_requires(node) or {}
   local used = MACRO.get_def_used(node) or {}
   local decls = MACRO.get_def_decls(node) or {}
   local exp_args = MACRO.get_def_exp_args(node) or {}

   if data.verbose <= 1 and data.name and data.modules[data.name] == "base" then
	  -- Don't check base modules
	  return
   end

   for flavor,values in pairs(used) do
	  if flavor == "class" or flavor == "perm" or flavor == "string" or
		 flavor == "tunable" or flavor == "level" or flavor == "range" then
		 -- skipping for now
	  else
		 local r = required[flavor] or {}
		 local d = decls[flavor] or {}
		 for val,_ in pairs(values) do
			if not exp_args[val] and not d[val] and val ~= "system_r" then
			   if not r[val] then
				  TREE.warning("Used but not required: "..
							   tostring(flavor).." "..tostring(val), node)
			   end
			end
		 end
	  end
   end
end

local function check_used_not_required(head, mod_decls, modules, verbose)
   if verbose < 1 then return end

   MSG.verbose_out("\nChecking for used but not required", verbose, 0)

   local do_action = {
	  ["file"] = check_if_file,
   }

   local file_action = {
	  ["macro"] = check_macro_used_not_required,
   }

   local data = {mod_decls=mod_decls, modules=modules, verbose=verbose,
				 file_action=file_action}
   TREE.walk_normal_tree(head, do_action, data)
end
refpolicy_check_requires.check_used_not_required = check_used_not_required

------------------------------------------------------------------------------
-- In general, everything that is required should be used
-- Tunables shouldn't be required because they are resolved earlier
--   This is a problem because tunables are sometimes required as a bool
local function check_macro_required_not_used(node, kind, do_action, do_block, data)
   local required = MACRO.get_def_requires(node) or {}
   local used = MACRO.get_def_used(node) or {}
   local all_tunables = data.all_decls and data.all_decls["tunable"] or {}

   if data.verbose <= 1 and data.name and data.modules[data.name] == "base" then
	  -- Don't check base modules
	  return
   end

   for flavor,values in pairs(required) do
	  if flavor == "class" or flavor == "perm" or flavor == "string" then
		 -- skipping for now
	  else
		 local u = used[flavor] or {}
		 for val,_ in pairs(values) do
			if not u[val] then
			   if flavor ~= "bool" or not all_tunables[val] then
				  TREE.warning("Required but not used: "..
							   tostring(flavor).." "..tostring(val), node)
			   end
			end
		 end
	  end
   end
end

local function check_required_not_used(head, all_decls, modules, verbose)
   if verbose < 1 then return end

   MSG.verbose_out("\nChecking for required but not used", verbose, 0)

   local do_action = {
	  ["file"] = check_if_file,
   }

   local file_action = {
	  ["macro"] = check_macro_required_not_used,
   }

   local data = {all_decls=all_decls, modules=modules, verbose=verbose,
				 file_action=file_action}
   TREE.walk_normal_tree(head, do_action, data)
end
refpolicy_check_requires.check_required_not_used = check_required_not_used

------------------------------------------------------------------------------
local function check_macro_used_not_declared_module(node, kind, do_action, do_block,
													data)
   local used = MACRO.get_def_used(node) or {}
   local all_decls = data.all_decls
   local mod_decls = data.mod_decls and data.mod_decls[data.name] or {}
   local all_tunables = all_decls["tunable"] or {}
   local mod_tunables = mod_decls["tunable"] or {}

   if data.name and data.modules[data.name] == "base" then
	  -- Don't check base modules
	  return
   end

   for flavor,values in pairs(used) do
	  if flavor == "class" or flavor == "perm" or flavor == "string" or
		 flavor == "level" or flavor == "range" then
		 -- skipping for now
	  else
		 local md = mod_decls[flavor] or {}
		 local ad = all_decls[flavor] or {}
		 for val,_ in pairs(values) do
			if ad[val] and not md[val] then
			   TREE.warning("Used but not declared in module: "..
							tostring(flavor).." "..tostring(val), node)
			elseif flavor == "bool" then
			   if all_tunables[val] and not mod_tunables[val] then
				  TREE.warning("Used but not declared in module: "..
							   "tunable".." "..tostring(val), node)
			   end
			end
		 end
	  end
   end
end

local function check_used_not_declared_module(head, all_decls, mod_decls, modules, verbose)
   if verbose < 2 then return end

   MSG.verbose_out("\nChecking for used but not declared in the module", verbose, 0)

   local do_action = {
	  ["file"] = check_if_file,
   }

   local file_action = {
	  ["macro"] = check_macro_used_not_declared_module,
   }

   local data = {all_decls=all_decls, mod_decls=mod_decls, modules=modules,
				 file_action=file_action}
   TREE.walk_normal_tree(head, do_action, data)
end
refpolicy_check_requires.check_used_not_declared_module = check_used_not_declared_module

------------------------------------------------------------------------------
local function check_macro_required_not_declared_module(node, kind, do_action, do_block,
														data)
   local required = MACRO.get_def_requires(node) or {}
   local all_decls = data.all_decls
   local mod_decls = data.mod_decls and data.mod_decls[data.name] or {}
   local all_tunables = all_decls["tunable"] or {}
   local mod_tunables = mod_decls["tunable"] or {}

   if data.name and data.modules[data.name] == "base" then
	  -- Don't check base modules
	  return
   end

   for flavor,values in pairs(required) do
	  if flavor == "class" or flavor == "perm" or flavor == "string" then
		 -- skipping for now
	  else
		 local md = mod_decls[flavor] or {}
		 local ad = all_decls[flavor] or {}
		 for val,_ in pairs(values) do
			if ad[val] and not md[val] then
			   TREE.warning("Required but not declared in module: "..
							tostring(flavor).." "..tostring(val), node)
			elseif flavor == "bool" then
			   if all_tunables[val] and not mod_tunables[val] then
				  TREE.warning("Required but not declared in module: "..
							   "tunable".." "..tostring(val), node)
			   end
			end
		 end
	  end
   end
end

local function check_required_not_declared_module(head, all_decls, mod_decls, modules,
												  verbose)
   if verbose < 2 then return end

   MSG.verbose_out("\nChecking for required but not declared in the module", verbose, 0)

   local do_action = {
	  ["file"] = check_if_file,
   }

   local file_action = {
	  ["macro"] = check_macro_required_not_declared_module,
   }

   local data = {all_decls=all_decls, mod_decls=mod_decls, modules=modules,
				 file_action=file_action}
   TREE.walk_normal_tree(head, do_action, data)
end
refpolicy_check_requires.check_required_not_declared_module =
   check_required_not_declared_module

------------------------------------------------------------------------------
local function check_macro_satisfied_externally(node, kind, do_action, do_block, data)
   local required = MACRO.get_def_requires(node) or {}
   local all_decls = data.all_decls
   local all_tunables = all_decls["tunable"] or {}
   local satisfied = next(required) and true or false
   local decl_mods = {}

   for flavor,values in pairs(required) do
	  if flavor == "class" or flavor == "perm" or flavor == "string" then
		 -- skipping for now
	  else
		 local ad = all_decls[flavor] or {}
		 for val,_ in pairs(values) do
			local found_external_decl = false
			local f = flavor
			local mods = ad[val]
			if not mods then
			   if flavor == "bool" and all_tunables[val] then
				  f = "tunable"
				  mods = all_tunables[val]
			   else
				  satisfied = false
				  break
			   end
			end
			for mod,_ in pairs(mods) do
			   if mod ~= data.name then
				  found_external_decl = true
				  decl_mods[f] = decl_mods[f] or {}
				  decl_mods[f][val] = decl_mods[f][val] or {}
				  decl_mods[f][val][mod] = true
				  break
			   end
			end
			if not found_external_decl then
			   satisfied = false
			   break
			end
		 end
	  end
	  if not satisfied then
		 break
	  end
   end

   if satisfied then
	  local name = MACRO.get_def_name(node)
	  TREE.warning("Requires block satisfied external to module for macro: "..
				   tostring(name), node)
	  if data.verbose > 0 then
		 for f,fd in pairs(decl_mods) do
			for v,vd in pairs(fd) do
			   for mod,_ in pairs(vd) do
				  MSG.warning("  Require "..tostring(f).." "..tostring(v)..
							  " is declared in module:"..tostring(mod))
			   end
			end
		 end
	  end
	  if data.verbose > 1 then
		 local calls = data.calls or {}
		 if not calls[name] then
			MSG.warning("  The macro is not called in policy")
		 else
			MSG.warning("  The macro is called in the following places:")
			local call_data = calls[name]
			for i=1,#call_data do
			   TREE.warning("    ",call_data[i])
			end
		 end
	  end
   end
end

local function check_requires_satisfied_externally(start, all_decls, calls, verbose)
   local do_action = {
	  ["file"] = check_if_file,
   }

   local file_action = {
	  ["macro"] = check_macro_satisfied_externally,
   }

   local data = {verbose=verbose, all_decls=all_decls, calls=calls,
				 file_action=file_action}
   TREE.walk_normal_tree(start, do_action, data)
end

local function check_inactive_requires_satisfied_externally(head, all_decls, mod_decls,
															calls, verbose)
   MSG.verbose_out("\nChecking for require blocks satisfied external to"..
				   " inactive modules", verbose, 0)

   head = TREE.get_head(head)
   local node_data = NODE.get_data(head) or {false, false}
   local inactive = node_data[2]
   if not inactive then
	  if verbose > 0 then
		 MSG.warning("There are no inactive files")
	  end
   else
	  check_requires_satisfied_externally(inactive, all_decls, calls, verbose)
   end
end
refpolicy_check_requires.check_inactive_requires_satisfied_externally =
   check_inactive_requires_satisfied_externally

local function check_active_requires_satisfied_externally(head, all_decls, mod_decls,
														  calls, verbose)
   if verbose < 2 then return end

   MSG.verbose_out("\nChecking for require blocks satisfied external to"..
				   " active module", verbose, 0)

   head = TREE.get_head(head)

   check_requires_satisfied_externally(head, all_decls, calls, verbose)
end
refpolicy_check_requires.check_active_requires_satisfied_externally =
   check_active_requires_satisfied_externally

------------------------------------------------------------------------------
return refpolicy_check_requires
