# Annotations

One of the design principles behind the [Wasm OCI Artifact
Layout](https://tag-runtime.cncf.io/wgs/wasm/deliverables/wasm-oci-artifact/) is
that it operates as a thin wrapper around Wasm Component binaries. Ideally this
would mean that it is possible to decode an OCI image to a Wasm Component, and
re-encode it back as OCI (roundtrip) without losing any information.
 
OCI images support a standard set of annotations for metadata, used by
registries such as GitHub Container Registry and Azure Container Registry in
their respective interfaces. These annotations are documented as part of the
[OpenContainers Annotation
Spec](https://specs.opencontainers.org/image-spec/annotations/). This
specification contains metadata such as the date/time when the image was
created, the license the image has, who the image was published by, and who the
image was published by.

## Custom Sections

This specifies custom sections for Wasm binaries, their encoding, and how they
map to fields in the OpenContainers Annotation Spec.

| Wasm Custom Section Name | OCI Annotation Key                     | Custom Section Encoding                                                                                                 |
| :----------------------- | :------------------------------------- | :---------------------------------------------------------------------------------------------------------------------- |
| authors                  | org.opencontainers.image.authors       | freeform string                                                                                                         |
| created                  | org.opencontainers.image.created       | [IETF RFC 3339](https://tools.ietf.org/html/rfc3339#section-5.6) date-time encoded as a string                          |
| description              | org.opencontainers.image.description   | URL encoded as a string                                                                                                 |
| documentation            | org.opencontainers.image.documentation | URL encoded as a string                                                                                                 |
| homepage                 | org.opencontainers.image.url           | URL encoded as a string                                                                                                 |
| licenses                 | org.opencontainers.image.licenses      | [SPDX License Expression](https://spdx.github.io/spdx-spec/v3.0.1/annexes/spdx-license-expressions) encoded as a string |
| revision                 | org.opencontainers.image.revision      | freeform string                                                                                                         |
| source                   | org.opencontainers.image.source        | freeform string                                                                                                         |
| vendor                   | org.opencontainers.image.vendor        | freeform string                                                                                                         |
| version                  | org.opencontainers.image.version       | freeform string                                                                                                         |

## See Also

- [Producers Section](./ProducersSection.md)
- [Wasm OCI Artifact Layout](https://tag-runtime.cncf.io/wgs/wasm/deliverables/wasm-oci-artifact/)

## References

- [OpenContainers Annotations Spec](https://specs.opencontainers.org/image-spec/annotations/)
- [webassembly/tool-conventions#230](https://github.com/WebAssembly/tool-conventions/issues/230)
- [IETF RFC 3339 | Date and Time on the Internet: Timestamps](https://tools.ietf.org/html/rfc3339)
- [SPDX License Expressions](https://spdx.github.io/spdx-spec/v3.0.1/annexes/spdx-license-expressions)
