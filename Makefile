PREFIX ?= $(DESTDIR)/usr
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib

LUA_VER ?= 5.3
LUA_DIR ?= $(LIBDIR)/lua/$(LUA_VER)
LUA_MODS ?= $(wildcard lua/*.lua)
LUA_CMOD_SRCS ?= $(wildcard src/*.c)
LUA_CMODS ?= $(patsubst %.c,%.so,$(LUA_CMOD_SRCS))

CFLAGS ?= -O2 -Wall -Werror

all: $(LUA_CMODS)

%.so: %.c
	$(CC) $(CFLAGS) -o $@ -shared -fpic $<

install: all
	-mkdir -p $(BINDIR)
	-mkdir -p $(LUA_DIR)/selpoltools
	install -m 755 spt_lint.lua $(BINDIR)
	install -m 644 $(LUA_MODS) $(LUA_DIR)/selpoltools
	install -m 644 $(LUA_CMODS) $(LUA_DIR)/selpoltools

clean:
	-rm -f $(LUA_CMODS)

