local MSG = require "messages"
local NODE = require "node"

local tree = {}

-------------------------------------------------------------------------------
local function add_node(cur, node)
   local nxt = NODE.get_next(cur)
   if nxt then
      NODE.set_next(node, nxt)
   end
   NODE.set_next(cur, node)
   return node
end
tree.add_node = add_node

local function remove_node(cur, prev)
   if not cur then
      return
   end
   local nxt = NODE.get_next(cur)
   NODE.set_next(prev, nxt)
   return nxt
end
tree.remove_node = remove_node

local next_node = NODE.get_next
tree.next_node = next_node

-------------------------------------------------------------------------------
local function get_head(cur)
   while NODE.get_parent(cur) do
      cur = NODE.get_parent(cur)
   end
   return cur
end
tree.get_head = get_head

local function get_last_node(cur)
   local nxt = next_node(cur)
   while nxt do
      cur = nxt
      nxt = next_node(cur)
   end
   return cur
end
tree.get_last_node = get_last_node

local function get_filename(cur)
   while cur and not NODE.get_file_name(cur) do
      cur = NODE.get_parent(cur)
   end
   return cur and NODE.get_file_name(cur)
end
tree.get_filename = get_filename

local function get_lineno(cur)
   while cur and not NODE.get_line_number(cur) do
      cur = NODE.get_parent(cur)
   end
   return cur and NODE.get_line_number(cur)
end
tree.get_lineno = get_lineno

-------------------------------------------------------------------------------
-- These functions are to be called on the head

local function set_active(head, active)
   head = get_head(head)
   local data = NODE.get_data(head) or {false, false}
   data[1] = active
   NODE.set_data(head, data)
   NODE.set_block_1(head, active)
end
tree.set_active = set_active

local function enable_active(head)
   head = get_head(head)
   local data = NODE.get_data(head) or {false, false}
   NODE.set_block_1(head, data[1])
end
tree.enable_active = enable_active

local function disable_active(head)
   head = get_head(head)   
   NODE.set_block_1(head, false)
end
tree.disable_active = disable_active

local function set_inactive(head, inactive)
   head = get_head(head)
   local data = NODE.get_data(head) or {false, false}
   data[2] = inactive
   NODE.set_data(head, data)
   NODE.set_block_2(head, inactive)
end
tree.set_inactive = set_inactive

local function enable_inactive(head)
   head = get_head(head)
   local data = NODE.get_data(head) or {false, false}
   NODE.set_block_2(head, data[2])
end
tree.enable_inactive = enable_inactive

local function disable_inactive(head)
   head = get_head(head)
   NODE.set_block_2(head, false)
end
tree.disable_inactive = disable_inactive

-------------------------------------------------------------------------------
local function compose_line_and_file_string(node)
   if not node then
      return ""
   end
   local line = get_lineno(node) or "(?)"
   local path = get_filename(node) or "(?)"
   local s,e,mod = string.find(path,"/([%w%_%-]+/[%w%_%-]+%.%w%w)$")
   mod = mod or path
   return string.format("%s:%s",mod, line)
end
tree.compose_line_and_file_string = compose_line_and_file_string

local function warning(msg, node)
   local msg = msg or ""
   if node then
      msg = msg.." at "..compose_line_and_file_string(node)
   end
   MSG.warning(msg)
end
tree.warning = warning

local function verbose_warning(verbose, level, msg, node)
   local msg = msg or ""
   if node then
      msg = msg.." at "..compose_line_and_file_string(node)
   end
   MSG.verbose_out(msg, verbose, level)
end
tree.verbose_warning = verbose_warning

local function warning1(verbose, msg, node)
   verbose_warning(verbose, 0, msg, node)
end
tree.warning1 = warning1

local function warning2(verbose, msg, node)
   verbose_warning(verbose, 1, msg, node)
end
tree.warning2 = warning2

local function warning3(verbose, msg, node)
   verbose_warning(verbose, 2, msg, node)
end
tree.warning3 = warning3

local function error_message(msg, node)
   local msg = msg or ""
   if node then
      msg = msg.." at "..compose_line_and_file_string(node)
   end
   MSG.error_message(msg)
end
tree.error_message = error_message

local function error_check(cond, msg, node)
   if cond then
      local msg = msg or ""
      if node then
	 msg = msg.." at "..compose_line_and_file_string(node)
      end
      original_error_message(msg)
   end
end
tree.error_check = error_check

-------------------------------------------------------------------------------
-- Walk Tree
-------------------------------------------------------------------------------
local function walk_block(cur, do_action, do_block, data, walk_func)
   local n1 = cur[7][1] --Inlining: NODE.get_block_1(cur)
   local n2 = cur[7][2] --Inlining: NODE.get_block_2(cur)
   if n1 then
      walk_func(n1, do_action, do_block, data)
   end
   if n2 then
      walk_func(n2, do_action, do_block, data)
   end
end
tree.walk_block = walk_block

local function walk_tree(cur, do_action, do_block, data)
   while cur do
      -- Inner loop is run > 3,000,000 times for Refpolicy
      local kind = cur[1] --Inlining: NODE.get_kind(cur)
      
      if do_action and do_action[kind] then	 
	 do_action[kind](cur, kind, do_action, do_block, data)
      elseif do_block and do_block[kind] then
	 do_block[kind](cur, kind, do_action, do_block, data)
     elseif cur[7] then --Inlining: NODE.has_block(cur)
	 walk_block(cur, do_action, do_block, data, walk_tree)
      end
      cur = cur[3] --Inlining: next_node(cur) [which is NODE.get_next(cur)]
   end
end
tree.walk_tree = walk_tree

local function walk_normal_tree(head, do_action, data)
   walk_tree(head, do_action, nil, data)
end
tree.walk_normal_tree = walk_normal_tree

-------------------------------------------------------------------------------
return tree
