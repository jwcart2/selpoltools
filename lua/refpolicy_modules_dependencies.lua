local MSG = require "messages"

local refpolicy_modules_dependencies = {}

-------------------------------------------------------------------------------
local function list_dependent_modules(dependencies, modules, verbose)
   if not next(dependencies) then
	  return
   end

   local num_mods = 0
   local num_base = 0
   local num_other = 0
   local num_contrib = 0
   for i,v in pairs(modules) do
	  num_mods = num_mods + 1
	  if v == "base" then
		 num_base = num_base + 1
	  elseif v == "contrib" then
		 num_contrib = num_contrib + 1
	  else
		 num_other = num_other + 1
	  end
   end

   local required = {}
   for n1,dep_data in pairs(dependencies) do
	  for n2,_ in pairs(dep_data) do
		 required[n2] = required[n2] or {}
		 required[n2][n1] = true
	  end
   end

   -- Base modules depending on other base modules is normal and expected
   if verbose >= 3 then
	  local warnings = {}
	  for name1, module_list in pairs(required) do
		 if modules[name1] == "base" then
			local dependent = {}
			for name2,_ in pairs(module_list) do
			   if modules[name2] == "base" then
				  dependent[#dependent+1] = tostring(name2)
			   end
			end
			if #dependent > 0 then
			   table.sort(dependent)
			   local s = table.concat(dependent,", ")
			   local msg = "  "..tostring(name1).." ["..tostring(#dependent).."/"..tostring(num_base).."]: ("..s..")"
			   MSG.warnings_buffer_add(warnings, msg)
			end
		 end
	  end
	  if next(warnings) then
		 MSG.warning("Base modules needed by other base modules:")
		 MSG.warnings_buffer_write(warnings)
	  end
   end

   -- Non-base modules depending on base modules is normal and expected
   if verbose == 3 then
	  local warnings = {}
	  for name1, module_list in pairs(required) do
		 if modules[name1] == "base" then
			local dependent = {}
			for name2,_ in pairs(module_list) do
			   if modules[name2] ~= "base" then
				  dependent[#dependent+1] = tostring(name2)
			   end
			end
			if #dependent > 0 then
			   table.sort(dependent)
			   local s = table.concat(dependent,", ")
			   local msg = "  "..tostring(name1).." ["..tostring(#dependent).."/"..tostring(num_other+num_contrib).."]: ("..s..")"
			   MSG.warnings_buffer_add(warnings, msg)
			end
		 end
	  end
	  if next(warnings) then
		 MSG.warning("Base modules needed by non-base modules:")
		 MSG.warnings_buffer_write(warnings)
	  end
   end

   -- Non-base, non-contrib modules depending on other non-base, non-contrib modules
   -- is sort of normal
   if verbose >= 2 then
	  local warnings = {}
	  for name1, module_list in pairs(required) do
		 if modules[name1] == "other" then
			local dependent = {}
			for name2,_ in pairs(module_list) do
			   if modules[name2] == "other" then
				  dependent[#dependent+1] = tostring(name2)
			   end
			end
			if #dependent > 0 then
			   table.sort(dependent)
			   local s = table.concat(dependent,", ")
			   local msg
			   if #dependent <= 10 or verbose == 3 then
				  msg = "  "..tostring(name1).." ["..tostring(#dependent).."/"..tostring(num_other).."]: ("..s..")"
			   else
				  msg = "  "..tostring(name1)..": ["..tostring(#dependent).."/"..tostring(num_other).."]: [Use -v -v -v to see list]"
			   end
			   MSG.warnings_buffer_add(warnings, msg)
			end
		 end
	  end
	  if next(warnings) then
		 MSG.warning("Non-base, non-contrib modules needed by other non-base, non-contrib modules:")
		 MSG.warnings_buffer_write(warnings)
	  end
   end

   -- Contrib modules depending on non-base, non-contrib modules is sort of normal
   if verbose >= 2 then
	  local warnings = {}
	  for name1, module_list in pairs(required) do
		 if modules[name1] == "other" then
			local dependent = {}
			for name2,_ in pairs(module_list) do
			   if modules[name2] == "contrib" then
				  dependent[#dependent+1] = tostring(name2)
			   end
			end
			if #dependent > 0 then
			   table.sort(dependent)
			   local s = table.concat(dependent,", ")
			   local msg
			   if #dependent <= 10 or verbose == 3 then
				  msg = "  "..tostring(name1).." ["..tostring(#dependent).."/"..tostring(num_contrib).."]: ("..s..")"
			   else
				  msg = "  "..tostring(name1)..": ["..tostring(#dependent).."/"..tostring(num_contrib).."]: [Use -v -v -v to see list]"
			   end
			   MSG.warnings_buffer_add(warnings, msg)
			end
		 end
	  end
	  if next(warnings) then
		 MSG.warning("Non-base, non-contrib modules needed by contrib modules:")
		 MSG.warnings_buffer_write(warnings)
	  end
   end

   -- Contrib modules depending on other contrib modules is not the best practice
   if verbose >= 1 then
	  local warnings = {}
	  for name1, module_list in pairs(required) do
		 if modules[name1] == "contrib" then
			local dependent = {}
			for name2,_ in pairs(module_list) do
			   if modules[name2] == "contrib" then
				  dependent[#dependent+1] = tostring(name2)
			   end
			end
			if #dependent > 0 then
			   table.sort(dependent)
			   local s = table.concat(dependent,", ")
			   local msg
			   if #dependent <= 10 or verbose == 3 then
				  msg = "  "..tostring(name1).." ["..tostring(#dependent).."/"..tostring(num_contrib).."]: ("..s..")"
			   else
				  msg = "  "..tostring(name1)..": ["..tostring(#dependent).."/"..tostring(num_contrib).."]: [Use -v -v -v to see list]"
			   end
			   MSG.warnings_buffer_add(warnings, msg)
			end
		 end
	  end
	  if next(warnings) then
		 MSG.warning("Contrib modules needed by other contrib modules:")
		 MSG.warnings_buffer_write(warnings)
	  end
   end

   -- Base modules depending on non-base modules is a problem
   local warnings = {}
   for name1, module_list in pairs(required) do
	  if modules[name1] ~= "base" then
		 local dependent = {}
		 for name2,_ in pairs(module_list) do
			if modules[name2] == "base" then
			   dependent[#dependent+1] = tostring(name2)
			end
		 end
		 if #dependent > 0 then
			table.sort(dependent)
			local s = table.concat(dependent,", ")
			local msg
			if #dependent <= 10 or verbose == 3 then
			   msg = "  "..tostring(name1).." ["..tostring(#dependent).."/"..tostring(num_contrib+num_other).."]: ("..s..")"
			else
			   msg = "  "..tostring(name1)..": ("..tostring(#dependent).."/"..tostring(num_contrib+num_other).."]: [Use -v -v -v to see list]"
			end
			MSG.warnings_buffer_add(warnings, msg)
		 end
	  end
   end
   if next(warnings) then
	  MSG.warning("Non-base modules needed by base modules:")
	  MSG.warnings_buffer_write(warnings)
   end
end
refpolicy_modules_dependencies.list_dependent_modules = list_dependent_modules

-------------------------------------------------------------------------------
return refpolicy_modules_dependencies
