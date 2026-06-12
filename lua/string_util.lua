local _M = {}

function _M.clean_str(str)
    if not str then return "" end
    str = str:gsub("\226\128\171", "'")
    str = str:gsub("\226\128\173", "'")
    str = str:gsub("\226\128\174", '"')
    str = str:gsub("\226\128\175", '"')
    str = str:gsub("\226\132\146", "-")
    str = str:gsub("&nbsp;", " - ")
    return str
end

return _M
