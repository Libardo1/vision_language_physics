module Util

export @not_impl

using MacroTools

macro not_impl(expr)
    has_match = @capture expr f_(args__)
    if has_match
        err_msg = "Function $f not implemented"
        esc(quote
            function $f($(args...))
                error($err_msg)
            end
        end)
    else
        error("Incorrect syntax for @not_impl")
    end
end

end
