local _M = {}

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

local CONTAINER_CLASSES = {
    "article-body", "articlebody", "article__body", "article_body",
    "entry-content", "entrycontent", "post-body", "postbody",
    "story-body", "storybody", "content-body", "contentbody",
}

local CONTAINER_IDS = {
    "article_body", "articlebody", "storytext", "post_content",
    "article-content", "main-article", "article-text",
    "content", "postbody", "storybody",
}

local function find_best_container(html)
    local best_score = 0
    local best_content = nil
    local best_title = ""

    for _, class_pattern in ipairs(CONTAINER_CLASSES) do
        local start = html:find(class_pattern)
        if start then
            local tag_start = html:find("<[%w]", start - 200, true)
            if not tag_start then tag_start = start - 200 end
            if tag_start < 1 then tag_start = 1 end

            local lt_pos = html:find("<", tag_start, true)
            if lt_pos and lt_pos <= start then
                local gt_pos = html:find(">", lt_pos, true)
                if gt_pos then
                    local full_tag_name = html:sub(lt_pos + 1, gt_pos):match("^([%w_]+)") or ""

                    local content_start = gt_pos + 1
                    local close_pattern = string.format("</%s", full_tag_name:lower())
                    local close_pos = html:find(close_pattern, content_start, true)
                    if close_pos then
                        local content = html:sub(content_start, close_pos - 1)
                        local score = _M._score_content(content)
                        if score > best_score then
                            best_score = score
                            best_content = content
                            local h1_match = content:match("<h[1-6][^>]*>(.-)</h[1-6]>")
                            if h1_match and #h1_match > 5 then
                                best_title = h1_match
                            end
                        end
                    end
                end
            end
        end
    end

    for _, id_pattern in ipairs(CONTAINER_IDS) do
        local id_search = 'id="[^"]*' .. id_pattern:gsub("%-", "%%-") .. '[^"]*"'
        local start = html:find(id_search)
        if not start then
            id_search = "id='[^']*" .. id_pattern:gsub("%-", "%%-") .. "[^']*'"
            start = html:find(id_search)
        end
        if start then
            local tag_start = html:find("<[%w]", start - 200, true)
            if not tag_start then tag_start = start - 200 end
            if tag_start < 1 then tag_start = 1 end

            local lt_pos = html:find("<", tag_start, true)
            if lt_pos and lt_pos <= start then
                local gt_pos = html:find(">", lt_pos, true)
                if gt_pos then
                    local full_tag_name = html:sub(lt_pos + 1, gt_pos):match("^([%w_]+)") or ""

                    local content_start = gt_pos + 1
                    local close_pattern = string.format("</%s", full_tag_name:lower())
                    local close_pos = html:find(close_pattern, content_start, true)
                    if close_pos then
                        local content = html:sub(content_start, close_pos - 1)
                        local score = _M._score_content(content)
                        if score > best_score then
                            best_score = score
                            best_content = content
                            local h1_match = content:match("<h[1-6][^>]*>(.-)</h[1-6]>")
                            if h1_match and #h1_match > 5 then
                                best_title = h1_match
                            end
                        end
                    end
                end
            end
        end
    end

    if not best_content then
        local art_start, art_end = html:find("<article[^>]*>")
        if art_start then
            local close_pos = html:find("</article>", art_end, true)
            if close_pos then
                local content = html:sub(art_end + 1, close_pos - 1)
                local score = _M._score_content(content)
                if score > best_score then
                    best_score = score
                    best_content = content
                end
            end
        end
    end

   if not best_content then
        local body_start, body_end = html:find("<body[^>]*>")
        if body_start then
            local close_pos = html:find("</body>", body_end, true)
            if close_pos then
                best_content = html:sub(body_end + 1, close_pos - 1)
                local title_match = html:match("<title>(.-)</title>")
                if title_match and #title_match > 3 then
                    best_title = title_match
                end
            end
        end
    end

    if not best_content then
        return nil, ""
    end

    return best_content, best_title
end

local function count_words(text)
    local count = 0
    local in_word = false
    for i = 1, #text do
        local c = text:sub(i, i)
        if c:match("[%w%l%u]") then
            if not in_word then
                count = count + 1
                in_word = true
            end
        else
            in_word = false
        end
    end
    return count
end

local function count_paragraphs(content)
    local count = 0
    for _ in content:gmatch("<[/]?[pPsS][%s>/%]]") do
        count = count + 1
    end
    local dbl = content:gmatch("[\r\n][\r\n]")
    for _ in dbl do
        count = count + 1
    end
    return count
end

local function calc_link_density(content)
    local total_words = count_words(content)
    if total_words == 0 then return 1.0 end

    local outside_links = content:gsub("<a[^>]*>.-</a>", " ")
    local outside_words = count_words(outside_links)

    local link_text_words = total_words - outside_words
    if link_text_words < 0 then link_text_words = 0 end

    return link_text_words / math.max(total_words, 1)
end

local function has_headings(content)
    return content:find("<h[1-6][^>]*>") ~= nil
end

_M._score_content = function(content)
    local words = count_words(content)
    if words < 50 then return 0 end

    local paragraphs = count_paragraphs(content)
    local link_density = calc_link_density(content)
    local has_h = has_headings(content)

    local score = words * 1 + paragraphs * 5

    if has_h then
        score = score + 20
    end

    if link_density > 0.3 then
        score = score * (1 - link_density)
    end

    return score
end

function _M.fetch_and_extract(article_url, allowed_tags_str)
    local body = http_get(article_url)
    if not body or #body == 0 then
        return nil, ""
    end

    local content, title = find_best_container(body)
    if not content then
        return nil, ""
    end

    local html_utils = require "html"
    local cleaned = html_utils.strip_tags(content, allowed_tags_str)

    local string_utils = require "string_util"
    cleaned = string_utils.clean_str(cleaned)

    return cleaned, title
end

return _M
