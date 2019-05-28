local common_table = {}


-------------------------------------------------------------------------------
local function get_sorted_list_of_keys(set)
   local list = {}
   for key,_ in pairs(set) do
      if type(key) ~= "number" then
	 list[#list+1] = key
      end
   end
   table.sort(list)
   return list
end
common_table.get_sorted_list_of_keys = get_sorted_list_of_keys

-------------------------------------------------------------------------------
return common_table
