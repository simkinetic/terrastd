# SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
# SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
#
# SPDX-License-Identifier: CC0-1.0

all: libtinymt.$(dyn)

libtinymt.$(dyn): tinymt32.o tinymt64.o
	$(CC) -fPIC -shared $^ -o $@

tinymt32.o: tinymt32.c
	$(CC) $(CFLAGS) $^ -c -o $@

tinymt64.o: tinymt64.c
	$(CC) $(CFLAGS) $^ -c -o $@

install: all
	cp libtinymt.$(dyn) $(INSTALL_DIR)/

.PHONY: clean realclean install

clean:
	$(RM) tinymt32.o tinymt64.o

realclean: clean
	$(RM) libtinymt.$(dyn)