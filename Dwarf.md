# DWARF for WebAssembly

This document describes how to use [DWARF](http://www.DWARFstd.org/doc/DWARF5.pdf)
debug information with WebAssembly.

## Locating the DWARF Debug Info for a WebAssembly File

The DWARF debug info for a WebAssembly file is either embedded in the
WebAssembly file itself, or it is in a separate, external file. A WebAssembly
file should not have both embedded DWARF and external DWARF; if this is the
case, a DWARF consumer may use either DWARF debug info or it may consider the
WebAssembly to lack DWARF debug info.

### Embedding DWARF Within a WebAssembly File

The DWARF sections are embedded in Wasm binary files as custom sections. Each
custom section's name matches the DWARF section name as defined in the DWARF
standard, e.g. `.debug_info` or `.debug_line`.

> Note: The full list of DWARF sections and the relationships between them
> are available in Appendix B of the [DWARF standard](http://www.DWARFstd.org/doc/DWARF5.pdf).

> Note: Embedding each DWARF section in its own custom section within the
> Wasm binary matches how DWARF is embedded into other binary formats. For
> example with ELF binaries, each DWARF section is embedded as an ELF section,
> and similar for Mach-O binaries (although the "." in the section name is
> substituted with "__" in Mach-O).

> Example: Here is the output of `wasm-objdump --headers` on a Wasm binary
> that has embedded DWARF debug info:

```text
example.wasm:	file format wasm 0x1

Sections:

     Type start=0x0000000a end=0x00000078 (size=0x0000006e) count: 16
   Import start=0x0000007a end=0x00000092 (size=0x00000018) count: 1
 Function start=0x00000094 end=0x000000f1 (size=0x0000005d) count: 92
    Table start=0x000000f3 end=0x000000f8 (size=0x00000005) count: 1
   Memory start=0x000000fa end=0x000000fd (size=0x00000003) count: 1
   Global start=0x000000ff end=0x00000118 (size=0x00000019) count: 3
   Export start=0x0000011b end=0x00000237 (size=0x0000011c) count: 14
     Elem start=0x00000239 end=0x0000024e (size=0x00000015) count: 1
     Code start=0x00000252 end=0x0000d303 (size=0x0000d0b1) count: 92
     Data start=0x0000d306 end=0x0000dab0 (size=0x000007aa) count: 3
   Custom start=0x0000dab4 end=0x00076c13 (size=0x0006915f) ".debug_info"
   Custom start=0x00076c15 end=0x00076c3f (size=0x0000002a) ".debug_macinfo"
   Custom start=0x00076c42 end=0x00079962 (size=0x00002d20) ".debug_loc"
   Custom start=0x00079966 end=0x0008a7b6 (size=0x00010e50) ".debug_pubtypes"
   Custom start=0x0008a7ba end=0x000b8408 (size=0x0002dc4e) ".debug_ranges"
   Custom start=0x000b840b end=0x000baa7e (size=0x00002673) ".debug_abbrev"
   Custom start=0x000baa82 end=0x00102786 (size=0x00047d04) ".debug_line"
   Custom start=0x0010278a end=0x00194e5a (size=0x000926d0) ".debug_str"
   Custom start=0x00194e5e end=0x001b5118 (size=0x000202ba) ".debug_pubnames"
```

### External DWARF File

> Note: Existing external DWARF debug info schemes have typically been
> designed for reducing the amount of debug info that a linker must process and
> relocate (see "Appendix F: Split DWARF Object Files" in the DWARF standard).
> On the other hand, the motivation for external DWARF files with WebAssembly
> is to reduce the size of the WebAssembly file to speed up network transfers.
> If a WebAssembly file is served over HTTP and its DWARF debug info is not
> needed, then the WebAssembly file can be downloaded more quickly if the DWARF
> is external.

A WebAssembly file that has external DWARF contains a custom section named
`"external_debug_info"`. The contents of the custom section contain a UTF-8
encoded URL string that points to the external DWARF file.

> Note: It is preferable that the URL will be in relative form, relative to
> the WebAssembly file, to make DWARF debug info relocatable and consumable
> from an alternative or cached location.

```text
external_debug_info ::= section_0(ed_data)

ed_data             ::= n:name b*:vec(byte)
                        (if n = 'external_debug_info' and utf8(ed_field_value) = b*)
```

> Note: A command line tool might prefer to use file paths, while browser
> devtools might prefer to use a URL. The `ed_data` field needs to be decoded
> according to "file" URI Scheme rules when it needs to be used as a file path,
> which can be environment specific.

If the `"external_debug_info"` section is present, any DWARF debug info
WebAssembly sections are ignored. A DWARF producer needs to remove such
sections to reduce the size of the WebAssembly file. If more than one valid
`"external_debug_info"` section is present, consumers will use the last one.

The external DWARF file pointed to by the `ed_data` must be a WebAssembly file
with [embedded DWARF debug info](#embedding-dwarf-within-a-webassembly-file).
A DWARF consumer should ignore any non-DWARF WebAssembly sections in this file,
including instances of `"external_debug_info"` sections.

> Note: The relocatable WebAssembly file may contain sections that are used
> to assist with updating references to data locations or code instructions. In
> this case, the relocatable sections for DWARF debug info section needs can be
> present in the external DWARF file to assist code producers.

## Consuming and Generating DWARF for WebAssembly Code

> Note: Some DWARF constructs don't map one-to-one onto WebAssembly
> constructs. We strive to enumerate and resolve any ambiguities here.

### Code Addresses

> Note: DWARF associates various bits of debug info with particular
> locations in the program via its code address (instruction pointer or PC).
> However, WebAssembly's linear memory address space does not contain
> WebAssembly instructions.

Wherever a code address (see 2.17 of the [DWARF standard](http://www.DWARFstd.org/doc/DWARF5.pdf))
is used in DWARF for WebAssembly, it must be the offset of an instruction
relative within the `Code` section of the WebAssembly file. The DWARF is
considered malformed if a PC offset is between instruction boundaries within
the `Code` section.

> Note: It is expected that a DWARF consumer does not know how to decode
> WebAssembly instructions. The instruction pointer is selected as the offset in
> the binary file of the first byte of the instruction, and it is consistent
> with the [WebAssembly Web API](https://www.w3.org/TR/wasm-web-api/#conventions)
> definition of the code location.

> Example: `.debug_line` Instruction Pointers. The `.debug_line` DWARF section
> maps instruction pointers to source locations. With WebAssembly, the
> `.debug_line` section maps `Code` section-relative instruction offsets to
> source locations.

> Example: `DW_AT_*` Attributes. For entities with a single associated code
> address, DWARF uses the `DW_AT_low_pc` attribute to specify the associated
> code address value. For WebAssembly, the `DW_AT_low_pc`'s value is a `Code`
> section-relative instruction offset. For entities with a single contiguous
> range of code, DWARF uses a pair of `DW_AT_low_pc` and `DW_AT_high_pc`
> attributes, which are also `Code` section-relative instruction offsets. For
> entities with multiple ranges of code, DWARF uses the `DW_AT_ranges`
> attribute, which refers to the array located at the `.debug_ranges` section.

### DWARF Expressions and Location Descriptions

> Note: To enable the recovery of the values of variables, parameters,
> statics, etc. of a debuggee program at runtime, DWARF has *location
> descriptions* (see 2.6 of the [DWARF standard](http://www.DWARFstd.org/doc/DWARF5.pdf)).
> There are four kinds of base, non-composite location description:
>
> 1. Empty location descriptions (see 2.6.1.1.1 of the DWARF standard) are
>    used for optimized-away variables, or data that is otherwise unavailable.
>
> 2. Memory location descriptions (see 2.6.1.1.2 of the DWARF standard) are
>    used when a value is located at some address in memory.
>
> 3. Register location descriptions (see 2.6.1.1.3 of the DWARF standard) are
>    used when a value is located in a register.
>
> 4. Implicit location descriptions (see 2.6.1.1.4 of the DWARF standard) are
>    used when a value does not have any runtime representation, but has a known
>    value anyways.
>
> Each of these location descriptions are applicable to values in WebAssembly,
> and may be used as they normally are, except for the third: register location
> descriptions. WebAssembly does not have registers per se. Instead, it has
> three distinct kinds of virtual registers (globals, locals, and the operand
> stack) and may use up to 2<sup>32</sup> - 1 instances of each virtual
> register.

When a program object's value is stored in a WebAssembly local, global, or on
the operand stack it must be encoded as an extended DWARF operation. The
meanings of the existing DWARF location does not match definitions of local,
global, or operands stack. The proposed format for the extension is:

```text
wasm-ext := DW_OP_WASM_location wasm-op

DW_OP_WASM_location := 0xED ;; available DWARF extension code

wasm-op := wasm-local | wasm-global | wasm-operand-stack

wasm-local := 0x00 i:uleb128

wasm-global := 0x01 i:uleb128 |
               0x03 i:u32

wasm-operand-stack := 0x02 i:uleb128
```

Summary of encoding WebAssembly-specific constructs:

| DWARF Location Index | WebAssembly Construct | Meaning of the argument              |
| -------------------- | --------------------- | ------------------------------------ |
| 0                    | Local                 | The i-th local of the function.      |
| 1 or 3               | Global                | The i-th global of the module.       |
| 2                    | Operand Stack         | The i-th item on the operand stack.  |

> Note: This approach leverages DWARF's vendor extensibility (see 7.1 of
> the [DWARF standard](http://www.DWARFstd.org/doc/DWARF5.pdf)) to reserve
> custom DWARF expression opcodes for WebAssembly-specific location
> descriptions. The encoding provides the basic set of needed operators. In the
> future, it is possible to extend this set with a more compact encoding scheme,
> as well as adding specific DWARF extensions for a set of commonly used
> WebAssembly-specific locations.

> Note: WebAssembly does not impose a limit on the maximum number of locals
> or globals. It will be a challenge to agree on an encoding scheme to represent
> WebAssembly locations listed above as registers, as well as documenting this
> scheme in the DWARF standard.

#### Locals

If a value is located in the currently executing function's i-th local, the
value's location description must be encoded as a `DW_OP_WASM_location 0x00`
operation with i as its ULEB128-encoded operand.

#### Global

If a value is located in the i-th global, the value's location description must
be encoded as a `DW_OP_WASM_location 0x01` operation with i as its
ULEB128-encoded operand. Alternatively, the operation encoding
`DW_OP_WASM_location 0x03` with i as its U32-encoded operand is available.

#### Operand Stack

If a value is located in the i-th entry on the operand stack, where 0 <= i <
length(operand stack) and i = 0 is the bottom of the operand stack, the value's
location description must be encoded as a `DW_OP_WASM_location 0x02` operation
with i as its ULEB128-encoded operand.

> Note: Using i = 0 as the bottom of the operand stack means that location
> descriptions will not need to be updated as frequently as if i = 0 were the
> top of the operand stack, since Wasm instructions are constantly pushing to
> and popping from the operand stack.

### Using with AOT/JIT Compilers

The DWARF for WebAssembly is not usable as-is with native debuggers such as
LLDB or GDB. This debug info needs to be transformed into native DWARF when a
native module is generated. The WebAssembly-to-native code compilers need to
perform the following operations:

- Transform WebAssembly code and data address space to native one (32- or
  64-bit). That might include a WebAssembly location to multiple native address
  ranges transformation for code instructions.

- Transform DWARF expressions that contain WebAssembly-specific extension
  operators, as described in the
  [DWARF Expressions and Location Descriptions](#dwarf-expressions-and-location-descriptions)
  section, with a proper native register or memory location.

> Example: An AOT compiler reads a WebAssembly module and its linked external
> DWARF file, applies the transforms above, and produces a native executable
> (e.g. an ELF x86-64 binary with native DWARF) that can be debugged with
> standard native debuggers.
