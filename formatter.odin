package utoml

import "core:fmt"
import "core:strconv"
import "core:math"

IntegerInfo :: struct {
    original       : string, // original "-0_12_345" token
    has_plus_sign  : bool,   // +1234
    has_separators : bool,   // 123_456_789
    the_base       : int,    // 2, 8, 10 or 16
} 


format_value :: proc(value: Value) {


}

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
   
    fmt.println(formatted)
    fmt.println(string(new_string.buf[:]))
}

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
