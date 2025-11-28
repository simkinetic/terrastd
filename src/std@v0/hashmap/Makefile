# SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
# SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
#
# SPDX-License-Identifier: CC0-1.0

all: libhash.$(dyn)

libhash.$(dyn): hashmap.o
	$(CC) -fPIC -shared $^ -o $@

hashmap.o: hashmap.c hashmap.h
	$(CC) $(CFLAGS) $< -c -o $@

.PHONY: clean realclean

clean:
	$(RM) hashmap.o

realclean: clean
	$(RM) libhash.$(dyn)