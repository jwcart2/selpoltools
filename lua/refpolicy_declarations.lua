local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"
local TREE = require "tree"

local refpolicy_decls = {}

-------------------------------------------------------------------------------
local function add_identifier_no_check(decls, flavor, identifier, node)
   decls[flavor] = decls[flavor] or {}
   if not decls[flavor][identifier] then
	  decls[flavor][identifier] = node
   end
end

local function add_identifier(decls, flavor, identifier, node, verbose)
   decls[flavor] = decls[flavor] or {}
   if decls[flavor][identifier] then
	  local f1 = TREE.get_filename(node)
	  local f2 = TREE.get_filename(decls[flavor][identifier])
	  if f1 ~= f2 or verbose > 2 then
		 local s1 = "Duplicate declaration: "..tostring(flavor).." "..tostring(identifier)
		 local s2 = string.rep(" ",string.len(s1))
		 TREE.warning(s1, node)
		 TREE.warning(s2, decls[flavor][identifier])
	  end
   else
	  decls[flavor][identifier] = node
   end
end

local function add_decls_to_all(all, decls, name, conflicting, verbose)
   for flavor, decl_tab in pairs(decls) do
	  all[flavor] = all[flavor] or {}
	  for decl,node in pairs(decl_tab) do
		 if all[flavor][decl] then
			if flavor ~= "role" then
			   local f1 = TREE.get_filename(node)
			   local s1 = "Duplicate declaration: "..tostring(flavor).." "..
				  tostring(decl)
			   local s2 = string.rep(" ",string.len(s1))
			   TREE.warning(s1, node)
			   for mod_name, prev in pairs(all[flavor][decl]) do
				  local f2 = TREE.get_filename(prev)
				  if f1 ~= f2 or verbose > 2 then
					 TREE.warning(s2, prev)
				  end
				  conflicting[name] = conflicting[name] or {}
				  conflicting[name][mod_name] = true
			   end
			end
			if not all[flavor][decl][name] then
			   all[flavor][decl][name] = node
			end
		 else
			all[flavor][decl] = {[name]=node}
		 end
	  end
   end
end

-------------------------------------------------------------------------------
local function skip(node, kind, do_action, do_block, data)
end

local function get_bool_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "bool", node_data[1], node, data.verbose)
end

local function get_tunable_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "tunable", node_data[1], node, data.verbose)
end

local function get_user_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "user", node_data[1], node, data.verbose)
end

local function get_role_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   -- Roles can be duplicated
   add_identifier_no_check(data.decls, "role", node_data[1], node)
end

local function get_type_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "type", node_data[1], node, data.verbose)
   local aliases = node_data[2]
   if aliases then
	  if type(aliases) ~= "table" then
		 add_identifier(data.decls, "type", aliases, node, data.verbose)
	  else
		 for _,alias in pairs(aliases) do
			add_identifier(data.decls, "type", alias, node, data.verbose)
		 end
	  end
   end
end

local function get_typealias_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local aliases = node_data[2]
   if type(aliases) ~= "table" then
	  add_identifier(data.decls, "type", aliases, node, data.verbose)
   else
	  for _,alias in pairs(aliases) do
		 add_identifier(data.decls, "type", alias, node, data.verbose)
	  end
   end
end

local function get_attribute_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "type", node_data[1], node, data.verbose)
end

local function get_attribute_role_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "role", node_data[1], node, data.verbose)
end

local function get_sensitivity_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "sensitivity", node_data[1], node, data.verbose)
   local aliases = node_data[2]
   if aliases then
	  if type(aliases) ~= "table" then
		 add_identifier(data.decls, "sensitivity", aliases, node, data.verbose)
	  else
		 for _,alias in pairs(aliases) do
			add_identifier(data.decls, "sensitivity", alias, node, data.verbose)
		 end
	  end
   end
end

local function get_category_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   add_identifier(data.decls, "category", node_data[1], node, data.verbose)
   local aliases = node_data[2]
   if aliases then
	  if type(aliases) ~= "table" then
		 add_identifier(data.decls, "category", aliases, node, data.verbose)
	  else
		 for _,alias in pairs(aliases) do
			add_identifier(data.decls, "category", alias, node, data.verbose)
		 end
	  end
   end
end

-- For unexpanded tree
local function get_call_decls(node, kind, do_action, do_block, data)
   local call_decls = MACRO.get_call_decls(node)
   for flavor, decl_tab in pairs(call_decls) do
	  for d,_ in pairs(decl_tab) do
		 if flavor ~= "role" then
			add_identifier(data.decls, flavor, d, node, data.verbose)
		 else
			add_identifier_no_check(data.decls, "role", d, node)
		 end
	  end
   end
end

-------------------------------------------------------------------------------
local function get_declarations_from_block(block, expanded, verbose)
   local block_actions = {
	  ["bool"] = get_bool_decl,
	  ["tunable"] = get_tunable_decl,
	  ["user"] = get_user_decl,
	  ["role"] = get_role_decl,
	  ["type"] = get_type_decl,
	  ["typealias"] = get_typealias_decl,
	  ["attribute"] = get_attribute_decl,
	  ["attribute_role"] = get_attribute_role_decl,
	  ["sensitivity"] = get_sensitivity_decl,
	  ["category"] = get_category_decl,
	  ["macro"] = skip,
	  ["module"] = skip,
   }
   if not expanded then
	  block_actions["call"] = get_call_decls
   end
   local decls = {}
   local data = {decls=decls, verbose=verbose}
   TREE.walk_normal_tree(block, block_actions, data)
   return decls
end

local function get_declarations_from_module(node, kind, do_action, do_block, data)
   local block = NODE.get_block(node)
   local decls = get_declarations_from_block(block, data.expanded, data.verbose)
   local mod_data = NODE.get_data(node)
   local name = mod_data[1]
   data.mod[name] = decls
   add_decls_to_all(data.all, decls, name, data.conflicting, data.verbose)
end

-------------------------------------------------------------------------------
local function get_declarations(head, expanded, verbose)
   MSG.verbose_out("\nCollect all potential declarations", verbose, 0)

   local all_decls = {}
   local mod_decls = {}
   local conflicting = {}

   local decl_action = {
	  ["macro"] = skip,
	  ["module"] = get_declarations_from_module,
   }
   local data = {all=all_decls, mod=mod_decls, expanded=expanded,
				 conflicting=conflicting, verbose=verbose}
   TREE.walk_normal_tree(head, decl_action, data)

   local global_decls = get_declarations_from_block(head, expanded, verbose)
   add_decls_to_all(all_decls, global_decls, "GLOBAL", conflicting, verbose)

   return all_decls, mod_decls, conflicting
end
refpolicy_decls.get_declarations = get_declarations

-------------------------------------------------------------------------------
local function compare_decls(decl1, decl2)
   for flavor, decl_tab1 in pairs(decl1) do
	  if not decl2[flavor] then
		 MSG.warning("decl2 does not have flavor "..tostring(flavor))
	  else
		 local decl_tab2 = decl2[flavor]
		 for v,_ in pairs(decl_tab1) do
			if not decl_tab2[v] then
			   MSG.warning("decl2 does not have "..tostring(v).." with flavor "..
						   tostring(flavor))
			end
		 end
	  end
   end
   for flavor, decl_tab2 in pairs(decl2) do
	  if not decl1[flavor] then
		 MSG.warning("decl1 does not have flavor "..tostring(flavor))
	  else
		 local decl_tab1 = decl1[flavor]
		 for v,_ in pairs(decl_tab2) do
			if not decl_tab1[v] then
			   MSG.warning("decl1 does not have "..tostring(v).." with flavor "..
						   tostring(flavor))
			end
		 end
	  end
   end
end
refpolicy_decls.compare_decls = compare_decls

local function compare_mod_decls(mod_decl1, mod_decl2)
   for mod, flav_tab1 in pairs(mod_decl1) do
	  if not mod_decl2[mod] then
		 MSG.warning("decl2 does not have module "..tostring(flavor))
	  else
		 local flav_tab2 = mod_decl2[mod]
		 for flavor, decl_tab1 in pairs(flav_tab1) do
			if not flav_tab2[flavor] then
			   MSG.warning("decl2 does not have flavor "..tostring(flavor)..
						   " in module "..tostring(mod))
			else
			   local decl_tab2 = flav_tab2[flavor]
			   for v,_ in pairs(decl_tab1) do
				  if not decl_tab2[v] then
					 MSG.warning("decl2 does not have "..tostring(v).." with flavor "..
								 tostring(flavor).." in module "..tostring(mod))
				  end
			   end
			end
		 end
	  end
   end
   for mod, flav_tab2 in pairs(mod_decl2) do
	  if not mod_decl1[mod] then
		 MSG.warning("decl1 does not have module "..tostring(flavor))
	  else
		 local flav_tab1 = mod_decl1[mod]
		 for flavor, decl_tab2 in pairs(flav_tab2) do
			if not flav_tab1[flavor] then
			   MSG.warning("decl1 does not have flavor "..tostring(flavor)..
						   " in module "..tostring(mod))
			else
			   local decl_tab1 = flav_tab1[flavor]
			   for v,_ in pairs(decl_tab2) do
				  if not decl_tab1[v] then
					 MSG.warning("decl1 does not have "..tostring(v).." with flavor "..
								 tostring(flavor).." in module "..tostring(mod))
				  end
			   end
			end
		 end
	  end
   end
end
refpolicy_decls.compare_mod_decls = compare_mod_decls

-------------------------------------------------------------------------------
return refpolicy_decls
