
# Specification

## Text (strings)

There are 2 types of text:
```toml
basic_string = "- Simple, \n- Escapable\n text"
and = "
    multiline
    by
    default
"
```

And
```
literal_string = 'where \ is just a character.'
so = '\u1234' # doesn't work
```

TOML's multiline strings ("""text""") are also allowed for better syntax highlighting.  
In non-literal strings use \\ to escape text & TOML's \uXXXX and \UXXXXXXXX for unicode characters.
