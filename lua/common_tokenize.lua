
local common_tokenize = {}

--------------------------------------------------------------------------------
local string_find = string.find
local string_sub = string.sub
local string_gmatch = string.gmatch

local TOK_EOL = "<<|EOL|>>"
local TOK_COMMENT = "<<|COMMENT|>>"

local BUFSIZE = 2^13

local function tokenize_file(filename)
   local tokens = {}
   local f = io.open(filename)
   if not f then
	  io.stderr:write("File not found: ",filename,"\n")
	  return tokens
   end
   while true do
	  local chunk, rest = f:read(BUFSIZE, "*line")
	  if not chunk then break end
	  if rest then chunk = chunk..rest end
	  chunk = chunk.."\n"
	  for line in string_gmatch(chunk,"[^\n]*\n") do
		 local e,w,c
		 local pos = 1
		 local len = line and #line or 0
		 while pos <= len do
			c = string_sub(line,pos,pos)
			if string_find(c,"%s") then
			   _,e = string_find(line,"^%s+",pos)
			   pos = e + 1
			elseif string_find(c,"%w") then
			   _,e,w = string_find(line,"^([_%.%-%$%w]+)", pos)
			   tokens[#tokens+1] = w
			   pos = e + 1
			elseif c == "#" then
			   tokens[#tokens+1] = TOK_COMMENT
			   tokens[#tokens+1] = string_sub(line, pos, len-1)
			   pos = len + 1
			elseif c == "$" then
			   _,e,w = string_find(line,"^(%$[_%.%-%$%*%w]+)", pos)
			   tokens[#tokens+1] = w
			   pos = e + 1
			elseif c == "\"" then
			   tokens[#tokens+1] = "\""
			   pos = pos + 1
			   _,e,w = string_find(line,"^([^\"]+)", pos)
			   if w then
				  tokens[#tokens+1] = w
				  pos = e + 1
			   end
			   if pos <= len and string_sub(line,pos,pos) == "\"" then
				  tokens[#tokens+1] = "\""
				  pos = pos + 1
			   end
			elseif c == "/" then
			   local more = true
			   local path = ""
			   while more do
				  more = false
				  _,e,w = string_find(line,"^([%S]+)", pos)
				  if w then
					 path = path..w
					 pos = e + 1
					 if pos <= len and string_sub(line,pos-1,pos) == "\\ " then
						path = path.." "
						pos = pos + 1
						more = true
					 end
				  end
			   end
			   tokens[#tokens+1] = path
			elseif pos == len then
			   tokens[#tokens+1] = c
			   pos = pos + 1
			else
			   if c == "&" or c == "|" or c == "=" or c == "<" or c == ">" then
				  local c2 = string_sub(line,pos+1,pos+1)
				  if c == c2 then
					 tokens[#tokens+1] = c..c2
					 pos = pos + 2
				  else
					 tokens[#tokens+1] = c
					 pos = pos + 1
				  end
			   elseif c == "!" then
				  local c2 = string_sub(line,pos+1,pos+1)
				  if c2 == "=" then
					 tokens[#tokens+1] = "!="
					 pos = pos + 2
				  else
					 tokens[#tokens+1] = c
					 pos = pos + 1
				  end
			   else
				  tokens[#tokens+1] = c
				  pos = pos + 1
			   end
			end
		 end
		 tokens[#tokens+1] = TOK_EOL
	  end
   end
   f:close()
   return tokens
end
common_tokenize.tokenize_file = tokenize_file

--------------------------------------------------------------------------------
return common_tokenize
