local MSG = require "messages"
local NODE = require "node"

local tree_write = {}

-------------------------------------------------------------------------------
-- Write Tree
-------------------------------------------------------------------------------
local DEBUG_MACROS = false

local function write_node(out, node, indent)
   local kind = NODE.get_kind(node) or "<[NONE]>"
   local path = NODE.get_file_name(node) or "<[NONE]>"
   local s,e,filename = string.find(path,"/([%w%_%-%.]+)$")
   filename = filename or path
   local lineno = NODE.get_line_number(node) or "<[NONE]>"
   local data = NODE.get_data(node) or {}
   local pad = string.rep("  ", indent)
   if kind == "call" then
	  local name = data[1] or "<[NONE]>"
	  out:write(pad,tostring(kind)," | ",tostring(name)," | ",tostring(#data)," | ",
				tostring(filename),":",tostring(lineno),"\n")
	  local orig_args = data[2] or {}
	  local buf = {}
	  for i=1,#orig_args do
		 if type(orig_args[i]) ~= "table" then
			buf[#buf+1] = orig_args[i]
		 else
			buf[#buf+1] = MSG.compose_table(orig_args[i],"{","}")
		 end
	  end
	  out:write(pad,"  (",table.concat(buf,","),")\n")
	  if DEBUG_MACROS then
		 local orig_args = data[2] or {}
		 local exp_args = data[3] or {}
		 local decls = data[4] or {}
		 if next(orig_args) then
			out:write(pad,"  CALL ORIG ARGS:",MSG.compose_table(orig_args,"{","}"),"\n")
		 end
		 if next(exp_args) then
			out:write(pad,"  CALL EXP ARGS :",MSG.compose_table(exp_args,"{","}"),"\n")
		 end
		 if next(decls) then
			out:write(pad,"  CALL DECLS    :",MSG.compose_table(decls,"{","}"),"\n")
		 end
	  end
   elseif kind == "macro" then
	  local name = data[1] or "<[NONE]>"
	  out:write(pad,tostring(kind)," | ",tostring(name)," | ",
				tostring(filename),":",tostring(lineno),"\n")
	  if DEBUG_MACROS then
		 local flavors = data[2] or {}
		 local exp_args = data[3] or {}
		 local decls = data[4] or {}
		 local used = data[5] or {}
		 local requires = data[6] or {}
		 if next(flavors) then
			out:write(pad,"  DEF ORIG FLAVORS:",MSG.compose_table(flavors,"{","}"),"\n")
		 end
		 if next(exp_args) then
			out:write(pad,"  DEF EXP ARGS    :",MSG.compose_table(exp_args,"{","}"),"\n")
		 end
		 if next(decls) then
			out:write(pad,"  DEF DECLS       :",MSG.compose_table(decls,"{","}"),"\n")
		 end
		 if next(used) then
			out:write(pad,"  DEF USED        :",MSG.compose_table(used,"{","}"),"\n")
		 end
		 if next(requires) then
			out:write(pad,"  DEF REQUIRES    :",MSG.compose_table(requires,"{","}"),"\n")
		 end
	  end
   else
	  out:write(pad,tostring(kind)," | ",tostring(#data)," | ",
				tostring(filename),":",tostring(lineno),"\n")
   end
end

local function write_block(out, block, indent)
   local cur = block
   local pad = string.rep("  ", indent)
   while cur do
	  write_node(out, cur, indent)
	  if NODE.has_block(cur) then
		 local block1 = NODE.get_block_1(cur)
		 local block2 = NODE.get_block_2(cur)
		 if block1 then
			out:write(pad, "block-1 {\n")
			write_block(out, block1, indent+1)
			out:write(pad, "}\n")
		 end
		 if block2 then
			out:write(pad, "block-2 {\n")
			write_block(out, block2, indent+1)
			out:write(pad, "}\n")
		 end
	  end
	  cur = NODE.get_next(cur)
   end
end
tree_write.write_block = write_block

local function write_tree(out, head)
   write_node(out, head, 0)
   out:write("block-1 {\n")
   write_block(out, NODE.get_block_1(head), 1)
   out:write("}\n")
   out:write("block-2 {\n")
   write_block(out, NODE.get_block_2(head), 1)
   out:write("}\n")
end
tree_write.write_tree = write_tree

-------------------------------------------------------------------------------
return tree_write
