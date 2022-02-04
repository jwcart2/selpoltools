local messages = {}

-------------------------------------------------------------------------------
-- Helper functions

local function compose_value(v, l, r)
   -- nil, "abc", 1, true, {a,b,c,d,e,...}
   if not v or type(v) ~= "table" then
	  return tostring(v)
   end
   local buf = {}
   for i = 1,#v do
	  if type(v[i]) ~= "table" then
		 buf[#buf+1] = tostring(v[i])
	  else
		 buf[#buf+1] = compose_value(v[i],l,r)
	  end
   end
   return l..table.concat(buf," ")..r
end
messages.compose_value = compose_value

local function compose_table(t, l, r)
   -- {k1=a, k2=b, k3=c, ...}
   if not t or type(t) ~= "table" then
	  return tostring(t)
   end
   local buf = {}
   for k,v in pairs(t) do
	  if type(v) ~= "table" then
		 buf[#buf+1] = tostring(k)..":"..tostring(v)
	  else
		 buf[#buf+1] = tostring(k)..":"..compose_table(v,l,r)
	  end
   end
   return l..table.concat(buf," ")..r
end
messages.compose_table = compose_table

-------------------------------------------------------------------------------
-- Info

local function verbose_out(msg, verbose, level)
   if verbose > level then
	  io.stderr:write(msg,"\n")
   end
end
messages.verbose_out = verbose_out

-------------------------------------------------------------------------------
-- Warnings

local function warning(msg)
   local warn = msg or ""
   io.stderr:write(warn,"\n")
end
messages.warning = warning

local function warnings_buffer_add(warn_buf, msg)
   warn_buf[#warn_buf+1] = msg
end
messages.warnings_buffer_add = warnings_buffer_add

local function warnings_buffer_write(warn_buf)
   if next(warn_buf) then
	  table.sort(warn_buf)
	  for i=1,#warn_buf do
		 warning(warn_buf[i])
	  end
   end
end
messages.warnings_buffer_write = warnings_buffer_write

local function warnings_buffer_write1(verbose, warn_buf)
   if verbose > 0 then
      warnings_buffer_write(warn_buf)
   end
end
messages.warnings_buffer_write1 = warnings_buffer_write1

local function warnings_buffer_write2(verbose, warn_buf)
   if verbose > 1 then
      warnings_buffer_write(warn_buf)
   end
end
messages.warnings_buffer_write2 = warnings_buffer_write2

local function warnings_buffer_write3(verbose, warn_buf)
   if verbose > 2 then
      warnings_buffer_write(warn_buf)
   end
end
messages.warnings_buffer_write3 = warnings_buffer_write3

-------------------------------------------------------------------------------
-- Errors

local function error_message(msg)
   warning(msg)
   os.exit(-1)
end
messages.error_message = error_message

local function error_check(cond, msg)
   if cond then
	  error_message(msg)
   end
end
messages.error_check = error_check

-------------------------------------------------------------------------------
-- Debug

local function debug_time(debug_on)
   if debug_on then
	  io.stderr:write(string.format("Time: %4.2f\n",os.clock()))
   end
end
messages.debug_time = debug_time

local function debug_time_and_gc(debug_on)
   if debug_on then
	  io.stderr:write(string.format("Time: %4.2f   Count (before): %6.0f\n", os.clock(),
									collectgarbage("count")))
	  collectgarbage()
	  io.stderr:write(string.format("Time: %4.2f   Count (after) : %6.0f\n", os.clock(),
									collectgarbage("count")))
   end
end
messages.debug_time_and_gc = debug_time_and_gc

return messages

