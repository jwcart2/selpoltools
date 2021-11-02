local node = {}

-------------------------------------
-- Generic tree node
-- 1  - Kind
-- 2  - Pointer to Parent
-- 3  - Pointer to next node
-- 4  - File name
-- 5  - Line number
-- 6  - Node Data
-- 7  - Block Data
--      - 1 - Block 1 (or then block)
--      - 2 - Block 2 (or else block)
-------------------------------------

local function create(kind, parent, file, line)
   return {kind, parent, false, file, line, false, false}
end
node.create = create

local function get_kind(cur)
   return cur and cur[1]
end
node.get_kind = get_kind

local function set_kind(cur, kind)
   if not cur then
	  return
   end
   cur[1] = kind
end
node.set_kind = set_kind

local function get_parent(cur)
   return cur and cur[2]
end
node.get_parent = get_parent

local function set_parent(cur, parent)
   if not cur then
	  return
   end
   cur[2] = parent
end
node.set_parent = set_parent

local function get_next(cur)
   return cur and cur[3]
end
node.get_next = get_next

local function set_next(cur, next)
   if not cur then
	  return
   end
   cur[3] = next
end
node.set_next = set_next

local function get_file_name(cur)
   return cur and cur[4]
end
node.get_file_name = get_file_name

local function set_file_name(cur, file_name)
   if not cur then
	  return
   end
   cur[4] = file_name
end
node.set_file_name = set_file_name

local function get_line_number(cur)
   return cur and cur[5]
end
node.get_line_number = get_line_number

local function set_line_number(cur, line_number)
   if not cur then
	  return
   end
   cur[5] = line_number
end
node.set_line_number = set_line_number

local function get_data(cur)
   return cur and cur[6]
end
node.get_data = get_data

local function set_data(cur, data)
   if not cur then
	  return
   end
   cur[6] = data
end
node.set_data = set_data

local function has_block(cur)
   return cur and cur[7]
end
node.has_block = has_block

local function get_block_1(cur)
   return cur and cur[7] and cur[7][1]
end
node.get_block_1 = get_block_1
node.get_block = get_block_1
node.get_then_block = get_block_1

local function set_block_1(cur, block)
   if not cur then
	  return
   end
   if not cur[7] then
	  cur[7] = {false, false}
   end
   cur[7][1] = block
end
node.set_block_1 = set_block_1
node.set_block = set_block_1
node.set_then_block = set_block_1

local function get_block_2(cur)
   return cur and cur[7] and cur[7][2]
end
node.get_block_2 = get_block_2
node.get_else_block = get_block_2

local function set_block_2(cur, block)
   if not cur then
	  return
   end
   if not cur[7] then
	  cur[7] = {false, false}
   end
   cur[7][2] = block
end
node.set_block_2 = set_block_2
node.set_else_block = set_block_2

return node
