local _M = {}

function _M.strip_tags(html, allowed)
    if not html or not allowed then return "" end

    local allowed_list = {}
    for tag in allowed:gmatch("<([%w_]+)>") do
        allowed_list[tag] = true
    end

    local result = ""
    local i = 1
    local len = #html

    while i <= len do
        if html:sub(i, i) == "<" then
            local tag_end = html:find(">", i, true)
            if not tag_end then
                result = result .. html:sub(i, len)
                break
            end

            local tag_str = html:sub(i, tag_end)
            local is_closing = tag_str:find("^</")

            local tag_name = tag_str:gsub("^<[/]?([%w_]+).*", "%1"):lower()

            if allowed_list[tag_name] then
                result = result .. tag_str
            end

            i = tag_end + 1
        else
            result = result .. html:sub(i, i)
            i = i + 1
        end
    end

    return result
end

return _M
