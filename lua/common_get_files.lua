local SPT = require "selpoltools"

local common_get_files = {}

-------------------------------------------------------------------------------
local function get_files_directly(dir, file_list)
   return SPT.get_files(dir, file_list)
end
common_get_files.get_files_directly = get_files_directly

-------------------------------------------------------------------------------
local function get_list_diffs(fl1, fl2)
   local diff1 = {}
   local diff2 = {}
   local fs1 = {}
   for i=1,#fl1 do
      fs1[fl1[i]] = true
   end
   local fs2 = {}
   for i=1,#fl2 do
      fs2[fl2[i]] = true
   end
   for f1,_ in pairs(fs1) do
      if not fs2[f1] then
	 diff1[#diff1+1] = f1
      end
   end
   for f2,_ in pairs(fs2) do
      if not fs1[f2] then
	 diff2[#diff2+1] = f2
      end
   end
   return diff1, diff2
end
common_get_files.get_list_diffs = get_list_diffs

-------------------------------------------------------------------------------
return common_get_files
