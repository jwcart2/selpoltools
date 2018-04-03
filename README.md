SELinux Policy Tools (selpoltools)

INTRODUCTION

	The selpoltools are a collection of policy tools for SELinux.
	spt_lint.lua parses a Refpolicy source tree or the given files and reports
	potential problems with the policy. spt_tree.lua parses a Refpolicy source
	tree or the given policy files and prints out a tree representation of policy.

	spt_lint.lua can detect problems such as:
	- Unused macro parameters
	- Calls that have more or less arguments then needed
	- Identifiers used in macros but not declared
	- Identifiers used in macros but not required
	- Identifiers required in macros but not declared
	- Identifiers required in macros but not used
	- Macros that will appear in policy even though their module is marked "off"
	  in modules.conf.

	spt_tree.lua can be useful for debugging (mostly debugging spt_lint.lua so far).

	The Refpolicy source tree must have had "make conf" run to create the
	policy/modules.conf, policy/modules/kernel/corenetwork.te, and
	policy/modules/kernel/corenetwork.if files.

DEPENDENCIES

	gcc, lua, and lua-devel

BUILD

	Run "make" or "make install"

USAGE

	spt_lint.lua [-v][-v][-v] [-p PATH] [FILES]
	  -p  Specify a path to a Refpolicy source tree.
	  -v  Set verbosity. Each flag adds 1 to current verbosity.
	      Verbosity levels are meaningful from 0 to 3
	  PATH is the path to the policy tree
	  FILES are the policy files to check if not providing a path to a policy tree


	spt_tree.lua [-v][-v][-v] [-p PATH] [FILES]
	  -p  Specify a path to a Refpolicy source tree.
	  -v  Set verbosity. Each flag adds 1 to current verbosity.
	      Verbosity levels are meaningful from 0 to 3
	  PATH is the path to the policy tree
	  FILES are the policy files to check if not providing a path to a policy tree

EXAMPLES

	1) Build and run from source directory to analyze a Refpolicy source tree
	  $ make
	  $ ./spt_lint.lua -p PATH_TO_REFPOLICY

	2) Build and install locally and run to analyze a Refpolicy source tree
	  $ make install DESTDIR=~/local
	  $ ~/local/usr/bin/spt_lint.lua -p PATH_TO_REFPOLICY

	3) Build and run from source directory to analyze a policy.conf file with
	   maximum verbosity
	  $ make
	  $ ./spt_lint.lua -v -v -v policy.conf

	4) Build and run from source directiory to analyze the abrt policy module files
	  $ make
	  $ ./spt_lint.lua -v ../refpolicy/policy/modules/contrib/abrt.*

DOCUMENTATION

	See docs directory
