// Generated by BUCKLESCRIPT VERSION 1.0.1 , PLEASE EDIT WITH CARE
'use strict';

var Range           = require("./range");
var Caml_exceptions = require("bs-platform/lib/js/caml_exceptions");
var Hashtbl         = require("bs-platform/lib/js/hashtbl");
var Block           = require("bs-platform/lib/js/block");
var Tyvarid         = require("./tyvarid");
var Assoc           = require("./assoc");
var List            = require("bs-platform/lib/js/list");

var ParseErrorDetail = Caml_exceptions.create("Types.ParseErrorDetail");

function replace_type_variable(tystr, key, value) {
  var iter = function (ty) {
    return replace_type_variable(ty, key, value);
  };
  var tymain = tystr[1];
  var rng = tystr[0];
  if (typeof tymain === "number") {
    return /* tuple */[
            rng,
            tymain
          ];
  }
  else {
    switch (tymain.tag | 0) {
      case 0 : 
          return /* tuple */[
                  rng,
                  /* FuncType */Block.__(0, [
                      replace_type_variable(tymain[0], key, value),
                      replace_type_variable(tymain[1], key, value)
                    ])
                ];
      case 1 : 
          return /* tuple */[
                  rng,
                  /* ListType */Block.__(1, [replace_type_variable(tymain[0], key, value)])
                ];
      case 2 : 
          return /* tuple */[
                  rng,
                  /* RefType */Block.__(2, [replace_type_variable(tymain[0], key, value)])
                ];
      case 3 : 
          return /* tuple */[
                  rng,
                  /* ProductType */Block.__(3, [List.map(iter, tymain[0])])
                ];
      case 4 : 
          var k = tymain[0];
          if (Tyvarid.same(k, key)) {
            return value;
          }
          else {
            return /* tuple */[
                    rng,
                    /* TypeVariable */Block.__(4, [k])
                  ];
          }
      case 5 : 
          return /* tuple */[
                  rng,
                  /* TypeSynonym */Block.__(5, [
                      List.map(iter, tymain[0]),
                      tymain[1],
                      replace_type_variable(tymain[2], key, value)
                    ])
                ];
      case 6 : 
          return /* tuple */[
                  rng,
                  /* VariantType */Block.__(6, [
                      List.map(iter, tymain[0]),
                      tymain[1]
                    ])
                ];
      case 7 : 
          var tvid = tymain[0];
          if (Tyvarid.same(tvid, key)) {
            return tystr;
          }
          else {
            return /* tuple */[
                    rng,
                    /* ForallType */Block.__(7, [
                        tvid,
                        tymain[1],
                        replace_type_variable(tymain[2], key, value)
                      ])
                  ];
          }
      case 9 : 
          return /* tuple */[
                  rng,
                  /* RecordType */Block.__(9, [Assoc.map_value(iter, tymain[0])])
                ];
      default:
        return /* tuple */[
                rng,
                tymain
              ];
    }
  }
}

function get_range(utast) {
  return utast[0];
}

function is_invalid_range(rng) {
  return +(rng[0] <= 0);
}

function erase_range_of_type(tystr) {
  var tymain = tystr[1];
  var dr = Range.dummy("erased");
  var newtymain;
  if (typeof tymain === "number") {
    newtymain = tymain;
  }
  else {
    switch (tymain.tag | 0) {
      case 0 : 
          newtymain = /* FuncType */Block.__(0, [
              erase_range_of_type(tymain[0]),
              erase_range_of_type(tymain[1])
            ]);
          break;
      case 1 : 
          newtymain = /* ListType */Block.__(1, [erase_range_of_type(tymain[0])]);
          break;
      case 2 : 
          newtymain = /* RefType */Block.__(2, [erase_range_of_type(tymain[0])]);
          break;
      case 3 : 
          newtymain = /* ProductType */Block.__(3, [List.map(erase_range_of_type, tymain[0])]);
          break;
      case 5 : 
          newtymain = /* TypeSynonym */Block.__(5, [
              List.map(erase_range_of_type, tymain[0]),
              tymain[1],
              erase_range_of_type(tymain[2])
            ]);
          break;
      case 6 : 
          newtymain = /* VariantType */Block.__(6, [
              List.map(erase_range_of_type, tymain[0]),
              tymain[1]
            ]);
          break;
      case 7 : 
          newtymain = /* ForallType */Block.__(7, [
              tymain[0],
              erase_range_of_kind(tymain[1]),
              erase_range_of_type(tymain[2])
            ]);
          break;
      default:
        newtymain = tymain;
    }
  }
  return /* tuple */[
          dr,
          newtymain
        ];
}

function erase_range_of_kind(kdstr) {
  if (kdstr) {
    return /* RecordKind */[Assoc.map_value(erase_range_of_type, kdstr[0])];
  }
  else {
    return /* UniversalKind */0;
  }
}

var global_hash_env = Hashtbl.create(/* None */0, 32);

exports.ParseErrorDetail      = ParseErrorDetail;
exports.replace_type_variable = replace_type_variable;
exports.get_range             = get_range;
exports.is_invalid_range      = is_invalid_range;
exports.erase_range_of_type   = erase_range_of_type;
exports.erase_range_of_kind   = erase_range_of_kind;
exports.global_hash_env       = global_hash_env;
/* global_hash_env Not a pure module */
