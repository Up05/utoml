package utoml

import "core:fmt"
import "dates"

IO :: struct {
    filepath  : string,
    fulltext  : string,
    tokens    : Tokens,
    hashes    : [dynamic] u32,
    defaults  : ^Table,

    root      : ^Table,
    alloc     : Allocator,

    error_handlers : struct {
        tokenizer  : ErrorHandler,
    },

    formatter : struct {
        integer_postprocessor : proc(this: string, info: IntegerInfo, out: ^Builder),  // = digit_grouper
        float_postprocessor   : proc(this: string, info: FloatInfo,   out: ^Builder),  // = nil
    },

    // a set of space/linebreak/comma configurations found in the TOML's tables and arrays
    _list_format_cache: [dynamic] [] string, // TODO: later move to .formatter?
    _curr : int,
}

TokenHandle :: struct {
    token : i32,
    hash  : u32,
}

File :: struct {
    path   : string,
    text   : string,
    tokens : Tokens,
    hashes : [dynamic] u32,
}

Table :: map [string] Value
List  :: [dynamic] Value
Date  :: dates.Date 

ValueData :: union { int, f64, bool, string, Date, ^List, ^Table }
Value :: struct {
    tokens : [] TokenHandle,  
    parsed : ValueData,
    format : int,
    hash   : Hash, // xxhash of the original value
}

Infinity : f64 = 1e5000
NaN := transmute(f64) ( transmute(i64) Infinity | 1 ) 

parse_file :: proc(filepath: string, $default: string, alloc : Allocator = {}) -> (io: IO, ok: bool) {
    io.alloc = make_arena() if alloc == {} else alloc
    io.error_handlers.tokenizer = default_tokenizer_handler
    
    io.filepath = "compile time config"
    io.fulltext = default
    io.tokens   = tokenize(default)
    io.hashes   = make_hashes(len(io.tokens), io.alloc)

    {
        validator := make_validator(&io)
        results   := make([dynamic] Validator, validator.allocator)

        validate_tokenizer(&validator, io.tokens, &results)
        digest_validator(results[:]) or_return
        free_all(validator.allocator)

        parse(&io, &io.defaults)
    }

    path, err1 := absolute_path(filepath, io.alloc)
    file, err2 := read_entire_file(filepath, io.alloc)
    io.filepath = path
    io.fulltext = string(file)
    io.tokens   = tokenize(io.fulltext)
    io.hashes   = make_hashes(len(io.tokens), io.alloc)

    {
        validator := make_validator(&io)
        results   := make([dynamic] Validator, validator.allocator)

        validate_tokenizer(&validator, io.tokens, &results)
        digest_validator(results[:]) or_return
        free_all(validator.allocator)

        parse(&io, &io.root)
    }

    return io, true
}

@private
parse :: proc(io: ^IO, into: ^^Table) {
    if into^ == nil { into^ = new(Table, io.alloc) }

    this   := into^
    tokens := io.tokens[:]
    for {
        should_continue := 
            handle_section(io, &this) ||
            handle_assign (io,  this) ||
            handle_extras (io,  this)
    
        if !should_continue do break
    }   
    io._curr = 0
}


// These should be validated by the tokenizer
// So, they are just here not to hang the program
// On syntax errors which are not yet implemented
@(private="file")
handle_extras :: proc(io: ^IO, out: ^Table) -> bool {
    if token_text(io, peek(io)) == "" do return false
    next(io)
    return true
}
@(private="file")
handle_extra  :: proc(io: ^IO, out: ^Value) -> bool {
    if token_text(io, peek(io)) == "" do return false
    next(io)
    return true
}

@(private="file")
handle_section :: proc(io: ^IO, out: ^^Table) -> bool {
    if token_text(io, peek(io)) != "[" do return false
    open  := next(io); // '['
    name  := next(io)
    table := new(Table, io.alloc) // should be io.alloc, yup
    table^ = make(type_of(table^), io.alloc)
    close := next(io); // ']'

    // out^ = io.root
    out^^[token_text(io, name)] = make_value(io, { open, name, close }, table)
    out^ = table

    return true
}

@(private="file")
handle_assign :: proc(io: ^IO, out: ^Table) -> bool {
    if token_text(io, peek(io, 1)) != "=" do return false
    key := next(io)
    next(io) // '='

    value: Value
    ok :=
        handle_integer(io, &value) ||
        handle_float  (io, &value) || 
        handle_bool   (io, &value) ||
        handle_date   (io, &value) ||
        handle_string (io, &value) || 
        handle_table  (io, &value) || 
        handle_list   (io, &value) ||
        handle_extra  (io, &value)


    out^[token_text(io, key)] = value
    return ok
}

@(private="file")
handle_table :: proc(io: ^IO, out: ^Value) -> bool {
    if token_text(io, peek(io)) != "{" do return false

    result := new(Table, io.alloc)
    result^ = make(type_of(result^), io.alloc)

    latest_formatting: Ring(int, 16)

    open := next(io) // '{'
    for !any_of(token_text(io, peek(io)), "}", "") {

        if token_text(io, peek(io)) == "," { next(io); continue }
        
        ok := 
            handle_assign(io, result) ||
            handle_extras(io, result)

        fmt := handle_formatting(io)
        if fmt != -1 { ring_append(&latest_formatting, fmt) }
    }
    close := next(io) // '}'
    
    out^ = make_value(io, { open, close }, result)
    out.format = ring_get_most_frequent(latest_formatting)
    
    fmt.println(latest_formatting)
    iterator: int
    for v in ring_iterate(latest_formatting, &iterator) {
        fmt.print(v, " ")
    }
    fmt.println("=", out.format)

    return true
}

@(private="file")
handle_list :: proc(io: ^IO, out: ^Value) -> bool {
    if token_text(io, peek(io)) != "[" do return false

    result := new(List, io.alloc)
    latest_formatting: Ring(int, 16)

    open := next(io) // '['
    for !any_of(token_text(io, peek(io)), "]", "") {

        if token_text(io, peek(io)) == "," { next(io); continue }
        
        element: Value
        ok :=
            handle_integer(io, &element) ||
            handle_float  (io, &element) || 
            handle_bool   (io, &element) ||
            handle_date   (io, &element) ||
            handle_string (io, &element) || 
            handle_table  (io, &element) ||
            handle_list   (io, &element) ||
            handle_extra  (io, &element)

        append(result, element) 

        fmt := handle_formatting(io)
        if fmt != -1 { ring_append(&latest_formatting, fmt) }
    }
    close := next(io) // ']'

    out^ = make_value(io, { open, close }, result)
    out.format = ring_get_most_frequent(latest_formatting)

    return true
}

@(private="file")
handle_integer :: proc(io: ^IO, out: ^Value) -> bool {
    num := parse_int(token_text(io, peek(io))) or_return
    out^ = make_value(io, { next(io) }, num)
    return true
}

@(private="file")
handle_float :: proc(io: ^IO, out: ^Value) -> bool {
    text := token_text(io, peek(io))

    if len(text) == 4 {
        if text[0] == '-' { if text[1:] == "inf" { out^ = make_value(io, { next(io) }, -Infinity); return true } }
        if text[0] == '+' { if text[1:] == "inf" { out^ = make_value(io, { next(io) }, +Infinity); return true } }
        if text[1:] == "nan" { out^ = make_value(io, { next(io) }, NaN); return true }
    }

    if text == "nan" { out^ = make_value(io, { next(io) }, NaN       ); return true }
    if text == "inf" { out^ = make_value(io, { next(io) }, +Infinity ); return true }

    num := parse_f64(token_text(io, peek(io))) or_return
    out^ = make_value(io, { next(io) }, num)
    return true
}

@(private="file")
handle_bool :: proc(io: ^IO, out: ^Value) -> bool {
    text := token_text(io, peek(io))
    if text == "true"  { out^ = make_value(io, { next(io) }, true ); return true }
    if text == "false" { out^ = make_value(io, { next(io) }, false); return true }
    return false
}

@(private="file")
handle_date :: proc(io: ^IO, out: ^Value) -> bool {
    if !dates.is_date_lax(token_text(io, peek(io))) { return false }
    
    a_tok := next(io)
    a, err1 := dates.from_string(token_text(io, a_tok))
    
    if dates.is_date_lax(token_text(io, peek(io))) {
        b_tok := next(io)
        b, err2 := dates.from_string(token_text(io, b_tok))

        if err1 != .NONE do return false
        if err2 != .NONE do return false
            
        out^ = make_value(io, { a_tok, b_tok }, dates.combine(a, b))

    } else {
        if err1 != .NONE do return false
    
        out^ = make_value(io, { a_tok }, a)
    }

    return true
}

@(private="file")
handle_string :: proc(io: ^IO, out: ^Value) -> bool {
    text := token_text(io, peek(io))
    if first_rune(text) != '"' && first_rune(text) != '\'' { return false }
    out^ = make_value(io, { next(io) }, text)
    return true
}

@(private="file") // returns -1 if the return value should be discarded.
handle_formatting :: proc(io: ^IO) -> (heuristic_cache_index: int) {
    // initialization of the "global" cache
    if len(io._list_format_cache) == 0 {
        io._list_format_cache = make_dynamic_array_len_cap([dynamic][]string, allocator = io.alloc, len = 0, cap = 16)
        append(&io._list_format_cache, []string {})
    }
    

    formatting: [] string
    for &token, i in io.tokens[io._curr:] {
        if len(token) > 0 && any_of(token, "}", "]") { return -1 }

        if len(token) > 0 && !contains(FORMATTING, first_rune(token)) { 
            formatting = io.tokens[io._curr:io._curr + i]
            break 
        } 
    }

    if len(formatting) == 0 { return 0 }

    cache_index := -1
    for heuristic, i in io._list_format_cache {
        matches := len(formatting) == len(heuristic)
        if !matches { continue }

        for token, j in formatting {
            if token != heuristic[j] {
                matches = false
                break
            }
        }

        if matches {
            cache_index = i
            break
        }
    }
    
    if cache_index == -1 {
        append(&io._list_format_cache, formatting)
        cache_index = len(io._list_format_cache) - 1
    } 

    return cache_index
}


@(private="file")
peek :: proc(io: ^IO, n := 0) -> TokenHandle {
    n := n
    for &token, i in io.tokens[io._curr:] {
        if len(token) > 0 && !contains(NONPRINTABLES, first_rune(token)) { n -= 1 } 
        if n < 0 {
            i := io._curr + i
            h := io.hashes[i]
            return { token = i32(i), hash = h }
        }
    }
    return {}
}

@(private="file")
next :: proc(io: ^IO) -> TokenHandle {
    for len(io.tokens) > io._curr {
        token := io.tokens[io._curr]
        defer io._curr += 1
        if len(token) > 0 && !contains(NONPRINTABLES, first_rune(token)) {
            return { token = i32(io._curr), hash = io.hashes[io._curr] }
        }
    }
    return {}
}

@(private="file")
t :: proc(io: ^IO, arr: [] TokenHandle) -> [] TokenHandle {
    out := make_slice(type_of(arr), len(arr), io.alloc)
    for _, i in arr { out[i] = arr[i] }
    return out
}

make_value :: proc(io: ^IO, tokens: [] TokenHandle, parsed: ValueData) -> Value {
    return { tokens = t(io, tokens), parsed = parsed, hash = hash_value(parsed) }
}

