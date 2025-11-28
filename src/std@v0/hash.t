-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("alloc")
local base = require("base")
local concepts = require("concepts")
local err = require("assert")
local parametrized = require("parametrized")
local range = require("range")
local string = terralib.includec("string.h")

local C = terralib.includec("hashmap/hashmap.h")
local ffi = require("ffi")
local OS = ffi.os
if OS == "Linux" then
    terralib.linklibrary("src/std@v0/hashmap/libhash.so")
else
    terralib.linklibrary("src/std@v0/hashmap/libhash.dylib")
end

import "terraform"

local primitive_compare
terraform primitive_compare(a: &T, b: &T) where {T: concepts.Primitive}
	if @a > @b then
		return 1
	elseif @a < @b then
		return -1
	else
		return 0
	end
end

terraform primitive_compare(a: &&opaque, b: &&opaque)
	var ae = [int64](@a)
	var be = [int64](@b)
	return primitive_compare(&ae, &be)
end

terraform primitive_compare(a: &&T, b: &&T) where {T}
	return primitive_compare([&&opaque](a), [&&opaque](b))
end

terraform primitive_compare(a: &rawstring, b: &rawstring)
	return string.strcmp(@a, @b)
end

local primitive_length
terraform primitive_length(a: &T) where {T: concepts.Primitive}
	var size: int64 = [sizeof(a.type.type)]
	return size
end

terraform primitive_length(a: &&opaque)
	return 8l -- 64 bit platform
end

terraform primitive_length(a: &&T) where {T}
	return primitive_length([&&opaque](a))
end

terraform primitive_length(a: &rawstring)
	var size: int64 = string.strlen(@a)
	return size
end

local get_types = terralib.memoize(function(I, T)

	return {entry, hash}
end)

local HashMap = parametrized.type(function(I, T)
	local entry = tuple(I, T)
	local struct hash{
		data: &C.hashmap
	}
	base.AbstractBase(hash)

	local terra compare_c(a: &opaque, b: &opaque, udata: &opaque)
		var ae = @[&entry](a)
		var be = @[&entry](b)
		return primitive_compare(&ae._0, &be._0)
	end

	local terra hash_c(a: &opaque, seed0: uint64, seed1: uint64)
		var ae = @[&entry](a)
		return C.hashmap_sip(&ae._0, primitive_length(&ae._0), seed0, seed1)
	end

	local D = terralib.includec("stdlib.h")
	terra hash.staticmethods.new(A: alloc.Allocator)
		var data = C.hashmap_new_with_allocator(
			D.malloc,
			D.realloc,
			D.free,
			sizeof(entry),
			0, -- cap
			0, -- seed0,
			0, -- seed1
			hash_c,
			compare_c,
			nil, -- elfree
			nil -- udata
		)
		return hash {data}
	end

	terra hash:__dtor()
		C.hashmap_free(self.data)
	end

	terra hash:length()
		var size: int64 = C.hashmap_count(self.data)
		return size
	end

	terra hash:empty()
		return self:length() == 0
	end

	terra hash:set(key: I, val: T)
		var key_val = entry {key, val}
		C.hashmap_set(self.data, &key_val)
	end
	-- Follow C++ interface for unordered_hashmap
	hash.methods.insert = hash.methods.set

	terra hash:get(key: I)
		var lookup = entry {key}
		var res = C.hashmap_get(self.data, &lookup)
		err.assert(res ~= nil)
		return [&entry](res)._1
	end

	terra hash:delete(key: I)
		var lookup = entry {key}
		var res = C.hashmap_delete(self.data, &lookup)
	end
	-- Follow C++ interface for unordered_hashmap
	hash.methods.erase = hash.methods.delete

	terra hash:some()
		err.assert(self:length() > 0)
		var i: uint64 = 0
		while true do
			var res = C.hashmap_probe(self.data, i)
			if res ~= nil then
				return @[&entry](res)
			end
			i = i + 1
		end
	end
	hash.methods.any = hash.methods.some

	local struct iterator {
		parent: &hash
		idx: uint64
		pitem: &opaque
	}
	terra iterator:getvalue()
		return @[&entry](self.pitem)
	end
	terra iterator:next()
	end
	terra iterator:isvalid()
		var hasitem = C.hashmap_iter(self.parent.data, &self.idx, &self.pitem)
		return hasitem
	end
	terra hash:getiterator()
		return iterator {self, 0, nil}
	end
	range.Base(hash, iterator)

	return hash
end)

return {
	HashMap = HashMap,
}
