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

| Field           | Type        | Description                    |
| ----------      | ----------- | ------------------------------ |
| memorysize      | `varuint32` | Size of the memory area the loader should reserve for the module, which will begin at `env.__memory_base` |
| memoryalignment | `varuint32` | The required alignment of the memory area, in bytes, encoded as a power of 2. |
| tablesize       | `varuint32` | Size of the table area the loader should reserve for the module, which will begin at `env.__table_base` |
| tablealignment  | `varuint32` | The required alignment of the table area, in elements, encoded as a power of 2. |

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

The "dylink" section should be the very first section in the module; this allows
detection of whether a binary is a dynamic library without having to scan the
entire contents.

## Interface and usage

A WebAssembly dynamic library must obey certain conventions.  In addition to
the `dylink` section described above a module may import the following globals
that will be provided by the dynamic loader:

 * The module can import `env.memory` for memory that is shared with the
   outside. If it does so, it should import `env.__memory_base`, an `i32`
   WebAssembly global, in which the loader will provide the start of the region
   in memory which has been reserved and zero-initialized for this module, as
   described earlier.  The module can use this global in the intializer of its
   data segments so that they loaded at the correct address.
 * The module can import `env.table` for a table that is shared with the
   outside. If it does so, it should import `env.__table_base`, an `i32`
   WebAssembly global, in which the loader will provide the start of the region
   in the table which has been reserved for this module, as described earlier.

### Relocations

WebAssembly dynamic libraies do not require relocations in the code section.
This allows for streaming complication and better code sharing, and reduces the
complexity of the dynamic linker.  This is acheived by referencing external
symbols via WebAssembly imports.  However relocation with the data segments may
still be required.  For example, if the address of an external symbol is stored
in static data.  In this case the dynamic library must generate code to apply
it own relocations on startup.

The module can export a function called `__post_instantiate`. If it is so
exported, the loader will call it after the module is instantiated, and before
any other function is called.  The `__post_instantiate` function is used both to
apply relocations and to run any static constructors.

(Note: the WebAssembly `start` function is not sufficient in all cases due to
reentrancy issues, i.e., the `start` function is called as the module is being
instantiated, before it returns its exports, so the outside cannot yet call into
the module.)

### Imports

Functions are directly imported from the `env` module (e.g.
`env.enternal_func `).  Data addresses and function addresses are imported as
functions that return the address.  This is because the final addresse of given
symbol might not be known until all modules are initialized.  These functions
are named with the `g$` prefix. For example `env.g$goo` can be imported and
used to access the address of `foo`.  In the futre this scheme could be
replaced with importing of mutable globals.

### Exports

Functions are directly exported as WebAssembly function exports.  Exported
addresses (i.e., exported memory locations or exported table locations) are
exported as i32 WebAssembly globals.  However since exports are static, modules
connect export the final relocated addresses (i.e. they cannot add
`__memory_base` before exporting). Thus, the exported address is before
relocation; the loader, which knows `__memory_base`, can then calculate the
final relocated address.

## Implementation Status

Emscripten can load WebAssembly dynamic libraries either at startup (using
`RUNTIME_LINKED_LIBS`) or dynamiclly (using `dlopen`/`dlsym`/etc).
See `test_dylink_*` adnd `test_dlfcn_*` in the test suite for examples.

Emscripten can create WebAssembly dynamic libraries with its `SIDE_MODULE`
option, see [the wiki](https://github.com/kripken/emscripten/wiki/WebAssembly-Standalone).

