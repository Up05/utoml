package utoml

import "core:fmt"
import "frigg"

main :: proc() {
    fmt.println("started...")
    
    when true {
    io, ok := parse_file("example.toml", #load("example.toml"))
    assert(ok)

    frigg.watch(io.root, true)

    v := io.root["value"]
    v.parsed = 256
    map_insert(io.root, "value", v)

    v = io.root["str"]
    v.parsed = "some oth\u222Bąčęąer\" text"
    map_insert(io.root, "str", v)

    v = io.root["dates_are_toml_like"]
    date := v.parsed.(Date)
    date.day += 5
    date.offset_hour += 13
    v.parsed = date
    map_insert(io.root, "dates_are_toml_like", v)

    format_value(&io, io.root["value"])
    format_value(&io, io.root["value2"])
    format_value(&io, io.root["str"])
    format_value(&io, io.root["dates_are_toml_like"])

    fmt.println("\n-------------------------------\n")
    fmt.println(io.tokens)
    fmt.println("\n-------------------------------\n")
    
    // frigg.watch(io.root, true)

    // get_common_element_separator(&io, io.root["section1"].parsed.(^Table)["table"].parsed.(^Table))

    } // /when
}

/*
    TODO HASH THE VALUES WHEN PARSING

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

