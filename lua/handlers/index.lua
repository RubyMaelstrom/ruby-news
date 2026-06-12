-- lua/handlers/index.lua
-- Main news feed page handler
-- Replaces index.php (main news listing)

local string_utils = require "string_util"

local function send_response(status_code, body)
    ngx.status = status_code
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    if status_code >= 400 then
        ngx.header["X-Robots-Tag"] = "noindex, nofollow"
    end
    ngx.say(body)
    ngx.exit(ngx.OK)
end

-- Get query parameter value (simplified replacement for $_GET)
local function get_param(name)
    local val = ngx.var["arg_" .. name]
    if val then
        return val
    end
    return nil
end

-- Main handler
local function handle()
    local section = get_param("section")
    local loc = get_param("loc") or "US"
    local lang = get_param("lang") or "en"

 

    -- Uppercase location
    loc = loc:upper()

    -- Add noindex header if any query params
    local uri = ngx.var.request_uri or ""
    if uri:find("?") then
        ngx.header["X-Robots-Tag"] = "noindex, nofollow"
    end

    -- Build feed URL
    local feed_url
    if section then
        feed_url = "https://news.google.com/news/rss/headlines/section/topic/" .. section:upper() .. "?ned=" .. loc .. "&hl=" .. lang
    else
        feed_url = "https://news.google.com/rss?gl=" .. loc .. "&hl=" .. lang .. "-" .. loc .. "&ceid=" .. loc .. ":" .. lang
    end

    -- Try to get from cache first
    local cache = ngx.shared.news_cache
    local feed
    local cache_key = "feed:" .. loc .. ":" .. lang .. ":" .. (section or "all")
    if cache then
        local cached = cache:get(cache_key)
        if cached then
            local cjson = require "cjson"
            local ok, decoded = pcall(cjson.decode, cached)
            if ok and decoded then
                feed = decoded
            end
        end
    end
    if not feed then
        -- Fetch the feed
        local fetcher = require "rss_fetcher"
        feed = fetcher.fetch_feed(section, loc, lang)

        -- Cache for 5 minutes (300 seconds)
        if feed then
            local cjson = require "cjson"
            cache:set(cache_key, cjson.encode(feed), 300)
        end
    end

    if not feed or not feed.items or #feed.items == 0 then
        local error_body = string.format(
            '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN"><meta http-equiv="Content-Type" content="text/html; charset=utf-8"><html><head><title>ruby.news: Error</title></head><body><center><h1><b>ruby.news:</b> <font color="#9400d3"><i>Headlines from the Future</i></font></h1></center><hr><small>Unable to load news feed. Please try again later.</small></body></html>'
        )
        send_response(502, error_body)
    end

    -- Build navigation links
    local nav_links = {
        { label = "TOP", params = "loc=" .. loc },
        { label = "WORLD", params = "section=world&loc=" .. loc },
        { label = "NATION", params = "section=nation&loc=" .. loc },
        { label = "BUSINESS", params = "section=business&loc=" .. loc },
        { label = "TECHNOLOGY", params = "section=technology&loc=" .. loc },
        { label = "ENTERTAINMENT", params = "section=entertainment&loc=" .. loc },
        { label = "SPORTS", params = "section=sports&loc=" .. loc },
        { label = "SCIENCE", params = "section=science&loc=" .. loc },
        { label = "HEALTH", params = "section=health&loc=" .. loc },
    }

    -- Build page
    local out = {}

    -- Header
    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<html><head>'
    out[#out + 1] = '\t<title>ruby.news: Headlines From the Future</title>'
    out[#out + 1] = '</head><body>'

    -- Title
    out[#out + 1] = '\t<center><h1><b>ruby.news:</b> <font color="#9400d3"><i>Headlines from the Future</i></font></h1></center>'
    out[#out + 1] = '\t<hr>'
    out[#out + 1] = '\t<center><small>Basic HTML Google News for vintage computers. Built by <a href="https://youtube.com/ActionRetro" target="_blank"><b>Action Retro</b></a> on YouTube. Tested on Netscape 1.1 through 4 on a Mac SE/30. Updated to lua backend by <a href="https://rubymaelstrom.com">Ruby</a>.</small></center>'

    -- Section title
    if section then
        local section_title = (feed.title or ""):upper()
        local parts = {}
        for p in section_title:gmatch("[^ -]+") do
            table.insert(parts, p)
        end
        out[#out + 1] = '\t<center><h2>' .. (parts[1] or section:upper()) .. ' NEWS</h2></center>'
    end

    -- Navigation and edition controls
    out[#out + 1] = '\t<small>'
    out[#out + 1] = '\t<p>'
    out[#out + 1] = '\t<center>'

    local loc_upper = loc:upper()
    for _, link in ipairs(nav_links) do
        out[#out + 1] = '<a href="/news?' .. link.params .. '">' .. link.label .. '</a> '
    end

    out[#out + 1] = '\t<br>'
    out[#out + 1] = '\t<font size="1">-=-=-=-=-=-=-=-=-=-=-=-=-=-</font><br>'
    out[#out + 1] = '\t<br>' .. loc_upper .. ' Edition <a href=/news/choose_edition>(Change)</a></center>'
    out[#out + 1] = '\t</p>'
    out[#out + 1] = '\t</small>'

    -- News items
    local html_utils = require "html"
    local allowed_tags = "<a><ol><ul><li><br><p><small><font><b><strong><i><em><blockquote><h1><h2><h3><h4><h5><h6>"

    for _, item in ipairs(feed.items) do
        local title_clean = string_utils.clean_str(item.title or "")
        local link = item.link or ""

        -- Build article link with loc parameter
        local article_url = "/news/article?loc=" .. loc .. "&a=" .. link

        out[#out + 1] = '\t\t<h3><font size="5"><a href="' .. article_url .. '">' .. title_clean .. '</a></font></h3>'
        out[#out + 1] = '\t\t<p><font size="4">'

        -- Process description
        local desc = item.description or ""
        desc = string_utils.clean_str(desc)

        -- Split on "<li><strong>" to remove Google "View Full Coverage" section
        local parts = {}
        for p in desc:gmatch("[^<]+") do
            table.insert(parts, p)
        end
        -- Actually split by the specific pattern
        local before_strong = desc:match("^(.-)<li><strong>")
        if before_strong then
            desc = before_strong .. "</li></ol></font></p>"
        else
            desc = desc .. "</font></p>"
        end

        -- Update links to include loc parameter
        desc = desc:gsub('<a href="([^"]*)"', function(url)
            if url:find("article") then
                local clean_url = url:gsub("^[%?&]*", "")
               return '<a href="/news/article?loc=' .. loc .. '&a=' .. clean_url .. '"'
            else
                return '<a href="' .. url
            end
        end)

        -- Strip disallowed tags
        local cleaned = html_utils.strip_tags(desc, allowed_tags)

        -- Replace strong/em with b/i
        cleaned = cleaned:gsub("strong>", "b>"):gsub("em>", "i>")

        -- Remove "View Full Coverage on Google News"
        cleaned = cleaned:gsub("View Full Coverage on Google News", "")

        out[#out + 1] = cleaned

        -- Date
        local date_str = ""
        if item.pub_date then
            -- Try to parse and format the date
            -- Google News RSS dates are RFC 822 style: "Fri, 12 Jun 2026 14:00:00 GMT"
            local day = item.pub_date:match("(%d+) (%a+) (%d+)")
            if day then
                -- Convert month name to number
                local months = {Jan="01",Feb="02",Mar="03",Apr="04",May="05",Jun="06",Jul="07",Aug="08",Sep="09",Oct="10",Nov="11",Dec="12"}
                local month = months[item.pub_date:match("(%d+) (%a+) (%d+)")]
                if month then
                    local d, m, y = item.pub_date:match("(%d+) (%a+) (%d+)")
                    local time = item.pub_date:match("(%d+:%d+)") or ""
                    local ampm = "am"
                    if time then
                        local hour = tonumber(time:sub(1, 2))
                        if hour >= 12 then ampm = "pm" end
                        if hour > 12 then hour = hour - 12 end
                        if hour == 0 then hour = 12 end
                        time = string.format("%d:%s %s", hour, time:sub(4), ampm)
                    end
                    date_str = string.format("%s %s %s | %s", d, m or "", y or "", time)
                end
            else
                -- ISO 8601 format from JSON feed: "2026-06-12T14:00:00Z" or similar
                local iso_match = item.pub_date:match("(%d+)-(%d+)-(%d+)")
                if iso_match then
                    local months_text = {["01"]="January",["02"]="February",["03"]="March",["04"]="April",["05"]="May",["06"]="June",["07"]="July",["08"]="August",["09"]="September",["10"]="October",["11"]="November",["12"]="December"}
                    local y, m, d = item.pub_date:match("(%d+)-(%d+)-(%d+)")
                    local time = item.pub_date:match("T?(%d+):(%d+)") or ""
                    local ampm = "am"
                    if time then
                        local hour = tonumber(time)
                        if hour >= 12 then ampm = "pm" end
                        if hour > 12 then hour = hour - 12 end
                        if hour == 0 then hour = 12 end
                        local min = item.pub_date:match("T?%d+:(%d+)") or ""
                        time = string.format("%d:%s %s", hour, min or "00", ampm)
                    end
                    date_str = string.format("%s %s %s | %s", d or "", months_text[m] or m or "", y or "", time)
                else
                    date_str = item.pub_date
                end
            end
        end

        out[#out + 1] = '\t\t</p><p><small>Posted on ' .. date_str .. '</small></p>'
    end

    -- Footer
    out[#out + 1] = '\t<p><center><small>v1.0 Powered by Lua on nginx</small></center></p>'
    out[#out + 1] = '</body></html>'

    send_response(200, table.concat(out))
end

local ok, err = pcall(handle)
if not ok then
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    ngx.status = 502
    ngx.say("<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 2.0//EN\"><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"><html><head><title>ruby.news: Error</title></head><body><center><h1><b>ruby.news:</b> <font color=\"#9400d3\"><i>Headlines from the Future</i></font></h1></center><hr><small>Error: " .. tostring(err) .. "</small></body></html>")
    ngx.exit(ngx.OK)
end
