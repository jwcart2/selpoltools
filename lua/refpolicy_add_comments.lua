local MSG = require "messages"
local NODE = require "node"
local TREE = require "tree"

local refpolicy_comments = {}

-------------------------------------------------------------------------------
local string_find = string.find
local string_sub = string.sub

-------------------------------------------------------------------------------
local function get_comments_from_file(node, kind, do_action, do_block, data)
   local file = NODE.get_file_name(node)
   local f = io.open(file)
   if not f then
	  file = file or "(nil)"
	  MSG.warning("Failed to open file: "..tostring(file))
	  return
   end
   local comments = {}
   local lineno = 1
   for l in f:lines() do
	  if l == "" then
		 comments[#comments+1] = {"blank", lineno, line}
	  end
	  local s,e = string_find(l,"^%s*#")
	  if s then
		 local line = string_sub(l,e+1)
		 comments[#comments+1] = {"comment", lineno, line}
	  end
	  lineno = lineno + 1
   end
   if #comments > 0 then
	  data[file] = comments
   end
   io.close(f)
end

local function get_comments(head)
   local action = {
	  ["file"] = get_comments_from_file,
   }

   local all_comments = {}

   TREE.walk_normal_tree(NODE.get_block_1(head), action, all_comments)

   TREE.disable_active(head)
   TREE.enable_inactive(head)
   TREE.walk_normal_tree(NODE.get_block_2(head), action, all_comments)
   TREE.disable_inactive(head)
   TREE.enable_active(head)

   return all_comments
end
refpolicy_comments.get_comments = get_comments

-------------------------------------------------------------------------------
local function add_comments_to_block(block, parent, file, comments, i)
   local last_comment = #comments
   local prev
   local cur = block
   local cur_lineno = NODE.get_line_number(cur)
   while cur and i <= last_comment do
	  local comment = comments[i]
	  local comment_lineno = comment[2]
	  if comment_lineno < cur_lineno then
		 local kind = comment[1]
		 local new = NODE.create(kind, parent, file, comment_lineno)
		 NODE.set_data(new, {comment[3]})
		 if prev then
			TREE.add_node(prev, new)
		 else
			TREE.add_node(new, block) -- New node is first in the block
			block = new
		 end
		 prev = new
		 i = i + 1
	  else
		 if NODE.has_block(cur) then
			local block1 = NODE.get_block_1(cur)
			local block2 = NODE.get_block_2(cur)
			if block1 then
			   i, block1 = add_comments_to_block(block1, cur, file, comments, i)
			   NODE.set_block(cur, block1)
			end
			if block2 then
			   i, block2 = add_comments_to_block(block2, cur, file, comments, i)
			   NODE.set_block(cur, block2)
			end
		 end
		 prev = cur
		 cur = NODE.get_next(cur)
		 cur_lineno = NODE.get_line_number(cur)
	  end
   end
   if not cur and i <= last_comment and NODE.get_kind(parent) == "file" then
	  for j=i,last_comment do
		 local comment = comments[j]
		 local kind = comment[1]
		 local new = NODE.create(kind, parent, file, comment[2])
		 NODE.set_data(new, {comment[3]})
		 if prev then
			TREE.add_node(prev, new)
		 else
			TREE.add_node(new, block) -- New node is first in the block
			block = new
		 end
		 prev = new
	  end
   end
   return i, block
end

local function add_comments_to_file(node, kind, do_action, do_block, data)
   local file = NODE.get_file_name(node)
   local comments = data[file]
   if not comments then
	  return
   end
   local block = NODE.get_block(node)
   if block then
	  _, block = add_comments_to_block(block, node, file, comments, 1)
	  NODE.set_block(node, block)
   end
end

local function add_comments(head, comments)
   local action = {
	  ["file"] = add_comments_to_file,
   }

   TREE.walk_normal_tree(NODE.get_block_1(head), action, comments)

   TREE.disable_active(head)
   TREE.enable_inactive(head)
   TREE.walk_normal_tree(NODE.get_block_2(head), action, comments)
   TREE.disable_inactive(head)
   TREE.enable_active(head)
end
refpolicy_comments.add_comments = add_comments

-------------------------------------------------------------------------------
local function add_comments_to_policy(head, verbose)
   MSG.verbose_out("\nAdd comments from policy files to policy tree", verbose, 0)

   local comments = get_comments(head)
   add_comments(head, comments)
end
refpolicy_comments.add_comments_to_policy = add_comments_to_policy
-------------------------------------------------------------------------------

return refpolicy_comments
