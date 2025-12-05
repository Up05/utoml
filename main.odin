package utoml

import "core:fmt"
import "frigg"

main :: proc() {
    fmt.println("started...")
    
    io: IO
    parse_userfile(&io, "example.toml")
    // parse_userfile(&io, "example2.toml")
    frigg.watch(io, true)
}

/*
    serialize(basic value) ->
        creates tokens
        replaces old tokens

    serialize(list) ->
        creates tokens
        ? creates formatting tokens
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




