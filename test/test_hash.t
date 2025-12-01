-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("std@v0/alloc")
local hash = require("std@v0/hash")
local string = terralib.includec("string.h")

local HashMap = hash.HashMap(rawstring, int32)

import "terratest@v1/terratest"

testenv "HashMap with strings" do
	terracode
		var A: alloc.DefaultAllocator()
		var map = HashMap.new(&A)
	end

	testset "Setters and Getters" do
		terracode
			var key = "Alice"
			var val = 43
			map:set(key, val)
			var val_map = map:get(key)
			var len = map:length()
		end
		test val == val_map
		test len == 1
	end
end

local HashPtr = hash.HashMap(&opaque, int64)

testenv "HashMap with pointers" do
	terracode
		var A: alloc.DefaultAllocator()
		var map = HashPtr.new(&A)
		var x: double[4]
		var y: int[31]
		map:set(&x, 4 * 8)
		map:set(&y, 31 * 4)
		var len = map:length()
	end

	testset "Size" do
		test len == 2
	end

	testset "Getters" do
		terracode
			var bytes_double = map:get(&x)
			var bytes_int = map:get(&y)
		end
		test bytes_double == 4 * 8
		test bytes_int == 31 * 4
	end
end

local HashInt = hash.HashMap(int64, double)

testenv "HashMap with integer indices" do
	terracode
		var A: alloc.DefaultAllocator()
		var map = HashInt.new(&A)
		map:set(10, -123.0)
		map:set(-2, 3.14)
		map:set(0, 2.71)
		var len = map:length()
	end

	testset "Size" do
		test len == 3
	end

	testset "Getters" do
		terracode
			var x = arrayof(double, map:get(0), map:get(10), map:get(-2))
			var xref = arrayof(double, 2.71, -123.0, 3.14)
			var xiter: double[3]
		end
		for i = 1, 3 do
			test x[i - 1] == xref[i - 1]
		end
	end

	testset "Iterator" do
		terracode
			var xref = arrayof(double, 2.71, -123.0, 3.14)
			var match: bool[3]
			var idx = 0
			for kv in map do
				var key, value = kv
				if key == 0 then
					match[0] = value == xref[0]
				end
				if key == 10 then
					match[1] = value == xref[1]
				end
				if key == -2 then
					match[2] = value == xref[2]
				end
				idx = idx + 1
			end
		end
		for i = 1, 3 do
			test match[i - 1] == true
		end
	end

	testset "Some element" do
		terracode
			var key, value = map:some()
		end
		test key == 10 and value == -123.0
	end

	testset "Erase" do
		terracode
			map:erase(-2)

			var xref = arrayof(double, 2.71, -123.0, 3.14)
			var match = arrayof(bool, false, false, false)
			var idx = 0
			for kv in map do
				var key, value = kv
				if key == 0 then
					match[0] = value == xref[0]
				end
				if key == 10 then
					match[1] = value == xref[1]
				end
				if key == -2 then
					match[2] = value == xref[2]
				end
				idx = idx + 1
			end
		end

		test map:length() == 2
		test match[0] == true
		test match[1] == true
		test match[2] == false
	end
end

