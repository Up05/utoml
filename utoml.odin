package utoml

import "core:fmt"

// get_value dotted.path -> Value

@(private="file")
find_identifier :: proc(tokens: [] string) -> int {
    for token, i in tokens { if !any_of(first_rune(token), ..FORMATTING) { return i } }
    return -1
}


@private
get_common_element_separator :: proc(io: ^IO, table: ^Table) -> [] string {
    common: [] string

    for k, v in table^ {
        if len(v.tokens) == 0 { continue }

        for file in io.userfiles {
            fmt.println( (cast(int) uintptr(raw_data(file.tokens)) - cast(int) uintptr(rawptr(back(v.tokens)))) / 8)
        }
        file := file_by_token(io, back(v.tokens)) 
        fmt.println("!", back(v.tokens)^, file)
        if file == nil { continue }
        
        index := index_from_ptrs(file.tokens[:], back(v.tokens))

        separation := find_identifier(file.tokens[index + 1:]) 
        fmt.println("=== SEPARATION ===", file.tokens[index + 1:index + 1 + separation])

        
    }
    
    return common
}


/* 
    {
        a = 1
    }

    {
        a = 5,
        b = 3,
        c = 2

    }

   for k, v, i in table_iterate()
        if len(v.tokens) > 0 
            format_value(v)

        else 
            if len(table.values) > 1
                p := table.values[0].tokens[-1]
                
                if len(table.values) > 1 
                    from := real_tokens[p] + 1
                    to   := real_tokens[p:] find !FORMATTING_TOKENS

                    from "}"
                        append ..real_tokens[from:to]
                        append key " " "=" " " value ","
                return

            if len(table.values) > 0
                p := table.values[0].tokens[-1]  
                if peek(from p) != ","         
                    from p
                        append ","

            table should store "{" and "}" as tokens
            from "{"
                append "\n" "\t"
                append key " " "=" " " value ","
*/

// for k, v in table_iterate()
// table_insert(k, v)
// table_delete(k)
// table_lookup(k) -> v
// 
