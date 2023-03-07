Basic Module ABI
================

There are many different ways to use Wasm modules, and many different
conventions, language-specific ABIs, and toolchain-specific ABIs. This
document describes ABI features intended to be common across all ABIs.

## The `_initialize` function

If a module exports a function named `_initialize` with no arguments and no
return values, and does not export a function named `_start`, the toolchain
that produced my assume that on any instance of the module, this `_initialize`
function is called before any other exports are accessed.

This is intended to support language features such as C++ static constructors,
as well as "top-level scripts" in many scripting languages, which can't use
the [wasm start function] because they may call imports that need to access
the module's exports. In use cases that don't need this, the wasm start
function should be used.

[wasm start section]: https://webassembly.github.io/spec/core/syntax/modules.html#syntax-start
