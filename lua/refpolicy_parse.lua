local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"
local IFDEF = require "node_ifdef"
local TREE = require "tree"
local LEX = require "common_lex"
local MLS = require "refpolicy_mls"

local refpolicy_parse = {}

-------------------------------------------------------------------------------
local string_find = string.find
local tree_add_node = TREE.add_node
local node_create = NODE.create
local node_next = NODE.get_next
local node_set_kind = NODE.set_kind
local node_set_data = NODE.set_data
local lex_get = LEX.get
local lex_get_full = LEX.get_full
local lex_peek = LEX.peek
local lex_next = LEX.next
local lex_prev = LEX.prev
local lex_SOF = LEX.SOF
local lex_EOF = LEX.EOF
local lex_END = LEX.END

-------------------------------------------------------------------------------
local UNKNOWN_FLAVOR = "_UNKNOWN_"
local TMP_FLAVOR = "_TMP_FLAVOR_"

local set_ops = {
   ["*"] = "all",
   ["~"] = "not",
   ["-"] = "neg",
}

local cond_ops = {
   ["!"]  = "not",
   ["^"]  = "xor",
   ["&&"] = "and",
   ["||"] = "or",
   ["=="] = "eq",
   ["!="] = "neq",
}

local function warning_message(state, msg, level)
   if state.verbose >= level then
      local file = LEX.filename(state.lex)
      local lineno = LEX.lineno(state.lex)
      local node = node_create(false, false, file, lineno)
      TREE.warning(msg, node)
   end
end

local function error_message(state, msg)
   local file = LEX.filename(state.lex)
   local lineno = LEX.lineno(state.lex)
   local node = node_create(false, false, file, lineno)
   TREE.error_message(msg, node)
end

local function copy_data(old)
   if type(old) ~= "table" then
      return old
   else
      local new = {}
      for i,v in pairs(old) do
	 if type(v) ~= "table" then
	    new[i] = v
	 else
	    new[i] = copy_data(v)
	 end
      end
      return new
   end
end

local function move_flavor(tab, old, new)
   if tab and tab[old] then
      tab[new] = tab[new] or {}
      for v,_ in pairs(tab[old]) do
	 tab[new][v] = true
      end
      tab[old] = nil
   end
end

local function delete_flavor(tab, flavor)
   if tab and tab[flavor] then
      tab[flavor] = nil
   end
end

local function add_to_used(state, value, flavor)
   if state.used and flavor then
      state.used[flavor] = state.used[flavor] or {}
      state.used[flavor][value] = true
   end
end

local function get_optional(state, expected)
    local token = lex_peek(state.lex)
    if token == expected then
        lex_get(state.lex)
    end

    return token == expected
end

local function get_expected(state, expected)
   local token = lex_get(state.lex)
   if token ~= expected then
      error_message(state, "Expected \""..tostring(expected).."\" but got \""..
		 tostring(token).."\"")
   end
end

local function get_identifier(state, flavor)
   local token = lex_get(state.lex)
   if state.used and flavor then
      state.used[flavor] = state.used[flavor] or {}
      state.used[flavor][token] = true
   end
   return token
end

local function get_declaration(state, flavor)
   local token = lex_get(state.lex)
   if flavor then
      if state.used then
	 state.used[flavor] = state.used[flavor] or {}
	 state.used[flavor][token] = true
      end
      if state.decls then
	 state.decls[flavor] = state.decls[flavor] or {}
	 state.decls[flavor][token] = true
      end
   end
   return token
end

local function get_quoted_string(state)
   local str = ""
   get_expected(state, "\"")
   if lex_peek(state.lex) ~= "\"" then
      str = get_identifier(state, "string")
   end
   get_expected(state, "\"")
   return str
end

local function get_comma_separated_list(state, flavor)
   local list = {}
   while lex_peek(state.lex) ~= ";" do
      local token = get_identifier(state, flavor)
      if not token or token == "," then
	 error_message(state, "Improper comma list")
      end
      list[#list+1] = token
      if lex_peek(state.lex) ~= ";" then
	 get_expected(state, ",")
      end
   end
   return list
end

local function get_expression(state, flavor, ops, left, right)
   local exp = {}
   get_expected(state, left)
   local token = lex_peek(state.lex)
   while token ~= right and token ~= lex_EOF do
      if token == left then
	 exp[#exp+1] = get_expression(state, flavor, ops, left, right)
      elseif ops and ops[token] then
	 exp[#exp+1] = lex_get(state.lex)
      else
	 exp[#exp+1] = get_identifier(state, flavor)
      end
      token = lex_peek(state.lex)
   end
   get_expected(state, right)
   return exp
end

local function get_conditional_expr(state, flavor)
   return get_expression(state, flavor, cond_ops, "(", ")")
end

local function get_m4_conditional_expr(state, flavor)
   return get_expression(state, flavor, cond_ops, "`", "'")
end

local function get_list(state, flavor, left, right)
   return get_expression(state, flavor, nil, left, right)
end

local function get_identifier_or_list(state, flavor, left, right)
   if lex_peek(state.lex) ~= left then
      return get_identifier(state, flavor)
   end
   return get_expression(state, flavor, nil, left, right)
end

local function get_declaration_or_list(state, flavor, left, right)
   if lex_peek(state.lex) ~= left then
      return get_declaration(state, flavor)
   end
   local list = get_expression(state, flavor, nil, left, right)
   if flavor and state.decls then
      state.decls[flavor] = state.decls[flavor] or {}
      for _,v in pairs(list) do
	 state.decls[flavor][v] = true
      end
   end
   return list
end

local function get_identifier_or_set(state, flavor)
   local set
   local token = lex_peek(state.lex)
   if token == "*" then
      lex_get(state.lex)
      set =  {"*"}
   elseif token == "~" then
      lex_get(state.lex)
      set = get_identifier_or_set(state, flavor)
      set = {"~", set}
   elseif token == "{" then
      set = get_expression(state, flavor, set_ops, "{", "}")
   else
      set = get_identifier(state, flavor)
   end
   return set
end

local function get_set(state, flavor)
   local set = get_identifier_or_set(state, flavor)
   if type(set) ~= "table" then
      set = {set}
   end
   return set
end

local function get_class(state)
   return get_identifier_or_set(state, "class")
end

local function get_perms(state)
   return get_identifier_or_set(state, "perm")
end

local function get_def_perms(state)
   local perms = {}
   get_expected(state,"{")
   local token = lex_peek(state.lex)
   while token ~= "}" and token ~= lex_EOF do
      perms[#perms+1] = get_identifier(state, "perm")
      token = lex_peek(state.lex)
   end
   get_expected(state, "}")
   return perms
end

local function get_xperms(state)
   local xperms = get_identifier_or_list(state, "xperm", "{", "}")
   if type(xperms) ~= "table" then
      xperms = {xperms}
   end
   return xperms
end

local function get_mls_categories_from_string(state, str)
   local cats = {}
   local s,e,cat = string.find(str, "^([%w%$][_%-%.%w%$]*)")
   while s do
      s = e + 1
      add_to_used(state, cat, "category")
      local token = string.sub(str,s,s)
      if token == "," then
	 s = s + 1
	 cats[#cats+1] = cat
      elseif c == "." then
	 local cat_rng = {}
	 cat_rng[1] = cat
	 s,e,cat = string.find(str, "^([%w%$][_%-%.%w%$]*)",s)
	 if not s then
	    error_message(state, "Improperly formed category range")
	 end
	 cat_rng[2] = cat
	 add_to_used(state, cat, "category")
	 cats[#cats+1] = cat_rng
	 s = e + 1
      end
      s,e,cat = string.find(str, "^([%w%$][_%-%.%w%$]*)",s)
   end
   return cats
end

local function get_mls_level_from_string(state, str)
   if not string.find(str,":") then
      -- simple level
      if str == "mls_systemhigh" or str == "mls_systemlow" or
	 str == "mcs_systemhigh" or str == "mcs_systemlow" or
         str == "systemhigh" or str == "systemlow" then
	    add_to_used(state, str, "level")
	 return str
      end
      return {str}
   end
   local level = {}
   local sens, cat_str = string.match(str,"^(.*):(.*)")
   level[1] = sens
   add_to_used(state, sens, "sensitivity")
   level[2] = get_mls_categories_from_string(state, cat_str)
   return level
end

local function add_cats_to_level_string(state, level)
   if lex_peek(state.lex) == ":" then
      lex_next(state.lex)
      return level..":"..lex_get(state.lex)
   end
   return level
end

local function get_mls_level(state)
   local level_str = lex_get(state.lex)
   level_str = add_cats_to_level_string(state, level_str)
   return get_mls_level_from_string(state, level_str)
end

local function get_mls_range(state)
   local range = {}
   local low = lex_get(state.lex)
   local high
   low = add_cats_to_level_string(state, low)
   if lex_peek(state.lex) == "-" then
      lex_next(state.lex)
      range[1] = get_mls_level_from_string(state, low)
      high = lex_get(state.lex)
      high = add_cats_to_level_string(state, high)
      range[2] = get_mls_level_from_string(state, high)
   elseif string.find(low, "%-") then
      local s,e,l = string.find(low,"^([^%-]+)")
      if not e then
	 error_message(state, "Invalid MLS range")
      end
      range[1] = get_mls_level_from_string(state, l)
      high = string.sub(low,e+2)
      high = add_cats_to_level_string(state, high)
      range[2] = get_mls_level_from_string(state, high)
   elseif not string.find(low, "%$") then
      range[1] = get_mls_level_from_string(state, low)
   else
      -- parameter
      range[1] = low
      add_to_used(state, low, "range")
   end
   return range
end

local function get_context(state)
   local context = {}
   if lex_peek(state.lex) == "<<" then
      get_expected(state, "<<")
      get_expected(state, "none")
      get_expected(state, ">>")
      context[#context+1] = "<<none>>"
   elseif lex_peek(state.lex) ~= "gen_context" then
      context[#context+1] = get_identifier(state, "user")
      get_expected(state, ":")
      context[#context+1] = get_identifier(state, "role")
      get_expected(state, ":")
      context[#context+1] = get_identifier(state, "type")
      if lex_peek(state.lex) == ":" then
	 lex_next(state.lex)
	 context[#context+1] = get_mls_range(state)
      end
   else
      get_expected(state, "gen_context")
      get_expected(state, "(")
      context[#context+1] = get_identifier(state, "user")
      get_expected(state, ":")
      context[#context+1] = get_identifier(state, "role")
      get_expected(state, ":")
      context[#context+1] = get_identifier(state, "type")
      if lex_peek(state.lex) == "," then
	 lex_next(state.lex)
	 context[#context+1] = get_mls_range(state)
	 if lex_peek(state.lex) == "," then
	    warning_message(state, "Found MCS Categories for gen_context()", 3)
	    lex_next(state.lex)
	    context[#context+1] = get_mls_categories_from_string(state,
								 lex_get(state.lex))
	 end
      end
      get_expected(state, ")")
   end
   return context
end

local function get_boolean(state)
   local bool = get_identifier(state, "string")
   bool = string.lower(bool)
   if bool ~= "true" and bool ~= "false" then
      error_message(state, "Expected either \"true\" or \"false\" for boolean value,"..
		       " but got \""..tostring(bool).."\"")
   end
   return bool
end

local function get_ports(state)
   local ports = {}
   ports[1] = get_identifier(state, "string")
   if lex_peek(state.lex) == "-" then
      lex_next(state)
      ports[2] = get_identifier(state, "string")
   end
   return ports
end

local function get_ip_address(state)
   local ip = {}
   local n = lex_peek(state.lex)
   while n == ":" or string.find(n,"%X") == nil do
      ip[#ip+1] = n
      lex_next(state)
      n = lex_peek(state.lex)
   end
   return table.concat(ip)
end

local function check_cstr_leaf_expr(state, ls, rs, op, mls, valtrans)
   local valid_ls = {u1="user", r1="role", t1="type",
		     u2="user", r2="role", t2="type"}
   local valid_ls_mls = {l1=true, h1=true, l2=true,}
   local valid_ls_valtrans = {u3=true, r3=true, t3=true,}
   local valid_op = {["=="]=true, ["!="]=true, ["eq"]=true, ["neq"]=true,}
   local valid_role_op = {["=="]=true, ["!="]=true, ["eq"]=true, ["neq"]=true,
			  ["dom"]=true, ["domby"]=true, ["incomp"]=true,}
   local valid_mls_op = valid_role_op
   if not valid_ls[ls] and (not mls or not valid_ls_mls[ls]) and
      (not valtrans or not valid_ls_valtrans[ls]) then
	 error_message(state, "Invalid left side ("..tostring(ls)..")"..
		       " for constraint expression")
   end
   if ls == "r1" and rs == "r2" then
      if not valid_role_op[op] then
	 error_message(state, "Invalid role operator ("..tostring(op)..")"..
		       " for constraint expression")
      end
   elseif mls and valid_ls_mls[ls] then
      if not valid_mls_op[op] then
	 error_message(state, "Invalid mls operator ("..tostring(op)..")"..
		       " for constraint expression")
      end
   else
      if not valid_op[op] then
	 error_message(state, "Invalid operator ("..tostring(op)..")"..
		       " for constraint expression")
      end
   end
   if rs == "u2" and ls ~= "u1" then
      error_message(state, "u2 on the right side must be matched with u1"..
		       " on the left side of the constraint")
   end
   if rs == "r2" and ls ~= "r1" then
      error_message(state, "r2 on the right side must be matched with r1"..
		       " on the left side of the constraint")
   end
   if rs == "t2" and ls ~= "t1" then
      error_message(state, "t2 on the right side must be matched with t1"..
		       " on the left side of the constraint")
   end
   if mls then
      if rs == "l2" and ls ~= "l1" and ls ~= "h1" then
	 error_message(state, "l2 on the right side must be matched with l1 or h1"..
			  " on the left side of the constraint")
      end
      if rs == "h2" and ls ~= "l1" and ls ~= "h1" and ls ~= "l2" then
	 error_message(state, "h2 on the right side must be matched with l1, h1, or l2"..
			  " on the left side of the constraint")
      end
      if rs == "h1" and ls ~= "l1" then
	 error_message(state, "h1 on the right side must be matched with l1"..
			  " on the left side of the constraint")
      end
   end
end

local function get_cstr_leaf_expr(state, mls, mlstrans)
   local flavors = {u1="user", r1="role", t1="type",
		    u2="user", r2="role", t2="type",
		    u3="user", r3="role", t3="type",
		    l1="level", l2="level", h1="level"}
   local ls = get_identifier(state, nil)
   local op = get_identifier(state, nil)
   local rs = lex_peek(state.lex)
   check_cstr_leaf_expr(state, ls, rs, op, mls, mlstrans)
   if rs == "u2" or rs == "r2" or rs == "t2" then
      lex_next(state.lex)
   elseif mls and (rs == "l2" or rs == "h2" or rs == "h1") then
      lex_next(state.lex)
   else
      if flavors[ls] then
	 rs = get_identifier_or_list(state, flavors[ls])
      else
	 error_message(state, "Unexpected value \""..tostring(ls)..
			  "\" on left side of constraint")
      end
   end
   return {ls, op, rs}
end

function get_constraint_expr(state, mls, mlstrans)
   local cstr = {}
   local token, expr, op
   repeat
      if op then
	 lex_next(state.lex)
	 cstr[#cstr+1] = op
      end
      token = lex_peek(state.lex)
      if token == "basic_ubac_conditions" then
	 lex_next(state.lex)
	 expr = token
      elseif token == "not" then
	 lex_next(state.lex)
	 expr = get_cstr_expr(state, mls, mlstrans)
	 expr =  {"not", expr}
      elseif token == "(" then
	 lex_next(state.lex)
	 expr = get_constraint_expr(state, mls, mlstrans)
	 get_expected(state, ")")
      else
	 expr = get_cstr_leaf_expr(state, mls, mlstrans)
      end
      cstr[#cstr+1] = expr
      op = lex_peek(state.lex)
   until op ~= "and" and op ~= "or"
   if #cstr == 1 and type(cstr[1]) == "table" then
      cstr =  cstr[1]
   end
   return cstr
end

--------------------------------------------------------------------------------
local function parse_policycap_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local capability = get_identifier(state, "string")
   node_set_data(node, {capability})
   get_expected(state, ";")
   return node
end

local function parse_bool_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local bool = get_declaration(state, "bool")
   local bool_val = get_boolean(state)
   node_set_data(node, {bool, bool_val})
   return node
end

local function parse_gen_bool_rule(state, kind, cur, node)
   node_set_kind(node, "bool")
   tree_add_node(cur, node)
   get_expected(state, "(")
   local bool = get_declaration(state, "bool")
   get_expected(state, ",")
   local bool_val = get_boolean(state)
   get_expected(state, ")")
   node_set_data(node, {bool, bool_val})
   return node
end

local function parse_tunable_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local tunable = get_declaration(state, "tunable")
   local bool_val = get_boolean(state)
   node_set_data(node, {tunable, bool_val})
   return node
end

local function parse_gen_tunable_rule(state, kind, cur, node)
   node_set_kind(node, "tunable")
   tree_add_node(cur, node)
   get_expected(state, "(")
   local token = lex_peek(state.lex)
   local quoted = token == "`" or token == "\""
   if quoted then
      if state.verbose > 2 then
	 -- Quoting is not required or desired, but works with m4
	 warning_message(state, "Quoting the tunable name is not required", 3)
      end
      lex_next(state.lex)
   end
   local tunable = get_declaration(state, "tunable")
   if quoted then
      if token == "`" then
	 get_expected(state, "'")
      elseif token == "\"" then
	 get_expected(state, "\"")
      end
   end
   get_optional(state, "'")
   get_expected(state, ",")
   local bool_val = get_boolean(state)
   get_expected(state, ")")
   node_set_data(node, {tunable, bool_val})
   return node
end

local function parse_sid_rule(state, kind, cur, node)
   -- Either sid or initial sid
   tree_add_node(cur, node)
   lex_next(state.lex)
   local token = lex_peek(state.lex)
   lex_prev(state.lex)
   if token == lex_EOF or state.rules[token] or
   state.blocks[token] then
      node_set_kind(node, "sid_decl")
      local sid = get_declaration(state, "sid")
      node_set_data(node, {sid})
   else -- initial sid
      local sid = get_identifier(state, "sid")
      local context = get_context(state)
      node_set_data(node, {sid, context})
   end
   return node
end

local function parse_class_rule(state, kind, cur, node)
   -- Either class declaration or class instantiation
   tree_add_node(cur, node)
   lex_next(state.lex)
   local token = lex_peek(state.lex)
   lex_prev(state.lex)
   if token == lex_EOF or state.rules[token] or
   state.blocks[token] then
      node_set_kind(node, "class_decl")
      local class = get_declaration(state, "class")
      node_set_data(node, {class})
   else -- class instantiation
      local class = get_identifier(state, "class")
      local common, perms
      if lex_peek(state.lex) == "inherits" then
	 lex_next(state.lex)
	 common = get_identifier(state, "common")
      end
      if lex_peek(state.lex) == "{" then
	 perms = get_def_perms(state)
      end
      node_set_data(node, {class, common, perms})
   end
   return node
end

local function parse_common_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local common = get_declaration(state, "common")
   local perms = get_def_perms(state)
   node_set_data(node, {common, perms})
   return node
end

local function parse_default_rule(state, kind, cur, node)
   -- default_user, default_role, default_type
   tree_add_node(cur, node)
   local class = get_class(state)
   local default = get_identifier(state, "string")
   if default ~= "source" and default ~= "target" then
      error_message(state, "Expected either \"source\" or \"target\" for default rule,"..
		       " but got \""..tostring(default).."\"")
   end
   get_expected(state, ";")
   node_set_data(node, {class, default})
   return node
end

local function parse_default_range_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local class = get_class(state)
   local default = get_identifier(state, "string")
   if default ~= "source" and default ~= "target" then
      error_message(state, "Expected either \"source\" or \"target\" for default rule,"..
		       " but got \""..tostring(default).."\"")
   end
   local range = get_identifier(state, "string")
   if range ~= "low" and range ~= "high" and range ~= "low_high" then
      error_message(state, "Expected \"low\", \"high\", or \"low_high\" for default"..
		       " range rule, but got \""..tostring(range).."\"")
   end
   get_expected(state, ";")
   node_set_data(node, {class, default, range})
   return node
end

local function get_gen_user_role_list(state)
   local roles = {}
   local mls_roles
   local token = lex_peek(state.lex)
   while token ~= "," and token ~= lex_EOF do
      if token == "ifdef" then
	 lex_next(state.lex)
	 get_expected(state, "(")
	 get_expected(state, "`")
	 get_expected(state, "enable_mls")
	 get_expected(state, "'")
	 get_expected(state, ",")
	 get_expected(state, "`")
	 mls_roles = {}
	 while token ~= "'" and token ~= lex_EOF do
	    mls_roles[#mls_roles+1] = get_identifier(state, "role")
	    token = lex_peek(state.lex)
	 end
	 lex_next(state.lex)
	 get_expected(state, ")")
      else
	 roles[#roles+1] = get_identifier(state, flavor)
      end
      token = lex_peek(state.lex)
   end
   get_expected(state, ",")
   if mls_roles then
      for i=1,#roles do
	 mls_roles[#mls_roles+1] = roles[i]
      end
      if #mls_roles == 1 then
	 mls_roles = mls_roles[1]
      end
   end
   if #roles == 1 then
      roles = roles[1]
   end
   return roles, mls_roles
end

local function parse_user_rule(state, kind, cur, node)
   node_set_kind(node, "user")
   tree_add_node(cur, node)
   local user = get_declaration(state, "user")
   get_expected(state, "roles")
   local roles = get_identifier_or_list(state, "role", "{", "}")
   local mls_level, mls_range = false, false
   if lex_peek(state.lex) == "level" then
      lex_next(state.lex)
      mls_level = get_mls_level(state)
   end
   if lex_peek(state.lex) == "range" then
      lex_next(state.lex)
      mls_range = get_mls_range(state)
   end
   node_set_data(node, {user, roles, mls_level, mls_range})
   return node
end

local function parse_gen_user_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   get_expected(state, "(")
   local user = get_declaration(state, "user")
   get_expected(state, ",")
   if lex_peek(state.lex) ~= "," then
      lex_next(state.lex) -- prefix
   end
   get_expected(state, ",")
   local roles, mls_roles = get_gen_user_role_list(state)
   local mls_level = get_mls_level(state)
   get_expected(state, ",")
   local mls_range = get_mls_range(state)
   local mcs_cats = false
   if lex_peek(state.lex) ~= ")" then
      -- Found MCS Categories
      get_expected(state, ",")
      warning_message(state, "Found MCS Categories for gen_user()", 3)
      local v = tostring(lex_peek(state.lex))
      if lex_peek(state.lex) == "mcs_allcats" then
	 mcs_cats = "mcs_allcats"
	 lex_next(state.lex)
      else
	 mcs_cats = get_mls_categories_from_string(state, lex_get(state.lex))
      end
   end
   get_expected(state, ")")
   if mls_level and mls_range then
      if not mls_roles then
	 mls_roles = roles
      end
      local file = NODE.get_file_name(node)
      local lineno = NODE.get_line_number(node)
      node_set_kind(node, "ifdef")
      IFDEF.set_conditional(node, {"enable_mls"})
      local new_user = node_create("user", node, file, lineno)
      node_set_data(new_user, {user, mls_roles, mls_level, mls_range})
      NODE.set_then_block(node, new_user)
      if mcs_cats then
	 local maxcatnum = state.cdefs["mcs_num_cats"] - 1
	 local mcs_range = {{"s0"},{"s0",{{"c0","c"..maxcatnum}}}}
	 local mcs_level = "s0"
	 local new_ifdef = node_create("ifdef", node, file, lineno)
	 IFDEF.set_conditional(new_ifdef, {"enable_mcs"})
	 NODE.set_else_block(node, new_ifdef)
	 new_user = node_create("user", new_ifdef, file, lineno)
	 node_set_data(new_user, {user, roles, mcs_level, mcs_range})
	 NODE.set_then_block(new_ifdef, new_user)
	 new_user = node_create("user", new_ifdef, file, lineno)
	 node_set_data(new_user, {user, roles, false, false})
	 NODE.set_else_block(new_ifdef, new_user)
      else
	 new_user = node_create("user", node, file, lineno)
	 node_set_data(new_user, {user, roles, false, false})
	 NODE.set_else_block(node, new_user)
      end
   else
      node_set_kind(node, "user")
      node_set_data(node, {user, roles, false, false})
   end
   return node
end

local function parse_role_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local role = get_declaration(state, "role")
   local types
   if lex_peek(state.lex) == "types" then
      lex_next(state.lex)
      types = get_identifier_or_set(state, "type")
   end
   get_expected(state, ";")
   node_set_data(node, {role, types})
   return node
end

local function parse_type_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local type_ = get_declaration(state, "type")
   local aliases, attributes
   if lex_peek(state.lex) == "alias" then
      lex_next(state.lex)
      aliases = get_declaration_or_list(state, "type", "{", "}")
   end
   if lex_peek(state.lex) == "," then
      lex_next(state.lex)
      attributes = get_comma_separated_list(state, "type")
   end
   get_expected(state, ";")
   node_set_data(node, {type_, aliases, attributes})
   return node
end

local function parse_typealias_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local type_ = get_identifier(state, "type")
   get_expected(state, "alias")
   local aliases = get_declaration_or_list(state, "type", "{", "}")
   get_expected(state, ";")
   node_set_data(node, {type_, aliases})
   return node
end

local function parse_typebounds_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local parent = get_identifier(state, "type")
   local child = get_identifier(state, "type")
   get_expected(state, ";")
   node_set_data(node, {parent, child})
   return node
end

local function parse_permissive_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local type_ = get_identifier(state, "type")
   get_expected(state, ";")
   node_set_data(node, {type_})
   return node
end

local function parse_attribute_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local attribute = get_declaration(state, "type")
   get_expected(state, ";")
   node_set_data(node, {attribute})
   return node
end

local function parse_typeattribute_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local type_ = get_identifier(state, "type")
   local attributes = get_comma_separated_list(state, "type")
   get_expected(state, ";")
   node_set_data(node, {type_, attributes})
   return node
end

local function parse_attribute_role_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local attribute = get_declaration(state, "role")
   get_expected(state, ";")
   node_set_data(node, {attribute})
   return node
end

local function parse_roleattribute_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local role = get_identifier(state, "role")
   local attributes = get_comma_separated_list(state, "role")
   get_expected(state, ";")
   node_set_data(node, {role, attributes})
   return node
end

local function parse_sensitivity_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local sensitivity = get_declaration(state, "sensitivity")
   local aliases
   if lex_peek(state.lex) == "alias" then
      lex_next(state.lex)
      aliases = get_declaration_or_list(state, "sensitivity", "{", "}")
   end
   get_expected(state, ";")
   node_set_data(node, {sensitivity, aliases})
   return node
end

local function parse_dominance_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local sensitivies = get_list(state, "sensitivity", "{", "}")
   node_set_data(node, {sensitivities})
   return node
end

local function parse_category_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local category = get_declaration(state, "category")
   local aliases
   if lex_peek(state.lex) == "alias" then
      lex_next(state.lex)
      aliases = get_declaration_or_list(state, "category", "{", "}")
   end
   get_expected(state, ";")
   node_set_data(node, {category, aliases})
   return node
end

local function parse_level_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local level = get_mls_level(state)
   get_expected(state, ";")
   node_set_data(node, {level})
   return node
end

local function get_sens_or_cat_number(state)
   local tok = lex_get(state.lex)
   local num
   if state.cdefs[tok] then
      num = state.cdefs[tok]
   else
      num = tonumber(tok)
   end
   if not num then
      error_message(state, "Expected a number but got"..tostring(tok))
   end
   return num
end

local function parse_gen_sens_rule(state, kind, cur, node)
   get_expected(state, "(")
   local sens = get_sens_or_cat_number(state)
   get_expected(state, ")")
   local parent = NODE.get_parent(node)
   local file = NODE.get_file_name(node)
   local lineno = NODE.get_line_number(node)
   local first, last = MLS.create_sens(sens, parent, file, lineno)
   tree_add_node(cur, first)
   cur = last
   first = MLS.create_dominance(sens, parent, file, lineno)
   cur = tree_add_node(cur, first)
   return cur
end

local function parse_gen_cats_rule(state, kind, cur, node)
   get_expected(state, "(")
   local cats = get_sens_or_cat_number(state)
   get_expected(state, ")")
   local parent = NODE.get_parent(node)
   local file = NODE.get_file_name(node)
   local lineno = NODE.get_line_number(node)
   local first, last = MLS.create_cats(cats, parent, file, lineno)
   tree_add_node(cur, first)
   return last
end

local function parse_gen_levels_rule(state, kind, cur, node)
   get_expected(state, "(")
   local sens = get_sens_or_cat_number(state)
   get_expected(state, ",")
   local cats = get_sens_or_cat_number(state)
   get_expected(state, ")")
   local parent = NODE.get_parent(node)
   local file = NODE.get_file_name(node)
   local lineno = NODE.get_line_number(node)
   local first, last = MLS.create_levels(sens, cats, parent, file, lineno)
   tree_add_node(cur, first)
   return last
end

local function parse_allow_rule(state, kind, cur, node)
   -- Either type allow or role allow
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, TMP_FLAVOR)
   local tgt = get_identifier_or_set(state, TMP_FLAVOR)
   if lex_peek(state.lex) == ":" then
      -- type allow
      lex_next(state.lex)
      move_flavor(state.used, TMP_FLAVOR, "type")
      local class = get_class(state)
      local perms = get_perms(state)
      node_set_data(node, {src, tgt, class, perms})
   else
      node_set_kind(node, "role_allow")
      move_flavor(state.used, TMP_FLAVOR, "role")
      node_set_data(node, {src, tgt})
   end
   get_expected(state, ";")
   return node
end

local function parse_xperm_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, "type")
   local tgt = get_identifier_or_set(state, "type")
   get_expected(state, ":")
   local class = get_class(state)
   get_expected(state, "ioctl")
   local xperms = get_xperms(state)
   get_expected(state, ";")
   node_set_data(node, {src, tgt, class, "ioctl", xperms})
   return node
end

local function parse_av_rule(state, kind, cur, node)
   -- dontaudit, auditallow, neverallow
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, "type")
   local tgt = get_identifier_or_set(state, "type")
   get_expected(state, ":")
   local class = get_class(state)
   local perms = get_perms(state)
   get_expected(state, ";")
   node_set_data(node, {src, tgt, class, perms})
   return node
end

local function parse_type_transition_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, "type")
   local tgt = get_identifier_or_set(state, "type")
   get_expected(state, ":")
   local class = get_class(state)
   local new = get_identifier(state, "type")
   local file = "*"
   if lex_peek(state.lex) ~= ";" then
      if lex_peek(state.lex) == "\"" then
	 file = get_quoted_string(state)
      else
	 file = get_identifier(state, "string")
      end
   end
   node_set_data(node, {src, tgt, class, new, file})
   get_expected(state, ";")
   return node
end

local function parse_type_change_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, "type")
   local tgt = get_identifier_or_set(state, "type")
   get_expected(state, ":")
   local class = get_class(state)
   local new = get_identifier_or_set(state, "type")
   node_set_data(node, {src, tgt, class, new})
   get_expected(state, ";")
   return node
end

local function parse_type_member_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, "type")
   local tgt = get_identifier_or_set(state, "type")
   get_expected(state, ":")
   local class = get_class(state)
   local new = get_identifier_or_set(state, "type")
   node_set_data(node, {src, tgt, class, new})
   get_expected(state, ";")
   return node
end

local function parse_range_transition_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, "type")
   local tgt = get_identifier_or_set(state, "type")
   get_expected(state, ":")
   local class = get_class(state)
   local range = get_mls_range(state)
   node_set_data(node, {src, tgt, class, range})
   get_expected(state, ";")
   return node
end

local function parse_role_transition_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local src = get_identifier_or_set(state, "role")
   local tgt = get_identifier_or_set(state, "type")
   local new = get_identifier(state, "role")
   node_set_data(node, {src, tgt, new})
   get_expected(state, ";")
   return node
end

local function parse_constrain_rule(state, kind, cur, node)
   -- constrain or mlsconstrain
   local mls = (kind == "mlsconstrain")
   tree_add_node(cur, node)
   local class = get_class(state)
   local perms = get_perms(state)
   local cexpr = get_constraint_expr(state, mls, false)
   node_set_data(node, {class, perms, cexpr})
   get_expected(state, ";")
   return node
end

local function parse_validatetrans_rule(state, kind, cur, node)
   -- validatetrans or mlsvalidatetrans
   local mls = (kind == "mlsvalidatetrans")
   tree_add_node(cur, node)
   local class = get_class(state)
   local cexpr = get_constraint_expr(state, mls, true)
   node_set_data(node, {class, cexpr})
   get_expected(state, ";")
   return node
end


local function parse_filecon_rule(state, kind, cur, node)
   local valid_file_types = {["-b"]=true, ["-c"]=true, ["-d"]=true, ["-p"]=true,
      ["-l"]=true, ["-s"]=true, ["--"]=true}
   node_set_kind(node, "filecon")
   tree_add_node(cur, node)
   local path = kind
   if string.find(lex_peek(state.lex),"/") then
      if (path == "HOME_ROOT" or path == "HOME_DIR") then
	 local rel_path = lex_get(state.lex)
	 path = kind..rel_path
      elseif path == "/" then
	 -- This occurs in kernel/devices.fc
	 warning_message(state, "Stray \"/\"", 0)
	 path = lex_get(state.lex)
      end
   end
   add_to_used(state, path, "string")
   local file_type = ""
   local token = lex_peek(state.lex)
   if token == "-" then
      lex_next(state.lex)
      file_type = "-"..get_identifier(state, "string")
      if not valid_file_types[file_type] then
	 error_message(state, "Invalid file type ("..tostring(file_type)..")"..
		       " for filecon rule")
      end
   end
   local context = get_context(state)
   node_set_data(node, {path, file_type, context})
   return node
end

local function parse_fs_use_rule(state, kind, cur, node)
   -- fs_use_xattr, fs_use_task, fs_use_trans
   tree_add_node(cur, node)
   local fs_name = get_identifier(state, "string")
   local context = get_context(state)
   node_set_data(node, {fs_name, context})
   get_expected(state, ";")
   return node
end

local function parse_genfscon_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local fs_name = get_identifier(state, "string")
   local path = get_identifier(state, "string")
   local context = get_context(state)
   node_set_data(node, {fs_name, path, context})
   return node
end

local function parse_netifcon_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local interface = get_identifier(state, "string")
   local if_context = get_context(state)
   local packet_context = get_context(state)
   node_set_data(node, {interface, if_context, packet_context})
   return node
end

local function parse_nodecon_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local subnet = get_ip_address(state)
   local netmask = get_ip_address(state)
   local context = get_context(state)
   node_set_data(node, {subnet, netmask, context})
   return node
end

local function parse_portcon_rule(state, kind, cur, node)
   tree_add_node(cur, node)
   local protocol = get_identifier(state, "string")
   if protocol ~= "udp" and protocol ~= "tcp" and protocol ~= "dccp" and
   protocol ~= "sctp" then
      error_message(state, "Expected either \"udp\", \"tcp\", \"dccp\", or "..
		    "\"sctp\" for the portcon "..
		       "protocol, but got \""..tostring(protocol).."\"")
   end
   local ports = get_ports(state)
   local context = get_context(state)
   node_set_data(node, {protocol, ports, context})
   return node
end

-----------------------------------------------------------------------------
local function get_call_args_expr(state)
   local exp = {}
   local token = lex_peek(state.lex)
   while token ~= "," and token ~= ")" and token ~= lex_EOF do
      if token == "{" then
	 exp[#exp+1] = get_expression(state, nil, set_ops, "{", "}")
      elseif set_ops[token] then
	 exp[#exp+1] = lex_get(state.lex)
      else
	 exp[#exp+1] = get_identifier(state, nil)
      end
      token = lex_peek(state.lex)
   end
   return exp
end

local function parse_macro_call(state, name, cur, node)
   node_set_kind(node, "call")
   tree_add_node(cur, node)
   local call_args = {}
   get_expected(state, "(")
   if lex_peek(state.lex) == "$*" then
      -- This means "pass all arguments through"
      warning_message(state, "Found argument pass-through in call "..name, 3)
      call_args[1] = lex_get(state.lex)
   else
      local token = lex_peek(state.lex)
      while token ~= ")" do
	 if token == "{" or token == "*" then
	    call_args[#call_args+1] = get_set(state, nil)
	 else
	    local call_arg = lex_get(state.lex)
	    local next_arg = lex_peek(state.lex)
	    if call_arg == "\"" then
	       lex_prev(state.lex)
	       call_args[#call_args+1] = get_quoted_string(state)
	    elseif next_arg == "-" then
	       -- probably mls range
	       lex_prev(state.lex)
	       call_args[#call_args+1] = get_mls_range(state)
	    elseif call_arg == "-" then
	       lex_prev(state.lex)
	       call_args[#call_args+1] = get_call_args_expr(state)
	    else
	       call_args[#call_args+1] = call_arg
	    end
	 end
	 if lex_peek(state.lex) ~= ")" then
	    get_expected(state, ",")
	 end
	 token = lex_peek(state.lex)
      end
   end
   get_expected(state, ")")
   MACRO.set_call_data(node, name, call_args, false, false, false, false)
   return node
end

-------------------------------------------------------------------------------
local function skip_block_common(state, right)
   local t = lex_get(state.lex)
   while t and t ~= right do
      if t == "[" then
	 skip_block_common(state, "]")
      elseif t == "{" then
	 skip_block_common(state, "}")
      elseif t == "(" then
	 skip_block_common(state, ")")
      end
      t = lex_get(state.lex)
   end
   if not t then
      error_message(state, "Out of symbols")
   end
end

local function skip_block(state, _, cur, node)
   local t = lex_get(state.lex)
   if t == "[" then
      skip_block_common(state, "]")
   elseif t == "{" then
      skip_block_common(state, "}")
   elseif t == "(" then
      skip_block_common(state, ")")
   else
      error_message(state, "Expected a bracket --[]{}()--, but got \""..
		       tostring(t).."\"")
   end
   return cur
end

local function parse_conditional_block(state, kind, cur, node, parse_func)
   tree_add_node(cur, node)
   local notallowed = {policy_module=true, module=true, template=true,
		       interface=true, class=true, common=true, gen_tunable=true} 
   if kind == "if" then
      node_set_kind(node, "boolif")
      local cond_exp = get_conditional_expr(state, "bool")
      node_set_data(node, {cond_exp})
   elseif kind == "optional" then
      warning_message(state, "Found optional", 0)
   end
   get_expected(state, "{")

   local then_block = parse_func(state, node, notallowed, "}")
   NODE.set_then_block(node, then_block)
   if lex_peek(state.lex) == "else" then
      lex_next(state.lex)
      get_expected(state, "{")
      local else_block = parse_func(state, node, notallowed, "}")
      NODE.set_else_block(node, else_block)
   end
   return node
end

local function parse_m4_conditional_block(state, kind, cur, node, parse_func)
   tree_add_node(cur, node)
   local notallowed = {policy_module=true, module=true, template=true,
		       interface=true, gen_tunable=true}
   get_expected(state, "(")
   if kind == "tunable_policy" then
      node_set_kind(node, "tunif")
      local cond_exp = get_m4_conditional_expr(state, "tunable")
      IFDEF.set_conditional(node, cond_exp)
      get_expected(state, ",")
   elseif kind == "ifdef" then
      node_set_kind(node, "ifdef")
      local cond_exp = get_m4_conditional_expr(state, "string")
      IFDEF.set_conditional(node, cond_exp)
      get_expected(state, ",")
   elseif kind == "ifndef" then
      node_set_kind(node, "ifdef")
      local cond_exp = get_m4_conditional_expr(state, "string")
      cond_exp = {"!", cond_exp}
      IFDEF.set_conditional(node, cond_exp)
      get_expected(state, ",")
   elseif kind == "optional_policy" then
      node_set_kind(node, "optional")
      notallowed["class"] = true
      notallowed["common"] = true
   end
   get_expected(state, "`")
   local then_block = parse_func(state, node, notallowed, "'")
   NODE.set_then_block(node, then_block)
   if lex_peek(state.lex) == "," then
      lex_next(state.lex)
      get_expected(state, "`")
      local else_block = parse_func(state, node, notallowed, "'")
      NODE.set_else_block(node, else_block)
   end
   get_expected(state,")")
   return node
end

local function parse_m4_ifelse_block(state, kind, cur, node, parse_func)
   warning_message(state, "Found ifelse block", 0)
   tree_add_node(cur, node)
   get_expected(state, "(")
   get_expected(state, "`")
   local v1 = lex_get(state.lex)
   get_expected(state, "'")
   get_expected(state, ",")
   get_expected(state, "`")
   local v2 = nil
   if lex_peek(state.lex) ~= "'" then
      v2 = lex_get(state.lex)
   end
   node_set_data(node, {v1,v2})
   get_expected(state, "'")
   get_expected(state, ",")
   get_expected(state, "`")  
   local notallowed = {file=true, policy_module=true, module=true, template=true,
		       interface=true, common=true, class=true}
   local then_block = parse_func(state, node, notallowed, "'")
   NODE.set_then_block(node, then_block)
   if lex_peek(state.lex) == "," then
      lex_next(state.lex)
      get_expected(state, "`")
      local else_block = parse_func(state, node, notallowed, "'")
      NODE.set_else_block(node, else_block)
   end
   get_expected(state,")")
   return cur
end

local function parse_obj_perm_set(state)
   get_expected(state, "{")
   local list = {}
   local token = lex_get(state.lex)
   while token ~= "}" and token ~= lex_END do
      list [#list+1] = token
      token = lex_get(state.lex)
   end
   if lex_peek(state.lex) == "refpolicywarn" then
      lex_next(state.lex)
      get_expected(state, "(")
      get_expected(state, "`")
      while lex_peek(state.lex) ~= "'" do
	 lex_next(state.lex)
      end
      get_expected(state, "'")
      get_expected(state, ")")
   end
   get_expected(state, "'")
   get_expected(state, ")")
   return list
end

local function parse_basic_ubac_conditions(state)
   get_expected(state, "ifdef")
   get_expected(state, "(")
   get_expected(state, "`")
   get_expected(state, "enable_ubac")
   get_expected(state, "'")
   get_expected(state, ",")
   get_expected(state, "`")
   local expr = get_constraint_expr(state, false, false)
   get_expected(state, "'")
   get_expected(state, ")")
   get_expected(state, "'")
   get_expected(state, ")")
   return expr
end

local function parse_m4_define_block(state, kind, cur, node, parse_func)
   get_expected(state, "(")
   get_expected(state, "`")
   local file = NODE.get_file_name(node)
   local name = lex_get(state.lex)
   if name == "_" then
      local strbuf = {}
      while name ~= "'" do
	 strbuf[#strbuf+1] = name
	 name = lex_get(state.lex)
      end
      lex_prev(state.lex)
      name = table.concat(strbuf)
   end
   get_expected(state, "'")
   if lex_peek(state.lex) == ")" then
      lex_next(state.lex)
      add_to_used(state, name, "tunable")
      tree_add_node(cur, node)
      node_set_kind(node, "tunable")
      node_set_data(node, {name, "true"})
      return node
   end
   get_expected(state, ",")
   get_expected(state, "`")
   if string.find(file,"misc_macros.spt",1,true) then
      if name ~= "can_exec" then
	 skip_block_common(state, ")")
	 return cur
      end
   elseif string.find(file,"obj_perm_sets.spt",1,true) then
      local list = parse_obj_perm_set(state)
      node_set_kind(node, "def")
      node_set_data(node, {name, list})
      tree_add_node(cur, node)
      return node
   elseif name == "basic_ubac_conditions" then
      local expr = parse_basic_ubac_conditions(state)
      node_set_kind(node, "def")
      node_set_data(node, {name, expr})
      tree_add_node(cur, node)
      return node
   elseif lex_peek(state.lex) == "{" then
      -- All of these should be handled elswhere
      error_message(state, "Did not expect to find a def_set")
   end
   node_set_kind(node, "macro")
   tree_add_node(cur, node)
   if state.used then
      error_message(state, "Macro not allowed inside a macro")
   end
   local used = {}
   local decls = {}
   state.used = used
   state.decls = decls
   MACRO.set_def_data(node, name, false, false, false, decls, used, false, false, false)
   local notallowed = {file=true, policy_module=true, module=true, template=true,
		       interface=true, common=true, class=true}
   local block = parse_func(state, node, notallowed, "'")
   NODE.set_block(node, block)
   get_expected(state,")")
   state.used = nil
   state.decls = nil
   return node
end

local function parse_m4_macro_block(state, kind, cur, node, parse_func)
   node_set_kind(node, "macro")
   tree_add_node(cur, node)
   get_expected(state, "(")
   get_expected(state, "`")
   local name = get_identifier(state, nil)
   get_expected(state, "'")
   get_expected(state, ",")
   get_expected(state, "`")
   if state.used then
      error_message(state, "Macro not allowed inside a macro")
   end
   local used = {}
   local decls = {}
   state.used = used
   state.decls = decls
   MACRO.set_def_data(node, name, false, false, false, decls, used, false, false, false)
   local notallowed = {file=true, policy_module=true, module=true, template=true,
		       interface=true, common=true, class=true}
   local block = parse_func(state, node, notallowed, "'")
   NODE.set_block(node, block)
   get_expected(state,")")
   state.used = nil
   state.decls = nil
   return node
end

local function parse_m4_module_block(state, kind, cur, node, parse_func)
   node_set_kind(node, "module")
   tree_add_node(cur, node)
   get_expected(state, "(")
   local name = lex_get(state.lex)
   local filename = LEX.filename(state.lex)
   local s,e,module_name = string.find(filename,"[%w%_%-]+/([%w%_%-]+)%.%w%w$")
   if name ~= module_name then
      warning_message(state, "Module name "..tostring(name)..
		       " is not the same as filename "..tostring(module_name), 0)
   end
   get_expected(state, ",")
   local version = {}
   while lex_peek(state.lex) ~= ")" do
      version[#version+1] = lex_get(state.lex)
   end
   get_expected(state, ")")
   node_set_data(node, {name, table.concat(version)})
   local notallowed = {file=true, policy_module=true, module=true,}
   local block = parse_func(state, node, notallowed, nil)
   NODE.set_block(node, block)
   return node
end

local function parse_require_block(state, kind, cur, node)
   -- role, type, attribute, attributerole, user, bool, tunable, sensitivity, category
   -- class [CLASS identifier names]
   local parent = NODE.get_parent(node)
   local parent_kind = NODE.get_kind(parent)
   local requires
   if parent_kind == "macro" then
      requires = MACRO.get_def_requires(parent)
   elseif state.verbose > 2 then
      -- For now just report require blocks outside of a macro
      -- There are a few in Red Hat's policy, but they are mostly for class and perms
      -- (with one for a bool)
      warning_message(state, "require outside of a macro", 3)
   end
   requires = requires or {}
   if kind == "gen_require" then
      get_expected(state, "(")
      get_expected(state, "`")
   else
      get_expected(state, "{")
   end
   while lex_peek(state.lex) ~= "'" and lex_peek(state.lex) ~= "}" do
      local flavor = lex_get(state.lex)
      if flavor == "attribute" then
	 flavor = "type"
      elseif flavor == "attribute_role" then
	 flavor = "role"
      end
      if flavor then
	 requires[flavor] = requires[flavor] or {}
	 if flavor == "class" then
	    -- For now, not doing anything with class
	    local class = lex_get(state.lex)
	    requires["class"][class] = {}
	    local perm = lex_get(state.lex)
	    if perm == "{" then
	       -- This can include "*" or "~"
	       perm = lex_get(state.lex)
	       while perm ~= "}" do
		  requires["class"][class][perm] = true
		  perm = lex_get(state.lex)
	       end
	    else
	       requires["class"][class][perm] = true
	    end
	 else
	    local list = get_comma_separated_list(state, nil)
	    for i=1,#list do
	       requires[flavor][list[i]] = true
	    end
	 end
	 get_expected(state, ";")
      end
   end
   if parent_kind == "macro" then
      MACRO.set_def_requires(parent, requires)
   end
   if kind == "gen_require" then
      get_expected(state,"'")
      get_expected(state,")")
   else
      get_expected(state,"}")
   end
   return cur
end

local function parse_refpolicywarn(state, kind, cur, node)
   local macro = node
   while macro and NODE.get_kind(macro) ~= "macro" do
      macro = NODE.get_parent(macro)
   end
   if not macro then
      return skip_block(state, kind, cur, node)
   end

   local node_flags = MACRO.get_def_flags(macro)

   get_expected(state,"(")
   get_expected(state,"`")
   local t = lex_get(state.lex)
   local found = false
   while t ~= "'" do
      if t == "deprecated" or t == "deprecated." or t == "replaced" then
	 node_flags[1] = true
	 found = true
      elseif t == "implemented" then
	 node_flags[2] = true
	 found = true
      end
      t = lex_get(state.lex)
   end
   get_expected(state,")")

   if not found then
      TREE.warning("Could not figure out refpolicywarn", node)
   end

   MACRO.set_def_flags(macro, node_flags)

   return cur
end

-------------------------------------------------------------------------------
local rules = {
   ["policycap"] = parse_policycap_rule,
   ["bool"] = parse_bool_rule,
   ["gen_bool"] = parse_gen_bool_rule,
   ["tunable"] = parse_tunable_rule,
   ["gen_tunable"] = parse_gen_tunable_rule,
   ["sid"] = parse_sid_rule, -- Either a sid declaration or an initial sid
   ["class"] = parse_class_rule, -- Either a class declaration or class instantiation
   ["common"] = parse_common_rule,
   ["default_user"] = parse_default_rule,
   ["default_role"] = parse_default_rule,
   ["default_type"] = parse_default_rule,
   ["default_range"] = parse_default_range_rule,
   ["gen_user"] = parse_gen_user_rule,
   ["user"] = parse_user_rule,
   ["role"] = parse_role_rule,
   ["type"] = parse_type_rule,
   ["typealias"] = parse_typealias_rule,
   ["typebounds"] = parse_typebounds_rule,
   ["permissive"] = parse_permissive_rule,
   ["attribute"] = parse_attribute_rule,
   ["typeattribute"] = parse_typeattribute_rule,
   ["attribute_role"] = parse_attribute_role_rule,
   ["roleattribute"] = parse_roleattribute_rule,
   ["sensitivity"] = parse_sensitivity_rule,
   ["dominance"] = parse_dominance_rule,
   ["category"] = parse_category_rule,
   ["level"] = parse_level_rule,
   ["allow"] = parse_allow_rule, -- Either type allow or role allow
   ["dontaudit"] = parse_av_rule,
   ["auditallow"] = parse_av_rule,
   ["neverallow"] = parse_av_rule,
   ["allowxperm"] = parse_xperm_rule,
   ["neverallowxperm"] = parse_xperm_rule,
   ["type_transition"] = parse_type_transition_rule,
   ["type_change"] = parse_type_change_rule,
   ["type_member"] = parse_type_member_rule,
   ["range_transition"] = parse_range_transition_rule,
   ["role_transition"] = parse_role_transition_rule,
   ["constrain"] = parse_constrain_rule,
   ["mlsconstrain"] = parse_constrain_rule,
   ["validatetrans"] = parse_validatetrans_rule,
   ["mlsvalidatetrans"] = parse_validatetrans_rule,
   ["filecon"] = parse_filecon_rule,
   ["fs_use_xattr"] = parse_fs_use_rule,
   ["fs_use_task"] = parse_fs_use_rule,
   ["fs_use_trans"] = parse_fs_use_rule,
   ["genfscon"] = parse_genfscon_rule,
   ["netifcon"] = parse_netifcon_rule,
   ["nodecon"] = parse_nodecon_rule,
   ["portcon"] = parse_portcon_rule,
   ["gen_sens"] = parse_gen_sens_rule,
   ["gen_cats"] = parse_gen_cats_rule,
   ["gen_levels"] = parse_gen_levels_rule,
   ["gen_require"] = parse_require_block,
   ["require"] = parse_require_block,
   ["undefine"] = skip_block,
   ["refpolicywarn"] = parse_refpolicywarn,
}

local blocks = {
   ["policy_module"] =   parse_m4_module_block,
   ["module"] =          parse_m4_module_block,
   ["ifdef"] =           parse_m4_conditional_block,
   ["ifndef"] =          parse_m4_conditional_block,
   ["tunable_policy"] =  parse_m4_conditional_block,
   ["if"] =              parse_conditional_block,
   ["optional"] =        parse_conditional_block,
   ["optional_policy"] = parse_m4_conditional_block,
   ["define"] =          parse_m4_define_block,
   ["ifelse"] =          parse_m4_ifelse_block,
}

local function parse_block(state, parent, not_allowed, endsym)
   local top = node_create(false, false, false, false)
   local cur = top
   local new
   local token, file, lineno = lex_get_full(state.lex)
   while token ~= lex_END and token ~= lex_EOF and token ~= endsym do
      new = node_create(token, parent, file, lineno)
      if notallowed and not_allowed[token] then
	 error_message(state, "Error: "..tostring(token).." not allowed in a "..
			       tostring(NODE.get_kind(parent)).." block")
      elseif blocks[token] then
	 cur = blocks[token](state, token, cur, new, parse_block)
      elseif rules[token] then
	 cur = rules[token](state, token, cur, new)
      elseif lex_peek(state.lex) == "(" then
	 cur = parse_macro_call(state, token, cur, new)
      else
	 warning_message(state, "Unexpected symbol: \""..tostring(token).."\"", 0)
      end
      token, file, lineno = lex_get_full(state.lex)
   end
   if token ~= endsym then
      lex_prev(state.lex)
   end
   return node_next(top)
end

local function parse_interface_file(state, parent, not_allowed, endsym)
   local top, cur, new
   local token, file, lineno = lex_get_full(state.lex)
   while token ~= lex_END and token ~= lex_EOF and token ~= endsym do
      if token == "interface" or token == "template" then
	 new = node_create(token, parent, file, lineno)
	 cur = parse_m4_macro_block(state, token, cur, new, parse_block)
      else
	 warning_message(state, "Unexpected symbol: \""..tostring(token).."\"", 0)
      end
      top = top or cur
      token, file, lineno = lex_get_full(state.lex)
   end
   if token ~= endsym then
      lex_prev(state.lex)
   end
   return top
end

local function parse_filecon_file(state, parent, not_allowed, endsym)
   local top, cur, new
   local token, file, lineno = lex_get_full(state.lex)
   while token ~= lex_END and token ~= lex_EOF and token ~= endsym do
      new = node_create(token, parent, file, lineno)
      if token == "ifdef" or token == "ifndef" then
	 cur = parse_m4_conditional_block(state, token, cur, new, parse_filecon_file)
      elseif string.find(token, "^%/") or token == "HOME_ROOT" or token == "HOME_DIR" then
	 cur = parse_filecon_rule(state, token, cur, new)
      else
	 warning_message(state, "Unexpected symbol: \""..tostring(token).."\"", 0)
      end
      top = top or cur
      token, file, lineno = lex_get_full(state.lex)
   end
   if token ~= endsym then
      lex_prev(state.lex)
   end
   return top
end

local function parse_files(state, parent)
   local top, cur, new, block
   local token, file, lineno = lex_get_full(state.lex)
   while token ~= lex_END do
      if token ~= lex_SOF then
	 error_message(state, "Expected start of file, found ["..
		       tostring(token).."]")
      end
      new = node_create("file", parent, file, lineno)
      top = top or new
      cur = tree_add_node(cur, new)
      node_set_data(new, {file})
      local _,_,ext = string.find(file,"%.(%a%a)$")
      if ext == "fc" then
	 block = parse_filecon_file(state, cur, nil, lex_EOF)
      elseif ext == "if" then
	 block = parse_interface_file(state, cur, nil, lex_EOF)
      else
	 block = parse_block(state, cur, nil, lex_EOF)
      end
      NODE.set_block(new, block)
      token, file, lineno = lex_get_full(state.lex)
   end
   return top
end

-------------------------------------------------------------------------------	 
local function parse_refpolicy_policy(active_files, inactive_files,
				      head, cdefs, tunables, verbose)
   MSG.verbose_out("\nParse Refpolicy Policy", verbose, 0)

   local lex_state = LEX.create(active_files, 4)
   local state = {verbose=verbose, lex=lex_state, rules=rules, blocks=blocks,
		  cdefs=cdefs, tunables=tunables}

   local block1 = parse_files(state, head)
   TREE.set_active(head, block1)
   TREE.enable_active(head)
   lex_next(lex_state)
   local files, lines, tokens = LEX.stats(lex_state)
   local s1 = string.format("Active: %d Files  %d Lines  %d Tokens",
			    files, lines, tokens)
   MSG.verbose_out(s1, verbose, 1)

   if inactive_files and next(inactive_files) then
      lex_state = LEX.create(inactive_files, 4)
      state.lex = lex_state
      local block2 = parse_files(state, head)
      TREE.set_inactive(head, block2)
      lex_next(lex_state)
      local files, lines, tokens = LEX.stats(lex_state)
      local s2 = string.format("Inactive: %d Files  %d Lines  %d Tokens\n",
			       files, lines, tokens)
      MSG.verbose_out(s2, verbose, 1)
   end
end
refpolicy_parse.parse_refpolicy_policy = parse_refpolicy_policy

return refpolicy_parse
