%% @copyright 2026 Marc Worrell
%% @doc Expand context-dependent JSON-LD into context-free document maps.
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

-module(jsonld_expand).

-export([
    expand/2
]).

expand(Input, Options) ->
    check(
        maps:get(processing_mode, Options, <<"json-ld-1.1">>) =:= <<"json-ld-1.1">>,
        unsupported_processing_mode
    ),
    C = jsonld_context:process(maps:get(context, Options, #{}), jsonld_context:new(Options)),
    Expanded = element_value(Input, C, #{}, 0),
    case Expanded of
        [#{<<"@graph">> := Ds} = Only] when map_size(Only) =:= 1 ->
            free_nodes(Ds);
        _ ->
            [
                D
             || D <- Expanded,
                is_map(D),
                map_size(D) > 0,
                not maps:is_key(<<"@value">>, D),
                not maps:is_key(<<"@list">>, D),
                not (map_size(D) =:= 1 andalso maps:is_key(<<"@id">>, D))
            ]
    end.

element_value(null, _C, _Term, _Depth) ->
    [];
element_value(List, C, Term, Depth) when is_list(List) ->
    lists:append([
        case is_list(V) andalso maps:get(in_list, Term, false) of
            true ->
                [#{<<"@list">> => element_value(V, C, Term, Depth)}];
            false ->
                element_value(V, C, Term, Depth)
        end
     || V <- List
    ]);
element_value(Map, Incoming, Term, Depth) when is_map(Map) ->
    C0 = element_context(Map, Incoming),
    check(Depth < maps:get(max_depth, maps:get(options, C0), 128), document_depth_exceeded),
    C1 = case maps:find(<<"@context">>, Map) of
        {ok, Local} ->
            jsonld_context:process(Local, C0);
        error ->
            C0
    end,
    C = type_context(Map, C1),
    Result = lists:foldl(
        fun({Key, V}, Acc) ->
            property(Key, V, C#{active_term => Term}, Depth + 1, Acc)
        end,
        #{},
        lists:sort(maps:to_list(Map))
    ),
    finish(Result);
element_value(Value, C, Term, _Depth) ->
    [scalar(Value, jsonld_context:scope(maps:get(property_scope, C, #{}), C), Term)].

type_context(Map, C) ->
    Types = lists:append([
        many(V)
     || {K, V} <- maps:to_list(Map), jsonld_context:iri(K, C, vocab) =:= <<"@type">>
    ]),
    Scoped = lists:foldl(
        fun(T, Acc) ->
            case jsonld_context:term(T, C) of
                #{context := Local, context_base := Base} ->
                    Next = jsonld_context:process(Local, Acc#{context_base => Base}),
                    case is_map(Local) andalso maps:get(<<"@propagate">>, Local, false) of
                        true ->
                            Next;
                        false ->
                            Next#{
                                previous =>
                                    case maps:get(previous, Acc, undefined) of
                                        undefined ->
                                            C;
                                        Prev ->
                                            Prev
                                    end
                            }
                    end;
                _ ->
                    Acc
            end
        end,
        C,
        lists:sort(Types)
    ),
    Scoped#{type_context => C}.

property(<<"@context">>, _V, _C, _Depth, Acc) ->
    Acc;
property(Key, V, C, Depth, Acc) ->
    Expanded = jsonld_context:iri(Key, C, vocab),
    case Expanded of
        null ->
            Acc;
        <<"@id">> ->
            check(is_binary(V), invalid_id_value),
            unique(Expanded, jsonld_context:iri(V, C, document), Acc);
        <<"@type">> ->
            Ts = many(V),
            check(lists:all(fun is_binary/1, Ts), invalid_type_value),
            append(Expanded, [type_iri(T, maps:get(type_context, C, C)) || T <- Ts], Acc);
        <<"@value">> ->
            unique(Expanded, V, Acc);
        <<"@language">> ->
            check(is_binary(V), invalid_language_value),
            unique(Expanded, lower(V), Acc);
        <<"@direction">> ->
            check(lists:member(V, [<<"ltr">>, <<"rtl">>]), invalid_direction_value),
            unique(Expanded, V, Acc);
        <<"@index">> ->
            check(is_binary(V), invalid_index_value),
            unique(Expanded, V, Acc);
        <<"@graph">> ->
            unique(Expanded, free_nodes(element_value(V, child(C), #{}, Depth)), Acc);
        <<"@included">> ->
            Nodes = element_value(V, child(C), #{}, Depth),
            check(
                lists:all(
                    fun(X) ->
                        not maps:is_key(<<"@value">>, X) andalso not maps:is_key(<<"@list">>, X)
                    end,
                    Nodes
                ),
                invalid_included_value
            ),
            append(Expanded, Nodes, Acc);
        <<"@list">> ->
            unique(
                Expanded,
                element_value(V, C, (maps:get(active_term, C, #{}))#{in_list => true}, Depth),
                Acc
            );
        <<"@set">> ->
            unique(Expanded, element_value(V, C, maps:get(active_term, C, #{}), Depth), Acc);
        <<"@nest">> ->
            lists:foldl(
                fun(M, A) ->
                    check(is_map(M), invalid_nest_value),
                    NC = jsonld_context:scope(jsonld_context:term(Key, C), C),
                    check(
                        not lists:any(
                            fun(K) ->
                                jsonld_context:iri(K, NC, vocab) =:= <<"@value">>
                            end,
                            maps:keys(M)
                        ),
                        invalid_nest_value
                    ),
                    lists:foldl(
                        fun({K, X}, B) ->
                            property(K, X, NC, Depth, B)
                        end,
                        A,
                        maps:to_list(M)
                    )
                end,
                Acc,
                many(V)
            );
        <<"@reverse">> ->
            check(is_map(V), invalid_reverse_value),
            Rs = element_value(V, C, #{}, Depth),
            lists:foldl(
                fun(R, A) ->
                    maps:fold(
                        fun(P, Vs, B) ->
                            reverse_values(P, Vs, B)
                        end,
                        A,
                        R
                    )
                end,
                Acc,
                Rs
            );
        <<"@", _/binary>> ->
            Acc;
        _ ->
            case is_absolute(Expanded) of
                false ->
                    Acc;
                true ->
                    Term = jsonld_context:term(Key, C),
                    Values = property_values(V, C, Term, Depth),
                    case {V, Values, maps:get(reverse, Term, false)} of
                        {null, [], _} ->
                            Acc;
                        {_, [], _} when not is_list(V), not is_map(V) ->
                            Acc;
                        {#{<<"@value">> := null}, [], _} ->
                            Acc;
                        {#{<<"@language">> := _} = LM, [], _} when map_size(LM) =:= 1 ->
                            Acc;
                        {_, _, true} ->
                            reverse_values(Expanded, Values, Acc);
                        {_, _, false} ->
                            append(Expanded, Values, Acc)
                    end
            end
    end.

property_values(V, C, Term, Depth) ->
    Child = C#{revert => true, property_scope => Term},
    Containers = maps:get(container, Term, []),
    ValueTerm = Term#{in_list => lists:member(<<"@list">>, Containers)},
    Values = case {maps:get(type, Term, undefined), is_map(V)} of
        {<<"@json">>, _} ->
            [#{<<"@value">> => V, <<"@type">> => <<"@json">>}];
        {_, true} ->
            case
                lists:any(
                    fun(K) ->
                        lists:member(K, Containers)
                    end,
                    [<<"@language">>, <<"@index">>, <<"@id">>, <<"@type">>]
                )
            of
                true ->
                    container_map(
                        V,
                        case lists:member(<<"@type">>, Containers) of
                            true ->
                                child(C);
                            false ->
                                C
                        end,
                        Term,
                        Depth
                    );
                false ->
                    element_value(V, Child, ValueTerm, Depth)
            end;
        _ ->
            element_value(V, Child, ValueTerm, Depth)
    end,
    Values1 =
        case
            lists:member(<<"@graph">>, Containers) andalso
                not lists:any(
                    fun(K) ->
                        lists:member(K, Containers)
                    end,
                    [<<"@id">>, <<"@index">>]
                )
        of
            true ->
                [#{<<"@graph">> => [X]} || X <- Values];
            false ->
                Values
        end,
    case lists:member(<<"@list">>, Containers) of
        true ->
            case Values1 of
                [#{<<"@list">> := _}] when is_map(V) ->
                    Values1;
                _ ->
                    [#{<<"@list">> => Values1}]
            end;
        false ->
            Values1
    end.

container_map(M, C, Term, Depth) ->
    Containers = maps:get(container, Term),
    lists:append([
        begin
            None = jsonld_context:iri(K, C, vocab) =:= <<"@none">>,
            case lists:member(<<"@language">>, Containers) of
                true ->
                    [language_value(X, K, None, C, Term) || X <- many(V), X =/= null];
                false ->
                    MapContext = case lists:member(<<"@type">>, Containers) of
                        true ->
                            type_context(#{<<"@type">> => K}, C);
                        false ->
                            C
                    end,
                    Values = element_value(V, jsonld_context:scope(Term, MapContext), Term, Depth),
                    Values1 = case lists:member(<<"@graph">>, Containers) of
                        true ->
                            [
                                case X of
                                    #{<<"@graph">> := _} ->
                                        X;
                                    _ ->
                                        #{<<"@graph">> => [X]}
                                end
                             || X <- Values
                            ];
                        false ->
                            Values
                    end,
                    [container_value(X, K, None, Containers, Term, C) || X <- Values1]
            end
        end
     || {K, V} <- lists:sort(maps:to_list(M))
    ]).

language_value(V, K, None, C, Term) ->
    check(is_binary(V), invalid_language_map_value),
    Base = scalar(V, C, Term#{language => null}),
    case None of
        true ->
            Base;
        false ->
            Base#{<<"@language">> => lower(K)}
    end.

container_value(X, _K, true, _Cs, _T, _C) ->
    X;
container_value(X, K, false, Cs, T, C) ->
    lists:foldl(
        fun
            (<<"@id">>, A) ->
                default(<<"@id">>, jsonld_context:iri(K, C, document), A);
            (<<"@type">>, A) ->
                check(not maps:is_key(<<"@value">>, A), invalid_type_map),
                A#{<<"@type">> => [jsonld_context:iri(K, C, vocab) | maps:get(<<"@type">>, A, [])]};
            (<<"@index">>, A) ->
                case maps:find(index, T) of
                    error ->
                        default(<<"@index">>, K, A);
                    {ok, Property} ->
                        check(not maps:is_key(<<"@value">>, A), invalid_index_value),
                        P = jsonld_context:iri(Property, C, vocab),
                        A#{
                            P => [
                                scalar(K, C, jsonld_context:term(Property, C)) | maps:get(P, A, [])
                            ]
                        }
                end;
            (_, A) ->
                A
        end,
        X,
        Cs
    ).

scalar(V, C, Term) ->
    Type = maps:get(type, Term, undefined),
    case Type of
        <<"@id">> when is_binary(V) ->
            #{<<"@id">> => jsonld_context:iri(V, C, document)};
        <<"@vocab">> when is_binary(V) ->
            #{<<"@id">> => type_iri(V, C)};
        _ ->
            M = #{<<"@value">> => V},
            case Type of
                T when is_binary(T), T =/= <<"@none">>, T =/= <<"@id">>, T =/= <<"@vocab">> ->
                    M#{<<"@type">> => T};
                _ when is_binary(V) ->
                    M1 = optional(<<"@language">>, fallback(language, Term, C), M),
                    optional(<<"@direction">>, fallback(direction, Term, C), M1);
                _ ->
                    check(is_number(V) orelse is_boolean(V), invalid_value),
                    M
            end
    end.

fallback(K, T, C) ->
    case maps:get(K, T, undefined) of
        undefined ->
            maps:get(K, C);
        V ->
            V
    end.

optional(_K, null, M) ->
    M;
optional(_K, undefined, M) ->
    M;
optional(K, V, M) ->
    M#{K => V}.

child(C) ->
    case maps:get(previous, C, undefined) of
        undefined ->
            C;
        Prev ->
            Prev
    end.

finish(#{<<"@value">> := V} = M) ->
    Allowed = [<<"@value">>, <<"@type">>, <<"@language">>, <<"@direction">>, <<"@index">>],
    check(
        lists:all(
            fun(K) ->
                lists:member(K, Allowed)
            end,
            maps:keys(M)
        ),
        invalid_value_object
    ),
    Type = maps:get(<<"@type">>, M, []),
    check(length(Type) =< 1, invalid_typed_value),
    check(
        not (Type =/= [] andalso
            (maps:is_key(<<"@language">>, M) orelse maps:is_key(<<"@direction">>, M))),
        invalid_value_object
    ),
    Json = Type =:= [<<"@json">>],
    check(
        Type =:= [] orelse Json orelse lists:all(fun valid_datatype/1, Type), invalid_typed_value
    ),
    check(Json orelse not (is_map(V) orelse is_list(V)), invalid_value_object),
    check(
        not maps:is_key(<<"@language">>, M) orelse is_binary(V) orelse V =:= null,
        invalid_language_tagged_value
    ),
    M1 = case Type of
        [T] ->
            M#{<<"@type">> => T};
        _ ->
            M
    end,
    case V =:= null andalso not Json of
        true ->
            [];
        false ->
            [M1]
    end;
finish(#{<<"@set">> := Values} = M) ->
    check(map_size(maps:remove(<<"@index">>, M)) =:= 1, invalid_set_object),
    Values;
finish(#{<<"@list">> := Values} = M) ->
    check(map_size(maps:remove(<<"@index">>, M)) =:= 1, invalid_list_object),
    _ = Values,
    [M];
finish(#{<<"@language">> := _} = M) when map_size(M) =:= 1 ->
    [];
finish(M) when map_size(M) =:= 0 ->
    [M];
finish(M) ->
    [M].

reverse_values(<<"@reverse">>, Ps, Acc) ->
    maps:fold(fun append/3, Acc, Ps);
reverse_values(P, Values, Acc) ->
    check(is_absolute(P), invalid_reverse_property),
    check(
        not lists:any(
            fun(X) ->
                maps:is_key(<<"@value">>, X) orelse maps:is_key(<<"@list">>, X)
            end,
            Values
        ),
        invalid_reverse_property_value
    ),
    R = maps:get(<<"@reverse">>, Acc, #{}),
    Acc#{<<"@reverse">> => append(P, Values, R)}.

append(K, Vs, M) ->
    M#{K => maps:get(K, M, []) ++ Vs}.

unique(K, V, M) ->
    check(not maps:is_key(K, M), {colliding_keywords, K}),
    M#{K => V}.

default(K, V, M) ->
    case maps:is_key(K, M) of
        true ->
            M;
        false ->
            M#{K => V}
    end.

many(V) when is_list(V) ->
    V;
many(V) ->
    [V].

lower(V) ->
    unicode:characters_to_binary(string:lowercase(unicode:characters_to_list(V))).

is_absolute(V) when is_binary(V) ->
    binary:match(V, <<":">>) =/= nomatch;
is_absolute(_) ->
    false.

check(true, _) ->
    ok;
check(false, E) ->
    fail(E).

fail(E) ->
    throw({jsonld, E}).

valid_datatype(<<"_:", _/binary>>) ->
    false;
valid_datatype(V) ->
    rdf_iri:is_absolute(V).

type_iri(V, C) ->
    case jsonld_context:iri(V, C, vocab) of
        I when is_binary(I) ->
            case is_absolute(I) of
                true ->
                    I;
                false ->
                    jsonld_context:iri(I, C, document)
            end;
        I ->
            I
    end.

element_context(Map, C) ->
    Clean = maps:without([revert, property_scope], C),
    IsValue = lists:any(
        fun(K) ->
            jsonld_context:iri(K, C, vocab) =:= <<"@value">>
        end,
        maps:keys(Map)
    ),
    IsReference =
        map_size(Map) =:= 1 andalso
            lists:any(
                fun(K) ->
                    jsonld_context:iri(K, C, vocab) =:= <<"@id">>
                end,
                maps:keys(Map)
            ),
    Base = case maps:get(revert, C, false) andalso not IsValue andalso not IsReference of
        true ->
            child(Clean);
        false ->
            Clean
    end,
    jsonld_context:scope(maps:get(property_scope, C, #{}), Base).

free_nodes(Ds) ->
    [
        D
     || D <- Ds,
        map_size(D) > 0,
        not maps:is_key(<<"@value">>, D),
        not maps:is_key(<<"@list">>, D),
        not (map_size(D) =:= 1 andalso maps:is_key(<<"@id">>, D))
    ].
