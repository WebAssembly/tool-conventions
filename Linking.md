WebAssembly Object File Linking
===============================

This document describes the WebAssembly object file format and the ABI used for
statically linking them to produce an executable WebAssembly module. This is
currently implemented in the clang/LLVM WebAssembly 
backend and other tools such as binaryen and wabt.  As mentioned in 
[README](README.md), this is not part of the official WebAssembly specification 
and other runtimes may choose to follow a different set of linking conventions.

Overview
--------

Each translation unit is compiled into a WebAssembly object file.  These files
are themselves valid WebAssembly module binaries but are not expected to be
directly executable and have certain additional constraints.  In order to
distinguish object files from executable WebAssembly modules the linker can
check for the presence of the ["linking"](#linking-metadata-section) custom
section which must exist in all object files.

The goal of the linker is to take one or more WebAssembly object files and merge
them into a single executable module.  In order to achieve this the following
tasks need to be performed:

- Merging of function sections (re-numbering functions)
- Merging of globals sections (re-numbering globals)
- Merging of event sections (re-numbering events)
- Merging of table sections (re-numbering tables)
- Merging of data segments (re-positioning data)
- Resolving undefined external references
- Synthesizing functions to call constructors and perform other initialization

The linking technique described here is designed to be fast, and avoids having
to disassemble the code section.  The extra metadata required by the linker
is stored in a custom ["linking"](#linking-metadata-section) section and zero or
more relocation sections whose names begin with "reloc.".  For each section that
requires relocation a "reloc" section will be present in the wasm file.  By
convention the reloc section names end with the name of the section that they 
refer to: e.g. "reloc.CODE" for code section relocations.  However, everything 
after the period is ignored and the specific target section is encoded in the 
reloc section itself.

The linker additionally checks that linked object files were built targeting
compatible feature sets. Unlike native targets, WebAssembly has no runtime
feature detection, and the presence of unsupported features causes a binary to
fail to validate. It is therefore important for the user to have explicit
control over the features used in the output binary and for the linker to
provide helpful errors when instructed to link incompatible or disallowed
features. This feature information is stored in a custom ["target feature
section"](#target-features-section).

Relocation Sections
-------------------

A relocation section is a user-defined section with a name starting with
"reloc." Relocation sections start with an identifier specifying which
section they apply to, and must be sequenced in the module after that
section.

The "reloc." custom sections must come after the
["linking"](#linking-metadata-section) custom section in order to validate
relocation indices.

Relocations contain the following fields:

| Field     | Type                | Description                     |
| ----------| ------------------- | ------------------------------- |
| section   | `varuint32`         | the index of the target section |
| count     | `varuint32`         | count of entries to follow      |
| entries   | `relocation_entry*` | sequence of relocation entries  |

A `relocation_entry` begins with:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| type     | `uint8`             | the relocation type            |
| offset   | `varuint32`         | offset of the value to rewrite (relative to the relevant section's body) |
| index    | `varuint32`         | the index of the symbol used (or, for `R_WASM_TYPE_INDEX_LEB` relocations, the index of the type) |

A relocation type can be one of the following:

- `0 / R_WASM_FUNCTION_INDEX_LEB` (since LLVM 10.0) - a function index encoded
as a 5-byte [varuint32]. Used for the immediate argument of a `call`
instruction.
- `1 / R_WASM_TABLE_INDEX_SLEB` (since LLVM 10.0) - a function table index
encoded as a 5-byte [varint32]. Used to refer to the immediate argument of a
`i32.const`  instruction, e.g. taking the address of a function.
- `2 / R_WASM_TABLE_INDEX_I32` (since LLVM 10.0) - a function table index
encoded as a [uint32], e.g. taking the address of a function in a static data
initializer.
- `3 / R_WASM_MEMORY_ADDR_LEB` (since LLVM 10.0) - a linear memory index
encoded as a 5-byte [varuint32]. Used for the immediate argument of a `load` or
`store` instruction, e.g. directly loading from or storing to a C++ global.
- `4 / R_WASM_MEMORY_ADDR_SLEB` (since LLVM 10.0) - a linear memory index
encoded as a 5-byte [varint32]. Used for the immediate argument of a `i32.const`
instruction, e.g. taking the address of a C++ global.
- `5 / R_WASM_MEMORY_ADDR_I32` (since LLVM 10.0) - a linear memory index
encoded  as a [uint32], e.g. taking the address of a C++ global in a static data
initializer.
- `6 / R_WASM_TYPE_INDEX_LEB` (since LLVM 10.0) - a type table index encoded as
a 5-byte [varuint32], e.g. the type immediate in a `call_indirect`.
- `7 / R_WASM_GLOBAL_INDEX_LEB` (since LLVM 10.0) - a global index encoded as a
  5-byte [varuint32], e.g. the index immediate in a `get_global`.
- `8 / R_WASM_FUNCTION_OFFSET_I32` (since LLVM 10.0) - a byte offset within
code section for the specific function encoded as a [uint32]. The offsets start
at the actual function code excluding its size field.
- `9 / R_WASM_SECTION_OFFSET_I32` (since LLVM 10.0) - an byte offset from start
of the specified section encoded as a [uint32].
- `10 / R_WASM_EVENT_INDEX_LEB` (since LLVM 10.0) - an event index encoded as a
5-byte [varuint32]. Used for the immediate argument of a `throw` and `if_except`
  instruction.
- `13 / R_WASM_GLOBAL_INDEX_I32` (since LLVM 11.0) - a global index encoded as
[uint32].
- `14 / R_WASM_MEMORY_ADDR_LEB64` (since LLVM 11.0) - the 64-bit counterpart of
`R_WASM_MEMORY_ADDR_LEB`. A 64-bit linear memory index encoded as a 10-byte
[varuint64], Used for the immediate argument of a `load` or `store` instruction
on a 64-bit linear memory array.
- `15 / R_WASM_MEMORY_ADDR_SLEB64` (since LLVM 11.0) - the 64-bit counterpart
of `R_WASM_MEMORY_ADDR_SLEB`. A 64-bit linear memory index encoded as a 10-byte
[varint64]. Used for the immediate argument of a `i64.const` instruction.
- `16 / R_WASM_MEMORY_ADDR_I64` (since LLVM 11.0) - the 64-bit counterpart of
`R_WASM_MEMORY_ADDR`. A 64-bit linear memory index encoded as a [uint64], e.g.
taking the 64-bit address of a C++ global in a static data initializer.
- `17 / R_WASM_MEMORY_ADDR_REL_SLEB64` (since LLVM 11.0) - the 64-bit
counterpart of `R_WASM_MEMORY_ADDR_REL_SLEB`.
- `18 / R_WASM_TABLE_INDEX_SLEB64` (in LLVM `master`) - the 64-bit counterpart
of  `R_WASM_TABLE_INDEX_SLEB`. A function table index encoded as a 10-byte
[varint64]. Used to refer to the immediate argument of a `i64.const`
instruction, e.g. taking the address of a function in Wasm64.
- `19 / R_WASM_TABLE_INDEX_I64` (in LLVM `master`) - the 64-bit counterpart of
`R_WASM_TABLE_INDEX_I32`. A function table index encoded as a [uint64], e.g.
taking the address of a function in a static data initializer.
- `20 / R_WASM_TABLE_NUMBER_LEB` (in LLVM `master`) - a table number encoded as
a 5-byte [varuint32]. Used for the table immediate argument in the table.*
  instructions.

**Note**: Please note that the 64bit relocations are not yet stable and 
therefore, subject to change.

[varuint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varuintn
[varuint64]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varuintn
[varint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varintn
[varint64]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varintn
[uint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#uintn
[uint64]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#uintn

For `R_WASM_MEMORY_ADDR_LEB`, `R_WASM_MEMORY_ADDR_SLEB`, 
`R_WASM_MEMORY_ADDR_I32`, `R_WASM_FUNCTION_OFFSET_I32`, and
`R_WASM_SECTION_OFFSET_I32` relocations (and their 64-bit counterparts) the 
following field is additionally present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| addend | `varint32`       | addend to add to the address        |

Note that for all relocation types, the bytes being relocated:
* from `offset` to `offset + 5` for LEB/SLEB relocations;
* from `offset` to `offset + 10` for LEB64/SLEB64 relocations;
* from `offset` to `offset + 4` for I32 relocations;
* or from `offset` to `offset + 8` for I64;

must lie within the section to which the relocation applies (as offsets are relative
to the section's body, this means that they cannot be too large). In addition,
the bytes being relocated may not overlap the boundary between the section's chunks,
where such a distinction exists (it may not for custom sections).  For example, for
relocations applied to the CODE section, a relocation cannot straddle two
functions, and for the DATA section relocations must lie within a data element's
body.

Linking Metadata Section
------------------------

A linking metadata section is a user-defined section with the name
"linking".

The "linking" custom section must be after the [data
section](https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#data-section)
in order to validate data symbols.

A linking metadata section begins with a version number which is then followed
by a series of sub-sections laid out in the same way as the ["names"][names_sec]
section:

| Field       | Type          | Description                          |
| ----------- | ------------- | ------------------------------------ |
| version     | `varuint32`   | the version of linking metadata contained in this section. Currently: 2 |
| subsections | `subsection*` | sequence of `subsection`             |

This `version` allows for breaking changes to be made to the format described
here.  Tools can then choose to reject imputs contained unexpected versions.

Each `subsection` is encoded as:

| Field        | Type        | Description                          |
| ------------ | ----------- | ------------------------------------ |
| type         | `uint8`     | code identifying type of subsection  |
| payload_len  | `varuint32` | size of this subsection in bytes     |
| payload_data | `bytes`     | content of this subsection, of length `payload_len` |

The current list of valid `type` codes are:

- `5 / WASM_SEGMENT_INFO` - Extra metadata about the data segments.

- `6 / WASM_INIT_FUNCS` - Specifies a list of constructor functions to be called
  at startup. These constructors will be called in priority order after memory
  has been initialized.

- `7 / WASM_COMDAT_INFO` - Specifies the COMDAT groups of associated linking
  objects, which are linked only once and all together.

- `8 / WASM_SYMBOL_TABLE` - Specifies extra information about the symbols present
  in the module.

For `WASM_SEGMENT_INFO` the following fields are present in the
subsection:

| Field       | Type         | Description                      |
| ----------- | ------------ | -------------------------------- |
| count       | `varuint32`  | number of `segment` in segments  |
| segments    | `segment*`   | sequence of `segment`            |

where a `segment` is encoded as:

| Field        | Type         | Description                                   |
| ------------ | ------------ | --------------------------------------------- |
| name_len     | `varuint32`  | length of `name_data` in bytes                |
| name_data    | `bytes`      | UTF-8 encoding of the segment's name          |
| alignment    | `varuint32`  | The required alignment of the segment, encoded as a power of 2 |
| flags        | `varuint32`  | a bitfield containing flags for this segment  |

For `WASM_INIT_FUNCS` the following fields are present in the
subsection:

| Field       | Type         | Description                           |
| ----------- | ------------ | ------------------------------------- |
| count       | `varuint32`  | number of init functions that follow  |
| functions   | `varuint32*` | sequence of symbol indices            |

The `WASM_INIT_FUNC` subsection must come after the `WASM_SYMBOL_TABLE` subsection.

For `WASM_SYMBOL_TABLE` the following fields are present in the
subsection:

| Field  | Type            | Description                  |
| ------ | --------------- | ---------------------------- |
| count  | `varuint32`     | number of `syminfo` in infos |
| infos  | `syminfo*`      | sequence of `syminfo`        |

where a `syminfo` is encoded as:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| kind         | `uint8`        | The symbol type.  One of:                   |
|              |                |   `0 / SYMTAB_FUNCTION`                     |
|              |                |   `1 / SYMTAB_DATA`                         |
|              |                |   `2 / SYMTAB_GLOBAL`                       |
|              |                |   `3 / SYMTAB_SECTION`                      |
|              |                |   `4 / SYMTAB_EVENT`                        |
|              |                |   `5 / SYMTAB_TABLE`                        |
| flags        | `varuint32`    | a bitfield containing flags for this symbol |

For functions, globals, events and tables, we reference an existing Wasm object, which
is either an import or a defined function/global/event/table (recall that the operand of a
Wasm `call` instruction uses an index space consisting of the function imports
followed by the defined functions, and similarly `get_global` for global imports
and definitions and `throw` for event imports and definitions).

If a symbols refers to an import, and the
`WASM_SYM_EXPLICIT_NAME` flag is not set, then the name is taken from the
import; otherwise the `syminfo` specifies the symbol's name.

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| index        | `varuint32`    | the index of the Wasm object corresponding to the symbol, which references an import if and only if the `WASM_SYM_UNDEFINED` flag is set  |
| name_len     | `varuint32` ?  | the optional length of `name_data` in bytes, omitted if `index` references an import |
| name_data    | `bytes` ?      | UTF-8 encoding of the symbol name, omitted if `index` references an import |

For data symbols:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| name_len     | `varuint32`    | the length of `name_data` in bytes          |
| name_data    | `bytes`        | UTF-8 encoding of the symbol name           |
| index        | `varuint32` ?  | the index of the data segment; provided if the symbol is defined |
| offset       | `varuint32` ?  | the offset within the segment; provided if the symbol is defined; must be <= the segment's size |
| size         | `varuint32` ?  | the size (which can be zero); provided if the symbol is defined; `offset + size` must be <= the segment's size |

For section symbols:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| section      | `varuint32`    | the index of the target section             |

The current set of valid flags for symbols are:

- `1 / WASM_SYM_BINDING_WEAK` - Indicating that this is a weak symbol.  When
  linking multiple modules defining the same symbol, all weak definitions are
  discarded if any strong definitions exist; then if multiple weak definitions
  exist all but one (unspecified) are discarded; and finally it is an error if
  more than one definition remains.
- `2 / WASM_SYM_BINDING_LOCAL` - Indicating that this is a local symbol (this
  is exclusive with `WASM_SYM_BINDING_WEAK`). Local symbols are not to be
  exported, or linked to other modules/sections. The names of all non-local
  symbols must be unique, but the names of local symbols are not considered for
  uniqueness. A local function or global symbol cannot reference an import.
- `4 / WASM_SYM_VISIBILITY_HIDDEN` - Indicating that this is a hidden symbol.
  Hidden symbols are not to be exported when performing the final link, but
  may be linked to other modules.
- `0x10 / WASM_SYM_UNDEFINED` - Indicating that this symbol is not defined.
  For non-data symbols, this must match whether the symbol is an import
  or is defined; for data symbols, determines whether a segment is specified.
- `0x20 / WASM_SYM_EXPORTED` - The symbol is intended to be exported from the
  wasm module to the host environment. This differs from the visibility flags
  in that it effects the static linker.
- `0x40 / WASM_SYM_EXPLICIT_NAME` - The symbol uses an explicit symbol name,
  rather than reusing the name from a wasm import. This allows it to remap
  imports from foreign WebAssembly modules into local symbols with different
  names.
- `0x80 / WASM_SYM_NO_STRIP` - The symbol is intended to be included in the
  linker output, regardless of whether it is used by the program.

For `WASM_COMDAT_INFO` the following fields are present in the
subsection:

| Field   | Type        | Description                                    |
| ------- | ----------- | ---------------------------------------------- |
| count   | `varuint32` | Number of `Comdat` in `comdats`                |
| comdats | `comdat*`   | Sequence of `Comdat`

where a `comdat` is encoded as:

| Field       | Type          | Description                               |
| ----------- | ------------- | ----------------------------------------- |
| name_len    | `varuint32`   | length of `name_str` in bytes             |
| name_str    | `bytes`       | UTF-8 encoding of the name                |
| flags       | `varuint32`   | Must be zero, no flags currently defined  |
| count       | `varuint32`   | Number of `comdat_sym` in `comdat_syms`   |
| comdat_syms | `comdat_sym*` | Sequence of `comdat_sym`                  |

and where a `comdat_sym` is encoded as:

| Field    | Type           | Description                                 |
| -------- | -------------- | ------------------------------------------- |
| kind     | `uint8`        | Type of symbol, one of:                     |
|          |                |   * `0 / WASM_COMDAT_DATA`, a data segment  |
|          |                |   * `1 / WASM_COMDAT_FUNCTION`              |
|          |                |   * `2 / WASM_COMDAT_GLOBAL`                |
|          |                |   * `3 / WASM_COMDAT_EVENT`                 |
|          |                |   * `4 / WASM_COMDAT_TABLE`                 |
|          |                |   * `5 / WASM_COMDAT_SECTION`               |
| index    | `varuint32`    | Index of the data segment/function/global/event/table in the Wasm module (depending on kind). The function/global/event/table must not be an import. |

Target Features Section
-----------------------

The target features section is an optional custom section with the name
"target_features". The target features section must come after the
["producers"](#linking-metadata-section) section.

The body of the target features section is a vector of entries:

| Field   | Type    | Description                              |
| ------- | ------- | ---------------------------------------- |
| prefix  | `byte`  | See below.                               |
| feature | `bytes` | The name of the feature. Must be unique. |

The recognized prefix bytes and their meanings are below. When the user does not
supply a set of allowed features explicitly, the set of allowed features is
taken to be the set of features used or required. Any feature not mentioned in
an object's target features section is not used by that object, but is not
necessarily prohibited in the final binary.

| Prefix     | Meaning |
| ---------- | ------- |
| 0x2b (`+`) | This object uses this feature, and the link fails if this feature is not in the allowed set. |
| 0x2d (`-`) | This object does not use this feature, and the link fails if this feature is in the allowed set. |
| 0x3d (`=`) | This object uses this feature, and the link fails if this feature is not in the allowed set or if any object does not use this feature. |

The generally accepted features are:

1. `atomics`
1. `bulk-memory`
1. `exception-handling`
1. `multivalue`
1. `mutable-globals`
1. `nontrapping-fptoint`
1. `sign-ext`
1. `simd128`
1. `tail-call`

Lowering Atomics and TLS to MVP WebAssembly
-------------------------------------------
MVP WebAssembly does not include support for atomic operations or the bulk
memory operations necessary to implement thread-local storage. As a result, any
atomics or TLS present at the source level must be lowered to non-atomic
operations and normal storage when targeting MVP WebAssembly. This is safe as
long as the resulting MVP object files are not used in a multi-threaded context.

To enforce this safety guarantee, the linker will error out if a shared memory
is requested but the `atomics` target feature is disallowed in the target
features section of any input objects. The compiler is responsible for marking
`atomics` disallowed and thereby preventing thread-unsafe linking if either
atomic operations or TLS are stripped during compilation. If the compiler
removes either one of atomic operations or TLS, the resulting object may only be
used with a single thread with an unshared memory, so the other one should be
removed as well.

If `atomics` or `bulk-memory` is not available during compilation but the source
does not contain atomic operations or TLS, then the result is a
"thread-agnostic" object that neither uses nor disallows the `atomics` feature.
Thread-agnostic objects can be safely linked with objects that do or do not use
`atomics`, although not both at the same time.

Merging Global Sections
-----------------------

Merging of the global sections requires the re-numbering of globals.  This
follows the normal rules for defining symbols: if two object files provide the
same global symbol strongly, there is a link error; if two object files provide
the symbol weakly, one is chosen.

When creating non-relocatable output, the Wasm output shall have an import for
each undefined strong symbol, and an export for each defined symbol with
non-local linkage and non-hidden visibility.

The linker may provide certain symbols itself, even if not defined by any
object file.  For example, the `__stack_pointer` symbol may be provided at
link-time.


Merging Event Sections
-----------------------

Events are meant to represent various control-flow changing constructs of wasm.
Currently, we have a
[proposal](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md)
for one kind of events: exceptions, but the event section can be used to support
other kinds of events in future as well. The event section is a list of declared
events associated with the module.

Merging of the event sections requires the re-numbering of events. This follows
the normal rules for defining symbols: if two object files provide the same
event symbol strongly, there is a link error; if two object files provide the
symbol weakly, one is chosen.

When creating non-relocatable output, the Wasm output shall have an import for
each undefined strong symbol, and an export for each defined symbol with
non-local linkage and non-hidden visibility.


Merging Function Sections
-------------------------

Merging of the function sections requires the re-numbering of functions.  This
requires modification to code sections at each location where a function
index is embedded.  There are currently two ways in which function indices are
stored in the code section:

1. Immediate argument of the `call` instruction (calling a function)
2. Immediate argument of the `i32.const` instruction (taking the address of a
   function).

The immediate argument of all such instructions are stored as padded LEB128 such
that they can be rewritten without altering the size of the code section.  For
each such instruction a `R_WASM_FUNCTION_INDEX_LEB` or `R_WASM_TABLE_INDEX_SLEB`
`reloc` entry is generated pointing to the offset of the immediate within the
code section.

The same technique applies for all function calls whether the function is
imported or defined locally.

When creating non-relocatable output, the Wasm output shall have an import for
each undefined strong symbol, and an export for each defined symbol with
non-local linkage and non-hidden visibility.


Merging Data Sections
---------------------

Merging of data sections is performed by creating a new data section from the
data segments in the object files. Data symbols (e.g. C/C+ globals) are
represented in the object file as Wasm data segments with an associated data
symbol, so each linked data symbol pulls its associated data segment into the
linked output.

Segments are merged according their type: segments with a common prefix such as
`.data` or `.rodata` are merged into a single segment in the output data
section. It is an error if this behavior would merge shared and unshared
segments.

The output data section is formed, essentially, by concatenating the data
sections of the input files.  Since the final location in linear memory of any
given symbol is not known until link time, all references to data addresses with
the code and data sections generate `R_WASM_MEMORY_ADDR_*` relocation entries,
which reference a data symbol.

Segments are linked as a whole, and a segment is either entirely included or
excluded from the link.


Merging Custom Sections
----------------------

Merging of custom sections is performed by concatenating all payloads for the
customs sections with the same name. The section symbol will refer the resulting
section, this means that the relocation entries addend that refer
the referred custom section fields shall be adjusted to take new offset
into account.

COMDATs
-------

A COMDAT group may contain one or more functions, data segments, and/or custom sections.
The linker will include all of these elements with a given group name from one object file,
and will exclude any element with this group name from all other object files.



Processing Relocations
----------------------

The final code and data sections are written out with relocations applied.

`R_WASM_TYPE_INDEX_LEB` relocations cannot fail.  The output Wasm file
shall contain a newly-synthesised type section which contains entries for all
functions and type relocations in the output.

`R_WASM_TABLE_INDEX_SLEB`, `R_WASM_TABLE_INDEX_I32` relocations and their 64-bit counterparts (`R_WASM_TABLE_INDEX_SLEB64` and `R_WASM_TABLE_INDEX_I64`) 
cannot fail.  The output Wasm file shall contain a newly-synthesised table,
which contains an entry for all defined or imported symbols referenced by table
relocations.  The output table elements shall begin at a non-zero offset within
the table, so that a `call_indirect 0` instruction is guaranteed to fail.
Finally, when processing table relocations for symbols which have neither an
import nor a definition (namely, weakly-undefined function symbols), the value
`0` is written out as the value of the relocation.

`R_WASM_FUNCTION_INDEX_LEB` relocations may fail to be processed, in
which case linking fails.  This occurs if there is a weakly-undefined function
symbol, in which case there is no legal value that can be written as the target
of any `call` instruction.  The frontend must generate calls to undefined weak
symbols via a `call_indirect` instruction.

`R_WASM_GLOBAL_INDEX_LEB` relocations may fail to be processed, in which
case linking fails.  This occurs if there is a weakly-undefined global symbol,
in which case there is no legal value that can be written as the target of any
`get_global` or `set_global` instruction. (This means the frontend must not
generate weak globals which may not be defined; a definition or import must
exist for all global symbols in the linked output.)

`R_WASM_MEMORY_ADDR_LEB`, `R_WASM_MEMORY_ADDR_SLEB` and
`R_WASM_MEMORY_ADDR_I32` relocations (and their 64-bit counterpairs `R_WASM_MEMORY_ADDR_LEB64`, `R_WASM_MEMORY_ADDR_SLEB64`, and `R_WASM_MEMORY_ADDR_I64`) cannot fail.  The relocation's value
is the offset within the linear memory of the symbol within the output segment,
plus the symbol's addend.  If the symbol is undefined (whether weak or strong),
the value of the relocation shall be `0`.

`R_WASM_FUNCTION_OFFSET_I32` relocations cannot fail. The values shall be
adjusted to reflect new offsets in the code section.

`R_WASM_SECTION_OFFSET_I32` relocation cannot fail. The values shall be
adjusted to reflect new offsets in the combined sections.

`R_WASM_EVENT_INDEX_LEB` relocations may fail to be processed, in which
case linking fails. This occurs if there is a weakly-undefined event symbol, in
which case there is no legal value that can be written as the target of any
`throw` and `if_except` instruction. (This means the frontend must not generate
weak events which may not be defined; a definition or import must exist for all
event symbols in the linked output.)

[names_sec]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#name-section

Start Section
-------------

By default the static linker should not output a WebAssembly start
section. Constructors are instead called from a synthetic function
`__wasm_call_ctors` that the runtime and embedder should arrange to have called
after instantiation. `__wasm_call_ctors` is not exported by default because it
may be called by some other startup function defined by the runtime. For the
embedder to call it directly it should be exported like any other function.

Rationale: Use of the WebAssembly start function was considered for running
static constructors and/or the main entry point to the program.  However,
running arbitrary code in the start section is currently problematic due to the
fact the module exports not available to the embedder at the time when the start
function runs.  A common example is the module memory itself.  If the code in
the start function wants to transfer any data to the embedder (e.g. `printf`)
this will not work as the embedded cannot yet access the modules memory.  This
extends to all embedder functions that might want to call back into the module.

If some future version of the WebAssembly spec allows for module exports to be
available during execution of the start function it will make sense to
reconsider this.

When shared memory is requested, a start function will be emitted to initialize
memory as described below.


Shared Memory and Passive Segments
----------------------------------

When shared memory is enabled, all data segments will be emitted as [passive
segments][passive_segments] to prevent each thread from reinitializing
memory. In a web context, using active segments would cause memory to be
reinitialized every time the module is instantiated on a new WebWorker as part
of spawning a new thread. The `memory.init` instructions that initialize these
passive segments and the `data.drop` instructions that mark them collectible
will be emitted into a synthetic function `__wasm_init_memory` that is made the
WebAssembly start function and called automatically on instantiation but is not
exported. `__wasm_init_memory` shall perform any synchronization necessary to
ensure that no thread returns from instantiation until memory has been fully
initialized, even if a module is instantiated on multiple threads
simultaneously. This synchronization may involve waiting, so in a web context
the runtime must ensure that the module is instantiated either first on the
browser's main thread without racing with worker threads or not at all on the
browser's main thread. To make the `memory.init` and `data.drop` instructions
valid, a [DataCount section][datacount_section] will also be emitted.

Note that `memory.init` and the DataCount section are features of the
bulk-memory proposal, not the atomics proposal, so any engine that supports
threads needs to support both of these proposals.

[passive_segments]: https://github.com/WebAssembly/bulk-memory-operations/blob/master/proposals/bulk-memory-operations/Overview.md#design
[datacount_section]: https://github.com/WebAssembly/bulk-memory-operations/blob/master/proposals/bulk-memory-operations/Overview.md#datacount-section

Thread Local Storage
--------------------

Currently, thread-local storage is only supported in the main WASM module
and cannot be accessed outside of it. This corresponds to the ELF local
exec TLS model.

Additionally, thread local storage depends on bulk memory instructions, and
therefore support depends on the bulk memory proposal.

All thread local variables will be merged into one passive segment called
`.tdata`. This section contains the starting values for all TLS variables.
The thread local block of every thread will be initialized with this segment.

In a threaded build, the linker will create:

* an immutable global variable of type `i32` called `__tls_size`.
  Its value is the total size of the thread local block for the module,
  i.e. the sum of the sizes of all thread local variables plus padding.
  This value will be `0` if there are no thread-local variables.
* an immutable global variable of type `i32` called `__tls_align`.
  Its value is the alignment requirement of the thread local block, in bytes,
  and will be a power of 2. The value will be `1` if there are no thread-local
  variables.
* a mutable global `i32` called `__tls_base`, with a `i32.const 0` initializer.
* a global function called `__wasm_init_tls` with signature `(i32) -> ()`.

To initialize thread-local storage, a thread should do the equivalent of the
following pseudo-code upon startup:

    (if (global.get __tls_size) (then
      (call __wasm_init_tls
        (call aligned_alloc
          (global.get __tls_align)
          (call roundUpToMultipleOf
            (global.get __tls_align)
            (global.get __tls_size))))))

`__wasm_init_tls` takes a pointer argument containing the memory block to use
as the thread local storage block of the current thread. It should do nothing if
there are no thread-local variables. Otherwise, the memory block will be
initialized with the passive segment `.tdata` via the `memory.init` instruction.
It will then set `__tls_base` to the address of the memory block passed to
`__wasm_init_tls`.

Note that `__tls_size` is not necessarily a multiple of `__tls_align`. In order to
use `aligned_alloc`, we must round the size up to be a multiple of `__tls_align`.

The relocations for thread local variables shall resolve into offsets relative to
the start of the TLS block. As such, adding the value of `__tls_base` yields the
actual address of the variable. For example, a variable called `tls_var` would
have its address computed as follows:

    (i32.add (global.get __tls_base) (i32.const tls_var))

The variable can then be used as normal. Upon thread exit, the runtime should free
the memory allocated for the TLS block.
