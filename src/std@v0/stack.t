-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require("terralibext")
local base = require("base")
local alloc = require("alloc")
local err = require("assert")
local concepts = require("concepts")
local range = require("range")
local parametrized = require("parametrized")

local Allocator = alloc.Allocator

local size_t = uint64

local StackBase = function(stack, options)

    local T = stack.traits.eltype

	terra stack:reverse()
		var size = self:length()
		for i = 0, size / 2 do
			var a, b = self:get(i), self:get(size -1 - i)
			self:set(i, b)
			self:set(size - 1 - i, a)
		end
	end

    --get a pointer to the first element
    terra stack:front()
        err.assert(self:length() > 0, "Error: stack doesn't have any elements.")
        return &self(0)
    end

    --get a pointer to the last element
    terra stack:back()
        err.assert(self:length() > 0, "Error: stack doesn't have any elements.")
        return &self(self:length()-1)
    end

    --iterator - behaves like a pointer and can be passed
    --around like a value, convenient for use in ranges.
    local struct iterator{
        parent : &stack
        ptr : &T
    }

    terra stack:getiterator()
        return iterator{self, self:getdataptr()}
    end

    terra iterator:first() : &T
        return self.parent:front()
    end

    terra iterator:sentinel() : &T
        return &self.parent(self.parent:length())
    end

    --iterator returntype by value or by reference
    if options.byvalue then
        --return value of the element
        terra iterator:getvalue()
            return @self.ptr
        end
    else
        --return a pointer to the element
        terra iterator:getvalue()
            return self.ptr
        end
    end

    terra iterator:next()
        self.ptr = self.ptr + 1
        return self.ptr
    end

    terra iterator:isvalid()
        return self.ptr - self.parent:getdataptr() < self.parent:length()
    end
    
    stack.iterator = iterator
    range.Base(stack, iterator)

end


local DynamicStack = parametrized.type(function(T, options)

    assert(type(options.byvalue) == "boolean", "CompileError: options.byvalue should be of boolean type.")

    local S = alloc.SmartBlock(T) --typed memory block
    S:complete() --always complete the implementation of SmartBlock

    local struct stack{
        data : S
        size : size_t
    }

    stack.metamethods.__typename = function(self)
        return ("DynamicStack(%s)"):format(tostring(T))
    end

    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concepts-based function overloading at compile-time
    base.AbstractBase(stack)

    stack.traits.eltype = T

    stack.staticmethods.new = terra(alloc : Allocator, capacity: size_t)
        return stack{alloc:new(sizeof(T), capacity), 0}
    end

    stack.staticmethods.frombuffer = terra(n: size_t, ptr: &T)
        return stack{S.frombuffer(n, ptr), n}
    end

    terra stack:getdataptr()
        return self.data:getdataptr()
    end

    terra stack:length()
        return self.size
    end

    terra stack:capacity()
        return self.data:size()
    end
    
    terra stack:push(v : T)
        --we don't allow pushing when 'data' is empty
        err.assert(self.data:isempty() == false)
        if self:length() == self:capacity() then
            self.data:reallocate(1 + 2 * self:capacity())
        end
        self.size = self.size + 1
        self.data.ptr[self.size - 1] = __move__(v)
    end

    terra stack:get(i : size_t)
        err.assert(i < self:length())
        return self.data:get(i)
    end

    terra stack:set(i : size_t, v : T)
        err.assert(i < self:length())
        self.data:set(i, v)
    end

    terra stack:pop()
        if self:length() > 0 then
            var tmp = __move__(self.data.ptr[self.size - 1])
            self.size = self.size - 1
            return tmp
        else
            --added this branch to make sure T:__init() is called 
            --in case of managed data
            var tmp : T -- T:__init() is called here
            return tmp
        end
    end

    stack.metamethods.__apply = macro(function(self, i)
        return `self.data(i)
    end)

    terra stack:insert(i: size_t, v: T)
        var sz = self:length()
        err.assert(i <= sz)
        self:push(v)
        if i < sz then
            for jj = 0, sz - i do
                var j = sz - 1 - jj
                self(j + 1) = self(j)
            end
            self(i) = v
        end
    end

    --add all methods from stack-base
    StackBase(stack, options)

    terralib.ext.addmissing.__init(stack)
    terralib.ext.addmissing.__move(stack)

    --sanity check
    assert(concepts.DStack(stack), "Stack type does not satisfy the DStack concepts.")

    return stack
end, {byvalue = true})

return {
    StackBase = StackBase,
    DynamicStack = DynamicStack
}
