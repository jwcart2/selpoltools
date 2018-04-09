local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"
local TREE = require "tree"

local refpolicy_macros_process = {}

-------------------------------------------------------------------------------
local UNUSED_FLAVOR = "_UNUSED_"

local set_ops = {
   ["*"] = "all",
   ["~"] = "not",
   ["-"] = "neg",
}

-------------------------------------------------------------------------------
local function add_macro_call_inside(node, kind, do_action, do_block, data)
   local name = MACRO.get_call_name(node)
   data.calls[name] = data.calls[name] or {}
   local n = #data.calls[name]
   data.calls[name][n+1] = node
   data.defs[name] = data.defs[name] or {}
   data.defs[name][data.name] = data.node
end

local function add_macro_def(macro, def_calls, call_defs)
   local call_action = {
      ["call"] = add_macro_call_inside,
   }
   local name = MACRO.get_def_name(macro)
   def_calls[name] = {}
   local def_data = {name=name, node=macro, calls=def_calls[name],
		     defs=call_defs}
   local block = NODE.get_block(macro)
   TREE.walk_tree(block, call_action, nil, def_data)
end

local function create_def_and_call_tables(defs)
   local def_calls = {}
   local call_defs = {}
   for _,def in pairs(defs) do
      add_macro_def(def, def_calls, call_defs)
   end
   return def_calls, call_defs
end

-------------------------------------------------------------------------------
local function add_to_tab(tab, token, flavor)
   local prev_flavor = tab[token]
   if type(flavor) ~= "table" then
      if not prev_flavor then
	 tab[token] = flavor
      elseif type(prev_flavor) ~= "table" then
	 if prev_flavor ~= flavor then
	     tab[token] = {prev_flavor, flavor}
	 end
      else
	 local duplicate = false
	 for i,f in pairs(prev_flavor) do
	    if f == flavor then
	       duplicate = true
	    end
	 end
	 if not duplicate then
	    prev_flavor[#prev_flavors+1] = flavor
	 end
      end
   else
      local i = 1
      if not prev_flavor then
	 tab[token] = {}
      elseif type(prev_flavor) ~= "table" then
	 tab[token] = {prev_flavor}
	 i = i + 1
      end
      for f,_ in pairs(flavor) do
	 if f ~= prev_flavor then
	    tab[token][i] = f
	    i = i + 1
	 end
      end
   end
end

local function get_flavors_and_args_from_used(used)
   local args = {}
   local flavors = {}
   local max_arg = 0
   for flavor, toktab in pairs(used) do
      for tok,_ in pairs(toktab) do
	 local s,e,num = string.find(tok, "%$(%d+)")
	 if s then
	    add_to_tab(args, tok, flavor)
	    if s == 1 and e == #tok then
	       -- Simple parameter: $1, $2, etc
	       local n = tonumber(num)
	       if n > max_arg then
		  max_arg = n
	       end
	       add_to_tab(flavors, n, flavor)
	    else
	       -- Compound parameter: $1_t, foo_$1_bar_$2_t, etc
	       for num in string.gmatch(tok, "%$(%d+)") do
		  local n = tonumber(num)
		  if n > max_arg then
		     max_arg = n
		  end
		  add_to_tab(flavors, n, "string")
	       end
	    end
	 end
      end
   end
   return flavors, args, max_arg
end

local function report_and_fix_parameter_holes(flavors, max, name, node, verbose)
   -- Reports holes in macro parameters. ex/ Has $2, but no $1
   local param_info = MACRO.get_def_param_info(node)
   local num_unused = param_info[2]

   for i=1,max do
      if not flavors[i] then
	 flavors[i] = UNUSED_FLAVOR
	 if num_unused > 0 then
	    num_unused = num_unused - 1
	 else
	    local param = "$"..tostring(i)
	    TREE.warning("Unused macro parameter: "..param.." in "..tostring(name).."()",
			 node)
	 end
      end
   end
end

local function prepare_ready_defs(defs, def_calls, call_defs, verbose)
   local ready = {}
   for name, calltab in pairs(def_calls) do
      if not next(calltab) then
	 local def = defs[name]
	 if not def then
	    TREE.warning1(verbose, "No macro def for "..tostring(name), nil)
	 end
	 local used = MACRO.get_def_used(def)
	 local decls = MACRO.get_def_decls(def)
	 if used["type"] and used["type"]["self"] then
	    used["type"]["self"] = nil
	 end
	 local orig_flavors, exp_args, max_arg = get_flavors_and_args_from_used(used)
	 if #orig_flavors ~= max_arg then
	    report_and_fix_parameter_holes(orig_flavors, max_arg, name, def, verbose)
	 end
	 MACRO.set_def_orig_flavors(def, orig_flavors)
	 MACRO.set_def_exp_args(def, exp_args)
	 if call_defs[name] then
	    ready[name] = def
	 else
	    def_calls[name] = nil
	 end
      else
	 local remove = {}
	 for callname, call_list in pairs(calltab) do
	    if not def_calls[callname] then
	       remove[callname] = true
	    end
	 end
	 for callname,_ in pairs(remove) do
	    calltab[callname] = nil
	 end
      end
   end
   return ready
end

-------------------------------------------------------------------------------
local function add_arg_to_used_flavor(used_flavor, arg)
   if type(arg) ~= "table" then
      if not set_ops[arg] then			   
	 used_flavor[arg] = true
      end
   else
      for i=1,#arg do
	 add_arg_to_used_flavor(used_flavor, arg[i])
      end
   end
end

local function add_args_to_used(args, flavors, used)
   for i,flavor in pairs(flavors) do
      local v = args[i]
      if v then
	 used[flavor] = used[flavor] or {}
	 if type(v) ~= "table" then
	    used[flavor][v] = true
	 else
	    add_arg_to_used_flavor(used[flavor], v)
	 end
      end
   end
end

local function handle_pass_through_args(flavors, call_node)
   local max = #flavors
   local args = {}
   for i=1,max do
      local v = "$"..tostring(i)
      args[i] = v
   end
   MACRO.set_call_orig_args(call_node, args)
   return args
end

local function report_wrong_number_of_args(args, flavors, call_name, call_node,
					   def_node, verbose)
   local param_info = MACRO.get_def_param_info(def_node)
   local num_optional = param_info[1]
   local num_unused = param_info[2]
   local def_name = MACRO.get_def_name(def_node)
   local num = #args - #flavors
   if num < 0 then
      num = -num

      if string.find(call_name, "filetrans") and num == 1 and
      flavors[#flavors] == "string" then
	 -- Expected
	 return
      end
      if verbose < 2 and (num - num_optional) <= 0 then
	 -- Expected
	 return
      end
      TREE.warning("Call has less arguments then needed: "..
		      tostring(call_name).."()",call_node)
   else
      if string.find(call_name, "stub") and num == 1 and verbose < 2 then
	 -- Expected
	 return
      end
      if verbose < 1 and (num - num_unused <= 0) then
	 return
      end
      TREE.warning("Call has more arguments then needed: "..
		      tostring(call_name).."()",call_node)
   end
end

local function create_trans_table(args)
   local trans_tab = {}
   for i,v in pairs(args) do
      local a = "$"..tostring(i)
      trans_tab[a] = v
   end
   return trans_tab
end

local function translate_complex_value(value, trans_tab)
   local s,e,arg = string.find(value, "(%$%d+)")
   if not s then
      return value
   else
      local t = {}
      local rem = value
      while s do
	 t[#t+1] = string.sub(rem,1,s-1)
	 t[#t+1] = trans_tab[arg]
	 rem = string.sub(rem,e+1)
	 s,e,arg = string.find(rem, "(%$%d+)")
      end
      t[#t+1] = rem
      return table.concat(t)
   end
end   

local function create_call_decls(decls, trans_tab)
   local call_decls = {}
   for flavor, decltab in pairs(decls) do
      call_decls[flavor] = call_decls[flavor] or {}
      for tok,_ in pairs(decltab) do
	 if trans_tab[tok] then
	    call_decls[flavor][trans_tab[tok]] = true
	 else
	    local value = translate_complex_value(tok, trans_tab)
	    call_decls[flavor][value] = true
	 end
      end
   end
   return call_decls
end

local function create_call_exp_args(exp_args, trans_tab)
   local call_exp_args = {}
   for v,_ in pairs(exp_args) do
      if trans_tab[v] then
	 call_exp_args[v] = trans_tab[v]
      else
	 local value = translate_complex_value(v, trans_tab)
	 call_exp_args[v] = value
      end
   end
   return call_exp_args
end

local function process_defs(ready, def_calls, call_defs, verbose)
   for call_name, call_def_node in pairs(ready) do
      def_calls[call_name] = nil
      local orig_flavors = MACRO.get_def_orig_flavors(call_def_node)
      local exp_args = MACRO.get_def_exp_args(call_def_node)
      local decls = MACRO.get_def_decls(call_def_node)
      for parent_name, parent_def in pairs(call_defs[call_name]) do
	 local parent_decls = MACRO.get_def_decls(parent_def)
	 local parent_used = MACRO.get_def_used(parent_def)
	 local calltab = def_calls[parent_name]
	 for _,call_node in pairs(calltab[call_name]) do
	    local orig_args = MACRO.get_call_orig_args(call_node)
	    if #orig_args == 1 and orig_args[1] == "$*" then
	       orig_args = handle_pass_through_args(orig_flavors, call_node)
	    end
	    if #orig_args ~= #orig_flavors then
	       report_wrong_number_of_args(orig_args, orig_flavors, call_name,
					   call_node, call_def_node, verbose)
	    end
	    local trans_tab = create_trans_table(orig_args)
	    local call_decls = create_call_decls(decls, trans_tab)
	    MACRO.set_call_decls(call_node, call_decls)
	    local call_exp_args = create_call_exp_args(exp_args, trans_tab)
	    MACRO.set_call_exp_args(call_node, call_exp_args)
	    for flavor, decltab in pairs(call_decls) do
	       parent_decls[flavor] = parent_decls[flavor] or {}
	       for d,_ in pairs(decltab) do
		  parent_decls[flavor][d] = true
	       end
	    end
	    add_args_to_used(orig_args, orig_flavors, parent_used)
	 end
	 calltab[call_name] = nil
      end
   end
end

-------------------------------------------------------------------------------
local function process_calls_outside(calls, defs, verbose)
   for name, call_list in pairs(calls) do
      if not defs[name] then
	 for _,call in pairs(call_list) do
	    MACRO.set_call_decls(call, {})
	    MACRO.set_call_exp_args(call, {})
	 end
      else
	 local def = defs[name]
	 local orig_flavors = MACRO.get_def_orig_flavors(def)
	 local def_decls = MACRO.get_def_decls(def)
	 local def_exp_args = MACRO.get_def_exp_args(def)
	 for _,call in pairs(call_list) do
	    local orig_args = MACRO.get_call_orig_args(call)
	    if #orig_args ~= #orig_flavors then
	       report_wrong_number_of_args(orig_args, orig_flavors, name, call,
					   def, verbose)
	    end
	    local trans_tab = create_trans_table(orig_args)
	    local call_decls = create_call_decls(def_decls, trans_tab)
	    MACRO.set_call_decls(call, call_decls)
	    local call_exp_args = create_call_exp_args(def_exp_args, trans_tab)
	    MACRO.set_call_exp_args(call, call_exp_args)
	 end
      end
   end
end

-------------------------------------------------------------------------------
local function process_macro_calls(defs, calls_out, verbose)
   MSG.verbose_out("\nProcess macro calls", verbose, 0)

   local def_calls, call_defs = create_def_and_call_tables(defs)
   while next(def_calls) do
      local ready = prepare_ready_defs(defs, def_calls, call_defs, verbose)
      process_defs(ready, def_calls, call_defs, verbose)
      if not next(ready) and next(def_calls) then
	 MSG.warning("Unable to process any more macros")
	 MSG.warning("The following macros were not processed:")
	 for macro, _ in pairs(def_calls) do
	    TREE.warning("  "..tostring(macro).."()")
	 end
      end
   end

   process_calls_outside(calls_out, defs, verbose)
end
refpolicy_macros_process.process_macro_calls = process_macro_calls

-------------------------------------------------------------------------------
return refpolicy_macros_process
