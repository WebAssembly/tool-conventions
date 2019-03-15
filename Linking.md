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
- Merging of event sections (re-numbering events)
- Merging of data segments (re-positioning data)
- Resolving undefined external references

The linking technique described here is designed to be fast, and avoids having
to disassemble the code section.  The extra metadata required by the linker
is stored in a custom ["linking"](#linking-metadata-section) section and zero or
more relocation sections whose names begin with "reloc.".  For each section that
requires relocation a "reloc" section will be present in the wasm file.  By
convention the reloc section names end with the name of the section that they refer
to: e.g. "reloc.CODE" for code section relocations.  However everything after
the period is ignored and the specific target section is encoded in the reloc
section itself.

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
| offset   | `varuint32`         | offset of the value to rewrite |
| index    | `varuint32`         | the index of the symbol used (or, for `R_WASM_TYPE_INDEX_LEB` relocations, the index of the type) |

A relocation type can be one of the following:

- `0 / R_WASM_FUNCTION_INDEX_LEB` - a function index encoded as a 5-byte
  [varuint32]. Used for the immediate argument of a `call` instruction.
- `1 / R_WASM_TABLE_INDEX_SLEB` - a function table index encoded as a
  5-byte [varint32]. Used to refer to the immediate argument of a `i32.const`
  instruction, e.g. taking the address of a function.
- `2 / R_WASM_TABLE_INDEX_I32` - a function table index encoded as a
  [uint32], e.g. taking the address of a function in a static data initializer.
- `3 / R_WASM_MEMORY_ADDR_LEB` - a linear memory index encoded as a 5-byte
  [varuint32]. Used for the immediate argument of a `load` or `store`
  instruction, e.g. directly loading from or storing to a C++ global.
- `4 / R_WASM_MEMORY_ADDR_SLEB` - a linear memory index encoded as a 5-byte
  [varint32]. Used for the immediate argument of a `i32.const` instruction,
  e.g. taking the address of a C++ global.
- `5 / R_WASM_MEMORY_ADDR_I32` - a linear memory index encoded as a
  [uint32], e.g. taking the address of a C++ global in a static data
  initializer.
- `6 / R_WASM_TYPE_INDEX_LEB` - a type table index encoded as a
  5-byte [varuint32], e.g. the type immediate in a `call_indirect`.
- `7 / R_WASM_GLOBAL_INDEX_LEB` - a global index encoded as a
  5-byte [varuint32], e.g. the index immediate in a `get_global`.
- `8 / R_WASM_FUNCTION_OFFSET_I32` - a byte offset within code section
  for the specic function encoded as a [uint32].
  The offsets start at the actual function code excluding its size field.
- `9 / R_WASM_SECTION_OFFSET_I32` - an byte offset from start of the
  specified section encoded as a [uint32].
- `10 / R_WASM_EVENT_INDEX_LEB` - an event index encoded as a 5-byte
  [varuint32]. Used for the immediate argument of a `throw` and `if_except`
  instruction.

[varuint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varuintn
[varint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varintn
[uint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#uintn

For `R_WASM_MEMORY_ADDR_LEB`, `R_WEBASSEMBLY_MEMORY_ADDR_SLEB`,
`R_WASM_MEMORY_ADDR_I32`, `R_WEBASSEMBLY_FUNCTION_OFFSET_I32`, and
`R_WASM_SECTION_OFFSET_I32` relocations the following field is additionally
present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| addend | `varint32`       | addend to add to the address        |

Note that for all relocation types, the bytes being relocated (from `offset`
to `offset + 5` for LEB/SLEB relocations or `offset + 4` for I32) must lie
within the section to which the relocation applies.  The bytes being relocated
may not overlap the boundary between the section's chunks, where such a
distinction exists (it may not for custom sections).  For example, for
relocations applied to the CODE section, a  relocation cannot straddle two
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
| version     | `varuint32`   | the version of linking metadata contained in this section. Currently: 3 |
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
| flags        | `varuint32`    | a bitfield containing flags for this symbol |

For functions, globals, events, and undefined data symbols the symbol references
an existing Wasm object, which is either an imported or defined
function/global/event (recall that the operand of a Wasm `call` instruction uses
an index space consisting of the function imports followed by the defined
functions, and similarly `get_global` for global imports and definitions and
`throw` for event imports and definitions). If a symbol references an
import, then the name is taken from the import; otherwise the `syminfo`
specifies the symbol's name.

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| index        | `varuint32`    | the index of the function/global/event corresponding to the symbol, which references an import if and only if the `WASM_SYM_UNDEFINED` flag is set  |
| name_len     | `varuint32` ?  | the optional length of `name_data` in bytes, omitted if `index` references an import |
| name_data    | `bytes` ?      | UTF-8 encoding of the symbol name           |

For defined data symbols:

| Field        | Type         | Description                                   |
| ------------ | ------------ | --------------------------------------------- |
| name_len     | `varuint32`  | the length of `name_data` in bytes            |
| name_data    | `bytes`      | UTF-8 encoding of the symbol name             |
| index        | `varuint32`  | the index of the data segment                 |
| offset       | `varuint32`  | the offset within the segment; must be <= the segment's size |
| size         | `varuint32`  | the size (which can be zero); `offset + size` must be <= the segment's size |

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
  For function/global/event symbols, must match whether the symbol is an import
  or is defined; for data symbols, determines whether a segment is specified.
- `0x20 / WASM_SYM_EXPORTED` - The symbol is intended to be exported from the
  wasm module to the host environment. This differs from the visibility flags
  in that it effects the static linker.
- `0x40 / WASM_SYMBOL_EXPLICIT_NAME` - This means that symbol has an explicit
  name that may differ from the name of the import.  This can be used to import
  a given symbol by a different name.

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
| index    | `varuint32`    | Index of the data segment/function/global/event in the Wasm module (depending on kind). The function/global/event must not be an import. |

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
taken to be the set of used features. Any feature not mentioned in an object's
target features section is not used by that object, but is not necessarily
prohibited in the final binary.

| Prefix     | Meaning |
| ---------- | ------- |
| 0x2b (`+`) | This object uses this feature, and the link fails if this feature is not in the allowed set. |
| 0x2d (`-`) | This object does not use this feature, and the link fails if this feature is in the allowed set. |
| 0x3d (`=`) | This object uses this feature, and the link fails if this feature is not in the allowed set or if any object does not use this feature. |

The generally accepted features are:

1. `atomics`
2. `bulk-memory`
3. `exception-handling`
4. `nontrapping-fptoint`
5. `sign-ext`
6. `simd128`

The "atomics" feature string is special: if it is present, the linker will
produce a binary that uses a shared memory.

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
Currently we have a
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

Processing Relocations
----------------------

The final code and data sections are written out with relocations applied.

`R_WASM_TYPE_INDEX_LEB` relocations cannot fail.  The output Wasm file
shall contain a newly-synthesised type section which contains entries for all
functions and type relocations in the output.

`R_WASM_TABLE_INDEX_SLEB` and `R_WEBASSEMBLY_TABLE_INDEX_I32` relocations
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

`R_WASM_MEMORY_ADDR_LEB`, `R_WEBASSEMBLY_MEMORY_ADDR_SLEB` and
`R_WASM_MEMORY_ADDR_I32` relocations cannot fail.  The relocation's value
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

By default the static linker should not output a WebAssembly start section.

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
