-- lua/google_news_decoder.lua
-- Decodes Google News article URLs to their actual article URLs
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

-- HTTP POST using curl
local function http_post(url, body, timeout_ms)
    local timeout = (timeout_ms or 15000) / 1000
    local cmd = string.format(
        'curl -sS --max-time %d -L -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -d "%s" "%s"',
        timeout,
        body:gsub('"', '\\"'),
        url
    )

    local reader = io.popen(cmd, "r")
    if not reader then
        return nil
    end

    local resp_body = reader:read("*a")
    reader:close()

    return resp_body
end

-- Extract base64 string from Google News article URL
function _M.get_base64_str(source_url)
    local parsed_host = source_url:match("https?://([^/]+)")
    if not parsed_host or not source_url:find("news.google.com") then
        return { status = false, message = "Invalid Google News URL format." }
    end

    local last_slash = #source_url
    local second_last_slash = 0
    local i = #source_url - 1
    while i > 0 do
        if source_url:sub(i, i) == "/" then
            if second_last_slash == 0 then
                second_last_slash = i
            else
                break
            end
        end
        i = i - 1
    end

    if second_last_slash > 0 then
        local segment = source_url:sub(second_last_slash + 1, last_slash - 1)
        if segment == "articles" or segment == "read" then
            local base64_start = second_last_slash + 1
            local query_pos = source_url:find("?", base64_start)
            if query_pos then
                return { status = true, base64_str = source_url:sub(base64_start, query_pos - 1) }
            else
                return { status = true, base64_str = source_url:sub(base64_start) }
            end
        end
    end

    local m = source_url:match("/articles/([A-Za-z0-9_-]+)")
    if m then
        return { status = true, base64_str = m }
    end

    return { status = false, message = "Invalid Google News URL format." }
end

-- Fetch decoding params (signature and timestamp) from Google News page
function _M.get_decoding_params(base64_str)
    local urls = {
        "https://news.google.com/articles/" .. base64_str,
        "https://news.google.com/rss/articles/" .. base64_str,
    }

    for _, url in ipairs(urls) do
        local html = http_get(url)
        if html then
            -- Exact equivalent of PHP: preg_match('/data-n-a-sg="([^"]+)"/', $html, $m)
            local sg_match = html:match('data%-n%-a%-sg="([^"]+)"')
            local ts_match = html:match('data%-n%-a%-ts="([^"]+)"')
            if sg_match and ts_match then
                return { status = true, signature = sg_match, timestamp = ts_match, base64_str = base64_str }
            end
        end
    end

    return { status = false, message = "Failed to fetch decoding params from Google News." }
end

-- Decode URL using signature + timestamp via Google's batchexecute API
function _M.decode_url(signature, timestamp, base64_str)
    local url = "https://news.google.com/_/DotsSplashUi/data/batchexecute"

    local payload = {
        "Fbv4je",
        string.format(
            "[\"garturlreq\",[[\"X\",\"X\",[\"X\",\"X\"],null,null,1,1,\"US:en\",null,1,null,null,null,null,null,0,1],\"X\",\"X\",1,[1,1,1],1,1,null,0,0,null,0],\"%s\",%s,\"%s\"]",
            base64_str, timestamp, signature
        )
    }

    local cjson = require "cjson"
    local encoded_json = cjson.encode({{payload}})
    -- URL-encode the JSON payload (same as PHP's urlencode())
    local post_body = "f.req=" .. encoded_json:gsub("([^A-Za-z0-9 _.%-])", function(c)
        return ("%%%02X"):format(c:byte())
    end):gsub(" ", "+")

    local response = http_post(url, post_body, 15000)
    if not response then
        return { status = false, message = "Failed to connect to Google News." }
    end

    local json_start = response:find("\n\n", 1, true)
    if not json_start then
        json_start = response:find("\r\r", 1, true)
    end
    local json_str
    if not json_start then
        json_str = response
    else
        json_str = response:sub(json_start + 2)
    end

    local ok, json_data = pcall(cjson.decode, json_str)
    if not ok or not json_data or not json_data[1] then
        return { status = false, message = "Failed to parse JSON." }
    end

    -- PHP: $jsonData[0][2] but Lua is 1-based, so [1][3]
    local parsed_data = json_data[1][3]
    if not parsed_data then
        return { status = false, message = "No decoded data found." }
    end

    local ok2, decoded = pcall(cjson.decode, parsed_data)
    if not ok2 or not decoded then
        return { status = false, message = "Failed to parse inner JSON." }
    end

    -- Inner JSON: ["garturlres","URL",1] → 0-based in JSON but Lua gives us 1-based
    -- PHP accesses $decoded[1] (the URL), which is decoded[2] in Lua
    if decoded[2] then
        return { status = true, decoded_url = decoded[2] }
    end

    return { status = false, message = "Failed to extract decoded URL." }
end

-- Main entry point: decode a Google News article URL to the actual article URL
function _M.decode_google_news_url(source_url)
    local base64_result = _M.get_base64_str(source_url)
    if not base64_result.status then return base64_result end

    local params_result = _M.get_decoding_params(base64_result.base64_str)
    if not params_result.status then return params_result end

    return _M.decode_url(params_result.signature, params_result.timestamp, params_result.base64_str)
end

return _M
