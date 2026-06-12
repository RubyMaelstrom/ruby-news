-- lua/utils/string.lua
-- String helper functions for ruby.news

local _M = {}

-- Replace curly quotes, dashes, and special chars with ASCII equivalents
-- Matches the PHP clean_str() function from index.php and article.php
function _M.clean_str(str)
    if not str then return "" end
    str = str:gsub("\226\128\171", "'")     -- ' (left single quote, U+2018)
    str = str:gsub("\226\128\173", "'")     -- ' (right single quote, U+2019)
    str = str:gsub("\226\128\174", '"')     -- " (left double quote, U+201C)
    str = str:gsub("\226\128\175", '"')     -- " (right double quote, U+201D)
    str = str:gsub("\226\132\146", "-")     -- – (en dash, U+2013)
    str = str:gsub("&nbsp;", " - ")
    return str
end

return _M
