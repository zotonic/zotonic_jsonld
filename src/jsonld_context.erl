%% @copyright 2026 Marc Worrell
%% @doc JSON-LD active contexts, recursive term definitions and IRI expansion.
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

-module(jsonld_context).

-export([
    new/1,
    process/2,
    iri/3,
    term/2,
    resolve/2,
    load/2,
    scope/2
]).

new(Options) ->
    #{
        terms => #{},
        base => maps:get(base, Options, undefined),
        vocab => null,
        context_base => maps:get(base, Options, undefined),
        language => null,
        direction => null,
        options => Options,
        remote => [],
        previous => undefined
    }.

term(Key, C) ->
    maps:get(Key, maps:get(terms, C), #{}).

process(null, C) ->
    Protected = lists:any(
        fun(T) ->
            is_map(T) andalso maps:get(protected, T, false)
        end,
        maps:values(maps:get(terms, C))
    ),
    check(
        not Protected orelse maps:get(override_protected, C, false), invalid_context_nullification
    ),
    (new(maps:get(options, C)))#{
        context_base => maps:get(context_base, C),
        remote => maps:get(remote, C),
        validating_scopes => maps:get(validating_scopes, C, [])
    };
process(List, C) when is_list(List) ->
    lists:foldl(fun process/2, C, List);
process(Url, C) when is_binary(Url) ->
    Absolute = resolve(Url, maps:get(context_base, C)),
    Stack = maps:get(remote, C),
    check(not lists:member(Absolute, Stack), {recursive_context, Absolute}),
    check(length(Stack) < maps:get(max_context_depth, maps:get(options, C), 32), context_overflow),
    {Doc, Location} = load(Absolute, maps:get(options, C)),
    check(is_map(Doc) andalso maps:is_key(<<"@context">>, Doc), {invalid_remote_context, Absolute}),
    C1 = process(maps:get(<<"@context">>, Doc), C#{
        context_base => Location, remote => [Absolute | Stack]
    }),
    C1#{context_base => maps:get(context_base, C), remote => Stack};
process(Local0, C0) when is_map(Local0) ->
    Local = import(Local0, C0),
    check(maps:get(<<"@version">>, Local, 1.1) =:= 1.1, invalid_version),
    Propagate = maps:get(<<"@propagate">>, Local, true),
    check(is_boolean(Propagate), invalid_propagate),
    C1 = case Propagate of
        false ->
            C0#{previous => C0};
        true ->
            C0
    end,
    C2 = case maps:get(remote, C1) of
        [] ->
            setting(<<"@base">>, base, Local, C1);
        _ ->
            C1
    end,
    C3 = setting(<<"@vocab">>, vocab, Local, C2),
    C4 = setting(<<"@language">>, language, Local, C3),
    C5 = setting(<<"@direction">>, direction, Local, C4),
    check(is_boolean(maps:get(<<"@protected">>, Local, false)), invalid_protected),
    C6 = C5#{defined => #{}},
    C7 = lists:foldl(
        fun(K, C) ->
            case
                lists:member(K, [
                    <<"@base">>,
                    <<"@vocab">>,
                    <<"@language">>,
                    <<"@direction">>,
                    <<"@version">>,
                    <<"@propagate">>,
                    <<"@protected">>
                ])
            of
                true ->
                    C;
                false ->
                    case keyword_form(K) andalso K =/= <<"@type">> of
                        true ->
                            check(not keyword(K), {keyword_redefinition, K}),
                            C;
                        false ->
                            case ignored_definition(maps:get(K, Local)) of
                                true ->
                                    C;
                                false ->
                                    define(K, Local, C, [])
                            end
                    end
            end
        end,
        C6,
        lists:sort(maps:keys(Local))
    ),
    Finished = maps:remove(defined, C7),
    Seen = maps:get(validating_scopes, C0, []),
    check(length(Seen) =< maps:get(max_context_depth, maps:get(options, C0), 32), context_overflow),
    lists:foreach(
        fun(K) ->
            case term(K, Finished) of
                #{context := Scoped} = T ->
                    case lists:member(Scoped, Seen) of
                        true ->
                            ok;
                        false ->
                            scope(T, Finished#{validating_scopes => [Scoped | Seen]})
                    end;
                _ ->
                    ok
            end
        end,
        maps:keys(Local)
    ),
    Finished;
process(_, _) ->
    fail(invalid_context).

import(#{<<"@import">> := Url} = Local, C) when is_binary(Url) ->
    {Doc, _} = load(resolve(Url, maps:get(context_base, C)), maps:get(options, C)),
    case Doc of
        #{<<"@context">> := Imported} when is_map(Imported) ->
            check(not maps:is_key(<<"@import">>, Imported), invalid_import),
            maps:merge(Imported, maps:remove(<<"@import">>, Local));
        _ ->
            fail(invalid_import)
    end;
import(Local, _) ->
    check(not maps:is_key(<<"@import">>, Local), invalid_import),
    Local.

setting(Key, Kind, Local, C) ->
    case maps:find(Key, Local) of
        error ->
            C;
        {ok, null} ->
            C#{Kind => null};
        {ok, V} when is_binary(V) ->
            Value = case Kind of
                base ->
                    resolve(V, maps:get(base, C));
                vocab ->
                    case iri(V, C, vocab) of
                        I when is_binary(I) ->
                            case valid_mapping(I) of
                                true ->
                                    I;
                                false ->
                                    resolve(I, maps:get(base, C))
                            end;
                        I ->
                            I
                    end;
                language ->
                    lower(V);
                direction ->
                    check(V =:= <<"ltr">> orelse V =:= <<"rtl">>, invalid_direction),
                    V
            end,
            C#{Kind => Value};
        _ ->
            fail({invalid_context_setting, Key})
    end.

define(T, L, C, Trace) ->
    check(is_binary(T) andalso T =/= <<>>, invalid_term),
    case maps:get(T, maps:get(defined, C, #{}), false) of
        true ->
            C;
        false ->
            check(not lists:member(T, Trace), {cyclic_term_definition, T}),
            Raw = maps:get(T, L),
            Def = case Raw of
                null ->
                    null;
                B when is_binary(B) ->
                    #{<<"@id">> => B};
                M when is_map(M) ->
                    M;
                _ ->
                    fail({invalid_term_definition, T})
            end,
            {Term, C1} = definition(T, Def, L, C, [T | Trace]),
            Old = term(T, C),
            case is_map(Old) andalso maps:get(protected, Old, false) of
                true ->
                    check(
                        maps:get(override_protected, C, false) orelse
                            (is_map(Term) andalso
                                maps:remove(protected, Term) =:= maps:remove(protected, Old)),
                        {protected_term_redefinition, T}
                    );
                false ->
                    ok
            end,
            Terms = maps:get(terms, C1),
            Done = maps:get(defined, C1, #{}),
            Stored =
                case
                    is_map(Old) andalso maps:get(protected, Old, false) andalso
                        not maps:get(override_protected, C, false)
                of
                    true ->
                        Old;
                    false ->
                        Term
                end,
            C1#{terms => Terms#{T => Stored}, defined => Done#{T => true}}
    end.

definition(T, null, L, C, Trace) ->
    definition(T, #{<<"@id">> => null}, L, C, Trace);
definition(<<"@type">>, D, L, C, _Trace) ->
    check(
        is_map(D) andalso maps:is_key(<<"@container">>, D) andalso
            lists:all(
                fun(K) ->
                    lists:member(K, [<<"@container">>, <<"@protected">>])
                end,
                maps:keys(D)
            ),
        invalid_keyword_alias
    ),
    check(maps:get(<<"@container">>, D, <<"@set">>) =:= <<"@set">>, invalid_container),
    {
        #{
            id => <<"@type">>,
            container => [<<"@set">>],
            protected => maps:get(<<"@protected">>, D, maps:get(<<"@protected">>, L, false))
        },
        C
    };
definition(T, D, L, C0, Trace) ->
    Allowed = [
        <<"@id">>,
        <<"@reverse">>,
        <<"@type">>,
        <<"@container">>,
        <<"@context">>,
        <<"@language">>,
        <<"@direction">>,
        <<"@prefix">>,
        <<"@protected">>,
        <<"@index">>,
        <<"@nest">>
    ],
    check(
        lists:all(
            fun(K) ->
                lists:member(K, Allowed)
            end,
            maps:keys(D)
        ),
        {invalid_term_definition, T}
    ),
    Reverse = maps:is_key(<<"@reverse">>, D),
    check(not (Reverse andalso maps:is_key(<<"@id">>, D)), invalid_reverse_property),
    Value = maps:get(<<"@reverse">>, D, maps:get(<<"@id">>, D, T)),
    {Id, C1} =
        case Value of
            null ->
                {null, C0};
            T ->
                default_iri(T, L, C0, Trace);
            _ when is_binary(Value) ->
                definition_iri(Value, L, C0, Trace);
            _ ->
                fail(invalid_iri_mapping)
        end,
    check(Id =:= null orelse valid_mapping(Id), {invalid_iri_mapping, Id}),
    check(Id =/= <<"@context">>, invalid_keyword_alias),
    check(
        not Reverse orelse (is_binary(Id) andalso not keyword_form(Id)), invalid_reverse_property
    ),
    check(Id =/= <<"@type">> orelse not maps:is_key(<<"@type">>, D), invalid_keyword_alias),
    case binary:match(T, <<"/">>) of
        nomatch ->
            ok;
        _ ->
            check(Id =:= resolve(T, maps:get(base, C1)), invalid_iri_mapping)
    end,
    case binary:split(T, <<":">>) of
        [P, Suffix] when P =/= <<>> ->
            case term(P, C1) of
                #{id := Ns, prefix := true} ->
                    check(Id =:= <<Ns/binary, Suffix/binary>>, invalid_iri_mapping);
                _ ->
                    ok
            end;
        _ ->
            ok
    end,
    {Type, C2} =
        case maps:find(<<"@type">>, D) of
            error ->
                {undefined, C1};
            {ok, V} when
                V =:= <<"@id">>; V =:= <<"@vocab">>; V =:= <<"@json">>; V =:= <<"@none">>
            ->
                {V, C1};
            {ok, V} when is_binary(V) ->
                definition_iri(V, L, C1, Trace);
            _ ->
                fail(invalid_type_mapping)
        end,
    check(
        Type =:= undefined orelse
            lists:member(Type, [<<"@id">>, <<"@vocab">>, <<"@json">>, <<"@none">>]) orelse
            absolute_type(Type),
        invalid_type_mapping
    ),
    Container = lists:usort(as_list(maps:get(<<"@container">>, D, []))),
    check(
        lists:all(
            fun(K) ->
                lists:member(K, [
                    <<"@set">>,
                    <<"@list">>,
                    <<"@language">>,
                    <<"@index">>,
                    <<"@id">>,
                    <<"@type">>,
                    <<"@graph">>
                ])
            end,
            Container
        ),
        invalid_container
    ),
    Core = lists:delete(<<"@set">>, Container),
    check(
        length(Core) =< 1 orelse
            lists:member(Core, [[<<"@graph">>, <<"@id">>], [<<"@graph">>, <<"@index">>]]),
        invalid_container
    ),
    check(
        not lists:member(<<"@list">>, Container) orelse length(Container) =:= 1, invalid_container
    ),
    check(
        not Reverse orelse
            lists:all(
                fun(K) ->
                    lists:member(K, [<<"@set">>, <<"@index">>])
                end,
                Container
            ),
        invalid_reverse_property
    ),
    case maps:find(<<"@index">>, D) of
        error ->
            ok;
        {ok, Index} ->
            check(
                is_binary(Index) andalso not keyword_form(Index) andalso
                    lists:member(<<"@index">>, Container),
                invalid_index_mapping
            )
    end,
    case maps:find(<<"@nest">>, D) of
        error ->
            ok;
        {ok, Nest} ->
            check(
                not Reverse andalso is_binary(Nest) andalso
                    (not keyword_form(Nest) orelse Nest =:= <<"@nest">>),
                invalid_nest_mapping
            )
    end,
    Prefix = maps:get(<<"@prefix">>, D, prefix_default(T, Id)),
    Protected = maps:get(<<"@protected">>, D, maps:get(<<"@protected">>, L, false)),
    check(is_boolean(Prefix) andalso is_boolean(Protected), invalid_term_definition),
    check(
        not Prefix orelse
            (not keyword(Id) andalso binary:match(T, <<"/">>) =:= nomatch andalso
                binary:match(T, <<":">>) =:= nomatch),
        invalid_prefix_mapping
    ),
    Language = maps:get(<<"@language">>, D, undefined),
    Direction = maps:get(<<"@direction">>, D, undefined),
    check(
        Language =:= undefined orelse Language =:= null orelse is_binary(Language),
        invalid_language_mapping
    ),
    check(
        lists:member(Direction, [undefined, null, <<"ltr">>, <<"rtl">>]), invalid_direction_mapping
    ),
    Lang = case is_binary(Language) of
        true ->
            lower(Language);
        false ->
            Language
    end,
    EffectiveType = case Type =:= undefined andalso lists:member(<<"@type">>, Container) of
        true ->
            <<"@id">>;
        false ->
            Type
    end,
    Term = #{
        id => Id,
        type => EffectiveType,
        reverse => Reverse,
        container => Container,
        prefix => Prefix,
        protected => Protected,
        language => Lang,
        direction => Direction
    },
    Term1 = lists:foldl(
        fun({K, A}, Acc) ->
            case maps:find(K, D) of
                {ok, Extra} ->
                    Acc#{A => Extra};
                error ->
                    Acc
            end
        end,
        Term,
        [{<<"@context">>, context}, {<<"@index">>, index}, {<<"@nest">>, nest}]
    ),
    {Term1#{context_base => maps:get(context_base, C2)}, C2}.

default_iri(T, L, C, Trace) ->
    case binary:split(T, <<":">>) of
        [Prefix, _] when Prefix =/= <<>> ->
            definition_iri(T, L, C#{terms => maps:remove(T, maps:get(terms, C))}, Trace);
        _ ->
            case maps:get(vocab, C) of
                V when is_binary(V) ->
                    {<<V/binary, T/binary>>, C};
                _ ->
                    fail({invalid_iri_mapping, T})
            end
    end.

definition_iri(V, L, C0, Trace) ->
    C = case maps:is_key(V, L) andalso not lists:member(V, Trace) of
        true ->
            define(V, L, C0, Trace);
        false ->
            C0
    end,
    case binary:split(V, <<":">>) of
        [Prefix, <<"//", _/binary>>] when Prefix =/= <<>> ->
            {V, C};
        [Prefix, _] when Prefix =/= <<>> ->
            C1 = case maps:is_key(Prefix, L) of
                true ->
                    define(Prefix, L, C, Trace);
                false ->
                    C
            end,
            {iri(V, C1, vocab), C1};
        _ ->
            check(not lists:member(V, Trace), {cyclic_term_definition, V}),
            {iri(V, C, vocab), C}
    end.

iri(null, _C, _Mode) ->
    null;
iri(<<"@", _/binary>> = V, C, Mode) ->
    case keyword(V) of
        true ->
            V;
        false ->
            case keyword_form(V) of
                true ->
                    null;
                false ->
                    case term(V, C) of
                        #{id := Id} when Mode =:= vocab ->
                            Id;
                        _ ->
                            iri_1(V, C, Mode)
                    end
            end
    end;
iri(V, C, Mode) when is_binary(V) ->
    Mapping = case Mode of
        vocab ->
            term(V, C);
        _ ->
            #{}
    end,
    case Mapping of
        null ->
            null;
        #{id := Id} ->
            Id;
        _ ->
            iri_1(V, C, Mode)
    end.

iri_1(<<"_:", _/binary>> = V, _C, _Mode) ->
    V;
iri_1(V, C, Mode) ->
    case binary:split(V, <<":">>) of
        [Prefix, <<"//", _/binary>>] when Prefix =/= <<>> ->
            V;
        [Prefix, Rest] when Prefix =/= <<>> ->
            case term(Prefix, C) of
                #{id := Ns, prefix := true} when is_binary(Ns) ->
                    <<Ns/binary, Rest/binary>>;
                _ ->
                    case absolute_type(V) of
                        true ->
                            V;
                        false ->
                            relative_iri(V, C, Mode)
                    end
            end;
        _ ->
            relative_iri(V, C, Mode)
    end.

relative_iri(V, C, Mode) ->
    case {Mode, maps:get(vocab, C)} of
        {vocab, Ns} when is_binary(Ns) ->
            <<Ns/binary, V/binary>>;
        {vocab, _} ->
            V;
        _ ->
            resolve(V, maps:get(base, C))
    end.

resolve(V, undefined) ->
    V;
resolve(V, null) ->
    V;
resolve(V, Base) ->
    rdf_iri:resolve(V, Base).

valid_mapping(<<"@", _/binary>> = V) ->
    keyword(V);
valid_mapping(V) when is_binary(V) ->
    binary:match(V, <<":">>) =/= nomatch;
valid_mapping(_) ->
    false.

prefix_default(T, <<"_:", _/binary>>) ->
    binary:match(T, <<":">>) =:= nomatch;
prefix_default(T, Id) when is_binary(Id), byte_size(Id) > 0 ->
    binary:match(T, <<":">>) =:= nomatch andalso lists:member(binary:last(Id), ":/#?[]@");
prefix_default(_, _) ->
    false.

lower(V) ->
    unicode:characters_to_binary(string:lowercase(unicode:characters_to_list(V))).

as_list(L) when is_list(L) ->
    L;
as_list(V) ->
    [V].

check(true, _) ->
    ok;
check(false, E) ->
    fail(E).

fail(E) ->
    throw({jsonld, E}).

load(Url, Options) ->
    Contexts = maps:get(contexts, Options, #{}),
    Result = case maps:find(Url, Contexts) of
        {ok, Cached} ->
            {ok, Cached};
        error ->
            load_external(Url, Options)
    end,
    case Result of
        {ok, #{document := D, document_url := Location}} ->
            {decode(D), Location};
        {ok, D} ->
            {decode(D), Url};
        {error, E} ->
            fail({loading_context_failed, Url, E});
        _ ->
            fail({invalid_loader_result, Url})
    end.

%% Supplied context documents need no I/O. All external loaders, including
%% application callbacks, require an explicit opt-in at this common boundary.

load_external(Url, #{allow_external_contexts := true} = Options) ->
    Loader = maps:get(document_loader, Options, fun jsonld_loader:load/1),
    Loader(Url);
load_external(Url, _Options) ->
    fail({external_context_loading_disabled, Url}).

decode(B) when is_binary(B) ->
    jsonld_json:decode(B);
decode(D) ->
    D.

%% Property-scoped contexts may override protected terms, without changing
%% protection rules for contexts subsequently supplied by the document.

scope(#{context := Local} = Term, C) ->
    Result = process(Local, C#{
        remote => [],
        override_protected => true,
        context_base => maps:get(context_base, Term, maps:get(context_base, C))
    }),
    Result#{override_protected => false};
scope(_, C) ->
    C.

absolute_type(<<"_:", _/binary>>) ->
    false;
absolute_type(V) when is_binary(V) ->
    rdf_iri:is_absolute(V);
absolute_type(_) ->
    false.

keyword_form(V) when is_binary(V) ->
    re:run(V, <<"^@[A-Za-z]+$">>, [{capture, none}]) =:= match;
keyword_form(_) ->
    false.

keyword(V) ->
    lists:member(V, [
        <<"@base">>,
        <<"@container">>,
        <<"@context">>,
        <<"@direction">>,
        <<"@graph">>,
        <<"@id">>,
        <<"@import">>,
        <<"@included">>,
        <<"@index">>,
        <<"@json">>,
        <<"@language">>,
        <<"@list">>,
        <<"@nest">>,
        <<"@none">>,
        <<"@prefix">>,
        <<"@propagate">>,
        <<"@protected">>,
        <<"@reverse">>,
        <<"@set">>,
        <<"@type">>,
        <<"@value">>,
        <<"@version">>,
        <<"@vocab">>
    ]).

ignored_definition(B) when is_binary(B) ->
    keyword_form(B) andalso not keyword(B);
ignored_definition(M) when is_map(M) ->
    ignored_definition(maps:get(<<"@id">>, M, maps:get(<<"@reverse">>, M, null)));
ignored_definition(_) ->
    false.
