local MSG = require "messages"
local LEX = require "common_lex"
local MACRO = require "node_macro"

local refpolicy_macros_param_info = {}

-------------------------------------------------------------------------------
local string_find = string.find

-------------------------------------------------------------------------------
local function get_param_info_from_file(file, defs)
   local f = io.open(file)
   if not f then
      file = file or "(nil)"
      MSG.warning("Failed to open file: "..tostring(file))
      return
   end
   local optional = 0
   local unused = 0
   for l in f:lines() do
      local s,e
      local c = string.sub(l,1,1)
      if c == "" then
	 -- skip
      elseif c == "#" then
	 if string_find(l, "optional=\"true\"") then
	    optional = optional + 1
	 end
	 if string_find(l, "unused=\"true\"") then
	    unused = unused + 1
	 end
      else
	 if c == "i" or c == "t" then
	    local name = nil
	    s,e,name = string_find(l, "^interface%(`([^']+)")
	    if not name then
	       s,e,name = string_find(l, "^template%(`([^']+)")
	    end
	    if name and defs[name] then
	       MACRO.set_def_param_info(defs[name], {optional, unused})
	    end
	 end
	 optional = 0
	 unused = 0
      end
   end	  
end

-------------------------------------------------------------------------------
local function get_macros_param_info(active_files, defs)
   for _,file in pairs(active_files) do
      local _,_,ext = string_find(file,"%.(%a%a)$")
      if ext == "if" then
	 get_param_info_from_file(file, defs)
      end
   end	 
end
refpolicy_macros_param_info.get_macros_param_info = get_macros_param_info

return refpolicy_macros_param_info
