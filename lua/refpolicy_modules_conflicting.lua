local MSG = require "messages"

local refpolicy_modules_conflicting = {}

-------------------------------------------------------------------------------
local function list_conflicting_modules(conflicting, modules, verbose)
   if not next(conflicting) then
	  return
   end

   local warnings = {}
   for name1, module_list in pairs(conflicting) do
	  if modules[name1] == "base" then
		 for name2,_ in pairs(module_list) do
			if modules[name2] == "base" then
			   local msg = "  "..tostring(name1).." and "..tostring(name2)
			   MSG.warnings_buffer_add(warnings, msg)
			end
		 end
	  end
   end
   if #warnings > 0 then
	  MSG.warning("Base modules conflicting with other base modules:")
	  MSG.warnings_buffer_write(warnings)
	  warnings = nil
   end

   warnings = {}
   for name1, module_list in pairs(conflicting) do
	  for name2,_ in pairs(module_list) do
		 if modules[name1] == "base" and modules[name2] ~= "base" then
			local msg = "  "..tostring(name2).." and "..tostring(name1)
			MSG.warnings_buffer_add(warnings, msg)
		 elseif modules[name1] ~= "base" and modules[name2] == "base" then
			local msg = "  "..tostring(name1).." and "..tostring(name2)
			MSG.warnings_buffer_add(warnings, msg)
		 end
	  end
   end
   if #warnings > 0 then
	  MSG.warning("Non-base modules conflicting with base modules:")
	  MSG.warnings_buffer_write(warnings)
	  warnings = nil
   end

   warnings = {}
   for name1, module_list in pairs(conflicting) do
	  if modules[name1] ~= "base" then
		 for name2,_ in pairs(module_list) do
			if modules[name2] ~= "base" then
			   local msg = "  "..tostring(name1).." and "..tostring(name2)
			   MSG.warnings_buffer_add(warnings, msg)
			end
		 end
	  end
   end
   if #warnings > 0 then
	  MSG.warning("Non-base modules conflicting with other non-base modules:")
	  MSG.warnings_buffer_write(warnings)
	  warnings = nil
   end

end
refpolicy_modules_conflicting.list_conflicting_modules = list_conflicting_modules

-------------------------------------------------------------------------------
return refpolicy_modules_conflicting
