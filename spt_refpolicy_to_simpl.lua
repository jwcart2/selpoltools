#!/usr/bin/lua

-- Expect that if this is in foo/bin, then
-- modules will be in foo/lib/5.X/selpoltools or foo/lib64/5.X/selpoltools
-- Otherwise, this is being run from the build directory
local s,e,prog_path = string.find(arg[0],"(.*)/.*$")
if prog_path then
   if string.find(prog_path,"/bin$") then
      local s,e,vstr = string.find(_VERSION,"(%d%.%d)$")
      s,e,prog_path = string.find(prog_path,"(.*)/bin$")
      local suffix = "/lua/"..tostring(vstr).."/selpoltools"
      package.path = prog_path.."/lib"..suffix.."/?.lua;"..package.path
      package.cpath = prog_path.."/lib"..suffix.."/?.so;"..package.cpath
      package.path = prog_path.."/lib64"..suffix.."/?.lua;"..package.path
      package.cpath = prog_path.."/lib64"..suffix.."/?.so;"..package.cpath
  else
      package.path = prog_path.."/lua/?.lua;"..package.path
      package.cpath = prog_path.."/src/?.so;"..package.cpath
   end
end

local NODE = require "node"
local MSG = require "messages"
local TREE = require "tree"
local GET_FILES = require "common_get_files"

-- Refpolicy
local REFPOL_GET_CONFIG = require "refpolicy_get_config"
local REFPOL_PARSE = require "refpolicy_parse"
local CHECK_REQ = require "refpolicy_check_requires"
local CHECK_STATE = require "refpolicy_check_statements"

local MACROS_COLLECT = require "refpolicy_macros_collect"
local MACROS_CHECK = require "refpolicy_macros_check"
local MACROS_PARAM = require "refpolicy_macros_param_info"
local MACROS_PROCESS = require "refpolicy_macros_process"
local COMMENTS = require "refpolicy_add_comments"
local SIMPL_WRITE = require "simpl_write"

local DECLS = require "refpolicy_declarations"
local MLS = require "refpolicy_mls"

local DEBUG = false

-------------------------------------------------------------------------------
local function print_usage(out, program_name)
   out:write("usage: ",program_name," [-v][-v][-v]"," -d DIR_OUT"," [-p PATH]",
	     " [FILES]","\n")
end

local function print_help(out, program_name)
   print_usage(out, program_name)
   out:write("\n")
   out:write("-d \t  Specify directory to write policy tree.\n")
   out:write("-p \t  Specifify a path to a Refpolicy source tree.\n")
   out:write("-v \t  Set verbosity. Each flag adds 1 to current verbosity.\n",
	     "\t  Verbosity levels are meaningful from 0 to 3\n")
   out:write("\n")
end

-------------------------------------------------------------------------------
-- Input
local path = nil
local all_files, in_files, inactive_files, missing_files, modules

--Output
local out_file = io.stdout
local out_dir = nil

-- Other options
local verbose = 0

local i = 1
while arg[i] and string.sub(arg[i],1,1) == "-" do
   if arg[i] == "--usage" then
      print_usage(io.stderr, arg[0])
      os.exit()
      i = i + 1
   elseif arg[i] == "--help" then
      print_help(io.stderr, arg[0])
      os.exit()
      i = i + 1
   elseif arg[i] == "-d" then
      out_dir = arg[i+1]
      i = i + 2
   elseif arg[i] == "-p" then
      path = arg[i+1]
      if string.sub(path,-1) == "/" then
	 path = string.sub(path,1,-2)
      end
      i = i + 2
   else
      local j = 2
      while j <= #arg[i] do
	 local op = string.sub(arg[i],j,j)
	 if op == "v" then
	    verbose = verbose + 1
	 else
	    io.stderr:write("Invalid option: ",arg[i],"\n")
	    print_usage(io.stderr, arg[0])
	    os.exit(-1)
	 end
	 j = j + 1
      end
      i = i + 1
   end
end

local cdefs, tunables, complete_policy

if not path then
   complete_policy = false
   in_files = {}
   modules = {}
   while i <= #arg do
      in_files[#in_files+1] = arg[i]
      i = i + 1
   end
else
   complete_policy = true
   all_files = REFPOL_GET_CONFIG.get_refpolicy_files_directly(path)
   modules, in_files = REFPOL_GET_CONFIG.get_refpolicy_files(path)
   if in_files then
      inactive_files, missing_files = GET_FILES.get_list_diffs(all_files, in_files)
      if missing_files and next(missing_files) and verbose >= 1 then
	 MSG.warning("The following files were not found:\n")
	 table.sort(missing_files)
	 for i=1,#missing_files do
	    MSG.warning("  "..tostring(missing_files[i]).."\n")
	 end
      end

      if inactive_files and next(inactive_files) and verbose >= 2 then
	 MSG.warning("The following files are inactive:\n")
	 table.sort(inactive_files)
	 for i=1,#inactive_files do
	    MSG.warning("  "..tostring(inactive_files[i]).."\n")
	 end
      end
   else
      local has_corenet = false
      for i=1,#all_files do
	 if string.find(all_files[i],"corenetwork.te",1,true) then
	    has_corenet = true
	 end
      end
      if not has_corenet then
	 MSG.error_message("Need to do \"make conf\" to create corenetwork files")
      end
      in_files = all_files
      inactive_files = {}
   end
   cdefs, tunables = REFPOL_GET_CONFIG.get_build_options(path)
end

if not next(in_files) then
   MSG.warning("No policy files were specified")
   print_usage(io.stderr, arg[0])
   os.exit(-1)
end

-------------------------------------------------------------------------------
local head = REFPOL_PARSE.parse_refpolicy_policy(in_files, inactive_files, cdefs,
												 tunables, verbose)

TREE.disable_inactive(head)

MSG.debug_time_and_gc(DEBUG)

COMMENTS.add_comments_to_policy(head, verbose)

MSG.debug_time_and_gc(DEBUG)

if not complete_policy then
   local file_node = MLS.create_default_mls(16, 1024, head)
   local last = TREE.get_last_node(NODE.get_block(head))
   TREE.add_node(last, file_node)
end

local mdefs, calls, calls_out, inactive_mdefs = MACROS_COLLECT.collect_macros(head,
									      verbose)
if complete_policy then
   MACROS_CHECK.check_macros(mdefs, inactive_mdefs, calls, verbose)
end
MACROS_PARAM.get_macros_param_info(in_files, mdefs)
MACROS_PROCESS.process_macro_calls(mdefs, calls_out, verbose)


MSG.debug_time_and_gc(DEBUG)

SIMPL_WRITE.write_simpl(head, out_dir, verbose)

MSG.debug_time_and_gc(DEBUG)
