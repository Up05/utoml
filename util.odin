package utoml

import "core:fmt"
import "core:mem"
import "core:math"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:unicode/utf8"
import "core:mem/virtual"
import "core:hash/xxhash"
import os "core:os/os2"

import "base:runtime"

Allocator :: mem.Allocator
Builder   :: strings.Builder
Hash      :: u64

exit             :: os.exit
absolute_path    :: os.get_absolute_path
read_entire_file :: os.read_entire_file_from_path

sort_by :: slice.sort_by

rune_size   :: utf8.rune_size
decode_rune :: utf8.decode_rune_in_string

parse_f64 :: strconv.parse_f64
parse_int :: strconv.parse_int

make_builder :: strings.builder_make
write_string :: strings.write_string
write_quoted :: strings.write_quoted_string
write_escape :: strings.write_encoded_rune
write_rune   :: strings.write_rune

equali :: strings.equal_fold
prefix :: strings.starts_with
suffix :: strings.ends_with
count  :: strings.count
index  :: strings.index
index_any  :: strings.index_any
index_byte :: strings.index_byte
last_index_byte :: strings.last_index_byte
split_iterator  :: strings.split_iterator
split           :: strings.split
string_clone    :: strings.clone

@private 
eat :: proc(v: $T, e: any) -> T { return v }

@private 
make_arena :: proc(initial_size := mem.Megabyte) -> Allocator {
    arena := new(virtual.Arena)
    _ = virtual.arena_init_growing(arena, uint(initial_size))
    return virtual.arena_allocator(arena) 
}

@private
first_rune :: proc(s: string) -> rune {
    if len(s) == 0 { return 0 }
    r, n := decode_rune(s)
    return r
}

@private
final_byte :: proc(s: string) -> byte {
    if len(s) == 0 { return 0 }
    return s[len(s) - 1]
}

@private
empty :: proc(text: ^string) -> bool {
    return text == nil || len(text^) == 0
}

@private
index_from_ptrs :: proc(a: []$T, b: ^T) -> int {
    base := cast(uintptr) raw_data(a)
    offs := cast(uintptr) rawptr(b)
    assert(base <= offs)
    assert(base + uintptr(len(a)) > offs)
    return int(offs - base) / size_of(T)
}

@private find      :: proc(a: string, b: string) -> int { i := strings.index(a, b); return i if i != -1 else len(a) }
@private find_rune :: proc(a: string, b: rune)   -> int { i := strings.index_rune(a, b); return i if i != -1 else len(a) }
@private find_byte :: proc(a: string, b: byte)   -> int { i := strings.index_byte(a, b); return i if i != -1 else len(a) }

@private back_slice :: proc(A: []$T) -> T { return A[len(A) - 1] }
@private back_dyarr :: proc(A: [dynamic]$T) -> T { return A[len(A) - 1] }
@private back_stack :: proc(A: [$N]$T) -> T { return A[len(A) - 1] }
@private back :: proc { back_slice, back_dyarr, back_stack }

@private
find_any :: proc(a: string, B: [] rune) -> int {
    #no_bounds_check for r, i in a {
        #no_bounds_check for b in B {
            if r == b do return i
        }
    }
    return len(a)
}

@private
contains_slice :: proc(array: [] $T, element: T) -> bool {
    #no_bounds_check for item in array {
        if item == element do return true
    }
    return false
}

contains :: proc { contains_slice, strings.contains_rune }

@private
any_of :: proc(a: $T, B: ..T) -> bool {
    for b in B do if a == b do return true
    return false
}

@private
digits_in :: proc(number: int) -> int {
    return int(math.log10(f64(number))) + 1
}

// The fact that this works is just honestly insane to me.
// One would not refer to this algorithm as made using some HQ Liquid-Srystal Display...
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

@private
to_hex_digit :: proc(digit: byte) -> byte {
    assert(digit < 16)
    if digit < 10 { return digit + '0' }
    return digit - 10 + 'A'
}

@private
file_by_token :: proc(io: ^IO, token: ^string) -> ^File {
    in_addr :: proc(value: rawptr, base: rawptr, size: int) -> bool {
        value := uintptr(value); base := uintptr(base); size := uintptr(size)
        return value >= base && value < base + size
    }

    for &file in io.userfiles {
        raw_array := transmute(runtime.Raw_Dynamic_Array) file.tokens
        if in_addr(rawptr(token), raw_array.data, raw_array.len * size_of(token)) { 
            return &file
        }
    }

    return nil
}


UNICODE_BLOCKS := [?] rune { 
    0x0, 0x80, 0x100, 0x180, 0x250, 0x2B0, 0x300, 0x370, 0x400, 0x500, 0x531, 0x591, 0x600, 0x700, 0x750,
    0x780, 0x7C0, 0x800, 0x840, 0x900, 0x981, 0xA01, 0xA81, 0xB01, 0xB82, 0xC01, 0xC82, 0xD02, 0xD82, 0xE01, 
    0xE81, 0xF00, 0x1000, 0x10A0, 0x1100, 0x1200, 0x1380, 0x13A0, 0x1400, 0x1680, 0x16A0, 0x1700, 0x1720, 0x1740, 
    0x1760, 0x1780, 0x1800, 0x18B0, 0x1900, 0x1950, 0x1980, 0x19E0, 0x1A00, 0x1A20, 0x1B00, 0x1B80, 0x1BC0, 0x1C00, 
    0x1C50, 0x1CD0, 0x1D00, 0x1D80, 0x1DC0, 0x1E00, 0x1F00, 0x2000, 0x2070, 0x20A0, 0x20D0, 0x2100, 0x2150, 0x2190, 
    0x2200, 0x2300, 0x2400, 0x2440, 0x2460, 0x2500, 0x2580, 0x25A0, 0x2600, 0x2701, 0x27C0, 0x27F0, 0x2800, 0x2900, 
    0x2980, 0x2A00, 0x2B00, 0x2C00, 0x2C60, 0x2C80, 0x2D00, 0x2D30, 0x2D80, 0x2DE0, 0x2E00, 0x2E80, 0x2F00, 0x2FF0, 
    0x3000, 0x3041, 0x30A0, 0x3105, 0x3131, 0x3190, 0x31A0, 0x31C0, 0x31F0, 0x3200, 0x3300, 0x3400, 0x4DC0, 0x4E00, 
    0xA000, 0xA490, 0xA4D0, 0xA500, 0xA640, 0xA6A0, 0xA700, 0xA720, 0xA800, 0xA830, 0xA840, 0xA880, 0xA8E0, 0xA900, 
    0xA930, 0xA960, 0xA980, 0xAA00, 0xAA60, 0xAA80, 0xAB01, 0xABC0, 0xAC00, 0xD7B0, 0xD800, 0xDB80, 0xDC00, 0xE000, 
    0xF900, 0xFB00, 0xFB50, 0xFE00, 0xFE10, 0xFE20, 0xFE30, 0xFE50, 0xFE70, 0xFF01, 0xFFF9, 0x10000, 0x10080, 0x10100, 
    0x10140, 0x10190, 0x101D0, 0x10280, 0x102A0, 0x10300, 0x10330, 0x10380, 0x103A0, 0x10400, 0x10450, 0x10480, 0x10800, 
    0x10840, 0x10900, 0x10920, 0x10A00, 0x10A60, 0x10B00, 0x10B40, 0x10B60, 0x10C00, 0x10E60, 0x11000, 0x11080, 0x12000, 
    0x12400, 0x13000, 0x16800, 0x1B000, 0x1D000, 0x1D100, 0x1D200, 0x1D300, 0x1D360, 0x1D400, 0x1F000, 0x1F030, 0x1F0A0, 
    0x1F100, 0x1F200, 0x1F300, 0x1F601, 0x1F680, 0x1F700, 0x20000, 0x2A700, 0x2B740, 0x2F800, 0xE0001, 0xE0100, 0xF0000, 
    0x100000 
}

