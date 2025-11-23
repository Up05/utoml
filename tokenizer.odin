package utoml

import "core:fmt"

SPECIAL_SYMBOLS : [] rune = { '=', ',', '#', '\'', '"', ' ', '\t', '\v', '\r', '\n' }
WHITESPACE      : [] rune = { ' ', '\t', '\v', '\r' }
NONPRINTABLES   : [] rune = { ' ', '\t', '\v', '\r', '\n', '#' }
SYNTAX_SYMBOLS  : [] rune = { '=', ',', '#', '\'', '"', '\n' }

Tokens :: [dynamic] string

tokenize :: proc(raw: string) -> Tokens {
    tokens: Tokens

    text := raw
    for {
        should_continue := 
            handle_identifier(&text, &tokens) ||
            handle_whitespace(&text, &tokens) ||
            handle_comment   (&text, &tokens) ||
            handle_string    (&text, &tokens) ||
            handle_else      (&text, &tokens)
        
        if !should_continue do break
    }

    fmt.println(tokens)

    return tokens
}

@(private="file")
handle_comment :: proc(text: ^string, out: ^Tokens) -> bool {
    if empty(text) || text[0] != '#' do return false
    end := find_byte(text^, '\n')
    append(out, text[:end])
    text^ = text[end:]
    return true
}

@(private="file")
handle_identifier :: proc(text: ^string, out: ^Tokens) -> bool {
    if empty(text) || !is_identifier(rune(text[0])) do return false
    end := find_any(text^, SPECIAL_SYMBOLS)
    append(out, text[:end])
    text^ = text[end:]
    return true
}

@(private="file")
handle_whitespace :: proc(text: ^string, out: ^Tokens) -> bool {
    if empty(text) || !is_whitespace(rune(text[0])) do return false
    end := find_end_of_whitespace(text^)
    append(out, text[:end])
    text^ = text[end:]
    return true
}

@(private="file")
handle_string :: proc(text: ^string, out: ^Tokens) -> bool {
    if empty(text) || (text[0] != '"' && text[0] != '\'') do return false
    end := find_end_of_string(text^, rune(text[0]))
    append(out, text[:end])
    text^ = text[end:]
    return true
}

@(private="file")
handle_else :: proc(text: ^string, out: ^Tokens) -> bool {
    if empty(text) do return false
    r, rlen := decode_rune(text^)
    append(out, text[:rlen])
    text^ = text[rlen:]
    return true
}


@private
is_whitespace :: proc(r: rune) -> bool {
    #no_bounds_check for char in WHITESPACE {
        if r == char do return true
    }
    return false
}

@private
find_end_of_whitespace :: proc(text: string) -> int {
    #no_bounds_check outer: for r, i in text {
        #no_bounds_check for char in WHITESPACE {
            if r == char do continue outer
        }
        return i
    }
    return len(text)
}

is_triple_string :: proc(text: string, quote: rune) -> bool {
    quote := byte(quote)
    quotes : [3] byte = { quote, quote, quote }
    quote_str : string = string(quotes[:])
    return len(text) > 2 && text[:3] == quote_str
}

@private
find_end_of_string :: proc(text: string, quote: rune) -> int {
    initial_quotes := int(len(text) > 0 && text[0] == byte(quote)) + 2*int(is_triple_string(text, quote))

    escaped: bool
    for r, i in text[initial_quotes:] {
        if escaped do escaped = false
        else if r == '\\'  do escaped = true
        else if r == quote do return i + initial_quotes + 1+2*int(is_triple_string(text[i + initial_quotes:], quote))
    }
    return len(text)
}

@private
is_identifier :: proc(r: rune) -> bool {
    #no_bounds_check for char in SPECIAL_SYMBOLS {
        if r == char do return false
    }
    return true
}
