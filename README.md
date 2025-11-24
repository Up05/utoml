# Usage

I haven't yet figured it out...
Probably will have a querrying API or smth.

I have a bunch of ideas about file watches & update(), flush(), reload(), assign\_file()

# Specification

## Things not in utoml
1. `dotted.paths.are.not.allowed`
2. `[[ lists_of_tables_are_not_allowed ]]`
3. `"quoted keys" = "are not allowed"`

Why?

Because they are annoying.

## Sections

```
[table]
they = "exists"

[and]
work = [ "normally", "-ish" ]
```

## Key-value pairs

Keys can, technically, be whatever...
This makes the statement "utoml is toml subset" false, but also:
```
= = 5 # is totally valid
# so...
```

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

## Integers

Equivalent to TOML.
```
a = 123
b = 0xDEADBEEF
c = 123_456_789
```

## Floating-point numbers

Equivalent to TOML.
```
a = 123.456
b = 123e2
c = -inf
```

## Boolean

Equivalent to TOML.
```
a = true
b = false
```

## Dates

Equivalent to TOML.
```
a = 2025-11-23
b = 12:30:00
c = 2025-11-23 12:30:00+02:00
```

## Lists (arrays)

Equivalent(-ish) to TOML.
```
list = [ 1, 2, 3 ]
yeah = [ [ 'a', 'b' ],,,, 5, ]
```

## (inline) Tables

Similar to TOML.
```
table = {
    b = { c = 1, d = 2 },
    e = [ 1, 2 ]
}
```

You cannot have dotted paths:
```
a = { terrible.better.yet.horrible = 999 }
also.invalid.here = {}
[and.here]
```


