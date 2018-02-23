local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"
local TREE = require "tree"

local refpolicy_decls = {}

-------------------------------------------------------------------------------
local function skip(node, kind, do_action, do_block, data)
end

local function get_bool_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "bool"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
end

local function get_tunable_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "tunable"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
end

local function get_user_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "user"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
end

local function get_role_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "role"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
end

local function get_type_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "type"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
   local aliases = node_data[2]
   if aliases then
      if type(aliases) ~= "table" then
	 data.decls[flavor][aliases] = true
      else
	 for _,alias in pairs(aliases) do
	    data.decls[flavor][alias] = true
	 end
      end
   end
end

local function get_typealias_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "type"
   data.decls[flavor] = data.decls[flavor] or {}
   local aliases = node_data[2]
   if type(aliases) ~= "table" then
      data.decls[flavor][aliases] = true
   else
      for _,alias in pairs(aliases) do
	 data.decls[flavor][alias] = true
      end
   end
end

local function get_attribute_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "type"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
end

local function get_attribute_role_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "role"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
end

local function get_sensitivity_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "sensitivity"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
   local aliases = node_data[2]
   if aliases then
      if type(aliases) ~= "table" then
	 data.decls[flavor][aliases] = true
      else
	 for _,alias in pairs(aliases) do
	    data.decls[flavor][alias] = true
	 end
      end
   end
end

local function get_category_decl(node, kind, do_action, do_block, data)
   local node_data = NODE.get_data(node)
   local flavor = "category"
   data.decls[flavor] = data.decls[flavor] or {}
   data.decls[flavor][node_data[1]] = true
   local aliases = node_data[2]
   if aliases then
      if type(aliases) ~= "table" then
	 data.decls[flavor][aliases] = true
      else
	 for _,alias in pairs(aliases) do
	    data.decls[flavor][alias] = true
	 end
      end
   end
end

-- For unexpanded tree
local function get_call_decls(node, kind, do_action, do_block, data)
   local call_decls = MACRO.get_call_decls(node)
   for flavor, decl_tab in pairs(call_decls) do
      data.decls[flavor] = data.decls[flavor] or {}
      for d,_ in pairs(decl_tab) do
	 data.decls[flavor][d] = true
      end
   end
end

-------------------------------------------------------------------------------
local function get_declarations_from_block(block, expanded)
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
   local data = {decls=decls}
   TREE.walk_normal_tree(block, block_actions, data)
   return decls
end

local function get_declarations_from_module(node, kind, do_action, do_block, data)
   local block = NODE.get_block(node)
   local decls = get_declarations_from_block(block, data.expanded)
   local mod_data = NODE.get_data(node)
   local name = mod_data[1]
   data.mod[name] = decls
   for flavor, decl_tab in pairs(decls) do
      data.all[flavor] = data.all[flavor] or {}
      for d,_ in pairs(decl_tab) do
	 data.all[flavor][d] = data.all[flavor][d] or {}
	 data.all[flavor][d][name] = true
      end
   end
end

-------------------------------------------------------------------------------
local function get_declarations(head, expanded, verbose)
   MSG.verbose_out("\nCollect all potential declarations", verbose, 0)

   local all_decls = {}
   local mod_decls = {}

   local decl_action = {
      ["macro"] = skip,
      ["module"] = get_declarations_from_module,
   }
   local data = {all=all_decls, mod=mod_decls, expanded=expanded}
   TREE.walk_normal_tree(head, decl_action, data)

   local global_decls = get_declarations_from_block(head, expanded)
   for flavor, decl_tab in pairs(global_decls) do
      all_decls[flavor] = all_decls[flavor] or {}
      for d,_ in pairs(decl_tab) do
	 all_decls[flavor][d] = all_decls[flavor][d] or {}
	 all_decls[flavor][d]["GLOBAL"] = true
      end
   end

   return all_decls, mod_decls
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
