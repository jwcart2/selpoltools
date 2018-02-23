local MSG = require "messages"
local COMMON_FILE = require "common_get_files"

local refpolicy_get_config = {}

-------------------------------------------------------------------------------
local function parse_modules_conf(file)
   local names = {}
   local module_list = {}

   local f = io.open(file)
   if not f then
      file = file or "(nil)"
      MSG.warning("Failed to open the module.conf file at "..tostring(file))
      return nil, nil
   end
   for l in f:lines() do
      local s,e
      local c = string.sub(l,1,1)
      if c == "" then
	 -- skip
      elseif c == "#" then
	 -- skip
      else
	 local name, value
	 s,e,name,value = string.find(l,"([%S]*)[=%s]*([%S]*)")
	 if name and value ~= "" and value ~= "off" then
	    names[#names+1] = name
	    module_list[name] = value
	 end
      end
   end
   return names, module_list
end
refpolicy_get_config.parse_modules_conf = parse_modules_conf

local function get_module_files(module_conf_file, prefix, file_list)
   local seen = {}
   local module_names, module_list = parse_modules_conf(module_conf_file)
   if not module_names then
      return nil
   end
   local path = prefix.."/policy/modules/"
   local layer_str = io.popen("dir "..path):read()
   local module_dirs = {}
   for dir in string.gmatch(layer_str,"%w+") do
      module_dirs[dir] = true
   end
   table.sort(module_names)
   for i=1,#module_names do
      local name = module_names[i]
      local value = module_list[name]
      if seen[name] then
	 MSG.warning("Module "..tostring(name).." is listed more than once")
	 value = "off"
      end
      local layer
      seen[name] = true
      if value ~= "off" and value ~= "base" and value ~= "module" then
	 MSG.warning("Module "..tostring(name).." is declared as \""..tostring(value)..
		     "\" which is not valid")
	 value = "off"
      end
      if value == "base" or value == "module" then
	 for dir in pairs(module_dirs) do
	    local f = io.open(path..dir.."/"..name..".te")
	    if f then
	       io.close(f)
	       layer = dir
	       break
	    end
	 end
	 if layer then
	    local base = path..layer.."/"..name
	    file_list[#file_list+1] = base..".fc"
	    file_list[#file_list+1] = base..".if"
	    file_list[#file_list+1] = base..".te"
	 else
	    MSG.warning("Module "..tostring(name).." was not found")
	 end
      end
   end
   return file_list
end

local function get_refpolicy_files(prefix)
   local file_list = {}
   file_list[#file_list+1] = prefix.."/policy/support/obj_perm_sets.spt"
   file_list[#file_list+1] = prefix.."/policy/flask/initial_sids"
   file_list[#file_list+1] = prefix.."/policy/flask/security_classes"
   file_list[#file_list+1] = prefix.."/policy/flask/access_vectors"
   file_list[#file_list+1] = prefix.."/policy/constraints"
   file_list[#file_list+1] = prefix.."/policy/mcs"
   file_list[#file_list+1] = prefix.."/policy/mls"
   file_list[#file_list+1] = prefix.."/policy/users"
   file_list[#file_list+1] = prefix.."/policy/global_tunables"
   file_list[#file_list+1] = prefix.."/policy/global_booleans"
   file_list[#file_list+1] = prefix.."/policy/policy_capabilities"
   file_list[#file_list+1] = prefix.."/policy/support/file_patterns.spt"
   file_list[#file_list+1] = prefix.."/policy/support/ipc_patterns.spt"
   file_list[#file_list+1] = prefix.."/policy/support/misc_patterns.spt"
   file_list[#file_list+1] = prefix.."/policy/support/misc_macros.spt"
   local module_conf = prefix.."/policy/modules.conf"
   file_list = get_module_files(module_conf, prefix, file_list)
   return file_list
end
refpolicy_get_config.get_refpolicy_files = get_refpolicy_files

-------------------------------------------------------------------------------
local function remove_non_modules(file_list)
   local i = 1
   while i < #file_list do
      local f = file_list[i]
      local s1 = string.find(f,"%.xml$")
      local s2 = string.find(f,"%.in$")
      local s3 = string.find(f,"%.m4$")
      local s4 = string.find(f,"Changelog$")
      local s5 = string.find(f,"/%.git")
      local s6 = string.find(f,"/#.*#$")
      local s7 = string.find(f,"~$")
      if s1 or s2 or s3 or s4 or s5 or s6 or s7 then
	 table.remove(file_list,i)
      else
	 i = i + 1
      end
   end
end

local function get_refpolicy_files_directly(prefix)
   local file_list = {}
   file_list[#file_list+1] = prefix.."/policy/flask/initial_sids"
   file_list[#file_list+1] = prefix.."/policy/flask/security_classes"
   file_list[#file_list+1] = prefix.."/policy/flask/access_vectors"
   file_list[#file_list+1] = prefix.."/policy/constraints"
   file_list[#file_list+1] = prefix.."/policy/mcs"
   file_list[#file_list+1] = prefix.."/policy/mls"
   file_list[#file_list+1] = prefix.."/policy/users"
   file_list[#file_list+1] = prefix.."/policy/global_tunables"
   file_list[#file_list+1] = prefix.."/policy/global_booleans"
   file_list[#file_list+1] = prefix.."/policy/policy_capabilities"
   file_list[#file_list+1] = prefix.."/policy/support/file_patterns.spt"
   file_list[#file_list+1] = prefix.."/policy/support/ipc_patterns.spt"
   file_list[#file_list+1] = prefix.."/policy/support/misc_patterns.spt"
   file_list[#file_list+1] = prefix.."/policy/support/misc_macros.spt"
   file_list[#file_list+1] = prefix.."/policy/support/obj_perm_sets.spt"
   local module_prefix = prefix.."/policy/modules"
   COMMON_FILE.get_files_directly(module_prefix, file_list)
   remove_non_modules(file_list)
   return file_list
end
refpolicy_get_config.get_refpolicy_files_directly = get_refpolicy_files_directly

local function add_default_tunables(tunables)
   tunables["hide_broken_symptoms"] = true
   tunables["enables_mls"] = false
   tunables["enables_mcs"] = false
   tunables["distro_debian"] = false
   tunables["distro_gentoo"] = false
   tunables["distro_redhat"] = false
   tunables["distro_suse"] = false
   tunables["distro_ubuntu"] = false
   tunables["init_systemd"] = false
   tunables["direct_sysadm_daemon"] = false
   tunables["enable_ubac"] = false
end

local function add_default_defs(defs)
   defs["mls_num_sens"] = 16
   defs["mls_num_cats"] = 1024
   defs["mcs_num_cats"] = 1024
   defs["num_sens"] = 16 -- compatibility with old patches
   defs["num_cats"] = 1024 -- compatibility with old patches
end
	 
-------------------------------------------------------------------------------
local function parse_build_conf(file)
   local defs = {}
   local tunables = {}

   add_default_tunables(tunables)
   add_default_defs(defs)

   local f = io.open(file)
   if not f then
      file = file or "(nil)"
      error("Failed to open the build.conf file at "..file.."\n")
   end
   for l in f:lines() do
      local c = string.sub(l,1,1)
      if c == "" or c == "#" then
	 -- skip
      else
	 local s,e,name,value = string.find(l,"([%S]*)[=%s]*([%S]*)")
	 if name then
	    if name == "CUSTOM_BUILDOPT" then
	       if value then
		  local len = #l
		  s,e = string.find(l,"=")
		  s = e + 1
		  while s <= len do
		     s,e,value = string.find(l,"([%S]+)",s)
		     tunables[value] = true
		     s = e + 1
		  end
	       end
	    elseif name == "TYPE" then
	       if value == "mls" then
		  tunables["enable_mls"] = true
	       elseif value == "mcs" then
		  tunables["enable_mcs"] = true
	       end
	    elseif name == "DISTRO" then
	       if value == "debian" or value == "gentoo" or value == "redhat" or
		  value == "suse" or value == "ubuntu" then
		     local d = "distro_"..tostring(value)
		     tunables[d] = true
		     if value == "ubuntu" then
			tunables["distro_debian"] = true
		     end
	       end
	    elseif name == "SYSTEMD" then
	       tunables["init_systemd"] = (value == "y")
	    elseif name == "DIRECT_INITRC" then
	       tunables["direct_sysadm_daemon"] = (value == "y")
	    elseif name == "UBAC" then
	       tunables["enable_ubac"] = (value == "y")
	    elseif name == "MLS_SENS" then
	       defs["mls_num_sens"] = tonumber(value)
	    elseif name == "MLS_CATS" then
	       defs["mls_num_cats"] = tonumber(value)
	    elseif name == "MCS_CATS" then
	       defs["mcs_num_cats"] = tonumber(value)
	    else
	       value = value or true
	       defs[name] = value
	    end
	 end
      end
   end
   return defs, tunables
end

local function get_build_options(path)
   local conf_file = path.."/build.conf"
   return parse_build_conf(conf_file)
end
refpolicy_get_config.get_build_options = get_build_options

return refpolicy_get_config
