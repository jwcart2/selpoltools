local SPT = require "selpoltools"
--local TOK = require "common_tokenize"

local coroutine_yield = coroutine.yield
local string_find = string.find
local string_gmatch = string.gmatch

local common_lex = {}

local TOK_START   = "<<|START|>>"
local TOK_END     = "<<|END|>>"
local TOK_SOF     = "<<|SOF|>>"
local TOK_EOF     = "<<|EOF|>>"
local TOK_EOL     = "<<|EOL|>>"
local TOK_COMMENT = "<<|COMMENT|>>"

common_lex.START   = TOK_START
common_lex.END     = TOK_END
common_lex.SOF     = TOK_SOF
common_lex.EOF     = TOK_EOF
common_lex.EOL     = TOK_EOL
common_lex.COMMENT = TOK_COMMENT

--------------------------------------------------------------------------------
local function tokenize(file_list)
   if not file_list then
      error("Error: No files given")
   end
   local files, total_lines, total_tokens = 0, 0, 0
   for i=1,#file_list do
      local filename = file_list[i]
      local tokens_data = SPT.tokenize_file(filename)
      if not tokens_data then
	 io.stderr:write("No tokens returned from file: ",filename,"\n")
      else
	 local lineno, lines, tokens = 1, 1, 0
	 local tok, tokprev, toknew = nil, nil, nil, nil
	 files = files + 1
	 coroutine_yield(TOK_SOF, 0)
	 coroutine_yield(filename, 0)
	 local j, last = 1, #tokens_data
	 while j <= last do
	    tokprev = tok
	    tok = tokens_data[j]
	    j = j + 1
	    if tok == TOK_COMMENT then
	       j = j + 1 -- Skip comment
	       if tokprev == TOK_EOL then
		  toknew = tokens_data[j]
		  if toknew == TOK_EOL then
		     -- Don't count as a line, but increment lineno
		     lineno = lineno + 1
		     j = j + 1  -- Skip EOL
		  end
	       end
	    elseif tok == TOK_EOL then
	       lineno = lineno + 1
	       lines = lines + 1
	       if tokprev ~= TOK_EOL then
		  lines = lines + 1
	       end
	    elseif tok == "dnl" then
	       toknew = tokens_data[j]
	       while j <= last and toknew ~= TOK_EOL do
		  j = j + 1
		  toknew = tokens_data[j]
	       end
	       if tokprev == TOK_EOL and toknew == TOK_EOL then
		  -- Don't count as a line, but increment lineno
		  lineno = lineno + 1
		  j = j + 1 -- Skip EOL
	       end
	    else
	       coroutine_yield(tok, lineno)
	       tokens = tokens + 1
	    end
	 end
	 coroutine_yield(TOK_EOF, lineno)
	 total_lines = total_lines + lines
	 total_tokens = total_tokens + tokens
      end
   end
   coroutine_yield(TOK_END, {files, total_lines, total_tokens})
end

-------------------------------------------------------------------------------
-- Interface between lexer and parser
--
-- node[1]: token
-- node[2]: file name
-- node[3]: line number

local function create_node(cur)
   -- 1=token, 2=file, 3=lineno
   local new = {false, false, false, nxt=false, prv=false}
   if cur then
      local last = cur.nxt
      new.prv = cur
      new.nxt = cur.nxt
      last.prv = new
      cur.nxt = new
   else
      new.nxt = new
      new.prv = new
   end
   return new
end

local function create_buffer(num_nodes)
   local cur
   for i=1,num_nodes do
      cur = create_node(cur)
   end
   return cur
end

local function set_node(node, token, file, lineno)
   node[1] = token
   node[2] = file
   node[3] = lineno
end

local function lex_create(file_list, num_put_backs)
   local token, file, lineno
   num_put_backs = num_put_backs or 8
   local yylex = coroutine.wrap(tokenize)
   token, _ = yylex(file_list)
   if token ~= TOK_SOF then
      io.stderr:write("No valid files\n")
      return nil
   end
   file, lineno = yylex()
   local cur = create_buffer(num_put_backs)
   set_node(cur, TOK_START, TOK_START, 0)
   local last = cur.nxt
   set_node(last, TOK_SOF, file, lineno)
   return {cur=cur, last=last, yylex=yylex}
end
common_lex.create = lex_create

local function lex_next(state)
   if state.cur[1] ~= TOK_END then
      state.cur = state.cur.nxt
      if state.cur == state.last then
	 local file = state.cur[2]
	 local token, lineno = state.yylex()
	 if token == TOK_SOF then
	    file, lineno = state.yylex()
	 elseif token == TOK_END then
	    file = lineno
	    lineno = 0
	 end
	 state.last = state.cur.nxt
	 local node = state.last
	 node[1] = token
	 node[2] = file
	 node[3] = lineno
      end
   end
end
common_lex.next = lex_next

local function lex_prev(state)
   local cur = state.cur
   local last = state.last
   if cur.prv == last then
      error("LEX: Exceeded back limit\n")
   end
   state.cur = cur.prv
end
common_lex.prev = lex_prev

local function lex_current(state)
   local node = state.cur
   return node[1]
end
common_lex.current = lex_current

local function lex_peek(state)
   local node = state.cur.nxt
   return node[1]
end
common_lex.peek = lex_peek

local function lex_peek_full(state)
   local node = state.cur.nxt
   return node[1], node[2], node[3]
end
common_lex.peek_full = lex_peek_full

local function lex_get(state)
   lex_next(state)
   return state.cur[1]
end
common_lex.get = lex_get

local function lex_get_full(state)
   lex_next(state)
   local node = state.cur
   return node[1], node[2], node[3]
end
common_lex.get_full = lex_get_full

local function lex_lineno(state)
   local node = state.cur
   return node[3]
end
common_lex.lineno = lex_lineno

local function lex_filename(state)
   local node = state.cur
   if type(node[2]) == "table" then
      return "none"
   else
      return node[2]
   end
end
common_lex.filename = lex_filename

local function lex_stats(state)
   local files, total_lines, total_tokens = 0, 0, 0
   if state.cur[1] == TOK_END then
      local node = state.cur
      local st = node[2]
      files, total_lines, total_tokens = st[1], st[2], st[3]
   end
   return files, total_lines, total_tokens
end
common_lex.stats = lex_stats

return common_lex
