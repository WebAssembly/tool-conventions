This repository holds documents describing *conventions* useful for coordinating interoperability between wasm-related tools. This includes descriptions of intermediate file formats, conventions for mapping high-level language types, names, and abstraction features to WebAssembly types, identifiers, and implementations, and schemes for supporting debuggers or other tools.

These conventions are not part of the WebAssembly standard, and are not required of WebAssembly-consuming implementations to execute WebAssembly code. Tools producing and working with WebAssembly in other ways also need not follow any of these conventions. They exist only to support tools that wish to interoperate with other tools at a higher abstraction level than just WebAssembly itself.

These conventions are also not exclusive. There could be multiple conventions for a given language for a given purpose. There are natural benefits to interoperability, but there are many reasons where having more than one way to do things can also make sense in m
any circumstances.
