interface ParserStr
  exposes [
    RawStr,
    runStr,
    runPartialStr,
    runRaw,
    runPartialRaw,
    string,
    codepoint,
    scalar,
    oneOf,
    digit,
    digits,
  ]
  imports [ParserCore.{Parser, const, fail, map, map2, apply, many, oneOrMore, run, runPartial, buildPrimitiveParser, between}]

# Specific string-based parsers:

RawStr : List U8

strFromRaw : RawStr -> Str
strFromRaw = \rawStr ->
  rawStr
  |> Str.fromUtf8
  |> Result.withDefault "Unexpected problem while turning a List U8 (that was originally a Str) back into a Str. This should never happen!"

strToRaw : Str -> RawStr
strToRaw = \str ->
  str |> Str.toUtf8

strFromScalar : U32 -> Str
strFromScalar = \scalarVal ->
  (Str.appendScalar "" (Num.intCast scalarVal))
  |> Result.withDefault  "Unexpected problem while turning a U32 (that was probably originally a scalar constant) into a Str. This should never happen!"

strFromCodepoint : U8 -> Str
strFromCodepoint = \cp ->
  strFromRaw [cp]

## Runs a parser against the start of a list of scalars, allowing the parser to consume it only partially.
runPartialRaw : Parser RawStr a, RawStr -> Result {val: a, input: RawStr} [ParsingFailure Str]
runPartialRaw = \parser, input ->
  runPartial parser input

## Runs a parser against the start of a string, allowing the parser to consume it only partially.
##
## - If the parser succeeds, returns the resulting value as well as the leftover input.
## - If the parser fails, returns `Err (ParsingFailure msg)`
runPartialStr : Parser RawStr a, Str -> Result {val: a, input: Str} [ParsingFailure Str]
runPartialStr = \parser, input ->
  parser
  |> runPartialRaw (strToRaw input)
  |> Result.map \{val: val, input: restRaw} ->
    {val: val, input: (strFromRaw restRaw)}

## Runs a parser against a string, requiring the parser to consume it fully.
##
## - If the parser succeeds, returns `Ok val`
## - If the parser fails, returns `Err (ParsingFailure msg)`
## - If the parser succeeds but does not consume the full string, returns `Err (ParsingIncomplete leftover)`
runRaw : Parser RawStr a, RawStr -> Result a [ParsingFailure Str, ParsingIncomplete RawStr]
runRaw = \parser, input ->
  run parser input (\leftover -> List.len leftover == 0)

runStr : Parser RawStr a, Str -> Result a [ParsingFailure Str, ParsingIncomplete Str]
runStr = \parser, input ->
  parser
  |> runRaw (strToRaw input)
  |> Result.mapErr \problem ->
      when problem is
        ParsingFailure msg ->
          ParsingFailure msg
        ParsingIncomplete leftoverRaw ->
          ParsingIncomplete (strFromRaw leftoverRaw)

codepoint : U8 -> Parser RawStr U8
codepoint = \expectedCodePoint ->
  # fail "x"
  buildPrimitiveParser \input ->
    {before: start, others: inputRest} = List.split input 1
    if List.isEmpty start then
        errorChar = strFromCodepoint expectedCodePoint
        Err (ParsingFailure "expected char `\(errorChar)` but input was empty")
        # Ok {val: 0, input: inputRest}
    else
      if start == (List.single expectedCodePoint) then
        Ok {val: expectedCodePoint, input: inputRest}
      else
        errorChar = strFromCodepoint expectedCodePoint
        otherChar = strFromRaw start
        inputStr = strFromRaw input
        Err (ParsingFailure "expected char `\(errorChar)` but found `\(otherChar)`.\n While reading: `\(inputStr)`")
        # Ok {val: 0, input: inputRest}

stringRaw : List U8 -> Parser RawStr (List U8)
stringRaw = \expectedString ->
  buildPrimitiveParser \input ->
    {before: start, others: inputRest} = List.split input (List.len expectedString)
    if start == expectedString then
      Ok {val: expectedString, input: inputRest}
    else
      errorString = strFromRaw expectedString
      otherString = strFromRaw start
      inputString = strFromRaw input
      Err (ParsingFailure "expected string `\(errorString)` but found `\(otherString)`.\nWhile reading: \(inputString)")

string : Str -> Parser RawStr Str
string = \expectedString ->
  (strToRaw expectedString)
  |> stringRaw
  |> map (\_val -> expectedString)

scalar : U32 -> Parser RawStr U32
scalar = \expectedScalar ->
  expectedScalar
  |> strFromScalar
  |> string
  |> map (\_ -> expectedScalar)

betweenBraces : Parser RawStr a -> Parser RawStr a
betweenBraces = \parser ->
  between parser (scalar '[') (scalar ']')


digit : Parser RawStr U8
digit =
  digitParsers =
      List.range 0 10
      |> List.map \digitNum ->
          digitNum + 48
          |> codepoint
          |> map (\_ -> digitNum)
  oneOf digitParsers

# NOTE: Currently happily accepts leading zeroes
digits : Parser RawStr (Int *)
digits =
  oneOrMore digit
  |> map \digitsList ->
    digitsList
    |> List.map Num.intCast
    |> List.walk 0 (\sum, digitVal -> 10 * sum + digitVal)

## Try a bunch of different parsers.
##
## The first parser which is tried is the one at the front of the list,
## and the next one is tried until one succeeds or the end of the list was reached.
##
## >>> boolParser : Parser RawStr Bool
## >>> boolParser = oneOf [string "true", string "false"] |> map (\x -> if x == "true" then True else False)
# NOTE: This implementation works, but is limited to parsing strings.
# Blocked until issue #3444 is fixed.
oneOf : List (Parser RawStr a) -> Parser RawStr a
oneOf = \parsers ->
  buildPrimitiveParser \input ->
    List.walkUntil parsers (Err (ParsingFailure "(no possibilities)")) \_, parser ->
      when runPartialRaw parser input is
        Ok val ->
          Break (Ok val)
        Err problem ->
          Continue (Err problem)
