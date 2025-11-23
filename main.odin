package utoml

import "core:fmt"
import "frigg"

main :: proc() {
    fmt.println("started...")
    
    // validate()
    io: IO
    parse_userfile(&io, "example.toml")
    frigg.watch(io, true)
}
