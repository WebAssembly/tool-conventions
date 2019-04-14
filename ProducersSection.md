# Producers Section

The producers section provides an optional, structured way to record all of the
distinct tools that were used to produce a given WebAssembly module. The
producers section is a [custom section](https://webassembly.github.io/spec/core/binary/modules.html#custom-section)
and thus has no semantic effects. Standard tools like [wabt](https://github.com/webassembly/wabt)'s
`wasm-strip` will remove the producers section, and toolchains which emit the
producers section by default are recommended to have an option to remove it as
well.

## Custom Section

Custom section `name` field: `producers`

The producers section may appear only once, and only after the
[Name section](https://webassembly.github.io/spec/core/appendix/custom.html#name-section).

The producers section contains a sequence of fields with unique names, where the
end of the last field must coincide with the last byte of the producers section:

| Field       | Type        | Description |
| ----------- | ----------- | ----------- |
| field_count | `varuint32` | number of fields that follow |
| fields      | `field*`    | sequence of field_count `field` records |

where a `field` is encoded as:

| Field             | Type | Description |
| ----------------- | ---- | ----------- |
| field_name        | [name][name-ref] | name of this field |
| field_value_count | `varuint32` | number of value strings that follow |
| field_values      | `versioned-name*` | sequence of field_value_count name-value pairs |

where a `versioned-name` is encoded as:

| Field   | Type | Description |
| ------- | ---- | ----------- |
| name    | [name][name-ref] | name of the language/tool |
| version | [name][name-ref] | version of the language/tool |

with the additional constraint that each field_name in the list must be unique
and found in the first column of the following table, and each of a given field_name's
field_values's name strings must be unique and found in the second column of
the field_name's row.

| field_name     | field_value name strings |
| -------------- | -------------------- |
| `language`     | [source language list](#source-languages) |
| `processed-by` | [individual tool list](#individual-tools) |
| `sdk`          | [SDK list](#sdks)    |

[name-ref]: https://webassembly.github.io/spec/core/binary/values.html#names
