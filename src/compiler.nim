#[****************************************************************
  * Arturo
  * 
  * Programming Language + Interpreter
  * (c) 2019 Yanis Zafirópulos (aka Dr.Kameleon)
  *
  * @file: compiler.nim
  *****************************************************************]#

import algorithm, macros, math, os, parseutils, sequtils, strutils, sugar, tables
import bignum
import panic

#[######################################################
    Type definitions
  ======================================================]#

type
    #[----------------------------------------
        Stack
      ----------------------------------------]#

    Context = ref object
        list    : seq[(string,Value)]

    #[----------------------------------------
        KeyPath
      ----------------------------------------]#

    KeyPathPartKind {.size: sizeof(cint),pure.} = enum
        stringKeyPathPart,
        integerKeyPathPart,
        inlineKeyPathPart

    KeyPathPart = ref object
        case kind: KeyPathPartKind:
            of stringKeyPathPart    : s: string
            of integerKeyPathPart   : i: int
            of inlineKeyPathPart    : a: Argument

    KeyPath = ref object
        parts: seq[KeyPathPart]
                
    #[----------------------------------------
        Argument
      ----------------------------------------]#
    
    ArgumentKind {.size: sizeof(cint),pure.} = enum
        identifierArgument, 
        literalArgument,
        arrayArgument,
        dictionaryArgument,
        functionArgument,
        inlineCallArgument

    Argument = ref object
        case kind: ArgumentKind:
            of identifierArgument   : i: string
            of literalArgument      : v: Value
            of arrayArgument        : a: ExpressionList
            of dictionaryArgument   : d: StatementList
            of functionArgument     : f: Function
            of inlineCallArgument   : c: Statement

    #[----------------------------------------
        Expression
      ----------------------------------------]#

    ExpressionOperator {.size: sizeof(cint),pure.} = enum
        PLUS_SG, MINUS_SG, MULT_SG, DIV_SG, MOD_SG, POW_SG,
        EQ_OP, GE_OP, LE_OP, GT_OP, LT_OP, NE_OP

    ExpressionKind = enum
        argumentExpression, 
        normalExpression

    Expression = ref object
        case kind: ExpressionKind:
            of argumentExpression:
                a       : Argument
            of normalExpression:
                left    : Expression
                op      : ExpressionOperator
                right   : Expression

    #[----------------------------------------
        ExpressionList
      ----------------------------------------]#

    ExpressionList = ref object
        list    : seq[Expression]

    #[----------------------------------------
        Statement
      ----------------------------------------]#

    StatementKind {.size: sizeof(cint),pure.} = enum
        commandStatement,
        assignmentStatement,
        expressionStatement,
        normalStatement

    Statement = ref object
        pos: int
        case kind: StatementKind:
            of commandStatement:
                code            : int
                arguments       : ExpressionList
            of assignmentStatement:
                symbol          : string
                rValue          : ExpressionList
            of expressionStatement:
                expression      : Expression
            of normalStatement:
                id              : string
                expressions     : ExpressionList

    #[----------------------------------------
        StatementList
      ----------------------------------------]#

    StatementList = ref object
        list    : seq[Statement]

    #[----------------------------------------
        Function
      ----------------------------------------]#

    FunctionConstraints     = seq[seq[ValueKind]]
    FunctionReturns         = seq[ValueKind]

    SystemFunction* = object
        lib*            : string
        name*           : string
        req             : FunctionConstraints
        ret             : FunctionReturns
        desc            : string

    Function* = ref object
        id              : string
        args            : seq[string]
        body            : StatementList
        hasContext      : bool
        parentThis      : Value
        parentContext   : Context

    #[----------------------------------------
        Value
      ----------------------------------------]#

    ValueKind* {.pure.} = enum
        stringValue, integerValue, bigIntegerValue, realValue, booleanValue,
        arrayValue, dictionaryValue, functionValue,
        nullValue, anyValue

    Value* = ref object
        case kind*: ValueKind:
            of stringValue          : s: string
            of integerValue         : i*: int
            of bigIntegerValue      : bi*: Int
            of realValue            : r: float
            of booleanValue         : b: bool 
            of arrayValue           : a: seq[Value]
            of dictionaryValue      : d: Context
            of functionValue        : f: Function
            of nullValue            : discard
            of anyValue             : discard

    #[----------------------------------------
        Returns
      ----------------------------------------]#

    ReturnValue* = object of Exception
        value: Value

#[######################################################
    Forward declarations
  ======================================================]#

proc getValueForKey*(ctx: Context, key: string): Value {.inline.}
proc inspectStack()

proc valueFromString(v: string): Value {.inline.}
proc valueFromInteger*(v: int): Value {.inline.}
proc valueFromInteger(v: string): Value {.inline.}
proc valueFromBigInteger*(v: Int): Value {.inline.}
proc valueFromBigInteger*(v: string): Value {.inline.}
proc valueFromArray(v: seq[Value]): Value {.inline.}
proc `+`(l: Value, r: Value): Value {.inline.}
proc `-`(l: Value, r: Value): Value {.inline.}
proc `*`(l: Value, r: Value): Value {.inline.}
proc `/`(l: Value, r: Value): Value {.inline.}
proc `%`(l: Value, r: Value): Value {.inline.}
proc `^`(l: Value, r: Value): Value {.inline.}
proc eq(l: Value, r: Value): bool {.inline.}
proc lt(l: Value, r: Value): bool {.inline.}
proc gt(l: Value, r: Value): bool {.inline.}
proc stringify*(v: Value, quoted: bool = true): string

proc execute(f: Function, v: Value): Value {.inline.} 

proc evaluate(x: Expression): Value {.inline.}
proc evaluate(xl: ExpressionList, forceArray: bool=false): Value

proc statementFromExpressions(i: cstring, xl: ExpressionList, l: cint=0): Statement {.exportc.}
proc statementFromCommand(i: cint, xl: ExpressionList, l: cint): Statement {.exportc.}
proc execute(stm: Statement, parent: Value = nil): Value {.inline.}
proc execute(sl: StatementList): Value

proc argumentFromInlineCallLiteral(l: Statement): Argument {.exportc.}
proc getValue(a: Argument): Value {.inline.}

#[######################################################
    Globals
  ======================================================]#

var
    MainProgram {.exportc.} : StatementList

    # Environment

    Stack*                  : seq[Context]
    FileName                : string
    IsRepl                  : bool

    # Const/literal arguments

    ConstStrings            : TableRef[string,Argument]
    ConstTrue               : Argument
    ConstFalse              : Argument
    ConstNull               : Argument

#[######################################################
    Aliases
  ======================================================]#

template SV():ValueKind         = stringValue
template IV():ValueKind         = integerValue
template BIV():ValueKind        = bigIntegerValue
template RV():ValueKind         = realValue
template BV():ValueKind         = booleanValue
template AV():ValueKind         = arrayValue
template DV():ValueKind         = dictionaryValue
template FV():ValueKind         = functionValue
template ANY():ValueKind        = anyValue

template S(_:int):string        = v[_].s
template I(_:int):int           = v[_].i
template BI(_:int):Int          = v[_].bi
template R(_:int):float         = v[_].r
template B(_:int):bool          = v[_].b
template A(_:int):seq[Value]    = v[_].a
template D(_:int):Context       = v[_].d
template FN(_:int):Function     = v[_].f

template NULL():Value       = ConstNull.v
template TRUE():Value       = ConstTrue.v
template FALSE():Value      = ConstFalse.v

#[######################################################
    System library
  ======================================================]#

include lib/core
include lib/collections
include lib/numbers

const
    SystemFunctions* = @[
        #----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
        #              Library              Name                 Args                                                    Return                  Description                                                                                             
        #----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
        SystemFunction(lib:"core",          name:"if",           req: @[@[BV,FV],@[BV,FV,FV]],                           ret: @[ANY],            desc:"if condition is true, execute given function; else execute optional alternative function"),
        SystemFunction(lib:"core",          name:"get",          req: @[@[AV,IV],@[DV,SV]],                              ret: @[ANY],            desc:"get element from collection using given index/key"),
        SystemFunction(lib:"core",          name:"loop",         req: @[@[AV,FV],@[DV,FV],@[BV,FV],@[IV,FV]],            ret: @[ANY],            desc:"execute given function for each element in collection, or while condition is true"),
        SystemFunction(lib:"core",          name:"print",        req: @[@[SV],@[AV],@[IV],@[BIV],@[FV],@[BV],@[RV]],     ret: @[SV],             desc:"print value of given expression to screen"),
        SystemFunction(lib:"core",          name:"range",        req: @[@[IV,IV]],                                       ret: @[AV],             desc:"get array from given range (from..to) with optional step"),
        # SystemFunction(lib:"core",          name:"return",       req: @[@[ANY]],                                         ret: @[ANY],            desc:"break execution and return given value"),

        # SystemFunction(lib:"core",          name:"and",          req: @[@[BV,BV],@[IV,IV]],                              ret: @[BV,IV],          desc:"bitwise/logical AND"),
        # SystemFunction(lib:"core",          name:"not",          req: @[@[BV],@[IV]],                                    ret: @[BV,IV],          desc:"bitwise/logical NOT"),
        # SystemFunction(lib:"core",          name:"or",           req: @[@[BV,BV],@[IV,IV]],                              ret: @[BV,IV],          desc:"bitwise/logical OR"),
        # SystemFunction(lib:"core",          name:"xor",          req: @[@[BV,BV],@[IV,IV]],                              ret: @[BV,IV],          desc:"bitwise/logical XOR"),

        # SystemFunction(lib:"core",          name:"filter",       req: @[@[AV,FV]],                                       ret: @[AV],             desc:"get array after filtering each element using given function"),
        # SystemFunction(lib:"core",          name:"shuffle",      req: @[@[AV]],                                          ret: @[AV],             desc:"get given array shuffled"),
        # SystemFunction(lib:"core",          name:"size",         req: @[@[AV],@[SV],@[DV]],                              ret: @[IV],             desc:"get size of given collection or string"),
        # SystemFunction(lib:"core",          name:"slice",        req: @[@[AV,IV],@[AV,IV,IV],@[SV,IV],@[SV,IV,IV]],      ret: @[AV,SV],          desc:"get slice of array/string given a starting and/or end point"),
        # SystemFunction(lib:"core",          name:"swap",         req: @[@[AV,IV,IV]],                                    ret: @[AV],             desc:"swap array elements at given indices"),

        # SystemFunction(lib:"core",          name:"isPrime",      req: @[@[IV]],                                          ret: @[BV],             desc:"check if given number is prime"),
        # SystemFunction(lib:"core",          name:"product",      req: @[@[AV]],                                          ret: @[IV,BIV],         desc:"return product of elements of given array"),
        # SystemFunction(lib:"core",          name:"sum",          req: @[@[AV]],                                          ret: @[IV,BIV],         desc:"return sum of elements of given array")
    ]

#[######################################################
    Parser C Interface
  ======================================================]#

type
    yy_buffer_state {.importc.} = ref object
        yy_input_file       : File
        yy_ch_buf           : cstring
        yy_buf_pos          : cstring
        yy_buf_size         : clong
        yy_n_chars          : cint
        yy_is_our_buffer    : cint
        yy_is_interactive   : cint
        yy_at_bol           : cint
        yy_fill_buffer      : cint
        yy_buffer_status    : cint

proc yyparse(): cint {.importc.}
proc yy_scan_buffer(buff: cstring, s: csize) {.importc.}

proc yy_scan_string(str: cstring): yy_buffer_state {.importc.}
proc yy_switch_to_buffer(buff: yy_buffer_state) {.importc.}
proc yy_delete_buffer(buff: yy_buffer_state) {.importc.}

var yyfilename {.importc.}: cstring
var yyin {.importc.}: File
var yylineno {.importc.}: cint

#[######################################################
    Context management
  ======================================================]#

proc addContext() {.inline.} =
    Stack.add(Context(list: @[]))

proc addContextWith(key:string, val:Value) {.inline.} =
    Stack[^1] = Context(list: @[(key,val)])

proc addContextWith(pairs:seq[(string,Value)]) {.inline.} =
    Stack[^1] = Context(list:pairs)

proc popContext() {.inline.} =
    discard Stack.pop()

proc updateOrSet(ctx: var Context, k: string, v: Value) {.inline.} = 
    var i = 0
    while i<ctx.list.len:
        if ctx.list[i][0]==k: 
            ctx.list[i][1] = v
            return
        inc(i)

    # not updated, so let's assign it
    ctx.list.add((k,v))

proc keys*(ctx: Context): seq[string] {.inline.} =
    result = ctx.list.map((x) => x[0])

proc hasKey*(ctx: Context, key: string): bool {.inline.} = 
    var i = 0
    while i<ctx.list.len:
        if ctx.list[i][0]==key: return true 
        inc(i)
    return false

proc getValueForKey*(ctx: Context, key: string): Value {.inline.} =
    var i = 0
    while i<ctx.list.len:
        if ctx.list[i][0]==key: return ctx.list[i][1] 
        inc(i)
    return nil

proc getSymbol(k: string): Value {.inline.} = 
    var i = len(Stack) - 1
    while i > -1:
        var j = 0
        while j<Stack[i].list.len:
            if Stack[i].list[j][0]==k: 
                return Stack[i].list[j][1]
            inc(j)
        dec(i)

    return nil

proc getAndSetSymbol(k: string, v: Value): Value {.inline.} = 
    var i = len(Stack) - 1
    while i > -1:
        var j = 0
        while j<Stack[i].list.len:
            if Stack[i].list[j][0]==k: 
                result = Stack[i].list[j][1]
                Stack[i].list[j][1] = v
            inc(j)
        dec(i)

    return nil

proc setSymbol(k: string, v: Value, redefine: bool=false): Value {.inline.} = 
    if redefine:
        Stack[^1].updateOrSet(k,v)
        result = v
    else:
        var i = len(Stack) - 1
        while i > -1:
            var j = 0
            while j<Stack[i].list.len:
                if Stack[i].list[j][0]==k: 
                    Stack[i].list[j][1]=v
                    return v
                inc(j)

            dec(i)

        Stack[^1].updateOrSet(k,v)
        result = v

proc inspectStack() =
    var i = 0
    for s in Stack:
        var tab = ""
        if i>0: tab = "\t"
        echo tab,"----------------"
        echo tab,"Stack[",i,"]"
        echo tab,"----------------"

        for t in s.list:
            echo tab,t[0]," -> ",t[1].stringify()

        inc(i)

#[######################################################
    Methods
  ======================================================]#

#[----------------------------------------
    Value
  ----------------------------------------]#

proc valueFromString(v: string): Value {.inline.} =
    Value(kind: stringValue, s: v)

proc valueFromInteger*(v: int): Value {.inline.} =
    Value(kind: integerValue, i: v)

proc valueFromInteger(v: string): Value {.inline.} =
    var intValue: int
    try: 
        discard parseInt(v, intValue)
        result = valueFromInteger(intValue)
    except: 
        result = valueFromBigInteger(v)

proc valueFromBigInteger*(v: Int): Value {.inline.} =
    Value(kind: bigIntegerValue, bi: v)

proc valueFromBigInteger*(v: string): Value {.inline.} =
    Value(kind: bigIntegerValue, bi: newInt(v))

proc valueFromReal(v: float): Value {.inline.} =
    result = Value(kind: realValue, r: v)

proc valueFromReal(v: string): Value {.inline.} =
    var floatValue: float
    discard parseFloat(v, floatValue)

    result = valueFromReal(floatValue)

proc valueFromBoolean(v: bool): Value {.inline.} =
    result = Value(kind: booleanValue, b: v)

proc valueFromBoolean(v: string): Value {.inline.} =
    if v=="true": result = valueFromBoolean(true)
    else: result = valueFromBoolean(false)

proc valueFromNull(): Value {.inline.} =
    result = Value(kind: nullValue)

proc valueFromArray(v: seq[Value]): Value {.inline.} =
    result = Value(kind: arrayValue, a: v)

proc valueFromDictionary(v: Context): Value {.inline.} = 
    result = Value(kind: dictionaryValue, d: v)

proc valueFromFunction(v: Function): Value {.inline.} =
    result = Value(kind: functionValue, f: v)

proc valueFromValue(v: Value): Value =
    {.computedGoto.}
    result = case v.kind
        of stringValue: valueFromString(v.s)
        of integerValue: valueFromInteger(v.i)
        of realValue: valueFromReal(v.r)
        of arrayValue: valueFromArray(v.a.map((x) => valueFromValue(x)))
        of dictionaryValue: valueFromDictionary(Context(list:v.d.list.map((x) => (x[0],valueFromValue(x[1])))))
        else: v

proc findValueInArray(v: Value, lookup: Value): int =
    var i = 0
    while i < v.a.len:
        if v.a[i].eq(lookup): return i 
        inc(i)
    return -1

proc `+`(l: Value, r: Value): Value {.inline.} =
    {.computedGoto.}
    case l.kind
        of stringValue:
            result = case r.kind
                of stringValue: valueFromString(l.s & r.s)
                of integerValue: valueFromString(l.s & $(r.i))
                of bigIntegerValue: valueFromString(l.s & $(r.bi))
                of realValue: valueFromString(l.s & $(r.r))
                else: valueFromString(l.s & r.stringify())
        of integerValue:
            result = case r.kind
                of stringValue: valueFromString($(l.i) & r.s)
                of integerValue: 
                    try: valueFromInteger(l.i + r.i)
                    except Exception as e: valueFromBigInteger(newInt(l.i)+r.i)
                of bigIntegerValue: valueFromBigInteger(l.i+r.bi)
                of realValue: valueFromReal(float(l.i)+r.r)
                else: InvalidOperationError("+",$(l.kind),$(r.kind))
        of bigIntegerValue:
            result = case r.kind
                of integerValue: valueFromBigInteger(l.bi + r.i)
                of bigIntegerValue: valueFromBigInteger(l.bi+r.bi)
                else: InvalidOperationError("+",$(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of stringValue: valueFromString($(l.r) & r.s)
                of integerValue: valueFromReal(l.r + float(r.i))
                of realValue: valueFromReal(l.r+r.r)
                else: InvalidOperationError("+",$(l.kind),$(r.kind))
        of arrayValue:
            if r.kind!=arrayValue:
                result = valueFromArray(l.a & r)
            else: 
                result = valueFromArray(l.a & r.a)
        of dictionaryValue:
            if r.kind==dictionaryValue:
                result = valueFromValue(l)
                for k in r.d.keys:
                    result.d.updateOrSet(k,r.d.getValueForKey(k))

            else: InvalidOperationError("+",$(l.kind),$(r.kind))
        else:
            InvalidOperationError("+",$(l.kind),$(r.kind))

proc `-`(l: Value, r: Value): Value {.inline.} =
    {.computedGoto.}
    case l.kind
        of stringValue:
            result = case r.kind
                of stringValue: valueFromString(l.s.replace(r.s,""))
                of integerValue: valueFromString(l.s.replace($(r.i),""))
                of bigIntegerValue: valueFromString(l.s.replace($(r.bi),""))
                of realValue: valueFromString(l.s.replace($(r.r),""))
                else: InvalidOperationError("-",$(l.kind),$(r.kind))
        of integerValue:
            result = case r.kind
                of integerValue: valueFromInteger(l.i - r.i)
                of bigIntegerValue: valueFromBigInteger(l.i - r.bi)
                of realValue: valueFromReal(float(l.i)-r.r)
                else: InvalidOperationError("-",$(l.kind),$(r.kind))
        of bigIntegerValue:
            result = case r.kind
                of integerValue: valueFromBigInteger(l.bi - r.i)
                of bigIntegerValue: valueFromBigInteger(l.bi - r.bi)
                else: InvalidOperationError("-",$(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of integerValue: valueFromReal(l.r - float(r.i))
                of realValue: valueFromReal(l.r-r.r)
                else: InvalidOperationError("-",$(l.kind),$(r.kind))
        of arrayValue:
            result = valueFromValue(l)
            if r.kind!=arrayValue:
                result.a.delete(l.findValueInArray(r))
            else:
                for item in r.a:
                    result.a.delete(result.findValueInArray(item))

        of dictionaryValue:
            result = valueFromValue(l)
            var i = 0
            while i < l.d.list.len:
                if l.d.list[i][1].eq(r):
                    result.d.list.del(i)
                inc(i)

        else:
            InvalidOperationError("-",$(l.kind),$(r.kind))

proc `*`(l: Value, r: Value): Value {.inline.} = 
    {.computedGoto.}
    case l.kind
        of stringValue:
            result = case r.kind
                of integerValue: valueFromString(l.s.repeat(r.i))
                of realValue: valueFromString(l.s.repeat(int(r.r)))
                else: InvalidOperationError("*",$(l.kind),$(r.kind))
        of integerValue:
            result = case r.kind
                of stringValue: valueFromString(r.s.repeat(l.i))
                of integerValue: 
                    try: valueFromInteger(l.i * r.i)
                    except Exception as e: valueFromBigInteger(newInt(l.i)*r.i)
                of bigIntegerValue: valueFromBigInteger(l.i * r.bi)
                of realValue: valueFromReal(float(l.i)*r.r)
                else: InvalidOperationError("*",$(l.kind),$(r.kind))
        of bigIntegerValue:
            result = case r.kind
                of integerValue: valueFromBigInteger(l.bi * r.i)
                of bigIntegerValue: valueFromBigInteger(l.bi * r.bi)
                else: InvalidOperationError("*",$(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of stringValue: valueFromString(r.s.repeat(int(l.r)))
                of integerValue: valueFromReal(l.r * float(r.i))
                of realValue: valueFromReal(l.r*r.r)
                else: InvalidOperationError("*",$(l.kind),$(r.kind))
        of arrayValue:
            result = valueFromArray(@[])
            if r.kind==integerValue or r.kind==realValue:
                var limit:int
                if r.kind==integerValue: limit = r.i
                else: limit = int(r.r)

                var i = 0
                while i<limit:
                    for item in l.a:
                        result.a.add(valueFromValue(item))
                    inc(i)
            else: InvalidOperationError("*",$(l.kind),$(r.kind))
        else:
            InvalidOperationError("*",$(l.kind),$(r.kind))

proc `/`(l: Value, r: Value): Value {.inline.} = 
    {.computedGoto.}
    case l.kind
        of stringValue:
            case r.kind
                of integerValue: 
                    var k=0
                    var resp=""
                    result = valueFromArray(@[])
                    while k<l.s.len:
                        resp &= l.s[k]
                        if ((k+1) mod r.i)==0: 
                            result.a.add(valueFromString(resp))
                            resp = ""
                        inc(k)
                
                of realValue: 
                    var k=0
                    var resp=""
                    result = valueFromArray(@[])
                    while k<l.s.len:
                        resp &= l.s[k]
                        if ((k+1) mod int(r.r))==0: 
                            result.a.add(valueFromString(resp))
                            resp = ""
                        inc(k)

                else: InvalidOperationError("/",$(l.kind),$(r.kind))
        of integerValue:
            result = case r.kind
                of integerValue: valueFromReal(l.i / r.i)
                of realValue: valueFromReal(float(l.i) / r.r)
                else: InvalidOperationError("/",$(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of integerValue: valueFromReal(l.r / float(r.i))
                of realValue: valueFromReal(l.r / r.r)
                else: InvalidOperationError("/",$(l.kind),$(r.kind))
        of arrayValue:
            result = valueFromArray(@[])
            if r.kind==integerValue or r.kind==realValue:
                var limit:int
                if r.kind==integerValue: limit = r.i
                else: limit = int(r.r)

                var k = 0
                var resp = valueFromArray(@[])
                while k<l.a.len:
                    resp.a.add(valueFromValue(l.a[k]))
                    if ((k+1) mod limit)==0: 
                        result.a.add(resp)
                        resp = valueFromArray(@[])
                    inc(k)

            else: InvalidOperationError("/",$(l.kind),$(r.kind))
        else:
            InvalidOperationError("/",$(l.kind),$(r.kind))

proc `%`(l: Value, r: Value): Value {.inline.} =
    {.computedGoto.}
    case l.kind
        of stringValue:
            case r.kind
                of integerValue: 
                    let le = (l.s.len mod r.i)
                    result = valueFromString(l.s[l.s.len-le..^1])
                
                of realValue: 
                    let le = (l.s.len mod int(r.r))
                    result = valueFromString(l.s[l.s.len-le..^1])

                else: InvalidOperationError("%",$(l.kind),$(r.kind))
        of integerValue:
            result = case r.kind
                of integerValue: valueFromInteger(l.i mod r.i)
                of bigIntegerValue: valueFromBigInteger(l.i mod r.bi)
                of realValue: valueFromInteger(l.i mod int(r.r))
                else: InvalidOperationError("%",$(l.kind),$(r.kind))
        of bigIntegerValue:
            result = case r.kind
                of integerValue: valueFromBigInteger(l.bi mod r.i)
                of bigIntegerValue: valueFromBigInteger(l.bi mod r.bi)
                else: InvalidOperationError("%",$(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of integerValue: valueFromInteger(int(l.r) mod r.i)
                of realValue: valueFromInteger(int(l.r) mod int(r.r))
                else: InvalidOperationError("%",$(l.kind),$(r.kind))
        of arrayValue:
            result = valueFromArray(@[])
            if r.kind==integerValue or r.kind==realValue:
                var limit:int
                if r.kind==integerValue: limit = r.i
                else: limit = int(r.r)

                let le = (l.a.len mod limit)
                result = valueFromArray(l.a[l.a.len-le..^1])
            else: InvalidOperationError("%",$(l.kind),$(r.kind))
        else:
            InvalidOperationError("%",$(l.kind),$(r.kind))

proc `^`(l: Value, r: Value): Value {.inline.} =
    {.computedGoto.}
    case l.kind
        of integerValue:
            result = case r.kind
                of integerValue: valueFromInteger(l.i ^ r.i)
                of realValue: valueFromInteger(l.i ^ int(r.r))
                else: InvalidOperationError("^",$(l.kind),$(r.kind))
        of bigIntegerValue:
            result = case r.kind
                of integerValue: valueFromBigInteger(l.bi ^ culong(r.i))
                else: InvalidOperationError("^",$(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of integerValue: valueFromInteger(int(l.r) ^ r.i)
                of realValue: valueFromReal(pow(l.r,r.r))
                else: InvalidOperationError("^",$(l.kind),$(r.kind))
        else:
            InvalidOperationError("^",$(l.kind),$(r.kind))

proc eq(l: Value, r: Value): bool {.inline.} =
    {.computedGoto.}
    case l.kind
        of stringValue:
            result = case r.kind
                of stringValue: l.s==r.s
                else: NotComparableError($(l.kind),$(r.kind))
                    
        of integerValue:
            result = case r.kind
                of integerValue: l.i==r.i
                of bigIntegerValue: l.i==r.bi
                of realValue: l.i==int(r.r)
                else: NotComparableError($(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of integerValue: int(l.r)==r.i
                of bigIntegerValue: int(l.r)==r.bi
                of realValue: l.r==r.r
                else: NotComparableError($(l.kind),$(r.kind))
        of booleanValue:
            result = case r.kind
                of booleanValue: l==r
                else: NotComparableError($(l.kind),$(r.kind))

        of arrayValue:
            case r.kind
                of arrayValue:
                    if l.a.len!=r.a.len: result = false
                    else:
                        var i=0
                        while i<l.a.len:
                            if not (l.a[i]==r.a[i]): return false
                            inc(i)
                        result = true
                else: NotComparableError($(l.kind),$(r.kind))
        of dictionaryValue:
            case r.kind
                of dictionaryValue:
                    if l.d.keys!=r.d.keys: result = false
                    else:
                        var i = 0
                        while i < l.d.list.len:
                            if not r.d.hasKey(l.d.list[i][0]): return false
                            else:
                                if not (l.d.list[i][1]==r.d.getValueForKey(l.d.list[i][0])): return false
                            inc(i)

                        result = true 
                else: NotComparableError($(l.kind),$(r.kind))

        else: NotComparableError($(l.kind),$(r.kind))

proc lt(l: Value, r: Value): bool {.inline.} =
    {.computedGoto.}
    case l.kind
        of stringValue:
            result = case r.kind
                of stringValue: l.s<r.s
                else: NotComparableError($(l.kind),$(r.kind))
                    
        of integerValue:
            result = case r.kind
                of integerValue: l.i<r.i
                of bigIntegerValue: l.i<r.bi
                of realValue: l.i<int(r.r)
                else: NotComparableError($(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of integerValue: int(l.r)<r.i
                of bigIntegerValue: int(l.r)<r.bi
                of realValue: l.r<r.r
                else: NotComparableError($(l.kind),$(r.kind))
        of arrayValue:
            result = case r.kind
                of arrayValue: l.a.len < r.a.len
                else: NotComparableError($(l.kind),$(r.kind))
        of dictionaryValue:
            result = case r.kind
                of dictionaryValue: l.d.keys.len < r.d.keys.len
                else: NotComparableError($(l.kind),$(r.kind))

        else: NotComparableError($(l.kind),$(r.kind))

proc gt(l: Value, r: Value): bool {.inline.} =
    {.computedGoto.}
    case l.kind
        of stringValue:
            result = case r.kind
                of stringValue: l.s>r.s
                else: NotComparableError($(l.kind),$(r.kind))
                    
        of integerValue:
            result = case r.kind
                of integerValue: l.i>r.i
                of bigIntegerValue: l.i>r.bi
                of realValue: l.i>int(r.r)
                else: NotComparableError($(l.kind),$(r.kind))
        of realValue:
            result = case r.kind
                of integerValue: int(l.r)>r.i
                of realValue: l.r>r.r
                else: NotComparableError($(l.kind),$(r.kind))
        of arrayValue:
            result = case r.kind
                of arrayValue: l.a.len > r.a.len
                else: NotComparableError($(l.kind),$(r.kind))
        of dictionaryValue:
            result = case r.kind
                of dictionaryValue: l.d.keys.len > r.d.keys.len
                else: NotComparableError($(l.kind),$(r.kind))

        else: NotComparableError($(l.kind),$(r.kind))

proc stringify*(v: Value, quoted: bool = true): string =
    {.computedGoto.}
    case v.kind
        of stringValue          :   
            if quoted: result = escape(v.s)
            else: result = v.s
        of integerValue         :   result = $(v.i)
        of bigIntegerValue      :   result = $(v.bi)
        of realValue            :   result = $(v.r)
        of booleanValue         :   result = $(v.b)
        of arrayValue           :
            result = "#("

            let items = v.a.map((x) => x.stringify())

            result &= items.join(" ")
            result &= ")"
        of dictionaryValue      :
            result = "#{ "
            
            let items = sorted(v.d.keys).map((x) => x & " " & v.d.getValueForKey(x).stringify())

            result &= items.join(", ")
            result &= " }"

            if result=="#{  }": result = "#{}"
        of functionValue        :   result = "<function>"
        of nullValue            :   result = "null"
        of anyValue             :   result = ""

#[----------------------------------------
    Functions
  ----------------------------------------]#

proc newUserFunction(s: StatementList, a: seq[string]): Function =
    result = Function(id: "", args: a, body: s, hasContext: false, parentThis: nil, parentContext: nil)

proc setFunctionName(f: Function, s: string) {.inline.} =
    f.id = s
    f.hasContext = true

proc functionConstraints*(n: string): seq[seq[ValueKind]] =
    var i = 0
    while i < SystemFunctions.len:
        if SystemFunctions[i].name == n:
            return SystemFunctions[i].req
        inc(i)
    result = nil

proc getSystemFunction*(n: string): int {.inline.} =
    var i = 0
    while i < SystemFunctions.len:
        if SystemFunctions[i].name==n:
            return i
        inc(i)

    result = -1

proc getNameOfSystemFunction*(n: int): cstring {.exportc.} =
    result = SystemFunctions[n].name

proc execute(f: Function, v: Value): Value {.inline.} =
    if f.hasContext:
        if Stack.len == 1: addContext()

        var oldSeq:Context
        oldSeq = Stack[1]
        #shallowCopy(oldSeq,Stack[1])
        if f.args.len>0:
            if v.kind == AV: addContextWith(zip(f.args,v.a))
            else: addContextWith(f.args[0],v)
        else: addContextWith("&",v)

        try                         : result = f.body.execute()
        except ReturnValue as ret   : result = ret.value
        finally                     : 
            Stack[1]=oldSeq
            #shallowCopy(Stack[1],oldSeq)
            if Stack[1].list.len==0: popContext()
    else:
        var stored: Value = nil
        if v!=NULL:
            if f.args.len>0:
                if v.kind == AV: 
                    var i = 0
                    while i<f.args.len:
                        discard setSymbol(f.args[i],v.a[i],redefine=true)
                        inc(i)
                else: discard setSymbol(f.args[0],v,redefine=true)
            else: stored = getAndSetSymbol("&",v)

        try                         : result = f.body.execute()
        except ReturnValue as ret   : raise
        finally                     : 
            if stored!=nil: discard setSymbol("&",stored)

proc validate(xl: ExpressionList, name: string, req: seq[seq[ValueKind]]): seq[Value] {.inline.} =
    result = xl.evaluate(forceArray=true).a

    if not req.contains(result.map((x) => x.kind)):

        let expected = req.map((x) => x.map((y) => ($y).replace("Value","")).join(",")).join(" or ")
        let got = result.map((x) => ($(x.kind)).replace("Value","")).join(",")
        
        IncorrectArgumentValuesError(name, expected, got)

proc validateOne(x: Expression, name: string, req: openArray[ValueKind]): Value =
    result = x.evaluate()

    if not (result.kind in req):
        let expected = req.map((x) => $(x)).join(" or ")
        IncorrectArgumentValuesError(name, expected, $(result.kind))

proc getOneLineDescription*(f: SystemFunction): string =
    let args = f.req.map((x) => "(" & x.map(proc (y: ValueKind): string = ($y).replace("Value","")).join(",") & ")").join(" / ")
    let ret = "[" & f.ret.join(",").replace("Value","") & "]"
    result = alignLeft("\e[1m" & f.name & "\e[0m",20) & " " & args & " -> " & ret

proc getFullDescription*(f: SystemFunction): string =
    let args = f.req.map((x) => "(" & x.map((y) => ($y).replace("Value","")).join(",") & ")").join(" / ")
    let ret = "[" & f.ret.join(",").replace("Value","") & "]"
    result  = "Function : \e[1m" & f.name & "\e[0m" & "\n"
    result &= "       # : " & f.desc & "\n\n"
    result &= "   usage : " & f.name & " " & args & "\n"
    result &= "        -> " & ret & "\n"

#[----------------------------------------
    KeyPath
  ----------------------------------------]#

proc keypathFromIdId(a: cstring, b: cstring): KeyPath {.exportc.} =
    result = KeyPath(parts: @[KeyPathPart(kind: stringKeyPathPart, s: $a), KeyPathPart(kind: stringKeyPathPart, s: $b)])

proc keypathFromIdInteger(a: cstring, b: cstring): KeyPath {.exportc.} =
    var intValue: int
    discard parseInt($b, intValue)

    result = KeyPath(parts: @[KeyPathPart(kind: stringKeyPathPart, s: $a), KeyPathPart(kind: integerKeyPathPart, i: intValue)])

proc keypathFromIdInline(a: cstring, b: Argument): KeyPath {.exportc.} =
    result = KeyPath(parts: @[KeyPathPart(kind: stringKeyPathPart, s: $a), KeyPathPart(kind: inlineKeyPathPart, a: b)])

proc keypathFromInlineId(a: Argument, b: cstring): KeyPath {.exportc.} =
    result = KeyPath(parts: @[KeyPathPart(kind: inlineKeyPathPart, a: a), KeyPathPart(kind: stringKeyPathPart, s: $b)])

proc keypathFromInlineInteger(a: Argument, b: cstring): KeyPath {.exportc.} =
    var intValue: int
    discard parseInt($b, intValue)

    result = KeyPath(parts: @[KeyPathPart(kind: inlineKeyPathPart, a: a), KeyPathPart(kind: integerKeyPathPart, i: intValue)])

proc keypathFromInlineInline(a: Argument, b: Argument): KeyPath {.exportc.} =
    result = KeyPath(parts: @[KeyPathPart(kind: inlineKeyPathPart, a: a), KeyPathPart(kind: inlineKeyPathPart, a: b)])

proc keypathByAddingIdToKeypath(k: KeyPath, a: cstring):KeyPath {.exportc.} =
    k.parts.add(KeyPathPart(kind: stringKeyPathPart, s: $a))
    result = k

proc keypathByAddingIntegerToKeypath(k: KeyPath, a: cstring):KeyPath {.exportc.} =
    var intValue: int
    discard parseInt($a, intValue)

    k.parts.add(KeyPathPart(kind: integerKeyPathPart, i: intValue))
    result = k

proc keypathByAddingInlineToKeypath(k: KeyPath, a: Argument): KeyPath {.exportc.} =
    k.parts.add(KeyPathPart(kind: inlineKeyPathPart, a: a))
    result = k

#[----------------------------------------
    Expression
  ----------------------------------------]#

proc expressionFromArgument(a: Argument): Expression {.exportc.} =
    result = Expression(kind: argumentExpression, a: a)

proc expressionFromExpressions(l: Expression, op: cstring, r: Expression): Expression {.exportc.} =
    result = Expression(kind: normalExpression, left: l, op: parseEnum[ExpressionOperator]($op), right: r)

proc evaluate(x: Expression): Value {.inline.} =
    case x.kind
        of argumentExpression:
            result = x.a.getValue()
        of normalExpression:
            var left = x.left.evaluate()
            var right: Value

            if x.right!=nil: right = x.right.evaluate()
            else: return left
            {.computedGoto.}
            case x.op
                of PLUS_SG  : result = left + right
                of MINUS_SG : result = left - right
                of MULT_SG  : result = left * right
                of DIV_SG   : result = left / right
                of MOD_SG   : result = left % right
                of POW_SG   : result = left ^ right
                of EQ_OP    : result = valueFromBoolean(left.eq(right))
                of LT_OP    : result = valueFromBoolean(left.lt(right))
                of GT_OP    : result = valueFromBoolean(left.gt(right))
                of LE_OP    : result = valueFromBoolean(left.lt(right) or left.eq(right))
                of GE_OP    : result = valueFromBoolean(left.gt(right) or left.eq(right))
                of NE_OP    : result = valueFromBoolean(not (left.eq(right)))

#[----------------------------------------
    ExpressionList
  ----------------------------------------]#

proc newExpressionList: ExpressionList {.exportc.} =
    result = ExpressionList(list: @[])

proc newExpressionListWithExpression(x: Expression): ExpressionList {.exportc.} =
    result = ExpressionList(list: @[x])

proc copyExpressionList(xl: ExpressionList): ExpressionList {.exportc.} =
    result = ExpressionList(list: xl.list)

proc addExpressionToExpressionList(x: Expression, xl: ExpressionList): ExpressionList {.exportc.} =
    xl.list.add(x)
    result = xl

proc addExpressionToExpressionListFront(x: Expression, xl: ExpressionList): ExpressionList {.exportc.} =
    xl.list.insert(x,0)
    result = xl

proc evaluate(xl: ExpressionList, forceArray: bool=false): Value = 
    if forceArray or xl.list.len>1:
        result = valueFromArray(xl.list.map((x) => x.evaluate()))
    else:
        if xl.list.len==1:
            result = xl.list[0].evaluate()
        else:
            result = valueFromArray(@[])

#[----------------------------------------
    Argument
  ----------------------------------------]#

proc argumentFromIdentifier(i: cstring): Argument {.exportc.} =
    Argument(kind: identifierArgument, i: $i)

proc argumentFromCommandIdentifier(i: cint): Argument {.exportc.} =
    Argument(kind: identifierArgument, i: SystemFunctions[i].name)

proc argumentFromStringLiteral(l: cstring): Argument {.exportc.} =
    if ConstStrings.hasKey($l):
        result = ConstStrings[$l]
    else:
        result = Argument(kind: literalArgument, v: valueFromString(unescape($l).replace("\\n","\n")))
        ConstStrings[$l] = result

proc argumentFromIntegerLiteral(l: cstring): Argument {.exportc.} =
    Argument(kind: literalArgument, v: valueFromInteger($l))

proc argumentFromRealLiteral(l: cstring): Argument {.exportc.} =
    Argument(kind: literalArgument, v: valueFromReal($l))

proc argumentFromBooleanLiteral(l: cstring): Argument {.exportc.} =
    if l=="true": ConstTrue
    else: ConstFalse

proc expressionFromKeyPathPart(part: KeyPathPart, isFirst: bool = false): Expression =
    case part.kind
        of stringKeyPathPart:
            if isFirst: result = expressionFromArgument(argumentFromIdentifier(part.s))
            else: result = expressionFromArgument(argumentFromStringLiteral("\"" & part.s & "\""))
        of integerKeyPathPart:
            result = expressionFromArgument(argumentFromIntegerLiteral($(part.i)))
        of inlineKeyPathPart:
            result = expressionFromArgument(part.a)

proc argumentFromKeypath(k: KeyPath): Argument {.exportc.} =
    var exprA = expressionFromKeyPathPart(k.parts[0], true)

    var i = 1
    while i<k.parts.len:
        var exprB = expressionFromKeyPathPart(k.parts[i], false)
        var lst = newExpressionList()

        discard addExpressionToExpressionList(exprA, lst)
        discard addExpressionToExpressionList(exprB, lst)
        exprA = expressionFromArgument(argumentFromInlineCallLiteral(statementFromCommand(1,lst,0)))

        inc(i)
        
    result = exprA.a

proc argumentFromNullLiteral(): Argument {.exportc.} =
    ConstNull

proc argumentFromArrayLiteral(l: ExpressionList): Argument {.exportc.} =
    if l==nil: Argument(kind: arrayArgument, a: newExpressionList())
    else: Argument(kind: arrayArgument, a: l)

proc argumentFromDictionaryLiteral(l: StatementList): Argument {.exportc.} =
    Argument(kind: dictionaryArgument, d: l)

proc argumentFromFunctionLiteral(l: StatementList, args: cstring = ""): Argument {.exportc.} =
    if args=="": Argument(kind: functionArgument, f: newUserFunction(l,@[]))
    else: Argument(kind: functionArgument, f: newUserFunction(l,($args).split(",")))

proc argumentFromInlineCallLiteral(l: Statement): Argument {.exportc.} =
    Argument(kind: inlineCallArgument, c: l)

proc getValue(a: Argument): Value {.inline.} =
    {.computedGoto.}
    case a.kind
        of identifierArgument:
            result = getSymbol(a.i)
            if result == nil: SymbolNotFoundError(a.i)
        of literalArgument:
            result = a.v
        of arrayArgument:
            result = a.a.evaluate(forceArray=true)
        of dictionaryArgument:
            var ret = valueFromDictionary(Context(list: @[]))

            addContext()
            for statement in a.d.list:
                discard statement.execute(ret)
            popContext()

            result = ret
        of functionArgument:
            result = valueFromFunction(a.f)
        of inlineCallArgument:
            result = a.c.execute()

#[----------------------------------------
    Statement
  ----------------------------------------]#

proc statementFromCommand(i: cint, xl: ExpressionList, l: cint): Statement {.exportc.} =
    result = Statement(kind: commandStatement, code: i, arguments: xl, pos: l)

proc statementFromAssignment(i: cstring, xl: ExpressionList, l: cint): Statement {.exportc.} =
    result = Statement(kind: assignmentStatement, symbol: $i, rValue: xl, pos: l)

proc statementFromExpression(x: Expression, l: cint=0): Statement {.exportc.} =
    result = Statement(kind: expressionStatement, expression: x, pos: l)

proc statementFromExpressions(i: cstring, xl: ExpressionList, l: cint=0): Statement {.exportc.} =
    result = Statement(kind: normalStatement, id: $i, expressions: xl, pos: l)

proc executeAssign(s: Statement, parent: Value = nil): Value {.inline.} =
    var ev = s.expressions.evaluate()

    if parent==nil:
        if ev.kind==functionValue:
            setFunctionName(ev.f,s.id)

        result = setSymbol(s.id, ev)
    else:
        parent.d.updateOrSet(s.id, ev)

        if ev.kind==functionValue:
            ev.f.parentThis = ev
            ev.f.parentContext = parent.d    

        result = ev    

proc execute(stm: Statement, parent: Value = nil): Value {.inline.} = 
    case stm.kind
        of assignmentStatement:
            result = stm.executeAssign(parent)
        of commandStatement:
            include system
        of expressionStatement:
            result = stm.expression.evaluate()
        of normalStatement:
            let sym = getSymbol(stm.id)
            if sym==nil: SymbolNotFoundError(stm.id)
            else: 
                if sym.kind==FV:
                    result = sym.f.execute(stm.expressions.evaluate(forceArray=true))
                else: 
                    if stm.expressions.list.len > 0:
                        FunctionNotFoundError(stm.id)
                    else:
                        result = expressionFromArgument(argumentFromIdentifier(stm.id)).evaluate()
            

#[----------------------------------------
    StatementList
  ----------------------------------------]#

proc newStatementList: StatementList {.exportc.} =
    result = StatementList(list: @[])

proc newStatementListWithStatement(s: Statement): StatementList {.exportc.} =
    result = StatementList(list: @[s])

proc addStatementToStatementList(s: Statement, sl: StatementList): StatementList {.exportc.} =
    sl.list.add(s)
    result = sl

proc execute(sl: StatementList): Value = 
    var i = 0
    while i < sl.list.len:
        try:
            result = sl.list[i].execute()
        except ReturnValue:
            raise
        except Exception as e:
            if IsRepl: raise
            else: runtimeError(e.msg, FileName, sl.list[i].pos, IsRepl)

        inc(i)

#[######################################################
    Store management
  ======================================================]#

template initializeConsts() =
    ConstStrings    = newTable[string,Argument]()
    ConstTrue       = Argument(kind: literalArgument, v: valueFromBoolean(true))
    ConstFalse      = Argument(kind: literalArgument, v: valueFromBoolean(false))
    ConstNull       = Argument(kind: literalArgument, v: valueFromNull())

#[######################################################
    MAIN ENTRY
  ======================================================]#

proc setup*(args: seq[string] = @[]) = 
    initializeConsts()

    addContext() # global
    addContextWith("&", valueFromArray(args.map((x) => valueFromString(x))))

proc runString*(src:string): string =
    var buff = yy_scan_string(src)

    yylineno = 0
    yyfilename = "-"
    FileName = "-"
    IsRepl = true

    yy_switch_to_buffer(buff)

    MainProgram = nil
    discard yyparse()

    yy_delete_buffer(buff)

    try:
        result = MainProgram.execute().stringify()
    except Exception as e:
        runtimeError(e.msg, FileName, 0, IsRepl)


proc runScript*(scriptPath:string, args: seq[string], includePath:string="", warnings:bool=false) = 
    if not fileExists(scriptPath): 
        cmdlineError("path not found: '" & scriptPath & "'")

    setup(args)

    yylineno = 0
    yyfilename = scriptPath
    FileName = scriptPath
    IsRepl = false

    let success = open(yyin, scriptPath)
    if not success:
        cmdlineError("something went wrong when opening file")
    else:
        #benchmark "parsing":
        discard yyparse()

        discard MainProgram.execute()
