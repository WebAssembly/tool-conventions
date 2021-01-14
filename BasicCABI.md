This document describes the "Basic" C ABI for WebAssembly. As mentioned in
[README](README.md), it's not the only possible C ABI. It is the ABI that the
clang/LLVM WebAssembly backend is currently using, and any other C or C++
compiler wishing to be ABI-compatible with it.

# Versioning and Machine interface

The current version of this ABI is *1*.

This ABI is designed to work with Release 1.0 of the WebAssembly [Specification](https://webassembly.github.io/spec/core/index.html). It does not require any 
[features](https://github.com/WebAssembly/proposals)
that have not yet been implemented and standardized. Future versions will depend on
features such as threads and/or multi-value.

## Data Representation

**Scalar Types**

The ABI for the currently-specifed version of WebAssembly (also known as "wasm32") uses an "ILP32" data model, 
where `int`, `long`, and pointer types are 32 bits. It is expected that the proposed extension to allow memories
larger than 4GB ("wasm64") will use an "LP64" data model, where `int` is 32 bits while `pointer` and `long` are
64 bits.

The following table shows the memory sizes and alignments of C and C++ scalar types, and their
correspondence to types used in the WebAssembly specification:


General type | C Type | `sizeof` | Alignment (bytes) | Wasm Value Type
-|-|-|-|-
 Integer | `_Bool`/`bool` | 1 | 1 | i32
 Integer | `char`, `signed char` | 1 | 1 | i32
 Integer | `unsigned char` | 1 | 1 | i32
 Integer | `short` / `signed short` | 2 | 2 | i32
 Integer | `unsigned short` | 2 | 2 | i32
 Integer | `int` / `signed int` / `enum` | 4 | 4 | i32
 Integer | `unsigned int` | 4 | 4 | i32
 Integer | `long` / `signed long` | 4 | 4 | i32
 Integer | `unsigned long` | 4 | 4 | i32
 Integer | `long long` / `signed long long` | 8 | 8 | i64
 Integer | `unsigned long long` | 8 | 8 | i64
 Pointer | *`any-type *`* / *`any-type (*)()`* | 4 | 4 | i32
 Floating point | `float` | 4 | 4 | f32
 Floating point | `double` | 8 | 8 | f64
 Floating point | `long double` | 16 | 16 | (none)
 
 * `long double` values correspond to 128-bit IEEE-754 quad-precision binary128 values.
 Operations on these values are currently implemented as calls to
 compiler-rt library functions.
 * A null pointer (for all types) has the value zero
 * The `size_t` type is defined as `unsigned long`.
 

**Aggregates and Unions**

Structures and unions assume the alignment of their most strictly aligned component.
Each member is assigned to the lowest available offset with the appropriate
alignment. The size of any object is always a multiple of the object‘s alignment.
An array uses the same alignment as its elements, except that a local or global
array variable of length at least 16 bytes or a C99 variable-length array variable
always has alignment of at least 16 bytes.
Structure and union objects can require padding to meet size and alignment
constraints. The contents of any padding is undefined.

**Bit-fields**

C struct and union definitions may include bit-fields that define integral values of
a specified size.
The ABI does not permit bit-fields having the type __m64, __m128 or __m256.
(Programs using bit-fields of these types are not portable.)
Bit-fields that are neither signed nor unsigned always have non-negative values.
Although they may have type char, short, int, or long (which can have negative values),
these bit-fields have the same range as a bit-field of the same size
with the corresponding unsigned type. Bit-fields obey the same size and alignment
rules as other structure and union members.
Also:

* bit-fields are allocated from right to left
* bit-fields must be contained in a storage unit appropriate for its declared
type
* bit-fields may share a storage unit with other struct / union members
* Unnamed bit-fields’ types do not affect the alignment of a structure or union.

Bitfield type | Witdh *w* | Range
-|-|-
`signed char` | 1 to 8 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`char`, `unsigned char` | 1 to 8 | 0 to 2<sup>w</sup>-1
`signed short` | 1 to 16 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`short`, `unsigned short` | 1 to 16 | 0 to 2<sup>w</sup>-1
`signed int` | 1 to 32 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`int`, `unsigned int` | 1 to 32 | 0 to 2<sup>w</sup>-1
`signed long long` | 1 to 64 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`long long`, `unsigned long long` | 1 to 64 | 0 to 2<sup>w</sup>-1



# Function Calling Sequence
This section describes the standard function calling sequence, including stack frame
layout, Wasm argument and local value usage, and so on. These requirements apply
only to global functions (those reachable from other compilation units) . Local functions
may use different conventions; however this may reduce the ability of external tools
to understand them.


## Locals and the stack frame
WebAssembly does not have registers in the style of hardware architectures. Instead it has an
unlimited number of function arguments and local variables, which have wasm value types. These 
local values are generally used as registers would be in a traditional architecture, but there
are some important differences. Because arguments are modeled explicitly and locals are local
to a function, there is no need for a concept of callee- or caller-saved locals.


### The linear stack
WebAssembly is a [Harvard](https://en.wikipedia.org/wiki/Harvard_architecture) architecture; 
this means that code and data are not in the same memory space. No code or code addresses are
visible in the wasm linear memory space, the only "address" that a function has is its index
in the wasm function index space. Additionally the wasm implementation's runtime call stack
(including the return address and function arguments) is not visible in the linear memory either.
This means that address-taken local C variables need to be on a separate stack in the linear memory
(herafter called the "linear stack"). It also means that some functions may not need a frame in the 
linear stack at all.

Instead of registers visible to all functions, WebAssembly has a table of global variables. One of these
acts as the stack pointer [TODO: describe how stack pointer is designated here, or in object file section] 
[TODO: discuss mutable global requirement].

Each function may have a frame on the linear stack. This stack grows downward
[TODO: describe how start position is determined].
The stack pointer global (`SP`) points to the bottom of the stack frame and always has 16-byte alignment. 
If there are dynamically-sized objects on the stack, a frame pointer (a local variable, `FP`) is used, 
and it points to the bottom of the static-size objects (those whose sizes are known at compile time). 
If objects in the current frame require alignment greater than 16, then a base pointer (another local, `BP`)
is used, which points to the bottom of the previous frame.
The stack also has a "red zone" which extends 128 bytes below the stack pointer. If a function
does not need a frame or base pointer, it may write data into the red zone which is not needed
across function calls. So a leaf function which needs less than 128 bytes of stack space
need not update the stack pointer in its prolog or epilog at all.

The frame organization is illustrated as follows (with higher memory addresses at the top):

Position                     | Contents                       | Frame
---------------------------- | -------------------------------| -----------
`BP`                         |  unspecified                   | Previous
 ...                         | unspecified (aligment padding) | Current
   `FP` + *s*<br>...<br>`FP` | static-size objects            | Current
 `SP` + *d*<br>...<br>`SP`   | dynamic-size objects           | Current
 ...<br>`SP`-128             | small static-size objects      | Current (red zone)

Note: in other ABIs the frame pointer typically points to a saved frame pointer (and return address) 
at the top of the current frame. In this ABI the frame pointer points to the bottom of the current frame instead. 
This is because the constant offset
field of Wasm load and store instructions are unsigned; addresses of the form `FP` + *n* can be folded
into a single insruction, e.g. `i32.load offset=n`. This is also why the stack grows downward (so `SP` + *n*
can also be folded). One consequence of of the lack of return addresses and frame pointer chains is that there
is no way to traverse the linear stack. There is also no currently-specified way to determine which wasm local
is used as the frame pointer or base pointer. This functionality is not needed for backtracing or unwinding (since the
wasm VM must do this in any case); however it may still be desirable to allow this functionality for debugging
or in-field crash reporting. Future ABIs may designate a convention for determining frame size and local usage.

### Function signatures

Types can be passed directly via WebAssembly function parameters or indirectly
via a pointer parameter that points to the value in memory. The callee is
allowed to modify the contents of that memory, so the caller is responsible for
making a copy of any indirectly passed data that the callee should not modify.
Similarly, types can either be returned directly from WebAssembly functions or
returned indirectly via a pointer parameter prepended to the parameter list.

Type                         | Parameter     | Result   |
-----------------------------|---------------|----------|
scalar[1]                    | direct        | direct   |
empty struct or union        | ignored       | ignored  |
singleton struct or union[2] | direct        | direct   |
other struct or union[3]     | indirect      | indirect |
array                        | indirect      | N/A      |

[1] `long long double` is passed directly as two `i64` values.

[2] Any struct or union that recursively (including through nested structs,
unions, and arrays) contains just a single scalar value and is not specified to
have greater than natural alignment.

[3] This calling convention was defined before
[multivalue](https://github.com/WebAssembly/multi-value) was standardized. A new
default calling convention that changes this behavior and takes advantage of
multivalue may be introduced in the future.

Varargs are placed in a buffer by the caller and the last parameter to the
function is a pointer to that buffer. The callee is allowed to modify the
contents of the buffer, so the caller is responsible for making a copy of any
varargs data that the callee should not modify.

## Program startup

### User entrypoint

The *user entrypoint* is the function which runs the bulk of the program.
It is called `main` in C, C++, and other languages. Note that this may
not be the first function in the program to be called, as programs may
also have global constructors which run before it.

At the wasm C ABI level, the following symbol names are used:

C ABI Symbol name            | C and C++ signature                |
---------------------------- | -----------------------------------|
`main`                       | `int main(void)` or `int main()`   |
`__main_argc_argv`           | `int main(int argc, char *argv[])` |

These symbol names only apply at the ABI level; C and C++ source should
continue to use the standard `main` name, and compilers will handle the
details of conforming to the ABI.

Also note that C symbol names are distinct from WebAssembly export
names, which are outside the scope of the C ABI. Toolchains which export
the user entrypoint may chose to export it as the name `main`, even when
the C ABI symbol name is `__main_argc_argv`.

A symbol name other than `main` is needed because the usual trick of
having implementations pass arguments to `main` even when they aren't
needed doesn't work in wasm, which requires caller and callee signatures
to exactly match.

For the same reason, the wasm C ABI doesn't support an `envp` parameter.
Fortunately, `envp` is not required by C, POSIX, or any other relevant
standards, and is generally considered obsolete in favor of `getenv`.

### Program entrypoint

The *program entrypoint* is the first function in the program to be called.
It is commonly called `_start` on other platforms, though this is a
low-level detail that most code doesn't interact with.

The program entrypoint is out of scope for the wasm C ABI. It may depend
on what environment the program will be run in.
