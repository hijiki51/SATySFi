{
  open Types
  open Parser

  exception LexError of Range.t * string

  (*
   * The SATySFi lexer is stateful; the transitions are:
   * | to \ from |program|block |inline|active |  math  |
   * |-----------|-------|------|------|-------|--------|
   * |  program  | (   ) |      |      | (   ) | !(   ) |
   * |           | (| |) |      |      | (| |) | !(| |) |
   * |           | [   ] |      |      | [   ] | ![   ] |
   * |  block    | '<  > | <  > | <  > | <     | !<   > |
   * |  inline   | {   } | {  } | {  } | {     | !{   } |
   * |  active   |       | +x ; | \x ; |       |        |
   * |           |       | #x ; | #x ; |       |        |
   * |  math     | ${  } |      | ${ } |       | {    } |
   *
   * Note that the active-block and active-inline transitions are one-way.
   *)

  type lexer_state =
    | ProgramState    (* program mode *)
    | VerticalState   (* block mode *)
    | HorizontalState (* inline mode *)
    | ActiveState     (* active mode *)
    | MathState       (* math mode *)


  let get_pos (lexbuf : Lexing.lexbuf) : Range.t =
    let posS = Lexing.lexeme_start_p lexbuf in
    let posE = Lexing.lexeme_end_p lexbuf in
    let fname = posS.Lexing.pos_fname in
    let lnum = posS.Lexing.pos_lnum in
    let cnumS = posS.Lexing.pos_cnum - posS.Lexing.pos_bol in
    let cnumE = posE.Lexing.pos_cnum - posE.Lexing.pos_bol in
    Range.make fname lnum cnumS cnumE


  let report_error lexbuf errmsg =
    let rng = get_pos lexbuf in
    raise (LexError(rng, errmsg))


  let pop lexbuf errmsg stack =
    if Stack.length stack > 1 then
      Stack.pop stack |> ignore
    else
      report_error lexbuf errmsg


  let increment_line (lexbuf : Lexing.lexbuf) : unit =
    Lexing.new_line lexbuf


  let adjust_bol (lexbuf : Lexing.lexbuf) (amt : int) : unit =
    let open Lexing in
    let lcp = lexbuf.lex_curr_p in
    lexbuf.lex_curr_p <- { lcp with pos_bol = lcp.pos_cnum + amt; }


  let rec increment_line_for_each_break (lexbuf : Lexing.lexbuf) (str : string) : unit =
    let len = String.length str in
    let rec aux num has_break tail_spaces prev =
      if num >= len then
        (has_break, tail_spaces)
      else
        match (prev, String.get str num) with
        | (Some('\r'), '\n') ->
            aux (num + 1) has_break (tail_spaces + 1) (Some('\n'))

        | (_, (('\n' | '\r') as c)) ->
            increment_line lexbuf;
            aux (num + 1) true 0 (Some(c))

        | _ ->
            aux (num + 1) has_break (tail_spaces + 1) None
    in
    let (has_break, amt) = aux 0 false 0 None in
    if has_break then
      adjust_bol lexbuf (-amt)
    else
      ()


  let initialize state =
    let stack = Stack.create () in
    Stack.push state stack;
    stack


  let reset_to_progexpr () =
    initialize ProgramState


  let reset_to_vertexpr () =
    initialize VerticalState


  let split_module_list (s : string) : module_name list * var_name =
    let ss = String.split_on_char '.' s in
    match List.rev ss with
    | varnm :: modnms_rev -> (List.rev modnms_rev, varnm)
    | []                  -> assert false

}

let space = [' ' '\t']
let break = ('\r' '\n' | '\n' | '\r')
let nonbreak = [^ '\n' '\r']
let nzdigit = ['1'-'9']
let digit = (nzdigit | "0")
let hex   = (digit | ['A'-'F'])
let capital = ['A'-'Z']
let small = ['a'-'z']
let latin = (small | capital)
let item  = "*"+
let lower = (small (digit | latin | "-")*)
let upper = (capital (digit | latin | "-")*)
let symbol = ( [' '-'@'] | ['['-'`'] | ['{'-'~'] )
let opsymbol = ( '+' | '-' | '*' | '/' | '^' | '&' | '|' | '!' | ':' | '=' | '<' | '>' | '~' | '\'' | '.' | '?' )
let str = [^ ' ' '\t' '\n' '\r' '@' '`' '\\' '{' '}' '<' '>' '%' '|' '*' '$' '#' ';']
let mathsymboltop = ('+' | '-' | '*' | '/' | ':' | '=' | '<' | '>' | '~' | '.' | ',' | '`')
let mathsymbol = (mathsymboltop | '?')
let mathascii = (small | capital | digit)
let mathstr = [^ '+' '-' '*' '/' ':' '=' '<' '>' '~' '.' ',' '`' '?' ' ' '\t' '\n' '\r' '\\' '{' '}' '%' '|' '$' '#' ';' '\'' '^' '_' '!' 'a'-'z' 'A'-'Z' '0'-'9']

rule progexpr stack = parse
  | "%"
      {
        comment lexbuf;
        progexpr stack lexbuf
      }
  | ("@" (lower as headertype) ":" (" "*) (nonbreak* as content) (break | eof))
      {
        let pos = get_pos lexbuf in
        increment_line lexbuf;
        match headertype with
        | "require" -> HEADER_REQUIRE(pos, content)
        | "import"  -> HEADER_IMPORT(pos, content)

        | "stage" ->
            begin
              match content with
              | "persistent" -> HEADER_PERSISTENT0(pos)
              | "0"          -> HEADER_STAGE0(pos)
              | "1"          -> HEADER_STAGE1(pos)
              | _            -> raise (LexError(pos, "undefined stage type '" ^ content ^ "'; should be 'persistent', '0', or '1'."))
            end

        | _ ->
            raise (LexError(pos, "undefined header type '" ^ headertype ^ "'"))
      }
  | space
      { progexpr stack lexbuf }
  | break
      {
        increment_line lexbuf;
        progexpr stack lexbuf
      }
  | "("
      { Stack.push ProgramState stack; LPAREN(get_pos lexbuf) }
  | ")"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "too many closing" stack;
        RPAREN(pos)
      }
  | "(|"
      { Stack.push ProgramState stack; BRECORD(get_pos lexbuf) }
  | "|)"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "too many closing" stack;
        ERECORD(pos)
      }
  | "["
      { Stack.push ProgramState stack; BLIST(get_pos lexbuf) }
  | "]"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "too many closing" stack;
        ELIST(pos)
      }
  | "{"
      {
        Stack.push HorizontalState stack;
        skip_spaces lexbuf;
        BHORZGRP(get_pos lexbuf)
      }
  | "'<"
      {
        Stack.push VerticalState stack;
        BVERTGRP(get_pos lexbuf)
      }
  | "${"
      {
        Stack.push MathState stack;
        BMATHGRP(get_pos lexbuf)
      }
  | "`"+
      {
        let pos_start = get_pos lexbuf in
        let quote_length = String.length (Lexing.lexeme lexbuf) in
        let buffer = Buffer.create 256 in
        let (pos_last, s, omit_post) = literal quote_length buffer lexbuf in
        let pos = Range.unite pos_start pos_last in
        LITERAL(pos, s, true, omit_post)
      }
  | ("#" ("`"+ as backticks))
      {
        let pos_start = get_pos lexbuf in
        let quote_length = String.length backticks in
        let buffer = Buffer.create 256 in
        let (pos_last, s, omit_post) = literal quote_length buffer lexbuf in
        let pos = Range.unite pos_start pos_last in
        LITERAL(pos, s, false, omit_post)
      }
  | ("@" ("`"+ as tok))
      {
        let pos_start = get_pos lexbuf in
        let quote_length = String.length tok in
        let buffer = Buffer.create 256 in
        let (pos_last, s, omit_post) = literal quote_length buffer lexbuf in
        let pos = Range.unite pos_start pos_last in
        if not omit_post then Logging.warn_number_sign_end pos_last;
        match Range.get_last pos_start with
        | None ->
            assert false

        | Some(last) ->
            let (fname, ln, col) = last in
            let ipos =
              {
                input_file_name = fname;
                input_line      = ln;
                input_column    = col;
              }
            in
            POSITIONED_LITERAL(pos, ipos, s)
      }
  | ("\\" (lower | upper) "@")
      { HORZMACRO(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("\\" (lower | upper))
      { HORZCMD(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("+" (lower | upper) "@")
      { VERTMACRO(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("+" (lower | upper))
      { VERTCMD(get_pos lexbuf, Lexing.lexeme lexbuf) }

  | "?"  { QUESTION(get_pos lexbuf) }
  | "#"  { ACCESS(get_pos lexbuf) }
  | "->" { ARROW(get_pos lexbuf) }
  | "<-" { REVERSED_ARROW(get_pos lexbuf) }
  | "|"  { BAR(get_pos lexbuf) }
  | "_"  { WILDCARD(get_pos lexbuf) }
  | ":"  { COLON(get_pos lexbuf) }
  | ","  { COMMA(get_pos lexbuf) }
  | "::" { CONS(get_pos lexbuf) }
  | "-"  { EXACT_MINUS(get_pos lexbuf) }
  | "="  { EXACT_EQ(get_pos lexbuf) }
  | "*"  { EXACT_TIMES(get_pos lexbuf) }
  | "&"  { EXACT_AMP(get_pos lexbuf) }
  | "~"  { EXACT_TILDE(get_pos lexbuf) }

  | ("+" opsymbol*) { BINOP_PLUS(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("-" opsymbol+) { BINOP_MINUS(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("*" opsymbol+) { BINOP_TIMES(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("/" opsymbol*) { BINOP_DIVIDES(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("=" opsymbol+) { BINOP_EQ(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("<" opsymbol*) { BINOP_LT(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | (">" opsymbol*) { BINOP_GT(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("&" opsymbol+) { BINOP_AMP(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("|" opsymbol+) { BINOP_BAR(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("^" opsymbol*) { BINOP_HAT(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("!" opsymbol*) { UNOP_EXCLAM(get_pos lexbuf, Lexing.lexeme lexbuf) }

  | ("'" (lower as tyvarnm))
      { TYPEVAR(get_pos lexbuf, tyvarnm) }
  | ((upper ".")+ lower)
      {
        let tokstr = Lexing.lexeme lexbuf in
        let pos = get_pos lexbuf in
        let (modnms, varnm) = split_module_list tokstr in
        PATH_LOWER(pos, modnms, varnm)
      }
  | lower
      {
        let tokstr = Lexing.lexeme lexbuf in
        let pos = get_pos lexbuf in
        match tokstr with
        | "and"       -> AND(pos)
        | "as"        -> AS(pos)
        | "block"     -> BLOCK(pos)
        | "else"      -> ELSE(pos)
        | "end"       -> END(pos)
        | "false"     -> FALSE(pos)
        | "fun"       -> FUN(pos)
        | "if"        -> IF(pos)
        | "in"        -> IN(pos)
        | "include"   -> INCLUDE(pos)
        | "inline"    -> INLINE(pos)
        | "let"       -> LET(pos)
        | "mod"       -> MOD(pos)
        | "match"     -> MATCH(pos)
        | "math"      -> MATH(pos)
        | "module"    -> MODULE(pos)
        | "mutable"   -> MUTABLE(pos)
        | "of"        -> OF(pos)
        | "open"      -> OPEN(pos)
        | "rec"       -> VAL(pos)
        | "sig"       -> SIG(pos)
        | "signature" -> STRUCT(pos)
        | "struct"    -> STRUCT(pos)
        | "then"      -> THEN(pos)
        | "true"      -> TRUE(pos)
        | "type"      -> TYPE(pos)
        | "val"       -> VAL(pos)
        | "with"      -> WITH(pos)
        | _           -> LOWER(pos, tokstr)
      }
  | upper
      { UPPER(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ((upper as modnm) ".(")
      { Stack.push ProgramState stack; OPENMODULE(get_pos lexbuf, modnm) }
  | (digit | (nzdigit digit+))
      { INTCONST(get_pos lexbuf, int_of_string (Lexing.lexeme lexbuf)) }
  | (("0x" | "0X") hex+)
      { INTCONST(get_pos lexbuf, int_of_string (Lexing.lexeme lexbuf)) }
  | ((digit+ "." digit*) | ("." digit+))
      { FLOATCONST(get_pos lexbuf, float_of_string (Lexing.lexeme lexbuf)) }
  | (((("-"? digit) | ("-"? nzdigit digit+)) as i) (lower as unitnm))
      { LENGTHCONST(get_pos lexbuf, float_of_int (int_of_string i), unitnm) }
  | ((("-"? digit+ "." digit*) as flt) (lower as unitnm))
      { LENGTHCONST(get_pos lexbuf, float_of_string flt, unitnm) }
  | ((("-"? "." digit+) as flt) (lower as unitnm))
      { LENGTHCONST(get_pos lexbuf, float_of_string flt, unitnm) }
  | eof
      {
        if Stack.length stack = 1 then
          EOI
        else
          report_error lexbuf "text input ended while reading a program area"
      }
  | _ as c
      { report_error lexbuf (Printf.sprintf "illegal token '%s' in a program area" (String.make 1 c)) }


and vertexpr stack = parse
  | "%"
      {
        comment lexbuf;
        vertexpr stack lexbuf
      }
  | (break | space)*
      {
        increment_line_for_each_break lexbuf (Lexing.lexeme lexbuf);
        vertexpr stack lexbuf
      }
  | ("#" (((upper ".")* lower) as s))
      {
        let (modnms, csnm) = split_module_list s in
        Stack.push ActiveState stack;
        VARINVERT(get_pos lexbuf, modnms, csnm)
      }
  | ("+" (lower | upper) "@")
      {
        Stack.push ActiveState stack;
        VERTMACRO(get_pos lexbuf, Lexing.lexeme lexbuf)
      }
  | ("+" (lower | upper))
      {
        Stack.push ActiveState stack;
        VERTCMD(get_pos lexbuf, Lexing.lexeme lexbuf)
      }
  | ("+" (((upper ".")+ (lower | upper)) as s))
      {
        let (modnms, csnm) = split_module_list s in
        Stack.push ActiveState stack;
        VERTCMDWITHMOD(get_pos lexbuf, modnms, "+" ^ csnm)
      }
  | "<"
      { Stack.push VerticalState stack; BVERTGRP(get_pos lexbuf) }
  | ">"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "too many closing" stack;
        EVERTGRP(pos)
      }
  | "{"
      {
        Stack.push HorizontalState stack;
        skip_spaces lexbuf;
        BHORZGRP(get_pos lexbuf)
      }
  | eof
      {
        if Stack.length stack = 1 then
          EOI
        else
          report_error lexbuf "unexpected end of input while reading a vertical area"
      }
  | _ as c
      { report_error lexbuf (Printf.sprintf "unexpected character '%s' in a vertical area" (String.make 1 c)) }

and horzexpr stack = parse
  | "%"
      {
        comment lexbuf;
        skip_spaces lexbuf;
        horzexpr stack lexbuf
      }
  | ((break | space)* "{")
      {
        increment_line_for_each_break lexbuf (Lexing.lexeme lexbuf);
        Stack.push HorizontalState stack;
        skip_spaces lexbuf;
        BHORZGRP(get_pos lexbuf)
      }
  | ((break | space)* "}")
      {
        increment_line_for_each_break lexbuf (Lexing.lexeme lexbuf);
        let pos = get_pos lexbuf in
        pop lexbuf "too many closing" stack;
        EHORZGRP(pos)
      }
  | ((break | space)* "<")
      {
        increment_line_for_each_break lexbuf (Lexing.lexeme lexbuf);
        Stack.push VerticalState stack;
        BVERTGRP(get_pos lexbuf)
      }
  | ((break | space)* "|")
      {
        increment_line_for_each_break lexbuf (Lexing.lexeme lexbuf);
        skip_spaces lexbuf;
        BAR(get_pos lexbuf)
      }
  | break
      {
        increment_line lexbuf;
        skip_spaces lexbuf;
        BREAK(get_pos lexbuf)
      }
  | space
      {
        skip_spaces lexbuf;
        SPACE(get_pos lexbuf)
      }
  | ((break | space)* (item as itemstr))
      {
        increment_line_for_each_break lexbuf (Lexing.lexeme lexbuf);
        skip_spaces lexbuf;
        ITEM(get_pos lexbuf, String.length itemstr)
      }
  | ("#" (((upper ".")* lower) as s))
      {
        let (modnms, csnm) = split_module_list s in
        Stack.push ActiveState stack;
        VARINHORZ(get_pos lexbuf, modnms, csnm)
      }
  | ("\\" (lower | upper))
      {
        let tok = Lexing.lexeme lexbuf in
        let rng = get_pos lexbuf in
        Stack.push ActiveState stack;
        HORZCMD(rng, tok)
      }
  | ("\\" (lower | upper) "@")
      {
        let tok = Lexing.lexeme lexbuf in
        let rng = get_pos lexbuf in
        Stack.push ActiveState stack;
        HORZMACRO(rng, tok)
      }
  | ("\\" (((upper ".")+ (lower | upper)) as s))
      {
        let (modnms, csnm) = split_module_list s in
        let rng = get_pos lexbuf in
        Stack.push ActiveState stack;
        HORZCMDWITHMOD(rng, modnms, "\\" ^ csnm)
      }
  | ("\\" symbol)
      {
        let tok = String.sub (Lexing.lexeme lexbuf) 1 1 in
        CHAR(get_pos lexbuf, tok)
      }
  | "${"
      {
        Stack.push MathState stack;
        BMATHGRP(get_pos lexbuf)
      }
  | "`"+
      {
        let pos_start = get_pos lexbuf in
        let quote_length = String.length (Lexing.lexeme lexbuf) in
        let buffer = Buffer.create 256 in
        let (pos_last, s, omit_post) = literal quote_length buffer lexbuf in
        let pos = Range.unite pos_start pos_last in
        LITERAL(pos, s, true, omit_post)
      }
  | ("#" ("`"+ as backticks))
      {
        let pos_start = get_pos lexbuf in
        let quote_length = String.length backticks in
        let buffer = Buffer.create 256 in
        let (pos_last, s, omit_post) = literal quote_length buffer lexbuf in
        let pos = Range.unite pos_start pos_last in
        LITERAL(pos, s, false, omit_post)
      }
  | eof
      {
        if Stack.length stack = 1 then
          EOI
        else
          report_error lexbuf "unexpected end of input while reading an inline text area"
      }
  | str+
      { let tok = Lexing.lexeme lexbuf in CHAR(get_pos lexbuf, tok) }

  | _ as c
      { report_error lexbuf (Printf.sprintf "illegal token '%s' in an inline text area" (String.make 1 c)) }


and mathexpr stack = parse
  | space
      { mathexpr stack lexbuf }
  | break
      { increment_line lexbuf; mathexpr stack lexbuf }
  | "%"
      {
        comment lexbuf;
        mathexpr stack lexbuf
      }
  | "?"
      { QUESTION(get_pos lexbuf) }
  | "!{"
      {
        Stack.push HorizontalState stack;
        skip_spaces lexbuf;
        BHORZGRP(get_pos lexbuf);
      }
  | "!<"
      {
        Stack.push VerticalState stack;
        BVERTGRP(get_pos lexbuf)
      }
  | "!("
      {
        Stack.push ProgramState stack;
        LPAREN(get_pos lexbuf)
      }
  | "!["
      {
        Stack.push ProgramState stack;
        BLIST(get_pos lexbuf)
      }
  | "!(|"
      {
        Stack.push ProgramState stack;
        BRECORD(get_pos lexbuf)
      }
  | "{"
      {
        Stack.push MathState stack;
        BMATHGRP(get_pos lexbuf)
      }
  | "}"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "too many closing" stack;
        EMATHGRP(pos)
      }
  | "|"
      { BAR(get_pos lexbuf) }
  | "^"
      { SUPERSCRIPT(get_pos lexbuf) }
  | "_"
      { SUBSCRIPT(get_pos lexbuf) }
  | "'"+
      { let n = String.length (Lexing.lexeme lexbuf) in PRIMES(get_pos lexbuf, n) }
  | (mathsymboltop (mathsymbol*))
      { MATHCHARS(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | mathascii
      { MATHCHARS(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | mathstr+
      { MATHCHARS(get_pos lexbuf, Lexing.lexeme lexbuf) }
  | ("#" (lower as varnm))
      {
        VARINMATH(get_pos lexbuf, [], varnm)
      }
  | ("#" (((upper ".")* (lower | upper)) as s))
      {
        let (modnms, csnm) = split_module_list s in
        VARINMATH(get_pos lexbuf, modnms, csnm)
      }
  | ("\\" (lower | upper))
      {
        let csnm = Lexing.lexeme lexbuf in
        MATHCMD(get_pos lexbuf, csnm)
      }
  | ("\\" (((upper ".")* (lower | upper)) as s))
      {
        let (modnms, csnm) = split_module_list s in
        MATHCMDWITHMOD(get_pos lexbuf, modnms, "\\" ^ csnm)
      }
  | ("\\" symbol)
      {
        let tok = String.sub (Lexing.lexeme lexbuf) 1 1 in
        MATHCHARS(get_pos lexbuf, tok)
      }
  | _ as c
      { report_error lexbuf (Printf.sprintf "illegal token '%s' in a math area" (String.make 1 c)) }
  | eof
      { report_error lexbuf "unexpected end of file in a math area" }


and active stack = parse
  | "%"
      {
        comment lexbuf;
        active stack lexbuf
      }
  | space
      { active stack lexbuf }
  | break
      { increment_line lexbuf; active stack lexbuf }
  | "~"
      { EXACT_TILDE(get_pos lexbuf) }
  | "?"
      { QUESTION(get_pos lexbuf) }
  | "("
      {
        Stack.push ProgramState stack;
        LPAREN(get_pos lexbuf)
      }
  | "(|"
      {
        Stack.push ProgramState stack;
        BRECORD(get_pos lexbuf)
      }
  | "["
      {
        Stack.push ProgramState stack;
        BLIST(get_pos lexbuf)
      }
  | "{"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "BUG; this cannot happen" stack;
        Stack.push HorizontalState stack;
        skip_spaces lexbuf;
        BHORZGRP(pos)
      }
  | "<"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "BUG; this cannot happen" stack;
        Stack.push VerticalState stack;
        BVERTGRP(pos)
      }
  | ";"
      {
        let pos = get_pos lexbuf in
        pop lexbuf "BUG; this cannot happen" stack;
        ENDACTIVE(pos)
      }
  | eof
      { report_error lexbuf "unexpected end of input while reading an active area" }
  | _
      {
        let s = Lexing.lexeme lexbuf in
        report_error lexbuf (Printf.sprintf "unexpected token '%s' in an active area" s)
      }


and literal quote_length buffer = parse
  | "`"+
      {
        let backticks = Lexing.lexeme lexbuf in
        let len = String.length backticks in
        if len < quote_length then begin
          Buffer.add_string buffer backticks;
          literal quote_length buffer lexbuf
        end else if len > quote_length then
          report_error lexbuf "literal area was closed with too many '`'s"
        else
          let s = Buffer.contents buffer in
          let pos_last = get_pos lexbuf in
          (pos_last, s, true)
    }
  | (("`"+ as backticks) "#")
      {
        let len = String.length backticks in
        if len < quote_length then begin
          Buffer.add_string buffer backticks;
          Buffer.add_string buffer "#";
          literal quote_length buffer lexbuf
        end else if len > quote_length then
          report_error lexbuf "literal area was closed with too many '`'s"
        else
          let s = Buffer.contents buffer in
          let pos_last = get_pos lexbuf in
          (pos_last, s, false)
    }
  | break
      {
        let tok = Lexing.lexeme lexbuf in
        increment_line lexbuf;
        Buffer.add_string buffer tok;
        literal quote_length buffer lexbuf
      }
  | eof
      {
        report_error lexbuf "unexpected end of input while reading literal area"
      }
  | _
      {
        let s = Lexing.lexeme lexbuf in
        Buffer.add_string buffer s;
        literal quote_length buffer lexbuf
      }


and comment = parse
  | break { increment_line lexbuf; }
  | eof   { () }
  | _     { comment lexbuf }


and skip_spaces = parse
  | break
      {
        increment_line lexbuf;
        skip_spaces lexbuf
      }
  | space
      {
        skip_spaces lexbuf
      }
  | "%"
      {
        comment lexbuf;
        skip_spaces lexbuf
      }
  | ""
      { () }


{
  let cut_token stack lexbuf =
    match Stack.top stack with
    | ProgramState    -> progexpr stack lexbuf
    | VerticalState   -> vertexpr stack lexbuf
    | HorizontalState -> horzexpr stack lexbuf
    | ActiveState     -> active stack lexbuf
    | MathState       -> mathexpr stack lexbuf

}
