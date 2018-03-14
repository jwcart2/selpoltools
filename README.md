# selpoltools
SELinux Policy Tools

USAGE:

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


Examples:

1) Build and run from source directory to analyze a Refpolicy source tree
make
./spt_lint.lua -p PATH_TO_REFPOLICY

2) Build and install locally and run to analyze a Refpolicy source tree
make install DESTDIR=~/local
~/local/usr/bin/spt_lint.lua -p PATH_TO_REFPOLICY

3) Build and run from source directory to analyze a policy.conf file with maximum verbosity
make
./spt_lint.lua -v -v -v policy.conf

4) Build and run from source directiory to analyze the abrt policy module files
make
./spt_lint.lua -v ../refpolicy/policy/modules/contrib/abrt.*

--------------------------------------------------------------------------------
Verbosity Level 0
--------------------------------------------------------------------------------
[Errors]
- Need to do "make conf" to create corenetwork files
- Did not find expected token when parsing
- Improper comma list
- Improper category range
- Invalid MLS range
- Did not get true or false for a boolean value
- Invalid constraint leaf expression
- Did not get expected value for default rule
- Did not get expected value for default_range rule
- Expected a number for sens or cat, but got something else
- Invalid file type for filecon rule
- Invalid protocol for portcon rule
- Ran out of symbols when skipping a block
- Expect some sort of bracket when starting to skip a block
- Found a set definition unexpectedly
- Found a macro definition inside a macro definition
- Found a rule that should not be in the block being parsed
- Expected the start of a file, but got a token
- Failed to open the build.conf file

[Warnings]
- Failed to open the module.conf file
- Stray "/" in fc file [warning, not error]
- Found ifelse block (Which is m4 and not Refpolicy)
- Module name is not the same as filename
- Unexpected symbol found where a rule kind is expected
- Unexpected symbol found where an interface or template is expected
- Unexpected symbol found in *.if file
- Unused macro parameter
- Call has less arguments then needed (and one or more are not optional)
- Call has more arguments then needed (and one or more are not marked as unused)
- Unable to process any more macros [Only occurs if there are circular references]
- Duplicate macro definition in active files
- Location of previous macro definition when there is a duplicate macro definition in active files
- No macro definition for a call
- Macro is defined in inactive policy and is called, at least once, outside of an optional block.
- Module is listed more than once
- Module has an invalid value assigned in modules conf file
- Module name listed in modules conf file not found
- Recursive class permission set definition
- Unexpected token found
- Duplicate definition of class obj_perm_set
- Duplicate definition of permission obj_perm_set
- Ambiguous definition of obj_perm_set called
- Used but not declared (Does not check: class, perm, string, tunable, level, and range)
- Required but not declared (Does not check: class, perm, and string)
- Macro require in inactive policy satisfied external to the module (Does not check: class, perm, and string)

--------------------------------------------------------------------------------
Verbosity Level 1
--------------------------------------------------------------------------------
- Call has more arguments then needed (regardless of whether they are unused or not)
- List of macros and the calls they contain not processed (When unable to process any more macros)
- Duplicate macro definition in inactive files
- Location of previous macro definition when there is a duplicate macro definition in inactive files
- List of places where an undefined macro is called
- Used but not required in non-base modules (Does not check: class, perm, string, tunable, level, and range)
- Required but not used in non-base modules (Does not check: class, perm, and string)
- For inactive macro with require satisfied externally, write out where each require is declared

--------------------------------------------------------------------------------
Verbosity Level 2
--------------------------------------------------------------------------------
- Call has less aguments then needed (regardless whether they are optional or not)
- Macro is defined in inactive policy, but called in active policy
- Used but not declared in module (Does not check: class, perm, string, level, and range)
- Required but not declared in module (Does not check: class, perm, and string)
- Macro require in active policy satisfied external to the module (Does not check: class, perm, and string)
- For active macro with requires satisfied externally, write out where each require is declared
- For all macros with requires satisfied externally, write out where the macro is called
- List of empty macro definitions created for undefined macros
- Used but not required in base modules (Does not check: class, perm, string, tunable, level, and range)
- Required but not used in base modules (Does not check: class, perm, and string)

--------------------------------------------------------------------------------
Verbosity Level 3
--------------------------------------------------------------------------------
- Found MCS categories for gen_context()
- Found MCS categories for gen_user()
- Found argument pass-through (In m4, "$*" passes all arguments to the macro being called)
- Found require block outside of a macro definition. This is not wrong and occurs in a few places, but it is unusual
