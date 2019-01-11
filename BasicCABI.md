This document describes the "Basic" C ABI for WebAssembly. As mentioned in
[README](README.md), it's not the only possible C ABI. It is the ABI that the
clang/LLVM WebAssembly backend is currently using, and any other C or C++
compiler wishing to be ABI-compatible with it.

wasm32 is ILP32 and wasm64 is LP64. `float` and `double` map to wasm’s `f32` and
`f64` respectively.  Varargs is lowered to passing a pointer to an
explicitly-allocated buffer.  Single-element struct return values are returned
by a normal wasm return value. TODO: Spell this all out in much more detail.

This is just an initial sketch of some content. Obviously, it would be desirable
to go into a lot more detail.

Eventually, some content from the design repo's
[CAndC++](https://github.com/WebAssembly/design/blob/master/CAndC++.md) should also
be moved here.



# Function Calling Sequence
This section describes the standard function calling sequence, including stack frame
layout, Wasm argument and local value usage, and so on. These requirements apply
only to global functions. Local functions not reachable from other compilation units
may use different conventions; however this may reduce the ability of external tools
to understand them.


## Locals and the stack frame
WebAssembly does not have registers in the style of hardware architectures. Instead it has an
unlimited number of function
arguments and local variables, which have wasm value types. These local values are generally
used as registers would be in a traditional architecture, but there are some important differences.
Because arguments are modeled explicitly and locals are local to a function, there is no need
for a concept of callee- or caller-saved locals.


### The linear stack
WebAssembly is a "Harvard" architcture; this means that code and data are not in the same
memory space. No code or code addresses are visible in the wasm linear memory space, the only "address"
that a function has is its index in the wasm function index space. Additionally the wasm implementation's
runtime call stack (including the return address and function arguments) is not visible in
the linear memory either.
This means that address-taken local C variables need to be on a separate stack in the linear memory
(herafter called the "linear stack"). It also means that some functions may not need a frame in the 
linear stack at all.

Instead of registers visible to all functions, WebAssembly has a table of global variables. One of these
acts as the stack pointer [TODO: describe how stack pointer is designated here, or in object file section] 
[TODO: discuss mutable global requirement].

Each function may have a frame on the linear stack. This stack grows downward
[TODO: describe how start position is determined and why it's located below the heap].
The stack pointer global (`SP`) points to the bottom of the stack frame and always has 16-byte alignment. 
If there are dynamically-sized objects on the stack, a frame pointer (a local variable, `FP`) is used, 
and it points to the bottom of the static-size objects (those whose sizes are known at compile time). 
If objects in the current frame require alignment greater than 16, then a base pointer (another local, `BP`) is used, which points to the bottom of the previous frame.
The stack also has a "red zone" which extends 128 bytes below the stack pointer. If a function
does not need a frame or base pointer, it may write data into the red zone which is not needed
across function calls. So a leaf function which needs less than 128 bytes of stack space
need not update the stack pointer in its prolog or epilog at all.

The frame organization is illustrated as follows:

Position | Contents | Frame
-|-|-
`BP` |  unspecified | Previous
 ... | unspecified (aligment padding) | Current
   `FP` + *s*<br>...<br>`FP` | static-size objects | Current
 `SP` + *d*<br>...<br>`SP` | dynamic-size objects | Current
 ...<br>`SP`-128| small static-size objects | Current (red zone)
 
