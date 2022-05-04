local SPT = require "selpoltools"
local MSG = require "messages"
local NODE = require "node"
local TREE = require "tree"
local IFDEF = require "node_ifdef"
local STRING = require "common_string"
local TABLE = require "common_table"
local MACRO = require "node_macro"
local TREE = require "tree"

local simpl_write = {}

-------------------------------------------------------------------------------
local function flush_buffer(out, buffer)
   for i = 1,#buffer do
	  out:write(buffer[i])
	  buffer[i] = nil
   end
end

-------------------------------------------------------------------------------
local function find_common_path_from_file(node, kind, do_action, do_block, data)
   local path = NODE.get_file_name(node)
   if not path then
	  return
   end
   local dirs = {}
   local s,e,pos,len,dirname
   pos = 1
   len = #path
   if string.find(path,"^/") then
	  dirs[1] = "/"
	  pos = 2
   end
   while pos <= len do
	  s,e,dirname = string.find(path,"([^%/]+)/",pos)
	  if e then
		 dirs[#dirs+1] = dirname
		 dirs[#dirs+1] = "/"
		 pos = e + 1
	  else
		 pos = len + 1
	  end
   end
   if not data.dirs then
	  data.dirs = dirs
   else
	  local num = #data.dirs
	  local i = 1
	  while i <= num and data.dirs[i] == dirs[i] do
		 i = i + 1
	  end
	  while i <= num do
		 data.dirs[i] = nil
		 i = i + 1
	  end
   end
end

local function find_common_path(head)
   local action = {
	  ["file"] = find_common_path_from_file,
   }
   data = {}
   TREE.walk_normal_tree(head, action, data)

   local common_path
   if data.dirs then
	  common_path = table.concat(data.dirs)
   end
   return common_path
end

-------------------------------------------------------------------------------
local function compose_exp_common(exp, left, right)
   local buf = {}
   for i = 1,#exp do
	  if type(exp[i]) == "table" then
		 buf[#buf+1] = compose_exp_common(exp[i], left, right)
	  else
		 buf[#buf+1] = exp[i]
	  end
   end
   local str = table.concat(buf, " ")
   return left..str..right
end

local function compose_set(set)
   if type(set) ~= "table" then
	  if not set then
		 return "{}"
	  else
		 return tostring(set)
	  end
   elseif #set == 1 then
	  return compose_set(set[1])
   end
   return compose_exp_common(set, "{", "}")
end

local function compose_list(list)
   if type(list) ~= "table" then
	  if not list then
		 return "{}"
	  else
		 return tostring(list)
	  end
   elseif #list == 1 then
	  return compose_list(list[1])
   end
   return compose_exp_common(list, "{", "}")
end

local function compose_enclosed_list(list)
   if type(list) ~= "table" then
	  if not list then
		 return "{}"
	  else
		 return "{"..tostring(list).."}"
	  end
   end
   return compose_exp_common(list, "{", "}")
end

local function compose_conditional(cond)
   if type(cond) ~= "table" then
	  return "("..tostring(cond)..")"
   end
   return compose_exp_common(cond, "(", ")")
end

local function compose_constraint(const)
   if type(const) ~= "table" then
	  return "("..tostring(const)..")"
   end
   return compose_exp_common(const, "(", ")")
end

local function compose_classperms(classperms)
   if type(classperms) ~= "table" then
	  -- classpermset
	  return tostring(classperms)
   elseif #classperms ~= 2 then
	  MSG.warning("Class permissions have the wrong number of elements")
	  return "{}"
   else
	  local class = tostring(classperms[1])
	  local perms = compose_set(classperms[2])
	  return class.." "..perms
   end
end

local function compose_xperms(xperms)
   if type(xperms) ~= "table" then
	  return tostring(xperms)
   elseif #xperms == 1 then
	  return xperms[1]
   else
	  local buf = {}
	  for i = 1,#xperms do
		 if type(xperms[i]) == "table" then
			local xp = xperms[i]
			if #xp ~= 2 then
			   MSG.warning("Range in xperms does not have two members")
			   return "[]"
			end
			buf[#buf+1] = "["..xp[1].." "..xp[2].."]"
		 else
			buf[#buf+1] = xperms[i]
		 end
	  end
   end
   return "{"..table.concat(buf," ").."}"
end

local function compose_categories(cats)
   local buf = {}
   if type(cats) ~= "table" then
	  buf[#buf+1] = tostring(cats)
   else
	  for i = 1,#cats do
		 if type(cats[i]) == "table" then
			local cs = cats[i]
			if #cs ~= 2 then
			   MSG.warning("Range in category list does not have two members")
			   return "[]"
			end
			buf[#buf+1] = "["..cs[1].." "..cs[2].."]"
		 else
			buf[#buf+1] = cats[i]
		 end
	  end
   end
   return "{"..table.concat(buf," ").."}"
end

local function compose_level(level)
   if type(level) ~= "table" then
	  -- level alias
	  return tostring(level)
   elseif #level > 2 then
	  MSG.warning("Level has more then two parts")
	  return "{}"
   else
	  local s = tostring(level[1])
	  if level[2] then
		 c = compose_categories(level[2])
		 return s.." "..c
	  end
	  return s
   end
end

local function compose_range(range)
   if type(range) ~= "table" then
	  -- range alias
	  return tostring(range)
   elseif #range > 2 then
	  MSG.warning("Range has more then two parts")
	  return "{}"
   else
	  local l1 = compose_level(range[1])
	  if range[2] then
		 local l2 = compose_level(range[2])
		 return "{{"..l1.."} {"..l2.."}}"
	  else
		 return "{"..l1.."}"
	  end
   end
end

local function compose_context(context)
   if type(context) ~= "table" then
	  -- context alias
	  return tostring(context)
   elseif #context == 1 and context[1] == "<<none>>" then
	  return context[1]
   elseif #context < 3 or #context > 4 then
	  MSG.warning("Context has wrong number of elements")
	  MSG.warning(MSG.compose_table(context, "{","}"))
	  return "{}"
   else
	  local buf = {}
	  buf[#buf+1] = tostring(context[1])
	  buf[#buf+1] = tostring(context[2])
	  buf[#buf+1] = tostring(context[3])
	  if context[4] then
		 buf[#buf+1] = compose_range(context[4])
	  end
	  return "{"..table.concat(buf," ").."}"
   end
end

local function compose_number_range(range)
   if type(range) ~= "table" then
	  return tostring(range)
   else
	  if #range == 1 then
		 return tostring(range[1])
	  elseif #range ~= 2 then
		 MSG.warning("Range does not have two members")
		 return "[]"
	  else
		 return "["..range[1].." "..range[2].."]"
	  end
   end
end

local function compose_call_args(args)
   local buf = {}
   for i=1,#args do
	  local a = args[i]
	  if type(a) == "table" then
		 buf[#buf+1] = compose_exp_common(a, "{", "}")
	  else
		 buf[#buf+1] = tostring(a)
	  end
   end
   return "("..table.concat(buf,", ")..")"
end

-------------------------------------------------------------------------------
local function buffer_handleunknown_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local value = tostring(data[1])
   local str = "handleunknown "..value..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_mls_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local value = tostring(data[1])
   local str = "mls "..value..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_filecon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local path = tostring(data[1])
   local file_type = tostring(data[2])
   local context = compose_context(data[3])
   local str = "filecon "..path.." "..file_type.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_common_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local common= tostring(data[1])
   local perm_list = compose_enclosed_list(data[2])
   local str = "common "..common.." "..perm_list..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_class_decl_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local class = tostring(data[1])
   local str = "decl class "..class..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_class_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local class = tostring(data[1])
   local common = data[2] or "<<none>>"
   local perm_list = compose_enclosed_list(data[3])
   local str = "class "..class.." "..common.." "..perm_list..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_classpermset_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local classperms = compose_classperms(data[2])
   local str = "classpermset "..name.." "..classperms..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_default_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local kind = NODE.get_kind(node)
   local class_list = compose_list(data[1])
   local object = tostring(data[2])
   local str
   if kind == "default_range" then
	  str = kind.." "..class_list.." "..object.." "..tostring(data[3])..";"
   else
	  str = kind.." "..class_list.." "..object..";"
   end
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_sensitivity_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local sens = tostring(data[1])
   local str = "decl sensitivity "..sens..";"
   STRING.add_to_buffer(buf, format, str)
   local aliases = data[2]
   if aliases then
	  if type(aliases) ~= "table" then
		 str = "alias sensitivity "..tostring(aliases).." "..sens..";"
		 STRING.add_to_buffer(buf, format, str)
	  else
		 for i=1,#aliases do
			str = "alias sensitivity "..tostring(aliases[i]).." "..sens..";"
			STRING.add_to_buffer(buf, format, str)
		 end
	  end
   end
end

local function buffer_sensorder_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local sens_list = compose_enclosed_list(data[1])
   local str = "order sensitivity "..sens_list..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_category_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local category = tostring(data[1])
   local str = "category "..category..";"
   STRING.add_to_buffer(buf, format, str)
   local aliases = data[2]
   if aliases then
	  if type(aliases) ~= "table" then
		 str = "alias category "..tostring(aliases).." "..category..";"
		 STRING.add_to_buffer(buf, format, str)
	  else
		 for i=1,#aliases do
			str = "alias category "..tostring(aliases[i]).." "..category..";"
			STRING.add_to_buffer(buf, format, str)
		 end
	  end
   end
end

local function buffer_level_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local level = compose_level(data[1])
   local str = "level "..level..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_aliaslevel_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local alias = tostring(data[1])
   local level = compose_level(data[2])
   local str = "alias level "..alias.." "..level..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_aliasrange_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local alias = tostring(data[1])
   local range = compose_range(data[2])
   local str = "alias range "..alias.." "..range..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_mlsconstrain_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local class = compose_list(data[1])
   local perms = compose_set(data[2])
   local cstr = compose_constraint(data[3])
   local str = "mlsconstrain "..class.." "..perms.." "..cstr..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_mlsvalidatetrans_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local class = compose_list(data[1])
   local cstr = compose_constraint(data[2])
   local str = "mlsvalidatetrans "..class.." "..cstr..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_policycap_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local caps = compose_list(data[1])
   local str = "policycap "..caps..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_typeattr_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local attr = tostring(data[1])
   local str = "typeattr "..attr..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_roleattr_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local attr = tostring(data[1])
   local str = "roleattr "..attr..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_bool_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local bool = tostring(data[1])
   local value = tostring(data[2])
   local str = "bool "..bool.." "..value..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_tunable_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local tunable = tostring(data[1])
   local value = tostring(data[2])
   local str = "tunable "..tunable.." "..value..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_type_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local str = "type "..name..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_typealias_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local aliases = data[2]
   if aliases then
	  if type(aliases) ~= "table" then
		 local str = "alias type "..tostring(aliases).." "..name..";"
		 STRING.add_to_buffer(buf, format, str)
	  else
		 for i=1,#aliases do
			local str = "alias type "..tostring(aliases[i]).." "..name..";"
			STRING.add_to_buffer(buf, format, str)
		 end
	  end
   end
end

local function buffer_typebounds_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local parent = tostring(data[1])
   local child = tostring(data[2])
   local str = "typebounds "..parent.." "..child..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_typeattrs_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local attrs = compose_list(data[2])
   local str = "typeattrs "..name.." "..attrs..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_attrtypes_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local attr = tostring(data[1])
   local types = compose_set(data[2])
   local str = "attrtypes "..attr.." "..types..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_permissive_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local str = "permissive "..name..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_av_rule(buf, format, node)
   local kind = NODE.get_kind(node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local perms = compose_set(data[4])
   local str = kind.." "..src.." "..tgt.." "..class.." "..perms..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_xperm_rule(buf, format, node)
   local kind = NODE.get_kind(node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local perms = compose_set(data[4])
   local xperms = compose_xperms(data[5])
   local str = kind.." "..src.." "..tgt.." "..class.." "..perms.." "..xperms..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_typetrans_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local obj = tostring(data[4])
   local file = data[5] or "nil"
   local str = "filetrans "..src.." "..tgt.." "..class.." "..obj.." "..file..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_typemember_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local obj = tostring(data[4])
   local str = "typemember "..src.." "..tgt.." "..class.." "..obj..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_typechange_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local obj = tostring(data[4])
   local str = "typechange "..src.." "..tgt.." "..class.." "..obj..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_rangetrans_rule(buf, format, node)
   local kind = NODE.get_kind(node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = data[3] or "nil"
   local range = compose_range(data[4])
   local str = kind.." "..src.." "..tgt.." "..class.." "..range..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_role_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local role = tostring(data[1])
   local str = "role "..role..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_roletypes_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local role = tostring(data[1])
   local types = compose_list(data[2])
   local str = "roletypes "..role.." "..types..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_roleattrs_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local role = tostring(data[1])
   local attrs = compose_list(data[2])
   local str = "roleattrs "..role.." "..attrs..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_roleallow_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local role1 = tostring(data[1])
   local role2 = tostring(data[2])
   local str = "roleallow "..role1.." "..role2..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_roletrans_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local roles = compose_set(data[1])
   local types = compose_set(data[2])
   local class = tostring(data[3])
   local role2 = tostring(data[4])
   local str = "roletrans "..roles.." "..types.." "..class.." "..role2..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_user_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local user = tostring(data[1])
   local roles = compose_list(data[2])
   local mls_level = data[3] and compose_level(data[3])
   local mls_range = data[4] and compose_range(data[4])
   local str = "user "..user..";"
   STRING.add_to_buffer(buf, format, str)
   str = "userrole "..user.." "..roles..";"
   STRING.add_to_buffer(buf, format, str)
   if mls_level then
	  str = "userlevel "..user.." "..mls_level..";"
	  STRING.add_to_buffer(buf, format, str)
   end
   if mls_range then
	  str = "userrange "..user.." "..mls_range..";"
	  STRING.add_to_buffer(buf, format, str)
   end
end

local function buffer_constrain_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local class = tostring(data[1])
   local perms = compose_set(data[2])
   local cstr = compose_constraint(data[3])
   local str = "constrain "..class.." "..perms.." "..cstr..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_validatetrans_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local class = compose_list(data[1])
   local cstr = compose_constraint(data[2])
   local str = "validatetrans "..class.." "..cstr..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_sid_decl_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local sid = tostring(data[1])
   local str = "decl sid "..sid..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_sid_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local sid = tostring(data[1])
   local context = compose_context(data[2])
   local str = "sid "..sid.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_fsuse_rule(buf, format, node)
   local kind = NODE.get_kind(node)
   local fs_type = string.find(kind,"fs_use_(.+)")
   local data = NODE.get_data(node) or {}
   local fs = tostring(data[1])
   local context = compose_context(data[2])
   local str = "fsuse "..fs_type.." "..fs.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_genfscon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local fs_name = tostring(data[1])
   local path = tostring(data[2])
   local file_type = tostring(data[3])
   local context = compose_context(data[4])
   local str = "genfscon "..fs_name.." "..path.." "
   if file_type == "all" then
	  str = str..context..";"
   else
	  str = str..file_type.." "..context..";"
   end
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_portcon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local protocol = tostring(data[1])
   local portnum = compose_number_range(data[2])
   local context = compose_context(data[3])
   local str = "portcon "..protocol.." "..portnum.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_netifcon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local interface = tostring(data[1])
   local context1 = compose_context(data[2])
   local context2 = compose_context(data[3])
   local str = "netifcon "..interface.." "..context1.." "..context2..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_nodecon4_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local addr4 = tostring(data[1])
   local mask4 = tostring(data[2])
   local context = compose_context(data[3])
   local str = "nodecon4 "..addr4.." "..mask4.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_nodecon6_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local addr6 = tostring(data[1])
   local mask6 = tostring(data[2])
   local context = compose_context(data[3])
   local str = "nodecon6 "..addr6.." "..mask6.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_pirqcon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local value = tostring(data[1])
   local context = compose_context(data[2])
   local str = "pirqcon "..value.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_iomemcon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local value = compose_number_range(data[1])
   local context = compose_context(data[2])
   local str = "iomemcon "..value.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_ioportcon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local value = compose_number_range(data[1])
   local context = compose_context(data[2])
   local str = "ioportcon "..value.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_pcidevicecon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local value = compose_number_range(data[1])
   local context = compose_context(data[2])
   local str = "pcidevicecon "..value.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_devicetreecon_rule(buf, format, node)
   local data = NODE.get_data(node) or {}
   local path = tostring(data[1])
   local context = compose_context(data[2])
   local str = "devicetreecon "..value.." "..context..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_call_rule(buf, format, node)
   local name = MACRO.get_call_name(node)
   local args = MACRO.get_call_orig_args(node)
   local str_args = compose_call_args(args)
   local str = "call "..tostring(name)..str_args..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_def_rule(buf, format, node)
   local node_data = NODE.get_data(node)
   local name = node_data[1]
   local list = compose_list(node_data[2])
   local kind
   if string.find(name, "_class_set$") then
	  kind = "class"
	  list = compose_list(node_data[2])
   elseif string.find(name, "_perms$") then
	  kind = "perm"
	  list = compose_list(node_data[2])
   elseif name == "basic_ubac_conditions" then
	  kind = "cexp"
	  list = compose_constraint(node_data[2])
   else
	  kind = "unknown"
	  list = compose_list(node_data[2])
   end
   local str = "def "..kind.." "..tostring(name).." "..list..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_order_rule(buf, format, node)
   local node_data = NODE.get_data(node)
   local flavor = tostring(node_data[1])
   local order = compose_enclosed_list(node_data[2])
   local str = "order "..flavor.." "..order..";"
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_comment_rule(buf, format, node)
   local node_data = NODE.get_data(node)
   local comment = node_data[1]
   local str = "#"..tostring(comment)
   STRING.add_to_buffer(buf, format, str)
end

local function buffer_blank_rule(buf, format, node)
   local node_data = NODE.get_data(node)
   local str = ""
   STRING.add_to_buffer(buf, format, str)
end

local simpl_rules = {
   ["handleunknown"] = buffer_handleunknown_rule,
   ["mls"] = buffer_mls_rule,
   ["filecon"] = buffer_filecon_rule,
   ["common"] = buffer_common_rule,
   ["class_decl"] = buffer_class_decl_rule,
   ["class"] = buffer_class_rule,
   ["classpermset"] = buffer_classpermset_rule,
   ["default"] = buffer_default_rule,
   ["sensitivity"] = buffer_sensitivity_rule,
   ["dominance"] = buffer_sensorder_rule,
   ["category"] = buffer_category_rule,
   ["level"] = buffer_level_rule,
   ["aliaslevel"] = buffer_aliaslevel_rule,
   ["aliasrange"] = buffer_aliasrange_rule,
   ["mlsconstrain"] = buffer_mlsconstrain_rule,
   ["mlsvalidatetrans"] = buffer_mlsvalidatetrans_rule,
   ["policycap"] = buffer_policycap_rule,
   ["attribute"] = buffer_typeattr_rule,
   ["attribute_role"] = buffer_roleattr_rule,
   ["bool"] = buffer_bool_rule,
   ["tunable"] = buffer_tunable_rule,
   ["type"] = buffer_type_rule,
   ["typealias"] = buffer_typealias_rule,
   ["typebounds"] = buffer_typebounds_rule,
   ["typeattribute"] = buffer_typeattrs_rule,
   ["attrtypes"] = buffer_attrtypes_rule,
   ["permissive"] = buffer_permissive_rule,
   ["allow"] = buffer_av_rule,
   ["auditallow"] = buffer_av_rule,
   ["dontaudit"] = buffer_av_rule,
   ["neverallow"] = buffer_av_rule,
   ["allowxperm"] = buffer_xperm_rule,
   ["auditallowxperm"] = buffer_xperm_rule,
   ["dontauditxperm"] = buffer_xperm_rule,
   ["neverallowxperm"] = buffer_xperm_rule,
   ["type_transition"] = buffer_typetrans_rule,
   ["type_member"] = buffer_typemember_rule,
   ["type_change"] = buffer_typechange_rule,
   ["range_transition"] = buffer_rangetrans_rule,
   ["role"] = buffer_role_rule,
   ["roletypes"] = buffer_roletypes_rule,
   ["roleattribute"] = buffer_roleattrs_rule,
   ["role_allow"] = buffer_roleallow_rule,
   ["role_transition"] = buffer_roletrans_rule,
   ["user"] = buffer_user_rule,
   ["constrain"] = buffer_constrain_rule,
   ["validatetrans"] = buffer_validatetrans_rule,
   ["sid_decl"] = buffer_sid_decl_rule,
   ["sid"] = buffer_sid_rule,
   ["fs_use_task"] = buffer_fsuse_rule,
   ["fs_use_trans"] = buffer_fsuse_rule,
   ["fs_use_xattr"] = buffer_fsuse_rule,
   ["genfscon"] = buffer_genfscon_rule,
   ["portcon"] = buffer_portcon_rule,
   ["netifcon"] = buffer_netifcon_rule,
   ["nodecon4"] = buffer_nodecon4_rule,
   ["nodecon6"] = buffer_nodecon6_rule,
   ["pirqcon"] = buffer_pirqcon_rule,
   ["iomemcon"] = buffer_iomemcon_rule,
   ["ioportcon"] = buffer_ioportcon_rule,
   ["pcidevicecon"] = buffer_pcidevicecon_rule,
   ["devicetreecon"] = buffer_devicetreecon_rule,
   ["call"] = buffer_call_rule,
   ["def"] = buffer_def_rule,
   ["order"] = buffer_order_rule,
   ["comment"] = buffer_comment_rule,
   ["blank"] = buffer_blank_rule,
}

-------------------------------------------------------------------------------
local function buffer_block_rules(buf, format, block, do_rules, do_blocks)
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if do_rules and do_rules[kind] then
		 do_rules[kind](buf, format, cur)
	  elseif do_blocks and do_blocks[kind] then
		 do_blocks[kind](buf, format, cur, do_rules, do_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
end

local function buffer_module_block(buf, format, node, do_rules, do_blocks)
   local mod_data = NODE.get_data(node)
   local version = mod_data[2]
   local str = "module "..tostring(version)..";"
   STRING.add_to_buffer(buf, format, str)
   buffer_block_rules(buf, format, NODE.get_block(node), do_rules, do_blocks)
end

local function buffer_conditional_rules(buf, format, node, do_rules, do_blocks)
   local then_block = NODE.get_then_block(node)
   local else_block = NODE.get_else_block(node)
   if then_block then
	  STRING.format_increase_depth(format)
	  buffer_block_rules(buf, format, then_block, do_rules, do_blocks)
	  STRING.format_decrease_depth(format)
   end
   if else_block then
	  STRING.add_to_buffer(buf, format, "} else {")
	  STRING.format_increase_depth(format)
	  buffer_block_rules(buf, format, else_block, do_rules, do_blocks)
	  STRING.format_decrease_depth(format)
   end
end

local function buffer_ifdef_block(buf, format, node, do_rules, do_blocks)
   local cond_data = IFDEF.get_conditional(node)
   local cond = compose_conditional(cond_data)
   local str = "ifdef "..cond.." {"
   STRING.add_to_buffer(buf, format, str)
   buffer_conditional_rules(buf, format, node, do_rules, do_blocks)
   STRING.add_to_buffer(buf, format, "}")
end

local function buffer_ifelse_block(buf, format, node, do_rules, do_blocks)
   local cond_data = NODE.get_data(node)
   local v1 = cond_data[1]
   local v2 = cond_data[2]

   local cond = tostring(v1)
   if v2 then
	  cond = cond.." == "..tostring(v2)
   end
   local str = "ifdef "..cond.." {"
   STRING.add_to_buffer(buf, format, str)
   buffer_conditional_rules(buf, format, node, do_rules, do_blocks)
   STRING.add_to_buffer(buf, format, "}")
end

local function buffer_tunif_block(buf, format, node, do_rules, do_blocks)
   local cond_data = IFDEF.get_conditional(node)
   local cond = compose_conditional(cond_data)
   local str = "tunif "..cond.." {"
   STRING.add_to_buffer(buf, format, str)
   buffer_conditional_rules(buf, format, node, do_rules, do_blocks)
   STRING.add_to_buffer(buf, format, "}")
end

local function buffer_boolif_block(buf, format, node, do_rules, do_blocks)
   local cond_data = IFDEF.get_conditional(node)
   local cond = compose_conditional(cond_data)
   local str = "boolif "..cond.." {"
   STRING.add_to_buffer(buf, format, str)
   buffer_conditional_rules(buf, format, node, do_rules, do_blocks)
   STRING.add_to_buffer(buf, format, "}")
end

local function buffer_optional_block(buf, format, node, do_rules, do_blocks)
   STRING.add_to_buffer(buf, format, "optional")
   STRING.add_to_buffer(buf, format, "{")
   buffer_conditional_rules(buf, format, node, do_rules, do_blocks)
   STRING.add_to_buffer(buf, format, "}")
end

local function args_to_string(macro)
   local flavors = MACRO.get_def_orig_flavors(macro)
   local buf = {}
   local i = 1
   local arg = "$"..tostring(i)
   while flavors[i] do
	  if type(flavors[i]) ~= "table" then
		 buf[i] = flavors[i].." "..arg
	  else
		 buf[i] = "string "..arg
	  end
	  i = i + 1
	  arg = "$"..tostring(i)
   end
   return table.concat(buf,", ")
end

local function buffer_require_rules(buf, format, node)
   local requires = MACRO.get_def_requires(node)
   if type(requires) == "boolean" then
	  return
   end
   local keys = TABLE.get_sorted_list_of_keys(requires)
   for i=1,#keys do
	  local t = keys[i]
	  if t == "class" then
		 local classes = TABLE.get_sorted_list_of_keys(requires[t])
		 if #classes == 1 then
			local c = classes[1]
			local perms = TABLE.get_sorted_list_of_keys(requires[t][c])
			local cp = compose_classperms({c,perms})
			STRING.add_to_buffer(buf, format, "require class "..cp..";")
		 else
			local cp_buf = {}
			for j=1,#classes do
			   local c = classes[j]
			   local perms = TABLE.get_sorted_list_of_keys(requires[t][c])
			   local cp = compose_classperms({c,perms})
			   cp_buf[#cp_buf+1] = "{"..cp.."}"
			end
			local cp_str = table.concat(cp_buf," ")
			STRING.add_to_buffer(buf, format, "require class ".." {"..cp_str.."};")
		 end
	  else
		 local values = compose_list(TABLE.get_sorted_list_of_keys(requires[t]))
		 STRING.add_to_buffer(buf, format, "require "..t.." "..values..";")
	  end
   end
end

local function process_compound_args(macro)
   local macro_name = MACRO.get_def_name(macro)
   local cmpd_args = MACRO.get_def_compound_args(macro)
   local cargs = {}
   if cmpd_args then
	  local n = 1
	  for v,_ in pairs(cmpd_args) do
		 cargs[v] = macro_name..tostring(n)
		 n = n + 1
	  end
   end
   return cargs
end

local function buffer_compound_args(buf, format, cargs)
   for cmpd_arg,name in pairs(cargs) do
	  local str_list = {}
	  local cur, s, e, arg
	  s = 1
	  cur = 1
	  s,e,arg = string.find(cmpd_arg, "(%$%d+)", cur)
	  while s do
		 if s > cur then
			str_list[#str_list+1] = string.sub(cmpd_arg, cur, s-1)
		 end
		 str_list[#str_list+1] = arg
		 cur = e + 1
		 s,e,arg = string.find(cmpd_arg, "(%$%d+)", cur)
	  end
	  if cur < #cmpd_arg then
		 str_list[#str_list+1] = string.sub(cmpd_arg, cur)
	  end
	  local str_list_str = table.concat(str_list, " ")
	  STRING.add_to_buffer(buf, format, "string "..name.." {"..str_list_str.."};")
   end
end

local function replace_compound_args(buf, start, cargs)
   for i=start,#buf do
	  local line = buf[i]
	  if line then
		 for old,new in pairs(cargs) do
			local s, n
			repeat
			   s,n = string.gsub(line, old, new)
			   if s and n > 0 then
				  line = s
				  buf[i] = s
			   end
			until n == 0
		 end
	  end
   end
end

local function buffer_macro_block(buf, format, node, do_rules, do_blocks)
   local name = MACRO.get_def_name(node)
   local args = args_to_string(node)
   STRING.add_to_buffer(buf, format, "macro "..tostring(name).."("..args..")")
   STRING.add_to_buffer(buf, format, "{")
   STRING.format_increase_depth(format)
   local start = #buf
   buffer_require_rules(buf, format, node)
   local cargs = process_compound_args(node)
   buffer_compound_args(buf, format, cargs)
   buffer_block_rules(buf, format, NODE.get_block(node), do_rules, do_blocks)
   STRING.format_decrease_depth(format)
   STRING.add_to_buffer(buf, format, "}")
   replace_compound_args(buf, start, cargs)
end

local simpl_blocks = {
   ["module"] = buffer_module_block,
   ["ifdef"] = buffer_ifdef_block,
   ["ifelse"] = buffer_ifelse_block,
   ["tunif"] = buffer_tunif_block,
   ["boolif"] = buffer_boolif_block,
   ["optional"] = buffer_optional_block,
   ["macro"] = buffer_macro_block,
}

-------------------------------------------------------------------------------
local function write_fc_file(out, block, format)
   local buf = {}
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if kind == "filecon" then
		 buffer_filecon_rule(buf, format, cur)
	  elseif kind == "comment" then
		 buffer_comment_rule(buf, format, cur)
	  elseif kind == "blank" then
		 buffer_blank_rule(buf, format, cur)
	  elseif kind == "tunif" then
		 buffer_tunif_block(buf, format, cur, simpl_rules, simpl_blocks)
	  elseif kind == "ifdef" then
		 buffer_ifdef_block(buf, format, cur, simpl_rules, simpl_blocks)
	  elseif kind == "optional" then
		 buffer_optional_block(buf, format, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   if next(buf) then
	  out:write("\n")
	  flush_buffer(out, buf)
   end
end

local function write_if_file(out, block, format)
   local buf = {}
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if simpl_rules[kind] then
		 simpl_rules[kind](buf, format, cur)
	  elseif simpl_blocks[kind] then
		 simpl_blocks[kind](buf, format, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   if next(buf) then
	  out:write("\n")
	  flush_buffer(out, buf)
   end
end

local function write_te_file(out, block, format)
   local buf = {}
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if simpl_rules[kind] then
		 simpl_rules[kind](buf, format, cur)
	  elseif simpl_blocks[kind] then
		 simpl_blocks[kind](buf, format, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   if next(buf) then
	  flush_buffer(out, buf)
   end
end

local function write_misc_file(out, block, format)
   local buf = {}
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if simpl_rules[kind] then
		 simpl_rules[kind](buf, format, cur)
	  elseif simpl_blocks[kind] then
		 simpl_blocks[kind](buf, format, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   flush_buffer(out, buf)
end

-------------------------------------------------------------------------------
local function sort_module_and_misc_files(node, kind, do_action, do_block, data)
   local filename = NODE.get_file_name(node)

   local s,e,mod,suffix = string.find(filename,"/([%w%_%-]+)%.(%w%w)$")
   if suffix == "fc" or suffix == "if" or suffix == "te" then
	  data.modules[mod] = data.modules[mod] or {}
	  data.modules[mod][suffix] = node
   else
	  data.misc_files[#data.misc_files+1] = node
   end
end
simpl_write.sort_module_and_misc_files = sort_module_and_misc_files

-------------------------------------------------------------------------------
local function get_dirs_and_filename_from_full_path(full_path, common_path)
   local path = full_path
   if common_path then
	  local s,e = string.find(path, common_path)
	  if e then
		 path = string.sub(path,e+1)
	  end
   end
   local dirs = {}
   local s,e,pos,dirname
   pos = 1
   s,e,dirname = string.find(path,"([^%/]+)/")
   while e do
	  dirs[#dirs+1] = dirname
	  pos = e + 1
	  s,e,dirname = string.find(path,"([^%/]+)/",pos)
   end
   local filename = string.sub(path,pos)

   return dirs, filename
end

local function create_dirs(dirs, out_dir)
   local path = out_dir
   if next(dirs) then
	  -- Create all directories that need to be created
	  for i=1,#dirs do
		 local dir = dirs[i]
		 path = path.."/"..dir
		 local d = io.open(path)
		 if not d then
			local res, err = SPT.make_dir(path)
			if not res then
			   MSG.error_message(err)
			end
		 else
			d:close()
		 end
	  end
   end
end

local function open_file(dirs, filename, out_dir)
   local path = out_dir
   if next(dirs) then
	  for i=1,#dirs do
		 path = path.."/"..dirs[i]
	  end
   end
   path = path.."/"..filename
   local out_file = io.open(path,"w")
   if not out_file then
	  MSG.error_message("Failed to open "..path)
   end
   return out_file
end

local function write_misc_files(misc_files, common_path, out_dir, format)
   for _,node in pairs(misc_files) do
	  local out
	  local full_path = NODE.get_file_name(node)
	  if out_dir then
		 local dirs, filename = get_dirs_and_filename_from_full_path(full_path,
																	 common_path)
		 create_dirs(dirs, out_dir)
		 out = open_file(dirs, filename, out_dir)
	  else
		 io.stdout:write("# FILE: "..full_path.."\n")
		 out = io.stdout
	  end
	  write_misc_file(out, NODE.get_block_1(node), format)

	  if out_dir then
		 out:close()
	  end
   end
end
simpl_write.misc_files = write_misc_files

local function write_modules(modules, common_path, out_dir, format)
   for mod,modtab in pairs(modules) do
	  local out
	  local te_node = modtab["te"]
	  local if_node = modtab["if"]
	  local fc_node = modtab["fc"]
	  local full_path = NODE.get_file_name(te_node)
	  if out_dir then
		 local dirs, filename = get_dirs_and_filename_from_full_path(full_path,
																	 common_path)
		 create_dirs(dirs, out_dir)
		 out = open_file(dirs, mod, out_dir)
		 write_te_file(out, NODE.get_block_1(te_node), format)
		 write_if_file(out, NODE.get_block_1(if_node), format)
		 write_fc_file(out, NODE.get_block_1(fc_node), format)
		 out:close()
	  else
		 out = io.stdout
		 io.stdout:write("# FILE: "..tostring(NODE.get_file_name(te_node)).."\n")
		 write_te_file(out, NODE.get_block_1(te_node), format)
		 io.stdout:write("# FILE: "..tostring(NODE.get_file_name(if_node)).."\n")
		 write_if_file(out, NODE.get_block_1(if_node), format)
		 io.stdout:write("# FILE: "..tostring(NODE.get_file_name(fc_node)).."\n")
		 write_fc_file(out, NODE.get_block_1(fc_node), format)
	  end
   end
end
simpl_write.write_modules = write_modules

-------------------------------------------------------------------------------
local function add_order_helper(node, order_kind, order_flavor, filename, order)
   local cur = node
   local last
   while cur do
	  local kind = NODE.get_kind(cur)
	  if kind == order_kind then
		 local node_data = NODE.get_data(cur) or {}
		 local name = node_data[1]
		 order[#order+1] = name
		 last = cur
	  end
	  local block1 = NODE.get_block_1(cur)
	  local block2 = NODE.get_block_2(cur)
	  if block1 then
		 local last1 = add_order_helper(block1, order_kind, order_flavor, filename, order)
		 last = last1 or last
	  end
	  if block2 then
		 local last1 = add_order_helper(block2, order_kind, order_flavor, filename, order)
		 last = last1 or last
	  end
	  cur = NODE.get_next(cur)
   end
   return last
end

local function add_order(node, order_kind, order_flavor, filename)
   local order = {}
   local last = add_order_helper(node, order_kind, order_flavor, filename, order)
   if last then
	  local new = NODE.create("order", node, filename, NODE.get_line_number(last))
	  NODE.set_data(new, {order_flavor, order})
	  TREE.add_node(last, new)
   else
	  MSG.warning("Failed to add "..tostring(order_flavor)..
				  " order statement to file "..tostring(filename))
   end
end

local function add_orders_to_files(node, kind, do_action, do_block, data)
   local filename = NODE.get_file_name(node)
   if string.find(filename, "security_classes$") then
	  add_order(NODE.get_block_1(node), "class_decl", "class", filename)
   elseif string.find(filename, "initial_sids$") then
	  add_order(NODE.get_block_1(node), "sid_decl", "sid", filename)
   end
end

local function add_orders_to_policy(head)
   local action = {
	  ["file"] = add_orders_to_files,
   }
   TREE.walk_normal_tree(NODE.get_block_1(head), action, nil)
end

-------------------------------------------------------------------------------
local function mod_mls_helper(node, sens, cats, dominance, levels)

   -- must handle blocks

   local last_sen
   local last_cat
   local last_level
   local cur = node
   while cur do
	  local kind = NODE.get_kind(cur)
	  if kind == "sensitivity" then
		 local node_data = NODE.get_data(cur) or {}
		 local name = node_data[1]
		 sens[#sens+1] = name
		 last_sen = cur
	  elseif kind == "category" then
		 local node_data = NODE.get_data(cur) or {}
		 local name = node_data[1]
		 cats[#cats+1] = name
		 last_cat = cur
	  elseif kind == "dominance" then
		 local node_data = NODE.get_data(cur) or {}
		 dominance = node_data[1]
	  elseif kind == "level" then
		 local node_data = NODE.get_data(cur) or {}
		 local s = node_data[1]
		 local level = node_data[2]
		 levels[s] = level
		 last_level = cur
	  end
	  
	  local block1 = NODE.get_block_1(cur)
	  local block2 = NODE.get_block_2(cur)
	  if block1 then
		 local last1 = add_mls_helper(block1, mls_kind, mls_flavor, filename, mls)
		 last = last1 or last
	  end
	  if block2 then
		 local last1 = add_mls_helper(block2, mls_kind, mls_flavor, filename, mls)
		 last = last1 or last
	  end
	  cur = NODE.get_next(cur)
   end
   return last
end

local function mod_mls(node, mls_kind, mls_flavor, filename)
   local mls = {}
   local last = add_mls_helper(node, mls_kind, mls_flavor, filename, mls)
   if last then
	  local new = NODE.create("mls", node, filename, NODE.get_line_number(last))
	  NODE.set_data(new, {mls_flavor, mls})
	  TREE.add_node(last, new)
   else
	  MSG.warning("Failed to add "..tostring(mls_flavor)..
				  " mls statement to file "..tostring(filename))
   end
end

local function mod_mls_in_files(node, kind, do_action, do_block, data)
   local filename = NODE.get_file_name(node)
   if string.find(filename, "mcs$") then
	  add_mls(NODE.get_block_1(node), "category", "category", filename)
   elseif string.find(filename, "mls$") then
	  add_mls(NODE.get_block_1(node), "category", "category", filename)
   end
end

local function mod_mls_in_policy(misc_files)
   for _,node in pairs(misc_files) do
	  local filename = NODE.get_file_name(node)
	  if string.find(filename, "mls$") then
	  elseif string.find(filename, "mcs$") then
	  end
   end
end

-------------------------------------------------------------------------------

local function write_simpl(head, out_dir, verbose)
   MSG.verbose_out("\nWrite SIMPL from Refpolicy", verbose, 0)

   if out_dir then
	  f = io.open(out_dir,"r")
	  if f then
		 f:close()
		 SPT.remove_dir(out_dir)
	  end
	  local res, err = SPT.make_dir(out_dir)
	  if not res then
		 MSG.error_message(err)
	  end
   end

   -- Need to add order rules (class, sid, cat, ...)
   add_orders_to_policy(head)

   local file_action = {
	  ["file"] = sort_module_and_misc_files,
   }

   local modules = {}
   local misc_files = {}
   local file_data = {
	  ["modules"] = modules,
	  ["misc_files"] = misc_files,
	  ["mls_files"] = mls_files,
   }

   TREE.walk_normal_tree(NODE.get_block_1(head), file_action, file_data)
   TREE.disable_active(head)
   TREE.enable_inactive(head)
   TREE.walk_normal_tree(NODE.get_block_2(head), file_action, file_data)
   TREE.disable_inactive(head)
   TREE.enable_active(head)

   local common_path = find_common_path(head)
   local format = STRING.get_new_format(4, 80)

   write_misc_files(misc_files, common_path, out_dir, format)
   write_modules(modules, common_path, out_dir, format)
end
simpl_write.write_simpl = write_simpl

-------------------------------------------------------------------------------
return simpl_write
