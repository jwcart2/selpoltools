local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"

local refpolicy_macros_expand = {}

-------------------------------------------------------------------------------
local function copy_and_expand_data(old, args)
   if old == false then
      return false
   else
      local new = {}
      for i,v in pairs(old) do
	 if type(v) ~= "table" then
	    if args[v] then
	       new[i] = args[v]
	    else
	       new[i] = v
	    end
	 else
	    new[i] = copy_and_expand_data(v, args)
	 end
      end
      return new
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

local expand_call_inside_macro

local function copy_and_expand_node(old, cur, parent, args, defs)
   cur = cur or false
   parent = parent or false
   local kind = NODE.get_kind(old) or false
   local filename = NODE.get_file_name(old) or false
   local lineno = NODE.get_line_number(old) or false
   local old_data = NODE.get_data(old) or false
   local new_data = copy_and_expand_data(old_data, args)
   local new = {kind, parent, false, filename, lineno, new_data, false}
   NODE.set_next(cur, new)
   if kind == "call" then
      local name = MACRO.get_call_name(new)
      if defs[name] then
	 expand_call_inside_macro(new, defs[name], defs, args)
      end
   end
   return new
end

local function copy_and_expand_block(old, parent, args, defs)
   local start = false
   local cur
   while old do
      cur = copy_and_expand_node(old, cur, parent, args, defs)
      if NODE.has_block(old) then
	 local old1 = NODE.get_block_1(old)
	 local old2 = NODE.get_block_2(old)
	 if old1 then
	    local block1 = copy_and_expand_block(old1, cur, args, defs)
	    NODE.set_block_1(cur, block1)
	 end
	 if old2 then
	    local block2 = copy_and_expand_block(old2, cur, args, defs)
	    NODE.set_block_2(cur, block2)
	 end
      end
      old = NODE.get_next(old)
      start = start or cur
   end
   return start
end

function expand_call_inside_macro(call, macro, defs, args)
   local orig_args = MACRO.get_call_orig_args(call)
   local call_exp_args_old = MACRO.get_call_exp_args(call)
   local trans_tab = create_trans_table(orig_args)
   local call_exp_args_new = create_call_exp_args(call_exp_args_old, trans_tab)
   local macro_block = NODE.get_block(macro)
   local block = copy_and_expand_block(macro_block, call, call_exp_args_new, defs)
   NODE.set_block(call, block)
end

local function expand_call_outside_macro(call, macro, defs)
   local args = MACRO.get_call_exp_args(call)
   local macro_block = NODE.get_block(macro)
   local block = copy_and_expand_block(macro_block, call, args, defs)
   NODE.set_block(call, block)
end

-------------------------------------------------------------------------------
local function expand_macros(defs, calls_out, verbose)
   MSG.verbose_out("\nExpand macro calls", verbose, 0)

   for name, call_list in pairs(calls_out) do
      if defs[name] then
	 for _, call in pairs(call_list) do
	    if not NODE.has_block(call) then
	       expand_call_outside_macro(call, defs[name], defs)
	    end
	 end
      end
   end
end
refpolicy_macros_expand.expand_macros = expand_macros

-------------------------------------------------------------------------------
return refpolicy_macros_expand
