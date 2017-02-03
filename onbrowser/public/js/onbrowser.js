// Generated by BUCKLESCRIPT VERSION 1.0.1 , PLEASE EDIT WITH CARE
'use strict';

var Out                     = require("./out");
var Caml_builtin_exceptions = require("bs-platform/lib/js/caml_builtin_exceptions");
var Lexer                   = require("./lexer");
var Parser                  = require("./parser");
var Variantenv              = require("./variantenv");
var Caml_exceptions         = require("bs-platform/lib/js/caml_exceptions");
var Typechecker             = require("./typechecker");
var Lexing                  = require("bs-platform/lib/js/lexing");
var Parsing                 = require("bs-platform/lib/js/parsing");
var Curry                   = require("bs-platform/lib/js/curry");
var Primitives              = require("./primitives");
var Kindenv                 = require("./kindenv");
var Subst                   = require("./subst");
var Domstd                  = require("./domstd");
var Evaluator               = require("./evaluator");
var Types                   = require("./types");

var OnBrowserError = Caml_exceptions.create("Onbrowser.OnBrowserError");

var env_default = Primitives.make_environment(/* () */0);

function output(inputCode) {
  try {
    Lexer.reset_to_numexpr(/* () */0);
    var utast = Parser.main(Lexer.cut_token, Lexing.from_string(inputCode));
    var match = Typechecker.main(Primitives.make_variant_environment, Kindenv.empty, Primitives.make_type_environment, utast);
    var match$1 = match[0][1];
    if (typeof match$1 === "number") {
      if (match$1 !== 2) {
        throw [
              OnBrowserError,
              "the output is not string"
            ];
      }
      else {
        return Out.main(Evaluator.interpret(env_default, match[4]));
      }
    }
    else {
      throw [
            OnBrowserError,
            "the output is not string"
          ];
    }
  }
  catch (exn){
    var exit = 0;
    var s;
    if (exn[0] === Lexer.LexError) {
      return "! [ERROR AT LEXER] " + (exn[1] + ".");
    }
    else if (exn === Parsing.Parse_error) {
      return "! [ERROR AT PARSER] something is wrong.";
    }
    else if (exn[0] === Types.ParseErrorDetail) {
      return "! [ERROR AT PARSER] " + (exn[1] + "");
    }
    else if (exn[0] === Typechecker.$$Error) {
      s = exn[1];
      exit = 1;
    }
    else if (exn[0] === Variantenv.$$Error) {
      s = exn[1];
      exit = 1;
    }
    else if (exn[0] === Subst.ContradictionError) {
      s = exn[1];
      exit = 1;
    }
    else if (exn[0] === Evaluator.EvalError) {
      return "! [ERROR AT EVALUATOR] " + (exn[1] + ".");
    }
    else if (exn[0] === Out.IllegalOut) {
      return "! [ERROR AT OUTPUT] " + (exn[1] + ".");
    }
    else if (exn[0] === OnBrowserError) {
      return "! [ERROR] " + (exn[1] + ".");
    }
    else if (exn[0] === Caml_builtin_exceptions.sys_error) {
      return "! [ERROR] System error - " + exn[1];
    }
    else {
      throw exn;
    }
    if (exit === 1) {
      return "! [ERROR AT TYPECHECKER] " + (s + ".");
    }
    
  }
}

Curry._1(Domstd.afterLoadingHTML, function () {
      var inputArea = document.inputForm.inputArea;
      var outputArea = Curry._2(Domstd.getElementById, "output-area", Domstd.$$document);
      var submissionButton = Curry._2(Domstd.getElementById, "submission-button", Domstd.$$document);
      return Domstd.addEventListener(/* Click */0, function () {
                  var outputText = output(inputArea.value);
                  Curry._2(Domstd.setInnerText, outputText, outputArea);
                  return /* () */0;
                }, submissionButton);
    });

var varntenv_default = Primitives.make_variant_environment;

var kdenv_default = Kindenv.empty;

var tyenv_default = Primitives.make_type_environment;

exports.OnBrowserError   = OnBrowserError;
exports.varntenv_default = varntenv_default;
exports.kdenv_default    = kdenv_default;
exports.tyenv_default    = tyenv_default;
exports.env_default      = env_default;
exports.output           = output;
/* env_default Not a pure module */
