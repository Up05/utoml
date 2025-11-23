package utoml

import "core:fmt"
import "core:mem"
import "core:math"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import os "core:os/os2"

Allocator :: mem.Allocator
Builder   :: strings.Builder

exit :: os.exit
read_entire_file :: os.read_entire_file_from_path

sort_by :: slice.sort_by

rune_size   :: utf8.rune_size
decode_rune :: utf8.decode_rune_in_string

make_builder :: strings.builder_make
write_string :: strings.write_string
write_rune   :: strings.write_rune

prefix :: strings.starts_with
suffix :: strings.ends_with
count  :: strings.count
index_byte :: strings.index_byte
last_index_byte :: strings.last_index_byte
split_iterator  :: strings.split_iterator
split           :: strings.split

find      :: proc(a: string, b: string) -> int { i := strings.index(a, b); return i if i != -1 else len(a) }
find_rune :: proc(a: string, b: rune)   -> int { i := strings.index_rune(a, b); return i if i != -1 else len(a) }
find_byte :: proc(a: string, b: byte)   -> int { i := strings.index_byte(a, b); return i if i != -1 else len(a) }

find_any :: proc(a: string, B: [] rune) -> int {
    #no_bounds_check for r, i in a {
        #no_bounds_check for b in B {
            if r == b do return i
        }
    }
    return len(a)
}

empty :: proc(text: ^string) -> bool {
    return text == nil || len(text^) == 0
}

contains :: proc(array: [] $T, element: T) -> bool {
    #no_bounds_check for item in array {
        if item == element do return true
    }
    return false
}

digits_in :: proc(number: int) -> int {
    return int(math.log10(f64(number))) + 1
}

// The fact that this works is just honestly insane to me.
// One would not refer to this algorithm as made using Liquid-CRYSTAL Display...
escape_ascii :: proc(raw: string, allocator: Allocator) -> string {
    ESC_SEQ : [32] byte = ' '
    ESC_SEQ[  0 ] = '0'
    ESC_SEQ['\b'] = 'b'
    ESC_SEQ['\t'] = 't'
    ESC_SEQ['\n'] = 'n'
    ESC_SEQ['\f'] = 'f'
    ESC_SEQ['\r'] = 'r'

    extra: int
    for r in raw { if r < 32 { extra += 3 - 2*int(ESC_SEQ[r] != ' ') } }
    escaped := make([]byte, len(raw) + extra)

    copy(escaped[:len(raw)], transmute([]byte) raw)

    size := len(raw)
    for i := size-1; i >= 0; i -= 1 {
        r := escaped[i]

        if r < 32 {
            if ESC_SEQ[r] != ' ' {
                copy(escaped[i+1:size+1], escaped[i:size])
                escaped[i+1] = ESC_SEQ[r]
                escaped[i] = '\\'
                size += 1
            } else {
                copy(escaped[i+3:size+3], escaped[i:size])
                escaped[i+3] = to_hex_digit(r % 16)
                escaped[i+2] = to_hex_digit(r / 16)
                escaped[i+1] = 'x'
                escaped[i] = '\\'
                size += 3
            }
        }
    }

    return string(escaped)
}

to_hex_digit :: proc(digit: byte) -> byte {
    assert(digit < 16)
    if digit < 10 { return digit + '0' }
    return digit - 10 + 'A'
}
