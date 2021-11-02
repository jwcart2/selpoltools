local NODE = require "node"

local node_ifdef = {}

-------------------------------------------------------------------------------
local node_set_data = NODE.set_data

-------------------------------------------------------------------------------

------------------------------
-- ifdef data
-- 1 - Conditional Expression
------------------------------

local function get_conditional(node)
   local data = node and node[6] --Inlining: NODE.get_data(node)
   return data and data[1]
end
node_ifdef.get_conditional = get_conditional

local function set_conditional(node, conditional)
   if not node then
	  return
   end
   local data = node[6] --Inlining: NODE.get_data(node)
   if not data then
	  node_set_data(node, {conditional, false})
   else
	  data[1] = conditional
   end
end
node_ifdef.set_conditional = set_conditional

-------------------------------------------------------------------------------
return node_ifdef
