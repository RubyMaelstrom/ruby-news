-- lua/rss_fetcher.lua
-- Fetches Google News feeds (JSON or XML) and parses them into a structured format
-- Uses curl via io.popen for reliable HTTPS support

local _M = {}

-- HTTP GET using curl
local function http_get(url, timeout_ms)
    local timeout = (timeout_ms or 15000) / 1000
    local cmd = string.format(
        'curl -sS --max-time %d -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "%s"',
        timeout,
        url
    )

    local reader = io.popen(cmd, "r")
    if not reader then
        return nil
    end

    local body = reader:read("*a")
    reader:close()

    if not body or #body == 0 then
        return nil
    end

    return body
end

-- Parse an XML/RSS feed (Google News RSS/Atom format)
local function parse_xml_feed(body)
    local feed = {
        title = "",
        items = {},
    }

    local title_match = body:match("<title>(.-)</title>")
    if title_match then
        title_match = title_match:gsub("&nbsp;", " - "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        feed.title = title_match
    end

    local items_start = 1
    while true do
        local item_start, item_end = body:find("<item>", items_start)
        if not item_start then break end

        local item_end_tag = body:find("</item>", item_end or item_start)
        if not item_end_tag then break end

        local item_html = body:sub(item_start, item_end_tag + 7)
        items_start = item_end_tag + 7

        local title = ""
        local link = ""
        local description = ""
        local pub_date = ""
        local images = {}

        local t_match = item_html:match("<title>(.-)</title>")
        if t_match then
            t_match = t_match:gsub("&nbsp;", " - "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
            title = t_match
        end

        local l_match = item_html:match("<link>(.-)</link>")
        if l_match then
            l_match = l_match:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
            link = l_match
        end

        local d_match = item_html:match("<description>(.-)</description>")
        if d_match then
            d_match = d_match:gsub("&nbsp;", " - "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
            description = d_match
        end

        local pd_match = item_html:match("<pubDate>(.-)</pubDate>")
        if pd_match then
            pub_date = pd_match
        end

        for img_url in item_html:gmatch('url=["\']([^"\']+)["\']') do
            if not images[img_url] then
                table.insert(images, img_url)
            end
        end

        local item = {
            title = title,
            link = link,
            description = description,
            pub_date = pub_date,
            images = images,
        }

        if title or link then
            table.insert(feed.items, item)
        end
    end

    return feed
end

-- Fetch and parse a Google News feed
function _M.fetch_feed(section, loc, lang)
    local url

    if section then
        url = string.format(
            "https://news.google.com/rss/headlines/section/topic/%s?ned=%s&hl=%s",
            section:upper(), loc, lang
        )
    else
        url = string.format(
            "https://news.google.com/rss?gl=%s&hl=%s-%s&ceid=%s:%s",
            loc, lang, loc, loc, lang
        )
    end

    local body = http_get(url)
    if body and #body > 0 then
        local feed = parse_xml_feed(body)
        return feed
    end

    return nil
end

return _M
