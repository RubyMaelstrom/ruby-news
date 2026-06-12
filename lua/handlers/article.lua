-- lua/handlers/article.lua
-- Article detail page handler — text-only, no images
-- Uses raw cosockets (ngx.socket.tcp), no external libraries

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

local function get_param(name)
    local val = ngx.var["arg_" .. name]
    if val then return val end
    return nil
end

local function handle()
    ngx.header["X-Robots-Tag"] = "noindex, nofollow"

    local loc = get_param("loc") or "US"
    loc = loc:upper()

    local article_url = get_param("a") or ""
    if not article_url or article_url == "" then
        send_response(400, 'What do you think you\'re doing... >;(')
    end

    -- Validate it's a Google News URL
    if article_url:sub(1, 23) ~= "https://news.google.com" then
        send_response(400, "That's not news :(")
    end

    -- Decode the Google News URL to get the actual article URL
    local decoder = require "google_news_decoder"
    local decode_result = decoder.decode_google_news_url(article_url)

    if not decode_result.status then
        send_response(502, "Failed to decode article URL: " .. (decode_result.message or "unknown error"))
    end

    local actual_article_url = decode_result.decoded_url

    -- Extract content using heuristic parser (fetches + parses in one step)
    local extract = require "article_extract"
    local allowed_tags = "<ol><ul><li><br><p><small><font><b><strong><i><em><blockquote><h1><h2><h3><h4><h5><h6>"

    local readable_article, title = extract.fetch_and_extract(actual_article_url, allowed_tags)
    readable_article = string_utils.clean_str(readable_article)

    if not readable_article or readable_article == "" then
        send_response(500, 'Sorry - working on it! (no content detected)<br>')
    end

    -- Strip remaining disallowed tags from the extracted content
    local html_utils = require "html"
    readable_article = html_utils.strip_tags(readable_article, allowed_tags)

    -- Convert strong/em to b/i for vintage browser compatibility
    readable_article = readable_article:gsub("strong>", "b>"):gsub("em>", "i>")

    -- Build page output
    local out = {}
    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<html><head>'

    local page_title = string_utils.clean_str(title or "ruby.news Article")
    out[#out + 1] = '\t<title>' .. page_title .. '</title>'
    out[#out + 1] = '</head><body>'

    out[#out + 1] = '   <small><a href="/news?loc=' .. loc .. '"> < Back to <font color="#9400d3">ruby.news</font> ' .. loc .. ' front page</a></small>'
    out[#out + 1] = '   <h1>' .. page_title .. '</h1>'

    out[#out + 1] = '   <p><small><a href="' .. actual_article_url .. '" target="_blank">Original source</a> (on modern site)</small></p>'
    out[#out + 1] = '   <p><font size="4">' .. readable_article .. '</font></p>'
    out[#out + 1] = '   <small><a href="/news?loc=' .. loc .. '"> < Back to <font color="#9400d3">ruby.news</font> ' .. loc .. ' front page</a></small>'

    out[#out + 1] = '</body></html>'

    send_response(200, table.concat(out))
end

handle()
