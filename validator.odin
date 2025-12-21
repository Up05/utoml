package utoml

import "core:fmt"
import "dates"

ErrorHandler :: proc(info: ^Validator)

Validator :: struct {
    allocator : Allocator,    // used for all internal allocations, may be free_all-ed
    handler   : ErrorHandler, // error handler function, see: default_tokenizer_handler 

    message_short : string,  // single line constant error message
    message_long  : Builder, // multiline error details, code snippets & suggestions

    full   : string, // full input text (from the file)
    line   : string, // full line where error occurred
    text   : string, // token the error was found in

    file   : string, // may be null, (absolute file path)
    row    : int,    // bad token's starting line number
    column : int,    // bad token's starting column 
    
    unique : bool,   // whether this error is first of its kind
    halt   : bool,   // true in last error/warning callback when there are errors, default handlers call os.exit here
    type   : enum u8 { Error, Warning }, // warnings are non-fatal & ordered after errors
}

MAX_ERRORS :: 16 // max errors to be "shown on screen" / given to error handlers

@private
make_validator :: proc(io: ^IO) -> (v: Validator) {
    v.allocator = make_arena()
    v.file      = io.filepath
    v.full      = io.fulltext
    return
}

@private
digest_validator :: proc(results: [] Validator) -> (ok: bool) {
    sort_by(results, proc(a, b: Validator) -> bool { return a.type == .Error })
    has_errors := len(results) > 0 && results[0].type == .Error

    result_count := min(MAX_ERRORS, len(results))
    for &result, i in results[:result_count] {
        if i == result_count - 1 && has_errors do result.halt = true
        fmt.assertf(result.handler != nil, "UTOML ASSERT: You passed in your own []Validator results into 'digest_validator', didn't ya?")
        result.handler(&result)
    }

    return !has_errors
}

@private
validate_tokenizer :: proc(base: ^Validator, tokens: Tokens, out: ^[dynamic] Validator) {
    lines  := split(base.full, "\n")
    defer delete(lines)

    ComplexType :: enum u8 { None, Array, Table }
    the_stack := make([dynamic] ComplexType, context.allocator)
    append(&the_stack, ComplexType.None)
    defer delete(the_stack)

    row: int
    for token, i in tokens {
        onwards := tokens[i:]
        next := peek(onwards, 1)

        this := base^
        this.text = token
        this.row  = row + 1
        this.line = lines[row] // Later, maybe handle the OOB...
        this.column = get_column(tokens[:i+1])
        defer row += count(tokens[i], "\n")
        if base.handler == nil do this.handler = default_tokenizer_handler 

        defer { // state calculations
            if token == "[" do append_elem(&the_stack, ComplexType.Array)
            if token == "{" do append_elem(&the_stack, ComplexType.Table)
            if token == "]" do pop(&the_stack) // technically incorrect
            if token == "}" do pop(&the_stack) // but has better behaviour... :) 
        }
        
        if dates.is_date_lax(token) {
            if _, err := dates.from_string(token); err != .NONE {
                context.user_ptr = &err
                this.unique = check_uniqueness() // careful! this uses #caller_location
                this.message_short = "Could not parse date (or part of date)"
                add_long_message(&this, "With error: %v", err)
                add_long_message(&this, "Dates follow this format: 'YYYY-MM-DD HH-MM-SS+HH:MM'")
                add_long_message(&this, "You may specify only one of date, time & UTC offset")
                add_example_code(&this, "", proc(line: string) -> int {  return dates.get_bad_spot(line, (^dates.DateError)(context.user_ptr)^)  })
                append(out, this)
            }
        }
        if token == "=" && back(the_stack) == .Array {
            this.unique = check_uniqueness() // careful! this uses #caller_location
            this.message_short = "Cannot assign inside a list"
            add_long_message(&this, "So what are we doing here exactly?")
            add_example_code(&this, "", "=")
            append(out, this)
        }
        if token == "]" && back(the_stack) == .Table {
            this.unique = check_uniqueness()
            this.message_short = "Mismatched brackets!"
            add_long_message(&this, "Forgot to close a table that was inside the \"closed\" list [ { ] }:")
            add_example_code(&this, "", "]")
            append(out, this)
        }
        if token == "}" && back(the_stack) == .Array {
            this.unique = check_uniqueness()
            this.message_short = "Mismatched brackets!"
            add_long_message(&this, "Forgot to close a list that was inside the \"closed\" table { [ } ]:")
            add_example_code(&this, "", "}")
            append(out, this)
        }
        if prefix(token, "'") && !suffix(token, "'") {
            this.unique = check_uniqueness()
            this.message_short = "Missing closing quote!"
            add_long_message(&this, "Try adding a single quote here:")
            add_example_code(&this, "'")
            append(out, this)
        } 
        if prefix(token, "\"") && !suffix(token, "\"") {
            this.unique = check_uniqueness()
            this.message_short = "Missing closing quote!"
            add_long_message(&this, "Try adding a double quote here:")
            add_example_code(&this, "\"")
            append(out, this)

        } 
        if stray_carriage_return(token) {
            this.type = .Warning
            this.unique = check_uniqueness()
            this.message_short = "Found a stray carriage return symbol!"
            add_long_message(&this, "Please add a new line character after the '\\r':")
            add_example_code(&this, "", "\r")
            append(out, this)
        }
        if non_decimal_float(token) {
            this.unique = check_uniqueness() // careful! this uses #caller_location
            this.message_short = "Found a floating-point number that is not base 10"
            add_long_message(&this, "I both agree they are cool and can't be bothered to implement them...")
            add_example_code(&this, "", proc(line: string) -> int { return index_any(line, "box") })
            append(out, this)
        }


        if prefix(token, "\"") && next == "=" && peek(onwards, 2) != "=" {
            this.type = .Warning
            this.unique = check_uniqueness()
            this.message_short = "Quoted keys are not actually implemented."
            add_long_message(&this, "You will have to access the value via e.g.: your_table[%q]", token)
            add_example_code(&this, "", "\"")
            append(out, this)
        } 
        if prefix(token, "'") && next == "=" && peek(onwards, 2) != "=" {
            this.type = .Warning
            this.unique = check_uniqueness()
            this.message_short = "Quoted keys are not actually implemented."
            add_long_message(&this, "Single quotes will not be stripped: your_table[%q] == your_value", token)
            add_example_code(&this, "", "'")
            append(out, this)
        } 
    }
}

// call get_long_message_line_type(validator.long_message split by lines) 
// to get this for your error handler
LineType :: enum {
    Normal, // for example, suggestion text
    Code,   // the code snippet
    Caret,  // the lil' ^~~~~~^ line below .Code 
}

get_long_message_line_type :: proc(line: string) -> LineType {
    if prefix(line, "       ") && contains(transmute([]byte)line, '^') { return .Caret }
    if prefix(line, "    ") { return .Code }
    return .Normal
}

default_tokenizer_handler :: proc(info: ^Validator) {
    // core:terminal/ansi is technically correct and practically useless
    start := "\x1b[31mError:" if info.type == .Error else "\x1b[33mWarning:" 

    fmt.println()
    fmt.printfln("%s\x1b[0;37m %s(%d:%d)\x1b[0m %s", start, info.file, info.row, info.column, info.message_short)
    
    long_message := string(info.message_long.buf[:])
    for line in split_iterator(&long_message, "\n") {
        colors: [LineType] string = { .Normal = "", .Code = "\x1b[90m", .Caret = "\x1b[1;96m" }
        fmt.print(colors[get_long_message_line_type(line)])
        fmt.println(line, "\x1b[0m")
    }

    if info.halt { 
        fmt.println("\x1b[3;31mProgram exited due to utoml errors...\x1b[0m")
        fmt.println("\x1b[2;37mTIP: you can replace io.error_handlers\x1b[0m")
        exit(1)
    }
}

@(private="file")
add_long_message :: proc(this: ^Validator, msg: string, args: ..any) {
    if len(this.message_long.buf) == 0 { this.message_long = make_builder(this.allocator) }
    fmt.sbprintfln(&this.message_long, msg, ..args)
}

@(private="file")
add_example_code :: proc { add_example_code_func, add_example_code_index }

@(private="file")
add_example_code_func :: proc(this: ^Validator, code: string, bad_char: proc(line: string) -> int) {
    str := this.line
    str  = escape_ascii(str, this.allocator)
    position := len(str) if bad_char == nil else bad_char(this.line[this.column-len(this.text):]) + this.column-len(this.text) 
    position += digits_in(this.row)+2

    fmt.sbprintfln(&this.message_long, "    %d: %s%s", this.row, str, code)
    fmt.sbprintf  (&this.message_long, "    % *s", position, "")

    write_rune(&this.message_long, '^')
    for i := 1; i < len(code) - 1; i += 1 { write_rune(&this.message_long, '~') }
    if len(code) > 1 { write_rune(&this.message_long, '^') }
    write_rune(&this.message_long, '\n')
}

@(private="file")
add_example_code_index :: proc(this: ^Validator, code: string, bad_char := "") {
    str := this.line
    str  = escape_ascii(str, this.allocator)
    position := len(str) if bad_char == "" else index(this.line[this.column-len(this.text):], bad_char) + this.column-len(this.text) 
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

@private
non_decimal_float :: proc(token: string) -> bool {
    if !(first_rune(token) == '0' && any_of(first_rune(token[1:]), 'x', 'o', 'b')) do return false
    return index_any(token, ".eE") != -1 
}

@private 
check_nil_io :: proc(io: ^IO, caller := #caller_location) {
    EXAMPLE :: 
        "    main :: proc() {\n" +
        "        io: IO\n" +
        "        parse_userfile(&io, \"example1.toml\")\n" +
        "        parse_userfile(&io, \"example2.toml\")\n" +
        "    }"

    fmt.assertf(io != nil, 
        "\n\x1b[31mUTOML ERROR:\x1b[0m io cannot be nil\n" +
        "\x1b[37mutoml mutates user-owned IO objects.\n" + 
        "How are you planning to get the result of %s?\x1b[0m\n" + 
        "Example:\n\x1b[33m%s\x1b[0m", caller.procedure, EXAMPLE)
}

@(private="file")
peek :: proc(tokens: [] string, n := 0) -> string {
    n := n
    for &token in tokens {
        if len(token) > 0 && 
           !contains(NONPRINTABLES, first_rune(token)) {
            n -= 1
        } 
        if n < 0 {
            return token
        }
    }
    return {}
}

