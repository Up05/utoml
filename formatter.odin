package utoml

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:math"

import "dates"

IntegerInfo :: struct {
    original       : string, // original "-0_12_345" token
    has_plus_sign  : bool,   // +1234
    has_separators : bool,   // 123_456_789
    the_base       : int,    // 2, 8, 10 or 16
} 

FloatInfo :: struct {
    original       : string,
    has_plus_sign  : bool,   // +123.4
    has_separators : bool,   // 123_456.789
    has_e          : bool,   // 123e10
    has_E          : bool,   // 123E+010
    format         : rune,   // 'e', 'E', 'f' or 'g'
    precision      : int,    // guessed precision (or -1)
}


format_value :: proc(io: ^IO, value: Value) {
    switch _ in value.parsed {
    case int:    handle_integer(io, value)
    case f64:    handle_float(io, value)
    case bool:   handle_bool(io, value)
    case string: handle_string(io, value)
    case Date:   handle_date(io, value)
    case ^List:  handle_list(io, value)
    case ^Table: panic("TODO")
    }
}

@(private="file")
handle_integer :: proc(io: ^IO, value: Value) {
    // if value.hash == hash(value) do return    
    number := value.parsed.(int)

    token  := value.tokens[0]^
    file   := file_by_token(io, value.tokens[0])

    has_plus_sign  := first_rune(token) == '+'
    has_separators := contains(token, '_')
    the_base := 2  if contains(token, 'b') else 
                8  if contains(token, 'o') else
                16 if contains(token, 'x') else
                10
    
    _formatted: [1024] byte
    formatted := strconv.write_bits(
        _formatted[:], u64(number), the_base, 
        true, 64, "0123456789ABCDEF", 
        { .Prefix } + ({ .Plus } if has_plus_sign else {})
    )

    new_string := make_builder(file.alloc)
    info: IntegerInfo = { original = token, has_plus_sign = has_plus_sign, has_separators = has_separators, the_base = the_base }
    if io.formatter.integer_postprocessor == nil { io.formatter.integer_postprocessor = digit_grouper }
    io.formatter.integer_postprocessor(formatted, info, &new_string)
    replace(value.tokens[0], string(new_string.buf[:]))
}

@(private="file")
handle_float :: proc(io: ^IO, value: Value) {
    // if value.hash == hash(value) do return    
    number := value.parsed.(f64)
    token  := value.tokens[0]^
    file   := file_by_token(io, value.tokens[0])

    if math.is_inf(number) {
        str := "-inf" if number == -Infinity else
               "+inf" if first_rune(token) == '+' else
                "inf"
        replace(value.tokens[0], string_clone(str, file.alloc)) 
        return
    }

    if math.is_nan(number) {
        str := "-nan" if first_rune(token) == '-' else
               "+nan" if first_rune(token) == '+' else
                "nan"
        replace(value.tokens[0], string_clone(str, file.alloc)) 
        return
    }

    has_plus_sign  := first_rune(token) == '+'
    has_separators := contains(token, '_')
    has_e := contains(token, 'e')
    has_E := contains(token, 'E')
    
    introduce_e := math.log10(number) > 9 && math.floor(math.log10(number)) != math.floor(math.log10(eat(strconv.parse_f64(token))))
    format := 'e' if has_e else 
              'E' if has_E else
              'f' if !introduce_e else 'g'


    precision := guess_precision(token, number) if format == 'f' else -1

    _formatted: [1024] byte
    formatted := strconv.write_float(_formatted[:], number, byte(format), precision, 64)

    info: FloatInfo = { original = token, has_plus_sign = has_plus_sign, has_separators = has_separators, 
                        has_e = has_e, has_E = has_E, format = format, precision = precision }
    new_string := make_builder(file.alloc)
    if io.formatter.float_postprocessor == nil { io.formatter.float_postprocessor = default_float_postprocessor }
    io.formatter.float_postprocessor(formatted, info, &new_string)
    replace(value.tokens[0], string(new_string.buf[:]))

    guess_precision :: proc(old: string, new: f64) -> int {
        num := eat(strconv.parse_f64(old))
        _, frac_a := math.modf_f64(num)
        _, frac_b := math.modf_f64(new)
        if frac_a != frac_b { return -1 }
    
        point    := index_byte(old, '.'); if point == -1 { return -1 }
        fraction := old[point+1:]
        digits   := 0
        #no_bounds_check for r in fraction {
            if r >= '0' && r <= '9' { digits += 1 }
        }

        return digits
    }
}

@(private="file")
handle_string :: proc(io: ^IO, value: Value) {
    text  := value.parsed.(string)
    token := value.tokens[0]^

    quote := "'''" if prefix(token, "'''") && suffix(token, "'''") else
             `"""` if prefix(token, `"""`) && suffix(token, `"""`) else
             "'"   if prefix(token, "'") else `"`

    if  !any_of(first_rune(text), '\'', '"') || 
        !any_of(final_byte(text), '\'', '"') {

        file    := file_by_token(io, value.tokens[0])
        builder := make_builder(file.alloc)
        write_string(&builder, quote[1:])
        enquote(&builder, text, token)
        write_string(&builder, quote[1:])
        replace(value.tokens[0], string(builder.buf[:]))
    }
}


@(private="file")
replace :: proc(value: ^string, with: string) {
    fmt.println(value^, "->", with)
    value^ = with
}

enquote :: proc(builder: ^Builder, raw: string, original: string = "a€↑∀▀ąЫα") {// {{{
    unescaped_groups: [len(UNICODE_BLOCKS)] int
    unescaped_group_len: int

    // r: 0xA7
    // g: 0 --- 0x80 --- 0x100 --- 0x180 --- 0x250
    //    r<g?  r<g?     r<g?
    //                   ^^^^^
    #no_bounds_check for r in original {
        #no_bounds_check for g, block in UNICODE_BLOCKS {
            // yeah, I don't know why this works either...
            // shouldn't it be: r >= g???
            // ...I don't have enough time to get it again :(
            if r < g && !any_of(block, ..unescaped_groups[:unescaped_group_len]) { 
                unescaped_groups[unescaped_group_len] = block-1
                unescaped_group_len += 1 
                break
            }
        }
    }

    #no_bounds_check outer: for r in raw {

        switch r {
        case '\b': write_string(builder, `\b`); continue outer
        case '\t': write_string(builder, `\t`); continue outer
        case '\n': write_string(builder, `\n`); continue outer
        case '\f': write_string(builder, `\f`); continue outer
        case '\r': write_string(builder, `\r`); continue outer
        case '\"': write_string(builder, `\"`); continue outer
        case '\\': write_string(builder, `\"`); continue outer
        }
        
        should_escape: bool // = 
        #no_bounds_check for g, block in UNICODE_BLOCKS {
            if r < g { 
                should_escape = !any_of(block-1, ..unescaped_groups[:unescaped_group_len])
                break
            }
        }

        if should_escape {
            if r < 0x10000 {
                fmt.sbprintf(builder, "\\u%04x", r)
            } else {
                fmt.sbprintf(builder, "\\U%08X", r)
            }
        } else {
            write_rune(builder, r)
        }
    }
}// }}}

@(private="file")
handle_date :: proc(io: ^IO, value: Value) {
    date  := value.parsed.(Date)
    file  := file_by_token(io, value.tokens[0])
    
    fmt.println(date)

    if len(value.tokens) == 1 {
        formatted, err := dates.partial_date_to_string(date, allocator = file.alloc)
        if err == .NONE {
            replace(value.tokens[0], formatted)
        } else { panic("soooo... what do we do here, eh?") }
    } else {
        assert(len(value.tokens) == 2)        
        
        formatted, err := dates.partial_date_to_string(date, allocator = file.alloc)
        if err == .NONE {
            space := index_byte(formatted, ' ')
            if space == -1 {
                replace(value.tokens[0], formatted)
                for t in value.tokens[1:] { t^ = "" }
            } else {
                replace(value.tokens[0], formatted[:space])
                replace(value.tokens[1], formatted[space + 1:])
            }
            
            

        } else { panic("soooo... what do we do here, eh?") }

    }
}

@(private="file")
handle_bool :: proc(io: ^IO, value: Value) {
    @static TRUE, FALSE: string
    if TRUE  == "" { TRUE  = string_clone("true",  io.alloc) }
    if FALSE == "" { FALSE = string_clone("false", io.alloc) }
    
    is_true := value.parsed.(bool)
    replace(value.tokens[0], TRUE if is_true else FALSE)
}

@(private="file")
handle_list :: proc(io: ^IO, value: Value) {
    list := value.parsed.(^List)
    
    for value in list^ {
        format_value(io, value)
    }
}

// handle_table


// ------------------------------- DEFAULT HANDLERS -------------------------------

digit_grouper :: proc(number: string, info: IntegerInfo, output: ^Builder) {
    if !info.has_separators {
        write_string(output, number)
        return
    } 
    
    group_size := 4 if any_of(info.the_base, 2, 16) else 3
    #no_bounds_check for r, i in number {
        write_rune(output, r)

        n := len(number) - (i+1)

        is_number := (r >= '0' && r <= '9') || (r >= 'A' && r <= 'F')
        is_number &= r != '0' || (n > 0 && !any_of(number[i + 1], 'x', 'o', 'b'))

        if is_number && n != 0 && n % group_size == 0 {
            write_rune(output, '_')
        }

    }
}

default_float_postprocessor :: proc(number: string, info: FloatInfo, output: ^Builder) {
    write_string(output, number)
}



