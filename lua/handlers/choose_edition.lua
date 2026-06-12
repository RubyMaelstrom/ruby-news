-- lua/handlers/choose_edition.lua
-- Country edition selector page
-- Replaces choose_edition.php (static HTML, no HTTP calls needed)

local function get_param(name)
    local val = ngx.var["arg_" .. name]
    if val then return val end
    return nil
end

local function handle()
    local loc = get_param("loc") or "US"

    -- List of all supported country editions
    local editions = {
        { code = "US", name = "United States" },
        { code = "JP", name = "Japan" },
        { code = "UK", name = "United Kingdom" },
        { code = "ES", name = "Spain (RIP)" },
        { code = "CA", name = "Canada" },
        { code = "DE", name = "Deutschland" },
        { code = "IT", name = "Italia" },
        { code = "FR", name = "France" },
        { code = "AU", name = "Australia" },
        { code = "TW", name = "Taiwan" },
        { code = "NL", name = "Nederland" },
        { code = "BR", name = "Brasil" },
        { code = "TR", name = "Turkey" },
        { code = "BE", name = "Belgium" },
        { code = "GR", name = "Greece" },
        { code = "IN", name = "India" },
        { code = "MX", name = "Mexico" },
        { code = "DK", name = "Denmark" },
        { code = "AR", name = "Argentina" },
        { code = "CH", name = "Switzerland" },
        { code = "CL", name = "Chile" },
        { code = "AT", name = "Austria" },
        { code = "KR", name = "Korea" },
        { code = "IE", name = "Ireland" },
        { code = "CO", name = "Colombia" },
        { code = "PL", name = "Poland" },
        { code = "PT", name = "Portugal" },
        { code = "PK", name = "Pakistan" },
    }

    local loc_upper = loc:upper()

    -- Build page output
    local out = {}
    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<html><head>'
    out[#out + 1] = '\t<title>ruby.news: Choose Your Edition</title>'
    out[#out + 1] = '</head><body>'

    out[#out + 1] = '   <center><h1><b>ruby.news:</b> <font color="#9400d3"><i>Headlines from the Future</i></font></h1></center>'
    out[#out + 1] = '   <hr>'
    out[#out + 1] = '   <center>'
    out[#out + 1] = '   <small>Basic HTML Google News for vintage computers. Built by <a href="https://youtube.com/ActionRetro" target="_blank"><b>Action Retro</b></a> on YouTube. Tested on Netscape 1.1 through 4 on a Mac SE/30. Updated to lua backend by <a href="https://rubymaelstrom.com">Ruby</a>.</small>'

    out[#out + 1] = '   <p><h2>CHOOSE YOUR EDITION:</h2></p>'

    for _, edition in ipairs(editions) do
       local href = '/news?section=nation&loc=' .. edition.code
        if edition.name:find("RIP") then
            out[#out + 1] = '   <p>' .. edition.name .. '</p>'
        else
            out[#out + 1] = '   <p><a href="' .. href .. '">' .. edition.name .. '</a></p>'
        end
    end

    out[#out + 1] = '   </center>'
    out[#out + 1] = '   <small><a href="/news?loc=' .. loc_upper .. '"> < Back to <font color="#9400d3">ruby.news</font> ' .. loc_upper .. ' front page</a></small>'
    out[#out + 1] = '\t<p><center><small>Powered by Lua on nginx</small></p>'

    out[#out + 1] = '</body></html>'

    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    ngx.say(table.concat(out))
end

handle()
