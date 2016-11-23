WebAssembly Object File Linking
===============================

This document describes the early plans for how linking of WebAssembly modules
might work in the clang/LLVM WebAssembly backend and other tools.  As mentioned
in [README](README.md), it is not the only possible way to link WebAssembly
modules.  Note: the ABI described in the document is a work in progress and
**should not be considered stable**.

Each compilation unit is compiled with a single WebAssembly module.  Each
module contains a single code section and a single data section.  The goal
of the linker is to take two or more modules and merge them into single module.
In order to achieve this the following tasks need to be performed:

- Merging of function section (re-numbering functions)
- Merging of data segments (re-positioning data)
- Resolving undefined external references

The linking technique described here is designed to be fast, and avoid having
the decode the WebAssembly op-codes in the code section.  A `user-defined`
section called called "reloc" to used to store additional information required
by the linker.

The "reloc" section is defined as:

| Field   | Type                | Description                    |
| ------- | ------------------- | ------------------------------ |
| count   | `varuint32`         | count of entries to follow     |
| entries | `relocation_entry*` | sequence of relocation entries |

a `relocation_entry` is:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| type     | `varuint32`         | the relocation type            |

A relocation type can be one of the following:

- `0 - R_FUNCTION_INDEX_LEB` - a function index encoded as a LEB128.  Used
  for the immediate argument of a call instruction in the code section.
- `1 - R_FUNCTION_INDEX_SLEB` - a function index encoded as a signed LEB128.
  Used to refer to the immediate argument of an `i32.const` instruction
  in the code section. e.g. a local variable storing a function address.
- `2 - R_GLOBAL_INDEX` - a global index encoded as a LEB128.  Points to
  the immediate value of `get_global` / `set_global` instructions.
- `3 / R_DATA` - a wam global used to refer to a global data location

For `R_FUNCTION_INDEX_[U]LEB` and `R_GLOBAL_INDEX` relocations the following
fields are present:

| Field  | Type                | Description                           |
| ------ | ------------------- | ------------------------------------- |
| offset | `varuint32`         | offset of LEB within the code section |

For `R_DATA` relocations the following fields are presnet:

| Field         | Type              | Description                    |
| ------------- | ----------------- | ------------------------------ |
| global\_index | `varuint32`       | the index of the global used   |

Merging Globals
---------------

Merging of globals sections requires re-numbering of the globals.  To allow
this a `R_GLOBAL_INDEX` entry in the `reloc` section is generated for each
`get_global` / `set_global` instruction.  The immediate values of all
`get_global` / `set_global` instruction are stored as padded LEB123 such that
they can be rewritten without altering the side of the code section.

Merging Function Sections
-------------------------

Merging of the function sections requires the re-numbering of functions.  This
requires that modification code sections for at each location where a function
index is embedded.  There are currently two ways in which function indices are
used in the code section:

1. Immediate argument of the `call` instruction
2. Immediate argument of the `i32.load` instruction for address taken
   functions.

The immediate argument of all such instruction are stored as padded LEB123
such that they can be rewritten without altering the side of the code section.
For each such instruction a `R_FUNCTION_INDEX_LEB` or `R_FUNCTION_INDEX_SLEB`
`reloc` entry is generated pointing to the offset of the immediate within the
code section.

The same technique applies for all function calls whether the function is
imported or defined locally.

Merging Data Sections
---------------------

References to global data are modeled as loads or stores via a wasm
[global](https://github.com/WebAssembly/design/blob/master/Modules.md#global-variables).
Each C global is assigned a wasm global, and access to global variables will
generate a `get_global` followed by the load or store the resulting address.
The address stored in these wasm globals can then be set by the linker when it
relocates data segments.  For each wasm global that is used in this way an entry
in the `reloc` of type `R_DATA` is generated so that the linker knows which
wasm globals to modify.

External references
-------------------

Undefined external references are modeled as named [function
imports](https://github.com/WebAssembly/design/blob/master/Modules.md#imports).

Exported functions
------------------

Non-static functions are modeled as [function
exports](https://github.com/WebAssembly/design/blob/master/Modules.md#exports).
