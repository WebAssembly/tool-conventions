This document describes the "Itanium-like" C++ ABI for WebAssembly. As mentioned
in [README](README.md), it's not the only possible C++ ABI or even the only
possible Itanium-derived C++ ABI for WebAssembly. It is the ABI that the
clang/LLVM WebAssembly backend is currently using, and any other C++ compiler
wishing to be ABI-compatible with it.

Most details follow
[the base Itanium C++ ABI](https://mentorembedded.github.io/cxx-abi/abi.html).

The following is a brief summary of deviations from this base:

 - The least-significant bit of the `adj` field of a member-function pointer is
   used to indicate whether the indicated function is virtual.
 - Member functions are not specially aligned.
 - Constructors and destructors return `this`.
 - Guard variables are 32-bit on wasm32.
 - Unused bits of guard variables are reserved.
 - Inline functions are never key functions.
 - C++11 POD rules are used to determine tail padding.

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
