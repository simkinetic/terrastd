# SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
# SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
#
# SPDX-License-Identifier: CC0-1.0

all: libpcg.$(dyn)

FILE=  pcg-advance-8.c pcg-advance-16.c pcg-advance-32.c pcg-advance-64.c \
       pcg-advance-128.c pcg-output-8.c pcg-output-16.c pcg-output-32.c   \
       pcg-output-64.c pcg-output-128.c pcg-rngs-8.c pcg-rngs-16.c        \
       pcg-rngs-32.c pcg-rngs-64.c pcg-rngs-128.c \
       pcg-global-32.c pcg-global-64.c

SRC=$(patsubst %.c, %.c, $(FILE))
OBJ=$(patsubst %.c, %.o, $(FILE))

libpcg.$(dyn): $(OBJ)
	$(CC) -fPIC -shared $^ -o $@

$(OBJ): %.o: %.c
	$(CC) $(CFLAGS) $^ -c -o $@

.PHONY: clean realclean

clean:
	$(RM) $(OBJ)

realclean: clean
	$(RM) libpcg.$(dyn)