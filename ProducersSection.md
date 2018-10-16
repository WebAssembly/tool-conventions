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

WebAssembly consumers should avoid using the producers section to derive
optimization hints. To ensure portable performance, hints should be
standardized in a separate custom section, probably in the core spec's
[Custom Sections appendix](https://webassembly.github.io/spec/core/appendix/custom.html).

An additional goal of the producers section is to provide a discrete, but
easily-growable [list of known tools/languages](#known-list) for each
record field. This avoids the skew that otherwise happens with unstructured
strings. Unknown names do not invalidate an otherwise-valid producers section.
However, wasm consumers may provide less accurate telemetry results for unknown
names or even emit diagnostics encouraging the name to be put on the known list.

Since version information is useful, but highly-variable, each field value
is accompanied with a version string so that the name can remain stable
over time without requiring frequent updates to the known list.

# Custom Section

Custom section `name` field: `producers`

The producers section may appear only once, and only after the
[Name section](https://webassembly.github.io/spec/core/appendix/custom.html#name-section).

The producers section contains a sequence of fields with unique names, where the
end of the last field must coincide with the last byte of the producers section:

| Field       | Type        | Description |
| ----------- | ----------- | ----------- |
| field_count | `varuint32` | number of fields that follow |
| fields      | `field*`     | sequence of field_count `field` records |

where a `field` is encoded as:

| Field             | Type | Description |
| ----------------- | ---- | ----------- |
| field_name        | [name](https://webassembly.github.io/spec/core/binary/values.html#names) | name of this field |
| field_value_count | `varuint32` | number of value strings that follow |
| field_values      | `versioned-name*` | sequence of field_value_count name-value pairs |

where a `versioned-name` is encoded as:

| Field   | Type | Description |
| ------- | ---- | ----------- |
| name    | [name](https://webassembly.github.io/spec/core/binary/values.html#names) | name of the language/tool |
| version | [name](https://webassembly.github.io/spec/core/binary/values.html#names) | version of the language/tool |

with the additional constraint that each field_name in the list must be unique
and found in the first column of the following table, and each of a given field_name's
field_values's name strings must be unique and found in the second column of
the field_name's row.

| field_name     | field_value name strings |
| -------------- | -------------------- |
| `language`     | [source language list](#source-languages) |
| `processed-by` | [individual tool list](#individual-tools) |
| `sdk`          | [SDK list](#sdks) |

# Text format

TODO

# Known list

The following lists contain all the known names for the fields listed above.
**If your tool is not on this list and you'd like it to be, please submit a PR.**

## Source Languages

It is possible for multiple source languages to be present in a single module
when the output of multiple compiled languages are statically linked together.

* `wat`
* `C`
* `C++`

## Individual Tools

It is possible (and common) for multiple tools to be used in the overall
pipeline that produces and optimizes a given wasm module.

* `wabt`
* `LLVM`
* `lld`
* `Binaryen`

## SDKs

While an SDK is technically just another tool, the `sdk` field designates the
top-level "thing" that the developer installs and interacts with directly to
produce the wasm module.

* `Emscripten`

