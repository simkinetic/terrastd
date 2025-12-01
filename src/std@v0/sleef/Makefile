# SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
# SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
#
# SPDX-License-Identifier: CC0-1.0

all: libsleef

libsleef: CMakeLists.txt
	cmake -G Ninja -B build-sleef -S . -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
	cmake --build build-sleef

.PHONY: clean realclean

install: all
	cp build-sleef/lib/libsleef.$(dyn) $(INSTALL_DIR)/

clean:

realclean: clean
	$(RM) -r build-sleef/*

