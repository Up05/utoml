package utoml

import "core:fmt"
import "frigg"

main :: proc() {
    fmt.println("started...")
    
    io: IO
    parse_userfile(&io, "example.toml")
    // // parse_userfile(&io, "example2.toml")
    // frigg.watch(io, true)

    // format_integer({ parsed = int(1234567) })
    
    handle_integer(&io, io.root["value"])
    handle_float(&io, io.root["value2"])
    // fmt.println(io.root["value"])
    // fmt.println(file_by_token(&io, io.root["value"].tokens[0]))
}

/*
    serialize(basic value) ->
        creates tokens
        replaces old tokens

    serialize(list) ->
        creates tokens
        ? creates formatting tokens <-- no !COPY WHITESPACE AROUND LAST ELEMENT?
        injects tokens into the_file.tokens

    serialize(table) ->
        ???
        kind of fucks everything else
        due to multiple files...

        for existing keys is fine actuallly

        adding new keys could just be: [ '\n' key ' ' '=' ' ' serialize(basic value | list) ]
        if serialize(table) in table, then just make it inline?
*/

/*
    Or make an API for updating
    values, that serializes and inserts in-real-time 
 
 
*/




