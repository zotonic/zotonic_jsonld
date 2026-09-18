%% @copyright 2026 Marc Worrell
%% @doc JSON-LD preserves lexical strings and arbitrary JSON objects.
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

-module(jsonld_json).

-export([
    decode/1,
    encode/2
]).

decode(Binary) ->
    try
        jsxrecord:decode(Binary, #{codecs => [], records => false, null => null})
    catch
        error:Reason ->
            throw({jsonld, {invalid_json, Reason}})
    end.

encode(Value, Options) ->
    Binary = jsxrecord:encode(Value),
    case maps:get(pretty, Options, false) of
        true ->
            euneus:format(Binary, #{
                indent_type => spaces, indent_width => 2, spaced_values => true, crlf => n
            });
        false ->
            Binary
    end.
