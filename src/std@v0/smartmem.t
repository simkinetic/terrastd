-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require "terralibext"

local C = terralib.includecstring[[
    #include <string.h>
]]

local base = require("std@v0/base")
local interface = require("std@v0/interface")
local range = require("std@v0/range")
local err = require("std@v0/assert")
local serde = require("std@v0/serde")
local parametrized = require("std@v0/parametrized")

local size_t = uint64
local u8 = uint8

import "std@v0/terraform"

local function Base(block, T, options)

    assert(
        options and type(options.copyable)=="boolean",
        "Invalid option. Please provide {copyable = true / false}"
    )
    --is the type copyable? Default to false.
    local copyable = options.copyable or false

    --type traits
    block.isblock = true
    block.type = block
    block.traits.eltype = T
    block.elsize = T==opaque and 1 or sizeof(T)

    block.methods.getdataptr = terra(self : &block)
        return self.ptr
    end

    --block is empty, no resource and no allocator
    block.methods.isempty = terra(self : &block)
        return self.ptr==nil
    end

    --resource is borrowed, there is no allocator
    --this represents a view of the data
    block.methods.borrows_resource = terra(self : &block)
        return self.ptr~=nil and self.alloc.data==nil
    end

    --resource is owned, there is an allocator
    block.methods.owns_resource = terra(self : &block)
        return self.ptr~=nil and self.alloc.data~=nil
    end

    block.methods.size_in_bytes = terra(self : &block) : size_t
        return self.nbytes
    end

    if T==opaque then
        block.methods.size = terra(self : &block) : size_t
            return self.nbytes
        end
    else
        block.methods.size = terra(self : &block) : size_t
            return self.nbytes / [block.elsize]
        end
    end
    
    --auto-generate __init method
    terralib.ext.addmissing.__init(block)
    block.methods.length = block.methods.size

    --exact clone of the block
    block.methods.clone = terra(self : &block)
        var newblk : block --allocate memory for exact clone
        if not self:isempty() then
            self.alloc:__allocators_best_friend(&newblk, [ block.elsize ], self:size())
            if not newblk:isempty() then
                C.memcpy(newblk.ptr, self.ptr, self:size_in_bytes())
            end
        end
        return newblk
    end

end

--abstraction of a memory block without any type information.
local struct block

local __Allocator = interface.newinterface("__Allocator")
terra __Allocator:__allocators_best_friend(blk: &block, elsize: size_t, counter: size_t) end
__Allocator:complete()

struct block{
    ptr : &opaque
    nbytes : size_t
    alloc : __Allocator
}

function block.metamethods.__typename(self)
    return "block"
end

--add base functionality
base.AbstractBase(block)
Base(block, opaque, {copyable=false})

--__dtor for opaque memory block
terra block.methods.__dtor(self : &block)
    if self:borrows_resource() then
        self:__init()
    elseif self:owns_resource() then
        self.alloc:__allocators_best_friend(self, 0, 0)
    end
end

--add raii move method
terralib.ext.addmissing.__move(block)
block:complete()


--abstraction of a memory block with type information.
local SmartBlock = parametrized.type(function(T, options)

    assert(type(options.copyable)=="boolean",
        "Invalid option. Expected copyable to be a boolean."
    )
    --is the type copyable? Default to false.
    local copyable = options.copyable

    local struct block{
        ptr : &T
        nbytes : size_t
        alloc : __Allocator
    }

    function block.metamethods.__typename(self)
        return ("SmartBlock(%s)"):format(tostring(T))
    end

    base.AbstractBase(block)

    -- Cast block from one type to another
    function block.metamethods.__cast(from, to, exp)
        local function passbyvalue(to, from)
            if from:ispointertostruct() and to:ispointertostruct() then
                return false, to.type, from.type
            end
            return true, to, from
        end
        --process types
        local byvalue, to, from = passbyvalue(to, from)        
        --exit early if types do not match
        if not to.isblock or not from.isblock then
            error("Arguments to cast need to be of generic type SmartBlock.")
        end
        --based on passing-by-reference or by-value we return a different parameter
        local returnfromcast = macro(function(blk)
            if byvalue then
                return quote
                in
                    [to.type]{[&to.traits.eltype](blk.ptr), blk.nbytes, blk.alloc}
                end
            else
                return quote
                in
                    [&to.type](blk)
                end
            end
        end) 
        --perform cast
        --case when and opaque block is cast to a SmartBlock with a managed element 
        --type (implements a '__dtor')
        --note: the opaque memory is first cast to the new (managed) element type
        --and is then initialized with the '__init' method to make sure that the 
        --uninitialized memory is initialized with the correct initializer.
        if terralib.ext.ismanaged(to.traits.eltype) and from.traits.eltype==opaque then
            return quote
                --we get a handle to the object, which means we get an lvalue that 
                --does not own the resource, so it's '__dtor' will not be called
                var tmp = __handle__(exp)
                --debug check if sizes are compatible, that is, is the
                --remainder zero after integer division
                err.assert(tmp:size_in_bytes() % [to.elsize]  == 0)
                --loop over all elements of blk and initialize their entries. This 
                --is done to correctly initialize the uninitialized memory.
                var size = tmp:size_in_bytes() / [to.elsize]
                var ptr = [&to.traits.eltype](tmp.ptr)
                for i = 0, size do
                    ptr:__init()
                    ptr = ptr + 1
                end
            in
                returnfromcast(tmp)
            end
        --simple case when to.eltype is not managed
        else
            return quote
                var tmp = __handle__(exp)
                --debug check if sizes are compatible, that is, is the
                --remainder zero after integer division
                err.assert(tmp:size_in_bytes() % [to.elsize]  == 0)
            in
                returnfromcast(tmp)
            end
        end
    end --__cast

    --declaring __dtor for use in implementation below
    terra block.methods.__dtor :: {&block} -> {}

    function block.metamethods.__staticinitialize(self)

        --add base functionality
        Base(block, T, options)

        --setters and getters
        block.methods.get = terra(self : &block, i : size_t)
            err.assert(i < self:size())
            return self.ptr[i]
        end

        block.methods.set = terra(self : &block, i : size_t, v : T)
            err.assert(i < self:size())
            self.ptr[i] = v
        end

        block.metamethods.__apply = macro(function(self, i)
            return quote
                err.assert(i < self:size())
            in
                self.ptr[i]
            end
        end)

        block.staticmethods.frombuffer = terra(size: size_t, ptr: &T)
            var nbytes = size * sizeof(T)
            var b: block
            b.ptr = ptr
            b.nbytes = nbytes
            b.alloc.data = nil
            b.alloc.ftab = nil
            return b
        end

        --iterator - behaves like a pointer and can be passed
        --around like a value, convenient for use in ranges.
        local struct iterator{
            parent : &block
            ptr : &T
        }

        terra block:getiterator()
            return iterator{self, self.ptr}
        end

        terra iterator:getvalue()
            return @self.ptr
        end

        terra iterator:next()
            self.ptr = self.ptr + 1
        end

        terra iterator:isvalid()
            return (self.ptr - self.parent.ptr) * [block.elsize] < self.parent.nbytes
        end
        
        block.iterator = iterator
        range.Base(block, iterator)

        terra block:reallocate(size : size_t)
            self.alloc:__allocators_best_friend(self, sizeof(T), size)
        end
        
        --implementation __dtor
        --ToDo: change recursion to a loop
        terra block.methods.__dtor(self : &block)
            --insert metamethods.__dtor if defined, which is used to introduce
            --side effects (e.g. counting number of calls for the purpose of testing)
            escape
                if block.metamethods and block.metamethods.__dtor then
                    emit quote
                        [block.metamethods.__dtor](self)
                    end
                end
            end
            --return if block is empty
            if self:isempty() then
                return
            end
            --initialize block and return if block borrows a resource
            if self:borrows_resource() then
                self:__init()
                return
            end
            --first destroy other memory block resources pointed to by self.ptr
            --ToDo: change recursion into a loop
            escape
                if terralib.ext.ismanaged(T) then
                    emit quote
                        var ptr = self.ptr
                        for i = 0, self:size() do
                            ptr:__dtor()
                            ptr = ptr + 1
                        end
                    end
                end
            end
            --free current memory block resources
            self.alloc:__allocators_best_friend(self, 0, 0)
        end

        --conditional compilation of a copy-method
        if copyable then
            block.methods.__copy = terra(from : &block, to : &block)
                --to:__dtor() is injected here by the compiler
                @to = from:clone()
            end
        end

        --add raii move method
        terralib.ext.addmissing.__move(block)

    end --__staticinitialize

    return block
end, {copyable=false})

--Abstraction of a single object that is stored on the heap.
--Do not memoize this function (memoization is done in SmartBlock)
--Remember, memoization requires that 'option' tables are serialized.
--This is done in 'SmartBlock'
local SmartObject = function(obj, options)

    --SmartObject is a special SmartBlock that has one element
    --see `new` method below
    --it's a heap object that has direct access to the fields of
    --the 'obj' type (using __entrymissing and __methodmissing)
    local smrtobj = SmartBlock(obj, options)

    --allocate an empty obj
    terraform smrtobj.staticmethods.new(A) where {A}
        var S: smrtobj = A:new(sizeof(obj), 1)
        return S
    end

    smrtobj.metamethods.__getmethod = function(self, methodname)
        local fnlike = self.methods[methodname] or smrtobj.staticmethods[methodname]
        --if no implementation is found try __methodmissing
        if not fnlike and terralib.ismacro(self.metamethods.__methodmissing) then
            fnlike = terralib.internalmacro(function(ctx, tree, ...)
                return self.metamethods.__methodmissing:run(ctx, tree, methodname, ...)
            end)
        end
        return fnlike
    end

    smrtobj.metamethods.__entrymissing = macro(function(entryname, self)
        return `self.ptr.[entryname]
    end)

    smrtobj.metamethods.__methodmissing = macro(function(method, self, ...)
        local args = terralib.newlist{...}
        return `self.ptr:[method](args)
    end)

    return smrtobj
end


return {
    block = block,
    SmartBlock = SmartBlock,
    SmartObject = SmartObject
}
