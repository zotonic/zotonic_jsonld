%% @copyright 2026 Marc Worrell
%% @end

%% Copyright 2026 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(zotonic_jsonld_tests).

-include_lib("eunit/include/eunit.hrl").
-define(S, <<"https://schema.org/">>).

standard_prefix_and_roundtrip_test() ->
    Input = #{
        <<"@context">> => #{<<"s">> => ?S, <<"name">> => <<"s:name">>},
        <<"@id">> => <<"https://example.test/alice">>,
        <<"name">> => <<"Alice">>
    },
    {ok, [D]} = zotonic_jsonld:parse(Input),
    ?assertEqual(#{<<"@value">> => <<"Alice">>}, maps:get(<<"schema:name">>, D)),
    ?assertEqual(zotonic_rdf:namespaces(), maps:get(<<"@context">>, D)),
    {ok, Encoded} = zotonic_jsonld:generate(D),
    ?assertEqual({ok, [D]}, zotonic_jsonld:parse(Encoded)).

context_aliases_and_coercion_test() ->
    C = #{
        <<"id">> => <<"@id">>,
        <<"kind">> => <<"@type">>,
        <<"s">> => ?S,
        <<"friend">> => #{<<"@id">> => <<"s:knows">>, <<"@type">> => <<"@id">>},
        <<"count">> => #{<<"@id">> => <<"s:count">>, <<"@type">> => <<"xsd:integer">>},
        <<"xsd">> => <<"http://www.w3.org/2001/XMLSchema#">>,
        <<"@base">> => <<"https://example.test/">>,
        <<"@vocab">> => ?S,
        <<"@language">> => <<"EN">>
    },
    {ok, [D]} = zotonic_jsonld:expand(#{
        <<"@context">> => C,
        <<"id">> => <<"alice">>,
        <<"kind">> => <<"Person">>,
        <<"name">> => <<"Alice">>,
        <<"friend">> => <<"bob">>,
        <<"count">> => <<"01">>
    }),
    ?assertEqual(<<"https://example.test/alice">>, maps:get(<<"@id">>, D)),
    ?assertEqual([<<?S/binary, "Person">>], maps:get(<<"@type">>, D)),
    ?assertEqual(
        [#{<<"@id">> => <<"https://example.test/bob">>}], maps:get(<<?S/binary, "knows">>, D)
    ),
    ?assertEqual(
        [#{<<"@value">> => <<"Alice">>, <<"@language">> => <<"en">>}],
        maps:get(<<?S/binary, "name">>, D)
    ),
    ?assertEqual(
        [
            #{
                <<"@value">> => <<"01">>,
                <<"@type">> => <<"http://www.w3.org/2001/XMLSchema#integer">>
            }
        ],
        maps:get(<<?S/binary, "count">>, D)
    ).

remote_contexts_and_import_test() ->
    A = <<"https://example.test/context/a">>,
    B = <<"https://example.test/context/b">>,
    Loader = fun
        (A0) when A0 =:= A ->
            {ok, #{<<"@context">> => [<<"b">>, #{<<"name">> => <<"s:name">>}]}};
        (B0) when B0 =:= B ->
            {ok, #{<<"@context">> => #{<<"s">> => ?S}}}
    end,
    ?assertMatch(
        {ok, [#{<<"schema:name">> := _}]},
        zotonic_jsonld:parse(
            #{<<"@context">> => A, <<"name">> => <<"Alice">>}, #{
                allow_external_contexts => true, document_loader => Loader
            }
        )
    ),
    ?assertMatch(
        {ok, [#{<<"schema:name">> := _}]},
        zotonic_jsonld:parse(
            #{
                <<"@context">> => #{<<"@import">> => B, <<"name">> => <<"s:name">>},
                <<"name">> => <<"Alice">>
            },
            #{allow_external_contexts => true, document_loader => Loader}
        )
    ),
    Cyclic = #{A => #{<<"@context">> => B}, B => #{<<"@context">> => A}},
    ?assertMatch(
        {error, {recursive_context, _}},
        zotonic_jsonld:parse(
            #{<<"@context">> => A}, #{contexts => Cyclic}
        )
    ),
    ?assertMatch(
        {error, {loading_context_failed, _, offline}},
        zotonic_jsonld:parse(
            #{<<"@context">> => A}, #{
                allow_external_contexts => true,
                document_loader => fun(_) ->
                    {error, offline}
                end
            }
        )
    ).

scoped_context_test() ->
    C = #{
        <<"@vocab">> => ?S,
        <<"child">> => #{
            <<"@id">> => <<"schema:knows">>,
            <<"@context">> => #{<<"label">> => <<"schema:name">>}
        }
    },
    {ok, [D]} = zotonic_jsonld:parse(#{
        <<"@context">> => C, <<"child">> => #{<<"label">> => <<"Bob">>}
    }),
    ?assertMatch(
        #{<<"schema:name">> := #{<<"@value">> := <<"Bob">>}}, maps:get(<<"schema:knows">>, D)
    ).

type_scope_test() ->
    C = #{
        <<"@vocab">> => ?S,
        <<"Person">> => #{
            <<"@id">> => <<"schema:Person">>,
            <<"@context">> => #{<<"label">> => <<"schema:name">>}
        }
    },
    {ok, [D]} = zotonic_jsonld:parse(#{
        <<"@context">> => C, <<"@type">> => <<"Person">>, <<"label">> => <<"Alice">>
    }),
    ?assert(maps:is_key(<<"schema:name">>, D)).

containers_test() ->
    C = #{
        <<"@vocab">> => ?S,
        <<"names">> => #{<<"@id">> => <<"schema:name">>, <<"@container">> => <<"@language">>},
        <<"items">> => #{
            <<"@id">> => <<"schema:itemListElement">>, <<"@container">> => <<"@list">>
        },
        <<"people">> => #{<<"@id">> => <<"schema:knows">>, <<"@container">> => <<"@id">>}
    },
    Input = #{
        <<"@context">> => C,
        <<"names">> => #{<<"EN">> => <<"Hello">>, <<"nl">> => <<"Hallo">>},
        <<"items">> => [1, 2],
        <<"people">> => #{<<"https://example.test/bob">> => #{<<"name">> => <<"Bob">>}}
    },
    {ok, [D]} = zotonic_jsonld:parse(Input),
    ?assertEqual(2, length(maps:get(<<"schema:name">>, D))),
    ?assertMatch(#{<<"@list">> := [_, _]}, maps:get(<<"schema:itemListElement">>, D)),
    ?assertMatch(#{<<"@id">> := <<"https://example.test/bob">>}, maps:get(<<"schema:knows">>, D)),
    {ok, Out} = zotonic_jsonld:generate(D),
    ?assertEqual({ok, [D]}, zotonic_jsonld:parse(Out)).

null_and_protected_context_test() ->
    ?assertMatch(
        {error, {protected_term_redefinition, _}},
        zotonic_jsonld:expand(
            #{
                <<"@context">> => [
                    #{<<"@protected">> => true, <<"p">> => <<"https://example.test/p">>},
                    #{<<"p">> => <<"https://example.test/other">>}
                ]
            }
        )
    ),
    ?assertEqual(
        {ok, []},
        zotonic_jsonld:expand(#{
            <<"@context">> => [#{<<"@vocab">> => ?S}, null], <<"name">> => <<"ignored">>
        })
    ),
    ?assertMatch(
        {error, {cyclic_term_definition, _}},
        zotonic_jsonld:expand(
            #{<<"@context">> => #{<<"a">> => <<"b">>, <<"b">> => <<"a">>}}
        )
    ).

reverse_graph_and_json_test() ->
    D = #{
        <<"@context">> => #{
            <<"@vocab">> => ?S, <<"parent">> => #{<<"@reverse">> => <<"schema:knows">>}
        },
        <<"@id">> => <<"https://example.test/a">>,
        <<"parent">> => #{<<"@id">> => <<"https://example.test/b">>}
    },
    ?assertMatch(
        {ok, [
            #{
                <<"subject">> := <<"https://example.test/b">>,
                <<"@id">> := <<"https://example.test/a">>
            }
        ]},
        zotonic_jsonld:to_triples(D)
    ),
    Json = #{
        <<"@context">> => #{
            <<"data">> => #{
                <<"@id">> => <<"https://example.test/data">>, <<"@type">> => <<"@json">>
            }
        },
        <<"data">> => #{<<"@context">> => null, <<"untouched">> => [1, true]}
    },
    {ok, [Parsed]} = zotonic_jsonld:parse(Json),
    {ok, Encoded} = zotonic_jsonld:generate(Parsed),
    ?assertEqual({ok, [Parsed]}, zotonic_jsonld:parse(Encoded)).

json_lexical_values_test() ->
    Raw = #{<<"_type">> => <<"_tuple">>, <<"_list">> => [null, <<"2008-12-10T13:30:00Z">>]},
    Input = #{
        <<"@context">> => #{
            <<"data">> => #{
                <<"@id">> => <<"https://example.test/data">>, <<"@type">> => <<"@json">>
            }
        },
        <<"data">> => Raw,
        <<"schema:dateCreated">> => <<"2008-12-10T13:30:00Z">>
    },
    {ok, [D]} = zotonic_jsonld:parse(jsxrecord:encode(Input)),
    ?assertMatch(#{<<"@value">> := Raw}, maps:get(<<"https://example.test/data">>, D)),
    ?assertEqual(
        #{<<"@value">> => <<"2008-12-10T13:30:00Z">>}, maps:get(<<"schema:dateCreated">>, D)
    ),
    {ok, Json} = zotonic_jsonld:generate(D, #{pretty => true}),
    ?assertEqual({ok, [D]}, zotonic_jsonld:parse(Json)).

protected_scope_and_recursion_test() ->
    C = #{
        <<"@vocab">> => ?S,
        <<"@protected">> => true,
        <<"name">> => <<"schema:name">>,
        <<"child">> => #{<<"@context">> => #{<<"name">> => <<"schema:alternateName">>}}
    },
    {ok, [D]} = zotonic_jsonld:parse(#{
        <<"@context">> => C,
        <<"name">> => <<"Alice">>,
        <<"child">> => #{<<"name">> => <<"Bob">>}
    }),
    ?assert(maps:is_key(<<"schema:name">>, D)),
    ?assertMatch(#{<<"schema:alternateName">> := _}, maps:get(<<"schema:child">>, D)),
    ?assertMatch(
        {error, _},
        zotonic_jsonld:expand(#{
            <<"@context">> => #{
                <<"p">> => #{
                    <<"@id">> => <<"https://example.test/p">>,
                    <<"@context">> => #{<<"undefinedTerm">> => #{<<"@context">> => #{}}}
                }
            }
        })
    ).

remote_context_base_test() ->
    Url = <<"https://example.test/contexts/main">>,
    Contexts = #{
        Url => #{
            <<"@context">> => [
                #{<<"@base">> => <<"https://wrong.test/">>},
                <<"child">>
            ]
        },
        <<"https://example.test/contexts/child">> =>
            #{<<"@context">> => #{<<"p">> => <<"https://example.test/p">>}}
    },
    {ok, [D]} = zotonic_jsonld:expand(
        #{
            <<"@context">> => Url,
            <<"@id">> => <<"node">>,
            <<"p">> => true
        },
        #{base => <<"https://document.test/">>, contexts => Contexts}
    ),
    ?assertEqual(<<"https://document.test/node">>, maps:get(<<"@id">>, D)).

unicode_iri_and_invalid_input_test() ->
    Name = unicode:characters_to_binary([16#e9]),
    Iri = <<"https://example.test/", Name/binary>>,
    {ok, [D]} = zotonic_jsonld:expand(
        #{
            <<"@id">> => Name,
            <<"https://example.test/p">> => 1
        },
        #{base => <<"https://example.test/">>}
    ),
    ?assertEqual(Iri, maps:get(<<"@id">>, D)),
    ?assertMatch({error, {invalid_json, _}}, zotonic_jsonld:parse(<<"{">>)),
    ?assertMatch(
        {error, unsupported_processing_mode},
        zotonic_jsonld:expand(#{}, #{processing_mode => <<"json-ld-1.0">>})
    ).

external_contexts_disabled_test() ->
    Loader = fun(_) ->
        error(external_loader_must_not_be_called)
    end,
    Apis = [
        fun zotonic_jsonld:parse/2,
        fun zotonic_jsonld:expand/2,
        fun zotonic_jsonld:generate/2,
        fun zotonic_jsonld:to_triples/2
    ],
    lists:foreach(
        fun(Url) ->
            Input = #{<<"@context">> => Url},
            Expected = {error, {external_context_loading_disabled, Url}},
            ?assertEqual(Expected, zotonic_jsonld:parse(Input)),
            lists:foreach(
                fun(Api) ->
                    ?assertEqual(Expected, Api(Input, #{document_loader => Loader})),
                    ?assertEqual(
                        Expected,
                        Api(Input, #{
                            allow_external_contexts => false,
                            document_loader => Loader
                        })
                    )
                end,
                Apis
            )
        end,
        [
            <<"https://example.test/context">>,
            <<"http://example.test/context">>,
            <<"file:///tmp/context.jsonld">>
        ]
    ).

nested_external_contexts_disabled_test() ->
    Url = <<"https://example.test/context">>,
    Loader = fun(_) ->
        error(external_loader_must_not_be_called)
    end,
    Contexts = [
        [#{}, Url],
        #{<<"@import">> => Url},
        #{<<"p">> => #{<<"@id">> => <<"https://example.test/p">>, <<"@context">> => Url}}
    ],
    lists:foreach(
        fun(Context) ->
            ?assertEqual(
                {error, {external_context_loading_disabled, Url}},
                zotonic_jsonld:parse(#{<<"@context">> => Context}, #{document_loader => Loader})
            )
        end,
        Contexts
    ),
    CachedUrl = <<"https://example.test/cached">>,
    ?assertEqual(
        {error, {external_context_loading_disabled, Url}},
        zotonic_jsonld:parse(#{<<"@context">> => CachedUrl}, #{
            contexts => #{CachedUrl => #{<<"@context">> => Url}}, document_loader => Loader
        })
    ),
    ?assertEqual(
        {error, {external_context_loading_disabled, Url}},
        zotonic_jsonld:expand(#{}, #{context => Url, document_loader => Loader})
    ).

supplied_contexts_do_not_require_external_loading_test() ->
    Url = <<"https://example.test/context">>,
    Context = #{<<"@context">> => #{<<"name">> => <<"https://schema.org/name">>}},
    Input = #{<<"@context">> => Url, <<"name">> => <<"Alice">>},
    Options = #{
        allow_external_contexts => false,
        contexts => #{Url => Context},
        document_loader => fun(_) ->
            error(external_loader_must_not_be_called)
        end
    },
    ?assertMatch(
        {ok, [#{<<"schema:name">> := #{<<"@value">> := <<"Alice">>}}]},
        zotonic_jsonld:parse(Input, Options)
    ).

external_context_loading_opt_in_test() ->
    Url = <<"https://example.test/context">>,
    Input = #{<<"@context">> => Url, <<"name">> => <<"Alice">>},
    Loader = fun(RequestedUrl) ->
        ?assertEqual(Url, RequestedUrl),
        {ok, #{<<"@context">> => #{<<"name">> => <<"https://schema.org/name">>}}}
    end,
    Options = #{allow_external_contexts => true, document_loader => Loader},
    ?assertMatch(
        {ok, [#{<<"schema:name">> := #{<<"@value">> := <<"Alice">>}}]},
        zotonic_jsonld:parse(Input, Options)
    ),
    ?assertEqual(
        {error, {external_context_loading_disabled, Url}},
        zotonic_jsonld:parse(Input, Options#{allow_external_contexts => false})
    ),
    %% Opt-in does not add filesystem access to the built-in HTTP(S) loader.
    FileUrl = <<"file:///tmp/context.jsonld">>,
    ?assertEqual(
        {error, {loading_context_failed, FileUrl, unsupported_url_scheme}},
        zotonic_jsonld:parse(#{<<"@context">> => FileUrl}, #{allow_external_contexts => true})
    ).
