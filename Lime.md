# The Lime Series

Lime is a series of defined and stable subsets of [WebAssembly features] that producers
and consumers can both use to promote interoperability. It is intended to be implemented
by producers such as LLVM, using features such as LLVM's concept of target CPUs. Once a
Lime configuration is defined, it will be stable and not add or remove any features.

Lime configuration names include a version number, such as "Lime1". When there is a
need to add or remove features, a new Lime configuration with a new version number will
be defined, such as "Lime2".

Lime aims for features which do not involve significant new runtime cost or complexity,
and can be implemented in mobile devices and other highly constrained environments.

The name "Lime" was inspired by abbreviating *Li*near *Me*mory, as this series currently
lacks wasm-gc and is therefore focused on linear-memory languages.

## The configurations

The following Lime configurations have been defined:
 - [Lime1](#lime1)

### Lime1

The Lime1 target consists of [WebAssembly 1.0] plus the following standardized
([phase-5]) features:

 - [mutable-globals]
 - [multivalue]
 - [sign-ext]
 - [nontrapping-fptoint]
 - [bulk-memory-opt]
 - [extended-const]
 - [call-indirect-overlong]

[WebAssembly features]: https://webassembly.org/features/
[WebAssembly 1.0]: https://www.w3.org/TR/wasm-core-1/
[phase-5]: https://github.com/WebAssembly/meetings/blob/main/process/phases.md#5-the-feature-is-standardized-working-group
[mutable-globals]: https://github.com/WebAssembly/mutable-global/blob/master/proposals/mutable-global/Overview.md
[multivalue]: https://github.com/WebAssembly/spec/blob/master/proposals/multi-value/Overview.md
[sign-ext]: https://github.com/WebAssembly/spec/blob/master/proposals/sign-extension-ops/Overview.md
[nontrapping-fptoint]: https://github.com/WebAssembly/spec/blob/master/proposals/nontrapping-float-to-int-conversion/Overview.md
[bulk-memory-opt]: #bulk-memory-opt
[extended-const]: https://github.com/WebAssembly/extended-const/blob/main/proposals/extended-const/Overview.md
[call-indirect-overlong]: #call-indirect-overlong

## Feature subsets

[WebAssembly features] sometimes contain several features combined into a
single proposal to simplify the standardization process, but can have very
different implementation considerations. This section defines subsets of
standardized features for use in Lime configurations.

### bulk-memory-opt

bulk-memory-opt is a subset of the [bulk-memory] feature that contains just the
`memory.copy` and `memory.fill` instructions.

It does not include the table instructions, `memory.init`, or `data.drop`.

### call-indirect-overlong

call-indirect-overlong is a subset of the [reference-types] feature that contains
just the change to the `call_indirect` instruction encoding to change the zero
byte to an LEB encoding which may have an overlong encoding.

It does not include the actual reference types.

[bulk-memory]: https://github.com/WebAssembly/bulk-memory-operations/blob/master/proposals/bulk-memory-operations/Overview.md
[reference-types]: https://github.com/WebAssembly/reference-types/blob/master/proposals/reference-types/Overview.md
