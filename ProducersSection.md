# Producers Section

The purpose of the producers section is to provide an optional,
highly-structured record of all the distinct tools that were used to produce
a given WebAssembly module. A primary purpose of this record is to allow
broad analysis of toolchain usage in the wild, which can help inform both wasm
producers and consumers.

The producers section is a
[custom section](https://webassembly.github.io/spec/core/binary/modules.html#custom-section)
and thus has no semantic effects and can be stripped at any time.
Since the producers section is relatively small, tools are encouraged to emit
the section or include themselves in an existing section by default, keeping
the producers section even in release builds.

An additional goal of the producers section is to provide a discrete, but
easily-growable [list of known tools](#known-tools) for each record field. This
avoids the skew that otherwise happens with unstructured strings. WebAssembly
consumers are encouraged to emit diagnostics when given values that don't match
the known tools list to encourage producers to register new field values in this
document.

Since version information is useful but highly-variable, every field value is
optionally suffixed with a parenthesized version string which is not validated
against any list.

# Known tools

The following lists contain all the valid tool names for the fields listed below.
**If your tool is not on this list and you'd like it to be, please submit a PR.**

## Source Languages

* `wat`
* `C`
* `C++`

## Individual Tools

* `wabt`
* `llvm`
* `lld`
* `Binaryen`

## SDKs

* `Emscripten`

# String formats

The binary encoding of record fields uses the standard
[name encoding](https://webassembly.github.io/spec/core/binary/values.html#names)
used elsewhere in wasm modules. However, the producers section imposes additional
validity constraints on the UTF-8-decoded code points of these strings.

## Tool name string

A tool name is a sequence of code points containing anything *other* than
parentheses and commas.

JS Pattern: `/[^(),]+/`

Example tool name strings:
* wabt
* c++
* ☃

## Version string

A version string can be appended to any tool name and describes the version of
that tool.

JS Pattern: `/\((\d+\.)*\d*\)/`

Example version strings:
* (1)
* (1.2)
* (0.12.1.30)

## Tool-version string

A tool-version string is a tool name string followed by an optional version string.

Pattern:
* Logical: `Tool name string` `Version string`?
* JS: `/[^(),]+(\((\d+\.)*\d*\))?/`

Example tool-version strings:
* a
* c++(11)
* ☃(0.0.1)

## Tool-version set string

A tool-version set string a is possibly-empty, comma-delimited list where each
contained tool name string is unique.

Pattern (ignoring uniqueness requirement):
* Logical: ( `Tool-version string` `,` )* `Tool-version string`
* JS: `/([^(),]+(\((\d+\.)*\d*\))?,)*[^(),]+(\((\d+\.)*\d*\))?/`

Example tool-version set strings:
* a
* a(1.0)
* llvm(20.3),binaryen,lld(1.3),webpack(4)

# Custom Section

Custom section `name` field: `producers`

The producers section may appear only once, and only after the
[Name section](https://webassembly.github.io/spec/core/appendix/custom.html#name-section).

The producers section contains a sequence of fields, where the end of the last
field must coincide with the last byte of the producers section:

| Field       | Type        | Description |
| ----------- | ----------- | ----------- |
| field_count | `varuint32` | number of fields that follow |
| fields      | `field*`     | sequence of `field` |

where a `field` is encoded as:

| Field       | Type | Description |
| ----------- | ---- | ----------- |
| field_name  | [name](https://webassembly.github.io/spec/core/binary/values.html#names) | name of this field, chosen from one of the set of valid field names below |
| field_value | [name](https://webassembly.github.io/spec/core/binary/values.html#names) | a string which match the specified pattern according to the table below |

The valid field names and their associated patterns are:

| field_name     | field_value pattern  | Valid tool names |
| -------------- | -------------------- | --------- |
| `language`     | [Tool-version string](#tool-version-string) | [source language list](#source-languages) |
| `processed-by` | [Tool-version set string](#tool-version-set-string) | [individual tool list](#individual-tools) |
| `sdk`          | [Tool-version string](#tool-version-string) | [SDK list](#sdks) |

# Text format

TODO
