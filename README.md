# zotonic_jsonld

Erlang JSON-LD 1.1 expansion, parsing and generation using the document maps and
standard namespaces from `zotonic_rdf`. JSON decoding and encoding use
`jsxrecord`; decoding disables date and record conversion so lexical values and
arbitrary JSON objects remain intact. Parsing is offline by default: embedded
contexts and explicitly supplied context documents are resolved without fetching
external resources.

## Quick start

```erlang
Input = #{
    <<"@context">> => #{<<"name">> => <<"https://schema.org/name">>},
    <<"@id">> => <<"https://example.org/alice">>,
    <<"name">> => <<"Alice">>
},
{ok, Documents} = zotonic_jsonld:parse(Input),
{ok, Json} = zotonic_jsonld:generate(Documents),
{ok, Expanded} = zotonic_jsonld:expand(Json),
{ok, Triples} = zotonic_jsonld:to_triples(Documents).
```

## API

All functions return `{ok, Result}` or `{error, Reason}`. Each accepts an optional
second argument with an options map. `decode/1,2` and `encode/1,2` are aliases for
`parse/1,2` and `generate/1,2`.

* `parse`: accepts UTF-8 JSON, a decoded map, or an array; returns a list of
  document maps. Every document has the standard `@context`, properties and
  datatypes use standard prefixes, and singleton property values are collapsed.
* `expand`: returns context-free JSON-LD expansion with absolute properties and
  array values. No standard context is implicitly supplied to this operation.
* `generate`: normalizes documents before serializing. A single document becomes
  a JSON object; multiple documents use an `@graph` wrapper with a shared context.
* `to_triples`: expands documents into the binary-keyed triple maps used by
  `zotonic_rdf`. Collections become `rdf:first`/`rdf:rest` triples; named graphs
  have an additional `<<"graph">>` key.

## Document format

The quick-start input produces one document with this shape:

```erlang
#{
    <<"@context">> => zotonic_rdf:namespaces(),
    <<"@id">> => <<"https://example.org/alice">>,
    <<"schema:name">> => #{<<"@value">> => <<"Alice">>}
}.
```

Properties with several values retain an array. A parsed typed value retains its
lexical form and explicit datatype:

```erlang
#{<<"@value">> => <<"01">>, <<"@type">> => <<"xsd:integer">>}
```

Blank-node IDs, references, shared nodes, list order, language tags and JSON-LD
`@json` values are retained. Output uses `zotonic_rdf:namespaces/0`, including
`zotonic: <http://zotonic.net/predicate/>`. Unknown absolute IRIs stay expanded.

## Context processing and options

Contexts are recursively processed, including context arrays, remote contexts,
`@import`, dependent term definitions, prefix and keyword aliases, base/vocabulary
IRIs, language/direction defaults, protected terms, property/type scoped contexts,
propagation, reverse properties, nesting, and list/set/language/index/id/type/graph
containers. Scoped contexts are validated even when their terms are unused.
Unmapped properties follow JSON-LD expansion rules and are omitted.

| Option | Meaning |
| --- | --- |
| `base` | Document base IRI as a binary. |
| `context` | Initial context; defaults to standard Zotonic namespaces for parse/generate/to_triples, and an empty context for expand. |
| `contexts` | Map from absolute context URL to a decoded document or JSON binary. Available even when external loading is disabled. Checked before the loader. |
| `allow_external_contexts` | Permit external context loading, including custom loader callbacks. Default `false`; only `true` enables it. |
| `document_loader` | `fun(Url) -> {ok, Document} \| {error, Reason}`; may return `{ok, #{document => Document, document_url => EffectiveUrl}}` for redirects. |
| `max_depth` | Maximum nested document-object depth, default 128. |
| `max_context_depth` | Maximum remote/scoped context depth, default 32. |
| `pretty` | Indent generated JSON, default `false`. |
| `processing_mode` | `<<"json-ld-1.1">>`; legacy 1.0 mode is not supported. |

External loading is disabled by default. An uncached context URL returns
`{error, {external_context_loading_disabled, Url}}`. The same rule applies to
`@import`, nested/scoped contexts and an initial `context` option. Supplying a
`document_loader` alone does not enable loading. All expansion-based APIs,
including generation and conversion to triples, use this policy.

To opt in to HTTP(S) context loading:

```erlang
{ok, Documents} = zotonic_jsonld:parse(Input, #{allow_external_contexts => true}).
```

The built-in loader uses verified TLS, request timeouts, a redirect limit and a
4 MiB accepted response limit. It does not read filesystem paths or `file:` URLs,
even after opt-in, and does not process HTML or HTTP Link-header contexts. A
custom loader can implement other sources, subject to the same opt-in switch.
For untrusted input, keep external loading disabled or supply a loader enforcing
your application's network/file-access policy.

Resolve known context URLs without external I/O by supplying their documents:

```erlang
Options = #{
    allow_external_contexts => false,
    contexts => #{
        <<"https://example.org/context">> => #{
            <<"@context">> => #{<<"name">> => <<"https://schema.org/name">>}
        }
    }
}.
```

Setting `allow_external_contexts => false` also disables a configured custom
loader. Unknown, disabled or failed external contexts return errors; they are
never silently left unexpanded.

JSON-LD directional and `@json` values round-trip as documents. Conversion of
these values to RDF triples is currently rejected explicitly. Framing,
application-selected compaction contexts and RDF dataset canonicalization are
outside this API.

## Build and test

The Makefile downloads a local rebar3 when needed (requires curl). To use an
existing installation, pass its absolute path, for example
`make REBAR="$(command -v rebar3)"`. GNU make is required; on systems whose
default make is not GNU make, the wrapper uses `gmake`. GitHub Actions runs
compilation, EUnit (including the vendored W3C cases), XRef and Dialyzer on
OTP 27, 28 and 29 for pushes and pull requests to `main`.

Requires Erlang/OTP 25 or later and rebar3. The dependency requirements include
`zotonic_rdf` 1.2.0 and `jsxrecord` 2.3.0, which provide the shared RDF document
and IRI APIs, Zotonic namespace and configurable JSON decoding. No dependency
checkouts are needed for these APIs.

```sh
make
make test
make xref
make dialyzer
```

In the Zotonic umbrella the applications are discovered in `_checkouts`.
The complete W3C JSON-LD test fixture set is vendored in
[`test/data/w3c-jsonld`](test/data/w3c-jsonld/SOURCE.md), with its original
manifests, input/output documents, support files and licensing.
`jsonld_w3c_tests` runs the 367 applicable JSON-LD 1.1 expansion cases by default,
using an explicitly enabled loader that reads only local fixtures. No network
access or environment variable is needed. Negative cases assert rejection, not
exact W3C error-code names. The other algorithm fixtures are retained for future
coverage; they are not currently executed by this runner.

To test a different upstream checkout, override the fixture directory:

```sh
W3C_JSONLD_TESTS=/path/to/json-ld-api/tests rebar3 eunit
```

## License and provenance

Copyright 2026 Marc Worrell. The Erlang source and test runners use
[Apache-2.0](LICENSE); see [NOTICE](NOTICE) for attribution and references.
This is an implementation written for Zotonic, not a port or direct
transliteration of the Elixir or Java libraries below. Those projects provided
API and behavior references; their implementation source is not included.
The vendored fixtures retain their original notices and separate
[W3C licensing](test/data/w3c-jsonld/LICENSE.md). Full
[W3C 3-clause BSD terms](test/data/w3c-jsonld/LICENSE-W3C-BSD.txt) and
[source details](test/data/w3c-jsonld/SOURCE.md) are included alongside them.

The [completed license review](LICENSE_REVIEW.md) records the checked source
headers, dependency metadata, pinned fixture revisions and redistribution notices.
The fixtures are used under the BSD option for development testing; local test
results do not constitute W3C conformance certification or endorsement.

## References

Implementation behavior was checked against the [W3C JSON-LD algorithms](https://www.w3.org/TR/json-ld11-api/)
and the API/context examples in Java's [Titanium JSON-LD](https://github.com/filip26/titanium-json-ld),
[jsonld-java](https://github.com/jsonld-java/jsonld-java), and Elixir's
[JSON-LD.ex](https://github.com/rdf-elixir/jsonld-ex).
