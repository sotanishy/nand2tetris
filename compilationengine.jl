const keywordconst = ["true", "false", "null", "this"]

const op = "+-*/&|<>="

const unaryop = "-~"


struct CompilationEngine
    tok::JackTokenizer
    io::IOStream

    function CompilationEngine(tok::JackTokenizer, path::String)
        hasmoretokens(tok) && advance!(tok)
        new(tok, open(path, "w"))
    end
end


close(engine::CompilationEngine) = Base.close(engine.io)


function writekeyword(engine::CompilationEngine)
    write(engine.io, "<keyword>$(keyword(engine.tok))</keyword>\n")
    hasmoretokens(engine.tok) && advance!(engine.tok)
end


function writesymbol(engine::CompilationEngine)
    s = symbol(engine.tok)
    if s == '<'
        s = "&lt;"
    elseif s == '>'
        s = "&gt;"
    elseif s == '&'
        s = "&amp;"
    end
    write(engine.io, "<symbol>$s</symbol>\n")
    hasmoretokens(engine.tok) && advance!(engine.tok)
end


function writeidentifier(engine::CompilationEngine)
    write(engine.io, "<identifier>$(identifier(engine.tok))</identifier>\n")
    hasmoretokens(engine.tok) && advance!(engine.tok)
end


function writeintconst(engine::CompilationEngine)
    write(engine.io, "<integerConstant>$(intval(engine.tok))</integerConstant>\n")
    hasmoretokens(engine.tok) && advance!(engine.tok)
end


function writestringconst(engine::CompilationEngine)
    write(engine.io, "<stringConstant>$(stringval(engine.tok))</stringConstant>\n")
    hasmoretokens(engine.tok) && advance!(engine.tok)
end


function compileclass(engine::CompilationEngine)
    write(engine.io, "<class>\n")

    # class
    writekeyword(engine)
    # className
    writeidentifier(engine)
    # {
    writesymbol(engine)
    # classVarDec*
    while tokentype(engine.tok) == t_keyword && keyword(engine.tok) in ("static", "field")
        compileclassvardec(engine)
    end
    # subroutineDec*
    while tokentype(engine.tok) == t_keyword && keyword(engine.tok) in ("constructor", "function", "method")
        compilesubroutine(engine)
    end
    # }
    writesymbol(engine)

    write(engine.io, "</class>\n")
end


function compileclassvardec(engine::CompilationEngine)
    write(engine.io, "<classVarDec>\n")

    # static | field
    writekeyword(engine)
    # type
    if tokentype(engine.tok) == t_keyword
        writekeyword(engine)
    else
        writeidentifier(engine)
    end
    # varName
    writeidentifier(engine)
    # (, varName)*
    while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
        # ,
        writesymbol(engine)
        # varName
        writeidentifier(engine)
    end
    # ;
    writesymbol(engine)

    write(engine.io, "</classVarDec>\n")
end


function compilesubroutine(engine::CompilationEngine)
    write(engine.io, "<subroutineDec>\n")
    # constructor | function method
    writekeyword(engine)
    # void | type
    if tokentype(engine.tok) == t_keyword
        writekeyword(engine)
    else
        writeidentifier(engine)
    end
    # subroutineName
    writeidentifier(engine)
    # (
    writesymbol(engine)
    # parameterList
    compileparameterlist(engine)
    # )
    writesymbol(engine)

    # subroutineBody
    write(engine.io, "<subroutineBody>\n")
    # {
    writesymbol(engine)
    # varDec*
    while tokentype(engine.tok) == t_keyword && keyword(engine.tok) == "var"
        compilevardec(engine)
    end
    # statements
    compilestatements(engine)
    # }
    writesymbol(engine)

    write(engine.io, "</subroutineBody>\n")
    write(engine.io, "</subroutineDec>\n")
end


function compileparameterlist(engine::CompilationEngine)
    write(engine.io, "<parameterList>\n")

    if (tokentype(engine.tok) == t_keyword && keyword(engine.tok) in ("int", "char", "boolean")) || tokentype(engine.tok) == t_identifier
        # type
        if tokentype(engine.tok) == t_keyword
            writekeyword(engine)
        else
            writeidentifier(engine)
        end
        # varName
        writeidentifier(engine)
        # (, type varName)*
        while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
            # ,
            writesymbol(engine)
            # type
            if tokentype(engine.tok) == t_keyword
                writekeyword(engine)
            else
                writeidentifier(engine)
            end
            # varName
            writeidentifier(engine)
        end
    end

    write(engine.io, "</parameterList>\n")
end


function compilevardec(engine::CompilationEngine)
    write(engine.io, "<varDec>\n")

    # var
    writekeyword(engine)
    # type
    if tokentype(engine.tok) == t_keyword
        writekeyword(engine)
    else
        writeidentifier(engine)
    end
    # varName
    writeidentifier(engine)
    # (, varName)*
    while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
        # ,
        writesymbol(engine)
        # varName
        writeidentifier(engine)
    end
    # ;
    writesymbol(engine)

    write(engine.io, "</varDec>\n")
end


function compilestatements(engine::CompilationEngine)
    write(engine.io, "<statements>\n")

    # statement*
    while tokentype(engine.tok) == t_keyword
        k = keyword(engine.tok)
        if k == "let"
            compilelet(engine)
        elseif k == "if"
            compileif(engine)
        elseif k == "while"
            compilewhile(engine)
        elseif k == "do"
            compiledo(engine)
        elseif k == "return"
            compilereturn(engine)
        else
            break
        end
    end

    write(engine.io, "</statements>\n")
end


function compiledo(engine::CompilationEngine)
    write(engine.io, "<doStatement>\n")

    # do
    writekeyword(engine)

    # subroutineCall
    # subroutineName or (className | varName)
    writeidentifier(engine)
    # (. subroutineName)?
    if tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '.'
        # .
        writesymbol(engine)
        # subroutineName
        writeidentifier(engine)
    end
    # (
    writesymbol(engine)
    # expressionList
    compileexpressionlist(engine)
    # )
    writesymbol(engine)

    # ;
    writesymbol(engine)

    write(engine.io, "</doStatement>\n")
end


function compilelet(engine::CompilationEngine)
    write(engine.io, "<letStatement>\n")

    # let
    writekeyword(engine)
    # varName
    writeidentifier(engine)
    # ([ expression ])?
    if tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '['
        # [
        writesymbol(engine)
        # expression
        compileexpression(engine)
        # ]
        writesymbol(engine)
    end
    # =
    writesymbol(engine)
    # expression
    compileexpression(engine)
    # ;
    writesymbol(engine)

    write(engine.io, "</letStatement>\n")
end


function compilewhile(engine::CompilationEngine)
    write(engine.io, "<whileStatement>\n")

    # while
    writekeyword(engine)
    # (
    writesymbol(engine)
    # expression
    compileexpression(engine)
    # )
    writesymbol(engine)
    # {
    writesymbol(engine)
    # statements
    compilestatements(engine)
    # }
    writesymbol(engine)

    write(engine.io, "</whileStatement>\n")
end


function compilereturn(engine::CompilationEngine)
    write(engine.io, "<returnStatement>\n")

    # return
    writekeyword(engine)
    # expression?
    if tokentype(engine.tok) != t_symbol || symbol(engine.tok) != ';'
        compileexpression(engine)
    end
    # ;
    writesymbol(engine)

    write(engine.io, "</returnStatement>\n")
end


function compileif(engine::CompilationEngine)
    write(engine.io, "<ifStatement>\n")

    # if
    writekeyword(engine)
    # (
    writesymbol(engine)
    # expression
    compileexpression(engine)
    # )
    writesymbol(engine)
    # {
    writesymbol(engine)
    # statements
    compilestatements(engine)
    # }
    writesymbol(engine)
    # (else { statements })?
    if tokentype(engine.tok) == t_keyword && keyword(engine.tok) == "else"
        # else
        writekeyword(engine)
        # {
        writesymbol(engine)
        # statements
        compilestatements(engine)
        # }
        writesymbol(engine)
    end

    write(engine.io, "</ifStatement>\n")
end


function compileexpression(engine::CompilationEngine)
    write(engine.io, "<expression>\n")

    # term
    compileterm(engine)
    # (op term)*
    while tokentype(engine.tok) == t_symbol && symbol(engine.tok) in op
        # op
        writesymbol(engine)
        # term
        compileterm(engine)
    end

    write(engine.io, "</expression>\n")
end


function compileterm(engine::CompilationEngine)
    write(engine.io, "<term>\n")

    # varName | varName [ expression ] |
    # subroutineCall
    if tokentype(engine.tok) == t_int_const
        # integerConstant
        writeintconst(engine)
    elseif tokentype(engine.tok) == t_string_const
        # stringConstant
        writestringconst(engine)
    elseif tokentype(engine.tok) == t_keyword && keyword(engine.tok) in keywordconst
        # keywordConstant
        writekeyword(engine)
    elseif tokentype(engine.tok) == t_symbol && symbol(engine.tok) in unaryop
        # unaryOp
        writesymbol(engine)
        # term
        compileterm(engine)
    elseif tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '('
        # (
        writesymbol(engine)
        # expression
        compileexpression(engine)
        # )
        writesymbol(engine)
    elseif tokentype(engine.tok) == t_identifier
        # varName | varName [ expression ] | subroutineCall

        # varName | subroutineName
        writeidentifier(engine)

        if tokentype(engine.tok) == t_symbol
            if symbol(engine.tok) == '['
                # [
                writesymbol(engine)
                # expression
                compileexpression(engine)
                # ]
                writesymbol(engine)
            elseif symbol(engine.tok) in ".("
                # (. subroutineName)?
                if tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '.'
                    # .
                    writesymbol(engine)
                    # subroutineName
                    writeidentifier(engine)
                end
                # (
                writesymbol(engine)
                # expressionList
                compileexpressionlist(engine)
                # )
                writesymbol(engine)
            end
        end
    end

    write(engine.io, "</term>\n")
end


function compileexpressionlist(engine::CompilationEngine)
    write(engine.io, "<expressionList>\n")

    if tokentype(engine.tok) != t_symbol || symbol(engine.tok) != ')'
        # expression
        compileexpression(engine)
        # (, expression)*
        while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
            # ,
            writesymbol(engine)
            # expression
            compileexpression(engine)
        end
    end

    write(engine.io, "</expressionList>\n")
end