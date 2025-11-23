package utoml

import "core:fmt"

Validator :: struct {
    allocator : Allocator,
    handler   : proc(info: ^Validator),

    message_short : string,
    message_long  : Builder,

    full   : string,
    line   : string,
    text   : string,

    file   : string,
    row    : int,
    column : int,
    
    unique : bool,
    halt   : bool,
    type   : enum u8 { Error, Warning },
}

MAX_ERRORS :: 16

validate :: proc(custom_validator: ^Validator = nil) -> (ok: bool) {
    default_validator : Validator = {
        allocator = context.temp_allocator,
        handler   = default_tokenizer_handler, 
    }

    base := custom_validator if custom_validator != nil else &default_validator
    results: [dynamic] Validator
    defer delete(results)

    base.file = "/home/ulti/src/utoml/example.toml"
    text, err := read_entire_file("example.toml", context.allocator)
    base.full = string(text)
    tokens := tokenize(string(text))

    validate_tokenizer(base, tokens, &results)
    
    sort_by(results[:], proc(a, b: Validator) -> bool { return a.type == .Error })
    has_errors := len(results) > 0 && results[0].type == .Error

    result_count := min(MAX_ERRORS, len(results))
    for &result, i in results[:result_count] {
        if i == result_count - 1 && has_errors do result.halt = true
        result.handler(&result)
    }

    return !has_errors
}

validate_tokenizer :: proc(base: ^Validator, tokens: Tokens, out: ^[dynamic] Validator) {
    lines := split(base.full, "\n")
    defer delete(lines)

    row: int
    for token, i in tokens {
        defer row += count(tokens[i], "\n")

        this := base^
        this.text = token
        this.type = .Error
        this.row  = row + 1
        this.line = lines[row] // Later, maybe handle the OOB...
        this.column = get_column(tokens[:i+1])

        if prefix(token, "'") && !suffix(token, "'") {
            this.unique = check_uniqueness()
            this.message_short = "Missing closing quote!"
            this.message_long  = make_builder(base.allocator)
            write_string(&this.message_long, "Try adding a single quote here: \n")
            add_example_code(&this, "'")
            append(out, this)

        } 
        if prefix(token, "\"") && !suffix(token, "\"") {
            this.unique = check_uniqueness()
            this.message_short = "Missing closing quote!"
            this.message_long  = make_builder(base.allocator)
            write_string(&this.message_long, "Try adding a double quote here: \n")
            add_example_code(&this, "\"")
            append(out, this)

        } 
        if stray_carriage_return(token) {
            this.type = .Warning
            this.unique = check_uniqueness()
            this.message_short = "Found a stray carriage return symbol!"
            this.message_long  = make_builder(base.allocator)
            write_string(&this.message_long, "Please add a new line character after the '\\r': \n")
            add_example_code(&this, "", index_byte(this.line, '\r'))
            append(out, this)

        }
        
    }
}

LineType :: enum {
    Normal,
    Code,
    Caret,
}

get_long_message_line_type :: proc(line: string) -> LineType {
    if prefix(line, "       ") && contains(transmute([]byte)line, '^') { return .Caret }
    if prefix(line, "    ") { return .Code }
    return .Normal
}

default_tokenizer_handler :: proc(info: ^Validator) {
    // I know about core:terminal/ansi and I do not care.
    start := "\x1b[31mError:" if info.type == .Error else "\x1b[33mWarning:" 

    fmt.println()
    fmt.printfln("%s\x1b[0;37m %s(%d:%d)\x1b[0m %s", start, info.file, info.row, info.column, info.message_short)
    
    long_message := string(info.message_long.buf[:])
    for line in split_iterator(&long_message, "\n") {
        colors: [LineType] string = { .Normal = "", .Code = "\x1b[90m", .Caret = "\x1b[1;96m" }
        fmt.print(colors[get_long_message_line_type(line)])
        fmt.println(line, "\x1b[0m")
    }

    if info.halt do exit(1)
}

@(private="file")
add_example_code :: proc(this: ^Validator, code: string, position := -1) {
    str := this.line
    str  = escape_ascii(str, this.allocator)
    position := len(str) if position == -1 else position 
    position += digits_in(this.row)+2

    fmt.sbprintfln(&this.message_long, "    %d: %s%s", this.row, str, code)
    fmt.sbprintf  (&this.message_long, "    % *s", position, "")

    write_rune(&this.message_long, '^')
    for i := 1; i < len(code) - 1; i += 1 { write_rune(&this.message_long, '~') }
    if len(code) > 1 { write_rune(&this.message_long, '^') }
    write_rune(&this.message_long, '\n')
}

@(private="file")
check_uniqueness :: proc(caller := #caller_location) -> bool {
    @static others: [MAX_ERRORS * 8] i32 // yeah, it's not "perfect" but whatever
    @static count := 0
    
    if count >= len(others) { return false }
    
    id := caller.line + caller.column
    if !contains(others[:], id) {
        others[count] = id
        count += 1
        return true
    } 
    return false
}

@private
get_column :: proc(tokens: [] string) -> int {
    chars := 0
    #reverse for token, i in tokens { 
        newline := last_index_byte(token, '\n')
        if i == len(tokens) - 1 && newline != -1 {
            chars += newline
        } else if newline != -1 {
            chars += len(token[newline + 1:])
            break
        } else {
            chars += len(token)
        }
    }
    return chars
}

@private
stray_carriage_return :: proc(token: string) -> bool {
    carriage_return: bool
    #no_bounds_check for r in token {
        if r == '\r' do carriage_return = true
        else if carriage_return && r != '\n' { return true }
        else { carriage_return = false }
    }
    return false
}
