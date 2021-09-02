const keywordconst = ["true", "false", "null", "this"]

const op = "+-*/&|<>="

const unaryop = "-~"


mutable struct CompilationEngine
    io::IOStream
    tok::JackTokenizer
    table::SymbolTable
    classname::String
    labelcnt::Int

    function CompilationEngine(tok::JackTokenizer, path::String)
        hasmoretokens(tok) && advance!(tok)
        new(open(path, "w"), tok, SymbolTable(), "null", 0)
    end
end


close(engine::CompilationEngine) = Base.close(engine.io)


function compileclass!(engine::CompilationEngine)
    # class className {
    advance!(engine.tok)
    name = identifier(engine.tok)
    engine.classname = name
    advance!(engine.tok)
    advance!(engine.tok)
    # classVarDec*
    while tokentype(engine.tok) == t_keyword && keyword(engine.tok) in ("static", "field")
        compileclassvardec(engine)
    end
    # subroutineDec*
    while tokentype(engine.tok) == t_keyword && keyword(engine.tok) in ("constructor", "function", "method")
        compilesubroutine(engine)
    end
    # }
end


function compileclassvardec(engine::CompilationEngine)
    # (static | field) type varName
    kind = keyword(engine.tok)
    advance!(engine.tok)
    if tokentype(engine.tok) == t_keyword
        type = keyword(engine.tok)
    else
        type = identifier(engine.tok)
    end
    advance!(engine.tok)
    name = identifier(engine.tok)
    define(engine.table, name, type, kind)
    advance!(engine.tok)
    # (, varName)*
    while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
        advance!(engine.tok)
        name = identifier(engine.tok)
        define(engine.table, name, type, kind)
        advance!(engine.tok)
    end
    # ;
    advance!(engine.tok)
end


function compilesubroutine(engine::CompilationEngine)
    startsubroutine(engine.table)
    # (constructor | function | method) (void | type) subroutineName
    kind = keyword(engine.tok)
    advance!(engine.tok)
    if tokentype(engine.tok) == t_keyword
        type = keyword(engine.tok)
    else
        type = identifier(engine.tok)
    end
    advance!(engine.tok)
    name = identifier(engine.tok)
    advance!(engine.tok)
    # ( parameterList ) {
    advance!(engine.tok)
    if kind == "method"
        define(engine.table, "this", engine.classname, "arg")
    end
    compileparameterlist(engine)
    advance!(engine.tok)
    advance!(engine.tok)
    # varDec*
    while tokentype(engine.tok) == t_keyword && keyword(engine.tok) == "var"
        compilevardec(engine)
    end

    nlocals = varcount(engine.table, "var")
    if kind == "method"
        nlocals += 1
    end
    writefunction(engine.io, "$(engine.classname).$name", nlocals)
    if kind == "method"
        writepush(engine.io, "argument", 0)
        writepop(engine.io, "pointer", 0)
    elseif kind == "constructor"
        writepush(engine.io, "constant", varcount(engine.table, "field"))
        writecall(engine.io, "Memory.alloc", 1)
        writepop(engine.io, "pointer", 0)
    end
    # statements
    compilestatements(engine)
    # }
    advance!(engine.tok)
end


function compileparameterlist(engine::CompilationEngine)
    if (tokentype(engine.tok) == t_keyword && keyword(engine.tok) in ("int", "char", "boolean")) || tokentype(engine.tok) == t_identifier
        # type varName
        if tokentype(engine.tok) == t_keyword
            type = keyword(engine.tok)
        else
            type = identifier(engine.tok)
        end
        advance!(engine.tok)
        name = identifier(engine.tok)
        define(engine.table, name, type, "arg")
        advance!(engine.tok)
        # (, type varName)*
        while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
            advance!(engine.tok)
            if tokentype(engine.tok) == t_keyword
                type = keyword(engine.tok)
            else
                type = identifier(engine.tok)
            end
            advance!(engine.tok)
            name = identifier(engine.tok)
            define(engine.table, name, type, "arg")
            advance!(engine.tok)
        end
    end
end


function compilevardec(engine::CompilationEngine)
    # var type varName
    advance!(engine.tok)
    if tokentype(engine.tok) == t_keyword
        type = keyword(engine.tok)
    else
        type = identifier(engine.tok)
    end
    advance!(engine.tok)
    name = identifier(engine.tok)
    advance!(engine.tok)
    define(engine.table, name, type, "var")
    # (, varName)*
    while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
        # , varName
        advance!(engine.tok)
        name = identifier(engine.tok)
        advance!(engine.tok)
        define(engine.table, name, type, "var")
    end
    # ;
    advance!(engine.tok)
end


function compilestatements(engine::CompilationEngine)
    # statement*
    while tokentype(engine.tok) == t_keyword
        k = keyword(engine.tok)
        if k == "let"
            compilelet(engine)
        elseif k == "if"
            compileif!(engine)
        elseif k == "while"
            compilewhile!(engine)
        elseif k == "do"
            compiledo(engine)
        elseif k == "return"
            compilereturn(engine)
        else
            break
        end
    end
end


function compiledo(engine::CompilationEngine)
    # do
    advance!(engine.tok)

    # subroutineCall
    nargs = 0
    # subroutineName or (className | varName)
    name = identifier(engine.tok)
    advance!(engine.tok)
    # (. subroutinename)?
    if tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '.'
        if kindof(engine.table, name) == "none"
            # function
            classname = name
        else
            # method in another class
            nargs += 1
            classname = typeof(engine.table, name)
            segment, index = getsegmentandindex(engine, name)
            writepush(engine.io, segment, index)
        end
        # . subroutineName
        advance!(engine.tok)
        subroutinename = identifier(engine.tok)
        advance!(engine.tok)
    else
        # method in this class
        nargs += 1
        classname = engine.classname
        subroutinename = name
        writepush(engine.io, "pointer", 0)
    end
    # ( expressionList );
    advance!(engine.tok)
    nargs += compileexpressionlist(engine)
    advance!(engine.tok)
    advance!(engine.tok)

    writecall(engine.io, "$classname.$subroutinename", nargs)
    writepop(engine.io, "temp", 0)
end


function compilelet(engine::CompilationEngine)
    array = false
    # let varName
    advance!(engine.tok)
    name = identifier(engine.tok)
    segment, index = getsegmentandindex(engine, name)
    advance!(engine.tok)
    # ([ expression ])?
    if tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '['
        array = true
        # [ expression ]
        advance!(engine.tok)
        compileexpression(engine)
        advance!(engine.tok)

        writepush(engine.io, segment, index)
        writearithmetic(engine.io, "add")
    end
    # = expression ;
    advance!(engine.tok)
    compileexpression(engine)
    advance!(engine.tok)

    if array
        writepop(engine.io, "temp", 0)
        writepop(engine.io, "pointer", 1)
        segment, index = "that", 0
        writepush(engine.io, "temp", 0)
    end
    writepop(engine.io, segment, index)
end


function compilewhile!(engine::CompilationEngine)
    i = engine.labelcnt
    engine.labelcnt += 1
    writelabel(engine.io, "LOOP$i")

    # while ( expression ) {
    advance!(engine.tok)
    advance!(engine.tok)

    compileexpression(engine)
    writearithmetic(engine.io, "not")
    writeif(engine.io, "END$i")

    advance!(engine.tok)
    advance!(engine.tok)
    # statements
    compilestatements(engine)
    # }
    advance!(engine.tok)

    writegoto(engine.io, "LOOP$i")
    writelabel(engine.io, "END$i")
end


function compilereturn(engine::CompilationEngine)
    # return
    advance!(engine.tok)
    # expression?
    if tokentype(engine.tok) != t_symbol || symbol(engine.tok) != ';'
        compileexpression(engine)
    else
        writepush(engine.io, "constant", 0)
    end
    # ;
    advance!(engine.tok)

    writereturn(engine.io)
end


function compileif!(engine::CompilationEngine)
    i = engine.labelcnt
    engine.labelcnt += 1
    # if ( expression ) {
    advance!(engine.tok)
    advance!(engine.tok)

    compileexpression(engine)
    writearithmetic(engine.io, "not")
    writeif(engine.io, "ELSE$i")

    advance!(engine.tok)
    advance!(engine.tok)
    # statements
    compilestatements(engine)
    # }
    advance!(engine.tok)
    writegoto(engine.io, "END$i")
    # (else { statements })?
    writelabel(engine.io, "ELSE$i")
    if tokentype(engine.tok) == t_keyword && keyword(engine.tok) == "else"
        # else {
        advance!(engine.tok)
        advance!(engine.tok)
        # statements
        compilestatements(engine)
        # }
        advance!(engine.tok)
    end

    writelabel(engine.io, "END$i")
end


function compileexpression(engine::CompilationEngine)
    # term
    compileterm(engine)
    # (op term)*
    while tokentype(engine.tok) == t_symbol && symbol(engine.tok) in op
        o = symbol(engine.tok)
        advance!(engine.tok)
        compileterm(engine)
        if o == '+'
            writearithmetic(engine.io, "add")
        elseif o == '-'
            writearithmetic(engine.io, "sub")
        elseif o == '*'
            writecall(engine.io, "Math.multiply", 2)
        elseif o == '/'
            writecall(engine.io, "Math.divide", 2)
        elseif o == '&'
            writearithmetic(engine.io, "and")
        elseif o == '|'
            writearithmetic(engine.io, "or")
        elseif o == '<'
            writearithmetic(engine.io, "lt")
        elseif o == '>'
            writearithmetic(engine.io, "gt")
        elseif o == '='
            writearithmetic(engine.io, "eq")
        end
    end
end


function compileterm(engine::CompilationEngine)
    if tokentype(engine.tok) == t_int_const
        # integerConstant
        writepush(engine.io, "constant", intval(engine.tok))
        advance!(engine.tok)
    elseif tokentype(engine.tok) == t_string_const
        # stringConstant
        s = stringval(engine.tok)
        advance!(engine.tok)

        writepush(engine.io, "constant", length(s))
        writecall(engine.io, "String.new", 1)
        writepop(engine.io, "pointer", 1)
        for c in s
            writepush(engine.io, "pointer", 1)
            writepush(engine.io, "constant", Int(c))
            writecall(engine.io, "String.appendChar", 2)
            writepop(engine.io, "pointer", 1)
        end
        writepush(engine.io, "pointer", 1)
    elseif tokentype(engine.tok) == t_keyword && keyword(engine.tok) in keywordconst
        # keywordConstant
        k = keyword(engine.tok)
        advance!(engine.tok)

        if k == "true"
            writepush(engine.io, "constant", 1)
            writearithmetic(engine.io, "neg")
        elseif k in ("false", "null")
            writepush(engine.io, "constant", 0)
        else  # this
            writepush(engine.io, "pointer", 0)
        end
    elseif tokentype(engine.tok) == t_symbol && symbol(engine.tok) in unaryop
        # unaryOp term
        o = symbol(engine.tok)
        advance!(engine.tok)
        compileterm(engine)
        if o == '-'
            writearithmetic(engine.io, "neg")
        else
            writearithmetic(engine.io, "not")
        end
    elseif tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '('
        # ( expression )
        advance!(engine.tok)
        compileexpression(engine)
        advance!(engine.tok)
    elseif tokentype(engine.tok) == t_identifier
        # varName | varName [ expression ] | subroutineCall

        # varName | subroutineName
        name = identifier(engine.tok)
        advance!(engine.tok)

        if tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '['
            # varName [ expression ]
            advance!(engine.tok)
            compileexpression(engine)
            advance!(engine.tok)

            segment, index = getsegmentandindex(engine, name)
            writepush(engine.io, segment, index)
            writearithmetic(engine.io, "add")
            writepop(engine.io, "pointer", 1)
            writepush(engine.io, "that", 0)
        elseif tokentype(engine.tok) == t_symbol && symbol(engine.tok) in ".("
            # subroutineCall
            nargs = 0
            # (. subroutineName)?
            if tokentype(engine.tok) == t_symbol && symbol(engine.tok) == '.'
                if kindof(engine.table, name) == "none"
                    # function
                    classname = name
                else
                    # method in another class
                    nargs += 1
                    classname = typeof(engine.table, name)
                    segment, index = getsegmentandindex(engine, name)
                    writepush(engine.io, segment, index)
                end
                # . subroutineName
                advance!(engine.tok)
                subroutinename = identifier(engine.tok)
                advance!(engine.tok)
            else
                # method in this class
                nargs += 1
                classname = engine.classname
                subroutinename = name
                writepush(engine.io, "pointer", 0)
            end
            # ( expressionList )
            advance!(engine.tok)
            nargs += compileexpressionlist(engine)
            advance!(engine.tok)

            writecall(engine.io, "$classname.$subroutinename", nargs)
        else
            # varName
            segment, index = getsegmentandindex(engine, name)
            writepush(engine.io, segment, index)
        end
    end
end


# return the number of expressions
function compileexpressionlist(engine::CompilationEngine)::Int
    cnt = 0
    if tokentype(engine.tok) != t_symbol || symbol(engine.tok) != ')'
        # expression
        compileexpression(engine)
        cnt += 1
        # (, expression)*
        while tokentype(engine.tok) == t_symbol && symbol(engine.tok) == ','
            # , expression
            advance!(engine.tok)
            compileexpression(engine)
            cnt += 1
        end
    end
    cnt
end


function getsegmentandindex(engine::CompilationEngine, name::String)
    kind = kindof(engine.table, name)
    if kind == "static"
        segment = "static"
    elseif kind == "field"
        segment = "this"
    elseif kind == "arg"
        segment = "argument"
    else  # var
        segment = "local"
    end
    index = indexof(engine.table, name)
    segment, index
end