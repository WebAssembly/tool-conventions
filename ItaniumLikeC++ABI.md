This document describes the "Itanium-like" C++ ABI for WebAssembly. As mentioned
in [README](README.md), it's not the only possible C++ ABI or even the only
possible Itanium-derived C++ ABI for WebAssembly. It is the ABI that the
clang/LLVM WebAssembly backend is currently using, and any other C++ compiler
wishing to be ABI-compatible with it.

Most details follow
[the base Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html).

The following is a brief summary of deviations from this base:

 - The least-significant bit of the `adj` field of a member-function pointer is
   used to indicate whether the indicated function is virtual.
 - Member functions are not specially aligned.
 - Constructors and destructors return `this`.
 - Guard variables are 32-bit on wasm32.
 - Unused bits of guard variables are reserved.
 - Inline functions are never key functions.
 - C++11 POD rules are used to determine tail padding.

## Function arguments and return values

The [Basic C ABI](BasicCABI.md#function-arguments-and-return-values) defines
the calling conventions and their classification rules. The following C++
rules modify how those rules apply.

A class type that is
[non-trivial for the purposes of calls](https://itanium-cxx-abi.github.io/cxx-abi/abi.html#non-trivial)
is passed and returned indirectly, regardless of its classification under the
Basic C ABI. The Itanium C++ ABI also specifies construction and destruction
of the objects used for these calls.

Otherwise, C++ types are classified using these equivalent representations,
whether they are parameters, results, or fields of an aggregate:

* A reference is passed or returned as a pointer to its referent.
* A pointer to a data member is classified as `ptrdiff_t`.
* A pointer to a member function is classified as a struct containing its
  pointer and adjustment components in the representation described above.

For the "C" calling convention, an
[empty C++ class](https://itanium-cxx-abi.github.io/cxx-abi/abi.html#definitions)
or union passed or returned as a value is ignored, even though its size can
be nonzero. When determining whether a class is empty for classification or
has a single scalar field, empty base classes and empty `[[no_unique_address]]`
class-type fields are ignored, and non-empty base classes are treated like
fields. An ordinary class-type member is not ignored merely because its type
is empty.

For the proposed "wasm-multivalue" calling convention, a non-union C++ class
is flattened by recursively flattening each direct non-virtual base subobject
and each non-static data member. The fields retain their offsets within the
complete object and are ordered by increasing offset. An empty base contributes
no fields. The base's fields are classified together with the other fields of
the complete object, not separately. The Basic C ABI's flattening restrictions
also apply recursively to base subobjects.

Flattening fails if the type is, or recursively contains, a C++ class with a
virtual base or a potentially-overlapping non-static data member. The type is
then classified INDIRECT. These restrictions do not apply to a class merely
referenced by a pointer or reference.

For example, the following C++ function signatures have the indicated wasm32
signatures. The `wasm_multivalue` attribute denotes the proposed calling
convention and may not yet be implemented.

```c++
struct Empty23 {};
// [] -> [] in the "C" convention, despite sizeof(Empty23) == 1
Empty23 f23(Empty23);

struct Member23 { Empty23 e; };
// [i32 i32] -> [] in the "C" convention (ordinary empty member)
Member23 f23_member(Member23);

struct Base24 { int a; };
struct Derived24 : Base24 { int b; };
// [i32 i32] -> [i32 i32]
//  a is flattened from the base subobject; b is a member of Derived24
__attribute__((wasm_multivalue))
Derived24 f24(Derived24);

struct EmptyBase24 : Empty23 { int value; };
// [i32] -> [i32] (the empty base contributes no value)
__attribute__((wasm_multivalue))
EmptyBase24 f24_empty(EmptyBase24);

struct Owner25 { void method(); };
using Method25 = void (Owner25::*)();
// [i32 i32] -> [i32 i32] (pointer and adjustment components)
__attribute__((wasm_multivalue))
Method25 f25(Method25);

struct Overlapping28 { [[no_unique_address]] Empty23 e; int value; };
// [i32 i32] -> [] (return pointer, then parameter pointer)
__attribute__((wasm_multivalue))
Overlapping28 f28(Overlapping28);

struct Left29 { unsigned short a; };
struct Right29 { unsigned short b; };
struct Multi29 : Left29, Right29 {};
// [i32] -> [i32] (a in bits 0-15, b in bits 16-31)
__attribute__((wasm_multivalue))
Multi29 f29(Multi29);

struct PadBase30 { int x; char y; PadBase30() {} };
struct Reuse30 : PadBase30 { char z; };
// [i64] -> [i64] (x at byte 0, y at byte 4, z at byte 5)
//  z occupies a byte of the base subobject's tail padding
__attribute__((wasm_multivalue))
Reuse30 f30(Reuse30);
```

The following are ideas for additional deviations that are being considered:

 - The Itanium C++ name mangling rules have special-case abbreviations for
   std::string, std::allocator, and a few others, however libc++ doesn’t get to
   take advantage of them because it uses a versioned namespace. It may be
   useful to add new special-cases to cover libc++’s mangled names for
   std::string et al.
 - There’s an interesting idea for a vtable optimization described
   [here](https://llvm.org/bugs/show_bug.cgi?id=26723) that’s worth thinking
   about.
 - Alternatively, the design of vtables may radically change to take better
   advantage of WebAssembly’s function table mechanisms.
 - Trivially copyable classes may be passed by value rather than by pointer.
   This would cover a lot of common C++ classes such as std::pair.

This is just an initial sketch of the kind of content we plan to have here.
Obviously it would be desirable to go into a lot more detail.
