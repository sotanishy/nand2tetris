struct SymbolTable
    globalscope::Dict{String,Tuple{String,String,Int}}  # static, field
    localscope::Dict{String,Tuple{String,String,Int}}   # arg, var
    count::Dict{String,Int}

    function SymbolTable()
        new(Dict(), Dict(), Dict())
    end
end


# start a new subroutine
function startsubroutine(table::SymbolTable)
    empty!(table.localscope)
    table.count["arg"] = table.count["var"] = 0
end


# define a new symbol
function define(table::SymbolTable, name::String, type::String, kind::String)
    if kind in ("static", "field")
        table.globalscope[name] = (kind, type, varcount(table, kind))
    else
        table.localscope[name] = (kind, type, varcount(table, kind))
    end
    table.count[kind] += 1
end


# return the number of symbols of the given kind
function varcount(table::SymbolTable, kind::String)::Int
    !haskey(table.count, kind) && (table.count[kind] = 0)
    table.count[kind]
end


# return the kind of the given symbol
function kindof(table::SymbolTable, name::String)::String
    if haskey(table.localscope, name)
        table.localscope[name][1]
    elseif haskey(table.globalscope, name)
        table.globalscope[name][1]
    else
        "none"
    end
end


# return the type of the given symbol
function typeof(table::SymbolTable, name::String)::String
    kind = kindof(table, name)
    if kind in ("static", "field")
        table.globalscope[name][2]
    else
        table.localscope[name][2]
    end
end


# return the index of the given symbol
function indexof(table::SymbolTable, name::String)::Int
    kind = kindof(table, name)
    if kind in ("static", "field")
        table.globalscope[name][3]
    else
        table.localscope[name][3]
    end
end