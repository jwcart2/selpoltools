local common_string = {}

------------------------------------------------------------------------------
local string_rep = string.rep
local string_find = string.find
local string_sub = string.sub
local math_floor = math.floor
local table_concat = table.concat

------------------------------------------------------------------------------
local function split_string(str, char)
   local buf = {}
   local s,e,p = 1,0,1
   while e do
	  p = e+1
	  s,e = string_find(str,char,p)
	  if e then
		 buf[#buf+1] = string_sub(str,p,s-1)
	  end
   end
   str = string_sub(str,p)
   if str ~= "" then
	  buf[#buf+1] = str
   end
   return buf
end
common_string.split_string = split_string

local function wrap_string(str, max)
   local buf = {}
   if #str <= max then
	  buf[#buf+1] = str
   else
	  local s,e = string_find(str,"%S%s")
	  local pad = e and string_rep(" ",e) or ""
	  if e and e > max/5 then
		 pad = string.rep(" ",math_floor(max/5))
	  end
	  while str and #str > max do
		 s,e = string_find(str,"%s+")
		 local last_s,last_e = s,e
		 while e and e < max do
			last_s,last_e = s,e
			s,e = string_find(str,"%s+",e+1)
		 end
		 if not last_s then
			-- No spaces found
			buf[#buf+1] = str
			str = ""
		 elseif s and e and e >= max and s <= max then
			-- whitespace stradles the max
			buf[#buf+1] = string_sub(str,1,s-1)
			str = pad..string_sub(str,e+1)
		 elseif last_s == 1 then
			-- No spaces found after the pad and before max
			if not s then
			   -- no whitspace found
			   s = #str+1
			   e = #str+1
			   pad = ""
			end
			extra = s-1-max
			if extra > last_e then
			   extra = last_e
			end
			buf[#buf+1] = string_sub(str,extra+1,s-1)
			str = pad..string_sub(str,e+1)
		 else
			buf[#buf+1] = string_sub(str,1,last_s-1)
			str = pad..string_sub(str,last_e+1)
		 end
	  end
	  if str and str ~= "" then
		 buf[#buf+1] = str
	  end
   end
   return buf
end
common_string.wrap_string = wrap_string

------------------------------------------------------------------------------
local function get_new_format(indent, width)
   return {indent=indent, width=width, depth=0, pad=""}
end
common_string.get_new_format = get_new_format

local function format_increase_depth(format)
   format.depth = format.depth + 1
   format.pad = string_rep(" ",format.indent*format.depth)
end
common_string.format_increase_depth = format_increase_depth

local function format_decrease_depth(format)
   format.depth = format.depth - 1
   if format.depth <= 0 then
	  format.depth = 0
	  format.pad = ""
   else
	  format.pad = string_rep(" ",format.indent*format.depth)
   end
end
common_string.format_decrease_depth = format_decrease_depth

local function format_get_max(format)
   local _,padlen = string_find(format.pad,"%S%s")
   padlen = padlen or 0
   return format.width - padlen
end
common_string.format_get_max = format_get_max

------------------------------------------------------------------------------

local function add_to_buffer(buf, format, str)
   if not str then
	  return
   end
   local max = format_get_max(format)
   if #str > max then
	  local buf2 = split_string(str,"\n")
	  for i=1,#buf2 do
		 local v = buf2[i]
		 local buf3 = wrap_string(v,max)
		 for j=1,#buf3 do
			local w = buf3[j]
			buf[#buf+1] = format.pad..w
			buf[#buf+1] = "\n"
		 end
	  end
   else
	  buf[#buf+1] = format.pad..str
	  buf[#buf+1] = "\n"
   end
end
common_string.add_to_buffer = add_to_buffer

local function convert_to_buffer(format, str)
   if not str then
	  return
   end
   local buf = {}
   add_to_buffer(buf, format, str)
   return buf
end
common_string.convert_to_buffer = convert_to_buffer

local function write(out, format, str)
   if not str then
	  return
   end
   local buf = convert_to_buffer(format, str)
   for i = 1,#buf do
	  out:write(buf[i])
   end
end
common_string.write = write

------------------------------------------------------------------------------
return common_string
