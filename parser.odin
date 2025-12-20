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
    },

    formatter : struct {
        integer_postprocessor : proc(this: string, info: IntegerInfo, out: ^Builder),  // = digit_grouper
        float_postprocessor   : proc(this: string, info: FloatInfo, out: ^Builder)     // = nil
    }
}

File :: struct {
    path   : string,
    text   : string,
    tokens : Tokens,
    alloc  : Allocator, // TODO should not exist / be used extremely rarely!
}

Table :: map [string] Value
List  :: [dynamic] Value
Date  :: dates.Date 

Value :: struct {
    tokens : [] ^string,
    parsed : union { int, f64, bool, string, Date, ^List, ^Table },
    hash   : Hash, // xxhash of the original value
}

Infinity : f64 = 1e5000
NaN := transmute(f64) ( transmute(i64) Infinity | 1 ) 

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

    validator := make_validator(file)
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
    if io.root == nil { io.root = new(Table, io.alloc) }

    table  := io.root
    tokens := file.tokens[:]
    for {
        should_continue := 
            handle_assign (io, &tokens,  table) ||
            handle_section(io, &tokens, &table) ||
            handle_extras (io, &tokens,  table)
    
        if !should_continue do break
    }   
}


// These should be validated by the tokenizer
// So, they are just here not to hang the program
// On syntax errors which are not yet implemented
@(private="file")
handle_extras :: proc(io: ^IO, tokens: ^[] string, out: ^Table) -> bool {
    if peek(tokens)^ == "" do return false
    next(tokens)
    return true
}
@(private="file")
handle_extra  :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    if peek(tokens)^ == "" do return false
    next(tokens)
    return true
}


@(private="file")
handle_section :: proc(io: ^IO, tokens: ^[] string, out: ^^Table) -> bool {
    if peek(tokens)^ != "[" do return false
    next(tokens); // '['
    name  := next(tokens)
    table := new(Table, io.alloc)

    out^ = io.root
    out^^[name^] = { tokens = t(io, { name }), parsed = table } 
    out^ = table

    next(tokens); // ']'
    return true
}

@(private="file")
handle_assign :: proc(io: ^IO, tokens: ^[] string, out: ^Table) -> bool {
    if peek(tokens, 1)^ != "=" do return false
    key := next(tokens)
    next(tokens) // '='

    value: Value
    ok :=
        handle_integer(io, tokens, &value) ||
        handle_float  (io, tokens, &value) || 
        handle_bool   (io, tokens, &value) ||
        handle_date   (io, tokens, &value) ||
        handle_string (io, tokens, &value) || 
        handle_table  (io, tokens, &value) || 
        handle_list   (io, tokens, &value) ||
        handle_extra  (io, tokens, &value)

    out^[key^] = value
    return ok
}

@(private="file")
handle_table :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    if peek(tokens)^ != "{" do return false

    result := new(Table, context.allocator)

    next(tokens) // '{'
    for !any_of(peek(tokens)^, "}", "") {

        if peek(tokens)^ == "," { next(tokens); continue }
        
        ok := 
            handle_assign(io, tokens, result) ||
            handle_extras(io, tokens, result)
    }
    next(tokens) // '}'

    out^ = { tokens = t(io, { /* child tokens are stored in children! */ }), parsed = result }
    return true
}

@(private="file")
handle_list :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    if peek(tokens)^ != "[" do return false

    result := new(List, context.allocator)
    all_tokens := make([dynamic] ^string, context.allocator) // TODO I hate my life.

    next(tokens) // '['
    for !any_of(peek(tokens)^, "]", "") {

        if peek(tokens)^ == "," { next(tokens); continue }
        
        element: Value
        ok :=
            handle_integer(io, tokens, &element) ||
            handle_float  (io, tokens, &element) || 
            handle_bool   (io, tokens, &element) ||
            handle_date   (io, tokens, &element) ||
            handle_string (io, tokens, &element) || 
            handle_table  (io, tokens, &element) ||
            handle_list   (io, tokens, &element) ||
            handle_extra  (io, tokens, &element)

        for token in element.tokens { append(&all_tokens, token) }
        append(result, element) 
    }
    next(tokens) // ']'

    out^ = { tokens = all_tokens[:], parsed = result }

    return true
}

@(private="file")
handle_integer :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    integer, ok := parse_int(peek(tokens)^)
    if !ok do return false
    out.tokens = t(io, { next(tokens) })
    out.parsed = integer
    return true
}

@(private="file")
handle_float :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    text := peek(tokens)^

    if len(text) == 4 {
        if text[0] == '-' { if text[1:] == "inf" { out^ = { tokens = t(io, { next(tokens) }), parsed = -Infinity }; return true } }
        if text[0] == '+' { if text[1:] == "inf" { out^ = { tokens = t(io, { next(tokens) }), parsed = +Infinity }; return true } }
        if text[1:] == "nan" { out^ = { tokens = t(io, { next(tokens) }), parsed = NaN }; return true }
    }

    if text == "nan" { out^ = { tokens = t(io, { next(tokens) }), parsed = NaN };      return true }
    if text == "inf" { out^ = { tokens = t(io, { next(tokens) }), parsed = +Infinity }; return true }

    float, ok := parse_f64(peek(tokens)^)
    if !ok { return false }
    out.tokens = t(io, { next(tokens) })
    out.parsed = float
    return true
}

@(private="file")
handle_bool :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    text := peek(tokens)^
    if text == "true"  { out^ = { tokens = t(io, { next(tokens) }), parsed = true  }; return true }
    if text == "false" { out^ = { tokens = t(io, { next(tokens) }), parsed = false }; return true }
    return false
}

@(private="file")
handle_date :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    if !dates.is_date_lax(peek(tokens)^) { return false }
    
    a_tok := next(tokens)
    a, err1 := dates.from_string(a_tok^)
    
    if dates.is_date_lax(peek(tokens)^) {
        b_tok := next(tokens)
        b, err2 := dates.from_string(b_tok^)

        if err1 != .NONE do return false
        if err2 != .NONE do return false
            
        out.tokens = t(io, { a_tok, b_tok })
        out.parsed = dates.combine(a, b)

    } else {
        if err1 != .NONE do return false
    
        out.tokens = t(io, { a_tok })
        out.parsed = a
    }

    return true
}

@(private="file")
handle_string :: proc(io: ^IO, tokens: ^[] string, out: ^Value) -> bool {
    text := peek(tokens)^
    if first_rune(text) != '"' && first_rune(text) != '\'' { return false }
    out^ = { tokens = t(io, { next(tokens) }), parsed = text }
    return true
}

@private // (used elsewhere in the project)
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

@(private="file")
t :: proc(io: ^IO, arr: [] ^string) -> [] ^string {
    out := make_slice(type_of(arr), len(arr), io.alloc)
    for _, i in arr { out[i] = arr[i] }
    return out
}

