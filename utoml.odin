package utoml

import "base:runtime"
import "core:fmt"
import "frigg"

@(private="file")
find_identifier :: proc(tokens: [] string) -> int {
    for token, i in tokens { if !any_of(first_rune(token), ..FORMATTING) { return i } }
    return -1
}

@private
find_identation_and_insertion :: proc(io: ^IO, into: Value) -> (most_common: []string, final_element_start: int) {
    table, ok := into.parsed.(^Table)
    if !ok do return

    Freq :: struct { slice: [] string, count: int }
    freq : [dynamic] Freq
    defer delete(freq)
    
    positions : [dynamic] int
    defer delete(positions)

    for k, v in table^ {
        if len(v.tokens) == 0 { continue }

        index := int(back(v.tokens).token)
        sep_len   := find_identifier(io.tokens[index + 1:]) 
        separator := io.tokens[index+1 : index+1 + sep_len]

        append(&positions, index + sep_len)

        any_match: bool
        out: for &f in freq {
            match := true
            j: int
            for e, k in f.slice {
                if j >= len(separator) do continue out
                for prefix(separator[j], "#") {
                    j += 1
                    if j >= len(separator) do continue out
                }
                if e != separator[j] {
                    match = false
                    break
                }
                j += 1
            }
            if match {
                any_match = true
                f.count += 1
                break
            }
        }

        if !any_match {
            append(&freq, Freq { slice = separator, count = 1 })
        }
    }

    common_count: int
    for f in freq {
        if f.count <= common_count { continue }
        common_count = f.count; most_common = f.slice
    }

    sort(positions[:]) // stupid, but whatever...
    final_element_start = positions[len(positions) - 2] if len(positions) > 2 else
                          positions[len(positions) - 1] if len(positions) > 1 else
                          int(into.tokens[0].token)                 

    return 
}

find_from_single_element :: proc(io: ^IO, into: Value) -> (indent: [] string, newline: bool, insert_before: int) {
    table, ok := into.parsed.(^Table)
    if !ok do return

    v: Value
    for _, &_v in table { v = _v }

    index   := int(back(v.tokens).token)
    sep_len := find_identifier(io.tokens[index + 1:]) 
    newline  = contains(io.tokens[index+1 : index+1 + sep_len], "\n")

    index   = int(into.tokens[0].token)
    sep_len = find_identifier(io.tokens[index + 1:]) 
    indent  = io.tokens[index+1 : index+1 + sep_len]
    // if i := find_slice(indent, "\n"); i != len(indent) { indent = indent[i+1:] }

    insert_before = index + sep_len

    return 
}


// table_append_tokens :: proc(io: ^IO, into: Value, tokens: []string) {
//     table, ok := into.parsed.(^Table)
//     if !ok do return
// 
//     if len(table) > 1 {
//         common_separator, insert_before := find_identation_and_insertion(io, into)
//         assert(insert_before > 0)
//         inject_at_elems(&io.tokens, insert_before + 1, ..tokens)
//         inject_at_elems(&io.tokens, insert_before + 1 + len(tokens), ..common_separator) // TODO, fuck, comments! ignore them here too :(
//         return
//     }
//     if len(table) > 0 {
//         indent, newline, insert_before := find_from_single_element(io, into)
//         fmt.println(tokens, indent)
//         inject_at_elems(&io.tokens, insert_before + 1, ..tokens)
//         inject_at_elems(&io.tokens, insert_before + 1 + len(tokens), ",")
//         inject_at_elems(&io.tokens, insert_before + 2 + len(tokens), ..indent)
//         return
//     }
//     if len(table) == 0 {
//         from := int(into.tokens[0].token)
//         to   := int(back(into.tokens).token)
// 
//         newline := find_slice(io.tokens[from+1:to], "\n")
//         newline_char := "\n" if newline == len(io.tokens[from+1:to]) else "" 
//         fmt.println(io.tokens[from+1:to], newline_char)
// 
//         indent  := "    " 
//         for t in io.tokens[from+1+newline:to] { if contains(t, ' ') { indent = ""; break } }
// 
//         insert_before := int(back(into.tokens).token)
//         inject_at_elems(&io.tokens, insert_before, newline_char, indent)
//         inject_at_elems(&io.tokens, insert_before + 2, ..tokens)
//         inject_at_elems(&io.tokens, insert_before + 2 + len(tokens), "\n")
//     }
// }

/*
1:
table = { }
2:
table = {

}
3:
table = {
    a = 5
}
4:
table = {
    a = 5,
    b = 6
}


 
*/

final_fmt_tokens :: proc(io: ^IO, into: Value) -> (from, to: int, tokens: [] string) {
    from = int(back(into.tokens).token)
    to   = from

    #reverse for token, i in io.tokens[:to] { 
        if !any_of(first_rune(token), ..FORMATTING) { 
            from   = i + 1 
            tokens = io.tokens[from:to]
            return
        } 
    }
    return 
}

table_append_tokens :: proc(io: ^IO, into: ^Value, tokens: [] string) {
    if into == nil do return
    table, ok := into.parsed.(^Table)
    if !ok do return

    indent      := 4
    multiline   := true

    from, to, old := final_fmt_tokens(io, into^)
    remove_range(&io.tokens, from, to)

    sep1 := []string { ",", "\n", get_indent(indent) } if multiline else { ",", " " }
    inject_at_elems(&io.tokens, from, ..sep1)
    inject_at_elems(&io.tokens, from + len(sep1), ..tokens)

    sep2 := []string { "\n" }
    inject_at_elems(&io.tokens, from + len(sep1) + len(tokens), ..sep2)

    into.tokens[len(into.tokens) - 1].token += i32(len(sep1) + len(tokens) + len(sep2) - (to - from))
}





