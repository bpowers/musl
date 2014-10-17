#
# Makefile for musl (requires GNU make)
#
# This is how simple every makefile should be...
# No, I take that back - actually most should be less than half this size.
#
# Use config.mak to override any of the following variables.
# Do not make changes here.
#

exec_prefix = /usr/local
bindir = $(exec_prefix)/bin

prefix = /usr/local
includedir = $(prefix)/include
libdir = $(prefix)/lib
syslibdir = /lib

# only include sources required for the correct function of malloc,
# realloc & free
SRCS = $(sort $(wildcard src/mman/*.c src/malloc/*.c arch/$(ARCH)/src/*.c)) src/internal/syscall_ret.c
OBJS = $(SRCS:.c=.o) src/internal/$(ARCH)/syscall.o
LOBJS = $(OBJS:.o=.lo)
GENH = include/bits/alltypes.h
GENH_INT = src/internal/version.h
IMPH = src/internal/stdio_impl.h src/internal/pthread_impl.h src/internal/libc.h

LDFLAGS = 
LIBCC = -lgcc
CPPFLAGS =
CFLAGS = -Os -pipe
CFLAGS_C99FSE = -std=c99 -ffreestanding -nostdinc

CFLAGS_ALL = $(CFLAGS_C99FSE)
CFLAGS_ALL += -D_XOPEN_SOURCE=700 -I./arch/$(ARCH) -I./src/internal -I./include
CFLAGS_ALL += $(CPPFLAGS) $(CFLAGS)
CFLAGS_ALL_STATIC = $(CFLAGS_ALL)
CFLAGS_ALL_SHARED = $(CFLAGS_ALL) -fPIC -DSHARED

AR      = $(CROSS_COMPILE)ar
RANLIB  = $(CROSS_COMPILE)ranlib
INSTALL = ./tools/install.sh

ARCH_INCLUDES = $(wildcard arch/$(ARCH)/bits/*.h)
ALL_INCLUDES = $(sort $(wildcard include/*.h include/*/*.h) $(GENH) $(ARCH_INCLUDES:arch/$(ARCH)/%=include/%))

STATIC_LIBS = lib/musl-malloc.a
SHARED_LIBS = lib/musl-malloc.so
ALL_LIBS = $(STATIC_LIBS) $(SHARED_LIBS)

-include config.mak

all: $(ALL_LIBS) $(ALL_TOOLS)

install: install-libs

clean:
	rm -f crt/*.o
	rm -f $(OBJS)
	rm -f $(LOBJS)
	rm -f $(ALL_LIBS) lib/*.[ao] lib/*.so
	rm -f $(ALL_TOOLS)
	rm -f $(GENH) $(GENH_INT)
	rm -f include/bits

distclean: clean
	rm -f config.mak

include/bits:
	@test "$(ARCH)" || { echo "Please set ARCH in config.mak before running make." ; exit 1 ; }
	ln -sf ../arch/$(ARCH)/bits $@

include/bits/alltypes.h.in: include/bits

include/bits/alltypes.h: include/bits/alltypes.h.in include/alltypes.h.in tools/mkalltypes.sed
	sed -f tools/mkalltypes.sed include/bits/alltypes.h.in include/alltypes.h.in > $@

src/internal/version.h: $(wildcard VERSION .git)
	printf '#define VERSION "%s"\n' "$$(sh tools/version.sh)" > $@

src/internal/version.lo: src/internal/version.h

OPTIMIZE_SRCS = $(wildcard $(OPTIMIZE_GLOBS:%=src/%))
$(OPTIMIZE_SRCS:%.c=%.o) $(OPTIMIZE_SRCS:%.c=%.lo): CFLAGS += -O3

MEMOPS_SRCS = src/string/memcpy.c src/string/memmove.c src/string/memcmp.c src/string/memset.c
$(MEMOPS_SRCS:%.c=%.o) $(MEMOPS_SRCS:%.c=%.lo): CFLAGS += $(CFLAGS_MEMOPS)

# This incantation ensures that changes to any subarch asm files will
# force the corresponding object file to be rebuilt, even if the implicit
# rule below goes indirectly through a .sub file.
define mkasmdep
$(dir $(patsubst %/,%,$(dir $(1))))$(notdir $(1:.s=.o)): $(1)
$(dir $(patsubst %/,%,$(dir $(1))))$(notdir $(1:.s=.lo)): $(1)
endef
$(foreach s,$(wildcard src/*/$(ARCH)*/*.s),$(eval $(call mkasmdep,$(s))))

%.lo: %.s
	as -o $@ $<

%.o: $(ARCH)$(ASMSUBARCH)/%.sub
	$(CC) $(CFLAGS_ALL_STATIC) -c -o $@ $(dir $<)$(shell cat $<)

%.o: $(ARCH)/%.s
	$(CC) $(CFLAGS_ALL_STATIC) -c -o $@ $<

%.o: %.c $(GENH) $(IMPH)
	$(CC) $(CFLAGS_ALL_STATIC) -c -o $@ $<

%.lo: $(ARCH)$(ASMSUBARCH)/%.sub
	$(CC) $(CFLAGS_ALL_SHARED) -c -o $@ $(dir $<)$(shell cat $<)

%.lo: $(ARCH)/%.s
	$(CC) $(CFLAGS_ALL_SHARED) -c -o $@ $<

%.lo: %.c $(GENH) $(IMPH)
	$(CC) $(CFLAGS_ALL_SHARED) -c -o $@ $<

lib/musl-malloc.so: $(LOBJS)
	$(CC) $(CFLAGS_ALL_SHARED) $(LDFLAGS) -shared \
	-Wl,-Bsymbolic-functions \
	-o $@ $(LOBJS) $(LIBCC)

lib/musl-malloc.a: $(OBJS)
	rm -f $@
	$(AR) rc $@ $(OBJS)
	$(RANLIB) $@

$(EMPTY_LIBS):
	rm -f $@
	$(AR) rc $@

$(DESTDIR)$(libdir)/%.so: lib/%.so
	$(INSTALL) -D -m 755 $< $@

$(DESTDIR)$(libdir)/%: lib/%
	$(INSTALL) -D -m 644 $< $@

install-libs: $(ALL_LIBS:lib/%=$(DESTDIR)$(libdir)/%) $(if $(SHARED_LIBS),$(DESTDIR)$(LDSO_PATHNAME),)

musl-git-%.tar.gz: .git
	 git archive --format=tar.gz --prefix=$(patsubst %.tar.gz,%,$@)/ -o $@ $(patsubst musl-git-%.tar.gz,%,$@)

musl-%.tar.gz: .git
	 git archive --format=tar.gz --prefix=$(patsubst %.tar.gz,%,$@)/ -o $@ v$(patsubst musl-%.tar.gz,%,$@)

.PHONY: all clean install install-libs
