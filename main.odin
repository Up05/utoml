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
