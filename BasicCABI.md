This document describes the "Basic" C ABI for WebAssembly. As mentioned in
[README](README.md), it's not the only possible C ABI. It is the ABI that the
clang/LLVM WebAssembly backend is currently using, and any other C or C++
compiler wishing to be ABI-compatible with it.


## Data Representation

**Scalar Types**

The ABI for the currently-specifed version of WebAssembly (also known as "wasm32") uses an "ILP32" data model, 
where `int`, `long`, and pointer types are 32 bits. It is expected that the proposed extension to allow memories
larger than 4GB ("wasm64") will use an "LP64" data model, where `int` and `long` are 64 bits.

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
 



*** 3 lines to avoid merge conflict with prevous PR, TODO remove ***

**Aggregates and Unions**

Structures and unions assume the alignment of their most strictly aligned component.
Each member is assigned to the lowest available offset with the appropriate
alignment. The size of any object is always a multiple of the object‘s alignment.
An array uses the same alignment as its elements, except that a local or global
array variable of length at least 16 bytes or a C99 variable-length array variable
always has alignment of at least 16 bytes.
Structure and union objects can require padding to meet size and alignment
constraints. The contents of any padding is undefined.

**Bitfields**

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

• bit-fields are allocated from right to left
• bit-fields must be contained in a storage unit appropriate for its declared
type
• bit-fields may share a storage unit with other struct / union members
Unnamed bit-fields’ types do not affect the alignment of a structure or union.

Bitfield type | Witdh *w* | Range
-|-|-
`signed char`, | 1 to 8 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`char`, `unsigned char` | 1 to 8 | 0 to 2<sup>w</sup>-1
`signed short`, | 1 to 16 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`short`, `unsigned short` | 1 to 16 | 0 to 2<sup>w</sup>-1
`signed int`, | 1 to 32 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`int`, `unsigned int` | 1 to 32 | 0 to 2<sup>w</sup>-1
`signed long long`, | 1 to 64 | -2<sup>(w-1)</sup> to 2<sup>(w-1)</sup>-1
`long long`, `unsigned long long` | 1 to 64 | 0 to 2<sup>w</sup>-1
