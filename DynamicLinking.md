WebAssembly Dynamic Linking
===========================

This document describes the early plans for how dynamic linking of WebAssembly modules might work.

# Shared Libraries

A WebAssembly shared library has some conventions for how it should be loaded and used:

 * The module can import `env.memory` for memory that is shared with the outside. If it does so, it should import `env.memoryBase`, an `i32`, in which the loader will provide the start of the region in memory which has been reserved for this module.
 * The module can import `env.table` for a table that is shared with the outside. If it does so, it should import `env.tableBase`, an `i32`, in which the loader will provide the start of the region in the table which has been reserved for this module.
 * The module can export a function called `__start_module`. If it is so exported, the loader will call it after creating the module and before it is used. (Note: the WebAssembly `start` method is not sufficient in all cases due to reentrancy issues, i.e., the `start` method is called as the module is being instantiated, before it returns its exports, so the outside cannot yet call into the module.)
 * While exported functions are straightforward, exported globals - i.e., exported addresses of locations in memory - are done *before* relocation. This is necessary since the module cannot add `memoryBase` before it exports them. The loader, which knows `memoryBase`, adds it to those exports before they are used.

The loader must know how much space in the memory and table to reserve for the module, and must know that *before* the module is created. To that end, a WebAssembly shared library is a small wrapper around a WebAssembly module, with suffix `.wso` (WebAssembly Shared Object), and contents

 * 4 bytes: `\0wso`
 * 8 bytes: Size of the memory area the loader should reserve for the module, which will begin at `memoryBase` (unsigned little-endian integer) (note: can be larger than the memory segments in the module)
 * 8 bytes: Size of the table area the loader should reserve for the module, which will begin at `tableBase` (unsigned little-endian integer)
 * The rest of the file is the WebAssembly module itself.

## Implementation Status

Emscripten can load WebAssembly shared libraries using `dlopen` and access them using `dlsym`, etc. (See `test_dlfcn_*` in the test suite for examples; `test_dylink_*` are relevant as well.)

Emscripten can create WebAssembly shared libraries with its `SIDE_MODULE` option, see [the wiki](https://github.com/kripken/emscripten/wiki/WebAssembly-Standalone).

