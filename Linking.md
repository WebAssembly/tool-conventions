WebAssembly Object File Linking
===============================

This document describes the early plans for how linking of WebAssembly modules
might work in the clang/LLVM WebAssembly backend and other tools.  As mentioned
in [README](README.md), it is not the only possible way to link WebAssembly
modules.  Note: the ABI described in the document is a work in progress and
**should not be considered stable**.

Each compilation unit is compiled as a single WebAssembly module.  Each
module contains a single code section and a single data section.  The goal
of the linker is to take two or more modules and merge them into single module.
In order to achieve this the following tasks need to be performed:

- Merging of function sections (re-numbering functions)
- Merging of globals sections (re-numbering globals)
- Merging of data segments (re-positioning data)
- Resolving undefined external references

The linking technique described here is designed to be fast, and avoids having
the disassemble the the code section.  The relocation information required by
the linker is stored in custom sections whose names begin with "reloc.".  For
each section that requires relocation a "reloc" section will be present in the
wasm file.  By convension the reloc section names end with name of the section
thet they refer to: e.g. "reloc.CODE" for code section relocations.  However
everything after the period is ignored and the specific target section is
encoded in the reloc section itself.

Relocation Sections
-------------------

A relocation section is a user-defined section with a name starting with
"reloc." Relocation sections start with an identifier specifying which
section they apply to, and must be sequenced in the module after that
section.

Relocation contain the following fields:

| Field      | Type                | Description                    |
| -----------| ------------------- | ------------------------------ |
| section_id | `varuint32`         | the section to which the relocations refer. |
| name_len   | `varuint32` ?       | the length of name in bytes, present if `section_id == 0` |
| name       | `bytes` ?           | the name of custom section, present if `section_id == 0` |
| count      | `varuint32`         | count of entries to follow     |
| entries    | `relocation_entry*` | sequence of relocation entries |

A `relocation_entry` is:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| type     | `varuint32`         | the relocation type            |

A relocation type can be one of the following:

- `0 / R_WEBASSEMBLY_FUNCTION_INDEX_LEB` - a function index encoded as a 5-byte
  [varuint32]. Used for the immediate argument of a `call` instruction.
- `1 / R_WEBASSEMBLY_TABLE_INDEX_SLEB` - a function table index encoded as a
  5-byte [varint32]. Used to refer to the immediate argument of a `i32.const`
  instruction, e.g. taking the address of a function.
- `2 / R_WEBASSEMBLY_TABLE_INDEX_I32` - a function table index encoded as a
  [uint32], e.g. taking the address of a function in a static data initializer.
- `3 / R_WEBASSEMBLY_MEMORY_ADDR_LEB` - a linear memory index encoded as a 5-byte
  [varuint32]. Used for the immediate argument of a `load` or `store`
  instruction, e.g. directly loading from or storing to a C++ global.
- `4 / R_WEBASSEMBLY_MEMORY_ADDR_SLEB` - a linear memory index encoded as a 5-byte
  [varint32]. Used for the immediate argument of a `i32.const` instruction,
  e.g. taking the address of a C++ global.
- `5 / R_WEBASSEMBLY_MEMORY_ADDR_I32` - a linear memory index encoded as a
  [uint32], e.g. taking the address of a C++ global in a static data
  initializer.
- `6 / R_WEBASSEMBLY_TYPE_INDEX_LEB` - a type table index encoded as a
  5-byte [varuint32], e.g. the type immediate in a `call_indirect`.
- `7 / R_WEBASSEMBLY_GLOBAL_INDEX_LEB` - a global index encoded as a
  5-byte [varuint32], e.g. the type immediate in a `get_global`.

[varuint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varuintn
[varint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varintn
[uint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#uintn

For `R_WEBASSEMBLY_FUNCTION_INDEX_LEB`, `R_WEBASSEMBLY_TABLE_INDEX_SLEB`,
and `R_WEBASSEMBLY_TABLE_INDEX_I32` relocations the following fields are
present:

| Field  | Type             | Description                              |
| ------ | ---------------- | ---------------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite           |
| index  | `varuint32`      | the index of the function used           |

For `R_WEBASSEMBLY_MEMORY_ADDR_LEB`, `R_WEBASSEMBLY_MEMORY_ADDR_SLEB`,
and `R_WEBASSEMBLY_MEMORY_ADDR_I32` relocations the following fields are
present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite      |
| index  | `varuint32`      | the index of the global used        |
| addend | `varint32`       | addend to add to the address        |

For `R_WEBASSEMBLY_TYPE_INDEX_LEB` relocations the following fields are
present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite      |
| index  | `varuint32`      | the index of the type used          |

For `R_WEBASSEMBLY_GLOBAL_INDEX_LEB` relocations the following fields
are present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite      |
| index  | `varuint32`      | the index of the global used        |

Linking Metadata Sections
-------------------------

A linking metadata section is a user-defined section with the name
"linking".

A linking metadata section contains a series of sub-sections layed
out in the same way as the ["names"][names_sec] section:

| Field        | Type        | Description                          |
| -------------| ------------| ------------------------------------ |
| type         | `varuint7`  | code identifying type of subsection  |
| payload_len  | `varuint32` | size of this subsection in bytes     |
| payload_data | `bytes`     | content of this subsection, of length `payload_len` |

The current list of valid `type` codes are:

- `0 / WASM_STACK_POINTER` - This specifies which global variable is to be
  treated as the stack pointer.

- `1 / WASM_SYMBOL_INFO` - Specifies extra information about the symbols present
  in the module.

For `WASM_STACK_POINTER` the following fields are present in the
subsection:

| Field  | Type        | Description                                    |
| ------ | ------------| ---------------------------------------------- |
| index  | `varuint32` | index of the global which is the stack pointer |

For `WASM_SYMBOL_INFO` the following fields are present in the
subsection:

| Field  | Type            | Description                  |
| -------| --------------- | -----------------------------|
| count  | `varuint32`     | number of `syminfo` in infos |
| infos  | `syminfo*`      | sequence of `syminfo`        |

where a `syminfo` is encoded as:

| Field        | Type           | Description                                 |
| -------------| -------------- | ------------------------------------------- |
| name_len     | `varuint32`    | length of `name_str` in bytes               |
| name_str     | `bytes`        | UTF-8 encoding of the name                  |
| flags        | `varuint32`    | a bitfield containing flags for this symbol |

The current set of valid flags for symbols are:

- `1 / WASM_SYM_FLAG_WEAK` - Indicating that this is a weak symbol


Merging Global Section
----------------------

Merging of globals sections requires re-numbering of the globals.

The global identified in the linking metadata section as the stack pointer is
handled specially. During linking, only one of these globals is kept, and all
references to stack-pointer globals are rewritten to use it.

Merging Function Sections
-------------------------

Merging of the function sections requires the re-numbering of functions.  This
requires modification to code sections at each location where a function
index is embedded.  There are currently two ways in which function indices are
stored in the code section:

1. Immediate argument of the `call` instruction (calling a function)
2. Immediate argument of the `i32.const` instruction (taking the address of a
   function).

The immediate argument of all such instruction are stored as padded LEB123
such that they can be rewritten without altering the size of the code section.
For each such instruction a `R_WEBASSEMBLY_FUNCTION_INDEX_LEB` or
`R_WEBASSEMBLY_TABLE_INDEX_SLEB` `reloc` entry is generated pointing to the
offset of the immediate within the code section.

The same technique applies for all function calls whether the function is
imported or defined locally.

Merging Data Sections
---------------------

References to global data are modeled as loads or stores via a wasm
[global](https://github.com/WebAssembly/design/blob/master/Modules.md#global-variables).
Each C global is assigned a wasm global, and access to C global variables will
generate a `get_global` followed by a load/store to/from the resulting address.
The addresses stored in these wasm globals can then be set by the linker when it
relocates data segments.  For each wasm global that is used in this way an entry
in the `reloc` of type `R_DATA` is generated so that the linker knows which
wasm globals require modification.

External references
-------------------

Undefined external references are modeled as named [function
imports](https://github.com/WebAssembly/design/blob/master/Modules.md#imports).

Exported functions
------------------

Non-static functions are modeled as [function
exports](https://github.com/WebAssembly/design/blob/master/Modules.md#exports).

[names_sec]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#name-section
