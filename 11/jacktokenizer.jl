@enum TokenType t_keyword t_symbol t_identifier t_int_const t_string_const

const keywords = [
    "class", "constructor", "function",
    "method", "field", "static", "var",
    "int", "char", "boolean", "void",
    "true", "false", "null", "this",
    "let", "do", "if", "else",
    "while", "return"
]

const symbols = "{}()[].,;+-*/&|<>=~"


mutable struct JackTokenizer
    io::IOStream
    token::String

    function JackTokenizer(path::String)
        new(open(path, "r"), "")
    end
end

close(tok::JackTokenizer) = Base.close(tok.io)


# remove leading whitespaces and comments
function trim(tok::JackTokenizer)
    while true
        skipchars(isspace, tok.io)
        eof(tok.io) && break

        # read two letters
        s = String(read(tok.io, 2))
        if s == "//"
            while !eof(tok.io) && peek(tok.io, Char) != '\n'
                skip(tok.io, 1)
            end
            skipchars(!isequal('\n'), tok.io)
        elseif s == "/*"
            while true
                skipchars(!isequal('*'), tok.io)
                String(read(tok.io, 2)) == "*/" && break
                # go back one position
                seek(tok.io, position(tok.io) - 1)
            end
        else
            # go back two positions
            seek(tok.io, position(tok.io) - 2)
            break
        end
    end
    !eof(tok.io)
end



# checks if the input stream has more tokens
function hasmoretokens(tok::JackTokenizer)::Bool
    trim(tok)
    !eof(tok.io)
end


# get the next token
function advance!(tok::JackTokenizer)
    trim(tok)
    firstletter = read(tok.io, Char)
    tok.token = string(firstletter)
    if isdigit(firstletter)  # integer constant
        while !eof(tok.io) && isdigit(peek(tok.io, Char))
            tok.token *= read(tok.io, Char)
        end
    elseif firstletter == '"'  # string constant
        tok.token *= readuntil(tok.io, '"', keep=true)
    elseif firstletter in symbols  # symbol
        # nothing
    else  # keyword or identifier
        while !eof(tok.io)
            c = peek(tok.io, Char)
            if isdigit(c) || isletter(c) || c == '_'
                tok.token *= read(tok.io, Char)
            else
                break
            end
        end
    end
end


# return the type of the current token
function tokentype(tok::JackTokenizer)::TokenType
    tok.token in keywords    && return t_keyword
    tok.token[1] in symbols  && return t_symbol
    isdigit(tok.token[1])    && return t_int_const
    tok.token[1] == '"'      && return t_string_const
    t_identifier
end


keyword(tok::JackTokenizer)::String    = tok.token
symbol(tok::JackTokenizer)::Char       = tok.token[1]
identifier(tok::JackTokenizer)::String = tok.token
intval(tok::JackTokenizer)::Int        = parse(Int, tok.token)
stringval(tok::JackTokenizer)::String  = tok.token[2:end-1]


function testjacktokenizer()
    inpath = ARGS[1]
    files = []
    if endswith(inpath, ".jack")
        push!(files, inpath)
    else
        for file in readdir(inpath, join=true)
            if endswith(file, ".jack")
                push!(files, file)
            end
        end
    end

    for file in files
        outpath = file[1:end-5] * "T.xml"

        tok = JackTokenizer(file)

        open(outpath, "w") do io
            write(io, "<tokens>\n")
            while hasmoretokens(tok)
                advance!(tok)
                type = tokentype(tok)
                if type == t_keyword
                    write(io, "<keyword>")
                    write(io, keyword(tok))
                    write(io, "</keyword>\n")
                elseif type == t_symbol
                    write(io, "<symbol>")
                    s = symbol(tok)
                    if s == '<'
                        s = "&lt;"
                    elseif s == '>'
                        s = "&gt;"
                    elseif s == '&'
                        s = "&amp;"
                    end
                    write(io, s)
                    write(io, "</symbol>\n")
                elseif type == t_identifier
                    write(io, "<identifier>")
                    write(io, identifier(tok))
                    write(io, "</identifier>\n")
                elseif type == t_int_const
                    write(io, "<integerConstant>")
                    write(io, string(intval(tok)))
                    write(io, "</integerConstant>\n")
                else
                    write(io, "<stringConstant>")
                    write(io, stringval(tok))
                    write(io, "</stringConstant>\n")
                end
            end
            write(io, "</tokens>\n")
        end

        close(tok)
    end
end


if abspath(PROGRAM_FILE) == @__FILE__
    testjacktokenizer()
end