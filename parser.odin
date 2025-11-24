package utoml

import "core:fmt"
import "dates"


IO :: struct {
    userfiles : [dynamic] File,
    defaults  : [dynamic] Tokens,
    root      : ^Table,
    alloc     : Allocator,

    error_handlers : struct {
        tokenizer  : ErrorHandler,
        parser     : ErrorHandler,
    }
}

File :: struct {
    path   : string,
    text   : string,
    tokens : Tokens,
    alloc  : Allocator,
}


Table :: map [string] Value
List  :: [dynamic] Value
Date  :: dates.Date 

ErrorValue :: struct {
    date_error: dates.DateError
}

Value :: struct {
    tokens : [] ^string,
    parsed : union { int, f64, bool, string, Date, ^List, ^Table, ErrorValue }
}

empty_token := ""

auto_init_io :: proc(io: ^IO) {
    set_default :: proc(v: ^$T, d: T) { v^ = v^ if v^ != { } else d }
    set_default(&io.alloc, make_arena())

    {   using io.error_handlers
        set_default(&tokenizer, default_tokenizer_handler)
    }
}

parse_userfile :: proc(io: ^IO, filename: string) -> (ok: bool) {
    check_nil_io(io)
    auto_init_io(io)

    file_alloc := context.allocator
    text, err1 := read_entire_file(filename, file_alloc)
    path, err2 := absolute_path(filename, file_alloc)
    tokens := tokenize(string(text))

    file: File = {
        path   = path,
        text   = string(text),
        tokens = tokens,
        alloc  = file_alloc
    }
    append(&io.userfiles, file)

    validator := make_validator(file, io.error_handlers.tokenizer)
    results   := make([dynamic] Validator, validator.allocator)

    validate_tokenizer(&validator, tokens, &results)
    ok = digest_validator(results[:])
    free_all(validator.allocator)
    if !ok do return false

    parse(io, file)
    return true
}

@private
parse :: proc(io: ^IO, file: File) {
    if io.root == nil {
        io.root = new(Table, io.alloc)
    }

    table  := io.root
    tokens := file.tokens[:]
    for {
        should_continue := 
            handle_assign(&tokens, table)
    
        if !should_continue do break
    }   
}

@(private="file")
handle_assign :: proc(tokens: ^[] string, out: ^Table) -> bool {
    if peek(tokens, 1)^ != "=" do return false
    key := next(tokens)
    next(tokens) // '='

    value: Value
    ok :=
        handle_integer(tokens, &value) ||
        handle_float  (tokens, &value) || 
        handle_bool   (tokens, &value) ||
        handle_date   (tokens, &value) ||
        handle_string (tokens, &value) || 
        handle_table  (tokens, &value) || 
        handle_list   (tokens, &value)

    if ok { out^[key^] = value }
    return ok
}

@(private="file")
handle_table :: proc(tokens: ^[] string, out: ^Value) -> bool {
    if peek(tokens)^ != "{" do return false

    result := new(Table, context.allocator)

    next(tokens) // '{'
    for !any_of(peek(tokens)^, "}", "") {

        if peek(tokens)^ == "," { next(tokens); continue }
        
        ok := handle_assign(tokens, result)
        if !ok { return false }
    }
    next(tokens) // '}'

    out^ = { tokens = { /* tables do not contain child tokens */ }, parsed = result }

    return true
}

@(private="file")
handle_list :: proc(tokens: ^[] string, out: ^Value) -> bool {
    if peek(tokens)^ != "[" do return false

    result := new(List, context.allocator)
    all_tokens := make([dynamic] ^string, context.allocator) // TODO I hate my life.

    next(tokens) // '['
    for !any_of(peek(tokens)^, "]", "") {

        if peek(tokens)^ == "," { next(tokens); continue }
        
        element: Value
        ok :=
            handle_integer(tokens, &element) ||
            handle_float  (tokens, &element) || 
            handle_bool   (tokens, &element) ||
            handle_date   (tokens, &element) ||
            handle_string (tokens, &element) || 
            handle_table  (tokens, &element) ||
            handle_list   (tokens, &element)
        if !ok { return false }

        for token in element.tokens { append(&all_tokens, token) }
        append(result, element) 
    }
    next(tokens) // ']'

    out^ = { tokens = all_tokens[:], parsed = result }

    return true
}

@(private="file")
handle_integer :: proc(tokens: ^[] string, out: ^Value) -> bool {
    integer, ok := parse_int(peek(tokens)^)
    if !ok do return false
    out.tokens = { next(tokens) }
    out.parsed = integer
    return true
}

@(private="file")
handle_float :: proc(tokens: ^[] string, out: ^Value) -> bool {
    text := peek(tokens)^

    Infinity : f64 = 1e5000
    NaN := transmute(f64) ( transmute(i64) Infinity | 1 ) 

    if len(text) == 4 {
        if text[0] == '-' { if text[1:] == "inf" { out^ = { tokens = { next(tokens) }, parsed = -Infinity }; return true } }
        if text[0] == '+' { if text[1:] == "inf" { out^ = { tokens = { next(tokens) }, parsed = +Infinity }; return true } }
        if text[1:] == "nan" { out^ = { tokens = { next(tokens) }, parsed = +NaN }; return true }
    }

    if text == "nan" { out^ = { tokens = { next(tokens) }, parsed = +NaN };      return true }
    if text == "inf" { out^ = { tokens = { next(tokens) }, parsed = +Infinity }; return true }

    float, ok := parse_f64(peek(tokens)^)
    if !ok { return false }
    out.tokens = { next(tokens) }
    out.parsed = float
    return true
}

@(private="file")
handle_bool :: proc(tokens: ^[] string, out: ^Value) -> bool {
    text := peek(tokens)^
    if text == "true"  { out^ = { tokens = { next(tokens) }, parsed = true  }; return true }
    if text == "false" { out^ = { tokens = { next(tokens) }, parsed = false }; return true }
    return false
}

@(private="file")
handle_date :: proc(tokens: ^[] string, out: ^Value) -> bool {
    if !dates.is_date_lax(peek(tokens)^) { return false }
    
    // TODO: handle errors... somehow...
    // probley just keep IO.date_errors: [] ^token

    a_tok := next(tokens)
    a, err1 := dates.from_string(a_tok^)
    
    if dates.is_date_lax(peek(tokens)^) {
        b_tok := next(tokens)
        b, err2 := dates.from_string(b_tok^)

        if err1 != .NONE do return false
        if err2 != .NONE do return false
            
        out.tokens = { a_tok, b_tok }
        out.parsed = dates.combine(a, b)
    } else {
        if err1 != .NONE do return false
    
        out.tokens = { a_tok }
        out.parsed = a
    }

    return true
}

@(private="file")
handle_string :: proc(tokens: ^[] string, out: ^Value) -> bool {
    text := peek(tokens)^
    if first_rune(text) != '"' && first_rune(text) != '\'' { return false }
    out^ = { tokens = { next(tokens) }, parsed = text }
    return true
}

@(private="file")
peek :: proc(tokens: ^[] string, n := 0) -> ^string {
    n := n
    for &token in tokens^ {
        if len(token) > 0 && 
           !contains(NONPRINTABLES, first_rune(token)) {
            n -= 1
        } 
        if n < 0 {
            return &token
        }
    }
    return &empty_token
}

@(private="file")
next :: proc(tokens: ^[] string) -> ^string {
    for len(tokens) > 0 {
        token := &tokens^[0]
        defer tokens^ = tokens^[1:]
        if len(token^) > 0 && !contains(NONPRINTABLES, first_rune(token^)) {
            return token
        }
    }
    return &empty_token
}
