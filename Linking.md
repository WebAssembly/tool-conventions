WebAssembly Object File Linking
===============================

This document describes the early plans for how static linking of WebAssembly
might work in the clang/LLVM WebAssembly backend and other tools.  As mentioned
in [README](README.md), it is not the only possible way to link WebAssembly
modules.  Note: the ABI described in the document is a work in progress and
**should not be considered stable**.

Each compilation unit is compiled as a "relocatable" WebAssembly module.  These
modules are not expected to be directly executable and have certain
constraints on them, but are otherwise well-formed WebAssembly modules.  In
order to distinguish relocatable modules the linker can check for the presence
of the ["linking"](#linking-metadata-section) custom section which must exist in
all relocatable modules.

The goal of the linker is to take one or more modules and merge them into
single executable module.  In order to achieve this the following tasks need to
be performed:

- Merging of function sections (re-numbering functions)
- Merging of globals sections (re-numbering globals)
- Merging of data segments (re-positioning data)
- Resolving undefined external references

The linking technique described here is designed to be fast, and avoids having
to disassemble the code section.  The extra metadata required by the linker
is stored in a custom ["linking"](#linking-metadata-section) section and zero or
more relocation sections whose names begin with "reloc.".  For each section that
requires relocation a "reloc" section will be present in the wasm file.  By
convention the reloc section names end with name of the section that they refer
to: e.g. "reloc.CODE" for code section relocations.  However everything after
the period is ignored and the specific target section is encoded in the reloc
section itself.

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
  5-byte [varuint32], e.g. the index immediate in a `get_global` (Not currently
  used by llvm).

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

Linking Metadata Section
------------------------

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

- `1 / WASM_SYMBOL_INFO` - Specifies extra information about the symbols present
  in the module.

- `2 / WASM_DATA_SIZE` - Specifies the total size of the static data used by the
  module, including both initialized and zero-initialized (bss) data.
  Note that this is similar to the "minimum" field in the linear memory
  description, however it's in units of bytes, so it's not limited to being
  a multiple of the page size.

- `3 / WASM_DATA_ALIGNMENT` - Specifies the alignment of the data section.  This
  tells the linking what constraints are placed on the location of the data
  section in the final binary.

- `6 / WASM_COMDAT_INFO` - Specifies the COMDAT groups of associated linking
  objects, which are linked only once and all together.

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

- `1 / WASM_SYM_BINDING_WEAK` - Indicating that this is a weak symbol.  When
  linking multiple modules defining the same symbol, all weak definitions are
  discarded if any strong definitions exist; then if multiple weak definitions
  exist all but one (unspecified) are discarded; and finally it is an error if
  more than one definition remains.
- `2 / WASM_SYM_BINDING_LOCAL` - Indicating that this is a local symbol (this
  is exclusive with `WASM_SYM_BINDING_WEAK`). Local symbols are not to be
  exported, or linked to other modules/sections.
- `4 / WASM_SYM_VISIBILITY_HIDDEN` - Indicating that this is a hidden symbol.
  Hidden symbols are not to be exported when performing the final link, but
  may be linked to other modules.

For `WASM_DATA_SIZE` the following fields are present in the
subsection:

| Field  | Type        | Description                                    |
| ------ | ------------| ---------------------------------------------- |
| size   | `varuint32` | size of the module's static data in bytes      |

For `WASM_DATA_ALIGNMENT` the following fields are present in the
subsection:

| Field  | Type        | Description                                    |
| ------ | ------------| ---------------------------------------------- |
| align  | `varuint32` | alignment requirement of the data stored as a power of 2 (`log2(alignment)`) |

For `WASM_COMDAT_INFO` the following fields are present in the
subsection:

| Field   | Type        | Description                                    |
| ------- | ------------| ---------------------------------------------- |
| count   | `varuint32` | Number of `Comdat` in `comdats`                |
| comdats | `Comdat*`   | Sequence of `Comdat`

where a `Comdat` is encoded as:

| Field       | Type         | Description                               |
| ----------- | ------------ | ----------------------------------------- |
| name_len    | `varuint32`  | length of `name_str` in bytes             |
| name_str    | `bytes`      | UTF-8 encoding of the name                |
| flags       | `varuint32`  | Must be zero, no flags currently defined  |
| count       | `varuint32`  | Number of `ComdatSym` in `comdat_syms`    |
| comdat_syms | `ComdatSym*` | Sequence of `ComdatSym`                   |

and where a `ComdatSym` is encoded as:

| Field    | Type           | Description                                 |
| -------- | -------------- | ------------------------------------------- |
| kind     | `varuint32`    | Type of symbol, one of:                     |
|          |                |   * `0 / WASM_COMDATA_DATA`, a data segment |
|          |                |   * `1 / WASM_COMDATA_FUNCTION`             |
| index    | `varuint32`    | Index of the symbol in the Wasm object      |


Merging Global Section
----------------------

Global data symbols (C/C+ globals) are represented in the object file as wasm
globals.  Defined symbols are modeled as exported I32 globals that contain the
address of the symbol in linear memory.  Undefined globals are modeled as
imported I32 globals.  These wasm globals are not used at runtime (i.e. there
are no `get_global/set_global` instructions that reference them) but are instead
referenced by `R_WEBASSEMBLY_MEMORY_ADDR*` relocation entries.

In the final linked binary all these globals are resolved and the only remaining
wasm global is the one that stores the explicit stack pointer.

Merging Function Sections
-------------------------

Merging of the function sections requires the re-numbering of functions.  This
requires modification to code sections at each location where a function
index is embedded.  There are currently two ways in which function indices are
stored in the code section:

1. Immediate argument of the `call` instruction (calling a function)
2. Immediate argument of the `i32.const` instruction (taking the address of a
   function).

The immediate argument of all such instruction are stored as padded LEB128
such that they can be rewritten without altering the size of the code section.
For each such instruction a `R_WEBASSEMBLY_FUNCTION_INDEX_LEB` or
`R_WEBASSEMBLY_TABLE_INDEX_SLEB` `reloc` entry is generated pointing to the
offset of the immediate within the code section.

The same technique applies for all function calls whether the function is
imported or defined locally.

Merging Data Sections
---------------------

The output data section is formed, essentially, by concatenating the data
sections of the input files.  Since the final location in linear memory of any
given symbol (C global) is not known until link time, all references to global
addresses with the code and data sections generate `R_WEBASSEMBLY_MEMORY_ADDR_*`
relocation entries.  The compiler ensures that each C global is assigned a wasm
[global](https://github.com/WebAssembly/design/blob/master/Semantics.md#global-variables)
and references to C globals generate relocations referencing the corresponding
wasm global.  The addresses stored in these wasm globals are offsets into the
linear memory of the object file in question.  In this way the wasm globals act
as symbol table mapping names to addresses in linear memory.

External references
-------------------

Undefined external references are modeled as named [function
imports](https://github.com/WebAssembly/design/blob/master/Modules.md#imports).

Exported functions
------------------

Non-static functions are modeled as [function
exports](https://github.com/WebAssembly/design/blob/master/Modules.md#exports).

[names_sec]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#name-section
