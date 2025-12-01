# SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
# SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
#
# SPDX-License-Identifier: CC0-1.0

uname_s := $(shell uname -s)
ifeq ($(uname_s),Linux)
	dyn := so
else ifeq ($(uname_s),Darwin)
	dyn := dylib
else
	$(error Unsupported build environment!)
endif

SOURCE_DIR=src/std@v0
TERRA?=terra
TERRAFLAGS?=-g

CFLAGS=-O2 -march=native -fPIC -g

INSTALL_DIR ?= $(abspath lib/std@v0)

export dyn CFLAGS SOURCE_DIR TERRA TERRAFLAGS INSTALL_DIR

SUBDIRS = hashmap pcg tinymt sleef

.PHONY: all clean realclean install $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $(SOURCE_DIR)/$@

install: all
	mkdir -p $(INSTALL_DIR)
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $(SOURCE_DIR)/$$dir install; \
	done

clean:
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $(SOURCE_DIR)/$$dir clean; \
	done

realclean: clean
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $(SOURCE_DIR)/$$dir realclean; \
	done