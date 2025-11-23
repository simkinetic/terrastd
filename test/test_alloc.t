-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest@v1/terratest"

local alloc = require("alloc")

--test serialization of options table in Lua for the 
--default allocator
assert(alloc.DefaultAllocator({Alignment = 0}) == alloc.DefaultAllocator())
assert(alloc.DefaultAllocator({Alignment = 64}) ~= alloc.DefaultAllocator())

local TracingAllocator = alloc.TracingAllocator()
local __dtor_counter = global(int, 0)

for _, alignment in ipairs{0, 64} do

    --Alignment = 0 - corresponds to natural alignment
    --Alignment = 64 - allocate aligned memory, size is different
    local DefaultAllocator = alloc.DefaultAllocator({Alignment = alignment})

    testenv(alignment) "Block - Default allocator" do

        local doubles = alloc.SmartBlock(double, {copyable = false})

        --test serialization of options table in Lua for the SmartBlock
        assert(doubles == alloc.SmartBlock(double))

        --metamethod used here for testing - counting the number
        --of times the __dtor method is called
        doubles.metamethods.__dtor = macro(function(self)
            return quote
                if self:owns_resource() then
                    __dtor_counter = __dtor_counter + 1
                end
            end
        end)
        local terra get_dtor_counter() return __dtor_counter end

        terracode
            var A : DefaultAllocator
        end

        testset "test smart block:__init()" do
            terracode
                var y : doubles
            end
            test y.ptr == nil
            test y.nbytes == 0
            test y.alloc.data == nil
            test y.alloc.ftab == nil
        end

        testset "cast opaque block to smart block - inside function" do
            terracode
                var y : doubles
                A:allocate(&y, sizeof(double), 2)
                y:set(0, 1.0)
                y:set(1, 2.0)
            end
            test y:isempty() == false
            test y:get(0) == 1.0
            test y:get(1) == 2.0
            test y:size() == 2
            if alignment ~= 0 then
                test [uint64](y.ptr) % alignment == 0
            end
        end

        testset "Cast opaque block to smart block - function return" do
            terracode
                var y : doubles = A:new(sizeof(double), 2)
                y:set(0, 1.0)
                y:set(1, 2.0)
            end
            test y:isempty() == false
            test y:get(0) == 1.0
            test y:get(1) == 2.0
            test y:size() == 2
            if alignment ~= 0 then
                test [uint64](y.ptr) % alignment == 0
            end
        end

        testset "opaque block - __init generated" do
            terracode
                var x : alloc.block
            end
            test x.ptr == nil
            test x.nbytes == 0
            test x.alloc.data == nil
            test x.alloc.ftab == nil
            test x:size() == 0
            test x:isempty()
        end

        testset "smart block - __init generated" do
            terracode
                var x : doubles
            end
            test x.ptr == nil
            test x.nbytes == 0
            test x.alloc.data == nil
            test x.alloc.ftab == nil
            test x:size() == 0
            test x:isempty()
        end

        testset "from buffer" do
            terracode
                var y : doubles = A:new(sizeof(double), 2)
                y:set(0, 1.0)
                y:set(1, 2.0)
                var z = doubles.frombuffer(2, y:getdataptr())
            end
            test y:owns_resource() and z:borrows_resource()
            test y:size() == 2 and y:get(0) == 1.0 and y:get(1) == 2.0
            test z:size() == 2 and z:get(0) == 1.0 and z:get(1) == 2.0
        end

        local integers = alloc.SmartBlock(int, {copyable = false})

        testset "move-semantics of smart block" do
            terracode
                var x : integers = A:new(sizeof(int), 2)
                x:set(0, 1)
                x:set(1, 2)
                var y = x --__move is called here
            end
            test x:isempty() and y:owns_resource()
            test y:size() == 2
            test y:get(0) == 1 and y:get(1) == 2
        end

        local integers = alloc.SmartBlock(int, {copyable = true})
        
        testset "value-semantics of smart block" do
            terracode
                var x : integers = A:new(sizeof(int), 2)
                x:set(0, 1)
                x:set(1, 2)
                var y = x --__copy is called here
            end
            test x:owns_resource() and y:owns_resource()
            test y.ptr ~= x.ptr
            test x:size() == 2 and y:size() == 2
            test x:get(0) == 1 and x:get(1) == 2
            test y:get(0) == 1 and y:get(1) == 2
        end

        testset "explicit move of smart block" do
            terracode
                var x : integers = A:new(sizeof(int), 2)
                x:set(0, 1)
                x:set(1, 2)
                var y = __move__(x) --__copy is called here
            end
            test x:isempty() and y:owns_resource()
            test y:size() == 2
            test y:get(0) == 1 and y:get(1) == 2
        end

        testset "default block - explicit __dtor" do
            terracode
                var x = A:new(sizeof(double), 2)
                var y = x --a move is performed here
                y:__dtor()
            end
            test x.ptr == nil
            test x.alloc.data == nil
            test x.alloc.ftab == nil
            test x:size() == 0
            test x:isempty() and y:isempty()
        end

        testset "smart-block - injected __dtor" do
            terracode
                do
                    __dtor_counter = 0
                    var y : doubles = A:new(sizeof(double), 2)
                end
            end
            test get_dtor_counter()==1
        end

        testset "allocator - owns" do
            terracode
                var x = A:new(sizeof(double), 2)
            end
            test x:isempty() == false
            test x:size_in_bytes() == 16
            test A:owns(&x)
        end

        testset "allocator - free" do
            terracode
                var x = A:new(sizeof(double), 2)
                A:deallocate(&x)
            end
            test x.ptr == nil
            test x.alloc.data == nil
            test x.alloc.ftab == nil
            test x:size() == 0
            test x:isempty()
        end

        testset "allocator - reallocate" do
            terracode
                var y : doubles = A:new(sizeof(double), 3)
                for i=0,3 do
                    y:set(i, i)
                end
                A:reallocate(&y, sizeof(double), 5)
            end
            test y:size() == 5
            for i=0,2 do
                test y:get(i)==i
            end
        end

        testset "block - clone" do
            terracode
                var y : doubles = A:new(sizeof(double), 3)
                for i=0,3 do
                    y:set(i, i)
                end
                var x = y:clone()
            end
            test y:size() == 3
            test x.ptr ~= y.ptr
            test y:owns_resource()
            test x:owns_resource()
            for i=0,2 do
                test x:get(i)==i
            end
        end
    end

    testenv(alignment) "Tracing allocator" do

        local std = {}
        std.io = terralib.includec("stdio.h")
        std.lib = terralib.includec("stdlib.h")
        local ffi = require("ffi")

        local function lua_reachable_bytes(tmpname)
            local input = assert(io.open(tmpname, "r"))
            local output = input:read("*all")
            input:close()
            local _, _, bytes = string.find(output, "(%d+)")
            return tonumber(bytes)
        end

        local get_reachable_bytes = (
            terralib.cast(
                {int, rawstring} -> int,
                function(len, tmpname)
                    return lua_reachable_bytes(ffi.string(tmpname, len))
                end
            )
        )

        terracode
            var libc: DefaultAllocator
        end

        testset "RAII clean up" do
            local tmpname = os.tmpname()
            terracode
                var stream = std.io.fopen([tmpname], "w")
                do
                    var tralloc = TracingAllocator.from(&libc)
                    TracingAllocator.setstream(stream)
                    do
                        var blk = tralloc:new(sizeof(double), 2)
                    end
                end
                std.io.fclose(stream)
                var all_cleaned = get_reachable_bytes([#tmpname], [tmpname])
            end

            test all_cleaned == 0
        end

        testset "Leaking memory" do
            local tmpname = os.tmpname()
            terracode
                var stream = std.io.fopen([tmpname], "w")
                do
                    var tralloc = TracingAllocator.from(&libc)
                    TracingAllocator.setstream(stream)
                    do
                        var blk = tralloc:new(sizeof(double), 3)
                        blk.alloc.data = nil
                        blk.alloc.ftab = nil
                    end
                end
                std.io.fclose(stream)
                var leaking_alloc = get_reachable_bytes([#tmpname], [tmpname])
            end
            test leaking_alloc == [sizeof(double) * 3]
        end
    end
end

import "terraform"

local DefaultAllocator = alloc.DefaultAllocator()

testenv "SmartObject" do

    local struct myobj{
        a : int
        b : int
    }

    terra myobj:product()
        return self.a * self.b
    end

    terraform myobj:add(x : T) where {T}
        self.a = self.a + x
        self.b = self.b + x
    end

    local smrtobj = alloc.SmartObject(myobj, {copyable=false})

    terracode
		var A : DefaultAllocator
        var obj = smrtobj.new(&A)   --allocate a new smart object
        obj.a = 2
        obj.b = 3
	end

    testset "get entries" do
        test obj.a == 2 and obj.b == 3
	end

    testset "get method" do
        test obj:product() == 6 
	end

    testset "get template method" do
        terracode
            obj:add(1)
        end
        test obj:product() == 12 
	end

    testset "frombuffer" do
        terracode
            var ab = myobj {3, -4}
            var smartab: smrtobj = smrtobj.frombuffer(1, &ab)
        end
        test smartab:product() == -12
    end
end

testenv "singly linked list - that is a cycle" do

	local Allocator = alloc.Allocator

    --implementation of singly-linked list
    local struct s_node
    local smrt_s_node = alloc.SmartObject(s_node, {copyable=false})

    --metamethod used here for testing - counting the number
    --of times the __dtor method is called
    local smrt_s_node_dtor_counter = global(int, 0)
    smrt_s_node.metamethods.__dtor = macro(function(self)
        return quote
            if self:owns_resource() then
                smrt_s_node_dtor_counter  = smrt_s_node_dtor_counter + 1
            end
        end
    end)

    local terra get_smrt_s_node_dtor_counter()
        return smrt_s_node_dtor_counter
    end

    struct s_node{
        index : int
        next : smrt_s_node
    }

    smrt_s_node.metamethods.__eq = terra(self : &smrt_s_node, other : &smrt_s_node)
        if not self:isempty() and not other:isempty() then
            return self.ptr == other.ptr
        end
        return false
    end

    terra smrt_s_node:allocate_next(A : Allocator)
        self.next = A:new(sizeof(s_node), 1)
        self.next.index = self.index + 1
    end

    terra smrt_s_node:set_next(next : &smrt_s_node)
        self.ptr.next.ptr = next.ptr  --make sure there is no ownership transfer via '__move'
    end

    terra smrt_s_node:setweakptr(other : &smrt_s_node)
        @self = __handle__(@other)
        self.alloc.data = nil
        self.alloc.ftab = nil
    end

    terracode
        var A : DefaultAllocator
    end

    testset "next" do
        terracode
            smrt_s_node_dtor_counter = 0
            --define head node
            var head : smrt_s_node = A:new(sizeof(s_node), 1)
            head.index = 0
            --make allocations
            head:allocate_next(&A)  --node 1
            head.next:allocate_next(&A) --node 2
            head.next.next:allocate_next(&A) --node 3
            --close loop
            head.next.next.next.next:setweakptr(&head)
            --get handles to nodes
            var node_0 = __handle__(head)
            var node_1 = __handle__(node_0.next)
            var node_2 = __handle__(node_1.next)
            var node_3 = __handle__(node_2.next)
        end
        --next node
        test node_0.next==node_1
        test node_1.next==node_2
        test node_2.next==node_3
        test node_3.next==node_0
    end

    testset "__dtor - head on the stack" do
        terracode
            smrt_s_node_dtor_counter = 0
            do
                --define head node
                var head : smrt_s_node = A:new(sizeof(s_node), 1)
                head.index = 0
                --make allocations
                head:allocate_next(&A)  --node 1
                head.next:allocate_next(&A) --node 2
                head.next.next:allocate_next(&A) --node 3
                --close loop
                head.next.next.next.next:setweakptr(&head)
            end
        end
        test smrt_s_node_dtor_counter==4
    end
end

testenv "doubly linked list - that is a cycle" do

	local Allocator = alloc.Allocator

    --implementation of double-linked list
    local struct d_node
    local smrt_d_node = alloc.SmartObject(d_node, {copyable=false})

    --metamethod used here for testing - counting the number
    --of times the __dtor method is called
    local smrt_d_node_dtor_counter = global(int, 0)
    smrt_d_node.metamethods.__dtor = macro(function(self)
        return quote
            if self:owns_resource() then
                smrt_d_node_dtor_counter  = smrt_d_node_dtor_counter + 1
            end
        end
    end)

    struct d_node{
        index : int
        next : smrt_d_node
        prev : smrt_d_node
    }

    smrt_d_node.metamethods.__eq = terra(self : &smrt_d_node, other : &smrt_d_node)
        if not self:isempty() and not other:isempty() then
            return self.ptr == other.ptr
        end
        return false
    end

    terra smrt_d_node:makeweakptr()
        self.alloc.data = nil
        self.alloc.ftab = nil
    end

    terra smrt_d_node:allocate_next(A : Allocator)
        self.next = A:new(sizeof(d_node), 1)
        self.next.index = self.index + 1
        self.next.prev = __handle__(@self)
        self.next.prev:makeweakptr()
    end

    terracode
        var A : DefaultAllocator
    end

    testset "next and prev" do
        terracode
            --define head node
            var head : smrt_d_node = A:new(sizeof(d_node), 1)
            head.index = 0
            --make allocations
            head:allocate_next(&A)  --node 1
            head.next:allocate_next(&A) --node 2
            head.next.next:allocate_next(&A) --node 3
            --close loop
            head.next.next.next.next = __handle__(head)
            head.prev = __handle__(head.next.next.next)
            head.next.next.next.next:makeweakptr()
            head.prev:makeweakptr()
            --get pointers to nodes
            var node_0 = __handle__(head)
            var node_1 = __handle__(node_0.next)
            var node_2 = __handle__(node_1.next)
            var node_3 = __handle__(node_2.next)
        end
        --next node
        test node_0.next==node_1
        test node_1.next==node_2
        test node_2.next==node_3
        test node_3.next==node_0
        --previous node
        test node_0.prev==node_3
        test node_1.prev==node_0
        test node_2.prev==node_1
        test node_3.prev==node_2
    end


    testset "__dtor - head on the stack" do
        terracode
            smrt_d_node_dtor_counter = 0
            do
                --define head node
                var head : smrt_d_node = A:new(sizeof(d_node), 1)
                head.index = 0
                --make allocations
                head:allocate_next(&A)  --node 1
                head.next:allocate_next(&A) --node 2
                head.next.next:allocate_next(&A) --node 3
                --close loop
                head.next.next.next.next = __handle__(head)
                head.prev = __handle__(head.next.next.next)
                head.next.next.next.next:makeweakptr()
                head.prev:makeweakptr()
            end
        end
        test smrt_d_node_dtor_counter==4
    end
end
