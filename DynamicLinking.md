WebAssembly Dynamic Linking
===========================

This document describes the early plans for how dynamic linking of WebAssembly
modules might work.

Note: there is no stable ABI here yet.

# Dynamic Libraries

A WebAssembly dynamic library is a WebAssembly binary with a special custom
section that indicates this is a dynamic library and contains additional
information needed by the loader.

## The "dylink" Section

The "dylink" section is defined as:

| Field                  | Type            | Description                    |
| ---------------------- | --------------- | ------------------------------ |
| memorysize             | `varuint32`     | Size of the memory area the loader should reserve for the module, which will begin at `env.__memory_base` |
| memoryalignment        | `varuint32`     | The required alignment of the memory area, in bytes, encoded as a power of 2. |
| tablesize              | `varuint32`     | Size of the table area the loader should reserve for the module, which will begin at `env.__table_base` |
| tablealignment         | `varuint32`     | The required alignment of the table area, in elements, encoded as a power of 2. |
| needed_dynlibs_count   | `varuint32`     | Number of needed shared libraries |
| needed_dynlibs_entries | `dynlib_entry*` | Repeated dynamic library entries as described below |

The "dynlib_entry" type is defined as:

| Field           | Type        | Description                    |
| --------------- | ----------- | ------------------------------ |
| dynlib_name_len | `varuint32` | Length of `dynlib_name_str` in bytes |
| dynlib_name_str | `bytes`     | Name of a needed dynamic library: valid UTF-8 byte sequence |

`env.__memory_base` and `env.__table_base` are `i32` imports that contain
offsets into the linked memory and table, respectively. If the dynamic library
has `memorysize > 0` then the loader will reserve room in memory of that size
and initialize it to zero (note: can be larger than the memory segments in the
module, if the dynamic library wants additional space) at offset
`env.__memory_base`, and similarly for the table (where initialization is to
`null`, i.e., a trap will occur if it is called). The allocated regions of the
table and memory are guaranteed to be at least as aligned as the library
requests in the `memoryalignment, tablealignment` properties. The library can
then place memory and table segments at the proper locations using those
imports.

If `needed_dynlibs_count > 0` then the loader, before loading the library, will
first load needed libraries specified by `needed_dynlibs_entries`.

The "dylink" section should be the very first section in the module; this allows
detection of whether a binary is a dynamic library without having to scan the
entire contents.

## Interface and usage

A WebAssembly dynamic library has some conventions for how it should be loaded
and used:

 * The module can import `env.memory` for memory that is shared with the
   outside. If it does so, it should import `env.__memory_base`, an `i32`, in
   which the loader will provide the start of the region in memory which has
   been reserved and zero-initialized for this module, as described earlier.
 * The module can import `env.table` for a table that is shared with the
   outside. If it does so, it should import `env.__table_base`, an `i32`, in
   which the loader will provide the start of the region in the table which has
   been reserved for this module, as described earlier.
 * The module can export a function called `__post_instantiate`. If it is so
   exported, the loader will call it after the module is instantiated, at a time
   when it is ready to be used. (Note: the WebAssembly `start` function is not
   sufficient in all cases due to reentrancy issues, i.e., the `start` function
   is called as the module is being instantiated, before it returns its exports,
   so the outside cannot yet call into the module.)
 * While exported functions are straightforward, exported addresses (i.e.,
   exported indexes of locations in memory or in the table) are exported
   *before* the loaded module can apply any relocation, since the module cannot
   add `__memory_base` before it exports them. Thus, the exported address is
   before relocation; the loader, which knows `__memory_base`, can then
   calculate the proper relocated and final address of those addresses.

## Implementation Status

Emscripten can load WebAssembly dynamic libraries using `dlopen` and access them
using `dlsym`, etc. (See `test_dlfcn_*` in the test suite for examples;
`test_dylink_*` are relevant as well.)

Emscripten can create WebAssembly dynamic libraries with its `SIDE_MODULE`
option, see [the wiki](https://github.com/kripken/emscripten/wiki/WebAssembly-Standalone).

