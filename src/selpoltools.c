#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <error.h>
#include <errno.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define SPT_FS_MT "spt_fs_mt"

#define SPT_TOK_MT "spt_tok_mt"
#define SPT_TOK_BUF_SZ 1024
#define SPT_TOK_EOL     "<<|EOL|>>"
#define SPT_TOK_COMMENT "<<|COMMENT|>>"

/* Tokenize File */

static int spt_tok_gc(lua_State *L)
{
	FILE **f;
	f = (FILE **)lua_touserdata(L, 1);
	if (*f) {
		fclose(*f);
	}
	return 0;
}

static int spt_tok_create_mt(lua_State *L)
{
	luaL_newmetatable(L, SPT_TOK_MT);
	lua_pushcfunction(L, spt_tok_gc);
	lua_setfield(L, -2, "__gc");
	return 1;
}

static inline void spt_tok_add(lua_State *L, char *tok)
{
	int index = luaL_len(L, 1);
	index++;
	lua_pushstring(L, tok);
	lua_seti(L, 1, index);
}

void spt_tok_tokenize_helper(lua_State *L, const char *filename)
{
	FILE **file;
	char buf[SPT_TOK_BUF_SZ];
	char *bp, *end;
	int c;
	int c2;
	int escape;

	file = (FILE**) lua_newuserdata(L, sizeof(FILE*));
	luaL_getmetatable(L, SPT_TOK_MT);
	lua_setmetatable(L, -2);

	*file = fopen(filename, "r");
	if (!*file) {
		luaL_error(L, "Failed to open file %s: %s", filename, strerror(errno));
		return;
	}

	end = buf + SPT_TOK_BUF_SZ;

	c = fgetc(*file);

	while (c != EOF) {
		bp = buf;
		while (c == ' ' || c == '\t')
			c = fgetc(*file);

		if (c == '\n') {
			spt_tok_add(L, SPT_TOK_EOL);
			c = fgetc(*file);
		} else if (isalnum(c)) {
			do {
				*bp++ = c;
				c = fgetc(*file);
			} while ((isalnum(c) || c == '_' || c == '.' || c == '-' ||
				  c == '$') && bp < end);
			*bp = '\0';
			spt_tok_add(L, buf);
		} else if (c == '#') {
			do {
				*bp++ = c;
				c = fgetc(*file);
			} while (c != '\n' && c != EOF && bp < end);
			*bp = '\0';
			spt_tok_add(L, SPT_TOK_COMMENT);
			spt_tok_add(L, buf);
		} else if (c == '"') {
			spt_tok_add(L, "\"");

			do {
				*bp++ = c;
				c = fgetc(*file);
			} while (c != '"' && c != EOF && bp < end);
			*bp = '\0';
			spt_tok_add(L, buf);
			spt_tok_add(L, "\"");
			c = fgetc(*file);
		} else if (c == '/') {
			do {
				*bp++ = c;
				escape = (c == '\\') ? 1 : 0;
				c = fgetc(*file);
			} while ((escape || c != ' ') && c != '\t' &&
				 c != EOF && bp < end);
			*bp = '\0';
			spt_tok_add(L, buf);
		} else {
			*bp++ = c;
			if (c == '&' || c == '|' || c == '=' || c == '<' || c == '>') {
				c2 = fgetc(*file);
				if (c == c2) {
					*bp++ = c2;
					c = fgetc(*file);
				} else {
					c = c2;
				}
				*bp = '\0';
				spt_tok_add(L, buf);
			} else if (c == '!') {
				c = fgetc(*file);
				if (c == '=') {
					*bp++ = c;
					c = fgetc(*file);
				}
				*bp = '\0';
				spt_tok_add(L, buf);
			} else if (c == '$') {
				c = fgetc(*file);
				if (isdigit(c) || (c == '*')) {
					do {
						*bp++ = c;
						c = fgetc(*file);
					} while ((isalnum(c) || c == '_' || c == '.' ||
						  c == '-' || c == '$') && bp < end);
					*bp = '\0';
					spt_tok_add(L, buf);
				} else {
					*bp = '\0';
					spt_tok_add(L, buf);
				}
			} else {
				*bp = '\0';
				spt_tok_add(L, buf);
				c = fgetc(*file);
			}
		}
	}

	fclose(*file);
	*file = NULL;
	lua_pop(L, 1); /* pop file */
}

static int spt_tok_tokenize(lua_State *L)
{
	const char *file = luaL_checkstring(L, 1);
	lua_pop(L, 1);
	lua_newtable(L);
	spt_tok_tokenize_helper(L, file);
	return 1;
}

/* Recursively get files in directory */

static int spt_fs_gc(lua_State *L)
{
	DIR **d;
	d = (DIR **)lua_touserdata(L, 1);
	if (*d) {
		closedir(*d);
	}
	return 0;
}

static int spt_fs_create_mt(lua_State *L)
{
	luaL_newmetatable(L, SPT_FS_MT);
	lua_pushcfunction(L, spt_fs_gc);
	lua_setfield(L, -2, "__gc");
	return 1;
}

static void spt_fs_get_files_helper(lua_State *L, const char *dirpath)
{
	DIR **dir;
	struct dirent *dp;
	struct stat st;
	const char *path;
	char *pathformat = "%s%s";
	int index;
	int rc;

	dir = (DIR**) lua_newuserdata(L, sizeof(DIR*));
	luaL_getmetatable(L, SPT_FS_MT);
	lua_setmetatable(L, -2);

	*dir = opendir(dirpath);
	if (!*dir) {
		luaL_error(L, "Failed to open dir %s: %s", dirpath, strerror(errno));
		return;
	}

	if (dirpath[strlen(dirpath)-1] != '/') {
		pathformat = "%s/%s";
	}

	dp = readdir(*dir);
	while (dp) {
		if (strcmp(dp->d_name, ".") == 0 || strcmp(dp->d_name, "..") == 0) {
			dp = readdir(*dir);
			continue;
		}

		path = lua_pushfstring(L, pathformat, dirpath, dp->d_name);

		rc = stat(path, &st);
		if (rc != 0) {
			const char *str = lua_pushfstring(L, "Failed to stat %s: %s",
							  path, strerror(errno));
			luaL_error(L, str);
			return;
		}
		if (st.st_mode & S_IFDIR) {
			spt_fs_get_files_helper(L, path);
			lua_pop(L,1); /* pop path */
		} else if (st.st_mode & S_IFREG) {
			index = luaL_len(L, 1);
			index++;
			lua_seti(L, 1, index);
		} else {
			lua_pop(L,1); /* pop path */
		}

		dp = readdir(*dir);
	}

	closedir(*dir);
	*dir = NULL;
	lua_pop(L,1); /* pop dir */
}

static int spt_fs_get_files(lua_State *L)
{
	const char *dirpath = luaL_checkstring(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	lua_remove(L, 1);
	spt_fs_get_files_helper(L, dirpath);
	return 1;
}

static int spt_fs_make_dir(lua_State *L)
{
	int res;
	const char *dirpath = luaL_checkstring(L, 1);
	lua_remove(L, 1);
	res = mkdir(dirpath, S_IWUSR|S_IRUSR|S_IXUSR|S_IRGRP|S_IXGRP|S_IROTH|S_IXOTH);
	if (res < 0) {
		lua_pushboolean(L, 0);
		lua_pushfstring(L, "Failed to create dir %s: %s\n",
				dirpath, strerror(errno));

		return 2;
	}
	lua_pushboolean(L, 1);
	return 1;
}

/* Lua Library */

static const struct luaL_Reg selpoltools[] = {
	{"get_files", spt_fs_get_files},
	{"tokenize_file", spt_tok_tokenize},
	{"make_dir", spt_fs_make_dir},
	{NULL, NULL},
};


/* gcc -o selpoltools.so -shared -fpic selpoltools.c */
int luaopen_selpoltools(lua_State *L)
{
	spt_fs_create_mt(L);
	spt_tok_create_mt(L);

	luaL_newlib(L, selpoltools);

	return 1;
}
