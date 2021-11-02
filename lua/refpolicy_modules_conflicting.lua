local MSG = require "messages"

local refpolicy_modules_conflicting = {}

-------------------------------------------------------------------------------
local function list_conflicting_modules(conflicting, modules, verbose)
   if not next(conflicting) then
	  return
   end

   local results = {}
   for name1, module_list in pairs(conflicting) do
	  if modules[name1] == "base" then
		 for name2,_ in pairs(module_list) do
			if modules[name2] == "base" then
			   results[#results+1] = "  "..tostring(name1).." and "..tostring(name2)
			end
		 end
	  end
   end
   if #results > 0 then
	  MSG.warning("Base modules conflicting with other base modules:")
	  for i=1,#results do
		 MSG.warning(results[i])
	  end
   end

   local results = {}
   for name1, module_list in pairs(conflicting) do
	  for name2,_ in pairs(module_list) do
		 if modules[name1] == "base" and modules[name2] ~= "base" then
			results[#results+1] = "  "..tostring(name2).." and "..tostring(name1)
		 elseif modules[name1] ~= "base" and modules[name2] == "base" then
			results[#results+1] = "  "..tostring(name1).." and "..tostring(name2)
		 end
	  end
   end
   if #results > 0 then
	  MSG.warning("Non-base modules conflicting with base modules:")
	  for i=1,#results do
		 MSG.warning(results[i])
	  end
   end

   local results = {}
   for name1, module_list in pairs(conflicting) do
	  if modules[name1] ~= "base" then
		 for name2,_ in pairs(module_list) do
			if modules[name2] ~= "base" then
			   results[#results+1] = "  "..tostring(name1).." and "..tostring(name2)
			end
		 end
	  end
   end
   if #results > 0 then
	  MSG.warning("Non-base modules conflicting with other non-base modules:")
	  for i=1,#results do
		 MSG.warning(results[i])
	  end
   end

end
refpolicy_modules_conflicting.list_conflicting_modules = list_conflicting_modules

-------------------------------------------------------------------------------
return refpolicy_modules_conflicting
