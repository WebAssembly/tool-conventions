This document describes the "Basic" C ABI for WebAssembly. As mentioned in
[README](README.md), it's not the only possible C ABI. Its "C" calling
convention is used by the clang/LLVM WebAssembly backend and by other C or C++
compilers wishing to be ABI-compatible with it. The "wasm-multivalue" calling
convention described below is a proposal and is not yet implemented in LLVM.

# Versioning and Machine interface

The current version of this ABI is *1*.

The version 1 "C" calling convention is designed to work with Release 1.0 of
the WebAssembly [Specification](https://webassembly.github.io/spec/core/index.html). It does not require any
[features](https://github.com/WebAssembly/proposals)
that have not yet been implemented and standardized. The proposed
"wasm-multivalue" convention requires [multivalue] and does not change the
version 1 "C" convention.

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
 Integer | `int` / `signed int` | 4 | 4 | i32
 Integer | `unsigned int` | 4 | 4 | i32
 Integer | `enum` | underlying type | underlying type | underlying type
 Integer | `long` / `signed long` | 4 | 4 | i32
 Integer | `unsigned long` | 4 | 4 | i32
 Integer | `long long` / `signed long long` | 8 | 8 | i64
 Integer | `unsigned long long` | 8 | 8 | i64
 Integer | `__int128_t` | 16 | 16 | (none)
 Integer | `__uint128_t` | 16 | 16 | (none)
 Pointer | *`any-type *`* / *`any-type (*)()`* | 4 | 4 | i32
 Floating point | `float` | 4 | 4 | f32
 Floating point | `double` | 8 | 8 | f64
 Floating point | `long double` | 16 | 16 | (none)
 Floating point | `long double` (Emscripten) | 16 | 8 | (none)

 * `long double` values correspond to 128-bit IEEE-754 quad-precision binary128 values.
 Operations on these values are currently implemented as calls to
 compiler-rt library functions.
 * A null object or function pointer has the value zero. C++ pointers to
   members have distinct representations; in particular, a null pointer to
   a data member has the value `-1` (see the
   [Itanium-like C++ ABI](ItaniumLikeC++ABI.md)).
 * The `size_t` type is defined as `unsigned long`.
 * An `enum` uses the size, alignment, and Wasm value type of its underlying
   integer type. An enum without a fixed underlying type uses a 32-bit type
   if its values fit in `int` or `unsigned int`; otherwise, if the compiler
   supports such an enum, it uses a 64-bit type.
 * Emscripten uses 8 byte alignment for `long double`.
 * `__int128_t` and `__uint128_t` are passed as two `i64`s in little-endian
   order, and are otherwise represented in the ABI as a struct containing two
   `i64` fields, in little-endian order.
 * `_Complex` types are represented in the ABI as a struct containing two
   corresponding floating-point fields, real and imaginary.
 * `_BitInt(N)` types are supported up to width 128. Their Wasm value types
   match the smallest same-signedness integer type with at least *N* bits,
   but their memory size and alignment are as follows:

   Width *N* | Size (bytes) | Alignment (bytes)
   -|-|-
   1–8 | 1 | 1
   9–16 | 2 | 2
   17–32 | 4 | 4
   33–64 | 8 | 8
   65–128 | 16 | 8

   Bits in the storage beyond the declared width may be unspecified.

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

**SIMD Vector types**

The ABI for vector types is not stable and may change as new optimization opportunities are
found.

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

### Function arguments and return values

Types can be passed directly via WebAssembly function parameters or indirectly
via a pointer parameter that points to the value in linear memory. The callee is
allowed to modify the contents of that memory, so the caller is responsible for
making a copy of any indirectly passed data that the callee should not modify.
Similarly, types can either be returned directly from WebAssembly functions or
returned indirectly via a pointer parameter prepended to the parameter list.

Variadic arguments are placed in a buffer by the caller, and the last
parameter to the function is a pointer to that buffer. Arguments are arranged
in order, with each placed at the lowest appropriately aligned address after
the previous argument. This existing buffer convention is unchanged by
"wasm-multivalue"; variadic arguments are not flattened using its aggregate
classification. The callee may modify the buffer, so the caller is responsible
for making a copy of any data it should not modify.

The existing default calling convention is referred to as "C" and was created
before [multivalue] was available, so it allows only a single result. The
proposed "wasm-multivalue" convention requires [multivalue] and makes
additional changes to argument and result passing.

In both calling conventions, the way a parameter or result is passed is
determined by *classifying* its type. Classification assigns to each type
either the class INDIRECT, in which case the parameter or result is passed
indirectly as described above, or a (possibly empty) sequence of WebAssembly
value types, in which case the parameter or result is passed directly as that
sequence of WebAssembly values, in order, subject to the per-convention limits
described below.

A `void` return type is classified as the empty sequence.

For C++ types, the [Itanium-like C++ ABI](ItaniumLikeC++ABI.md#function-arguments-and-return-values)
specifies additional rules, including overrides and equivalent types applied
before the classification and flattening rules below.

#### Classification of scalar types

The following scalar types have the same classifications in both calling
conventions:

C type | Classification
-|-
`_Bool`/`bool`, 8, 16 and 32-bit integers, pointers | i32
64-bit integers | i64
`__int128_t` / `__uint128_t` | i64, i64 (low bits, then high bits)
`float` | f32
`double` | f64
`long double` | i64, i64 (low bits, then high bits)

An enum is classified as its underlying integer type. A `_BitInt(N)` has the
same classification as the integer type specified in
[Data Representation](#data-representation). Its actual memory size and
alignment, as specified there, are used when flattening aggregates.

When passed or returned as an individual scalar i32 value, signed integers
narrower than 32 bits are sign-extended and unsigned integers narrower than
32 bits are zero-extended, including from the declared width of a
`_BitInt(N)`.

#### Classification in the "C" calling convention

The "C" calling convention classifies types as follows:

* A scalar type other than `_Complex` is classified as the sequence of value
  types given above.
* A `_Complex` type is classified INDIRECT.
* A zero-sized struct or union is classified as the empty sequence, meaning
  that it is ignored and no values are passed for it.
* A struct or union with a single scalar field is classified as the type of
  that field. A "scalar field" of a struct or union is a field which
  recursively, through nested structs, unions, and arrays, contains just a
  single scalar value and is not specified to have greater than natural
  alignment. Each enclosing record must have the same size as the scalar.
  Zero-sized fields and unnamed bit-fields do not contribute scalar values,
  but their storage still counts toward the record's size. C++ base classes
  and fields are handled as described in the C++ ABI.
* All other struct and union types are classified INDIRECT.

A parameter is passed directly whenever its classification is not INDIRECT.

Because the "C" calling convention predates [multivalue], a function may
return at most one WebAssembly value. A result whose classification is
INDIRECT, or whose classification contains more than one value type (such as
the 128-bit scalars), is returned indirectly.

#### Classification in the "wasm-multivalue" calling convention

The "wasm-multivalue" calling convention classifies an aggregate by
*flattening* it into its leaf scalar fields and mapping those fields onto a
sequence of WebAssembly values. Integer fields are *bit-packed* into i32 and
i64 values, while floating-point fields are kept as individual f32 and f64
values.

For these rules, the term *integer field* includes fields of integer and enumeration
types, pointer types (including pointers to functions), and the synthetic integer fields
described below.

##### Flattening

The *flattened fields* of a type are an ordered list of scalar fields, each
with an assigned byte offset within the object, determined as follows:

* A `_Complex` type flattens as a struct with real and imaginary fields of
  its corresponding floating-point type, in that order.
* Other scalar types flatten to a single field of that type at offset 0.
* A struct flattens to the flattened fields of its members in declaration
  order, each at its offset within the struct.
* An array flattens to the flattened fields of its elements in index order,
  each at its offset within the array.
* A union with exactly one member flattens to the flattened fields of that
  member.
* A union with more than one member fails to flatten if it is larger than
  8 bytes or if any member's flattened fields are not all integer fields.
  Otherwise, it flattens to a single integer field covering the union's size.

If flattening a member or element fails, flattening its containing type also
fails.

A type whose flattening fails is classified INDIRECT. Flattening also fails
if any of the following hold:

* the type, or any struct, union, or array it recursively contains, has
  greater than natural alignment (e.g. via `_Alignas` or
  `__attribute__((aligned))`), or has a member with less than natural
  alignment (e.g. via `__attribute__((packed))`),
* the type recursively contains a bit-field,
* the type recursively contains a flexible array member.

##### Classification of flattened fields

In these rules, an *integer unit* is a group of one or more integer fields
represented by a single WebAssembly integer value.

A zero-sized struct or union is classified as the empty sequence, meaning
that it is ignored and no values are passed for it. Otherwise, the flattened
fields are mapped to a sequence of WebAssembly values, in offset order, as
follows:

* An f32 field is classified as an f32 value, and an f64 field is classified
  as an f64 value. Floating-point fields are never bit-packed together with
  other fields.
* A field wider than 64 bits (`__int128_t`, `__uint128_t`, `long double`,
  and `_BitInt(N)` with *N* greater than 64) is treated as two consecutive
  8-byte integer fields.
* Each maximal run of consecutive integer fields is bit-packed into one or
  more integer units:
  * The first field of a run begins the *current integer unit*, whose *base*
    is that field's offset.
  * For each subsequent field in the run, add it to the current integer unit
    if the field lies entirely within the 8 bytes starting at that unit's
    base and the unit would contain at most one field of 4 bytes or more.
    Otherwise, begin a new current integer unit with that field and set its
    base to the field's offset.
  * Each integer unit whose fields all lie within the 4 bytes starting at its
    base is classified as an i32 value; any other integer unit is classified
    as an i64 value.

Thus, two 32-bit integer fields cannot share a unit; for example, a struct
containing only two such fields is classified as two i32 values. Narrower
fields can still share a unit with a 32-bit field when they fit.

Intervening padding is not removed when packing fields: gaps between fields
count when determining whether they fit in the same unit and which value type
the unit uses. Padding before the first field or after the last field of a
unit does not by itself increase the unit's size.

> Rationale: retaining the fields' relative memory offsets can avoid
> shifting and masking to compact values that are already in memory. The
> trade-off is that padding can require more units and cause an aggregate to
> be passed indirectly.

Within an integer unit, each field occupies the same bits that it occupies in
the object's in-memory representation: a field at offset *o* of size *s*
bytes occupies bits 8 × (*o* − *base*) through 8 × (*o* − *base* + *s*) − 1
of the unit's value, counting bits from zero and following the little-endian
in-memory representation. Fields are never split across two units. Bits of a
unit that are not covered by any field (padding, and any bits above the last
field's end) have unspecified contents; in particular, fields narrower than
the unit are not sign- or zero-extended within it. Constructing a unit does
not require reading padding or bytes outside the object.

##### Parameter passing

A parameter is passed indirectly if its classification is INDIRECT, if its
classification contains more than 2 integer (i32 or i64) values, or if its
classification contains more than 4 floating-point (f32 or f64) values.
All other parameters are passed directly as their sequence of values. These
limits apply to each parameter individually; the number of parameters of a
function is not limited by this calling convention. Implementations and
embeddings may impose limits on the total WebAssembly function signature,
including parameters introduced by indirect results and varargs.

> Rationale: the limits are chosen so that small aggregates that native ABIs
> pass in registers — for example an RGBA color made of four 8-bit or 16-bit
> channels, a pointer-and-length pair, or a vector of four floats — are
> passed directly, without allowing a single aggregate parameter to expand
> into an unbounded number of WebAssembly parameters. The integer limit of 2
> units is inspired by the x86-64 psABI's limit of two eightbytes in
> general-purpose registers, but it does not imply that every 16-byte
> integer aggregate is passed directly. The separate floating-point limit
> of 4 values accommodates common vector types such as `vec4`.

##### Result passing

A result is returned indirectly if its classification is INDIRECT or if its
classification contains more than 100 values. All other results are returned
directly as their sequence of values; returning more than one value requires
[multivalue].

> Rationale: results are classified with the same algorithm as parameters,
> but with a much higher limit to support functions needing many results.
> The limit does not guarantee that every desired WebAssembly signature can
> be expressed or that every implementation supports the resulting function
> type.

#### Examples

Some example C function signatures, and their corresponding wasm32 function
signatures, are shown below. `__attribute__((wasm_multivalue))` denotes the
proposed calling convention and may not yet be implemented; the empty struct
and union use a C extension.

```c
#include <stdint.h>

// [] -> []
void f1(void);

// [f32 f64] -> [i32]
int f2(float, double);

// [i32 i64 i64] -> []
//    |   |   ^ high bits of parameter
//    |   ^ low bits of parameter
//    ^ return-pointer
__int128 f3(long double);

// [] -> []
struct Foo4 { };
union Bar4 { };
union Bar4 f4(struct Foo4);

// [i32] -> [i32]
struct Foo5 { int a; };
union Bar5 { int a; };
union Bar5 f5(struct Foo5);

// [i32 i32] -> []
//    |   ^ pointer to parameter
//    ^ return-pointer
struct Foo6 { int a; int b; };
struct Foo6 f6(struct Foo6);

// [i32 i32] -> [i32 i32]
//  32-bit integer fields are not packed together
struct Foo7 { int a; int b; };
__attribute__((wasm_multivalue))
struct Foo7 f7(struct Foo7);

// [] -> [i64 i64]
__attribute__((wasm_multivalue))
__int128 f8(void);

// [i32] -> [i32]
//  bits 0-7 = r, 8-15 = g, 16-23 = b, 24-31 = a
struct Rgba9 { uint8_t r; uint8_t g; uint8_t b; uint8_t a; };
__attribute__((wasm_multivalue))
struct Rgba9 f9(struct Rgba9);

// [i64] -> [i64]
//  array elements are flattened and bit-packed like ordinary fields
struct Pixel10 { uint16_t channels[4]; };
__attribute__((wasm_multivalue))
struct Pixel10 f10(struct Pixel10);

// [f32 f32 f32 f32] -> [f32 f32 f32 f32]
//  floating-point fields are passed as individual values, never bit-packed
struct Vec11 { float x; float y; float z; float w; };
__attribute__((wasm_multivalue))
struct Vec11 f11(struct Vec11);

// [f32 i64] -> [f32 i64]
//  bits 0-15 = id, 16-31 = flags, 32-63 = next
struct Entity12 { float scale; uint16_t id; uint16_t flags; uint32_t next; };
__attribute__((wasm_multivalue))
struct Entity12 f12(struct Entity12);

// [i32] -> [i32]
//  all members flatten to integer fields and the union is 4 bytes
union Bits13 { uint32_t word; uint8_t bytes[4]; };
__attribute__((wasm_multivalue))
union Bits13 f13(union Bits13);

// [i32] -> [i64 i64 i64]
//    ^ pointer to parameter (more than 2 integer values)
struct Big14 { uint64_t a; uint64_t b; uint64_t c; };
__attribute__((wasm_multivalue))
struct Big14 f14(struct Big14);

// [i32 i32] -> [i32 i32]
//  32-bit array elements remain separate values
struct Pair15 { uint32_t values[2]; };
__attribute__((wasm_multivalue))
struct Pair15 f15(struct Pair15);

// [i32] -> [i32 i32 i32]
//    ^ pointer to parameter (more than 2 integer values)
struct Triple16 { uint32_t values[3]; };
__attribute__((wasm_multivalue))
struct Triple16 f16(struct Triple16);

// [i64 i32] -> [i64 i32]
//  channels share an i64; tag occupies a separate i32
struct Pixel17 { uint16_t channels[4]; uint32_t tag; };
__attribute__((wasm_multivalue))
struct Pixel17 f17(struct Pixel17);

// [i64 i32] -> [i64 i32]
//  a and b share an i64 with a padding gap between them; c uses an i32
struct Mixed18 { uint16_t a; uint32_t b; uint16_t c; };
__attribute__((wasm_multivalue))
struct Mixed18 f18(struct Mixed18);

// [i64] -> [i64]
//  the wasm32 pointer and length share an integer unit
struct Buffer19 { void *data; uint16_t length; };
__attribute__((wasm_multivalue))
struct Buffer19 f19(struct Buffer19);

// [i64] -> [i64]
enum Wide20 { wide_value = 1LL << 40 };
__attribute__((wasm_multivalue))
enum Wide20 f20(enum Wide20);

// [f32 f32] -> [f32 f32]
//  real and imaginary parts are separate floating-point fields
__attribute__((wasm_multivalue))
float _Complex f21(float _Complex);

// [i32 i32] -> []
//  the "C" convention passes the complex argument and result indirectly
float _Complex f22(float _Complex);

struct Hundred26 { float values[100]; };
// [i32] -> [100 f32 values]
//  the argument exceeds the parameter limit, but the result is within its limit
__attribute__((wasm_multivalue))
struct Hundred26 f26(struct Hundred26);

struct HundredOne27 { float values[101]; };
// [i32 i32] -> [] (return pointer, then parameter pointer)
//  both the argument and result exceed their respective limits
__attribute__((wasm_multivalue))
struct HundredOne27 f27(struct HundredOne27);
```

Note that the "C" ABI is the default ABI used in C, and using the
"wasm-multivalue" ABI would require an explicit opt-in. While the default
calling convention may change in the future, that is not currently planned.
When the proposed convention is implemented, programs can use either
convention to define functions, but the caller and callee calling convention
must match when a call is made.

To use the proposed "wasm-multivalue" calling convention the [`multivalue`
target feature](./Linking.md#target-features-section) must be enabled. It is a
compiler error to use this calling convention when the target feature is not
enabled. Enabling the `multivalue` target feature does not change the "C"
calling convention; it only enables usage of "wasm-multivalue".

[multivalue]: https://github.com/WebAssembly/multi-value

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
