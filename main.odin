package utoml

import "core:fmt"
import "frigg"

main :: proc() {
    fmt.println("started...")
    
    when true {
    io, ok := parse_file("example.toml", #load("example.toml"))
    assert(ok)

    // frigg.watch(io.root, true)

    // v := io.root["value"]
    // v.parsed = 256
    // map_insert(io.root, "value", v)

    // v = io.root["str"]
    // v.parsed = "some oth\u222Bąčęąer\" text"
    // map_insert(io.root, "str", v)

    // v = io.root["dates_are_toml_like"]
    // date := v.parsed.(Date)
    // date.day += 5
    // date.offset_hour += 13
    // v.parsed = date
    // map_insert(io.root, "dates_are_toml_like", v)

    // format_value(&io, io.root["value"])
    // format_value(&io, io.root["value2"])
    // format_value(&io, io.root["str"])
    // format_value(&io, io.root["dates_are_toml_like"])


    // for k, &v in io.root {
    //     calculate_heuristics_recursively(&io, &v)
    // }

    frigg.watch(io, true)

    new_tokens := [?] string { "x", " ", "=", " ", "9" }
    tb := &io.root["section1"].parsed.(^Table)["table"]
    table_append_tokens(&io, tb, new_tokens[:])
    new_tokens  = [?] string { "y", " ", "=", " ", "9" }
    table_append_tokens(&io, tb, new_tokens[:])
    new_tokens  = [?] string { "z", " ", "=", " ", "9" }
    table_append_tokens(&io, tb, new_tokens[:])
    new_tokens  = [?] string { "w", " ", "=", " ", "9" }
    table_append_tokens(&io, tb, new_tokens[:])

    fmt.println("\n-------------------------------\n")
    fmt.println(io.tokens)
    fmt.println("\n-------------------------------\n")

    for t in io.tokens do fmt.print(t)



    } // /when
}

/*
    TODO HASH THE VALUES WHEN PARSING

    make an API for updating
    values, that serializes and inserts in-real-time 
*/

