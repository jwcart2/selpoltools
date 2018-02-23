local MSG = require "messages"
local LEX = require "common_lex"

local refpolicy_get_class_perm_sets = {}

-------------------------------------------------------------------------------
local lex_get = LEX.get
local lex_SOF = LEX.SOF
local lex_EOF = LEX.EOF
local lex_END = LEX.END

-------------------------------------------------------------------------------
local function get_sorted_list_from_set(set)
   local list = {}
   for s,_ in pairs(set) do
      list[#list+1] = s
   end
   table.sort(list)
   return list
end

local function expand_set(sets, name, inprogress, done)
   local found_set = false
   for e,_ in pairs(sets[name]) do
      if sets[e] then
	 found_set = true
      end
   end
   if found_set then
      local new = {}
      for e,_ in pairs(sets[name]) do
	 if sets[e] then
	    if not done[e] then
	       if inprogress[e] then
		  MSG.warning("Recursive definition in set "..tostring(name)..
				 " involving "..tostring(e))
	       end
	       inprogress[e] = true
	       expand_set(sets, e, inprogress, done)
	       inprogress[e] = false
	    end
	    for e2,_ in pairs(sets[e]) do
	       new[e2] = true
	    end
	 else
	    new[e] = true
	 end
      end
      sets[name] = new
   end
   done[name] = true
end

local function sets_to_flattened_lists(sets)
   local lists = {}
   local done = {}
   for n,_ in pairs(sets) do
      if not done[n] then
	 expand_set(sets, n, {[n]=true}, done)
      end
   end
   for n,set in pairs(sets) do
      lists[n] = get_sorted_list_from_set(set)
   end
   return lists
end

-------------------------------------------------------------------------------
local function warning(lex_state, msg)
      local file = LEX.filename(lex_state) or "(?)"
      local lineno = LEX.lineno(lex_state)
      lineno = lineno and tostring(lineno) or "(?)"
      MSG.warning(tostring(msg).." at line "..lineno.." in "..file)
end

local function get_expected(lex_state, expected)
   local token = LEX.get(lex_state)    
   if token ~= expected then
      warning(lex_state, "Expected \""..tostring(expected).."\" but got \""..
		 tostring(token).."\"")
   end
end

local function get_set(lex_state, class_sets, perm_sets)
   get_expected(lex_state, "(")
   get_expected(lex_state, "`")
   local name = lex_get(lex_state)
   get_expected(lex_state, "'")
   get_expected(lex_state, ",")
   get_expected(lex_state, "`")
   get_expected(lex_state, "{")
   local set = {}
   local token = lex_get(lex_state)
   while token ~= "}" and token ~= lex_END do
      set[token] = true
      token = lex_get(lex_state)
   end
   get_expected(lex_state, "'")
   get_expected(lex_state, ")")

   if string.find(name, "_class_set$") then
      if class_sets[name] then
	 warning(lex_state, "Duplicate definition of class obj_perm_set "..
		    tostring(name))
      end
      class_sets[name] = set
   elseif string.find(name, "_perms$") then
      if perm_sets[name] then
	 warning(lex_state, "Duplicate definition of permission obj_perm_set "..
		    tostring(name))
      end
      perm_sets[name] = set
   else
      warning(lex_state, "Ambiguous definition of obj_perm_set called "..
		 tostring(name))
   end
end

local function parse_obj_perm_sets_file(file)
   local perm_sets = {}
   local class_sets = {}

   if not file then
      return class_sets, perm_sets
   end

   local files = {file}
   local lex_state = LEX.create(files, 4)

   local token = lex_get(lex_state)
   if token ~= lex_SOF then
      MSG.error_message("Expected start of file, found ", " [", tostring(token), "]\n")
   end

   while token ~= lex_END and token ~= lex_EOF do
      if token == "define" then
	 get_set(lex_state, class_sets, perm_sets)
      end
      token = lex_get(lex_state)
   end

   return class_sets, perm_sets
end

-------------------------------------------------------------------------------
local function get_class_perm_sets(active_files)

   local obj_perm_sets_file
   local i = 1
   local last = #active_files
   while not obj_perm_sets_file and i < last do
      if string.find(active_files[i],"/policy/support/obj_perm_sets.spt$") then
	 obj_perm_sets_file = table.remove(active_files, i)
      end
      i = i + 1
   end

   local class_sets_sets, perm_sets_sets =  parse_obj_perm_sets_file(obj_perm_sets_file)
   local class_sets_lists = sets_to_flattened_lists(class_sets_sets)
   local perm_sets_lists = sets_to_flattened_lists(perm_sets_sets)

   return class_sets_lists, perm_sets_lists
end
refpolicy_get_class_perm_sets.get_class_perm_sets = get_class_perm_sets

return refpolicy_get_class_perm_sets
