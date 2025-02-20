%%%-------------------------------------------------------------------
%%% @author Ulf Norell
%%% @copyright (C) 2019, Aeternity Anstalt
%%% @doc
%%%     Formatting of code generation errors.
%%% @end
%%%
%%%-------------------------------------------------------------------
-module(aeso_code_errors).

-export([format/1, pos/1]).

format({last_declaration_must_be_main_contract, Decl = {Kind, _, {con, _, C}, _}}) ->
    Msg = io_lib:format("Expected a main contract as the last declaration instead of the ~p '~s'",
                        [Kind, C]),
    mk_err(pos(Decl), Msg);
format({missing_init_function, Con}) ->
    Msg = io_lib:format("Missing init function for the contract '~s'.", [pp_expr(Con)]),
    Cxt = "The 'init' function can only be omitted if the state type is 'unit'.",
    mk_err(pos(Con), Msg, Cxt);
format({missing_definition, Id}) ->
    Msg = io_lib:format("Missing definition of function '~s'.", [pp_expr(Id)]),
    mk_err(pos(Id), Msg);
format({parameterized_state, Decl}) ->
    Msg = "The state type cannot be parameterized.",
    mk_err(pos(Decl), Msg);
format({parameterized_event, Decl}) ->
    Msg = "The event type cannot be parameterized.",
    mk_err(pos(Decl), Msg);
format({invalid_entrypoint, Why, Ann, {id, _, Name}, Thing}) ->
    What = case Why of higher_order -> "higher-order (contains function types)";
                       polymorphic  -> "polymorphic (contains type variables)" end,
    ThingS = case Thing of
                 {argument, X, T} -> io_lib:format("argument\n~s\n", [pp_typed(X, T)]);
                 {result, T}      -> io_lib:format("return type\n~s\n", [pp_type(2, T)])
             end,
    Bad = case Thing of
              {argument, _, _} -> io_lib:format("has a ~s type", [What]);
              {result, _}      -> io_lib:format("is ~s", [What])
          end,
    Msg = io_lib:format("The ~sof entrypoint '~s' ~s.",
                        [ThingS, Name, Bad]),
    case Why of
        higher_order -> mk_err(pos(Ann), Msg)
    end;
format({invalid_aens_resolve_type, Ann, T}) ->
    Msg = io_lib:format("Invalid return type of AENS.resolve:\n"
                        "~s\n"
                        "It must be a string or a pubkey type (address, oracle, etc).",
                        [pp_type(2, T)]),
    mk_err(pos(Ann), Msg);
format({invalid_oracle_type, Why, What, Ann, Type}) ->
    WhyS = case Why of higher_order -> "higher-order (contain function types)";
                       polymorphic  -> "polymorphic (contain type variables)" end,
    Msg = io_lib:format("Invalid oracle type\n~s", [pp_type(2, Type)]),
    Cxt = io_lib:format("The ~s type must not be ~s.", [What, WhyS]),
    mk_err(pos(Ann), Msg, Cxt);
format({var_args_not_set, Expr}) ->
    mk_err( pos(Expr), "Could not deduce type of variable arguments list"
          , "When compiling " ++ pp_expr(Expr)
          );
format({found_void, Ann}) ->
    mk_err(pos(Ann), "Found a void-typed value.", "`void` is a restricted, uninhabited type. Did you mean `unit`?");

format(Err) ->
    mk_err(aeso_errors:pos(0, 0), io_lib:format("Unknown error: ~p\n", [Err])).

pos(Ann) ->
    File = aeso_syntax:get_ann(file, Ann, no_file),
    Line = aeso_syntax:get_ann(line, Ann, 0),
    Col  = aeso_syntax:get_ann(col, Ann, 0),
    aeso_errors:pos(File, Line, Col).

pp_typed(E, T) ->
    prettypr:format(prettypr:nest(2,
    lists:foldr(fun prettypr:beside/2, prettypr:empty(),
                [aeso_pretty:expr(E), prettypr:text(" : "),
                 aeso_pretty:type(T)]))).

pp_expr(E) ->
    pp_expr(0, E).

pp_expr(N, E) ->
    prettypr:format(prettypr:nest(N, aeso_pretty:expr(E))).

pp_type(N, T) ->
    prettypr:format(prettypr:nest(N, aeso_pretty:type(T))).

mk_err(Pos, Msg) ->
    aeso_errors:new(code_error, Pos, lists:flatten(Msg)).

mk_err(Pos, Msg, Cxt) ->
    aeso_errors:new(code_error, Pos, lists:flatten(Msg), lists:flatten(Cxt)).

