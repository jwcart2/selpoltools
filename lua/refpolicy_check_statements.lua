local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"
local TREE = require "tree"
local FLAVORS = require "refpolicy_flavors"

local refpolicy_check_statements = {}

-------------------------------------------------------------------------------
local UNUSED_FLAVOR = "_UNUSED_"

local set_ops = {
   ["*"] = "all",
   ["~"] = "not",
   ["-"] = "neg",
}

local cstr_ops = {
   ["not"] = "not",
   ["and"] = "and",
   ["or"] = "or",
}

local level_alias = {
   ["mls_systemhigh"] = true,
   ["mls_systemlow"] = true,
   ["mcs_systemhigh"] = true,
   ["mcs_systemlow"] = true,
   ["systemhigh"] = true,
   ["systemlow"] = true,
}

local cstr_flavors = {
   u1="user", u2="user", u3="user",
   r1="role", r2="role", r3="role",
   t1="type", t2="type", t3="type",
   l1="level", l2="level", h1="level", h2="level",
}

-------------------------------------------------------------------------------
local function get_module_name(node)
   local filename = TREE.get_filename(node)
   if not filename then
	  return nil
   end
   local s,e,name,suffix = string.find(filename,"/([%w%_%-]+)%.(%w%w)$")
   if suffix == "if" or suffix == "te" or suffix == "fc" then
	  return name
   end
   return nil
end

-------------------------------------------------------------------------------
local function check_skip(flavor, value, all_decls, mod_decls, mod_name,
						  modules, dependencies, verbose, warnings)
end

local function check_simple_flavor(node, flavor, value, all_decls, mod_decls, mod_name,
								   modules, dependencies, verbose, warnings)
   if type(value) ~= "table" then
	  local all_flav_decls = all_decls[flavor]
	  if not all_flav_decls then
		 local msg = TREE.compose_msg("No declarations in policy for flavor "..tostring(flavor), node)
		 MSG.warnings_buffer_add(warnings, msg)
		 return
	  end
	  if not all_flav_decls[value] then
		 if flavor == "type" and value == "self" then
			return
		 end
		 if flavor == "role" and value == "object_r" then
			return
		 end
		 local msg = TREE.compose_msg("Not declared in policy: "..tostring(flavor).." "..tostring(value), node)
		 MSG.warnings_buffer_add(warnings, msg)
		 return
	  end

	  if not mod_name then
		 return
	  end
	  if flavor == "sensitivity" or flavor == "category" then
		 return
	  end
	  if flavor == "role" and value == "system_r" then
		 return
	  end
	  local mod_flav_decls = mod_decls[mod_name][flavor]
	  if mod_flav_decls and mod_flav_decls[value] then
		 return
	  end

	  for mn,_ in pairs(all_flav_decls[value]) do
		 dependencies[mod_name] = dependencies[mod_name] or {}
		 dependencies[mod_name][mn] = true
		 if modules[mn] == "base" or mn == "GLOBAL" then
			if modules[mod_name] == "base" or verbose == 0 then
			   return
			end
		 end
	  end

	  local msg = TREE.compose_msg("Not declared in module: "..tostring(flavor).." "..tostring(value), node)
	  for _,m_node in pairs(all_flav_decls[value]) do
		 if verbose >= 1 then
			msg = msg.."\n"..TREE.compose_msg("  Declared", m_node)
		 end
	  end
	  MSG.warnings_buffer_add(warnings, msg)
   else
	  for i,v in pairs(value) do
		 if not set_ops[v] then
			check_simple_flavor(node, flavor, v, all_decls, mod_decls, mod_name,
								modules, dependencies, verbose, warnings)
		 end
	  end
   end
end

local function check_level(node, flavor, value, all_decls, mod_decls, mod_name,
						   modules, dependencies, verbose, warnings)
   if type(value) ~= "table" then
	  if not level_alias[value] then
		 check_simple_flavor(node, "sensitivity", value, all_decls, mod_decls, mod_name,
							 modules, dependencies, verbose, warnings)
	  end
   else
	  local sens = value[1]
	  local cats = value[2]
	  check_simple_flavor(node, "sensitivity", sens, all_decls, mod_decls, mod_name,
						  modules, dependencies, verbose, warnings)
	  if cats then
		 check_simple_flavor(node, "category", cats, all_decls, mod_decls, mod_name,
							 modules, dependencies, verbose, warnings)
	  end
   end
end

local function check_range(node, flavor, value, all_decls, mod_decls, mod_name,
						   modules, dependencies, verbose, warnings)
   if type(value) ~= "table" then
	  check_level(node, flavor, value, all_decls, mod_decls, mod_name,
				  modules, dependencies, verbose)
   else
	  local low = value[1]
	  local high = value[2]
	  check_level(node, flavor, low, all_decls, mod_decls, mod_name,
				  modules, dependencies, verbose)
	  if high then
		 check_level(node, flavor, high, all_decls, mod_decls, mod_name,
					 modules, dependencies, verbose)
	  end
   end
end

local function check_context(node, flavor, value, all_decls, mod_decls, mod_name,
							 modules, dependencies, verbose, warnings)
   if type(value) ~= "table" then
	  local msg = TREE.compose_msg("Expected context to contain a table", node)
	  MSG.warnings_buffer_add(warnings, msg)
   end
   if #value == 1 then
	  if value[1] ~= "<<none>>" then
		 local msg = TREE.compose_msg("Unknown context string: "..tostring(value[1]), node)
		 MSG.warnings_buffer_add(warnings, msg)
	  end
   else
	  if value[1] ~= "system_u" then
		 check_simple_flavor(node, "user", value[1], all_decls, mod_decls, mod_name,
							 modules, dependencies, verbose, warnings)
	  end
	  if value[2] ~= "object_r" then
		 check_simple_flavor(node, "role", value[2], all_decls, mod_decls, mod_name,
							 modules, dependencies, verbose, warnings)
	  end
	  check_simple_flavor(node, "type", value[3], all_decls, mod_decls, mod_name,
						  modules, dependencies, verbose, warnings)
	  if value[4] then
		 check_range(node, "range", value[4], all_decls, mod_decls, mod_name,
					 modules, dependencies, verbose)
	  end
   end
end

local function check_constraint_expr(node, flavor, value, all_decls, mod_decls, mod_name,
									 modules, dependencies, verbose, warnings)
   if type(value) ~= "table" then
	  local msg = TREE.compose_msg("Expected constraint expression to contain a table", node)
	  MSG.warnings_buffer_add(warnings, msg)
   end
   local f = cstr_flavors[value[1]]
   if f then
	  if not cstr_flavors[value[3]] then
		 if f == "level" then
			check_level(node, f, value[3], all_decls, mod_decls, mod_name,
						modules, dependencies, verbose)
		 else
			check_simple_flavor(node, f, value[3], all_decls, mod_decls, mod_name,
								modules, dependencies, verbose, warnings)
		 end
	  end
   else
	  for _,v in pairs(value) do
		 if type(v) == "table" then
			check_constraint_expr(node, flavor, v, all_decls, mod_decls, mod_name,
								  modules, dependencies, verbose)
		 end
	  end
   end
end

-------------------------------------------------------------------------------
local check_flavor = {
   ["string"] = check_skip,
   ["bool"] = check_simple_flavor,
   ["tunable"] = check_simple_flavor,
   ["class"] = check_skip,
   ["common"] = check_skip,
   ["perm"] = check_skip,
   ["xperm"] = check_skip,
   ["user"] = check_simple_flavor,
   ["role"] = check_simple_flavor,
   ["type"] = check_simple_flavor,
   ["sensitivity"] = check_simple_flavor,
   ["category"] = check_simple_flavor,
   ["level"] = check_level,
   ["range"] = check_range,
   ["c_expr"] = check_constraint_expr,
   ["cv_expr"] = check_constraint_expr,
   ["mc_expr"] = check_constraint_expr,
   ["mcv_expr"] = check_constraint_expr,
   ["context"] = check_context,
   ["sid"] = check_skip,
   ["port"] = check_skip,
   ["ip"] = check_skip,
   [UNUSED_FLAVOR] = check_skip,
}

local function check_call(node, kind, do_action, do_block, data)
   local macro_name = MACRO.get_call_name(node)
   local macro_def = data.macros[macro_name]
   if not macro_def then
	  return
   end

   if not data.in_optional then
	  local mod_name = get_module_name(macro_def)
	  if mod_name and data.name ~= mod_name then
		 data.dependencies[data.name] = data.dependencies[data.name] or {}
		 data.dependencies[data.name][mod_name] = true
		 if data.modules[mod_name] ~= "base" and
			(data.modules[data.name] == "base" or data.verbose > 0) then
			local msg = TREE.compose_msg("Call outside of an optional block: "..tostring(macro_name), node)
			MSG.warnings_buffer_add(data.warn_calls, msg)
		 end
	  end
   end

   local arg_flavors = MACRO.get_def_orig_flavors(macro_def)
   local call_args = MACRO.get_call_orig_args(node)
   for i,flavor in pairs(arg_flavors) do
	  if call_args[i] then
		 if type(flavor) ~= "table" then
			if check_flavor[flavor] then
			   check_flavor[flavor](node, flavor, call_args[i], data.all, data.mod,
									data.name, data.modules, data.dependencies,
									data.verbose, data.warn_decls)
			else
			   local msg = TREE.compose_msg("Invalid parameter flavor "..tostring(flavor), node)
			   MSG.warnings_buffer_add(data.warn_decls, msg)
			end
		 else
			for _,f in pairs(flavor) do
			   if check_flavor[f] then
				  check_flavor[f](node, flavor, call_args[i], data.all, data.mod,
								  data.name, data.modules, data.dependencies,
								  data.verbose)
			   else
				  local msg = TREE.compose_msg("Invalid parameter flavor "..tostring(f), node)
				  MSG.warnings_buffer_add(data.warn_decls, msg)
			   end
			end
		 end
	  end
   end 
end

local function check_statement(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavors = data.flavors[kind]
   if not flavors then
	  local msg = "No flavors information for a "..tostring(kind).." statement"
	  MSG.warnings_buffer_add(data.warn_decls, msg)
	  return
   end
   for i,flavor in pairs(flavors) do
	  if check_flavor[flavor] then
		 check_flavor[flavor](node, flavor, node_data[i], data.all, data.mod, data.name,
							  data.modules, data.dependencies, data.verbose)
	  else
		 local msg = TREE.compose_msg("No function to check flavor "..tostring(flavor), node)
		 MSG.warnings_buffer_add(data.warn_decls, msg)
	  end
   end
end

local function check_optional(node, kind, do_action, do_block, data)
   data.in_optional = true
   local block = NODE.get_block(node)
   TREE.walk_normal_tree(block, data.actions, data)
   data.in_optional = false
end

-------------------------------------------------------------------------------
local function skip(node, kind, do_action, do_block, data)
end

local function check_file(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local path = node_data[1]
   local s,e,name,suffix = string.find(path,"/([%w%_%-]+)%.(%w%w)$")

   if suffix == "if" or suffix == "te" or suffix == "fc" then
	  data.name = name
   end
   local block = NODE.get_block(node)
   TREE.walk_normal_tree(block, data.actions, data)
   data.name = nil
end

local function check_statements_in_policy(head, all_decls, mod_decls, macro_defs, modules,
										  verbose)
   MSG.verbose_out("\nCheck policy statements for undeclared identifiers",
				   verbose, 0)

   local statement_flavors = FLAVORS.statements
   local statement_actions = {}
   for kind,_ in pairs(statement_flavors) do
	  statement_actions[kind] = check_statement
   end
   statement_actions["optional"] = check_optional
   statement_actions["call"] = check_call
   statement_actions["macro"] = skip

   local dependencies = {}
   local warn_decls = {}
   local warn_calls = {}
   local data = {flavors=statement_flavors, actions=statement_actions, all=all_decls,
				 mod=mod_decls, macros=macro_defs, modules=modules, in_optional=false,
				 dependencies=dependencies, verbose=verbose, warn_decls=warn_decls,
				 warn_calls=warn_calls}

   local actions = {
	  ["file"] = check_file,
   }
   TREE.walk_normal_tree(head, actions, data)
   MSG.warnings_buffer_write(warn_decls)
   MSG.warnings_buffer_write(warn_calls)
   return dependencies
end
refpolicy_check_statements.check_statements_in_policy = check_statements_in_policy

-------------------------------------------------------------------------------
return refpolicy_check_statements
