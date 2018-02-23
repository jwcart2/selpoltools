local MSG = require "messages"
local NODE = require "node"
local MACRO = require "node_macro"
local TREE = require "tree"

local refpolicy_macros_collect = {}

-------------------------------------------------------------------------------
local function add_macro_call_inside(node, kind, do_action, do_block, data)
   local name = MACRO.get_call_name(node)
   data.calls[name] = data.calls[name] or {}
   local n = #data.calls[name]
   data.calls[name][n+1] = node
end

local function add_macro_def(node, kind, do_action, do_block, data)
   local call_action = {
      ["call"] = add_macro_call_inside,
   }
   local name = MACRO.get_def_name(node)
   if name and data.defs[name] then
      TREE.warning("Duplicate macro def", node)
      TREE.warning("  Previously declared at", data.defs[name])
      return
   end
   data.defs[name] = node
   local block = NODE.get_block(node)
   TREE.walk_tree(block, call_action, do_block, data)
end

local function add_macro_call_outside(node, kind, do_action, do_block, data)
   local name = MACRO.get_call_name(node)
   local n

   data.calls[name] = data.calls[name] or {}
   n = #data.calls[name]
   data.calls[name][n+1] = node

   data.calls_out[name] = data.calls_out[name] or {}
   n = #data.calls_out[name]
   data.calls_out[name][n+1] = node
end

local function collect_active_macros(head, verbose)
   MSG.verbose_out("\nCollect active macro definitions and calls", verbose, 0)

   local data = {verbose=verbose, defs={}, calls={}, calls_out={}}
   local macro_action = {
      ["macro"] = add_macro_def,
      ["call"] = add_macro_call_outside,
   }

   head = TREE.get_head(head)
   TREE.walk_normal_tree(head, macro_action, data)

   -- defs      - All macro definitions defs
   --               [DEF_NAME] = def_node
   -- calls     - All macro calls
   --               [CALL_NAME][LIST] = call_node
   -- calls_out - Macro calls outside of macro definitions
   --               [CALL_NAME][LIST] = call_node
   return data.defs, data.calls, data.calls_out
end
refpolicy_macros_collect.collect_active_macros = collect_active_macros

-------------------------------------------------------------------------------
local function add_inactive_macro_def(node, kind, do_action, do_block, data)
   local name = MACRO.get_def_name(node)
   if name and data.defs[name] then
      TREE.warning1(data.verbose, "Duplicate macro def", node)
      TREE.warning1(data.verbose, "  Previously declared at", data.defs[name])
      return
   end
   data.defs[name] = node
end

local function collect_inactive_macros(head, verbose)
   MSG.verbose_out("\nCollect inactive macro definitions", verbose, 0)

   local data = {verbose=verbose, defs={}}
   local macro_action = {
      ["macro"] = add_inactive_macro_def,
   }

   head = TREE.get_head(head)
   TREE.disable_active(head)
   TREE.enable_inactive(head)
   TREE.walk_normal_tree(head, macro_action, data)
   TREE.disable_inactive(head)
   TREE.enable_active(head)

   -- defs      - All inactive macro definitions defs
   --               [DEF_NAME] = def_node
   return data.defs
end
refpolicy_macros_collect.collect_inactive_macros = collect_inactive__macros

-------------------------------------------------------------------------------
local function collect_macros(head, verbose)

   local defs, calls, calls_out = collect_active_macros(head, verbose)
   local inactive_defs = collect_inactive_macros(head, verbose)
   return defs, calls, calls_out, inactive_defs
end
refpolicy_macros_collect.collect_macros = collect_macros

-------------------------------------------------------------------------------
return refpolicy_macros_collect
