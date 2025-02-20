%%% -*- erlang-indent-level:4; indent-tabs-mode: nil -*-
%%%-------------------------------------------------------------------
%%% @copyright (C) 2017, Aeternity Anstalt
%%% @doc Pretty printer for Sophia.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(aeso_pretty).

-import(prettypr, [text/1, sep/1, above/2, beside/2, nest/2, empty/0]).

-export([decls/1, decls/2, decl/1, decl/2, expr/1, expr/2, type/1, type/2]).

-export_type([options/0]).

-include("aeso_utils.hrl").

-type doc() :: prettypr:document().
-type options() :: [{indent, non_neg_integer()} | show_generated].

%% More options:
%%  Newline before open curly
%%  Space before ':'

%% -- Options ----------------------------------------------------------------

-define(aeso_pretty_opts, aeso_pretty_opts).

-spec options() -> options().
options() ->
    case get(?aeso_pretty_opts) of
        undefined -> [];
        Opts      -> Opts
    end.

-spec option(atom(), any()) -> any().
option(Key, Default) ->
    proplists:get_value(Key, options(), Default).

-spec show_generated() -> boolean().
show_generated() -> option(show_generated, false).

-spec indent() -> non_neg_integer().
indent() -> option(indent, 2).

-spec with_options(options(), fun(() -> A)) -> A.
with_options(Options, Fun) ->
    put(?aeso_pretty_opts, Options),
    Res = Fun(),
    erase(?aeso_pretty_opts),
    Res.

%% -- Pretty printing helpers ------------------------------------------------

-spec par([doc()]) -> doc().
par(Ds) -> par(Ds, indent()).

-spec par([doc()], non_neg_integer()) -> doc().
par([], _) -> empty();
par(Ds, N) -> prettypr:par(Ds, N).

-spec follow(doc(), doc(), non_neg_integer()) -> doc().
follow(A, B, N) ->
    sep([A, nest(N, B)]).

-spec follow(doc(), doc()) -> doc().
follow(A, B) -> follow(A, B, indent()).

-spec above([doc()]) -> doc().
above([])       -> empty();
above([D])      -> D;
above([D | Ds]) -> lists:foldl(fun(X, Y) -> above(Y, X) end, D, Ds).

-spec beside([doc()]) -> doc().
beside([])       -> empty();
beside([D])      -> D;
beside([D | Ds]) -> lists:foldl(fun(X, Y) -> beside(Y, X) end, D, Ds).

-spec hsep([doc()]) -> doc().
hsep(Ds) -> beside(punctuate(text(" "), [ D || D <- Ds, D /= empty() ])).

-spec hsep(doc(), doc()) -> doc().
hsep(D1, D2) -> hsep([D1, D2]).

-spec punctuate(doc(), [doc()]) -> [doc()].
punctuate(_Sep, [])      -> [];
punctuate(_Sep, [D])     -> [D];
punctuate(Sep, [D | Ds]) -> [beside(D, Sep) | punctuate(Sep, Ds)].

-spec paren(doc()) -> doc().
paren(D) -> beside([text("("), D, text(")")]).

-spec paren(boolean(), doc()) -> doc().
paren(false, D) -> D;
paren(true,  D) -> paren(D).

-spec indent(doc()) -> doc().
indent(D) -> nest(indent(), D).

%% block(Header, Body) ->
%%  Header
%%      Body
-spec block(doc(), doc()) -> doc().
block(Header, Body) ->
    sep([ Header, indent(Body) ]).

-spec comma_brackets(string(), string(), [doc()]) -> doc().
comma_brackets(Open, Close, Ds) ->
    beside([text(Open), par(punctuate(text(","), Ds), 0), text(Close)]).

-spec tuple([doc()]) -> doc().
tuple(Ds) ->
    comma_brackets("(", ")", Ds).

-spec list([doc()]) -> doc().
list(Ds) ->
    comma_brackets("[", "]", Ds).

-spec record([doc()]) -> doc().
record(Ds) ->
    comma_brackets("{", "}", Ds).

%% equals(A, B) -> A = B
-spec equals(doc(), doc()) -> doc().
equals(A, B) -> follow(hsep(A, text("=")), B).

%% typed(A, B) -> A : B.
-spec typed(doc(), aeso_syntax:type()) -> doc().
typed(A, Type) ->
    case aeso_syntax:get_ann(origin, Type) == system andalso
         not show_generated() of
        true  -> A;
        false -> follow(hsep(A, text(":")), type(Type))
    end.

contract_head(contract_main)      -> text("main contract");
contract_head(contract_child)     -> text("contract");
contract_head(contract_interface) -> text("contract interface").

%% -- Exports ----------------------------------------------------------------

-spec decls([aeso_syntax:decl()], options()) -> doc().
decls(Ds, Options) ->
    with_options(Options, fun() -> decls(Ds) end).

-spec decls([aeso_syntax:decl()]) -> doc().
decls(Ds) -> above([ decl(D) || D <- Ds ]).

-spec decl(aeso_syntax:decl(), options()) -> doc().
decl(D, Options) ->
    with_options(Options, fun() -> decl(D) end).

-spec decl(aeso_syntax:decl()) -> doc().
decl({Con, Attrs, C, Is, Ds}) when ?IS_CONTRACT_HEAD(Con) ->
    Mod = fun({Mod, true}) when Mod == payable ->
                  text(atom_to_list(Mod));
             (_) -> empty() end,
    ImplsList = case Is of
                    [] -> [empty()];
                    _  -> [text(":"), par(punctuate(text(","), lists:map(fun name/1, Is)), 0)]
                end,
    block(follow( hsep(lists:map(Mod, Attrs) ++ [contract_head(Con)])
                , hsep([name(C)] ++ ImplsList ++ [text("=")])), decls(Ds));
decl({namespace, _, C, Ds}) ->
    block(follow(text("namespace"), hsep(name(C), text("="))), decls(Ds));
decl({pragma, _, Pragma}) -> pragma(Pragma);
decl({type_decl, _, T, Vars}) -> typedecl(alias_t, T, Vars);
decl({type_def, _, T, Vars, Def}) ->
    Kind = element(1, Def),
    equals(typedecl(Kind, T, Vars), typedef(Def));
decl({fun_decl, Ann, F, T}) ->
    Mod = fun({Mod, true}) when Mod == private; Mod == stateful; Mod == payable ->
                  text(atom_to_list(Mod));
             (_) -> empty() end,
    Fun = case aeso_syntax:get_ann(entrypoint, Ann, false) of
            true  -> text("entrypoint");
            false -> text("function")
          end,
    hsep(lists:map(Mod, Ann) ++ [Fun, typed(name(F), T)]);
decl(D = {letfun, Attrs, _, _, _, _}) ->
    Mod = fun({Mod, true}) when Mod == private; Mod == stateful; Mod == payable ->
                            text(atom_to_list(Mod));
             (_) -> empty() end,
    Fun = case aeso_syntax:get_ann(entrypoint, Attrs, false) of
              true  -> "entrypoint";
              false -> "function"
          end,
    hsep(lists:map(Mod, Attrs) ++ [letdecl(Fun, D)]);
decl({fun_clauses, Ann, Name, Type, Clauses}) ->
    above([ decl(D) || D <- [{fun_decl, Ann, Name, Type} | Clauses] ]);
decl(D = {letval, _, _, _}) -> letdecl("let", D);
decl({block, _, Ds}) ->
    above([ decl(D) || D <- Ds ]).

-spec pragma(aeso_syntax:pragma()) -> doc().
pragma({compiler, Op, Ver}) ->
    text("@compiler " ++ atom_to_list(Op) ++ " " ++ string:join([integer_to_list(N) || N <- Ver], ".")).

-spec expr(aeso_syntax:expr(), options()) -> doc().
expr(E, Options) ->
    with_options(Options, fun() -> expr(E) end).

-spec expr(aeso_syntax:expr()) -> doc().
expr(E) -> expr_p(0, E).

%% -- Not exported -----------------------------------------------------------

-spec name(aeso_syntax:id() | aeso_syntax:qid() | aeso_syntax:con() | aeso_syntax:qcon() | aeso_syntax:tvar()) -> doc().
name({id, _,   Name})  -> text(Name);
name({con, _,  Name})  -> text(Name);
name({qid, _,  Names}) -> text(string:join(Names, "."));
name({qcon, _, Names}) -> text(string:join(Names, "."));
name({tvar, _, Name})  -> text(Name);
name({typed, _, Name, _}) -> name(Name).

-spec letdecl(string(), aeso_syntax:letbind()) -> doc().
letdecl(Let, {letval, _, P, E}) ->
    block_expr(0, hsep([text(Let), expr(P), text("=")]), E);
letdecl(Let, {letfun, _, F, Args, T, [GuardedBody]}) ->
    beside(hsep([text(Let), typed(beside(name(F), expr({tuple, [], Args})), T)]), guarded_body(GuardedBody, "="));
letdecl(Let, {letfun, _, F, Args, T, GuardedBodies}) ->
    block(hsep([text(Let), typed(beside(name(F), expr({tuple, [], Args})), T)]), above(lists:map(fun(GB) -> guarded_body(GB, "=") end, GuardedBodies))).

-spec args([aeso_syntax:arg()]) -> doc().
args(Args) ->
    tuple(lists:map(fun arg/1, Args)).

-spec arg(aeso_syntax:arg()) -> doc().
arg({arg, _, X, T}) -> typed(name(X), T).

-spec typedecl(alias_t | record_t | variant_t, aeso_syntax:id(), [aeso_syntax:tvar()]) -> doc().
typedecl(Kind, T, Vars) ->
    KW = case Kind of
            alias_t -> text("type");
            record_t -> text("record");
            variant_t -> text("datatype")
         end,
    case Vars of
        [] -> hsep(KW, name(T));
        _  -> beside(hsep(KW, name(T)),
                tuple(lists:map(fun name/1, Vars)))
    end.

-spec typedef(aeso_syntax:typedef()) -> doc().
typedef({alias_t, Type})           -> type(Type);
typedef({record_t, Fields})        ->
    record(lists:map(fun field_t/1, Fields));
typedef({variant_t, Constructors}) ->
    par(punctuate(text(" |"), lists:map(fun constructor_t/1, Constructors))).

-spec constructor_t(aeso_syntax:constructor_t()) -> doc().
constructor_t({constr_t, _, C, []}) -> name(C);
constructor_t({constr_t, _, C, Args}) -> beside(name(C), args_type(Args)).

-spec field_t(aeso_syntax:field_t()) -> doc().
field_t({field_t, _, Name, Type}) ->
    typed(name(Name), Type).

-spec type(aeso_syntax:type(), options()) -> doc().
type(Type, Options) ->
    with_options(Options, fun() -> type(Type) end).

-spec type(aeso_syntax:type()) -> doc().
type({fun_t, _, Named, Args, Ret}) ->
    follow(hsep(args_type(Named ++ Args), text("=>")), type(Ret));
type({type_sig, _, Named, Args, Ret}) ->
    follow(hsep(tuple_type(Named ++ Args), text("=>")), type(Ret));
type({app_t, _, Type, []}) ->
    type(Type);
type({app_t, _, Type, Args}) ->
    beside(type(Type), args_type(Args));
type({tuple_t, _, Args}) ->
    tuple_type(Args);
type({args_t, _, Args}) ->
    args_type(Args);
type({bytes_t, _, any}) -> text("bytes(_)");
type({bytes_t, _, Len}) ->
    text(lists:concat(["bytes(", Len, ")"]));
type({if_t, _, Id, Then, Else}) ->
    beside(text("if"), args_type([Id, Then, Else]));
type({named_arg_t, _, Name, Type, _Default}) ->
    %% Drop the default value
    %% follow(hsep(typed(name(Name), Type), text("=")), expr(Default));
    typed(name(Name), Type);

type(R = {record_t, _}) -> typedef(R);
type(T = {id, _, _})   -> name(T);
type(T = {qid, _, _})  -> name(T);
type(T = {con, _, _})  -> name(T);
type(T = {qcon, _, _}) -> name(T);
type(T = {tvar, _, _}) -> name(T).

-spec args_type([aeso_syntax:type()]) -> doc().
args_type(Args) ->
    tuple(lists:map(fun type/1, Args)).

-spec tuple_type([aeso_syntax:type()]) -> doc().
tuple_type([]) ->
    text("unit");
tuple_type(Factors) ->
    beside(
      [ text("(")
      , par(punctuate(text(" *"), lists:map(fun type/1, Factors)), 0)
      , text(")")
      ]).

-spec expr_p(integer(), aeso_syntax:arg_expr()) -> doc().
expr_p(P, {letpat, _, Id, Pat}) ->
    paren(P > 100, follow(hsep(expr(Id), text("=")), expr(Pat)));
expr_p(P, {named_arg, _, Name, E}) ->
    paren(P > 100, follow(hsep(expr(Name), text("=")), expr(E)));
expr_p(P, {lam, _, Args, E}) ->
    paren(P > 100, follow(hsep(args(Args), text("=>")), expr_p(100, E)));
expr_p(P, If = {'if', Ann, Cond, Then, Else}) ->
    Format   = aeso_syntax:get_ann(format, If),
    if  Format == '?:' ->
            paren(P > 100,
                follow(expr_p(200, Cond),
                follow(hsep(text("?"), expr_p(100, Then)),
                   hsep(text(":"), expr_p(100, Else)), 0)));
        true ->
            {Elifs, Else1} = get_elifs(Else),
            above([ stmt_p(Stmt) || Stmt <- [{'if', Ann, Cond, Then} | Elifs] ++ [Else1]])
    end;
expr_p(_P, {switch, _, E, Cases}) ->
    block(beside(text("switch"), paren(expr(E))),
          above(lists:map(fun alt/1, Cases)));
expr_p(_, {tuple, _, Es}) ->
    tuple(lists:map(fun expr/1, Es));
expr_p(_, {list, _, Es}) ->
    list(lists:map(fun expr/1, Es));
expr_p(_, {list_comp, _, E, Binds}) ->
    list([follow(expr(E), hsep(text("|"), par(punctuate(text(","), lists:map(fun lc_bind/1, Binds)), 0)), 0)]);
expr_p(_, {record, _, Fs}) ->
    record(lists:map(fun field/1, Fs));
expr_p(_, {map, Ann, KVs}) ->
    record([ field({field, Ann, [{map_get, [], K}], V}) || {K, V} <- KVs ]);
expr_p(P, {map, Ann, E, Flds}) ->
    expr_p(P, {record, Ann, E, Flds});
expr_p(P, {record, Ann, E, Fs}) ->
    paren(P > 900, hsep(expr_p(900, E), expr({record, Ann, Fs})));
expr_p(_, {block, _, Ss}) ->
    block(empty(), statements(Ss));
expr_p(P, {proj, _, E, X}) ->
    paren(P > 900, beside([expr_p(900, E), text("."), name(X)]));
expr_p(P, {map_get, _, E, Key}) ->
    paren(P > 900, beside([expr_p(900, E), list([expr(Key)])]));
expr_p(P, {map_get, Ann, E, Key, Val}) ->
    paren(P > 900, beside([expr_p(900, E), list([expr(equals(Ann, Key, Val))])]));
expr_p(P, {typed, _, E, T}) ->
    paren(P > 0, typed(expr(E), T));
expr_p(P, {assign, _, LV, E}) ->
    paren(P > 0, equals(expr_p(900, LV), expr(E)));
%% -- Operators
expr_p(_, {app, _, {'..', _}, [A, B]}) ->
    list([infix(0, '..', A, B)]);
expr_p(P, E = {app, _, F = {Op, _}, Args}) when is_atom(Op) ->
    case {aeso_syntax:get_ann(format, E), Args} of
        {infix, [A, B]} -> infix(P, Op, A, B);
        {prefix, [A]}   -> prefix(P, Op, A);
        _               -> app(P, F, Args)
    end;
expr_p(_, {app, _, C={Tag, _, _}, []}) when Tag == con; Tag == qcon ->
    expr_p(0, C);
expr_p(P, {app, _, F, Args}) ->
    app(P, F, Args);
%% -- Constants
expr_p(_, E = {int, _, N}) ->
    S = case aeso_syntax:get_ann(format, E) of
            hex -> "0x" ++ integer_to_list(N, 16);
            _   -> integer_to_list(N)
           end,
    text(S);
expr_p(_, {bool, _, B}) -> text(atom_to_list(B));
expr_p(_, {bytes, _, Bin}) ->
    Digits = byte_size(Bin),
    <<N:Digits/unit:8>> = Bin,
    text(lists:flatten(io_lib:format("#~*.16.0b", [Digits*2, N])));
expr_p(_, {hash, _, <<N:512>>}) -> text("#" ++ integer_to_list(N, 16));
expr_p(_, {Type, _, Bin})
    when Type == account_pubkey;
         Type == contract_pubkey;
         Type == oracle_pubkey;
         Type == oracle_query_id ->
    text(binary_to_list(aeser_api_encoder:encode(Type, Bin)));
expr_p(_, {string, _, <<>>}) -> text("\"\"");
expr_p(_, {string, _, S}) ->
    text(io_lib:format("\"~s\"", [binary_to_list(S)]));
expr_p(_, {char, _, C}) ->
    case C of
        $' -> text("'\\''");
        $" -> text("'\"'");
        _ when C < 16#80 ->
            S = lists:flatten(io_lib:format("~p", [[C]])),
            text("'" ++ tl(lists:droplast(S)) ++ "'");
        _  ->
            S = lists:flatten(
                  io_lib:format("'~ts'", [list_to_binary(aeso_scan:utf8_encode([C]))])),
            text(S)
    end;
%% -- Names
expr_p(_, E = {id, _, _})   -> name(E);
expr_p(_, E = {con, _, _})  -> name(E);
expr_p(_, E = {qid, _, _})  -> name(E);
expr_p(_, E = {qcon, _, _}) -> name(E);
%% -- For error messages
expr_p(_, {Op, _}) when is_atom(Op) ->
    paren(text(atom_to_list(Op)));
expr_p(_, {lvalue, _, LV})  -> lvalue(LV).

stmt_p({'if', _, Cond, Then}) ->
    block_expr(200, beside(text("if"), paren(expr(Cond))), Then);
stmt_p({elif, _, Cond, Then}) ->
    block_expr(200, beside(text("elif"), paren(expr(Cond))), Then);
stmt_p({else, Else}) ->
    HideGenerated = not show_generated(),
    case aeso_syntax:get_ann(origin, Else) of
        system when HideGenerated -> empty();
        _ -> block_expr(200, text("else"), Else)
    end.

lc_bind({comprehension_bind, P, E}) ->
    follow(hsep(expr(P), text("<-")), expr(E));
lc_bind({comprehension_if, _, E}) ->
    beside([text("if("), expr(E), text(")")]);
lc_bind(Let) ->
    letdecl("let", Let).

-spec bin_prec(aeso_syntax:bin_op()) -> {integer(), integer(), integer()}.
bin_prec('..')   -> {  0,   0,   0};  %% Always printed inside '[ ]'
bin_prec('=')    -> {  0,   0,   0};  %% Always printed inside '[ ]'
bin_prec('@')    -> {  0,   0,   0};  %% Only in error messages
bin_prec('||')   -> {200, 300, 200};
bin_prec('&&')   -> {300, 400, 300};
bin_prec('<')    -> {400, 500, 500};
bin_prec('>')    -> {400, 500, 500};
bin_prec('=<')   -> {400, 500, 500};
bin_prec('>=')   -> {400, 500, 500};
bin_prec('==')   -> {400, 500, 500};
bin_prec('!=')   -> {400, 500, 500};
bin_prec('++')   -> {500, 600, 500};
bin_prec('::')   -> {500, 600, 500};
bin_prec('+')    -> {600, 600, 650};
bin_prec('-')    -> {600, 600, 650};
bin_prec('*')    -> {700, 700, 750};
bin_prec('/')    -> {700, 700, 750};
bin_prec(mod)    -> {700, 700, 750};
bin_prec('^')    -> {750, 750, 800}.

-spec un_prec(aeso_syntax:un_op()) -> {integer(), integer()}.
un_prec('-')    -> {650, 650};
un_prec('!')    -> {800, 800}.

equals(Ann, A, B) ->
    {app, [{format, infix} | Ann], {'=', Ann}, [A, B]}.

-spec infix(integer(), aeso_syntax:bin_op(), aeso_syntax:expr(), aeso_syntax:expr()) -> doc().
infix(P, Op, A, B) ->
    {Top, L, R} = bin_prec(Op),
    paren(P > Top,
        follow(hsep(expr_p(L, A), text(atom_to_list(Op))),
               expr_p(R, B))).

prefix(P, Op, A) ->
    {Top, Inner} = un_prec(Op),
    paren(P > Top, hsep(text(atom_to_list(Op)), expr_p(Inner, A))).

app(P, F, Args) ->
    paren(P > 900,
    beside(expr_p(900, F),
           tuple(lists:map(fun expr/1, Args)))).

field({field, _, LV, E}) ->
    follow(hsep(lvalue(LV), text("=")), expr(E));
field({field, _, LV, Id, E}) ->
    follow(hsep([lvalue(LV), text("@"), name(Id), text("=")]), expr(E));
field({field_upd, _, LV, Fun}) ->
    follow(hsep(lvalue(LV), text("~")), expr(Fun)). %% Not valid syntax

lvalue([E | Es]) ->
    beside([elim(E) | lists:map(fun elim1/1, Es)]).

elim({proj, _, X})         -> name(X);
elim({map_get, Ann, K})    -> expr_p(0, {list, Ann, [K]});
elim({map_get, Ann, K, V}) -> expr_p(0, {list, Ann, [equals(Ann, K, V)]}).

elim1(Proj={proj, _, _})      -> beside(text("."), elim(Proj));
elim1(Get={map_get, _, _})    -> elim(Get);
elim1(Get={map_get, _, _, _}) -> elim(Get).

alt({'case', _, Pat, [GuardedBody]}) ->
    beside(expr(Pat), guarded_body(GuardedBody, "=>"));
alt({'case', _, Pat, GuardedBodies}) ->
    block(expr(Pat), above(lists:map(fun(GB) -> guarded_body(GB, "=>") end, GuardedBodies))).

guarded_body({guarded, _, Guards, Body}, Then) ->
    block_expr(0, hsep(guards(Guards), text(Then)), Body).

guards([]) ->
    text("");
guards(Guards) ->
    hsep([text(" |"), par(punctuate(text(","), lists:map(fun expr/1, Guards)), 0)]).

block_expr(_, Header, {block, _, Ss}) ->
    block(Header, statements(Ss));
block_expr(P, Header, E) ->
    follow(Header, expr_p(P, E)).

statements(Stmts) ->
    above([ statement(S) || S <- Stmts ]).

statement(S = {letval, _, _, _})       -> letdecl("let", S);
statement(S = {letfun, _, _, _, _, _}) -> letdecl("let", S);
statement(E) -> expr(E).

get_elifs(Expr) -> get_elifs(Expr, []).

get_elifs(If = {'if', Ann, Cond, Then, Else}, Elifs) ->
    case aeso_syntax:get_ann(format, If) of
        elif -> get_elifs(Else, [{elif, Ann, Cond, Then} | Elifs]);
        _    -> {lists:reverse(Elifs), If}
    end;
get_elifs(Else, Elifs) -> {lists:reverse(Elifs), {else, Else}}.

