script_name('CBUGER LOW')
script_author('by Pryanix')
script_version(1.0)

local CBUGER_RESTORE_SHOWCURSOR_PATCH
local CBUGER_SHOWCURSOR_PATCH = nil
do
    local original = showCursor
    local existing = rawget(_G, '__CBUGER_SHOWCURSOR_DEDUP')
    if type(existing) == 'table'
        and type(existing.original) == 'function'
        and type(existing.wrapper) == 'function'
        and original == existing.wrapper then
        CBUGER_SHOWCURSOR_PATCH = existing
    elseif type(original) == 'function' then
        local last_state = nil
        local function stable_show_cursor(show, ...)
            local visible = show and true or false
            if visible == last_state then return end
            last_state = visible
            return original(visible, ...)
        end
        CBUGER_SHOWCURSOR_PATCH = {
            original = original,
            wrapper = stable_show_cursor,
            hide = function()
                last_state = false
                return original(false)
            end
        }
        rawset(_G, '__CBUGER_SHOWCURSOR_DEDUP', CBUGER_SHOWCURSOR_PATCH)
        showCursor = stable_show_cursor
    end
end

CBUGER_RESTORE_SHOWCURSOR_PATCH = function()
    local patch = CBUGER_SHOWCURSOR_PATCH
    if type(patch) ~= 'table' then return end
    if showCursor == patch.wrapper then
        showCursor = patch.original
    end
    if rawget(_G, '__CBUGER_SHOWCURSOR_DEDUP') == patch then
        rawset(_G, '__CBUGER_SHOWCURSOR_DEDUP', nil)
    end
end

function CBUGER_FORCE_HIDE_CURSOR()
    local patch = CBUGER_SHOWCURSOR_PATCH
    if type(patch) == 'table' and type(patch.hide) == 'function' then
        pcall(patch.hide)
    elseif type(patch) == 'table' and type(patch.original) == 'function' then
        pcall(patch.original, false)
    else
        pcall(showCursor, false)
    end
    pcall(sampSetCursorMode, 0)
end
do
    local lfs_ = require('lfs')
    local M = {}
    local pending_ini_saves = rawget(_G, '__CBUGER_PENDING_INICFG_SAVES')
    if type(pending_ini_saves) ~= 'table' then
        pending_ini_saves = {}
        rawset(_G, '__CBUGER_PENDING_INICFG_SAVES', pending_ini_saves)
    end
    local function mkdirs(dir)
        dir = tostring(dir or ''):gsub('/', '\\'):gsub('\\+$', '')
        local acc = ''
        for part in dir:gmatch('[^\\]+') do
            acc = (acc == '') and part or (acc .. '\\' .. part)
            if not acc:match('^%a:$') then
                local ok, mode = pcall(lfs_.attributes, acc, 'mode')
                if not (ok and mode == 'directory') then pcall(lfs_.mkdir, acc) end
            end
        end
    end
    function M.resolve(name)
        name = tostring(name or 'cbuger')
        if not name:lower():match('%.ini$') then name = name .. '.ini' end
        if name:match('^%a:[\\/]') or name:match('^[\\/][\\/]') then return name end
        name = name:gsub('^moonloader[\\/]config[\\/]', ''):gsub('^config[\\/]', ''):gsub('/', '\\')
        local base = CBUGER_CONFIG or (getWorkingDirectory() .. '\\CBUGER PRO\\config\\')
        return base .. name
    end
    local function read_all(path)
        local f = io.open(path, 'rb')
        if not f then
            local ok_exists, exists = pcall(function()
                if type(doesFileExist) == 'function' then return doesFileExist(path) end
                local attr, attr_err = lfs_.attributes(path)
                if attr ~= nil then return true end
                local err_text = tostring(attr_err or ''):lower()
                if err_text:find('no such file', 1, true)
                    or err_text:find('not found', 1, true)
                    or err_text:find('cannot find', 1, true) then
                    return false
                end
                return true
            end)
            if not ok_exists then return nil, true end
            return nil, exists and true or false
        end
        local ok_read, data = pcall(function() return f:read('*a') end)
        local ok_close, close_result = pcall(function() return f:close() end)
        if not ok_read or type(data) ~= 'string' or not ok_close or close_result == nil then
            return nil, true
        end
        return data, false
    end



    local pending_safe_writes = rawget(_G, '__CBUGER_PENDING_SAFE_WRITES')
    if type(pending_safe_writes) ~= 'table' then
        pending_safe_writes = {}
        rawset(_G, '__CBUGER_PENDING_SAFE_WRITES', pending_safe_writes)
    end

    local function CBUGER_SAFE_WRITE_FILE_IMPL(path, content)
        if type(path) ~= 'string' or path == '' or type(content) ~= 'string' then return false end
        local dir = path:match('^(.*)[\\/][^\\/]*$') or ''
        mkdirs(dir)
        local tmp, bak = path .. '.tmp', path .. '.bak'
        pcall(os.remove, tmp)

        local f = io.open(tmp, 'wb')
        if not f then return false end
        local ok_write, write_result = pcall(function() return f:write(content) end)
        local ok_flush, flush_result = pcall(function() return f:flush() end)
        local ok_close, close_result = pcall(function() return f:close() end)
        if not ok_write or write_result == nil or not ok_flush or flush_result == nil
            or not ok_close or close_result == nil then
            pcall(os.remove, tmp)
            return false
        end
        if read_all(tmp) ~= content then
            pcall(os.remove, tmp)
            return false
        end

        local old_data, old_read_error = read_all(path)
        if old_read_error then
            pcall(os.remove, tmp)
            return false
        end
        if old_data ~= nil then

            local ok_remove, remove_result = pcall(os.remove, bak)
            if not ok_remove or remove_result == nil then

                local check_bak = read_all(bak)
                if check_bak ~= nil then
                    pcall(os.remove, tmp)
                    return false
                end
            end
            local ok_backup, backup_result = pcall(os.rename, path, bak)
            if not ok_backup or not backup_result then
                pcall(os.remove, tmp)
                return false
            end
        end

        local ok_rename, rename_result = pcall(os.rename, tmp, path)
        if not ok_rename or not rename_result then
            if old_data ~= nil then pcall(os.rename, bak, path) end
            pcall(os.remove, tmp)
            return false
        end

        if read_all(path) ~= content then
            pcall(os.remove, path)
            if old_data ~= nil then pcall(os.rename, bak, path) end
            return false
        end
        return true
    end

    function CBUGER_SAFE_WRITE_FILE(path, content)
        if type(path) ~= 'string' or path == '' or type(content) ~= 'string' then return false end
        local ok, saved = pcall(CBUGER_SAFE_WRITE_FILE_IMPL, path, content)
        saved = ok and saved == true
        if saved then
            pending_safe_writes[path] = nil
        else
            pending_safe_writes[path] = content
        end
        return saved
    end

    function CBUGER_SAFE_RESTORE_FILE(path, content)
        if type(path) ~= 'string' or path == '' or type(content) ~= 'string' then return false end
        local dir = path:match('^(.*)[\\/][^\\/]*$') or ''
        mkdirs(dir)
        local tmp, broken = path .. '.restore.tmp', path .. '.invalid'
        pcall(os.remove, tmp)
        local f = io.open(tmp, 'wb')
        if not f then return false end
        local ok_write, wr = pcall(function() return f:write(content) end)
        local ok_flush, fl = pcall(function() return f:flush() end)
        local ok_close, cl = pcall(function() return f:close() end)
        if not ok_write or wr == nil or not ok_flush or fl == nil or not ok_close or cl == nil then
            pcall(os.remove, tmp); return false
        end
        if read_all(tmp) ~= content then pcall(os.remove, tmp); return false end
        local current_data, current_read_error = read_all(path)
        if current_read_error then pcall(os.remove, tmp); return false end
        local had_broken = current_data ~= nil
        if had_broken then
            pcall(os.remove, broken)
            local ok_move, moved = pcall(os.rename, path, broken)
            if not ok_move or not moved then pcall(os.remove, tmp); return false end
        end
        local ok_move, moved = pcall(os.rename, tmp, path)
        if not ok_move or not moved or read_all(path) ~= content then
            pcall(os.remove, path)
            if had_broken then pcall(os.rename, broken, path) end
            pcall(os.remove, tmp)
            return false
        end
        return true
    end

    function CBUGER_SAFE_READ_TEXT(path, validator)
        if type(path) ~= 'string' or path == '' then return nil end
        local function valid_text(value)
            if type(value) ~= 'string' or value == '' then return false end
            if type(validator) ~= 'function' then return true end
            local ok, result = pcall(validator, value)
            return ok and result and true or false
        end
        local raw = read_all(path)
        if valid_text(raw) then return raw end
        local backup = read_all(path .. '.bak')
        if valid_text(backup) then
            pcall(CBUGER_SAFE_RESTORE_FILE, path, backup)
            return backup
        end
        return nil
    end

    function CBUGER_SAFE_LOAD_JSON(path, validator)
        if type(path) ~= 'string' or path == '' or type(decodeJson) ~= 'function' then return nil end
        for _, candidate in ipairs({path, path .. '.bak'}) do
            local raw = read_all(candidate)
            if raw and raw ~= '' then
                local ok, decoded = pcall(decodeJson, raw)
                local valid = ok and type(decoded) == 'table'
                if valid and type(validator) == 'function' then
                    local vok, vres = pcall(validator, decoded)
                    valid = vok and vres and true or false
                end
                if valid then
                    if candidate ~= path then pcall(CBUGER_SAFE_RESTORE_FILE, path, raw) end
                    return decoded
                end
            end
        end
        return nil
    end

    local function conv(v)
        v = tostring(v or ''):match('^%s*(.-)%s*$')
        if v == 'true' then return true end
        if v == 'false' then return false end
        local n = tonumber(v)
        if n ~= nil then return n end
        return v
    end
    local function parse(path)
        local f = io.open(path, 'rb')
        if not f then return nil end
        local ok_read, text = pcall(function() return f:read('*a') end)
        local ok_close, close_result = pcall(function() return f:close() end)
        if not ok_read or type(text) ~= 'string' or not ok_close or close_result == nil or text == '' then
            return nil
        end
        if text:sub(1, 3) == '\239\187\191' then text = text:sub(4) end
        local data, sec = {}, nil
        for line in (text .. '\n'):gmatch('([^\r\n]*)\r?\n') do
            local l = line:match('^%s*(.-)%s*$')
            if l ~= '' and l:sub(1, 1) ~= ';' then
                local sname = l:match('^%[(.-)%]$')
                if sname then
                    sec = sname
                    data[sec] = data[sec] or {}
                elseif sec then
                    local k, v = l:match('^([^=]-)%s*=%s*(.*)$')
                    if k and k ~= '' then data[sec][k] = conv(v) end
                end
            end
        end
        return data
    end
    local function merge(dst, src)
        for k, v in pairs(src) do
            if dst[k] == nil then
                if type(v) == 'table' then dst[k] = {}; merge(dst[k], v) else dst[k] = v end
            elseif type(v) == 'table' and type(dst[k]) == 'table' then
                merge(dst[k], v)
            end
        end
    end
    function M.save(data, name)
        if type(data) ~= 'table' then return false end
        local path = M.resolve(name)
        local list = {}
        for sname, t in pairs(data) do
            if type(t) == 'table' then list[#list + 1] = { tostring(sname), t } end
        end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        local out = {}
        for _, e in ipairs(list) do
            out[#out + 1] = '[' .. e[1] .. ']'
            local keys = {}
            for k, v in pairs(e[2]) do
                local tv = type(v)
                if tv == 'number' or tv == 'string' or tv == 'boolean' then keys[#keys + 1] = k end
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local v = e[2][k]
                if type(v) == 'string' then v = v:gsub('[\r\n]+', ' ') end
                out[#out + 1] = tostring(k) .. '=' .. tostring(v)
            end
            out[#out + 1] = ''
        end
        local saved = CBUGER_SAFE_WRITE_FILE(path, table.concat(out, '\r\n'))
        pending_ini_saves[path] = nil
        return saved
    end
    local function has_ini_values(data)
        if type(data) ~= 'table' then return false end
        for _, section in pairs(data) do
            if type(section) == 'table' and next(section) ~= nil then return true end
        end
        return false
    end
    function M.load(def, name)
        local path = M.resolve(name)
        local data = parse(path)
        if not has_ini_values(data) then
            local backup_path = path .. '.bak'
            local backup_data = parse(backup_path)
            if has_ini_values(backup_data) then
                local backup_text = read_all(backup_path)
                if backup_text then pcall(CBUGER_SAFE_RESTORE_FILE, path, backup_text) end
                data = backup_data
            else
                data = nil
            end
        end
        if data == nil then
            if def == nil then return nil end
            data = {}
            merge(data, def)
            pcall(M.save, data, name)
            return data
        end
        if type(def) == 'table' then merge(data, def) end
        return data
    end
    local retry_pending_at = 0
    function CBUGER_RETRY_PENDING_WRITES(force)
        local now = os.clock()
        if not force and now < retry_pending_at then return end
        retry_pending_at = now + 5.0

        for path, content in pairs(pending_safe_writes) do
            if type(content) == 'string' then
                pcall(CBUGER_SAFE_WRITE_FILE, path, content)
            else
                pending_safe_writes[path] = nil
            end
        end
        for path in pairs(pending_ini_saves) do pending_ini_saves[path] = nil end
    end

    package.loaded['inicfg'] = M
    package.preload['inicfg'] = function() return M end
end
local ffi      = require 'ffi'
local imgui    = require 'mimgui'
local encoding = require 'encoding'
local inicfg   = require 'inicfg'
local sampev   = require 'lib.samp.events'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local fa = require 'fAwesome6_solid'
local lfs  = require('lfs')
local memory = require('memory')
CBUGER_CORE = CBUGER_CORE or {}
CBUGER_CORE.libs = CBUGER_CORE.libs or {}
CBUGER_CORE.util = CBUGER_CORE.util or {}
CBUGER_CORE.libs.ffi      = ffi
CBUGER_CORE.libs.imgui    = imgui
CBUGER_CORE.libs.encoding = encoding
CBUGER_CORE.libs.inicfg   = inicfg
CBUGER_CORE.libs.sampev   = sampev
CBUGER_CORE.libs.lfs      = lfs
CBUGER_CORE.libs.memory   = memory
CBUGER_CORE.libs.fa       = fa
CBUGER_CORE.libs.moonloader = require('moonloader')
local CoreUtil = CBUGER_CORE.util
if not CoreUtil.clamp then
    function CoreUtil.clamp(v, lo, hi)
        v = tonumber(v)
        if v == nil then return lo end
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end
end
if not CoreUtil.clamp01 then
    function CoreUtil.clamp01(v)
        return CoreUtil.clamp(v, 0.0, 1.0)
    end
end
if not CoreUtil.lerp then
    function CoreUtil.lerp(a, b, t)
        return a + (b - a) * t
    end
end
if not CoreUtil.toBool then
    function CoreUtil.toBool(v, default)
        if v == nil then return default end
        if v == true or v == '1' or v == 'true' or v == 'TRUE' then return true end
        if v == false or v == '0' or v == 'false' or v == 'FALSE' then return false end
        return default
    end
end
if not CoreUtil.toNumber then
    function CoreUtil.toNumber(v, default)
        local n = tonumber(v)
        return n ~= nil and n or default
    end
end
if not CoreUtil.ensureDir then
    function CoreUtil.ensureDir(path)
        local ok, mode = pcall(lfs.attributes, path, 'mode')
        if ok and mode == 'directory' then return true end
        if type(cbugerEnsureDir) == 'function' then cbugerEnsureDir(path) else pcall(lfs.mkdir, path) end
        local ok2, mode2 = pcall(lfs.attributes, path, 'mode')
        return ok2 and mode2 == 'directory'
    end
end
if not CoreUtil.packColor then
    function CoreUtil.packColor(r, g, b, a)
        local R = math.floor(CoreUtil.clamp01(r) * 255)
        local G = math.floor(CoreUtil.clamp01(g) * 255)
        local B = math.floor(CoreUtil.clamp01(b) * 255)
        local A = math.floor(CoreUtil.clamp01(a) * 255)
        return A * 16777216 + B * 65536 + G * 256 + R
    end
end
CBUGER_RUNTIME_READY = false
CBUGER_RENDER_READY  = false
CBUGER_NATIVE_READY  = false
function CBUGER_IS_GAME_STABLE()
    if not isSampAvailable() then return false end
    local ped = PLAYER_PED
    if not ped or ped == 0 then return false end
    local ok_ped, exists = pcall(doesCharExist, ped)
    if not ok_ped or not exists then return false end
    local ok_res, sw, sh = pcall(getScreenResolution)
    if not ok_res or type(sw) ~= 'number' or type(sh) ~= 'number' then return false end
    if sw < 640 or sh < 480 or sw > 10000 or sh > 10000 then return false end
    local ok_id, sid = pcall(function()
        return select(2, sampGetPlayerIdByCharHandle(ped))
    end)
    if not ok_id or type(sid) ~= 'number' or sid < 0 then return false end
    return true
end
function CBUGER_WAIT_RUNTIME_READY()
    while not CBUGER_RUNTIME_READY do
        wait(100)
    end
end
function CBUGER_GET_INTERFACE_ALPHA()
    local ptr = nil
    if type(CB) == 'table' then
        ptr = CB.interface_alpha
        if not ptr and type(CB.ui) == 'table' then
            ptr = CB.ui.interface_alpha
        end
    end
    local a = ptr and tonumber(ptr[0]) or 1.0
    if type(a) ~= 'number' then a = 1.0 end
    if a < 0.0 then return 0.0 end
    if a > 1.0 then return 1.0 end
    return a
end
function CBUGER_ApplyGlobalAlphaU32(color)
    local c = tonumber(color) or 0
    if c < 0 then c = c + 4294967296 end
    local a = math.floor(c / 16777216) % 256
    local rgb = c - a * 16777216
    local ga = CBUGER_GET_INTERFACE_ALPHA()
    local na = math.floor(a * ga + 0.5)
    return rgb + na * 16777216
end
function CBUGER_ApplyOverlayAlphaU32(color)
    local c = tonumber(color) or 0
    if c < 0 then c = c + 4294967296 end
    return c
end

function CBUGER_GET_EFFECTS()
    local cbfx = (type(CB) == 'table') and CB.fx or nil
    if type(cbfx) == 'table' then
        if rawget(_G, 'fx_cfg') ~= cbfx then
            rawset(_G, 'fx_cfg', cbfx)
        end
        return cbfx
    end
    local legacy = rawget(_G, 'fx_cfg')
    if type(legacy) == 'table' then return legacy end
    return nil
end
function CBUGER_GET_EFFECT_SPEED(default_value)
    local fx = CBUGER_GET_EFFECTS()
    local ptr = fx and fx.waves_speed
    local v = ptr and tonumber(ptr[0]) or tonumber(default_value) or 1.0
    if v < 0.1 then v = 0.1 end
    if v > 3.0 then v = 3.0 end
    return v
end
function CBUGER_GET_ANIM_RATE(base_rate)
    return (tonumber(base_rate) or 10.0) * CBUGER_GET_EFFECT_SPEED(1.0)
end

CBUGER_RESIZE_STATE = CBUGER_RESIZE_STATE or {}
function CBUGER_PREPARE_WINDOW_SIZE(id, default_w, default_h)
    local key = tostring(id or 'window')
    local st = CBUGER_RESIZE_STATE[key]
    if type(st) ~= 'table' then
        st = { w = default_w or 400, h = default_h or 300,
               resizing = false, start_w = 0, start_h = 0,
               start_x = 0, start_y = 0 }
        CBUGER_RESIZE_STATE[key] = st
    end
    st.w = tonumber(st.w) or tonumber(default_w) or 400
    st.h = tonumber(st.h) or tonumber(default_h) or 300
    return st
end
function CBUGER_APPLY_WINDOW_SIZE(id, default_w, default_h)
    local im = (type(CB) == 'table' and CB.Data and CB.Data.nfn and CB.Data.nfn.mimgui) or imgui
    local st = CBUGER_PREPARE_WINDOW_SIZE(id, default_w, default_h)
    if im and im.SetNextWindowSize then
        im.SetNextWindowSize(im.ImVec2(st.w, st.h), im.Cond.Always)
    end
    return st
end
function CBUGER_DRAW_INVISIBLE_RESIZER(id, st, min_w, min_h, alpha_mult, draw_lines, size_ref)
    local im = (type(CB) == 'table' and CB.Data and CB.Data.nfn and CB.Data.nfn.mimgui) or imgui
    if not im or type(st) ~= 'table' then return end
    min_w = tonumber(min_w) or 250
    min_h = tonumber(min_h) or 180
    alpha_mult = tonumber(alpha_mult) or CBUGER_GET_INTERFACE_ALPHA()
    draw_lines = draw_lines ~= false
    local saved_cursor = im.GetCursorScreenPos()
    local pos = im.GetWindowPos()
    local size = im.GetWindowSize()
    local grab = 20
    local mx = im.GetMousePos().x
    local my = im.GetMousePos().y
    local gx = pos.x + size.x - grab
    local gy = pos.y + size.y - grab
    local hovered = mx >= gx and mx <= pos.x + size.x and my >= gy and my <= pos.y + size.y
    im.SetCursorScreenPos(im.ImVec2(gx, gy))
    im.InvisibleButton('##CBUGER_UniversalResizer_' .. tostring(id), im.ImVec2(grab, grab))
    local active = im.IsItemActive()
    hovered = hovered or im.IsItemHovered()
    if im.IsItemClicked(0) and not st.resizing then
        st.resizing = true
        st.w = size.x
        st.h = size.y
        st.start_w = size.x
        st.start_h = size.y
        local mp = im.GetMousePos()
        st.start_x = mp.x
        st.start_y = mp.y
    end
    if st.resizing then
        if im.IsMouseDown(0) then
            local mp = im.GetMousePos()
            st.w = math.max(min_w, st.start_w + (mp.x - st.start_x))
            st.h = math.max(min_h, st.start_h + (mp.y - st.start_y))
        else
            st.resizing = false
        end
    elseif active and im.IsMouseDown(0) then
        st.resizing = true
    end
    if type(size_ref) == 'table' then
        if size_ref.x ~= nil then size_ref.x = st.w end
        if size_ref.y ~= nil then size_ref.y = st.h end
        if size_ref.w ~= nil then size_ref.w = st.w end
        if size_ref.h ~= nil then size_ref.h = st.h end
    end
    if hovered or st.resizing then
        if im.SetMouseCursor then
            local cursor_id = (im.MouseCursor and im.MouseCursor.ResizeNWSE) or 6
            pcall(im.SetMouseCursor, cursor_id)
        end
    end
    if draw_lines then
        local dl = im.GetWindowDrawList()
        local rc = (type(CB) == 'table' and CB.Data and CB.Data.neon_active_colors and CB.Data.neon_active_colors[im.Col.ResizeGrip]) or nil
        local c = rc or ((type(CB) == 'table' and CB.fx and CB.fx.icon_resize_color) or {0.7, 0.0, 1.0, 0.67})
        local a = (c[4] or 0.67) * alpha_mult
        local packed = nil
        if type(Data) == 'table' and Data.nfn and Data.nfn.pack_color then
            packed = Data.nfn.pack_color(c[1] or 0.7, c[2] or 0, c[3] or 1, a, true, 1.0)
        elseif im.GetColorU32Vec4 then
            packed = im.GetColorU32Vec4(im.ImVec4(
                c[1] or 0.7, c[2] or 0, c[3] or 1, a))
        elseif im.GetColorU32 then
            packed = CBUGER_CORE.util.packColor(c[1] or 0.7, c[2] or 0, c[3] or 1, a)
        end
        if packed then
            dl:AddLine(im.ImVec2(pos.x + size.x - 5, pos.y + size.y - 2), im.ImVec2(pos.x + size.x - 2, pos.y + size.y - 5), packed, 1.5)
            dl:AddLine(im.ImVec2(pos.x + size.x - 9, pos.y + size.y - 2), im.ImVec2(pos.x + size.x - 2, pos.y + size.y - 9), packed, 1.0)
        end
    end
    im.SetCursorScreenPos(saved_cursor)
end
CBUGER_FONT_STATE = CBUGER_FONT_STATE or {
    neon_idx_ptr = nil,
    last_neon_idx = nil,
    shared_idx = 0,
}
function CBUGER_SYNC_GLOBAL_FONT_INDEX()
    local st = CBUGER_FONT_STATE
    local cb = (type(CB) == 'table') and CB or nil
    local neon = cb and cb.neon
    if not st.neon_idx_ptr and neon and neon.current_font_idx then
        st.neon_idx_ptr = neon.current_font_idx
    end
    local neon_idx = st.neon_idx_ptr and tonumber(st.neon_idx_ptr[0]) or 0
    if st.last_neon_idx == nil or neon_idx ~= st.last_neon_idx then
        st.shared_idx = neon_idx
    end
    local data = cb and cb.Data
    local fonts = data and data.neon_loaded_fonts
    local max_idx = (type(fonts) == 'table') and #fonts or 0
    st.shared_idx = math.max(0, math.min(tonumber(st.shared_idx) or 0, max_idx))
    if st.neon_idx_ptr then
        st.neon_idx_ptr[0] = st.shared_idx
    end
    st.last_neon_idx = st.neon_idx_ptr and tonumber(st.neon_idx_ptr[0]) or st.shared_idx
    return st.shared_idx
end
function CBUGER_GET_GLOBAL_FONT()
    local cb = (type(CB) == 'table') and CB or nil
    local data = cb and cb.Data
    local fonts = data and data.neon_loaded_fonts
    if type(fonts) ~= 'table' then return nil end
    local idx = CBUGER_SYNC_GLOBAL_FONT_INDEX()
    if idx > 0 and fonts[idx] ~= nil then
        return fonts[idx]
    end
    return nil
end

function CBUGER_APPLY_GLOBAL_FONT_DEFAULT()
    local fnt = CBUGER_GET_GLOBAL_FONT()
    local ok, io = pcall(imgui.GetIO)
    if not ok or not io then return end
    pcall(function() io.FontDefault = fnt end)
end
function CBUGER_PUSH_GLOBAL_FONT()
    local fnt = CBUGER_GET_GLOBAL_FONT()
    if fnt == nil or type(imgui) ~= 'table' or type(imgui.PushFont) ~= 'function' then
        return false
    end
    local ok = pcall(imgui.PushFont, fnt)
    return ok and true or false
end
function CBUGER_POP_GLOBAL_FONT(pushed)
    if pushed and type(imgui) == 'table' and type(imgui.PopFont) == 'function' then
        pcall(imgui.PopFont)
    end
end
do
    local mt = (type(imgui) == 'table') and imgui or nil
    local original_onframe = mt and mt.OnFrame
    if mt and type(original_onframe) == 'function' and not mt.__CBUGER_GLOBAL_FONT_ONFRAME then
        mt.__CBUGER_GLOBAL_FONT_ONFRAME = true
        mt.__CBUGER_ORIGINAL_ONFRAME = original_onframe
        mt.OnFrame = function(condition, draw_callback, ...)
            if type(draw_callback) ~= 'function' then
                return original_onframe(condition, draw_callback, ...)
            end
            local guarded_condition = function(...)
                if not CBUGER_RENDER_READY then return false end
                if type(condition) == 'function' then
                    return condition(...)
                end
                return condition and true or false
            end
            local wrapped_callback = function(self)
                CBUGER_APPLY_GLOBAL_FONT_DEFAULT()
                local pushed = CBUGER_PUSH_GLOBAL_FONT()
                local ok, err = xpcall(function()
                    draw_callback(self)
                end, debug.traceback)
                CBUGER_POP_GLOBAL_FONT(pushed)
                if not ok then error(err, 0) end
            end
            return original_onframe(guarded_condition, wrapped_callback, ...)
        end
    end
end
CBUGER_ROOT   = getWorkingDirectory() .. '\\CBUGER PRO\\'
CBUGER_CONFIG = CBUGER_ROOT .. 'config\\'
CBUGER_ROOT_HINT = 'moonloader\\CBUGER PRO\\'
function cbugerEnsureDir(path)
    path = tostring(path or ''):gsub('/', '\\'):gsub('\\+$', '')
    local acc = ''
    for part in path:gmatch('[^\\]+') do
        acc = (acc == '') and part or (acc .. '\\' .. part)
        if not acc:match('^%a:$') then
            local ok, mode = pcall(lfs.attributes, acc, 'mode')
            if not (ok and mode == 'directory') then pcall(lfs.mkdir, acc) end
        end
    end
end
function cbugerMoveTree(src, dst)
    local ok, mode = pcall(lfs.attributes, src, 'mode')
    if not ok or mode ~= 'directory' then return end
    cbugerEnsureDir(dst)
    local names = {}
    pcall(function() for n in lfs.dir(src) do if n ~= '.' and n ~= '..' then names[#names + 1] = n end end end)
    for _, n in ipairs(names) do
        local sp, dp = src .. n, dst .. n
        local m = lfs.attributes(sp, 'mode')
        if m == 'directory' then
            cbugerMoveTree(sp .. '\\', dp .. '\\')
        elseif m == 'file' and not lfs.attributes(dp, 'mode') then
            if not os.rename(sp, dp) then
                local fi = io.open(sp, 'rb')
                if fi then
                    local d = fi:read('*a'); fi:close()
                    if type(d) == 'string' and CBUGER_SAFE_WRITE_FILE(dp, d) then os.remove(sp) end
                end
            end
        end
    end
    pcall(lfs.rmdir, src)
end
do
    local wd = getWorkingDirectory() .. '\\'
    local function isdir(p) local o, m = pcall(lfs.attributes, p, 'mode'); return o and m == 'directory' end
    for _, old in ipairs({ 'Cbuger', 'CBUGER' }) do
        local op = wd .. old .. '\\'
        if isdir(op) then
            if not isdir(CBUGER_ROOT) then
                if not os.rename(wd .. old, wd .. 'CBUGER PRO') then cbugerMoveTree(op, CBUGER_ROOT) end
            else
                cbugerMoveTree(op, CBUGER_ROOT)
            end
        end
    end
end
cbugerEnsureDir(CBUGER_ROOT)
cbugerEnsureDir(CBUGER_CONFIG)
cbugerEnsureDir(CBUGER_ROOT .. 'icons_image\\')
cbugerEnsureDir(CBUGER_ROOT .. 'HitMarker\\')
local function cbugerMoveConfigFile(old_name, new_name)
    local old_path = CBUGER_CONFIG .. old_name
    local new_path = CBUGER_CONFIG .. new_name
    if lfs.attributes(new_path, 'mode') == 'file' then return true end
    if lfs.attributes(old_path, 'mode') ~= 'file' then return false end
    if os.rename(old_path, new_path) then return true end
    local fi = io.open(old_path, 'rb')
    if not fi then return false end
    local data = fi:read('*a') or ''
    fi:close()
    if not CBUGER_SAFE_WRITE_FILE(new_path, data) then return false end
    os.remove(old_path)
    return true
end

do
    local legacy = CBUGER_CONFIG .. 'Cbuger.ini'
    local f = io.open(legacy, 'rb')
    if f then
        local txt = f:read('*a') or ''; f:close()
        if not txt:find('%[config%]') and not txt:find('^%s*%[') then
            if lfs.attributes(CBUGER_CONFIG .. 'Wheel.ini', 'mode') ~= 'file' then
                if not cbugerMoveConfigFile('Cbuger.ini', 'Wheel.ini') then
                    if CBUGER_SAFE_WRITE_FILE(CBUGER_CONFIG .. 'Wheel.ini', txt) then os.remove(legacy) end
                end
            end
        end
    end
end

for _, pair in ipairs({
    {'Cbuger_cbug_speed.ini', 'cbug_speed.ini'},
    {'Cbuger_HitZones.ini', 'HitZones.ini'},
    {'Cbuger_HitZones_cbug.ini', 'HitZones_cbug.ini'},
    {'Cbuger_SmartCrosshair.ini', 'SmartCrosshair.ini'},
    {'Cbuger_SmartCrosshair_modes.lua', 'SmartCrosshair_modes.lua'},
    {'Cbuger_Wheel.ini', 'Wheel.ini'},
    {'cbuger_combos.json', 'combos.json'},
    {'cbuger_shotmap.json', 'shotmap.json'},
    {'cbuger_guide_settings.txt', 'guide_settings.txt'},
}) do
    cbugerMoveConfigFile(pair[1], pair[2])
end
do
    local old_dir = getWorkingDirectory() .. '\\config\\'
    local names = {}
    pcall(function()
        for n in lfs.dir(old_dir) do
            local ln = n:lower()
            if ln:find('^cbuger') or ln == 'pricel.ini' then names[#names + 1] = n end
        end
    end)
    for _, n in ipairs(names) do
        local sp, dp = old_dir .. n, CBUGER_CONFIG .. n
        if lfs.attributes(sp, 'mode') == 'file' and not lfs.attributes(dp, 'mode') then
            local fi = io.open(sp, 'rb')
            if fi then
                local d = fi:read('*a'); fi:close()
                if type(d) == 'string' and CBUGER_SAFE_WRITE_FILE(dp, d) then
                    if n:lower() ~= 'pricel.ini' then os.remove(sp) end
                end
            end
        end
    end
end
CB = {}
do
local Lib, Fn, Data = {}, {}, {}
Lib.inicfg   = inicfg
Lib.mimgui   = imgui
Lib.encoding = encoding
Lib.sampev   = sampev
Lib.ffi      = ffi
fa = fa or CBUGER_CORE.libs.fa
Lib.encoding.default = 'CP1251'
u8 = Lib.encoding.UTF8
Lib.new, Lib.str = Lib.mimgui.new, Lib.mimgui.str
Lib.sizeof = Lib.ffi.sizeof
Lib.imgui = Lib.mimgui
local sampev = Lib.sampev
local function safe_icon(candidates, fallback)
    if type(candidates) == 'string' then candidates = {candidates} end
    for _, name in ipairs(candidates) do
        local ok, v = pcall(function() return fa[name] end)
        if ok and type(v) == 'string' and v ~= '' then return v end
    end
    return fallback or ''
end
if not Lib.imgui.PushID then
    if Lib.imgui.PushIDStr then Lib.imgui.PushID = Lib.imgui.PushIDStr
    elseif Lib.imgui.PushIDInt then Lib.imgui.PushID = Lib.imgui.PushIDInt
    else Lib.imgui.PushID = function(...) end end
end
if not Lib.imgui.PopID then
    if Lib.imgui.PopIDStr then Lib.imgui.PopID = Lib.imgui.PopIDStr
    else Lib.imgui.PopID = function(...) end end
end
if not Lib.imgui.SelectableBool then
    if Lib.imgui.Selectable then
       Lib.imgui.SelectableBool = function(label, selected, flags, size)
            local ok, a, b = pcall(Lib.imgui.Selectable, label, selected, flags, size)
            if ok then return a or false end
            local ok2, c = pcall(Lib.imgui.Selectable, label)
            if ok2 then return c or false end
            return false
        end
    else Lib.imgui.SelectableBool = function(...) return false end end
end
if not Lib.imgui.ImVec2 then
    if Lib.imgui.ImVec2_ then Lib.imgui.ImVec2 = Lib.imgui.ImVec2_
    else Lib.imgui.ImVec2 = function(x,y) return {x=x or 0, y=y or 0} end end
end
if not Lib.imgui.ImVec4 then
   Lib.imgui.ImVec4 = function(x,y,z,w) return {x=x or 0, y=y or 0, z=z or 0, w=w or 0} end
end
Data.CBUGER_DIR = CBUGER_ROOT
Data.CBUGER_CONFIG_DIR = CBUGER_CONFIG
Data.CBUGER_FONTS_DIR = CBUGER_ROOT .. 'fonts\\'
cbugerEnsureDir(Data.CBUGER_FONTS_DIR)
local function migrate_file(old_path, new_path)
    if doesFileExist(new_path) then return end
    if doesFileExist(old_path) then
        pcall(function() os.rename(old_path, new_path) end)
    end
end
migrate_file(Data.CBUGER_CONFIG_DIR .. 'keyboard.ini', Data.CBUGER_CONFIG_DIR .. 'cbuger.ini')
migrate_file(Data.CBUGER_CONFIG_DIR .. 'keyboard_combos.json', Data.CBUGER_CONFIG_DIR .. 'cbuger_combos.json')
migrate_file(Data.CBUGER_CONFIG_DIR .. 'guide_editor_settings.txt', Data.CBUGER_CONFIG_DIR .. 'cbuger_guide_settings.txt')
do
    local old_config_dir = getWorkingDirectory() .. '\\config\\'
    local old_fonts_dir  = getWorkingDirectory() .. '\\fonts\\'
    for _, fname in ipairs({'cbuger.ini', 'cbuger_combos.json', 'cbuger_shotmap.json', 'cbuger_guide_settings.txt'}) do
        migrate_file(old_config_dir .. fname, Data.CBUGER_CONFIG_DIR .. fname)
    end
    pcall(function()
        for f in lfs.dir(old_fonts_dir) do
            if f ~= '.' and f ~= '..' then
                local ext = f:match('%.([^.]+)$')
                if ext and (ext:lower() == 'ttf' or ext:lower() == 'otf') then
                    migrate_file(old_fonts_dir .. f, Data.CBUGER_FONTS_DIR .. f)
                end
            end
        end
    end)
end
Data.neon_loaded_fonts      = {}
Data.neon_loaded_font_names = { u8"Системный" }
Data.neon_loaded_font_files = {}
Data.CHILD_BG_KEY = Lib.imgui.Col.ChildBg or 10
Lib.imgui.OnInitialize(function()
    local fonts_dir = Data.CBUGER_FONTS_DIR
    local windows_fonts_dir = (os.getenv("WINDIR") or "C:\\Windows") .. "\\Fonts\\"
    local font_files = {
        { name = u8"Arial",          file = "arial.ttf"    },
        { name = u8"Arial Bold",     file = "arialbd.ttf"  },
        { name = u8"Arial Italic",   file = "ariali.ttf"   },
        { name = u8"Tahoma",         file = "tahoma.ttf"   },
        { name = u8"Tahoma Bold",    file = "tahomabd.ttf" },
        { name = u8"Verdana",        file = "verdana.ttf"  },
        { name = u8"Verdana Bold",   file = "verdanab.ttf" },
        { name = u8"Segoe UI",       file = "segoeui.ttf"  },
        { name = u8"Segoe UI Bold",  file = "segoeuib.ttf" },
        { name = u8"Segoe UI Light", file = "segoeuil.ttf" },
        { name = u8"Calibri",        file = "calibri.ttf"  },
        { name = u8"Calibri Bold",   file = "calibrib.ttf" },
        { name = u8"Times New Roman",file = "times.ttf"    },
        { name = u8"Courier New",    file = "cour.ttf"     },
        { name = u8"Comic Sans MS",  file = "comic.ttf"    },
        { name = u8"Georgia",        file = "georgia.ttf"  },
        { name = u8"Trebuchet MS",   file = "trebuc.ttf"   },
        { name = u8"Impact",         file = "impact.ttf"   },
        { name = u8"Consolas",       file = "consola.ttf"  },
        { name = u8"Candara",        file = "Candara.ttf"  },
        { name = u8"Franklin Gothic",file = "framd.ttf"    },
        { name = u8"Palatino",       file = "pala.ttf"     },
    }
    local io_ptr = Lib.imgui.GetIO()

    if io_ptr then
        local config_flags = Lib.imgui.ConfigFlags
        local no_mouse_cursor_change = config_flags and config_flags.NoMouseCursorChange
        if no_mouse_cursor_change ~= nil then
            local bitlib = rawget(_G, 'bit')
            if not (bitlib and type(bitlib.bor) == 'function') then
                local ok_bit, loaded_bit = pcall(require, 'bit')
                if ok_bit then bitlib = loaded_bit end
            end

            local current_flags = tonumber(io_ptr.ConfigFlags) or 0
            if bitlib and type(bitlib.bor) == 'function' then
                local ok_flags, combined = pcall(bitlib.bor, current_flags, no_mouse_cursor_change)
                if ok_flags then
                    io_ptr.ConfigFlags = combined
                end
            else

                local flag = tonumber(no_mouse_cursor_change)
                if flag and flag > 0 and math.floor(current_flags / flag) % 2 == 0 then
                    io_ptr.ConfigFlags = current_flags + flag
                end
            end
        end
    end

    if not (io_ptr and io_ptr.Fonts) then return end
    local glyph_ranges = Lib.ffi.new("unsigned short[9]",
        0x0020, 0x00FF, 0x0400, 0x04FF, 0x2000, 0x206F, 0x2DE0, 0x2DFF, 0x0000)
    local function merge_fa(size)
        if fa and fa.Init then pcall(fa.Init, size or 16.0) end
    end
    local function add_font(path, display_name)
        local font_id = tostring(display_name or ""):lower():gsub("[%s_%-]", "")
        if font_id == "nextwaveoutital" then return end
        local f = io.open(path, "rb")
        if not f then return end
        f:close()
        local ok, font = pcall(function()
            return io_ptr.Fonts:AddFontFromFileTTF(path, 16.0, nil, glyph_ranges)
        end)
        if ok and font and font ~= nil then
            merge_fa(16.0)
            table.insert(Data.neon_loaded_fonts, font)
            table.insert(Data.neon_loaded_font_names, display_name)
            table.insert(Data.neon_loaded_font_files, path)
        end
    end
    merge_fa(16.0)
    for _, fd in ipairs(font_files) do
        add_font(windows_fonts_dir .. fd.file, fd.name)
    end
    local p = true
    if p then
        local files = {}
        pcall(function()
            for name in lfs.dir((fonts_dir:gsub('[\\/]+$', ''))) do
                if name ~= '.' and name ~= '..' then table.insert(files, name) end
            end
        end)
        table.sort(files, function(a, b) return a:lower() < b:lower() end)
        for _, name in ipairs(files) do
            local ext = name:match('%.([^.]+)$')
            if ext then
                ext = ext:lower()
                if ext == 'ttf' or ext == 'otf' then
                    local base = name:gsub('%.[^.]+$', '')
                    local display_name = base
                    local ok_name, converted = pcall(function() return u8(base) end)
                    if ok_name and converted then display_name = converted end
                    add_font(fonts_dir .. name, display_name)
                end
            end
        end
    end
end)
local neon = {
    target_main   = Lib.new.bool(false),
    target_editor = Lib.new.bool(false),
    main_alpha    = 0.0,
    editor_alpha  = 0.0,
    _main_fade    = 0.0,
    _editor_fade  = 0.0,
    current_tab   = 1,
    anim_tab_pos  = 1.0,
    slider_pos    = 1.0,
    global_alpha  = 1.0,
    _global_fade  = 1.0,
    is_any_slider_active    = false,
    is_discord_layout       = false,
    is_dragging             = false,
    drag_offset             = { x = 0, y = 0 },
    is_resizing             = false,
    window_size             = { w = 480, h = 520 },
    resize_start_size       = { w = 0, h = 0 },
    resize_start_mouse      = { x = 0, y = 0 },
    content_max_w           = 480,
    current_frame_max_w     = 480,
    editor_is_dragging      = false,
    editor_drag_offset      = { x = 0, y = 0 },
    editor_is_resizing      = false,
    editor_window_size      = { w = 450, h = 550 },
    editor_resize_start_size  = { w = 0, h = 0 },
    editor_resize_start_mouse = { x = 0, y = 0 },
    editor_content_max_w    = 450,
    editor_current_frame_max_w = 450,
    editor_tab              = 1,
    sc                      = nil,
    combo_rows_h            = 0,
    last_mouse_pos          = { x = 0, y = 0 },
    particle_tick           = 0,
    title_anim_state        = 0.0,
    settings_icon_anim      = 0.0,
    settings_time           = 0.0,
    footer_anim_state       = 0.0,
    footer_timer            = 0.0,
    is_collapsed            = false,
    eye_anim_state          = 0.0,
    is_first_frame          = true,
    current_rendering_window = "main",
    current_font_idx        = Lib.new.int(0),
    target_combo_editor     = Lib.new.bool(false),
    combo_editor_alpha      = 0.0,
    combo_editor_is_dragging  = false,
    combo_editor_drag_offset  = { x = 0, y = 0 },
    combo_editor_window_size  = { w = 680, h = 560 },
}
Data.neon_lists = {
    cursor_fx = {
        u8"Обычный", u8"Крестики", u8"Всплывающие кольца", u8"Капли", u8"Замедленный след",
        u8"Огонь", u8"Кольца", u8"Линии", u8"Туманность", u8"Горизонтальные штрихи",
        u8"Тёмная дыра", u8"Случайный", u8"Падающие штрихи", u8"Диагональ", u8"Взрыв",
        u8"Спираль", u8"Крупные кольца", u8"Зигзаг", u8"Конфетти", u8"Шестиугольники"
    },
    waves_modes = {
        u8"Волны", u8"Эквалайзер", u8"Расходящиеся круги", u8"Цифровой шум",
        u8"Кардиограмма", u8"Двойная спираль", u8"Радар", u8"Соты", u8"Пузыри",
        u8"Тройные волны", u8"Спираль", u8"Маятник", u8"Лабиринт", u8"Звёздный поток",
        u8"Пульсирующие круги", u8"Шестиугольники на волне", u8"Спектр", u8"Фигуры Лиссажу", u8"Деформация поля"
    },
    ambient_modes = {
        u8"Полиция мигает", u8"Мигающие вспышки", u8"Вертикальный скан",
        u8"Пульс", u8"Стробоскоп", u8"Световые полосы", u8"Расходящийся круг",
        u8"Прожектор", u8"Острый импульс", u8"Молния", u8"Световой мерцатель",
        u8"Горизонтальный скан", u8"Хроматик", u8"Кольцо", u8"Морзе", u8"Градиент"
    },
    tabs = { fa.KEYBOARD.." "..u8"Основные", fa.PALETTE.." "..u8"Стиль", fa.LIST_UL.." "..u8"Комбо" },
    tab_icons  = { fa.KEYBOARD, fa.PALETTE, fa.LIST_UL, (fa.GUN or fa.CROSSHAIRS or fa.GEAR) },
    tab_labels = { u8"Основные", u8"Стиль", u8"Комбо", u8"Тренировка" },
    imgui_colors = {
        {id = Lib.imgui.Col.WindowBg,            name = "Фон основного окна",          cat = 1},
        {id = Data.CHILD_BG_KEY,                   name = "Фон дочернего виджета",         cat = 1},
        {id = Lib.imgui.Col.FrameBg,             name = "Фон слайдера/чекбокса",        cat = 2},
        {id = Lib.imgui.Col.FrameBgHovered,      name = "Наведение слайдера",     cat = 2},
        {id = Lib.imgui.Col.FrameBgActive,       name = "Активный слайдер",        cat = 2},
        {id = Lib.imgui.Col.Button,              name = "Кнопка",                         cat = 2},
        {id = Lib.imgui.Col.ButtonHovered,       name = "Кнопка наведение",        cat = 2},
        {id = Lib.imgui.Col.ButtonActive,        name = "Кнопка нажатие",           cat = 2},
        {id = Lib.imgui.Col.CheckMark,           name = "Галочка",                     cat = 2},
        {id = Lib.imgui.Col.Header,              name = "Заголовок",                      cat = 3},
        {id = Lib.imgui.Col.HeaderHovered,       name = "Заголовок наведение",     cat = 3},
        {id = Lib.imgui.Col.HeaderActive,        name = "Заголовок нажатие",        cat = 3},
        {id = Lib.imgui.Col.ScrollbarBg,         name = "Фон скролла",               cat = 4},
        {id = Lib.imgui.Col.ScrollbarGrab,       name = "Ползунок скролла",                 cat = 4},
        {id = Lib.imgui.Col.ScrollbarGrabHovered,name = "Ползунок наведение",        cat = 4},
        {id = Lib.imgui.Col.ScrollbarGrabActive, name = "Ползунок нажатие",           cat = 4},
        {id = Lib.imgui.Col.Text,                name = "Основной текст",                   cat = 5},
        {id = Lib.imgui.Col.TextDisabled,        name = "Заголовки секций",         cat = 5},
        {id = Lib.imgui.Col.Border,              name = "Граница",                        cat = 5},
        {id = Lib.imgui.Col.Separator,           name = "Разделитель",                 cat = 5},
    }
}
Data.neon_ui_anim          = { last_time = os.clock(), dt = 0 }
Data.samp_chat_is_open     = false
Fn = Fn or {}
do
    local ffi = Lib.ffi
    pcall(function()
        ffi.cdef[[
            typedef void* HWND;
            typedef void* HINSTANCE;
            HINSTANCE ShellExecuteA(HWND hwnd, const char* lpOperation,
                                     const char* lpFile, const char* lpParameters,
                                     const char* lpDirectory, int nShowCmd);
        ]]
    end)
    local ok_shell32, shell32 = pcall(ffi.load, 'shell32.dll')
    Data.shell32 = ok_shell32 and shell32 or nil
end
Fn.open_external_url = function(url)
    if type(url) ~= "string" or url == "" then return false end
    local ffi = Lib.ffi
    local shell32 = Data.shell32
    if shell32 then
        local ok, result = pcall(function()
            return shell32.ShellExecuteA(nil, "open", url, nil, nil, 1)
        end)
        if ok and result ~= nil then
            local ok_cast, code = pcall(function()
                return tonumber(ffi.cast("intptr_t", result))
            end)
            if ok_cast and code and code > 32 then
                return true
            end
        end
    end
    local safe_url = url:gsub('"', '')
    local ok_fallback = pcall(function()
        os.execute('explorer "' .. safe_url .. '"')
    end)
    return ok_fallback
end
Fn.link_hitbox = function(id, size, url)
    Lib.imgui.InvisibleButton(id, size)
    local hovered = Lib.imgui.IsItemHovered()
    local clicked = Lib.imgui.IsItemClicked(0)
    if hovered then
        Data.nfn.set_hand_cursor()
    end
    if clicked then
        return Fn.open_external_url(url)
    end
    return false
end
Data.neon_button_anims     = {}
Data.neon_slider_anims     = {}
Data.neon_color_pickers    = {}
Data.neon_active_colors    = {}
Data.neon_trail_particles  = {}
local neon_fx = {
    global_base_color   = {0.0, 0.8, 1.0, 0.95},
    neon_border_color   = {0.0, 0.8, 1.0, 0.66},
    button_border_color = {0.0, 0.32, 0.4, 0.6},
    tab_buttons_text_color = {1.0, 1.0, 1.0, 1.0},
    tab_icon_color      = {1.0, 1.0, 1.0, 1.0},
    title_color         = {0.0, 0.8, 1.0, 1.0},
    title_button_color  = {0.0, 0.8, 1.0, 1.0},
    ambient_on          = Lib.new.bool(false),
    ambient_var         = Lib.new.int(0),
    ambient_speed       = Lib.new.float(1.0),
    ambient_color_1     = {0.0, 0.0, 1.0, 1.0},
    ambient_color_2     = {1.0, 0.0, 0.0, 1.0},
    tabs_color          = {0.0, 0.8, 1.0, 1.0},
    waves_on            = Lib.new.bool(false),
    waves_speed         = Lib.new.float(1.0),
    waves_var           = Lib.new.int(0),
    waves_color         = {0.0, 0.8, 1.0, 1.0},
    sparks_on           = Lib.new.bool(false),
    sparks_speed        = Lib.new.float(1.0),
    sparks_size         = Lib.new.float(1.0),
    cursor_fx_var       = Lib.new.int(0),
    sparks_color        = {0.0, 0.8, 1.0, 1.0},
    icon_cross_color    = {1.0, 0.2, 0.2, 1.0},
    icon_eye_color      = {0.0, 0.8, 1.0, 1.0},
    icon_gear_color     = {0.0, 0.8, 1.0, 1.0},
    icon_resize_color   = {0.7, 0.0, 1.0, 0.67},
    section_icon_color  = {0.0, 0.8, 1.0, 1.0},
    selection_color     = {0.0, 0.8, 1.0, 1.0},
    pryanix_color       = {0.0, 0.8, 1.0, 1.0},
    title_main_color    = {0.0, 0.8, 1.0, 1.0},
    recoil_flash_color  = {1.0, 0.1, 0.1, 1.0},
}
Data.neon_smooth_close = Lib.new.bool(false)
Data.nfn = {}
Data.nfn.PushButtonBorder = function()
    local c = neon_fx.button_border_color
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(c[1], c[2], c[3], c[4] or 1.0))
end
Data.nfn.PopButtonBorder = function()
    Lib.imgui.PopStyleColor()
end
Data.nfn.record_width = function(w)
    if neon.current_rendering_window == "main" then
        local padding = neon.is_discord_layout and 200 or 100
        neon.current_frame_max_w = math.max(neon.current_frame_max_w, w + padding)
    elseif neon.current_rendering_window == "editor" then
        neon.editor_current_frame_max_w = math.max(neon.editor_current_frame_max_w, w + 100)
    end
end
Data.nfn.set_hand_cursor = function()
    local cursor_id = (Lib.imgui.MouseCursor and Lib.imgui.MouseCursor.Hand) or 7
    pcall(function() Lib.imgui.SetMouseCursor(cursor_id) end)
end
Data.nfn.set_resize_cursor = function()
    local cursor_id = (Lib.imgui.MouseCursor and Lib.imgui.MouseCursor.ResizeNWSE) or 6
    pcall(function() Lib.imgui.SetMouseCursor(cursor_id) end)
end
Data.nfn.lerp = function(a, b, t) return a + (b - a) * t end
Data.nfn.pack_color = function(r, g, b, a, ignore_fade, mult)
    local alpha_mult = (ignore_fade and 1.0 or neon.global_alpha) * (mult or 1.0)
    local final_a = (a or 1.0) * alpha_mult
    local R = math.floor(math.max(0, math.min(1, r)) * 255)
    local G = math.floor(math.max(0, math.min(1, g)) * 255)
    local B = math.floor(math.max(0, math.min(1, b)) * 255)
    local A = math.floor(math.max(0, math.min(1, final_a)) * 255)
    return A * 16777216 + B * 65536 + G * 256 + R
end
Data.nfn.SetStyleColorSafe = function(id, r, g, b, a)
    if id ~= nil then Data.neon_active_colors[id] = {r, g, b, a} end
end
Data.nfn.anim_update = function(current, target, speed)
    return target
end
do
    local S = {
        WHEEL_STEP = 45,
        SPEED      = 14,
        PAD_BOTTOM = 20,
        ZONE_W     = 14,
        MIN_THUMB  = 28,
        EPS        = 0.35,
    }
    local clamp = CoreUtil.clamp
    local function mix(a, b, t) return a + (b - a) * t end
    function S.new()
        return {
            pages    = {},
            view_h   = 0,
            dragging = false,
            grab_off = 0,
            vis_a    = 0,
            hover_a  = 0,
            drag_a   = 0,
        }
    end
    local function page(sc, idx)
        local p = sc.pages[idx]
        if not p then
            p = { pos = 0, target = 0, content = 0 }
            sc.pages[idx] = p
        end
        return p
    end
    function S.max(sc, idx)
        local m = page(sc, idx).content - sc.view_h
        if m < 1 then return 0 end
        return math.floor(m + 0.5)
    end
    function S.set_content(sc, idx, content)
        page(sc, idx).content = content
    end
    function S.page_height(sc, idx)
        return math.max(sc.view_h, page(sc, idx).content + 4)
    end
    function S.offset(sc, idx)
        local p = page(sc, idx)
        return math.floor(clamp(p.pos, 0, S.max(sc, idx)) + 0.5)
    end
    function S.on_tab_click(sc, idx, current)
        local p = page(sc, idx)
        p.target = 0
        if idx ~= current then p.pos = 0 end
    end
    function S.wheel_allowed(p_min, p_max, mp)
        local im = Lib.imgui
        local hf = im.HoveredFlags
        if hf and hf.ChildWindows then
            local ok, res = pcall(im.IsWindowHovered, hf.ChildWindows)
            if ok then return res and true or false end
        end
        return mp.x >= p_min.x and mp.x <= p_max.x and mp.y >= p_min.y and mp.y <= p_max.y
    end
    function S.begin_frame(sc, idx, view_h, io, wheel_ok)
        sc.view_h = view_h
        local p   = page(sc, idx)
        local max = S.max(sc, idx)
        if wheel_ok and not sc.dragging and io.MouseWheel ~= 0 then
            p.target = p.target - io.MouseWheel * S.WHEEL_STEP
        end
        p.target = clamp(p.target, 0, max)
        if sc.dragging then
            p.pos = p.target
        else
            p.pos = Data.nfn.anim_update(p.pos, p.target, S.SPEED)
            if math.abs(p.pos - p.target) < S.EPS then p.pos = p.target end
        end
        p.pos = clamp(p.pos, 0, max)
    end
    function S.draw_bar(sc, idx, dl, cx, top, h, io, alpha)
        local im  = Lib.imgui
        local p   = page(sc, idx)
        local max = S.max(sc, idx)
        local can = max > 0 and h > 8
        p.target = clamp(p.target, 0, max)
        p.pos    = clamp(p.pos, 0, max)
        local thumb_h = h
        if can then thumb_h = clamp(h * h / (h + max), math.min(S.MIN_THUMB, h), h) end
        local track   = math.max(1, h - thumb_h)
        local thumb_y = top + ((can and max > 0) and (p.pos / max) * track or 0)
        local hovered, active = false, false
        if can then
            im.SetCursorScreenPos(im.ImVec2(cx - S.ZONE_W * 0.5, top))
            im.InvisibleButton("##nscrollzone", im.ImVec2(S.ZONE_W, h))
            hovered = im.IsItemHovered()
            active  = im.IsItemActive()
        end
        if active then
            local my = io.MousePos.y
            if not sc.dragging then
                sc.dragging = true
                if my >= thumb_y and my <= thumb_y + thumb_h then
                    sc.grab_off = my - thumb_y
                else
                    sc.grab_off = thumb_h * 0.5
                end
            end
            local t  = clamp((my - top - sc.grab_off) / track, 0, 1)
            p.target = t * max
            p.pos    = p.target
            thumb_y  = top + t * track
        else
            sc.dragging = false
        end
        if hovered or active then Data.nfn.set_hand_cursor() end
        local anim = Data.nfn.anim_update
        sc.vis_a   = anim(sc.vis_a,   can and 1 or 0, 10)
        sc.hover_a = anim(sc.hover_a, (hovered or sc.dragging) and 1 or 0, 16)
        sc.drag_a  = anim(sc.drag_a,  sc.dragging and 1 or 0, 20)
        if sc.vis_a < 0.01 then return end
        local C  = Data.neon_active_colors
        local bg = C[im.Col.ScrollbarBg]          or {0, 0, 0, 0.3}
        local gr = C[im.Col.ScrollbarGrab]        or {0.5, 0.5, 0.5, 0.7}
        local gh = C[im.Col.ScrollbarGrabHovered] or gr
        local ga = C[im.Col.ScrollbarGrabActive]  or gh
        local function col(i)
            return mix(mix(gr[i] or 1, gh[i] or 1, sc.hover_a), ga[i] or 1, sc.drag_a)
        end
        local mult = alpha * sc.vis_a
        local tw   = 2 + sc.hover_a * 2
        local gw   = 4 + sc.hover_a * 2
        dl:AddRectFilled(im.ImVec2(cx - tw * 0.5, top), im.ImVec2(cx + tw * 0.5, top + h),
            Data.nfn.pack_color(bg[1], bg[2], bg[3], bg[4] or 0.3, false, mult), tw * 0.5)
        dl:AddRectFilled(im.ImVec2(cx - gw * 0.5, thumb_y), im.ImVec2(cx + gw * 0.5, thumb_y + thumb_h),
            Data.nfn.pack_color(col(1), col(2), col(3), col(4), false, mult), gw * 0.5)
    end
    Data.nfn.scroll = S
    neon.sc = S.new()
end
Data.nfn.bezier = function(t, p0, p1, p2, p3)
    local u = 1 - t; local tt = t*t; local uu = u*u; local uuu = uu*u; local ttt = tt*t
    local p = {x = uuu*p0.x, y = uuu*p0.y}
    p.x = p.x + 3*uu*t*p1.x; p.y = p.y + 3*uu*t*p1.y
    p.x = p.x + 3*u*tt*p2.x; p.y = p.y + 3*u*tt*p2.y
    p.x = p.x + ttt*p3.x;    p.y = p.y + ttt*p3.y
    return Lib.imgui.ImVec2(p.x, p.y)
end
Data.nfn.draw_safe_bezier = function(dl, p0, p1, p2, p3, col, thickness)
    local prev = p0
    for i = 1, 15 do
        local curr = Data.nfn.bezier(i/15, p0, p1, p2, p3)
        dl:AddLine(prev, curr, col, thickness)
        prev = curr
    end
end
Data.nfn.SafeCombo = function(label, int_ptr, items)
    if items and #items > 0 then
        local items_arr = Lib.ffi.new("const char*[?]", #items, items)
        Data.nfn.PushButtonBorder()
       Lib.imgui.Combo(label, int_ptr, items_arr, #items)
        Data.nfn.PopButtonBorder()
       Data.nfn.record_width(Lib.imgui.CalcTextSize(label).x + 150)
    end
end
Data.nfn.SyncAccentColorsFromBase = function(r, g, b)
    local function setc(c, rr, gg, bb)
        c[1], c[2], c[3] = CoreUtil.clamp(rr, 0, 1), CoreUtil.clamp(gg, 0, 1), CoreUtil.clamp(bb, 0, 1)
    end
    setc(neon_fx.neon_border_color,  r * 0.95, g * 0.95, b * 0.95)
    setc(neon_fx.button_border_color, r * 0.45, g * 0.45, b * 0.45)
    setc(neon_fx.icon_cross_color,   r, g, b)
    setc(neon_fx.icon_eye_color,     r, g, b)
    setc(neon_fx.icon_gear_color,    r, g, b)
    setc(neon_fx.icon_resize_color,  r * 0.25, g * 0.25, b * 0.25)
    setc(neon_fx.section_icon_color, r * 0.85, g * 0.85, b * 0.85)
    setc(neon_fx.tab_icon_color,     r * 1.10, g * 1.10, b * 1.10)
end
Data.nfn.ApplyGlobalTheme = function(r, g, b)
   Data.neon_color_pickers = {}
    local base_a = neon_fx.global_base_color[4] or 0.95
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.WindowBg,           r*0.1,  g*0.1,  b*0.1,  base_a)
   Data.nfn.SetStyleColorSafe(Data.CHILD_BG_KEY,                 r*0.05, g*0.05, b*0.05, 0.4)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.FrameBg,            r*0.15, g*0.15, b*0.15, 0.9)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.FrameBgHovered,     r*0.25, g*0.25, b*0.25, 0.9)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.FrameBgActive,      r*0.5,  g*0.5,  b*0.5,  1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.Button,             r*0.2,  g*0.2,  b*0.2,  0.9)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ButtonHovered,      r*0.4,  g*0.4,  b*0.4,  1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ButtonActive,       r*0.6,  g*0.6,  b*0.6,  1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.Header,             r*0.25, g*0.25, b*0.25, 0.8)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.HeaderHovered,      r*0.4,  g*0.4,  b*0.4,  0.9)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.HeaderActive,       r*0.6,  g*0.6,  b*0.6,  1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.CheckMark,          r,      g,      b,      1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.Border,             r*0.4,  g*0.4,  b*0.4,  0.6)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.Separator,          r*0.3,  g*0.3,  b*0.3,  0.8)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.SeparatorHovered,   r*0.5,  g*0.5,  b*0.5,  1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.SeparatorActive,    r,      g,      b,      1.0)
    if Lib.imgui.Col.SliderGrab then
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.SliderGrab,     r*0.7,  g*0.7,  b*0.7,  1.0)
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.SliderGrabActive, r,    g,      b,      1.0)
    end
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ScrollbarBg,        r*0.05, g*0.05, b*0.05, 0.3)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ScrollbarGrab,      r*0.5,  g*0.5,  b*0.5,  0.7)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ScrollbarGrabHovered, r*0.7, g*0.7, b*0.7,  0.9)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ScrollbarGrabActive,  r,     g,     b,      1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.Text,               1.0,    1.0,    1.0,    1.0)
   Data.nfn.SetStyleColorSafe(Lib.imgui.Col.TextDisabled,       r*0.5,  g*0.5,  b*0.5,  1.0)
    if Lib.imgui.Col.TitleBg then
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.TitleBg,        r*0.1,  g*0.1,  b*0.1,  1.0)
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.TitleBgActive,  r*0.2,  g*0.2,  b*0.2,  1.0)
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.TitleBgCollapsed, r*0.05, g*0.05, b*0.05, 0.8)
    end
    if Lib.imgui.Col.PopupBg then
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.PopupBg,        r*0.08, g*0.08, b*0.1,  0.98)
    end
    if Lib.imgui.Col.Tab then
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.Tab,                r*0.2,  g*0.2,  b*0.2,  0.9)
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.TabHovered,         r*0.5,  g*0.5,  b*0.5,  1.0)
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.TabActive,          r*0.35, g*0.35, b*0.35, 1.0)
    end
    if Lib.imgui.Col.NavHighlight then Data.nfn.SetStyleColorSafe(Lib.imgui.Col.NavHighlight, r, g, b, 0.8) end
    if Lib.imgui.Col.TextSelectedBg then Data.nfn.SetStyleColorSafe(Lib.imgui.Col.TextSelectedBg, r*0.3, g*0.3, b*0.3, 0.5) end
    if Lib.imgui.Col.DragDropTarget  then Data.nfn.SetStyleColorSafe(Lib.imgui.Col.DragDropTarget,  r, g, b, 0.9) end
    if Lib.imgui.Col.ModalWindowDimBg then Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ModalWindowDimBg, 0, 0, 0, 0.35) end
    neon_fx.sparks_color[1]     = r; neon_fx.sparks_color[2]     = g; neon_fx.sparks_color[3]     = b
    neon_fx.waves_color[1]      = r; neon_fx.waves_color[2]      = g; neon_fx.waves_color[3]      = b
    neon_fx.tabs_color[1]       = r; neon_fx.tabs_color[2]       = g; neon_fx.tabs_color[3]       = b
    neon_fx.ambient_color_1[1]  = r; neon_fx.ambient_color_1[2]  = g; neon_fx.ambient_color_1[3]  = b
    neon_fx.ambient_color_2[1]  = r*0.2; neon_fx.ambient_color_2[2] = g*0.2; neon_fx.ambient_color_2[3] = b*0.2
    neon_fx.title_color[1]      = r; neon_fx.title_color[2]      = g; neon_fx.title_color[3]      = b
    neon_fx.title_button_color[1]=r; neon_fx.title_button_color[2]=g; neon_fx.title_button_color[3]=b
    Data.nfn.SyncAccentColorsFromBase(r, g, b)
    neon_fx.selection_color[1] = r; neon_fx.selection_color[2] = g; neon_fx.selection_color[3] = b
    neon_fx.pryanix_color[1]   = r; neon_fx.pryanix_color[2]   = g; neon_fx.pryanix_color[3]   = b
    neon_fx.title_main_color[1]= r; neon_fx.title_main_color[2]= g; neon_fx.title_main_color[3]= b
    if Lib.imgui.Col.ResizeGrip then
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ResizeGrip,        r*0.5, 0,     b*0.5, 0.35)
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ResizeGripHovered, r*0.7, 0,     b*0.7, 0.6)
       Data.nfn.SetStyleColorSafe(Lib.imgui.Col.ResizeGripActive,  r*0.9, g*0.1, b,     0.9)
    end
end
Data.nfn.BeginStandardPopupStyle = function()
    local im = Lib.imgui
    im.PushStyleVarVec2(im.StyleVar.WindowPadding, im.ImVec2(18, 12))
    im.PushStyleVarVec2(im.StyleVar.ItemSpacing, im.ImVec2(8, 8))
    im.PushStyleVarVec2(im.StyleVar.FramePadding, im.ImVec2(8, 4))
    im.PushStyleVarFloat(im.StyleVar.WindowRounding, 6)
    return 4
end
Data.nfn.EndStandardPopupStyle = function(count)
    if count and count > 0 then Lib.imgui.PopStyleVar(count) end
end
Data.nfn.BeginColorPopupStyle = function()
    Lib.imgui.SetNextWindowSize(Lib.imgui.ImVec2(261, 0), Lib.imgui.Cond.Always)
end
Data.nfn.EndColorPopupStyle = function()
end
do
    local im = Lib.imgui
    if type(im) == 'table' and type(im.BeginPopup) == 'function'
        and not im.__CBUGER_STANDARD_POPUP_STYLE then
        im.__CBUGER_STANDARD_POPUP_STYLE = true
        local orig_begin_popup = im.BeginPopup
        local orig_begin_modal = im.BeginPopupModal
        local orig_end_popup = im.EndPopup
        local orig_ctx_item = im.BeginPopupContextItem
        local orig_ctx_window = im.BeginPopupContextWindow
        local orig_ctx_void = im.BeginPopupContextVoid
        local popup_style_stack = {}
        local context_depth = 0
        local popup_wrap = {}
        popup_wrap.BeginPopup = function(name, flags, ...)
            if context_depth > 0 then
                return orig_begin_popup(name, flags, ...)
            end
            local count = Data.nfn.BeginStandardPopupStyle()
            local ok, opened = pcall(orig_begin_popup, name, flags, ...)
            if not ok then
                Data.nfn.EndStandardPopupStyle(count)
                error(opened, 0)
            end
            if opened then
                popup_style_stack[#popup_style_stack + 1] = count
                return true
            end
            Data.nfn.EndStandardPopupStyle(count)
            return false
        end
        if type(orig_begin_modal) == 'function' then
            popup_wrap.BeginPopupModal = function(name, p_open, flags, ...)
                local count = Data.nfn.BeginStandardPopupStyle()
                local ok, opened = pcall(orig_begin_modal, name, p_open, flags, ...)
                if not ok then
                    Data.nfn.EndStandardPopupStyle(count)
                    error(opened, 0)
                end
                if opened then
                    popup_style_stack[#popup_style_stack + 1] = count
                    return true
                end
                Data.nfn.EndStandardPopupStyle(count)
                return false
            end
        end
        local function wrap_context(original, ...)
            local count = Data.nfn.BeginStandardPopupStyle()
            context_depth = context_depth + 1
            local ok, opened = pcall(original, ...)
            context_depth = math.max(0, context_depth - 1)
            if not ok then
                Data.nfn.EndStandardPopupStyle(count)
                error(opened, 0)
            end
            if opened then
                popup_style_stack[#popup_style_stack + 1] = count
                return true
            end
            Data.nfn.EndStandardPopupStyle(count)
            return false
        end
        if type(orig_ctx_item) == 'function' then
            popup_wrap.BeginPopupContextItem = function(...) return wrap_context(orig_ctx_item, ...) end
        end
        if type(orig_ctx_window) == 'function' then
            popup_wrap.BeginPopupContextWindow = function(...) return wrap_context(orig_ctx_window, ...) end
        end
        if type(orig_ctx_void) == 'function' then
            popup_wrap.BeginPopupContextVoid = function(...) return wrap_context(orig_ctx_void, ...) end
        end
        popup_wrap.EndPopup = function(...)
            local ok, err = pcall(orig_end_popup, ...)
            local count = table.remove(popup_style_stack)
            if count then Data.nfn.EndStandardPopupStyle(count) end
            if not ok then error(err, 0) end
        end
        for k, v in pairs(popup_wrap) do rawset(im, k, v) end
    end
end
Data.nfn.CustomColorPicker = function(label, id_string, color_ref, has_alpha, alpha_mult)
    local w, h = 24, 24
    local p  = Lib.imgui.GetCursorScreenPos()
    local dl = Lib.imgui.GetWindowDrawList()
    local center = Lib.imgui.ImVec2(p.x + w/2, p.y + h/2)
    local popup_id = "ncp_" .. id_string
   Lib.imgui.InvisibleButton("nbtn_"..id_string, Lib.imgui.ImVec2(w, h))
    local hovered = Lib.imgui.IsItemHovered()
    local clicked = Lib.imgui.IsItemClicked()
    if hovered then Data.nfn.set_hand_cursor() end
    if clicked  then Lib.imgui.OpenPopup(popup_id) end
    local u32_col = Data.nfn.pack_color(color_ref[1], color_ref[2], color_ref[3], color_ref[4] or 1.0, true, alpha_mult or 1.0)
    dl:AddCircleFilled(center, w/2 - 2, u32_col, 24)
    local bpc = neon_fx.button_border_color
    local bpu = Data.nfn.pack_color(bpc[1], bpc[2], bpc[3], hovered and (bpc[4] or 1) or (bpc[4] or 1) * 0.55, false, alpha_mult or 1.0)
    dl:AddCircle(center, w/2 - 2, bpu, 24, hovered and 1.8 or 1.5)
   Lib.imgui.SameLine(0, 10)
   Lib.imgui.SetCursorPosY(Lib.imgui.GetCursorPosY() + 2)
   Lib.imgui.Text(label)
   Data.nfn.record_width(Lib.imgui.CalcTextSize(label).x + 80)
    local changed = false
   Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.Alpha, alpha_mult or 1.0)
   Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
    Data.nfn.BeginColorPopupStyle()
    if Lib.imgui.BeginPopup(popup_id) then
        local t_col = Data.neon_active_colors[Lib.imgui.Col.Text] or {1.0, 1.0, 1.0, 1.0}
       Lib.imgui.TextColored(Lib.imgui.ImVec4(t_col[1], t_col[2], t_col[3], 1.0), label)
       Lib.imgui.Separator()
        if not Data.neon_color_pickers[id_string] then
           Data.neon_color_pickers[id_string] = Lib.new.float[4](
                color_ref[1] or 1.0, color_ref[2] or 1.0, color_ref[3] or 1.0, color_ref[4] or 1.0)
        end
        local st = Data.neon_color_pickers[id_string]
        local _ga = CBUGER_GET_INTERFACE_ALPHA()
        local _base_a = math.max(0.0, math.min(1.0, tonumber(color_ref[4]) or 1.0))
        st[0] = color_ref[1] or 1.0
        st[1] = color_ref[2] or 1.0
        st[2] = color_ref[3] or 1.0
        st[3] = _base_a * _ga
        local cp_flags = 0
        if Lib.imgui.ColorEditFlags then
            cp_flags = (Lib.imgui.ColorEditFlags.NoSidePreview or 0) + (Lib.imgui.ColorEditFlags.NoSmallPreview or 0) + (Lib.imgui.ColorEditFlags.AlphaBar or 0)
        end
        if Lib.imgui.ColorPicker4("##npicker_"..id_string, st, cp_flags) then
            color_ref[1] = st[0]; color_ref[2] = st[1]
            color_ref[3] = st[2]
            if _ga > 0.0001 then
                color_ref[4] = math.max(0.0, math.min(1.0, st[3] / _ga))
            else
                color_ref[4] = 0.0
            end
            changed = true
        end
       Lib.imgui.EndPopup()
    end
    Data.nfn.EndColorPopupStyle()
   Lib.imgui.PopStyleColor(1)
   Lib.imgui.PopStyleVar(1)
    return changed
end
Data.INF_ICON = nil
Data.nfn.label_size = function(label)
    local sz = Lib.imgui.CalcTextSize(label)
    local icon = Data.INF_ICON
    if icon and icon ~= '' then
        local i, j = label:find(icon, 1, true)
        if i then
            local pre, suf = label:sub(1, i - 1), label:sub(j + 1)
            local w = Lib.imgui.CalcTextSize(pre).x + Lib.imgui.CalcTextSize(icon).x * 0.7 + Lib.imgui.CalcTextSize(suf).x
            return { x = w, y = sz.y }
        end
    end
    return sz
end
Data.nfn.draw_label = function(dl, pos, col, label)
    local icon = Data.INF_ICON
    local i, j
    if icon and icon ~= '' then i, j = label:find(icon, 1, true) end
    if not i then dl:AddText(pos, col, label); return end
    local pre, suf = label:sub(1, i - 1), label:sub(j + 1)
    local font = Lib.imgui.GetFont()
    local fs = Lib.imgui.GetFontSize()
    local isz = fs * 0.7
    local x = pos.x
    if #pre > 0 then dl:AddText(Lib.imgui.ImVec2(x, pos.y), col, pre); x = x + Lib.imgui.CalcTextSize(pre).x end
    dl:AddTextFontPtr(font, isz, Lib.imgui.ImVec2(x, pos.y + (fs - isz) * 0.5), col, icon)
    x = x + Lib.imgui.CalcTextSize(icon).x * 0.7
    if #suf > 0 then dl:AddText(Lib.imgui.ImVec2(x, pos.y), col, suf) end
end
Data.nfn.ios_slider = function(label, val_ptr, min_v, max_v, alpha_mult, left_align, val_fmt)
    local pending_layout_dx = tonumber(Data.fixed_slider_pending_x or 0) or 0
    Data.fixed_slider_pending_x = 0
    local base_cursor_x = Lib.imgui.GetCursorPosX()
    local f_bg  = Data.neon_active_colors[Lib.imgui.Col.FrameBg]
    local f_act = Data.neon_active_colors[Lib.imgui.Col.FrameBgActive]
    if not f_bg or not f_act then Lib.imgui.SliderFloat("##"..label, val_ptr, min_v, max_v); return end
    local bg_col   = Data.nfn.pack_color(f_bg[1],f_bg[2],f_bg[3],f_bg[4],false,alpha_mult)
    local fill_col = Data.nfn.pack_color(f_act[1],f_act[2],f_act[3],f_act[4],false,alpha_mult)
    local glow_c   = {f_act[1],f_act[2],f_act[3],f_act[4]}
    local avail_w  = Lib.imgui.GetContentRegionAvail().x
    local w_orig   = avail_w*.8
    local offset_x = left_align and 0 or (avail_w-w_orig)/2
   Lib.imgui.SetCursorPosX(base_cursor_x + offset_x + pending_layout_dx)
   Lib.imgui.BeginGroup()
    local h_orig, p_orig, dl = 26, Lib.imgui.GetCursorScreenPos(), Lib.imgui.GetWindowDrawList()
   Lib.imgui.InvisibleButton("nslider_"..label, Lib.imgui.ImVec2(w_orig, h_orig))
    local active  = Lib.imgui.IsItemActive()
    local hovered = Lib.imgui.IsItemHovered()
    if active then
        neon.is_any_slider_active = true
        val_ptr[0] = math.max(min_v, math.min(max_v, (Lib.imgui.GetIO().MousePos.x-p_orig.x)/w_orig*(max_v-min_v)+min_v))
    end
    if hovered then Data.nfn.set_hand_cursor() end
   Data.neon_slider_anims[label] = Data.nfn.anim_update(Data.neon_slider_anims[label] or 1.0, 1.0, 15)
    local scale = Data.neon_slider_anims[label]
    local w, h = w_orig*scale, h_orig*scale
    local p = Lib.imgui.ImVec2(p_orig.x+(w_orig-w)/2, p_orig.y+(h_orig-h)/2)
    dl:AddRectFilled(p, Lib.imgui.ImVec2(p.x+w, p.y+h), bg_col, h/2)
    local progress = (val_ptr[0]-min_v)/(max_v-min_v)
    if progress > 0 then
        local fill_w = math.max(h, w*progress)
        dl:AddRectFilled(p, Lib.imgui.ImVec2(p.x+fill_w, p.y+h), fill_col, h/2)
        if active or hovered then Data.nfn.draw_neon_glow(dl, p, Lib.imgui.ImVec2(p.x+fill_w,p.y+h), glow_c, 5, 0.3, alpha_mult) end
    end
   Data.neon_button_anims[label] = Data.nfn.anim_update(Data.neon_button_anims[label] or 0.0, (hovered or active) and 1 or 0, 15)
    local t = Data.neon_button_anims[label]
    local _v = val_ptr[0]
    local val_text
    local _range_is_int = math.floor(min_v) == min_v and math.floor(max_v) == max_v
    local _range_over_one = (max_v - min_v) > 1
    if val_fmt then
        val_text = string.format(val_fmt, _v)
    elseif _range_is_int and _range_over_one and math.floor(_v) == _v then
        val_text = string.format("%d", math.floor(_v))
    else
        val_text = string.format("%d%%", _v * 100)
    end
    local label_size = Data.nfn.label_size(label); local val_size = Lib.imgui.CalcTextSize(val_text)
   Data.nfn.record_width(label_size.x+100)
    local txt_col = Data.neon_active_colors[Lib.imgui.Col.Text] or {1,1,1,1}
    local c = progress > 0.5 and 0.1 or txt_col[1]
    if (1-t) > 0.01 then Data.nfn.draw_label(dl, Lib.imgui.ImVec2(p.x+(w-label_size.x)/2, p.y+(h-label_size.y)/2), Data.nfn.pack_color(txt_col[1],txt_col[2],txt_col[3],1-t,true,alpha_mult), label) end
    if t > 0.01     then dl:AddText(Lib.imgui.ImVec2(p.x+(w-val_size.x)/2,   p.y+(h-val_size.y)/2),   Data.nfn.pack_color(c,c,c,t,true,alpha_mult), val_text) end
   Lib.imgui.EndGroup()
   Lib.imgui.SetCursorPosX(base_cursor_x)
end
Data.nfn.ios_toggle = function(label, bool_ptr, alpha_mult, txt_col_override)
    local dl  = Lib.imgui.GetWindowDrawList()
    local h, w = 18, 33
    local txt_col = txt_col_override or Data.neon_active_colors[Lib.imgui.Col.Text] or {1,1,1,1}
   Lib.imgui.BeginGroup()
   Lib.imgui.SetWindowFontScale(0.9)
   Lib.imgui.TextColored(Lib.imgui.ImVec4(txt_col[1] or 1, txt_col[2] or 1, txt_col[3] or 1, 0.7*neon.global_alpha*(alpha_mult or 1)), label)
   Lib.imgui.SetWindowFontScale(1.0)
   Data.nfn.record_width(Lib.imgui.CalcTextSize(label).x+100)
   local _tgx = tonumber(Data.fixed_toggle_pending_x or 0) or 0
   Data.fixed_toggle_pending_x = 0
   Lib.imgui.SameLine(Lib.imgui.GetWindowContentRegionMax().x-w-25+_tgx)
    local p, id = Lib.imgui.GetCursorScreenPos(), "ntoggle_"..label
   Lib.imgui.InvisibleButton(id, Lib.imgui.ImVec2(w, h))
    if Lib.imgui.IsItemClicked() then bool_ptr[0] = not bool_ptr[0] end
    if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
   Data.neon_button_anims[id] = Data.nfn.anim_update(Data.neon_button_anims[id] or (bool_ptr[0] and 1 or 0), bool_ptr[0] and 1 or 0, 15)
    local t = Data.neon_button_anims[id]
    local bg_off = Data.neon_active_colors[Lib.imgui.Col.FrameBg]   or {0.2,0.2,0.2,1}
    local bg_on  = Data.neon_active_colors[Lib.imgui.Col.CheckMark] or {0,0.8,1,1}
    local cur_r = Data.nfn.lerp(bg_off[1],bg_on[1],t); local cur_g = Data.nfn.lerp(bg_off[2],bg_on[2],t); local cur_b = Data.nfn.lerp(bg_off[3],bg_on[3],t)
    local glow_c = {bg_on[1],bg_on[2],bg_on[3],bg_on[4] or 1}
    dl:AddRectFilled(p, Lib.imgui.ImVec2(p.x+w,p.y+h), Data.nfn.pack_color(cur_r,cur_g,cur_b,bg_off[4] or 1,false,alpha_mult), h/2)
    if t > 0.1 then Data.nfn.draw_neon_glow(dl, p, Lib.imgui.ImVec2(p.x+w,p.y+h), glow_c, 3, t*.1, alpha_mult) end
    dl:AddCircleFilled(Lib.imgui.ImVec2(Data.nfn.lerp(p.x+h/2, p.x+w-h/2, t), p.y+h/2), h/2-2,
       Data.nfn.pack_color(0.9,0.9,0.9,1,true,alpha_mult), 24)
   Lib.imgui.EndGroup()
end
Data.nfn.draw_neon_glow = function(draw_list, p_min, p_max, color_rgb, thickness, intensity, alpha_mult)
end
Data.nfn.draw_neon_border = function(draw_list, p_min, p_max, alpha_mult)
end
Data.nfn.draw_police_ambient = function(draw_list, p_min, p_max, alpha_mult)
end
Data.nfn.draw_wave_strings = function(draw_list, p_min, p_max, color_rgb, alpha_mult)
end
Data.nfn.draw_animated_settings_icon = function(draw_list, center, radius, hover_factor, time, alpha_mult)
end
Data.nfn.draw_cross = function(dl, center, radius, hovered, alpha_mult)
    local c_c = neon_fx.icon_cross_color
    local col = Data.nfn.pack_color(c_c[1],c_c[2],c_c[3],0.85*(c_c[4] or 1),false,alpha_mult)
    local r = radius*.45
    dl:AddLine(Lib.imgui.ImVec2(center.x-r,center.y-r), Lib.imgui.ImVec2(center.x+r,center.y+r), col, 2)
    dl:AddLine(Lib.imgui.ImVec2(center.x+r,center.y-r), Lib.imgui.ImVec2(center.x-r,center.y+r), col, 2)
end
Data.nfn.draw_cross_fa = function(center, hovered, scale)
    scale = scale or 1.35
    local hf  = hovered and 1.0 or 0.0
    local c_c = neon_fx.icon_cross_color
   Lib.imgui.SetWindowFontScale(scale)
    local gs = Lib.imgui.CalcTextSize(fa.XMARK)
   Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(center.x - gs.x/2, center.y - gs.y/2))
   Lib.imgui.TextColored(Lib.imgui.ImVec4(c_c[1], c_c[2], c_c[3], (0.5+hf*.5)*(c_c[4] or 1)), fa.XMARK)
   Lib.imgui.SetWindowFontScale(1.0)
end
Data.nfn.draw_eye = function(dl, center, radius, closed_t, hovered, alpha_mult)
    local e_c = neon_fx.icon_eye_color
    local col = Data.nfn.pack_color(e_c[1],e_c[2],e_c[3],0.85*(e_c[4] or 1),false,alpha_mult)
    local p0  = Lib.imgui.ImVec2(center.x-radius, center.y)
    local p3  = Lib.imgui.ImVec2(center.x+radius, center.y)
    local ty  = radius*(1.1-closed_t*1.1)
    Data.nfn.draw_safe_bezier(dl, p0, Lib.imgui.ImVec2(center.x-radius/2,center.y-ty), Lib.imgui.ImVec2(center.x+radius/2,center.y-ty), p3, col, 2)
    Data.nfn.draw_safe_bezier(dl, p0, Lib.imgui.ImVec2(center.x-radius/2,center.y+ty), Lib.imgui.ImVec2(center.x+radius/2,center.y+ty), p3, col, 2)
    if closed_t < 0.9 then
        dl:AddCircleFilled(center, radius*.4, col, 16)
    end
end
Data.nfn.draw_dots_toggle = function(dl, center, is_vertical, hover_t, color, alpha_mult)
    local spacing = 7.5
    local static_a = (color[4] or 1) * (alpha_mult or 1)
    for i = 1, 3 do
        local off = (i - 2) * spacing
        local pos = is_vertical
            and Lib.imgui.ImVec2(center.x, center.y + off)
            or  Lib.imgui.ImVec2(center.x + off, center.y)
        dl:AddCircleFilled(pos, 2.4, Data.nfn.pack_color(color[1], color[2], color[3], static_a, true, 1.0), 16)
    end
end
Data.nfn.draw_enhanced_cursor = function(draw_list, alpha_mult, do_update)
end
 Fn.neon_FontCombo = function(label, idx_ptr)
    local names = Fn.translateList(Data.neon_loaded_font_names)
    if #names == 0 then return end
    local items_arr = Lib.ffi.new("const char*[?]", #names, names)
    if idx_ptr[0] >= #names then idx_ptr[0] = 0 end
   Lib.imgui.PushItemWidth(250)
   Lib.imgui.Combo(label, idx_ptr, items_arr, #names)
   Lib.imgui.PopItemWidth()
   Data.nfn.record_width(Lib.imgui.CalcTextSize(label).x + 150)
end
Data.neon_win_bg = {0.04, 0.04, 0.07, 0.97}
Data.neon_wave_color_tbl = {0, 0, 0, 1}
 Fn.cp = function(s)
    local ok, r = pcall(function()
        return Lib.encoding.UTF8:decode(s)
    end)
    return (ok and r) or tostring(s)
end
Data.COMBO_FILE = Data.CBUGER_CONFIG_DIR .. 'combos.json'
 Fn.save_combos_to_json = function(data_list)
    local ok, json = pcall(encodeJson, data_list or {})
    if not ok or type(json) ~= 'string' then return false end
    return CBUGER_SAFE_WRITE_FILE(Data.COMBO_FILE, json)
end
 Fn.load_combos_from_json = function()
    local decoded = CBUGER_SAFE_LOAD_JSON(Data.COMBO_FILE, function(value)
        return type(value) == 'table'
    end)
    return decoded
end
Data.SHOTMAP_FILE = Data.CBUGER_CONFIG_DIR .. 'shotmap.json'
Data.SHOTMAP_MAX_SESSIONS = 300
Data.shotmap = {
    sessions = {},
    current  = {points = {}, ref = nil, ts = os.time()},
    dirty = false, last_save = os.clock(),
}
Data.recoil_line_arm = false
 Fn.save_shotmap_to_json = function()
    if type(Data.shotmap) ~= 'table' then return false end
    local payload = {
        version = 2,
        sessions = Data.shotmap.sessions or {},
        current = Data.shotmap.current or { points = {}, ref = nil, ts = os.time() },
    }
    local ok, json = pcall(encodeJson, payload)
    if not ok or type(json) ~= 'string' then return false end
    local saved = CBUGER_SAFE_WRITE_FILE(Data.SHOTMAP_FILE, json)
    if saved then
        Data.shotmap.dirty = false
        Data.shotmap.last_save = os.clock()
    end
    return saved
end
 Fn.load_shotmap_from_json = function()
    local decoded = CBUGER_SAFE_LOAD_JSON(Data.SHOTMAP_FILE, function(value)
        return type(value.sessions) == 'table'
    end)
    if not decoded then return false end
    Data.shotmap.sessions = decoded.sessions or {}
    if type(decoded.current) == 'table' and type(decoded.current.points) == 'table' then
        Data.shotmap.current = decoded.current
        Data.shotmap.current.ref = Data.shotmap.current.ref
        Data.shotmap.current.ts = tonumber(Data.shotmap.current.ts) or os.time()
    else

        Data.shotmap.current = { points = {}, ref = nil, ts = os.time() }
    end
    Data.shotmap.dirty = false
    return true
end
 Fn.getColorU32 = function(r, g, b, a)
    local R = math.floor(math.max(0, math.min(1, r)) * 255 + 0.5)
    local G = math.floor(math.max(0, math.min(1, g)) * 255 + 0.5)
    local B = math.floor(math.max(0, math.min(1, b)) * 255 + 0.5)
    local A = math.floor(math.max(0, math.min(1, a)) * 255 + 0.5)
    return (A * 0x1000000) + (B * 0x10000) + (G * 0x100) + R
end
Fn.getColorU32Global = function(r, g, b, a)
    return CBUGER_ApplyGlobalAlphaU32(Fn.getColorU32(r, g, b, a))
end
 Fn.hsv_to_rgb = function(h, s, v)
    if s == 0 then return v, v, v end
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end
 Fn.lerp = function(a, b, t) return a + (b - a) * t end
 Fn.heatColor = function(ratio)
    ratio = math.max(0, math.min(1, ratio or 0))
    local stops = {
        {0.20, 0.85, 0.20},
        {0.95, 0.90, 0.15},
        {0.98, 0.55, 0.05},
        {0.95, 0.15, 0.10},
    }
    local seg = ratio * (#stops - 1)
    local i   = math.floor(seg)
    local f   = seg - i
    if i >= #stops - 1 then return stops[#stops][1], stops[#stops][2], stops[#stops][3] end
    local a, b = stops[i + 1], stops[i + 2]
    return Fn.lerp(a[1], b[1], f), Fn.lerp(a[2], b[2], f), Fn.lerp(a[3], b[3], f)
end
 Fn.decodeSafe = function(s)
    if not s then return "" end
    local ok, res = pcall(function() return u8 and u8.decode and u8.decode(s) or tostring(s) end)
    if ok and res then return res end
    return tostring(s)
end
Data.space_as_shift_enabled = false
 Fn.getSpaceCode = function()
    return Data.space_as_shift_enabled and 0x10 or 0x20
end
 Fn.computePulsedColor = function(base_col, enabled, speed)
    if not enabled then
        return {base_col[1], base_col[2], base_col[3], base_col[4]}
    end
    local t = os.clock() * (speed or 0.6)
    local hue = t % 1
    local hr, hg, hb = Fn.hsv_to_rgb(hue, 1, 1)
    local factor = 0.5 + 0.5 * math.sin(os.clock() * (speed or 0.6) * 2 * math.pi)
    return {
       Fn.lerp(base_col[1], hr, factor),
       Fn.lerp(base_col[2], hg, factor),
       Fn.lerp(base_col[3], hb, factor),
        base_col[4] or 1
    }
end
local S = {}
local function CBUGER_HOLD(name, hold_time)
    local duration = tonumber(hold_time) or 0.5
    if duration < 0.1 then duration = 0.1 end
    if duration > 10.0 then duration = 10.0 end
    return { name = name, hold = true, time = duration }
end
local function CBUGER_REPEAT_STAGES(prefix_stages, keys, count, suffix_stages)
    local out = {}
    for _, stage in ipairs(prefix_stages or {}) do
        out[#out + 1] = stage
    end
    for _ = 1, count do
        local stage = {}
        for _, key in ipairs(keys or {}) do
            if type(key) == 'table' then
                local copy = {}
                for k, v in pairs(key) do copy[k] = v end
                stage[#stage + 1] = copy
            else
                stage[#stage + 1] = key
            end
        end
        out[#out + 1] = stage
    end
    for _, stage in ipairs(suffix_stages or {}) do
        out[#out + 1] = stage
    end
    return out
end

S.default_combos = {
    { name = u8"+C | C-bug", guide_text = "", data = {{u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}}, keymap_alternatives = {
        {{u8"ПКМ", u8"ЛКМ", "D", "C"}}
    }},
    { name = u8"Отвод | Otvod", guide_text = "", data = {{u8"ЛКМ", u8"Ф", u8"ПКМ", "C"}}, keymap_alternatives = {
        {{u8"ЛКМ", "D", u8"ПКМ", "C"}}
    }},
    { name = u8"Полуслайд | RP Litefoot", guide_text = "", data = {
        {u8"ЛКМ", CBUGER_HOLD(u8"ПКМ", 1.5), CBUGER_HOLD(u8"Ф", 1.5)},
        {"D", "Q", "E", u8"ПРОБЕЛ"}
    }, keymap_alternatives = {
    {
        {u8"ЛКМ", CBUGER_HOLD(u8"ПКМ", 1.5), CBUGER_HOLD("D", 1.5)},
        {u8"Ф", "Q", "E", u8"ПРОБЕЛ"}
    }
    }},
    { name = u8"Перекаты | Riffles", guide_text = "", data = {{
        u8"ЛКМ", CBUGER_HOLD(u8"ПКМ", 1.5), "C", u8"ЛКМ",
        CBUGER_HOLD("D", 1.5), CBUGER_HOLD("C", 1.5)
    }}, keymap_alternatives = {
        {{u8"ЛКМ", CBUGER_HOLD(u8"ПКМ", 1.5), "C", u8"ЛКМ", CBUGER_HOLD(u8"Ф", 1.5), CBUGER_HOLD("C", 1.5)}}
    }},
    { name = u8"ДаблХит + Перекаты | DubleHit + Riffles", guide_text = "", data = {{
        u8"ЛКМ", u8"Ф", CBUGER_HOLD(u8"ПКМ", 2.0), "C", u8"ЛКМ", "C", u8"ЛКМ",
        CBUGER_HOLD("D", 1.0), CBUGER_HOLD("C", 1.0)
    }}, keymap_alternatives = {
        {{u8"ЛКМ", "D", CBUGER_HOLD(u8"ПКМ", 2.0), "C", u8"ЛКМ", "C", u8"ЛКМ", CBUGER_HOLD(u8"Ф", 1.0), CBUGER_HOLD("C", 1.0)}}
    }},
    { name = u8"Слайд | Litefoot", guide_text = "", data = {
        {u8"ЛКМ", CBUGER_HOLD("D", 1.0), u8"ПКМ", "C", CBUGER_HOLD(u8"ПРОБЕЛ", 1.0)},
        {u8"ЛКМ", CBUGER_HOLD(u8"Ф", 1.0), u8"ПКМ", "C", CBUGER_HOLD(u8"ПРОБЕЛ", 1.0)}
    }, keymap_alternatives = {
    {
        {u8"ЛКМ", CBUGER_HOLD(u8"Ф", 1.0), u8"ПКМ", "C", CBUGER_HOLD(u8"ПРОБЕЛ", 1.0)},
        {u8"ЛКМ", CBUGER_HOLD("D", 1.0), u8"ПКМ", "C", CBUGER_HOLD(u8"ПРОБЕЛ", 1.0)}
    }
    }},
    { name = u8"Рывок | Hardgun Slide", guide_text = "", data = {
        {u8"ЛКМ", "D", u8"ПКМ", "C", "Q", "E", u8"ПРОБЕЛ"},
        {u8"ЛКМ", u8"Ф", u8"ПКМ", "C", "E", "Q", u8"ПРОБЕЛ"}
    }, keymap_alternatives = {
    {
        {u8"ЛКМ", u8"Ф", u8"ПКМ", "C", "Q", "E", u8"ПРОБЕЛ"},
        {u8"ЛКМ", "D", u8"ПКМ", "C", "E", "Q", u8"ПРОБЕЛ"}
    }
    }},
    { name = u8"ДаблХит | DoubleHit", guide_text = "", data = {{
        u8"ЛКМ", u8"Ф", CBUGER_HOLD(u8"ПКМ", 1.0), "C", u8"ЛКМ"
    }}, keymap_alternatives = {
        {{u8"ЛКМ", "D", CBUGER_HOLD(u8"ПКМ", 1.0), "C", u8"ЛКМ"}}
    }},
    { name = u8"ДаблХит + Слайд | DoubleHit + Litefoot", guide_text = "", data = {
        {u8"ЛКМ", u8"Ф", CBUGER_HOLD(u8"ПКМ", 0.5), "C", u8"ЛКМ"},
        {CBUGER_HOLD("D", 1.0), "C", CBUGER_HOLD(u8"ПРОБЕЛ", 1.0)}
    }, keymap_alternatives = {
    {
        {u8"ЛКМ", "D", CBUGER_HOLD(u8"ПКМ", 0.5), "C", u8"ЛКМ"},
        {CBUGER_HOLD(u8"Ф", 1.0), "C", CBUGER_HOLD(u8"ПРОБЕЛ", 1.0)}
    }
    }},
    { name = u8"ДаблХит + Рывок | DoubleHit + Hardgun Slide", guide_text = "", data = {
        {u8"ЛКМ", u8"Ф", u8"ПКМ", "C", u8"ЛКМ"},
        {"D", "C", "Q", "E", u8"ПРОБЕЛ"}
    }, keymap_alternatives = {
    {
        {u8"ЛКМ", "D", u8"ПКМ", "C", u8"ЛКМ"},
        {u8"Ф", "C", "Q", "E", u8"ПРОБЕЛ"}
    }
    }},
    { name = u8"Фаст | Fast", guide_text = "", data = CBUGER_REPEAT_STAGES({}, {u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}, 6, {}), keymap_alternatives = {
        CBUGER_REPEAT_STAGES({}, {u8"ПКМ", u8"ЛКМ", "D", "C"}, 6, {})
    }},
    { name = u8"Отвод + Фаст | Otvod + Fast", guide_text = "", data = CBUGER_REPEAT_STAGES({{u8"ЛКМ", u8"Ф", u8"ПКМ", "C"}}, {u8"ПКМ", u8"ЛКМ", "D", "C"}, 5, {}), keymap_alternatives = {
        CBUGER_REPEAT_STAGES({{u8"ЛКМ", "D", u8"ПКМ", "C"}}, {u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}, 5, {})
    }},
    { name = u8"ДаблХит + Фаст | Fast + DubleHit", guide_text = "", data = CBUGER_REPEAT_STAGES(
        {{u8"ЛКМ", u8"Ф", u8"ПКМ", "C", u8"ЛКМ"},
         {"C", u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}},
        {u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}, 3, {}), keymap_alternatives = {
        CBUGER_REPEAT_STAGES(
            {{u8"ЛКМ", "D", u8"ПКМ", "C", u8"ЛКМ"},
             {"C", u8"ПКМ", u8"ЛКМ", "D", "C"}},
            {u8"ПКМ", u8"ЛКМ", "D", "C"}, 3,
            {{u8"ПКМ", u8"ПКМ", "D", "C"}})
    }},
    { name = u8"Фаст + Слайд | Fast + Litefoot", guide_text = "", data = CBUGER_REPEAT_STAGES(
        {}, {u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}, 6,
        {{"D", "C", u8"ПРОБЕЛ"}}), keymap_alternatives = {
        CBUGER_REPEAT_STAGES(
            {}, {u8"ПКМ", u8"ЛКМ", "D", "C"}, 6,
            {{u8"Ф", "C", u8"ПРОБЕЛ"}})
    }},
    { name = u8"Фаст + Рывок | Fast + Hardgun", guide_text = "", data = CBUGER_REPEAT_STAGES(
        {}, {u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}, 5,
        {{"D", "C", "Q", "E", u8"ПРОБЕЛ"}}), keymap_alternatives = {
        CBUGER_REPEAT_STAGES(
            {}, {u8"ПКМ", u8"ЛКМ", "D", "C"}, 5,
            {{u8"Ф", "C", "Q", "E", u8"ПРОБЕЛ"}})
    }},
    { name = u8"ДаблХит + Фаст + Рывок | Fast + DubleHit + Hardgun", guide_text = "", data = CBUGER_REPEAT_STAGES(
        {{u8"ЛКМ", u8"Ф", u8"ПКМ", "C", u8"ЛКМ"},
         {"C", u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}},
        {u8"ПКМ", u8"ЛКМ", u8"Ф", "C"}, 3,
        {{"D", "C", "Q", "E", u8"ПРОБЕЛ"}}), keymap_alternatives = {
        CBUGER_REPEAT_STAGES(
            {{u8"ЛКМ", "D", u8"ПКМ", "C", u8"ЛКМ"},
             {"C", u8"ПКМ", u8"ЛКМ", "D", "C"}},
            {u8"ПКМ", u8"ЛКМ", "D", "C"}, 3,
            {{u8"Ф", "C", "Q", "E", u8"ПРОБЕЛ"}})
    }},
}
S.combos_list = {}
S.KEY_COLORS  = { NORMAL = 0xFFFFFFFF, HELD = 0xFF006400 }
S.state = {
    current_combo        = nil,
    current_combo_name   = nil,
    current_combo_index  = nil,
    combo_started        = false,
    key_logs             = {},
    key_states           = {},
    current_key_index    = 1,
    current_part_index   = 1,
    key_required_hold    = {},
    hold_start_times     = {},
    hold_durations       = {},
    DEFAULT_HOLD_TIME    = 0.5,
    NON_HOLD_ERROR_TIME  = 0.5,
    held_keys            = {},
    hold_triggered       = {},
    blocked_held         = {},
    error_state          = { is_error = false, error_time = 0 },
    wrong_key            = nil,
    wrong_slot           = nil,
    wrong_part_index     = nil,
    combo_mini_error     = nil,
    combo_completed      = false,
    combo_display_completed = false,
    completed_wait_keys  = {},
    completed_at_frame   = nil,
    last_combo_activity  = 0,
    LAST_ACTIVITY_TIMEOUT = 3.0,
    ryvok_swapped        = false,
    last_pressed_key_name = nil,
    correct_press_count  = {},
    hold_max_times       = {},
    key_needs_release    = {},
    tap_keys_last_part   = {},
    tap_keys_released    = {},
    error_recovery_at    = nil,
    active_bridge_code   = nil,
    last_correct_flash_key       = nil,
    last_correct_flash_time      = 0,
    last_correct_flash_part_idx  = nil,
    last_correct_flash_key_idx   = nil,
    combo_streak         = 0,
            runtime_frame        = 0,
    combo_transition_frame = -1,
    pending_next_part_key = nil,
}
S.log_buffer = {}
S.MAX_LOGS   = 50
S.all_monitored_keys = {
    {code = 0x01, name = u8"ЛКМ"},
    {code = 0x02, name = u8"ПКМ"},
    {code = 0x41, name = "A"},
    {code = 0x57, name = "W"},
    {code = 0x45, name = "E"},
    {code = 0x44, name = "D"},
    {code = 0x46, name = u8"А"},
    {code = 0x53, name = "S"},
    {code = 0x43, name = "C"},
    {code = 0x51, name = "Q"},
    {code = 0x20, name = u8"ПРОБЕЛ"},
}
S.prev_key_states = {}
Data.iniFile = 'cbuger.ini'
S.cfg = Lib.inicfg.load({
    config = {
        active = false, move = false, border_thickness = 1.2,
        border_mode = 2, text_alpha = 1.0,
        held_r = 0, held_g = 100/255, held_b = 0, held_a = 1,
        correct_r = 0, correct_g = 1, correct_b = 0, correct_a = 1,
        error_r = 1, error_g = 0, error_b = 0, error_a = 1,
        key_fill_r = 0, key_fill_g = 0, key_fill_b = 0, key_fill_a = 1,
        key_border_r = 1, key_border_g = 1, key_border_b = 1, key_border_a = 1,
        key_text_r = 1, key_text_g = 1, key_text_b = 1, key_text_a = 1,
        key_fill_rgb = false, key_border_rgb = false, key_text_rgb = false, rgb_speed = 0.6,
        pressed_fill_r = 0.2, pressed_fill_g = 0.2, pressed_fill_b = 0.2, pressed_fill_a = 1,
        pressed_border_r = 1, pressed_border_g = 1, pressed_border_b = 1, pressed_border_a = 1,
        pressed_text_r = 1, pressed_text_g = 1, pressed_text_b = 1, pressed_text_a = 1,
        pressed_fill_enabled = false, pressed_border_enabled = false, pressed_text_enabled = false,
        keyboard_scale = 1.0, keyboard_key_alpha = 1.0, keyboard_type = 0, wave_enabled = false, wave_mode = 1,
        wave_speed = 1.0, wave_transparency = 0.6, wave_target = 1, wave_color_rgb = false, wave_random_colors = false,
        wave_r = 1, wave_g = 1, wave_b = 0, wave_a = 0.8,
        show_combo_window = false, combo_window_scale = 1.0, script_enabled = false,
        combo_window_display_mode = 1, combo_footer_safety_margin = 0.0,

        combo_text_layout_gap_extra = 0.0, combo_text_layout_bottom_pad = 8.0,
        combo_text_layout_hide_step_px = 29.9,

        combo_text_layout_hide_step_adjust_px = 0.0,

        combo_text_layout_last_stage_threshold_px = -16.0,

        plaque_layout_stage_h = 28.0, plaque_layout_gap_extra = 0.0,
        plaque_layout_bottom_pad = 0.0, plaque_layout_hide_step_auto = true,
        plaque_layout_last_stage_threshold_px = -16.0,
        plaque_layout_hide_step_px = 29.9, plaque_layout_hide_step_adjust_px = 0.0,
        plaque_layout_error_reserve = 18.0,
        plaque_layout_error_always_reserve = false, plaque_layout_error_offset = 10.0,
        plaque_footer_safety_margin = 0.0,
        show_chat_messages = false,
        show_logs = false, logs_limit_row = 10, logs_style = 1, logs_display_mode = 2,
        logs_max_display = 20, logs_reverse = false, logs_combo_rgb = false,
        mouse_gap = 5.0,
        combo_action_btn_width = 160.0,
        language_mode = 1, space_as_shift = false,
        interface_alpha = 1.0, interface_lang = 1,
        recoil_enabled = false, recoil_line_thickness = 2.0, recoil_show_line = false,
        recoil_flash_r = 1.0, recoil_flash_g = 0.1, recoil_flash_b = 0.1, recoil_flash_a = 1.0,
        recoil_flash_duration = 0.15, recoil_flash_alpha = 0.55,
        recoil_correct = 0, recoil_incorrect = 0,
        recoil_ring_height = 0.0, recoil_ring_slope = 0.0,
        shotmap_enabled = false, shotmap_session_size = 30,
        initial_setup_v9_done = false,
        initial_training_layout_v1_done = false,
        initial_training_layout_v2_done = false,
        initial_training_layout_v3_done = false,
        initial_training_layout_v4_done = false,
        initial_training_layout_v6_done = false,
        initial_layout_apply_v30_done = false,
        initial_all_checkboxes_off_v1_done = false,
        dbg_layout_screenshot_values_v1 = false,
    },
    mouse = {
        active = false, x = 162.0, y = 471.0,
        lmb_width = 58, lmb_height = 29,
        rmb_width = 58, rmb_height = 29,
        mmb_width = 40, mmb_height = 29,
        side_width = 58, side_height = 20
    },
    keyboard = {
        key_width = 36, key_height = 35,
        space_width = 189, space_height = 32,
        c_x = 2.2, c_y = 9.1,
        space_x = -0.81, space_y = 8.13
    },
    pos   = { x = 10, y = 500 },
    space = { x = 10, y = 540 },

    combo = { x = -1, y = -1, w = 205, h = 120, position_saved = false },
    logs  = { x = 10, y = 400, w = 300, h = 200 },
    space = { x = 10, y = 560 },
    neon  = {
        smooth_close    = false,
        font_idx        = 0,
        win_w           = 480, win_h = 520,
        base_r          = 0.0,  base_g  = 0.8,  base_b  = 1.0,  base_a  = 0.95,
        border_r        = 0.0,  border_g= 0.8,  border_b= 1.0,  border_a= 0.66,
        button_border_r = 0.0, button_border_g = 0.32, button_border_b = 0.4, button_border_a = 0.6,
        tabs_r          = 0.0,  tabs_g  = 0.8,  tabs_b  = 1.0,  tabs_a  = 1.0,
        title_r         = 0.0,  title_g = 0.8,  title_b = 1.0,  title_a = 1.0,
        cross_r         = 1.0,  cross_g = 0.2,  cross_b = 0.2,  cross_a = 1.0,
        eye_r           = 0.0,  eye_g   = 0.8,  eye_b   = 1.0,  eye_a   = 1.0,
        gear_r          = 0.0,  gear_g  = 0.8,  gear_b  = 1.0,  gear_a  = 1.0,
        resize_r        = 0.7,  resize_g= 0.0,  resize_b= 1.0,  resize_a= 0.67,
        sec_icon_r      = 0.0,  sec_icon_g=0.8, sec_icon_b=1.0, sec_icon_a=1.0,
        tab_icon_r      = 1.0,  tab_icon_g=1.0, tab_icon_b=1.0, tab_icon_a=1.0,
        sel_r           = 0.0,  sel_g   = 0.8,  sel_b   = 1.0,  sel_a   = 1.0,
        pryanix_r       = 0.0,  pryanix_g=0.8,  pryanix_b=1.0,  pryanix_a=1.0,
        title_main_r    = 0.0,  title_main_g=0.8, title_main_b=1.0, title_main_a=1.0,
        recoil_flash_r  = 1.0,  recoil_flash_g=0.1, recoil_flash_b=0.1, recoil_flash_a=1.0,
        sparks_on       = false, sparks_speed = 1.0, sparks_size = 1.0, cursor_fx = 0,
        sparks_r        = 0.0,  sparks_g= 0.8,  sparks_b= 1.0,  sparks_a= 1.0,
        waves_on        = false, waves_speed  = 1.0, waves_var   = 0,
        waves_r         = 0.0,  waves_g = 0.8,  waves_b = 1.0,  waves_a = 1.0,
        ambient_on      = false, ambient_speed= 1.0, ambient_var = 0,
        ambient1_r      = 0.0,  ambient1_g=0.0, ambient1_b=1.0, ambient1_a=1.0,
        ambient2_r      = 1.0,  ambient2_g=0.0, ambient2_b=0.0, ambient2_a=1.0,
    }
}, Data.iniFile)
local had_legacy_combo_debug =
    S.cfg.config.combo_debug_bottom_padding ~= nil or
    S.cfg.config.combo_debug_extra_height ~= nil
local had_legacy_combo_width = tonumber(S.cfg.combo.w) == 220
if had_legacy_combo_debug or had_legacy_combo_width then
    S.cfg.combo.w = 205
end
S.cfg.config.combo_debug_bottom_padding = nil
S.cfg.config.combo_debug_extra_height = nil
if had_legacy_combo_debug or had_legacy_combo_width then
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end

if type(S.cfg.combo) == 'table' and S.cfg.combo.position_saved ~= true then
    S.cfg.combo.x = -1
    S.cfg.combo.y = -1
    S.cfg.combo.position_saved = false
end
if not doesFileExist(CBUGER_CONFIG .. Data.iniFile) then
   Lib.inicfg.save(S.cfg, Data.iniFile)
end

if S.cfg.config.plaque_bottom_pad_25_5_applied_v2 ~= true then
    S.cfg.config.plaque_bottom_pad_25_5_applied_v2 = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end

if S.cfg.config.combo_stage_gap_px_migrated_v1 ~= true then
    S.cfg.config.combo_text_layout_gap_extra = math.max(0, 4.0 + (tonumber(S.cfg.config.combo_text_layout_gap_extra) or 0.0))
    S.cfg.config.plaque_layout_gap_extra = math.max(0, 4.0 + (tonumber(S.cfg.config.plaque_layout_gap_extra) or 0.0))
    S.cfg.config.combo_stage_gap_px_migrated_v1 = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end

if S.cfg.config.dbg_layout_screenshot_values_v1 ~= true then

    S.cfg.config.combo_text_layout_gap_extra = 4.0
    S.cfg.config.combo_text_layout_last_stage_threshold_px = -16.0
    S.cfg.config.combo_text_layout_bottom_pad = 8.0
    S.cfg.config.combo_text_layout_hide_step_px = 29.9
    S.cfg.config.combo_text_layout_hide_step_adjust_px = 0.0

    S.cfg.config.plaque_layout_stage_h = 28.0
    S.cfg.config.plaque_layout_gap_extra = 4.0
    S.cfg.config.plaque_layout_bottom_pad = 0.0
    S.cfg.config.plaque_layout_last_stage_threshold_px = -16.0
    S.cfg.config.plaque_layout_hide_step_auto = true
    S.cfg.config.plaque_layout_hide_step_px = 29.9
    S.cfg.config.plaque_layout_hide_step_adjust_px = 0.0
    S.cfg.config.plaque_layout_error_offset = 10.0
    S.cfg.config.plaque_layout_error_reserve = 18.0
    S.cfg.config.plaque_layout_error_always_reserve = false
    S.cfg.config.plaque_footer_safety_margin = 0.0

    S.cfg.config.dbg_layout_screenshot_values_v1 = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if S.cfg.config.combo_text_layout_bottom_pad == nil then
    S.cfg.config.combo_text_layout_bottom_pad = 8.0
end
if S.cfg.config.mouse_gap == nil then
    S.cfg.config.mouse_gap = 5.0
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_setup_v9_done then
    S.cfg.config.keyboard_type = 0
    S.cfg.config.key_fill_rgb = false
    S.cfg.config.key_border_rgb = false
    S.cfg.config.key_text_rgb = false
    S.cfg.config.pressed_fill_enabled = false
    S.cfg.config.pressed_border_enabled = false
    S.cfg.config.pressed_text_enabled = false
    S.cfg.config.initial_setup_v9_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_all_checkboxes_off_v1_done then
    S.cfg.config.script_enabled         = false
    S.cfg.config.active                = false
    S.cfg.config.move                  = false
    S.cfg.config.space_as_shift        = false
    S.cfg.config.show_chat_messages    = false
    S.cfg.config.show_combo_window     = false
    S.cfg.config.show_logs             = false
    S.cfg.config.logs_combo_rgb        = false
    S.cfg.config.recoil_enabled        = false
    S.cfg.config.recoil_show_line      = false
    S.cfg.config.shotmap_enabled       = false
    S.cfg.config.key_fill_rgb          = false
    S.cfg.config.key_border_rgb        = false
    S.cfg.config.key_text_rgb          = false
    S.cfg.config.pressed_fill_enabled  = false
    S.cfg.config.pressed_border_enabled= false
    S.cfg.config.pressed_text_enabled  = false
    S.cfg.config.wave_enabled          = false
    S.cfg.config.wave_color_rgb        = false
    S.cfg.config.wave_random_colors    = false
    S.cfg.neon.smooth_close             = false
    S.cfg.neon.sparks_on                = false
    S.cfg.neon.waves_on                 = false
    S.cfg.neon.ambient_on               = false
    S.cfg.config.initial_all_checkboxes_off_v1_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_training_layout_v3_done then
    S.cfg.keyboard.c_x = 2.20
    S.cfg.keyboard.c_y = 9.10
    S.cfg.keyboard.space_x = 5.20
    S.cfg.keyboard.space_y = 18.90
    S.cfg.config.initial_training_layout_v3_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_training_layout_v4_done then
    S.cfg.config.keyboard_type = 0
    S.cfg.keyboard.c_x = 2.20
    S.cfg.keyboard.c_y = 9.10
    S.cfg.keyboard.space_x = 5.20
    S.cfg.keyboard.space_y = 18.90
    S.cfg.config.initial_training_layout_v4_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_training_layout_v5_done then
    S.cfg.keyboard.space_x = -0.81
    S.cfg.keyboard.space_y = 8.13
    S.cfg.config.initial_training_layout_v5_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_training_layout_v6_done then
    S.cfg.config.keyboard_type = 0
    S.cfg.pos.x = 14.0
    S.cfg.pos.y = 474.0
    S.cfg.space.x = 13.0
    S.cfg.space.y = 578.0
    S.cfg.keyboard.space_x = -0.81
    S.cfg.keyboard.space_y = 8.13
    S.cfg.mouse.x = 158.0
    S.cfg.mouse.y = 478.0
    S.cfg.config.mouse_gap = 5.0
    S.cfg.config.initial_training_layout_v6_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_training_layout_v7_done then
    S.cfg.config.keyboard_type = 0
    S.cfg.pos.x = 14.0
    S.cfg.pos.y = 474.0
    S.cfg.space.x = 13.0
    S.cfg.space.y = 578.0
    S.cfg.keyboard.space_x = -0.81
    S.cfg.keyboard.space_y = 8.13
    S.cfg.mouse.x = 158.0
    S.cfg.mouse.y = 478.0
    S.cfg.config.mouse_gap = 5.0
    S.cfg.config.initial_training_layout_v7_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_training_layout_v8_done then
    S.cfg.space.x = 14.0
    S.cfg.space.y = 579.0
    S.cfg.keyboard.space_x = -0.81
    S.cfg.keyboard.space_y = 8.13
    S.cfg.config.initial_training_layout_v8_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
if not S.cfg.config.initial_layout_apply_v30_done then
    S.cfg.config.keyboard_type = 0
    S.cfg.pos.x = 14.0
    S.cfg.pos.y = 474.0
    S.cfg.space.x = 14.0
    S.cfg.space.y = 579.0
    S.cfg.mouse.x = 158.0
    S.cfg.mouse.y = 478.0
    S.cfg.config.mouse_gap = 5.0
    S.cfg.keyboard.space_x = -0.81
    S.cfg.keyboard.space_y = 8.13
    S.cfg.config.initial_layout_apply_v30_done = true
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
local ui = {}
ui.settings              = Lib.new.bool(false)
ui.keyboard              = Lib.new.bool(false)
ui.mouse                 = Lib.new.bool(false)
ui.move                  = Lib.new.bool(S.cfg.config.move)
ui.script_enabled        = Lib.new.bool(S.cfg.config.script_enabled)
ui.show_combo_window     = Lib.new.bool(S.cfg.config.show_combo_window)
ui.show_chat_messages    = Lib.new.bool(S.cfg.config.show_chat_messages)
ui.show_logs             = Lib.new.bool(S.cfg.config.show_logs)
ui.wave_enabled          = Lib.new.bool(S.cfg.config.wave_enabled)
ui.key_fill_rgb          = Lib.new.bool(S.cfg.config.key_fill_rgb)
ui.key_border_rgb        = Lib.new.bool(S.cfg.config.key_border_rgb)
ui.key_text_rgb          = Lib.new.bool(S.cfg.config.key_text_rgb)
ui.guide_open            = Lib.new.bool(false)
ui.current_guide_index   = nil
ui.current_guide_name    = nil
ui.guide_text_buffer      = Lib.new.char[16384]("")
ui.guide_dragging         = false
ui.guide_drag_offset      = { x = 0, y = 0 }
ui.guide_drag_pos         = nil
ui.guide_resizing         = false
ui.guide_resize_start_size = { w = 359, h = 250 }
ui.guide_resize_start_mouse = { x = 0, y = 0 }
ui.guide_window_size      = { w = 359, h = 250 }
ui.guide_color            = Lib.new.float[4](1, 1, 1, 1)
ui.guide_picker           = Lib.new.float[4](1, 1, 1, 1)
ui.guide_size             = Lib.new.float(1.0)
ui.guide_show_size        = false
ui.tab_selected              = Lib.new.int(0)
ui.language_mode             = Lib.new.int(S.cfg.config.language_mode or 1)
ui.interface_alpha           = Lib.new.float(S.cfg.config.interface_alpha or 1.0)
ui.interface_lang            = Lib.new.int(S.cfg.config.interface_lang or 1)
ui.recoil_enabled            = Lib.new.bool(S.cfg.config.recoil_enabled or false)
ui.recoil_line_thickness     = Lib.new.float(S.cfg.config.recoil_line_thickness or 2.0)
ui.recoil_flash_duration     = Lib.new.float(S.cfg.config.recoil_flash_duration or 0.15)
ui.recoil_flash_alpha        = Lib.new.float(S.cfg.config.recoil_flash_alpha or 0.55)
ui.recoil_show_line          = Lib.new.bool(S.cfg.config.recoil_show_line ~= false)
Data.RING_RADIUS   = 6.0
Data.RING_EYE      = 0.55
Data.RING_SEGMENTS = 96
Data.RING_STEP     = 0.05
Data.recoil_ring = { height = S.cfg.config.recoil_ring_height or 0.0 }
if (S.cfg.config.recoil_ring_height == nil or S.cfg.config.recoil_ring_height == 0)
   and (S.cfg.config.recoil_ring_slope or 0) ~= 0 then
   Data.recoil_ring.height = S.cfg.config.recoil_ring_slope * Data.RING_RADIUS
end
Data.SHOTMAP_KPD_RADIUS = 1.5
Data.SHOTMAP_SCALE      = 4.0
ui.shotmap_enabled           = Lib.new.bool(S.cfg.config.shotmap_enabled or false)
ui.shotmap_session_size      = Lib.new.int(S.cfg.config.shotmap_session_size or 30)
ui.shotmap_view_mode         = Lib.new.int(1)
ui.shotmap_view_index        = Lib.new.int(1)
 Fn.shotmapCardCount = function()
    return #Data.shotmap.sessions + 1
end
 Fn.shotmapGetCard = function(idx)
    local total = #Data.shotmap.sessions
    if idx <= total then
        return Data.shotmap.sessions[idx], false
    end
    return Data.shotmap.current, true
end
 Fn.shotmapVisiblePoints = function()
    if ui.shotmap_view_mode[0] == 2 then
        local pts = {}
        for _, s in ipairs(Data.shotmap.sessions) do
            for _, p in ipairs(s.points) do pts[#pts + 1] = p end
        end
        for _, p in ipairs(Data.shotmap.current.points) do pts[#pts + 1] = p end
        return pts, "agg:" .. #pts
    else
        local total = Fn.shotmapCardCount()
        local idx = ui.shotmap_view_index[0]
        if idx < 1 then idx = 1 end
        if idx > total then idx = total end
        ui.shotmap_view_index[0] = idx
        local card = Fn.shotmapGetCard(idx)
        return card.points, "card" .. idx .. ":" .. #card.points
    end
end
 Fn.shotmapComputeColors = function(points)
    local cell = 5
    local bins = {}
    for _, p in ipairs(points) do
        local key = math.floor(p.x / cell) .. ":" .. math.floor(p.y / cell)
        bins[key] = (bins[key] or 0) + 1
    end
    local maxCount = 1
    for _, c in pairs(bins) do if c > maxCount then maxCount = c end end
    local colors = {}
    for i, p in ipairs(points) do
        local key = math.floor(p.x / cell) .. ":" .. math.floor(p.y / cell)
        local r, g, b = Fn.heatColor(bins[key] / maxCount)
        colors[i] = {r, g, b}
    end
    return colors
end
Data.shotmap_color_cache = { key = nil, colors = nil }
 Fn.shotmapStats = function(points, fast)
    local n = #points
    local st = { n = n, spread = 0, kpd = 0, mean_p = 0 }
    if n == 0 then return st end
    local SC = Data.SHOTMAP_SCALE
    local rad, inside = Data.SHOTMAP_KPD_RADIUS, 0
    for _, p in ipairs(points) do
        local x, y = p.x or 0, p.y or 0
        if math.sqrt(x * x + y * y) <= rad then inside = inside + 1 end
    end
    st.kpd = inside / n * 100
    if n == 1 then
        st.mean_p = 0
    elseif n <= 250 then
        local sum_p, cnt = 0, 0
        for i = 1, n - 1 do
            local pi = points[i]
            for j = i + 1, n do
                local pj = points[j]
                local dx = (pi.x or 0) - (pj.x or 0)
                local dy = (pi.y or 0) - (pj.y or 0)
                sum_p = sum_p + math.sqrt(dx * dx + dy * dy)
                cnt = cnt + 1
            end
        end
        st.mean_p = cnt > 0 and (sum_p / cnt) or 0
    else
        local cx, cy = 0, 0
        for _, p in ipairs(points) do
            cx = cx + (p.x or 0)
            cy = cy + (p.y or 0)
        end
        cx, cy = cx / n, cy / n
        local sr = 0
        for _, p in ipairs(points) do
            local dx = (p.x or 0) - cx
            local dy = (p.y or 0) - cy
            sr = sr + math.sqrt(dx * dx + dy * dy)
        end
        st.mean_p = (sr / n) * 1.13
    end
    st.spread = math.max(0, math.min(100, (1 - st.mean_p / SC) * 100))
    return st
end
Data.shotmap_stats_cache = {}
 Fn.shotmapStatsCached = function(slot, points, key, fast)
    local c = Data.shotmap_stats_cache[slot]
    if not c then c = {}; Data.shotmap_stats_cache[slot] = c end
    local k = tostring(key) .. ":" .. #points
    if c.key ~= k then c.key = k; c.stats = Fn.shotmapStats(points, fast) end
    return c.stats
end
 Fn.statColorVec = function(pct, higher_better)
    local t = math.max(0, math.min(1, (pct or 0) / 100))
    if higher_better == false then t = 1 - t end
    local r, g, b
    if t < 0.5 then
        r, g, b = 1.0, 0.15 + 1.5 * t, 0.12
    else
        r, g, b = 1.0 - 1.6 * (t - 0.5), 0.9, 0.20
    end
    return Lib.imgui.ImVec4(math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), b, 1)
end
 Fn.shotmapSessionStats = function()
    local cards_n = #Data.shotmap.sessions
    local cur_n   = #Data.shotmap.current.points
    local k = "sess:" .. cards_n .. ":" .. cur_n
    local c = Data.shotmap_stats_cache["session"]
    if c and c.key == k then return c.stats end
    local all = {}
    for _, sess in ipairs(Data.shotmap.sessions) do
        for _, p in ipairs(sess.points) do all[#all + 1] = p end
    end
    for _, p in ipairs(Data.shotmap.current.points) do all[#all + 1] = p end
    local st = Fn.shotmapStats(all, true)
    st.cards = cards_n
    Data.shotmap_stats_cache["session"] = { key = k, stats = st }
    return st
end
 Fn.shotmapCardDate = function(ts)
    if not ts or ts == 0 then return "-" end
    local ok, str = pcall(os.date, "%d.%m %H:%M", ts)
    return ok and str or "-"
end
 Fn.shotmapStatLines = function(st)
   Lib.imgui.TextColored(Fn.statColorVec(st.spread, true),
        Fn.T(u8"Разброс: ") .. string.format("%.1f%%", st.spread))
   Lib.imgui.TextColored(Fn.statColorVec(st.kpd, true),
        Fn.T(u8"КПД: ") .. string.format("%.1f%%", st.kpd))
end
 Fn.shotmapTooltip = function()
   Lib.imgui.BeginTooltip()
    local head_col = Lib.imgui.ImVec4(0.55, 0.85, 1.0, 1.0)
    if ui.shotmap_view_mode[0] == 2 then
        local ss = Fn.shotmapSessionStats()
       Lib.imgui.TextColored(head_col, Fn.T(u8"Общая сессия"))
        if ss.n == 0 then
           Lib.imgui.Text(Fn.T(u8"Нет данных"))
        else
           Lib.imgui.Text(Fn.T(u8"Выстрелов: ") .. ss.n .. "   " .. Fn.T(u8"Карточек: ") .. ((ss.cards or 0) + 1))
           Fn.shotmapStatLines(ss)
        end
    else
        local idx  = ui.shotmap_view_index[0]
        local card, is_current = Fn.shotmapGetCard(idx)
        local pts  = card and card.points or {}
        local st   = Fn.shotmapStatsCached("card", pts, "card" .. idx)
        local head = is_current and Fn.T(u8"Сейчас")
            or (Fn.T(u8"Карточка ") .. idx .. "  " .. Fn.shotmapCardDate(card and card.ts))
       Lib.imgui.TextColored(head_col, head)
        if st.n == 0 then
           Lib.imgui.Text(Fn.T(u8"Нет данных"))
        else
           Lib.imgui.Text(Fn.T(u8"Выстрелов: ") .. st.n)
           Fn.shotmapStatLines(st)
        end
    end
   Lib.imgui.Separator()
   Lib.imgui.TextColored(Lib.imgui.ImVec4(0.6, 0.6, 0.65, 1), Fn.T(u8"ЛКМ — график по карточкам"))
   Lib.imgui.EndTooltip()
end
Data.shotmap_chart_open   = false
Data.shotmap_chart_metric = 1
 Fn.shotmapChartSeries = function()
    local cards_n = #Data.shotmap.sessions
    local cur_n   = #Data.shotmap.current.points
    local k = "chart:" .. cards_n .. ":" .. cur_n .. ":" .. Data.shotmap_chart_metric
    local c = Data.shotmap_stats_cache["chart"]
    if c and c.key == k then return c.stats end
    local series = {}
    local function push(card, idx, is_cur)
        if #card.points == 0 then return end
        local st = Fn.shotmapStats(card.points, true)
        local v = st.spread
        if Data.shotmap_chart_metric == 2 then v = st.kpd end
        series[#series + 1] = { value = v, st = st, ts = card.ts, idx = idx, current = is_cur }
    end
    for i, sess in ipairs(Data.shotmap.sessions) do push(sess, i, false) end
    push(Data.shotmap.current, cards_n + 1, true)
   Data.shotmap_stats_cache["chart"] = { key = k, stats = series }
    return series
end
 Fn.drawShotmapChart = function(dl, p_min, p_max, alpha_mult)
    local bg = Data.neon_active_colors[Lib.imgui.Col.WindowBg] or {0.04, 0.04, 0.07, 0.97}
    dl:AddRectFilled(p_min, p_max,
       Data.nfn.pack_color(bg[1] + 0.03, bg[2] + 0.03, bg[3] + 0.05, 0.92, false, alpha_mult), 8)
    local bc = neon_fx.neon_border_color
    dl:AddRect(p_min, p_max,
       Data.nfn.pack_color(bc[1], bc[2], bc[3], 0.6, true, alpha_mult), 8, 15, 1.5)
    local titles = { Fn.T(u8"Разброс"), Fn.T(u8"КПД") }
    local title  = titles[Data.shotmap_chart_metric] or titles[1]
    local higher = Data.shotmap_chart_metric == 2
    local padL, padT, padB, padR = 26, 22, 18, 8
    local x0, y0 = p_min.x + padL, p_min.y + padT
    local x1, y1 = p_max.x - padR, p_max.y - padB
    if x1 - x0 < 20 or y1 - y0 < 20 then return end
    local grid = Fn.getColorU32(1, 1, 1, 0.10 * alpha_mult, false)
    local dim  = Fn.getColorU32(0.65, 0.7, 0.8, 0.75 * alpha_mult, false)
    for lvl = 0, 4 do
        local val = 100 * lvl / 4
        local yy  = y1 - (val / 100) * (y1 - y0)
        dl:AddLine(Lib.imgui.ImVec2(x0, yy), Lib.imgui.ImVec2(x1, yy), grid, 1)
        dl:AddText(Lib.imgui.ImVec2(p_min.x + 4, yy - 6), dim, tostring(math.floor(val)))
    end
    dl:AddText(Lib.imgui.ImVec2(x0 + 2, p_min.y + 5), Fn.getColorU32(0.55, 0.85, 1.0, alpha_mult, false), title)
    local series = Fn.shotmapChartSeries()
    local n = #series
    if n == 0 then
        dl:AddText(Lib.imgui.ImVec2(x0 + 6, (y0 + y1) / 2), dim, Fn.T(u8"Нет данных"))
        return
    end
    local stepX = n > 1 and (x1 - x0 - 8) / (n - 1) or 0
    local pts = {}
    for i, e in ipairs(series) do
        pts[i] = {
            x = x0 + 4 + stepX * (i - 1),
            y = y1 - (math.max(0, math.min(100, e.value)) / 100) * (y1 - y0),
            e = e,
        }
    end
    for i = 1, n - 1 do
        local c1 = Fn.statColorVec(series[i].value, higher)
        local fill = Fn.getColorU32(c1.x, c1.y, c1.z, 0.18 * alpha_mult, false)
        dl:AddQuadFilled(Lib.imgui.ImVec2(pts[i].x, pts[i].y), Lib.imgui.ImVec2(pts[i + 1].x, pts[i + 1].y),
            Lib.imgui.ImVec2(pts[i + 1].x, y1), Lib.imgui.ImVec2(pts[i].x, y1), fill)
        dl:AddLine(Lib.imgui.ImVec2(pts[i].x, pts[i].y), Lib.imgui.ImVec2(pts[i + 1].x, pts[i + 1].y),
            Fn.getColorU32(c1.x, c1.y, c1.z, 0.9 * alpha_mult, false), 2.0)
    end
    for i = 1, n do
        local c = Fn.statColorVec(series[i].value, higher)
        dl:AddCircleFilled(Lib.imgui.ImVec2(pts[i].x, pts[i].y), 2.8,
            Fn.getColorU32(c.x, c.y, c.z, 0.95 * alpha_mult, false), 10)
    end
    local function label(i)
        local e = series[i]
        return e.current and Fn.T(u8"Сейчас") or Fn.shotmapCardDate(e.ts)
    end
    dl:AddText(Lib.imgui.ImVec2(x0 - 2, y1 + 3), dim, label(1))
    if n > 2 then
        local mid = math.ceil(n / 2)
        dl:AddText(Lib.imgui.ImVec2(pts[mid].x - 18, y1 + 3), dim, label(mid))
    end
    if n > 1 then
        local lastTxt = label(n)
        local ts = Lib.imgui.CalcTextSize(lastTxt)
        dl:AddText(Lib.imgui.ImVec2(math.min(x1 - ts.x, pts[n].x - ts.x / 2), y1 + 3), dim, lastTxt)
    end
    local mp = Lib.imgui.GetMousePos()
    if mp and mp.x >= p_min.x and mp.x <= p_max.x and mp.y >= p_min.y and mp.y <= p_max.y then
        local best, bd = 1, math.huge
        for i, pt in ipairs(pts) do
            local d = math.abs(pt.x - mp.x)
            if d < bd then bd = d; best = i end
        end
        local pt = pts[best]
        dl:AddCircle(Lib.imgui.ImVec2(pt.x, pt.y), 5, Fn.getColorU32(1, 1, 1, 0.9 * alpha_mult, false), 12, 1.5)
       Lib.imgui.BeginTooltip()
       Lib.imgui.TextColored(Lib.imgui.ImVec4(0.55, 0.85, 1.0, 1.0),
            (pt.e.current and Fn.T(u8"Сейчас") or (Fn.T(u8"Карточка ") .. pt.e.idx))
            .. "  " .. Fn.shotmapCardDate(pt.e.ts))
       Lib.imgui.Text(Fn.T(u8"Выстрелов: ") .. pt.e.st.n)
       Fn.shotmapStatLines(pt.e.st)
       Lib.imgui.EndTooltip()
    end
end
 Fn.drawShotmapCard = function(dl, p_min, p_max, points, alpha_mult)
    local bg = Data.neon_active_colors[Lib.imgui.Col.WindowBg] or {0.04, 0.04, 0.07, 0.97}
    dl:AddRectFilled(p_min, p_max,
       Data.nfn.pack_color(bg[1] + 0.03, bg[2] + 0.03, bg[3] + 0.05, 0.92, false, alpha_mult), 8)
    local bc = neon_fx.neon_border_color
    dl:AddRect(p_min, p_max,
       Data.nfn.pack_color(bc[1], bc[2], bc[3], 0.6, true, alpha_mult), 8, 15, 1.5)
    local cx, cy = (p_min.x + p_max.x) / 2, (p_min.y + p_max.y) / 2
    local half_w, half_h = (p_max.x - p_min.x) / 2 - 10, (p_max.y - p_min.y) / 2 - 10
    if half_w < 4 or half_h < 4 then return end
    local guide_col = Fn.getColorU32(1, 1, 1, 0.12 * alpha_mult, false)
    dl:AddLine(Lib.imgui.ImVec2(cx - half_w, cy), Lib.imgui.ImVec2(cx + half_w, cy), guide_col, 1)
    dl:AddLine(Lib.imgui.ImVec2(cx, cy - half_h), Lib.imgui.ImVec2(cx, cy + half_h), guide_col, 1)
    if #points == 0 then return end
    local cache = Data.shotmap_color_cache
    local key = tostring(ui.shotmap_view_mode[0]) .. ":" .. tostring(ui.shotmap_view_index[0]) .. ":" .. #points
    if cache.key ~= key then
        cache.key    = key
        cache.colors = Fn.shotmapComputeColors(points)
    end
    local colors = cache.colors
    local maxAbs = 1
    for _, p in ipairs(points) do
        maxAbs = math.max(maxAbs, math.abs(p.x), math.abs(p.y))
    end
    local scale = math.min(half_w, half_h) / maxAbs
    for i, p in ipairs(points) do
        local c  = colors[i] or {0.2, 0.85, 0.2}
        local px = cx + p.x * scale
        local py = cy + p.y * scale
        dl:AddCircleFilled(Lib.imgui.ImVec2(px, py), 2.2, Fn.getColorU32(c[1], c[2], c[3], 0.9 * alpha_mult, true), 8)
    end
end
Data.UI_TRANSLATIONS_RAW = {
    [u8"(пустой — перетащите сюда)"] = "(empty — drag here)",
    [u8"+ Добавить этап"] = "+ Add stage",
    [u8"2xЛКМ - настройки зажатия. ПКМ - удалить. Перетаскивание - перемещение."] = "2xLMB - hold settings. RMB - delete. Drag - move.",
    [u8"< Назад"] = "< Back",
    [u8"OK"] = "OK",
    [u8"RGB (Логи / Комбо)"] = "RGB (Logs / Combo)",
    [u8"[CBUGER]: Ожидалась: "] = "[CBUGER]: Expected: ",
    [u8"[CBUGER]: Ошибка, лишнее нажатие: "] = "[CBUGER]: Error, extra press: ",
    [u8"[CBUGER]: Ошибка, нажата не та клавиша: "] = "[CBUGER]: Error, wrong key pressed: ",
    [u8", но нажата: "] = ", but pressed: ",
    [u8"[CBUGER]: Ошибка, вы зажали слишком долго: "] = "[CBUGER]: Error, you held too long: ",
    [u8"[CBUGER]: Ошибка, вы зажали: "] = "[CBUGER]: Error, you held: ",
    [u8"[CBUGER]: Ошибка, вы не зажимали: "] = "[CBUGER]: Error, you did not hold: ",
    [u8"Анимация вкладок"] = "Tab animation",
    [u8"Базовый цвет интерфейса"] = "Base interface color",
    [u8"Вариант клавиатуры"] = "Keyboard variant",
    [u8"Вкл"] = "On",
    [u8"Вкл##pborder"] = "On##pborder",
    [u8"Вкл##pfill"] = "On##pfill",
    [u8"Вкл##ptext"] = "On##ptext",
    [u8"Включить волну"] = "Enable wave",
    [u8"Волна на клавишах"] = "Wave on keys",
    [u8"Клавиши"] = "Keys",
    [u8"Всё"] = "All",
    [u8"Режим волны:"] = "Wave mode:",
    [u8"RGB волна"] = "RGB wave",
    [u8"Рандомные цвета волны"] = "Random wave colors",
    [u8"Контроль +С"] = "Recoil Control (+C)",
    [u8"Включить контроль"] = "Enable control",
    [u8"Поставить линию"] = "Place the line",
    [u8"Линия ещё не установлена"] = "Line not placed yet",
    [u8"Ожидание выстрела..."] = "Waiting for a shot...",
    [u8"Наведитесь и выстрелите, чтобы поставить линию"] = "Aim and fire to place the line",
    [u8"Толщина линии"] = "Line thickness",
    [u8"Длительность вспышки"] = "Flash duration",
    [u8"Яркость вспышки"] = "Flash brightness",
    [u8"Цвет вспышки"] = "Flash color",
    [u8"Показывать линию"] = "Show line",
    [u8"Поставить черту"] = "Set the line",
    [u8"Высота черты: "] = "Line height: ",
    [u8" м"] = " m",
    [u8"Выше"] = "Up",
    [u8"Ниже"] = "Down",
    [u8"По центру"] = "Center",
    [u8"Черта ещё не установлена"] = "Line not set yet",
    [u8"Наведитесь и выстрелите, чтобы задать высоту черты"] = "Aim and fire to set the line height",
    [u8"Правильно: "] = "Correct: ",
    [u8"Неправильно: "] = "Incorrect: ",
    [u8"КПД: "] = "Efficiency: ",
    [u8"Сбросить статистику"] = "Reset statistics",
    [u8"Карта выстрелов"] = "Shot Map",
    [u8"Записывать карту"] = "Record map",
    [u8"Выстрелов на карточку"] = "Shots per card",
    [u8"По сессиям"] = "By session",
    [u8"Общий вид"] = "Overall view",
    [u8"Сейчас"] = "Now",
    [u8"Карточка "] = "Card ",
    [u8"Очистить карту"] = "Clear map",
    [u8"Точность"] = "Accuracy",
    [u8"ЛКМ — график по карточкам"] = "LMB — chart by cards",
    [u8"Общая сессия"] = "Whole session",
    [u8"Выстрелов: "] = "Shots: ",
    [u8"Разброс: "] = "Spread: ",
    [u8"Разброс"] = "Spread",
    [u8"Карточек: "] = "Cards: ",
    [u8"Нет данных"] = "No data",
    [u8"Время (сек):"] = "Time (sec):",
    [u8"Время зажатия (сек):"] = "Hold time (sec):",
    [u8"Вся клавиатура"] = "Full keyboard",
    [u8"Выбор шрифта"] = "Font selection",
    [u8"Выкл"] = "Off",
    [u8"Гайд"] = "Guide",
    [u8"Глаз (свернуть)"] = "Eye (minimize)",
    [u8"Добавить клавишу в последний этап:"] = "Add key to last stage:",
    [u8"Дублировать"] = "Duplicate",
    [u8"Зажатие включено"] = "Hold enabled",
    [u8"Зажатие выключено"] = "Hold disabled",
    [u8"Закрыть"] = "Close",
    [u8"Заливка"] = "Fill",
    [u8"Иконки"] = "Icons",
    [u8"Иконки вкладок окна"] = "Window tab icons",
    [u8"Иконки и элементы"] = "Icons and elements",
    [u8"Клавиатура"] = "Keyboard",
    [u8"Клавиатура без NumPad"] = "Keyboard without NumPad",
    [u8"Кнопки и элементы"] = "Buttons and elements",
    [u8"Кнопок в ряд"] = "Buttons per row",
    [u8"Комбинаций: "] = "Combos: ",
    [u8"Крестик (закрытие)"] = "Cross (close)",
    [u8"Курсор-частицы"] = "Cursor particles",
    [u8"Логи нажатий"] = "Press logs",
    [u8"Логи нажатий##logwin"] = "Press logs##logwin",
    [u8"Масштаб комбо"] = "Combo scale",
    [u8"Мышь"] = "Mouse",
    [u8"Нажмите последовательно:"] = "Press in sequence:",
    [u8"Направление:"] = "Direction:",
    [u8"Настройки для: "] = "Settings for: ",
    [u8"Настройки клавиши:"] = "Key settings:",
    [u8"Нет комбинаций"] = "No combos",
    [u8"Нет нажатий..."] = "No presses...",
    [u8"Новая комбинация"] = "New combo",
    [u8"Обводка"] = "Outline",
    [u8"Обводка:"] = "Outline:",
    [u8"Обводки кнопок"] = "Button outlines",
    [u8"Общие настройки"] = "General settings",
    [u8"Обычные:"] = "Regular:",
    [u8"Ожидалась: "] = "Expected: ",
    [u8"Окно комбинаций"] = "Combo window",
    [u8"Очистить"] = "Clear",
    [u8"Ошибка"] = "Error",
    [u8"ПРОБЕЛ"] = "SPACE",
    [u8"Переключатель вкладок"] = "Tab switcher",
    [u8"Перемещение клавиатуры"] = "Move keyboard",
    [u8"Плавное закрытие окна"] = "Smooth window closing",
    [u8"Плашки##cwm"] = "Badges##cwm",
    [u8"Плашки##lwm"] = "Badges##lwm",
    [u8"Показывать логи"] = "Show logs",
    [u8"Показывать окно"] = "Show window",
    [u8"Показывать последних"] = "Show last",
    [u8"Правильно"] = "Correct",
    [u8"При нажатии"] = "On press",
    [u8"При нажатии:"] = "On press:",
    [u8"Пробел = Shift"] = "Space = Shift",
    [u8"Прозрачность"] = "Transparency",
    [u8"Прозрачность интерфейса"] = "Interface transparency",
    [u8"Прозрачность клавиш"] = "Key transparency",
    [u8"Прозрачность текста"] = "Text transparency",
    [u8"Прямоугольное выделение"] = "Rectangular selection",
    [u8"Размер"] = "Size",
    [u8"Размер частиц"] = "Particle size",
    [u8"Рамка окна"] = "Window border",
    [u8"Расширенные настройки цветов"] = "Advanced color settings",
    [u8"Редактировать"] = "Edit",
    [u8"Редактор комбинации"] = "Combo editor",
    [u8"Редактор стиля"] = "Style editor",
    [u8"Режим анимации"] = "Animation mode",
    [u8"Режим курсора"] = "Cursor mode",
    [u8"Режим свечения"] = "Glow mode",
    [u8"Сбросить комбинацию"] = "Reset combo",
    [u8"Сбросить комбо"] = "Reset combo",
    [u8"Скорость"] = "Speed",
    [u8"Скорость RGB"] = "RGB speed",
    [u8"Скорость анимации"] = "Animation speed",
    [u8"Скорость свечения"] = "Glow speed",
    [u8"Скорость частиц"] = "Particle speed",
    [u8"Скрипт"] = "Script",
    [u8"Общая активация"] = "Global activation",
    [u8"Скроллбар"] = "Scrollbar",
    [u8"Сообщения в чате"] = "Chat messages",
    [u8"Сохранить"] = "Save",
    [u8"Текст"] = "Text",
    [u8"Текст и рамки"] = "Text and borders",
    [u8"Текст##cwm"] = "Text##cwm",
    [u8"Текст##lwm"] = "Text##lwm",
    [u8"Толщина обводки"] = "Outline thickness",
    [u8"Тренировочная (W A S D Q E / C / ПРОБЕЛ)"] = "Training (W A S D Q E / C / SPACE)",
    [u8"Удалить"] = "Delete",
    [u8"Удержание"] = "Held",
    [u8"Фон и окна"] = "Background and windows",
    [u8"Фоновое свечение"] = "Background glow",
    [u8"Цвет анимаций вкладок"] = "Tab animation color",
    [u8"Цвет вкладок"] = "Tabs color",
    [u8"Цвет волны"] = "Wave color",
    [u8"Цвет подписи"] = "Label color",
    [u8"Цвет свечения (1)"] = "Glow color (1)",
    [u8"Цвет свечения (2)"] = "Glow color (2)",
    [u8"Цвет частиц"] = "Particle color",
    [u8"Цвета"] = "Colors",
    [u8"Цвета клавиш"] = "Key colors",
    [u8"Цвета комбо-клавиш"] = "Combo-key colors",
    [u8"Шестерёнка (настройки)"] = "Gear (settings)",
    [u8"Эффекты"] = "Effects",
    [u8"Язык клавиатуры"] = "Keyboard language",
    [u8"<>"] = "<->",
    [u8"^v"] = "^v",
    [u8"><"] = "-><-",
    [u8"v^"] = "v^",
    [u8"Гайд: "] = "Guide: ",
    [u8"Обычный"] = "Normal",
    [u8"Крестики"] = "Crosses",
    [u8"Огненный хвост"] = "Fire trail",
    [u8"Капли"] = "Drops",
    [u8"Замедленный след"] = "Slow trail",
    [u8"Огненный взрыв"] = "Fire burst",
    [u8"Кольца"] = "Rings",
    [u8"Линии"] = "Lines",
    [u8"Туманность"] = "Nebula",
    [u8"Волна"] = "Wave",
    [u8"Тёмная дыра"] = "Black hole",
    [u8"Случайный"] = "Random",
    [u8"Капли-газ"] = "Gas drops",
    [u8"Диагональ"] = "Diagonal",
    [u8"Взрыв"] = "Explosion",
    [u8"Спираль"] = "Spiral",
    [u8"Шар"] = "Orb",
    [u8"Зигзаг"] = "Zigzag",
    [u8"Конфетти"] = "Confetti",
    [u8"Кристаллический шар"] = "Crystal orb",
    [u8"Волны"] = "Waves",
    [u8"Эквалайзер"] = "Equalizer",
    [u8"Расходящийся"] = "Diverging",
    [u8"Цифровой шум"] = "Digital noise",
    [u8"Прямоугольная"] = "Rectangular",
    [u8"Ноды"] = "Nodes",
    [u8"Радар"] = "Radar",
    [u8"Соты"] = "Honeycomb",
    [u8"Пузыри"] = "Bubbles",
    [u8"Синусоиды V2"] = "Sine waves V2",
    [u8"Маятник"] = "Pendulum",
    [u8"Зигзаги"] = "Zigzags",
    [u8"Звёздный дождь"] = "Star rain",
    [u8"Пузырьки круги"] = "Bubble circles",
    [u8"Шестиугольники V2"] = "Hexagons V2",
    [u8"Стрелки"] = "Arrows",
    [u8"Фигуры Лиссажу"] = "Lissajous figures",
    [u8"Деформация поля"] = "Field distortion",
    [u8"Полиция мигает"] = "Police lights",
    [u8"Мигающие вспышки"] = "Flashing bursts",
    [u8"Скользящий луч"] = "Sliding beam",
    [u8"Пульсар"] = "Pulsar",
    [u8"Стробоскоп"] = "Strobe",
    [u8"Световые полосы"] = "Light stripes",
    [u8"Пульс"] = "Pulse",
    [u8"Прожектор"] = "Spotlight",
    [u8"Острый импульс"] = "Sharp pulse",
    [u8"Молния"] = "Lightning",
    [u8"Световой мерцатель"] = "Light flicker",
    [u8"Метла"] = "Sweep",
    [u8"Хроматик"] = "Chromatic",
    [u8"Кольцо"] = "Ring",
    [u8"Морзе"] = "Morse",
    [u8"Горизонтальный скан"] = "Horizontal scan",
    [u8"Системный"] = "System",
    [u8"Фон основного окна"] = "Main window background",
    [u8"Фон дочернего виджета"] = "Child widget background",
    [u8"Фон слайдера/чекбокса"] = "Slider/checkbox background",
    [u8"Наведение слайдера"] = "Slider hover",
    [u8"Активный слайдер"] = "Active slider",
    [u8"Кнопка"] = "Button",
    [u8"Кнопка наведение"] = "Button hover",
    [u8"Кнопка нажатие"] = "Button pressed",
    [u8"Галочка"] = "Checkmark",
    [u8"Заголовок"] = "Header",
    [u8"Заголовок наведение"] = "Header hover",
    [u8"Заголовок нажатие"] = "Header pressed",
    [u8"Фон скролла"] = "Scrollbar background",
    [u8"Ползунок скролла"] = "Scrollbar grab",
    [u8"Ползунок наведение"] = "Grab hover",
    [u8"Ползунок нажатие"] = "Grab pressed",
    [u8"Основной текст"] = "Main text",
    [u8"Заголовки секций"] = "Section headers",
    [u8"Граница"] = "Border",
    [u8"Разделитель"] = "Separator",
    [u8"Настройки интерфейса"] = "Interface settings",
    [u8"Основные"] = "General",
    [u8"Стиль"] = "Style",
    [u8"Комбо"] = "Combo",
    [u8"Тренировочная"] = "Training",
    [u8"Язык интерфейса"] = "Interface language",
    [u8"Цвет##gcol"] = "Color##gcol",
    [u8"Белый##gcr"] = "White##gcr",
    [u8"Выбрать##gcapply"] = "Apply##gcapply",
    [u8"Размер##gsize"] = "Size##gsize",
    [u8"Сохранить и обновить экспорт"] = "Save and refresh export",
    [u8"Скопировать настройки в буфер"] = "Copy settings to clipboard",
    [u8"Сбросить отступы этой вкладки"] = "Reset spacing on this tab",
    [u8"Сдвиг всей вкладки"] = "Whole tab X offset",
    [u8"Меняйте интервалы ниже, затем проверьте вкладку. Значения сохраняются в cbuger.ini."] = "Change the gaps below, then check the tab. Values are saved to cbuger.ini.",
}
Data.UI_TRANSLATIONS = {}
for k, v in pairs(Data.UI_TRANSLATIONS_RAW) do
    Data.UI_TRANSLATIONS[Fn.decodeSafe(k)] = v
end
Fn.T = function(s)
    local safe = Fn.decodeSafe(s)
    if ui and ui.interface_lang and ui.interface_lang[0] == 2 then
        local tr = Data.UI_TRANSLATIONS[safe]
        if tr then return tr end

        local visible, hidden = safe:match('^(.-)(##.*)$')
        if visible and hidden then
            local base_tr = Data.UI_TRANSLATIONS[visible]
            if not base_tr then
                local leading, core, trailing = visible:match('^(%s*)(.-)(%s*)$')
                if core and core ~= '' then base_tr = Data.UI_TRANSLATIONS[core] end
                if base_tr then return (leading or '') .. base_tr .. (trailing or '') .. hidden end
            end
            if base_tr then return base_tr .. hidden end
        else
            local leading, core, trailing = safe:match('^(%s*)(.-)(%s*)$')
            if core and core ~= '' and core ~= safe then
                tr = Data.UI_TRANSLATIONS[core]
                if tr then return (leading or '') .. tr .. (trailing or '') end
            end
        end
    end
    return safe
end

do
    local extra_translations = {
        [u8("  вы по нему")] = "  you hit them",
        [u8("  он по вам")] = "  they hit you",
        [u8("%s  |  %d:%02d  |  Счёт: %d  Комбо: %d  Промахи: %d/%d")] = "%s  |  %d:%02d  |  Score: %d  Combo: %d  Misses: %d/%d",
        [u8("(нет файлов в pt_tiles)")] = "(no files in pt_tiles)",
        [u8("--- Цвет FA-иконок ---")] = "--- FA icon colors ---",
        [u8("--- Цвет плиток ---")] = "--- Tile colors ---",
        [u8("... ещё %d — уточните поиск")] = "... and %d more — refine your search",
        [u8("? Текущая сессия")] = "? Current session",
        [u8("FA-иконки вместо плиток")] = "FA icons instead of tiles",
        [u8("FA-иконки недоступны — не найдена библиотека")] = "FA icons unavailable — library not found",
        [u8("Kills")] = "Kills",
        [u8("Авто-переключение")] = "Auto switching",
        [u8("Авто-режим выключен")] = "Auto mode disabled",
        [u8("Авто-ускорение")] = "Auto acceleration",
        [u8("Активация")] = "Activation",
        [u8("Базовый цвет плитки")] = "Base tile color",
        [u8("Без музыки")] = "No music",
        [u8("Включить")] = "Enable",
        [u8("Включить авто-слайдшоу")] = "Enable auto slideshow",
        [u8("Включить дыры от пуль")] = "Enable bullet holes",
        [u8("Включить переливание")] = "Enable color cycling",
        [u8("Включить прицел")] = "Enable crosshair",
        [u8("Воспроизвести")] = "Play",
        [u8("Время")] = "Time",
        [u8("Время (сек)")] = "Time (sec)",
        [u8("Время: ")] = "Time: ",
        [u8("Встреч между этими игроками не зафиксировано")] = "No encounters between these players have been recorded",
        [u8("Всё")] = "All",
        [u8("Выберите станцию")] = "Select a station",
        [u8("Высота над головой")] = "Height above head",
        [u8("Высота подъёма")] = "Rise height",
        [u8("Выстрелов: ")] = "Shots: ",
        [u8("Геймплей")] = "Gameplay",
        [u8("Горячая клавиша")] = "Hotkey",
        [u8("Громкость")] = "Volume",
        [u8("Дал.:")] = "Dist.:",
        [u8("Движение меток")] = "Marker movement",
        [u8("Действие")] = "Action",
        [u8("Длинные плитки")] = "Long tiles",
        [u8("Длительность паузы")] = "Pause duration",
        [u8("Добавить")] = "Add",
        [u8("Добавить этап")] = "Add stage",
        [u8("Дыр:")] = "Bullet holes:",
        [u8("Дыра #")] = "Hole #",
        [u8("Дыра #:")] = "Bullet hole #:",
        [u8("Дыры")] = "Holes",
        [u8("Дыры от пуль")] = "Bullet holes",
        [u8("Его по мне")] = "Their hits on me",
        [u8("Задержка подъёма")] = "Rise delay",
        [u8("Задержка растворения")] = "Fade delay",
        [u8("Зазор")] = "Gap",
        [u8("Закрыть")] = "Close",
        [u8("Заново")] = "Restart",
        [u8("Запустить игру")] = "Start game",
        [u8("Зона")] = "Zone",
        [u8("Игра")] = "Game",
        [u8("Игра остановлена.")] = "Game stopped.",
        [u8("Изображение плитки:")] = "Tile image:",
        [u8("Изображения плиток:")] = "Tile images:",
        [u8("Иконка плиток:")] = "Tile icon:",
        [u8("Иконка:")] = "Icon:",
        [u8("Индивидуальная")] = "Individual",
        [u8("Индивидуальная:")] = "Individual:",
        [u8("Индивидуальные текстуры дыр")] = "Individual bullet-hole textures",
        [u8("Индивидуальные текстуры меток")] = "Individual marker textures",
        [u8("Интенс. подъёма")] = "Rise intensity",
        [u8("Интенс. раств.")] = "Fade intensity",
        [u8("Интервал иконок")] = "Icon interval",
        [u8("Интервал плиток")] = "Tile interval",
        [u8("Интервал появления")] = "Spawn interval",
        [u8("Интервал смены")] = "Change interval",
        [u8("Интервал смены иконки")] = "Icon change interval",
        [u8("Интервал фона")] = "Background interval",
        [u8("Использовать кастомные текстуры дыр")] = "Use custom hole textures",
        [u8("Использовать кастомные текстуры меток")] = "Use custom marker textures",
        [u8("Использует глобальную / стандартную")] = "Using global / default",
        [u8("История")] = "History",
        [u8("Итого:")] = "Total:",
        [u8("КПД: ")] = "Efficiency: ",
        [u8("Каждая новая плитка получает случайное\nизображение из папки moonloader\\CBUGER PRO\\PianoTiles\\pt_tiles")] = "Each new tile gets a random image from the moonloader\\CBUGER PRO\\PianoTiles\\pt_tiles folder",
        [u8("Количество полос")] = "Number of lanes",
        [u8("Команды:")] = "Commands:",
        [u8("Команды: /hm  |  /hitmarker")] = "Commands: /hm  |  /hitmarker",
        [u8("Комбо")] = "Combo",
        [u8("ЛКМ — выбрать изображение для маркеров. ПКМ — добавить/убрать из очереди. Порядок = порядок кликов.")] = "LMB selects a marker image. RMB adds/removes it from the queue. Queue order follows click order.",
        [u8("Личная")] = "Personal",
        [u8("Личная статистика...")] = "Personal statistics...",
        [u8("Личную")] = "Personal",
        [u8("Макс. скорость")] = "Max speed",
        [u8("Максимум промахов")] = "Maximum misses",
        [u8("Масштаб")] = "Scale",
        [u8("Масштаб визуала")] = "Visual scale",
        [u8("Масштаб текста")] = "Text scale",
        [u8("Менять цвет при попадании")] = "Change color on hit",
        [u8("Метка #")] = "Marker #",
        [u8("Метка #:")] = "Marker #:",
        [u8("Метки")] = "Markers",
        [u8("Метки:")] = "Markers:",
        [u8("Мои по нему")] = "My hits on them",
        [u8("Мои попадания по всем игрокам")] = "My hits on all players",
        [u8("Музыка")] = "Music",
        [u8("Нажмите любую клавишу...")] = "Press any key...",
        [u8("Название")] = "Name",
        [u8("Назначить клавишу")] = "Assign key",
        [u8("Настройки")] = "Settings",
        [u8("Настройки цветов")] = "Color settings",
        [u8("Не удалось подключиться к радиостанции. Повторная попытка будет выполнена автоматически.")] = "Could not connect to the radio station. It will retry automatically.",
        [u8("Нет (цвет)")] = "None (color)",
        [u8("Нет активных дыр")] = "No active bullet holes",
        [u8("Нет активных меток")] = "No active markers",
        [u8("Нет записанных сессий. Сыграйте хотя бы одну партию.")] = "No recorded sessions. Play at least one game.",
        [u8("Нет изображений — поместите файлы в:")] = "No images — place files in:",
        [u8("Нет песен — поместите файлы в:")] = "No songs — place files in:",
        [u8("Ник")] = "Nickname",
        [u8("Ник[ID]")] = "Nickname [ID]",
        [u8("Ник[ID] и статистику")] = "Nickname [ID] and stats",
        [u8("Новое сравнение")] = "New comparison",
        [u8("Нужно выстрелов")] = "Required shots",
        [u8("Обводка")] = "Outline",
        [u8("Обн.")] = "Refresh",
        [u8("Обновить")] = "Refresh",
        [u8("Общая")] = "General",
        [u8("Общую")] = "Overall",
        [u8("Обычная плитка")] = "Regular tile",
        [u8("Ожидание первого нажатия для начала игры")] = "Waiting for the first key press to start",
        [u8("Оружие")] = "Weapon",
        [u8("Остановить игру")] = "Stop game",
        [u8("Остановить музыку")] = "Stop music",
        [u8("Открыть")] = "Open",
        [u8("Открыть##cmp")] = "Open##cmp",
        [u8("Отображать трейсеры")] = "Show tracers",
        [u8("Оформление")] = "Appearance",
        [u8("Оформление (Фон и Плитки)")] = "Appearance (Background and Tiles)",
        [u8("Очередь изображений")] = "Image queue",
        [u8("Очередь пуста — добавьте изображения (ПКМ)")] = "Queue is empty — add images (RMB)",
        [u8("Очистить")] = "Clear",
        [u8("Очистить все дыры")] = "Clear all holes",
        [u8("Очистить все метки")] = "Clear all markers",
        [u8("Очистить всё")] = "Clear all",
        [u8("Очистить очередь")] = "Clear queue",
        [u8("Очистить рекорды")] = "Clear records",
        [u8("Ошибка воспроизведения.")] = "Playback error.",
        [u8("Папка pt_tiles пуста. Поместите PNG/JPG в:")] = "The pt_tiles folder is empty. Place PNG/JPG files in:",
        [u8("Параметр")] = "Parameter",
        [u8("Параметры метки")] = "Marker settings",
        [u8("Пауза")] = "Pause",
        [u8("Пауза при перезарядке")] = "Pause on reload",
        [u8("Переливание:")] = "Color cycling:",
        [u8("Переместить")] = "Move",
        [u8("Переместить прицел")] = "Move crosshair",
        [u8("Позиция HUD")] = "HUD position",
        [u8("Позиция текста")] = "Text position",
        [u8("Показывать смерти")] = "Show deaths",
        [u8("Показывать убийства")] = "Show kills",
        [u8("Положите PNG/JPG/BMP в папку:")] = "Put PNG/JPG/BMP files in:",
        [u8("Поп.")] = "Hits",
        [u8("Попаданий")] = "Hits",
        [u8("Попаданий до исчезновения")] = "Hits before disappearing",
        [u8("Попадания всех игроков по мне")] = "All players’ hits on me",
        [u8("Прим шрифт")] = "Apply font",
        [u8("Применить")] = "Apply",
        [u8("Прицел")] = "Crosshair",
        [u8("Прозрачность")] = "Opacity",
        [u8("Прозрачность изобр.")] = "Image opacity",
        [u8("Прозрачность текста")] = "Text opacity",
        [u8("Проигрыш")] = "Game over",
        [u8("Промахи")] = "Misses",
        [u8("Радио")] = "Radio",
        [u8("Радио-режим")] = "Radio mode",
        [u8("Размер")] = "Size",
        [u8("Размер иконки")] = "Icon size",
        [u8("Размер текста")] = "Text size",
        [u8("Ред")] = "Edit",
        [u8("Режим без границ")] = "Borderless mode",
        [u8("Рекордов нет")] = "No records",
        [u8("Рекорды")] = "Records",
        [u8("Рекорды CBug:")] = "CBug records:",
        [u8("Сброс")] = "Reset",
        [u8("Сброс позиции")] = "Reset position",
        [u8("Сброс##cmp")] = "Reset##cmp",
        [u8("Сбросить ВСЁ")] = "Reset ALL",
        [u8("Сбросить зоны")] = "Reset zones",
        [u8("Сбросить к стандартным")] = "Reset to defaults",
        [u8("Сбросить клавишу")] = "Reset hotkey",
        [u8("Сбросить сессию")] = "Reset session",
        [u8("Сбросить статистику")] = "Reset statistics",
        [u8("Скопировать")] = "Copy",
        [u8("Скорость анимации")] = "Animation speed",
        [u8("Скорость движения плиток")] = "Tile movement speed",
        [u8("Скорость роста")] = "Acceleration rate",
        [u8("Скорость смены")] = "Change speed",
        [u8("Скрипт активен")] = "Script active",
        [u8("Скрипт выключен")] = "Script disabled",
        [u8("Скрыть (метки и дыры)")] = "Hide (markers and holes)",
        [u8("Слайдшоу")] = "Slideshow",
        [u8("Следующее изображение")] = "Next image",
        [u8("Случайная смена иконки")] = "Random icon switching",
        [u8("Случайная смена цвета фона")] = "Random background color cycling",
        [u8("Случайные изображения")] = "Random images",
        [u8("Случайный цвет иконок")] = "Random icon color",
        [u8("Случайный цвет плиток")] = "Random tile color",
        [u8("Случайный цвет при попадании")] = "Random hit color",
        [u8("Смещение: X=%d  Y=%d px")] = "Offset: X=%d  Y=%d px",
        [u8("Сначала выберите песню или радиостанцию.")] = "Select a song or radio station first.",
        [u8("Сортировка")] = "Sort",
        [u8("Состояние")] = "Status",
        [u8("Сохранить настройки")] = "Save settings",
        [u8("Сохранить рекорды")] = "Save records",
        [u8("Специально для тех, у кого не сохраняются настройки.")] = "For users whose settings are not being saved.",
        [u8("Список обновляется автоматически.")] = "The list updates automatically.",
        [u8("Сравнение:")] = "Comparison:",
        [u8("Стиль")] = "Style",
        [u8("Стиль HUD:")] = "HUD style:",
        [u8("Стрик на HUD")] = "Show streak on HUD",
        [u8("Счёт")] = "Score",
        [u8("Текст внутри метки")] = "Text inside marker",
        [u8("Текст:")] = "Text:",
        [u8("Текстура для всех дыр:")] = "Texture for all bullet holes:",
        [u8("Текстура для всех меток:")] = "Texture for all markers:",
        [u8("Текстура для дыры #")] = "Texture for bullet hole #",
        [u8("Текстура для метки #")] = "Texture for marker #",
        [u8("Текстура дыр от пуль")] = "Bullet-hole textures",
        [u8("Текстура меток (для всех)")] = "Marker texture (global)",
        [u8("Текстуры")] = "Textures",
        [u8("Текущая:")] = "Current:",
        [u8("Текущее значение:")] = "Current value:",
        [u8("Текущий:")] = "Current:",
        [u8("Тип:")] = "Type:",
        [u8("Толщ. обв.")] = "Outline width",
        [u8("Толщина")] = "Thickness",
        [u8("Точка")] = "Dot",
        [u8("Трейсеры")] = "Tracers",
        [u8("Трек")] = "Track",
        [u8("Трекер активен")] = "Tracker active",
        [u8("Трекер зон активен")] = "Zone tracker active",
        [u8("Треки не выбраны — настройте в разделе Музыка")] = "No tracks selected — configure them in the Music tab",
        [u8("Треки:")] = "Tracks:",
        [u8("Убийца")] = "Killer",
        [u8("Убитый")] = "Victim",
        [u8("Уведомление в чат")] = "Chat notification",
        [u8("Уведомление о рекорде")] = "Record notification",
        [u8("Управление")] = "Controls",
        [u8("Флаг")] = "Flag",
        [u8("Флаг текста")] = "Text flag",
        [u8("Фон сетки:")] = "Grid background:",
        [u8("Фон статистики")] = "Statistics background",
        [u8("Цвет")] = "Color",
        [u8("Цвет HUD")] = "HUD color",
        [u8("Цвет дыры:")] = "Hole color:",
        [u8("Цвет иконки")] = "Icon color",
        [u8("Цвет иконки:")] = "Icon color:",
        [u8("Цвет индикатора:")] = "Indicator color:",
        [u8("Цвет при попадании")] = "Hit color",
        [u8("Цвет прицела")] = "Crosshair color",
        [u8("Цвет слов")] = "Word color",
        [u8("Цвет текста в метке")] = "Marker text color",
        [u8("Цвет фона")] = "Background color",
        [u8("Цвет цифр")] = "Number color",
        [u8("Цвет:")] = "Color:",
        [u8("Цвета")] = "Colors",
        [u8("Цвета меток")] = "Marker colors",
        [u8("Шанс появления длинных")] = "Long tile spawn chance",
        [u8("Шрифт")] = "Font",
        [u8("Шрифт:")] = "Font:",
        [u8("Эл.:")] = "Items:",
        [u8("м")] = "m",
        [u8("прозрачность")] = "Opacity",
        [u8("сек")] = "sec",
    }
    for k, v in pairs(extra_translations) do
        Data.UI_TRANSLATIONS[Fn.decodeSafe(k)] = v
    end
end

Fn.L = function(ru, en)
    if ui and ui.interface_lang and ui.interface_lang[0] == 2 then return en end
    return ru
end
Fn.translateList = function(list)
    local out = {}
    for i, v in ipairs(list) do
        out[i] = Fn.T(v)
    end
    return out
end

do
    local audit_translations = {
        [u8"КПД"] = "Efficiency",
        [u8"Удалить выделенные"] = "Delete selected",
        [u8"Цель-объект"] = "Target object",
        [u8"Хитмаркер"] = "Hitmarker",
        [u8"Шахматная доска"] = "Chess board",
        [u8"Подпись \"by Pryanix\""] = "\"by Pryanix\" signature",
        [u8"Этап "] = "Stage ",
        [u8"Добавить клавишу в этап "] = "Add key to stage ",
        [u8"Не назначена"] = "Unassigned",
        [u8"Голова"] = "Head",
        [u8"Грудь"] = "Chest",
        [u8"Живот"] = "Belly",
        [u8"Л.рука"] = "Left arm",
        [u8"П.рука"] = "Right arm",
        [u8"Л.нога"] = "Left leg",
        [u8"П.нога"] = "Right leg",
        [u8"Зона"] = "Zone",
        [u8"Поп."] = "Hits",
    }
    for k, v in pairs(audit_translations) do
        Data.UI_TRANSLATIONS[Fn.decodeSafe(k)] = v
    end
end


Data.UI_TRANSLATIONS[Fn.decodeSafe(u8"Положите PNG/JPG/BMP в папку:")] = "Place PNG/JPG/BMP files in the folder:"

local CBUGER_IMGUI_TRANSLATION_PATCH = { originals = {}, wrappers = {} }
local function CBUGER_WRAP_IMGUI_TRANSLATION(name, arg_index)
    local original = imgui[name]
    if type(original) ~= 'function' then return end
    local wrapper
    if arg_index == 2 then
        wrapper = function(a, b, ...)
            if type(b) == 'string' then b = Fn.T(b) end
            return original(a, b, ...)
        end
    elseif arg_index == 12 then
        wrapper = function(a, b, ...)
            if type(a) == 'string' then a = Fn.T(a) end
            if type(b) == 'string' then b = Fn.T(b) end
            return original(a, b, ...)
        end
    else
        wrapper = function(a, ...)
            if type(a) == 'string' then a = Fn.T(a) end
            return original(a, ...)
        end
    end
    CBUGER_IMGUI_TRANSLATION_PATCH.originals[name] = original
    CBUGER_IMGUI_TRANSLATION_PATCH.wrappers[name] = wrapper
    imgui[name] = wrapper
end
for _, name in ipairs({
    'Text', 'TextDisabled', 'TextWrapped', 'TextUnformatted', 'BulletText', 'SetTooltip',
    'Button', 'SmallButton', 'InvisibleButton', 'Checkbox', 'RadioButton', 'Selectable',
    'MenuItem', 'BeginMenu', 'CollapsingHeader', 'TreeNode', 'TreeNodeEx', 'Begin', 'BeginChild',
    'BeginPopup', 'BeginPopupModal', 'BeginCombo', 'BeginTabBar', 'BeginTabItem', 'TabItemButton',
    'OpenPopup', 'InputText', 'InputTextMultiline', 'InputInt', 'InputInt2', 'InputInt3', 'InputInt4',
    'InputFloat', 'InputFloat2', 'InputFloat3', 'InputFloat4', 'InputDouble',
    'Combo', 'ListBox', 'ListBoxHeader', 'SliderAngle', 'SliderFloat', 'SliderInt',
    'SliderFloat2', 'SliderFloat3', 'SliderFloat4', 'SliderInt2', 'SliderInt3', 'SliderInt4',
    'DragFloat', 'DragFloat2', 'DragFloat3', 'DragFloat4', 'DragFloatRange2',
    'DragInt', 'DragInt2', 'DragInt3', 'DragInt4', 'DragIntRange2',
    'ColorEdit3', 'ColorEdit4', 'ColorPicker3', 'ColorPicker4'
}) do
    CBUGER_WRAP_IMGUI_TRANSLATION(name, 1)
end
CBUGER_WRAP_IMGUI_TRANSLATION('TextColored', 2)
CBUGER_WRAP_IMGUI_TRANSLATION('LabelText', 12)
CBUGER_WRAP_IMGUI_TRANSLATION('InputTextWithHint', 12)
function CBUGER_RESTORE_IMGUI_TRANSLATION_PATCH()
    for name, wrapper in pairs(CBUGER_IMGUI_TRANSLATION_PATCH.wrappers) do
        if imgui[name] == wrapper then imgui[name] = CBUGER_IMGUI_TRANSLATION_PATCH.originals[name] end
    end
end


ui.border_mode               = Lib.new.int(S.cfg.config.border_mode or 2)
ui.wave_mode                 = Lib.new.int(S.cfg.config.wave_mode)
ui.combo_window_display_mode = Lib.new.int(S.cfg.config.combo_window_display_mode or 1)
ui.logs_limit_row            = Lib.new.int(S.cfg.config.logs_limit_row)
ui.logs_max_display          = Lib.new.int(S.cfg.config.logs_max_display or 20)
ui.logs_style                = Lib.new.int(S.cfg.config.logs_style)
ui.logs_reverse              = Lib.new.bool(S.cfg.config.logs_reverse or false)
ui.logs_combo_rgb            = Lib.new.bool(S.cfg.config.logs_combo_rgb or false)
ui.space_as_shift            = Lib.new.bool(S.cfg.config.space_as_shift or false)
Data.combo_action_btn_width = Lib.new.float(196.0)
Data.combo_action_btn_width[0] = 196.0
S.cfg.config.combo_action_btn_width = 196.0
Data.combo_action_btn_offset = Lib.new.float(-5.0)
Data.combo_action_btn_offset[0] = -5.0
S.cfg.config.combo_action_btn_offset = -5.0
Data.main_master_checkbox_ptrs = {
    ui.keyboard,
    ui.mouse,
    ui.space_as_shift,
    ui.move,
    ui.show_chat_messages,
    ui.show_logs,
    ui.logs_combo_rgb,
    ui.recoil_enabled,
    ui.recoil_show_line,
    ui.shotmap_enabled,
}
Data.main_master_last = ui.script_enabled[0]
function Data.applyScriptMaster(force)
    local state = ui.script_enabled[0] and true or false
    if not force and Data.main_master_last == state then return false end
    for _, ptr in ipairs(Data.main_master_checkbox_ptrs) do
        ptr[0] = state
    end
    Data.main_master_last = state
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
    return true
end
ui.keyboard_type       = Lib.new.int(S.cfg.config.keyboard_type or 0)
if ui.keyboard_type[0] >= 3 then
    ui.keyboard_type[0] = 1
    S.cfg.config.keyboard_type = 1
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
ui.keyboard_scale      = Lib.new.float(S.cfg.config.keyboard_scale)
ui.keyboard_key_alpha  = Lib.new.float(S.cfg.config.keyboard_key_alpha)
ui.text_alpha          = Lib.new.float(S.cfg.config.text_alpha or 1.0)
ui.wave_speed          = Lib.new.float(S.cfg.config.wave_speed)
ui.wave_transparency   = Lib.new.float(S.cfg.config.wave_transparency)
ui.wave_target         = Lib.new.int(S.cfg.config.wave_target or 1)
ui.wave_color_rgb      = Lib.new.bool(S.cfg.config.wave_color_rgb or false)
ui.wave_random_colors  = Lib.new.bool(S.cfg.config.wave_random_colors or false)
ui.combo_window_scale  = Lib.new.float(S.cfg.config.combo_window_scale)
ui.rgb_speed           = Lib.new.float(S.cfg.config.rgb_speed)
Data.border_thickness = Lib.new.float(S.cfg.config.border_thickness)
ui.keyboard_pos = Lib.imgui.ImVec2(S.cfg.pos.x,     S.cfg.pos.y)
Data.force_keyboard_pos_once = (ui.keyboard_type[0] == 0)
ui.mouse_pos    = Lib.imgui.ImVec2(S.cfg.mouse.x,   S.cfg.mouse.y)
ui.space_pos    = Lib.imgui.ImVec2(S.cfg.space.x,   S.cfg.space.y)
ui.combo_pos    = Lib.imgui.ImVec2(S.cfg.combo.x,   S.cfg.combo.y)
ui.combo_size   = Lib.imgui.ImVec2(S.cfg.combo.w,   S.cfg.combo.h)

ui.combo_dragging = false
ui.combo_drag_offset = { x = 0, y = 0 }
ui.logs_pos     = Lib.imgui.ImVec2(S.cfg.logs.x,    S.cfg.logs.y)
ui.logs_size    = Lib.imgui.ImVec2(S.cfg.logs.w or 300, S.cfg.logs.h or 200)
ui.logs_dragging = false
ui.logs_drag_offset = { x = 0, y = 0 }

ui.logs_display_mode = Lib.new.int(S.cfg.config.logs_display_mode or 2)
ui.combo_size_initialized = false
ui.combo_pos_initialized  = false
ui.combo_auto_size_signature = nil
ui.combo_open             = Lib.new.bool(true)
ui._prev_settings_open    = false
ui.held_color       = {S.cfg.config.held_r,      S.cfg.config.held_g,      S.cfg.config.held_b,      S.cfg.config.held_a}
ui.correct_color    = {S.cfg.config.correct_r,   S.cfg.config.correct_g,   S.cfg.config.correct_b,   S.cfg.config.correct_a}
ui.error_color      = {S.cfg.config.error_r,     S.cfg.config.error_g,     S.cfg.config.error_b,     S.cfg.config.error_a}
ui.key_fill_color   = {S.cfg.config.key_fill_r,  S.cfg.config.key_fill_g,  S.cfg.config.key_fill_b,  S.cfg.config.key_fill_a}
ui.key_border_color = {S.cfg.config.key_border_r,S.cfg.config.key_border_g,S.cfg.config.key_border_b,S.cfg.config.key_border_a}
ui.key_text_color   = {S.cfg.config.key_text_r,  S.cfg.config.key_text_g,  S.cfg.config.key_text_b,  S.cfg.config.key_text_a}
 Fn.newFloat4 = function(t)
    local f = Lib.new.float[4]()
    f[0] = t[1]; f[1] = t[2]; f[2] = t[3]; f[3] = t[4]
    return f
end
ui.held_color_if4    = Fn.newFloat4(ui.held_color)
ui.correct_color_if4 = Fn.newFloat4(ui.correct_color)
ui.error_color_if4   = Fn.newFloat4(ui.error_color)
ui.key_fill_if4      = Fn.newFloat4(ui.key_fill_color)
ui.key_border_if4    = Fn.newFloat4(ui.key_border_color)
ui.key_text_if4      = Fn.newFloat4(ui.key_text_color)
ui.pressed_fill_color   = {S.cfg.config.pressed_fill_r,   S.cfg.config.pressed_fill_g,   S.cfg.config.pressed_fill_b,   S.cfg.config.pressed_fill_a}
ui.pressed_border_color = {S.cfg.config.pressed_border_r, S.cfg.config.pressed_border_g, S.cfg.config.pressed_border_b, S.cfg.config.pressed_border_a}
ui.pressed_text_color   = {S.cfg.config.pressed_text_r,   S.cfg.config.pressed_text_g,   S.cfg.config.pressed_text_b,   S.cfg.config.pressed_text_a}
ui.pressed_fill_if4     = Fn.newFloat4(ui.pressed_fill_color)
ui.pressed_border_if4   = Fn.newFloat4(ui.pressed_border_color)
ui.pressed_text_if4     = Fn.newFloat4(ui.pressed_text_color)
ui.pressed_fill_enabled   = Lib.new.bool(S.cfg.config.pressed_fill_enabled)
ui.pressed_border_enabled = Lib.new.bool(S.cfg.config.pressed_border_enabled)
ui.pressed_text_enabled   = Lib.new.bool(S.cfg.config.pressed_text_enabled)
ui.wave_color_if4    = Lib.new.float[4]()
ui.wave_color_if4[0] = S.cfg.config.wave_r
ui.wave_color_if4[1] = S.cfg.config.wave_g
ui.wave_color_if4[2] = S.cfg.config.wave_b
ui.wave_color_if4[3] = S.cfg.config.wave_a
Data.lmb_width    = Lib.new.int(S.cfg.mouse.lmb_width)
Data.lmb_height   = Lib.new.int(S.cfg.mouse.lmb_height)
Data.rmb_width    = Lib.new.int(S.cfg.mouse.rmb_width)
Data.rmb_height   = Lib.new.int(S.cfg.mouse.rmb_height)
Data.mmb_width    = Lib.new.int(S.cfg.mouse.mmb_width or 40)
Data.mmb_height   = Lib.new.int(S.cfg.mouse.mmb_height or 29)
Data.side_width   = Lib.new.int(S.cfg.mouse.side_width or 58)
Data.side_height  = Lib.new.int(S.cfg.mouse.side_height or 20)
Data.key_width    = Lib.new.int(S.cfg.keyboard.key_width)
Data.key_height   = Lib.new.int(S.cfg.keyboard.key_height)
Data.space_width  = Lib.new.int(S.cfg.keyboard.space_width)
Data.space_height = Lib.new.int(S.cfg.keyboard.space_height)
Data.c_pos_x      = Lib.new.float(S.cfg.keyboard.c_x)
Data.c_pos_y      = Lib.new.float(S.cfg.keyboard.c_y)
Data.space_pos_x  = Lib.new.float(S.cfg.keyboard.space_x)
Data.space_pos_y  = Lib.new.float(S.cfg.keyboard.space_y)
Data.mouse_gap      = Lib.new.float(tonumber(S.cfg.config.mouse_gap or 5.0) or 5.0)
Data.mouse_pos_x    = Lib.new.float(tonumber(S.cfg.mouse.x or 162) or 162)
Data.mouse_pos_y    = Lib.new.float(tonumber(S.cfg.mouse.y or 471) or 471)
Data.mouse_force_pos_once = true
ui.space_dragging   = false
ui.space_drag_offset = { x = 0, y = 0 }
Data.editor_add_hold_times = {}
 Fn.getEditorAddHoldTime = function(kname)
    if not Data.editor_add_hold_times[kname] then
       Data.editor_add_hold_times[kname] = Lib.new.float(S.state.DEFAULT_HOLD_TIME)
    end
    return Data.editor_add_hold_times[kname]
end
Data.editor_add_is_hold = {}
 Fn.getEditorAddIsHold = function(kname)
    if not Data.editor_add_is_hold[kname] then
       Data.editor_add_is_hold[kname] = Lib.new.bool(false)
    end
    return Data.editor_add_is_hold[kname]
end
ui.editor = {
    active              = false,
    selected_index      = -1,
    name_buffer         = Lib.new.char[64](""),
    temp_combo          = {},
    is_new              = false,
    drag_part_index     = nil,
    drag_key_index      = nil,
    hover_timer         = 0,
    last_hovered_part   = nil,
    last_hovered_key    = nil,
    drag_offset         = Lib.imgui.ImVec2(0, 0),
    edit_time_popup     = false,
    edit_time_val       = Lib.new.float(0.5),
    edit_time_is_hold   = Lib.new.bool(true),
    edit_time_target_part = -1,
    edit_time_target_key  = -1,
    pending_click_part  = nil,
    pending_click_key   = nil,
    pending_click_frame = 0,
    add_row_dragging    = false,
    add_row_drag_key    = nil,
    add_row_drag_offset = Lib.imgui.ImVec2(0, 0),
    add_row_hover_part  = nil,
    add_row_hover_key   = nil,
    add_row_hover_timer = 0,
    endzone_hovered_part = nil,
    emptystage_hovered_part = nil,
}
ui.selection = {
    active              = false,
    dragging            = false,
    start_pos           = Lib.imgui.ImVec2(0, 0),
    current_pos         = Lib.imgui.ImVec2(0, 0),
    selected_indices    = {},
    preview_indices     = {}
}
ui.dnd = {
    drag_index          = nil,
    hover_timer         = 0,
    last_hovered_index  = nil,
    drag_offset         = Lib.imgui.ImVec2(0, 0)
}
ui.context_menu_target = -1
local keyboards = {
    {
        { {"Q", 0x51}, {"W", 0x57}, {"E", 0x45} },
        { {"A", 0x41}, {"S", 0x53}, {"D", 0x44}, {u8"А", 0x46}, {"C", 0x43} },
        { {" ", 0x20, space = true} }
    }
}
Data.RU_LAYOUT_MAP = {
    ['Q']=u8'Й', ['W']=u8'Ц', ['E']=u8'У', ['R']=u8'К', ['T']=u8'Е', ['Y']=u8'Н', ['U']=u8'Г', ['I']=u8'Ш', ['O']=u8'Щ', ['P']=u8'З',
    ['A']=u8'Ф', ['S']=u8'Ы', ['D']=u8'В', ['F']=u8'А', ['G']=u8'П', ['H']=u8'Р', ['J']=u8'О', ['K']=u8'Л', ['L']=u8'Д',
    ['Z']=u8'Я', ['X']=u8'Ч', ['C']=u8'С', ['V']=u8'М', ['B']=u8'И', ['N']=u8'Т', ['M']=u8'Ь',
    ['[']=u8'Х', [']']=u8'Ъ', [';']=u8'Ж', ["'"]=u8'Э', [',']=u8'Б', ['.']=u8'Ю', ['/']='.', ['`']=u8'Ё',
}
 Fn.getLocalizedName = function(name)
    local safe = Fn.decodeSafe(name)
    if safe == Fn.decodeSafe(u8"ПРОБЕЛ") and Data.space_as_shift_enabled then
        return "SHIFT"
    end
    if ui.language_mode[0] == 2 then
        if safe == Fn.decodeSafe(u8"ЛКМ")    then return "LMB"   end
        if safe == Fn.decodeSafe(u8"ПКМ")    then return "RMB"   end
        if safe == Fn.decodeSafe(u8"СКМ")    then return "MMB"   end
        if safe == Fn.decodeSafe(u8"НАЗАД")  then return "BACK"  end
        if safe == Fn.decodeSafe(u8"ВПЕРЁД") then return "FWD"   end
        if safe == Fn.decodeSafe(u8"ПРОБЕЛ") then return "SPACE"  end
        return safe
    end
    local ru_letter = Data.RU_LAYOUT_MAP[safe]
    if ru_letter then return Fn.decodeSafe(ru_letter) end
    return safe
end
 Fn.normalizeKeyName = function(key)
    if type(key) == 'table' then key = key.name or key[1] end
    if type(key) == 'string' then
        local safe = Fn.decodeSafe(key)



        if safe == Fn.decodeSafe(u8"Й") then return "Q" end
        if safe == Fn.decodeSafe(u8"У") then return "E" end
        if safe == Fn.decodeSafe(u8"Ф") then return "A" end

        return key
    end
    return tostring(key)
end
 Fn.getKeyHoldSettings = function(key)
    if type(key) == 'table' then
        return key.hold or false, key.time or nil
    end
    return false, nil
end

do
    pcall(function()
        ffi.cdef[[ short __stdcall GetAsyncKeyState(int vKey); ]]
    end)
    local ok_user32, user32 = pcall(ffi.load, 'user32.dll')
    Data.key_state_user32 = ok_user32 and user32 or nil
end
Fn.isPhysicalKeyDown = function(code)
    local vk = tonumber(code)
    if not vk then return false end
    local api = Data.key_state_user32
    if api then
        local ok, value = pcall(function() return api.GetAsyncKeyState(vk) end)
        if ok and value ~= nil then

            return (tonumber(value) or 0) < 0
        end
    end

    local ok, down = pcall(isKeyDown, vk)
    return ok and down and true or false
end
 Fn.isKeyDownByName = function(keyName)
    keyName = Fn.normalizeKeyName(keyName)
    local safe = Fn.decodeSafe(keyName)
    if safe == Fn.decodeSafe(u8"ЛКМ")    then return Fn.isPhysicalKeyDown(0x01) end
    if safe == Fn.decodeSafe(u8"ПКМ")    then return Fn.isPhysicalKeyDown(0x02) end
    if safe == Fn.decodeSafe(u8"ПРОБЕЛ") then return Fn.isPhysicalKeyDown(Fn.getSpaceCode()) end
    if keyName == "A" or safe == Fn.decodeSafe(u8"Ф") then return Fn.isPhysicalKeyDown(0x41) end
    if keyName == "W" then return Fn.isPhysicalKeyDown(0x57) end
    if keyName == "C" then return Fn.isPhysicalKeyDown(0x43) end
    if keyName == "D" then return Fn.isPhysicalKeyDown(0x44) end
    if safe == Fn.decodeSafe(u8"А") then return Fn.isPhysicalKeyDown(0x46) end
    if keyName == "Q" then return Fn.isPhysicalKeyDown(0x51) end
    if keyName == "E" then return Fn.isPhysicalKeyDown(0x45) end
    if keyName == "S" then return Fn.isPhysicalKeyDown(0x53) end
    return false
end
 Fn.codeToName = function(code)
    for _, k in ipairs(S.all_monitored_keys) do
        if k.code == code then return k.name end
    end
    return tostring(code)
end
 Fn.nameToCode = function(name)
    name = Fn.normalizeKeyName(name)
    for _, k in ipairs(S.all_monitored_keys) do
        if k.name == name then return k.code end
    end
    local safe = Fn.decodeSafe(name)
    if safe == Fn.decodeSafe(u8"ПРОБЕЛ") then return Fn.getSpaceCode() end
    if safe == Fn.decodeSafe(u8"Ф") then return 0x41 end
    return nil
end

Fn.BuildComboDisplayGroups = function(combo)
    local groups = {}
    if type(combo) ~= 'table' then return groups end

    local function part_signature(part)
        local bits = {}
        for _, key in ipairs(part or {}) do
            local name = Fn.decodeSafe(Fn.normalizeKeyName(key) or '')
            local is_hold, hold_time = Fn.getKeyHoldSettings(key)
            if is_hold then
                hold_time = tonumber(hold_time)
                    or (S.state and S.state.DEFAULT_HOLD_TIME)
                    or 0.5
                bits[#bits + 1] = tostring(#name) .. ':' .. name
                    .. ':H:' .. string.format('%.4f', hold_time)
            else
                bits[#bits + 1] = tostring(#name) .. ':' .. name .. ':T'
            end
        end
        return table.concat(bits, '|')
    end

    for i, part in ipairs(combo) do
        local signature = part_signature(part)
        local group = groups[#groups]
        if group and group.signature == signature then
            group.indices[#group.indices + 1] = i
            group.count = group.count + 1
            group.end_idx = i
        else
            group = {
                part = part,
                start_idx = i,
                end_idx = i,
                count = 1,
                indices = { i },
                signature = signature
            }
            groups[#groups + 1] = group
        end
    end
    return groups
end

Fn.ComboDisplayGroupContains = function(group, part_index)
    if not group then return false end
    if group.indices then
        for _, idx in ipairs(group.indices) do
            if idx == part_index then return true end
        end
        return false
    end
    return part_index >= (group.start_idx or 1) and part_index <= (group.end_idx or group.start_idx or 1)
end

Fn.ComboDisplayGroupRemainingCount = function(group, part_index)
    if not group then return 0 end
    local total = math.max(1, tonumber(group.count) or 1)
    local first = tonumber(group.start_idx) or 1
    local last = tonumber(group.end_idx) or first
    local current = tonumber(part_index)
    if not current or current < first then return total end
    if current > last then return 0 end
    return math.max(1, last - current + 1)
end

 Fn.drawTextWithHoldProgress = function(name, progress, base_col, held_col)
    local display    = Fn.getLocalizedName(name)
    local p          = Lib.imgui.GetCursorScreenPos()
    local draw_list  = Lib.imgui.GetWindowDrawList()

    local draw_font  = Lib.imgui.GetFont()
    local draw_fsz   = Lib.imgui.GetFontSize()
    local text_size  = draw_font:CalcTextSizeA(draw_fsz, 1000, 0, display)
    local base_alpha = (base_col[4] or 1) * ui.text_alpha[0]
    local held_alpha = (held_col[4] or 1) * ui.text_alpha[0]
    draw_list:AddTextFontPtr(draw_font, draw_fsz, p,
        Fn.getColorU32Global(base_col[1], base_col[2], base_col[3], base_alpha, true), display)
    if progress and progress > 0 then
        local clip_x = p.x + text_size.x * math.max(0, math.min(1, progress))
        draw_list:PushClipRect(Lib.imgui.ImVec2(p.x, p.y), Lib.imgui.ImVec2(clip_x, p.y + text_size.y), true)
        draw_list:AddTextFontPtr(draw_font, draw_fsz, p,
            Fn.getColorU32Global(held_col[1], held_col[2], held_col[3], held_alpha, true), display)
        draw_list:PopClipRect()
    end
   Lib.imgui.Dummy(Lib.imgui.ImVec2(text_size.x, text_size.y))
end
 Fn.getCurrentPart = function()
    local st = S.state
    if not st.current_combo then return nil end
    return st.current_combo[st.current_part_index]
end
 Fn.prepareCurrentPart = function()
    local st = S.state
    if not st.current_combo then return end
    local part = Fn.getCurrentPart()
    if not part then return end
    st.key_logs           = {}
    st.key_states         = {}
    st.key_required_hold  = {}
    st.hold_start_times   = {}
    st.hold_durations     = {}
    st.hold_max_times     = {}
    st.ryvok_swapped      = false
    st.last_pressed_key_name = nil
    st.correct_press_count = {}
    st.key_needs_release   = {}
    for i = 1, #part do
        local k           = part[i]
        st.key_logs[i]    = Fn.normalizeKeyName(k)
        st.key_states[i]  = nil
        local isHold, holdTime = Fn.getKeyHoldSettings(k)
        if isHold then
            st.key_required_hold[i] = true
            st.hold_durations[i]    = holdTime or st.DEFAULT_HOLD_TIME
            st.hold_max_times[i]    = (holdTime or st.DEFAULT_HOLD_TIME) + 0.2
        else
            st.key_required_hold[i] = false
        end
        st.hold_start_times[i] = nil
    end
end
 Fn.resetComboFull = function()
    local st = S.state
    st.current_combo      = nil
    st.current_combo_name  = nil
    st.current_combo_index = nil
    st.combo_started      = false
    st.key_logs           = {}
    st.key_states         = {}
    st.current_key_index  = 1
    st.current_part_index = 1
    st.key_required_hold  = {}
    st.hold_start_times   = {}
    st.hold_max_times     = {}
    st.error_state        = { is_error = false, error_time = 0 }
    st.wrong_key          = nil
    st.wrong_slot         = nil
    st.wrong_part_index   = nil
    st.combo_mini_error   = nil
    st.held_keys          = {}
    st.hold_triggered     = {}
    st.blocked_held       = {}
    st.combo_completed    = false
    st.combo_display_completed = false
    st.completed_wait_keys = {}
    st.completed_at_frame = nil
    st.last_combo_activity = 0
    st.ryvok_swapped      = false
    st.last_pressed_key_name = nil
    st.correct_press_count = {}
    st.key_needs_release   = {}
    st.tap_keys_last_part  = {}; st.tap_keys_released = {}
    st.pending_next_part_key = nil
    st.error_recovery_at   = nil
end
 Fn.restartCombo = function()
    if S.state.current_combo_name and S.state.current_combo then
        local st = S.state
                        st.combo_transition_frame = st.runtime_frame
        st.current_part_index = 1
        st.current_key_index  = 1
        st.combo_started      = false
        st.error_state        = { is_error = false, error_time = 0 }
        st.wrong_key          = nil
        st.wrong_slot         = nil
        st.wrong_part_index   = nil
        st.combo_mini_error   = nil
        st.hold_triggered     = {}
        st.blocked_held       = {}
        st.combo_completed    = false
        st.completed_wait_keys = {}
        st.completed_at_frame = nil
        st.last_combo_activity = 0
        st.key_needs_release   = {}
        st.active_bridge_code  = nil
        for _, info in ipairs(S.all_monitored_keys) do
            if not Fn.isPhysicalKeyDown(info.code) then
                st.held_keys[info.code]      = nil
                st.hold_triggered[info.code] = nil
                st.blocked_held[info.code]   = nil
            else
                st.hold_triggered[info.code] = true
                st.blocked_held[info.code]   = true
                st.held_keys[info.code]      = nil
            end
        end
        st.tap_keys_last_part  = {}; st.tap_keys_released = {}
        st.pending_next_part_key = nil
       Fn.prepareCurrentPart()
    end
end
 Fn.selectCombo = function(comboData, name, combo_index)
    local st = S.state
    st.current_combo       = comboData
    st.current_combo_name  = name
    st.current_combo_index = combo_index
    st.combo_transition_frame = st.runtime_frame
    st.current_part_index = 1
    st.current_key_index  = 1
    st.combo_started      = false
    st.error_state        = { is_error = false, error_time = 0 }
    st.wrong_key          = nil
    st.wrong_slot         = nil
    st.wrong_part_index   = nil
    st.combo_mini_error   = nil
    st.hold_triggered     = {}
    st.held_keys          = {}
    st.blocked_held       = {}
    st.combo_completed    = false
    st.combo_display_completed = false
    st.completed_wait_keys = {}
    st.completed_at_frame = nil
    st.last_combo_activity = 0
    st.key_needs_release   = {}
    st.pending_next_part_key = nil
    st.active_bridge_code  = nil
    for _, info in ipairs(S.all_monitored_keys) do
        if Fn.isPhysicalKeyDown(info.code) then
            st.hold_triggered[info.code] = true
            st.blocked_held[info.code]   = true
            st.held_keys[info.code]      = nil
        end
    end
    ui.combo_size_initialized = false

    ui.combo_auto_size_signature = nil
    ui.show_combo_window[0] = true
    ui.combo_open[0] = true
    st.combo_streak = 0
   Fn.prepareCurrentPart()
    if ui.show_chat_messages[0] then
        sampAddChatMessage(
           Fn.L(Fn.cp(u8'[CBUGER]: Комбинация: "'), '[CBUGER]: Combo: "') .. Fn.cp(name) ..
           Fn.L(Fn.cp(u8'". Нажмите первую клавишу для старта.'), '". Press the first key to start.'),
            0x00FF00
        )
    end
end
 Fn.setError = function(msgKey, chatMsg, slot)
    local st = S.state
    if st.error_state.is_error then return end
    if slot == nil then
        local part = Fn.getCurrentPart()
        if part then
            local target = Fn.decodeSafe(msgKey)
            local last_done = math.min((tonumber(st.current_key_index) or 1) - 1, #part)
            for i = last_done, 1, -1 do
                if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == target then slot = i; break end
            end
            if slot == nil then
                for i = math.max(1, tonumber(st.current_key_index) or 1), #part do
                    if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == target then slot = i; break end
                end
            end
        end
    end
    st.combo_streak = 0
    st.error_state.is_error = true
    st.error_state.error_time = os.clock()
    st.wrong_key             = msgKey
    st.wrong_slot            = slot
    st.wrong_part_index      = st.current_part_index
    st.combo_mini_error      = {
        key = msgKey,
        slot = slot,
        part_index = st.current_part_index,
        time = os.clock(),
    }
    local code = Fn.nameToCode(msgKey)
    if code then
        st.blocked_held[code] = true
        st.held_keys[code] = nil
        st.hold_triggered[code] = true
    end
    if ui.show_chat_messages[0] then
        sampAddChatMessage(chatMsg and Fn.cp(chatMsg) or Fn.L(Fn.cp(u8'[CBUGER]: Ошибка'), '[CBUGER]: Error'), 0xFF0000)
    end
    st.error_recovery_at = os.clock() + 0.7
end
 Fn.findKeyIndicesInCurrentPart = function(name)
    local st  = S.state
    local res = {}
    if not st.current_combo then return res end
    local part = Fn.getCurrentPart()
    if not part then return res end
    local safe = Fn.decodeSafe(name)
    for i = 1, #part do
        local kn = Fn.normalizeKeyName(part[i])
        if Fn.decodeSafe(kn) == safe then
            table.insert(res, i)
        end
    end
    return res
end
 Fn.chooseBestIndexForKey = function(indices)
    if not indices or #indices == 0 then return nil end
    local st = S.state
    for _, idx in ipairs(indices) do
        if idx == st.current_key_index then return idx end
    end
    for _, idx in ipairs(indices) do
        if st.key_states[idx] ~= nil then return idx end
    end
    return indices[1]
end
 Fn.markKeyCorrect = function(idx)
    local st = S.state
    if not st.current_combo then return 'correct' end
    st.last_combo_activity = os.clock()
    local log_type = 'correct'
    if st.key_required_hold[idx] then
        st.key_states[idx]        = S.KEY_COLORS.HELD
        st.hold_start_times[idx]  = os.clock()
        st.current_key_index      = st.current_key_index + 1
        log_type = 'held'
    else
        st.key_states[idx]   = 0x00FF00
        st.current_key_index = st.current_key_index + 1
    end
    local part = Fn.getCurrentPart()
    if part and part[idx] then
        local kname = Fn.normalizeKeyName(part[idx])
        st.last_pressed_key_name = kname
        st.last_correct_flash_key       = kname
        st.last_correct_flash_time      = os.clock()
        st.last_correct_flash_part_idx  = st.current_part_index
        st.last_correct_flash_key_idx   = idx
        if st.current_key_index <= #part then
            local nextKey = Fn.normalizeKeyName(part[st.current_key_index])
            if Fn.decodeSafe(nextKey) == Fn.decodeSafe(kname) then
                st.key_needs_release[Fn.decodeSafe(kname)] = true
            end
        end
    end
    return log_type
end



 Fn.isComboEffectivelyDone = function()
    local st = S.state
    if not st.current_combo or not st.combo_started or st.combo_completed then return false end
    if st.error_state and st.error_state.is_error then return false end
    if st.current_part_index < #st.current_combo then return false end
    local part = Fn.getCurrentPart()
    return part ~= nil and (tonumber(st.current_key_index) or 1) > #part
end
 Fn.checkHoldProgress = function()
    if Data.samp_chat_is_open then return end
    local st = S.state
    if not st.current_combo or st.combo_completed then return end
    local part = Fn.getCurrentPart()
    if not part then return end
    if st.current_key_index > #part then
        local now = os.clock()
                                for i = 1, #part do
            if st.key_required_hold[i] and st.key_states[i] == S.KEY_COLORS.HELD then
                local hold_name = Fn.normalizeKeyName(part[i])
                local hold_started = tonumber(st.hold_start_times[i])
                local max_hold = tonumber(st.hold_max_times[i]) or 999
                if hold_started and (now - hold_started) > max_hold and not st.error_state.is_error then
                    st.key_states[i] = 0xFF0000
                    Fn.setError(hold_name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали слишком долго: ") .. Fn.getLocalizedName(hold_name), i)
                    Fn.pushLog(hold_name, 'error')
                    return
                end
                if Fn.isKeyDownByName(hold_name) then
                    return
                end
                                st.key_states[i] = 0x00FF00
                st.key_needs_release[Fn.decodeSafe(hold_name)] = nil
            end
        end
        for i = 1, #part do
            if not st.key_required_hold[i] then
                local kname = Fn.normalizeKeyName(part[i])
                local code  = Fn.nameToCode(kname)
                if code and Fn.isPhysicalKeyDown(code) and not st.blocked_held[code] then
                    local held_since = st.held_keys[code]
                    if held_since and (now - held_since) >= st.NON_HOLD_ERROR_TIME then
                        st.hold_triggered[code] = true
                        st.blocked_held[code]   = true
                        st.held_keys[code]      = nil
                       Fn.setError(kname, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(kname), i)
                        return
                    end
                end
            end
        end
        st.tap_keys_last_part = {}; st.tap_keys_released = {}
        for i = 1, #part do
            if not st.key_required_hold[i] then
                local normalized_name = Fn.normalizeKeyName(part[i])
                local kn = Fn.decodeSafe(normalized_name)
                st.tap_keys_last_part[kn] = true
                                                                if not Fn.isKeyDownByName(normalized_name) then
                    st.tap_keys_released[kn] = true
                end
            end
        end
        if st.current_part_index < #st.current_combo then
            local pending_next_key = st.pending_next_part_key
            st.pending_next_part_key = nil
            st.current_part_index  = st.current_part_index + 1
            st.combo_transition_frame = st.runtime_frame
           Fn.prepareCurrentPart()
            st.current_key_index   = 1
            st.combo_started       = false
            st.last_combo_activity = 0

            if pending_next_key then
                local next_part = Fn.getCurrentPart()
                local first_key = next_part and next_part[1] or nil
                local first_name = first_key and Fn.normalizeKeyName(first_key) or nil
                if first_name and Fn.decodeSafe(first_name) == Fn.decodeSafe(pending_next_key.name) then
                    local first_is_hold = Fn.getKeyHoldSettings(first_key)
                    if not first_is_hold or Fn.isKeyDownByName(first_name) then
                        local pending_name = Fn.decodeSafe(first_name)
                        st.tap_keys_last_part[pending_name] = nil
                        st.tap_keys_released[pending_name] = true



                        local pending_code = Fn.nameToCode(first_name)
                        if pending_code then S.prev_key_states[pending_code] = true end
                        Fn.addComboLog(first_name)
                        if first_is_hold and st.key_states[1] == S.KEY_COLORS.HELD then
                            st.hold_start_times[1] = pending_next_key.time or st.hold_start_times[1]
                        end
                    end
                end
            end
        else
            st.combo_streak = (st.combo_streak or 0) + 1
            if ui.show_chat_messages[0] then
                local streak_msg = "{00FF00}[CBUGER]: " .. Fn.L(Fn.cp(u8"Комбинация выполнена правильно!"), "Combo performed correctly!")
                if st.combo_streak > 1 then
                    streak_msg = streak_msg .. " {FF8800}x" .. tostring(st.combo_streak)
                end
                sampAddChatMessage(streak_msg, 0xFFFFFF)
            end
            st.combo_completed = true
            st.combo_display_completed = true
            st.completed_wait_keys = {}
            st.completed_at_frame = st.runtime_frame
            st.pending_next_part_key = nil
            st.last_combo_activity = 0

            for _, completed_part in ipairs(st.current_combo or {}) do
                for _, completed_key in ipairs(completed_part) do
                    local completed_name = Fn.normalizeKeyName(completed_key)
                    local completed_code = Fn.nameToCode(completed_name)
                    if completed_code and Fn.isPhysicalKeyDown(completed_code) then
                        st.completed_wait_keys[completed_code] = true
                    end
                end
            end
        end
        return
    end
    for i = 1, #part do
        if st.key_required_hold[i] and st.key_states[i] == S.KEY_COLORS.HELD then
            local name = Fn.normalizeKeyName(part[i])
            if not Fn.isKeyDownByName(name) then
                local nextIsSame = false
                if i + 1 <= #part then
                    local nextName = Fn.normalizeKeyName(part[i + 1])
                    if Fn.decodeSafe(nextName) == Fn.decodeSafe(name) then
                        nextIsSame = true
                    end
                end
                if not nextIsSame then
                    local hold_count = 0
                    for j = 1, #part do
                        local pn = Fn.decodeSafe(Fn.normalizeKeyName(part[j]))
                        local isHoldJ = Fn.getKeyHoldSettings(part[j])
                        if pn == Fn.decodeSafe(name) and isHoldJ then
                            hold_count = hold_count + 1
                            if hold_count >= 2 then
                                nextIsSame = true
                                break
                            end
                        end
                    end
                end
                local wasHeld = (st.hold_start_times[i] ~= nil)
                if nextIsSame and wasHeld then
                    st.key_states[i] = 0x00FF00
                    st.key_needs_release[name] = nil
                    st.last_combo_activity = os.clock()
                   Fn.pushLog(name, 'held')
                else
                    if not st.error_state.is_error then
                        st.key_states[i] = 0xFF0000
                       Fn.setError(name, Fn.T(u8"[CBUGER]: Ошибка, вы не зажимали: ") .. Fn.getLocalizedName(name), i)
                       Fn.pushLog(name, 'error')
                    end
                    return
                end
            end
            if st.hold_start_times[i] then
                local elapsed = os.clock() - st.hold_start_times[i]
                local maxTime = st.hold_max_times[i] or 999
                if elapsed > maxTime and not st.error_state.is_error then
                    st.key_states[i] = 0xFF0000
                   Fn.setError(name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали слишком долго: ") .. Fn.getLocalizedName(name), i)
                   Fn.pushLog(name, 'error')
                    return
                end
            end
        end
    end
end
Fn.pushLog = function(key_name, log_type)
    table.insert(S.log_buffer, 1, {
        name = key_name,
        time = os.clock(),
        type = log_type or 'normal',
        display = Fn.getLocalizedName(key_name)
    })
    if #S.log_buffer > S.MAX_LOGS then table.remove(S.log_buffer) end
end
 Fn.countKeyInPart = function(part, keyName)
    local count = 0
    local safe = Fn.decodeSafe(keyName)
    for _, k in ipairs(part) do
        if Fn.decodeSafe(Fn.normalizeKeyName(k)) == safe then count = count + 1 end
    end
    return count
end
 Fn.countCorrectPressesForKey = function(part, keyName)
    local count = 0
    local safe = Fn.decodeSafe(keyName)
    for i, k in ipairs(part) do
        if Fn.decodeSafe(Fn.normalizeKeyName(k)) == safe and S.state.key_states[i] ~= nil then
            count = count + 1
        end
    end
    return count
end
 Fn.addComboLog = function(key_name)
    if ui.guide_open and ui.guide_open[0] then return end
    if Data.samp_chat_is_open then return end
    local st = S.state
    if st.combo_completed then return end
    if st.runtime_frame ~= nil and st.combo_transition_frame == st.runtime_frame then
        local transition_part = st.current_combo and Fn.getCurrentPart() or nil
        local transition_first = transition_part and transition_part[1] and Fn.normalizeKeyName(transition_part[1]) or nil
        local is_expected_first = transition_first and not st.combo_started
            and Fn.decodeSafe(key_name) == Fn.decodeSafe(transition_first)
        if not is_expected_first then
            Fn.pushLog(key_name, 'normal')
            return
        end
    end
    if st.error_state.is_error then Fn.pushLog(key_name, 'normal'); return end
    if Fn.isComboEffectivelyDone() then
        Fn.pushLog(key_name, 'normal')
        Fn.checkHoldProgress()
        return
    end
    if st.key_needs_release[Fn.decodeSafe(key_name)] then
        if not st.error_state.is_error then
           Fn.setError(key_name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(key_name))
           Fn.pushLog(key_name, 'error')
        else
           Fn.pushLog(key_name, 'normal')
        end
        return
    end
    if st.current_combo and not st.combo_started then
        local part = Fn.getCurrentPart()
        if not part then Fn.pushLog(key_name, 'normal'); return end
        local firstName = Fn.normalizeKeyName(part[1])
        if Fn.decodeSafe(key_name) == Fn.decodeSafe(firstName) then
            local kn = Fn.decodeSafe(key_name)
            if st.tap_keys_last_part[kn] and not st.tap_keys_released[kn] then
               Fn.pushLog(key_name, 'normal')
                return
            end
            local firstIsHold, _ = Fn.getKeyHoldSettings(part[1])
            st.combo_started       = true
            st.combo_display_completed = false
            st.last_combo_activity = os.clock()
            st.tap_keys_last_part  = {}; st.tap_keys_released = {}
            if firstIsHold then
                st.key_states[1]       = S.KEY_COLORS.HELD
                st.hold_start_times[1] = os.clock()
                st.current_key_index   = 2
                if #part >= 2 then
                    local nextKey = Fn.normalizeKeyName(part[2])
                    if Fn.decodeSafe(nextKey) == Fn.decodeSafe(firstName) then
                        st.key_needs_release[Fn.decodeSafe(firstName)] = true
                    end
                end
               Fn.pushLog(key_name, 'held')
            else
                local lt = Fn.markKeyCorrect(1)
               Fn.pushLog(key_name, lt)
            end
        else
            local kn = Fn.decodeSafe(key_name)
            if st.tap_keys_last_part[kn] and not st.tap_keys_released[kn] and not st.error_state.is_error then
               Fn.setError(key_name, Fn.T(u8"[CBUGER]: Ошибка, лишнее нажатие: ") .. Fn.getLocalizedName(key_name))
               Fn.pushLog(key_name, 'error')
            else
               Fn.pushLog(key_name, 'normal')
            end
        end
        return
    end
    if st.current_combo and st.combo_started then
        local part = Fn.getCurrentPart()
        if not part then Fn.pushLog(key_name, 'normal'); return end
        local skip_advanced_same_key = false
        local first_iter = true
        while st.current_key_index <= #part do
            local expected     = part[st.current_key_index]
            local expectedName = Fn.normalizeKeyName(expected)
            local isHold       = Fn.getKeyHoldSettings(expected)
            if first_iter and Fn.decodeSafe(expectedName) ~= Fn.decodeSafe(key_name) then
                break
            end
            first_iter = false
            if isHold and Fn.isKeyDownByName(expectedName) then
                if st.key_states[st.current_key_index] ~= S.KEY_COLORS.HELD then
                    st.key_states[st.current_key_index]       = S.KEY_COLORS.HELD
                    st.hold_start_times[st.current_key_index] = os.clock()
                    st.last_combo_activity = os.clock()
                end
                if Fn.decodeSafe(expectedName) == Fn.decodeSafe(key_name) then
                    skip_advanced_same_key = true
                end
                st.current_key_index = st.current_key_index + 1
                if skip_advanced_same_key then break end
            else break end
        end
        if skip_advanced_same_key then
           Fn.pushLog(key_name, 'held')
           Fn.checkHoldProgress()
            return
        end
        if st.current_key_index > #part then
            local part_index_before = st.current_part_index
            local next_part = st.current_combo[st.current_part_index + 1]
            local next_first = next_part and next_part[1] and Fn.normalizeKeyName(next_part[1]) or nil
            if next_first and Fn.decodeSafe(key_name) == Fn.decodeSafe(next_first) then

                st.pending_next_part_key = { name = key_name, time = os.clock() }
                Fn.checkHoldProgress()
                if st.current_part_index ~= part_index_before then
                    return
                end
                Fn.pushLog(key_name, 'normal')
                return
            end
            local total_in_part   = Fn.countKeyInPart(part, key_name)
            local already_pressed = Fn.countCorrectPressesForKey(part, key_name)
            if total_in_part > 0 and already_pressed >= total_in_part then
                local is_held_correctly = false
                for i = 1, #part do
                    if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(key_name)
                       and st.key_states[i] == S.KEY_COLORS.HELD then
                        is_held_correctly = true; break
                    end
                end
                if not is_held_correctly and not st.error_state.is_error then
                    st.key_states[#part] = 0xFF0000
                   Fn.setError(key_name, Fn.T(u8"[CBUGER]: Ошибка, лишнее нажатие: ") .. Fn.getLocalizedName(key_name))
                   Fn.pushLog(key_name, 'error')
                    return
                end
            end
           Fn.checkHoldProgress()
           Fn.pushLog(key_name, 'normal')
            return
        end
        local expected     = part[st.current_key_index]
        local expectedName = Fn.normalizeKeyName(expected)
        local expectedIsHold = Fn.getKeyHoldSettings(expected)

        local is_ryvok_followup = st.ryvok_swapped and not expectedIsHold and
            ((expectedName == "E" and key_name == "Q") or
             (expectedName == "Q" and key_name == "E"))
        if is_ryvok_followup then
            local lt = Fn.markKeyCorrect(st.current_key_index)
            st.ryvok_swapped = false
            Fn.checkHoldProgress()
            Fn.pushLog(key_name, lt)
            return
        end

        if expectedIsHold and Fn.decodeSafe(key_name) == Fn.decodeSafe(expectedName) then
           Fn.pushLog(key_name, 'held')
            return
        end
        local total_in_part = Fn.countKeyInPart(part, key_name)
        local already_pressed = Fn.countCorrectPressesForKey(part, key_name)
        if already_pressed >= total_in_part and total_in_part > 0 then
            local is_currently_held_correctly = false
            for i = 1, #part do
                if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(key_name) and st.key_states[i] == S.KEY_COLORS.HELD then
                    is_currently_held_correctly = true; break
                end
            end
            if is_currently_held_correctly then
               Fn.pushLog(key_name, 'normal')
                return
            end
            if not st.error_state.is_error then
                local excess_slot = nil
                for i = st.current_key_index - 1, 1, -1 do
                    if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(key_name)
                       and st.key_states[i] ~= nil then
                        excess_slot = i; break
                    end
                end
                if excess_slot then st.key_states[excess_slot] = 0xFF0000 end
               Fn.setError(key_name, Fn.T(u8"[CBUGER]: Ошибка, лишнее нажатие: ") .. Fn.getLocalizedName(key_name), excess_slot)
               Fn.pushLog(key_name, 'error')
            end
            return
        end
        if Fn.decodeSafe(key_name) == Fn.decodeSafe(expectedName) then
            local lt = Fn.markKeyCorrect(st.current_key_index)
           Fn.checkHoldProgress()
           Fn.pushLog(key_name, lt)
        else
            local is_prev_correct = false
            for i = 1, math.max(1, st.current_key_index - 1) do
                if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(key_name) and st.key_states[i] ~= nil then
                    is_prev_correct = true
                    break
                end
            end
            if is_prev_correct then
                local excess_slot = nil
                for i = st.current_key_index - 1, 1, -1 do
                    if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(key_name) and st.key_states[i] ~= nil then
                        excess_slot = i; break
                    end
                end
                if not st.error_state.is_error then
                    if excess_slot then st.key_states[excess_slot] = 0xFF0000 end
                   Fn.setError(key_name, Fn.T(u8"[CBUGER]: Ошибка, нажата не та клавиша: ") .. Fn.getLocalizedName(key_name), excess_slot)
                   Fn.pushLog(key_name, 'error')
                end
                return
            end
            local allowSwap = false
            if st.current_key_index < #part then
                local nextExpected = Fn.normalizeKeyName(part[st.current_key_index + 1])
                if (expectedName == "Q" and nextExpected == "E") or
                   (expectedName == "E" and nextExpected == "Q") then
                    if not st.ryvok_swapped and Fn.decodeSafe(key_name) == nextExpected then
                        allowSwap = true
                        st.ryvok_swapped = true
                    end
                end
            end
            if allowSwap then
                local lt = Fn.markKeyCorrect(st.current_key_index)
               Fn.checkHoldProgress()
               Fn.pushLog(key_name, lt)
            else
                for i = 1, st.current_key_index - 1 do
                    if st.key_required_hold[i] and st.key_states[i] ~= S.KEY_COLORS.HELD then
                        st.key_states[i] = 0xFF0000
                       Fn.setError(
                           Fn.normalizeKeyName(part[i]),
                            Fn.T(u8"[CBUGER]: Ошибка, вы не зажимали: ") .. Fn.getLocalizedName(Fn.normalizeKeyName(part[i])),
                            i
                        )
                       Fn.pushLog(key_name, 'error')
                        return
                    end
                end
                st.key_states[st.current_key_index] = 0xFF0000
               Fn.setError(
                    expectedName,
                    Fn.T(u8"[CBUGER]: Ожидалась: ") .. Fn.getLocalizedName(expectedName) ..
                    Fn.T(u8", но нажата: ") .. Fn.getLocalizedName(key_name),
                    st.current_key_index
                )
               Fn.pushLog(key_name, 'error')
            end
        end
    else
       Fn.pushLog(key_name, 'normal')
    end
end
 Fn.processHeldErrors = function()
    if Data.samp_chat_is_open then return end
    local st  = S.state
    if not st.current_combo or st.combo_completed then return end
    if Fn.isComboEffectivelyDone() then return end
    local now = os.clock()
    if st.combo_started and not st.error_state.is_error then
        for kname_safe, _ in pairs(st.key_needs_release) do
            local code2 = nil
            for _, info2 in ipairs(S.all_monitored_keys) do
                if Fn.decodeSafe(info2.name) == kname_safe then code2 = info2.code; break end
            end
            if code2 and Fn.isPhysicalKeyDown(code2) and not st.blocked_held[code2] then
                local held_since2 = st.held_keys[code2]
                if held_since2 and (now - held_since2) >= st.NON_HOLD_ERROR_TIME then
                    st.hold_triggered[code2] = true
                    st.blocked_held[code2]   = true
                    st.held_keys[code2]      = nil
                    st.key_needs_release[kname_safe] = nil
                    local err_slot = nil
                    local part0 = Fn.getCurrentPart()
                    if part0 then
                        for i = st.current_key_index - 1, 1, -1 do
                            if Fn.decodeSafe(Fn.normalizeKeyName(part0[i])) == kname_safe
                               and not st.key_required_hold[i]
                               and st.key_states[i] ~= nil then
                                err_slot = i; break
                            end
                        end
                    end
                    if err_slot then st.key_states[err_slot] = 0xFF0000 end
                   Fn.setError(kname_safe, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(kname_safe), err_slot)
                    return
                end
            end
        end
    end
    if st.active_bridge_code and not Fn.isPhysicalKeyDown(st.active_bridge_code) then
        st.active_bridge_code = nil
    end
    for _, info in ipairs(S.all_monitored_keys) do
        local code = info.code
        local name = info.name
        if st.active_bridge_code == code then
            local part2 = Fn.getCurrentPart()
            local still_bridge = false
            if part2 then
                for i = 1, #part2 do
                    if Fn.decodeSafe(Fn.normalizeKeyName(part2[i])) == Fn.decodeSafe(name)
                       and st.key_states[i] ~= nil
                       and i + 1 <= #part2 then
                        local nextName2  = Fn.normalizeKeyName(part2[i + 1])
                        local nextHold2  = Fn.getKeyHoldSettings(part2[i + 1])
                        if Fn.decodeSafe(nextName2) == Fn.decodeSafe(name)
                           and nextHold2
                           and st.key_states[i + 1] == nil
                           and (i + 1 == st.current_key_index) then
                            still_bridge = true
                            break
                        end
                    end
                end
            end
            if still_bridge then
                goto continue_held_loop
            else
                st.active_bridge_code = nil
            end
        end
        if st.held_keys[code] then
            local dt = now - st.held_keys[code]
            if dt >= st.NON_HOLD_ERROR_TIME and not st.hold_triggered[code] then
                if not st.combo_started then
                    local kn = Fn.decodeSafe(name)
                    if st.tap_keys_last_part[kn] and not st.tap_keys_released[kn] then
                        st.hold_triggered[code] = true
                        st.blocked_held[code]   = true
                        st.held_keys[code]      = nil
                       Fn.setError(name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(name), nil)
                        return
                    end
                    if st.current_combo and st.current_part_index > 1 then
                        local part = Fn.getCurrentPart()
                        if part then
                            for i = 2, #part do
                                local pname = Fn.decodeSafe(Fn.normalizeKeyName(part[i]))
                                local pIsHold = Fn.getKeyHoldSettings(part[i])
                                if pname == kn and not pIsHold then
                                    st.hold_triggered[code] = true
                                    st.blocked_held[code]   = true
                                    st.held_keys[code]      = nil
                                   Fn.setError(name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(name), i)
                                    return
                                end
                            end
                        end
                    end
                else
                    local part = Fn.getCurrentPart()
                    local idx = nil
                    local bridge_slot = nil
                    if part then
                        for i = 1, #part do
                            if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(name)
                               and st.key_states[i] ~= nil then
                                if i + 1 <= #part then
                                    local nextName    = Fn.normalizeKeyName(part[i + 1])
                                    local nextIsHold  = Fn.getKeyHoldSettings(part[i + 1])
                                    if Fn.decodeSafe(nextName) == Fn.decodeSafe(name)
                                       and nextIsHold
                                       and st.key_states[i + 1] == nil then
                                        bridge_slot = i
                                        break
                                    end
                                end
                            end
                        end
                        if bridge_slot and (bridge_slot + 1 == st.current_key_index) then
                            st.active_bridge_code = code
                        else
                            if st.current_key_index <= #part then
                                local curExpected = Fn.normalizeKeyName(part[st.current_key_index])
                                local curIsHold   = Fn.getKeyHoldSettings(part[st.current_key_index])
                                if Fn.decodeSafe(curExpected) == Fn.decodeSafe(name) and curIsHold then
                                    goto continue_held_loop
                                end
                            end
                            do
                                local is_correctly_held = false
                                if part then
                                    for i = 1, #part do
                                        if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(name)
                                           and st.key_required_hold[i]
                                           and st.key_states[i] == S.KEY_COLORS.HELD then
                                            is_correctly_held = true
                                            break
                                        end
                                    end
                                end
                                if is_correctly_held then goto continue_held_loop end
                            end
                            for i = #part, 1, -1 do
                                if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(name)
                                   and not st.key_required_hold[i]
                                   and st.key_states[i] ~= nil then
                                    idx = i; break
                                end
                            end
                            if not idx then
                                for i = 1, #part do
                                    if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(name)
                                       and not st.key_required_hold[i] then
                                        idx = i; break
                                    end
                                end
                            end
                            if not idx then
                                for i = 1, #part do
                                    if Fn.decodeSafe(Fn.normalizeKeyName(part[i])) == Fn.decodeSafe(name) then
                                        idx = i; break
                                    end
                                end
                            end
                        end
                    end
                    if st.active_bridge_code == code then
                    elseif idx then
                        if not st.key_required_hold[idx] then
                            local alreadyHeld = (st.key_states[idx] == S.KEY_COLORS.HELD)
                            if not alreadyHeld then
                                local alreadyDone = (st.key_states[idx] ~= nil)
                                if not alreadyDone then
                                    st.key_states[idx]      = 0xFF0000
                                    st.hold_triggered[code] = true
                                    st.blocked_held[code]   = true
                                    st.held_keys[code]      = nil
                                   Fn.setError(name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(name), idx)
                                    return
                                end
                                st.key_states[idx]      = 0xFF0000
                                st.hold_triggered[code] = true
                                st.blocked_held[code]   = true
                                st.held_keys[code]      = nil
                               Fn.setError(name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(name), idx)
                                return
                            end
                        end
                    else
                        st.hold_triggered[code] = true
                        st.blocked_held[code]   = true
                        st.held_keys[code]      = nil
                       Fn.setError(name, Fn.T(u8"[CBUGER]: Ошибка, вы зажали: ") .. Fn.getLocalizedName(name), nil)
                        return
                    end
                end
            end
        end
        ::continue_held_loop::
    end
end
 Fn.deepcopy = function(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Fn.deepcopy(orig_key)] = Fn.deepcopy(orig_value)
        end
        setmetatable(copy, Fn.deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end
Fn.cleanEmptyComboStages = function(combo)
    local cleaned = {}
    local changed = false
    if type(combo) ~= 'table' then
        return cleaned, true
    end

    local function has_key_name(key)
        local raw_name
        if type(key) == 'table' then
            raw_name = key.name
            if raw_name == nil or tostring(raw_name):match('^%s*$') then
                raw_name = key[1]
            end
        else
            raw_name = key
        end
        local name = tostring(raw_name or ''):match('^%s*(.-)%s*$') or ''
        return name ~= ''
    end

    for _, part in ipairs(combo) do
        if type(part) == 'table' then
            local clean_part = {}
            for _, key in ipairs(part) do
                if has_key_name(key) then
                    clean_part[#clean_part + 1] = key
                else
                    changed = true
                end
            end
            if #clean_part > 0 then
                cleaned[#cleaned + 1] = clean_part
            else
                                changed = true
            end
        else
            changed = true
        end
    end

    if #cleaned ~= #combo then changed = true end
    return cleaned, changed
end

Fn.saveCombos = function() return Fn.save_combos_to_json(S.combos_list) end

Fn.refreshSavedCombo = function(index, select_when_window_open)
    local entry = index and S.combos_list[index] or nil
    if not entry then return end

    local st = S.state
    local window_was_open = ui.show_combo_window and ui.show_combo_window[0] or false
    local is_current = st.current_combo_index == index
    local should_refresh = is_current or (select_when_window_open and window_was_open)
    if not should_refresh then return end

    local pos_was_initialized = ui.combo_pos_initialized
    local chat_was_enabled = ui.show_chat_messages and ui.show_chat_messages[0]
    if type(entry.data) == 'table' and #entry.data > 0 then
        if ui.show_chat_messages then ui.show_chat_messages[0] = false end
        Fn.selectCombo(Fn.deepcopy(entry.data), entry.name, index)
        if ui.show_chat_messages then ui.show_chat_messages[0] = chat_was_enabled end
    else
                Fn.resetComboFull()
    end

    ui.show_combo_window[0] = window_was_open
    ui.combo_pos_initialized = pos_was_initialized
    ui.combo_size_initialized = false
    ui.combo_auto_size_signature = nil
end

Fn.closeComboEditor = function()
    local idx = ui.editor.selected_index
    local saved_changed = false
    if not ui.editor.is_new and idx and idx > 0 then
        local entry = S.combos_list[idx]
        if entry and type(entry.data) == 'table' then
            local cleaned, changed = Fn.cleanEmptyComboStages(entry.data)
            if changed then
                entry.data = cleaned
                saved_changed = true
            end
        end
    end

    ui.editor.temp_combo = Fn.cleanEmptyComboStages(ui.editor.temp_combo)
    if saved_changed then
        Fn.saveCombos()
        Fn.refreshSavedCombo(idx, false)
    end
    neon.target_combo_editor[0] = false
    ui.editor.add_target_part = nil
    ui.editor.active = false
end

 Fn.open_guide = function(index)
    if not index then index = ui.context_menu_target end
    local combo = index and S.combos_list[index] or nil
    if not combo then return end
    combo.guide_text = combo.guide_text or ''
    ui.current_guide_index = index
    ui.current_guide_name = combo.name or u8('Инфо')
    Lib.ffi.copy(ui.guide_text_buffer, combo.guide_text, 16383)
    ui.guide_open[0] = true
end
 Fn.InitEditor = function(is_new, index)
    ui.editor.is_new = is_new
    if is_new then
        ui.editor.selected_index = -1
        ui.editor.temp_combo     = {{}}
        local nm = u8"Новая Комбинация"
       Lib.ffi.copy(ui.editor.name_buffer, nm, math.min(#nm + 1, 64))
    else
        ui.editor.selected_index = index
        local c = S.combos_list[index]
        ui.editor.temp_combo = Fn.deepcopy(c.data)
       Lib.ffi.copy(ui.editor.name_buffer, c.name, math.min(#c.name + 1, 64))
    end
    ui.editor.add_target_part   = nil
    ui.editor.active            = true
    neon.target_combo_editor[0] = true
end
Data.now_phase   = 0
Data.wave_color  = {1, 1, 0, 0.8}
Data.wave_keys_list  = {}
Data.wave_key_index  = 1.0
Data.wave_cycle       = 0
 Fn.getKeyStateColor = function(keyName, comboVisualsActive, code)
    local st = S.state
    if st.current_combo and st.error_state.is_error
       and st.wrong_part_index == st.current_part_index then
        local ws = st.wrong_slot
        if ws then
            local part = Fn.getCurrentPart()
            if part and part[ws] and Fn.decodeSafe(Fn.normalizeKeyName(part[ws])) == Fn.decodeSafe(keyName) then
                return {
                    ui.error_color[1], ui.error_color[2], ui.error_color[3],
                    (ui.error_color[4] or 1) * ui.keyboard_key_alpha[0]
                }, nil
            end
        elseif st.wrong_key and Fn.decodeSafe(st.wrong_key) == Fn.decodeSafe(keyName) then
            return {
                ui.error_color[1], ui.error_color[2], ui.error_color[3],
                (ui.error_color[4] or 1) * ui.keyboard_key_alpha[0]
            }, nil
        end
    end
    do
        local now_flash_top = os.clock()
        if st.last_correct_flash_key and (now_flash_top - (st.last_correct_flash_time or 0)) < 0.1 then
            if Fn.decodeSafe(st.last_correct_flash_key) == Fn.decodeSafe(keyName) then
                return {
                    ui.correct_color[1], ui.correct_color[2], ui.correct_color[3],
                    (ui.correct_color[4] or 1) * ui.keyboard_key_alpha[0]
                }, nil
            end
        end
    end
    if not comboVisualsActive then
        if not st.current_combo then return nil, nil end
        local indices2 = Fn.findKeyIndicesInCurrentPart(keyName)
        if indices2 and #indices2 > 0 then
            for _, idx2 in ipairs(indices2) do
                local col2 = st.key_states and st.key_states[idx2]
                if col2 == 0x00FF00 then
                    return {
                        ui.correct_color[1], ui.correct_color[2], ui.correct_color[3],
                        (ui.correct_color[4] or 1) * ui.keyboard_key_alpha[0]
                    }, idx2
                end
            end
        end
        return nil, nil
    end
    local indices = Fn.findKeyIndicesInCurrentPart(keyName)
    if not indices or #indices == 0 then return nil, nil end
    local best_idx = nil
    if not best_idx then
        for _, idx in ipairs(indices) do
            if st.key_states[idx] == 0xFF0000 then
                best_idx = idx
                break
            end
        end
    end
    if not best_idx then
        for _, idx in ipairs(indices) do
            if st.key_states[idx] == S.KEY_COLORS.HELD then
                best_idx = idx
                break
            end
        end
    end
    if not best_idx then
        for _, idx in ipairs(indices) do
            if idx == st.current_key_index then
                best_idx = idx
                break
            end
        end
    end
    if not best_idx then
        local last_done = nil
        local has_undone = false
        for _, idx in ipairs(indices) do
            if st.key_states[idx] == 0x00FF00 then
                last_done = idx
            elseif st.key_states[idx] == nil then
                has_undone = true
            end
        end
        if last_done and has_undone then
            best_idx = last_done
        end
    end
    if not best_idx then
        local all_done = true
        for _, idx in ipairs(indices) do
            if st.key_states[idx] ~= 0x00FF00 then
                all_done = false
                break
            end
        end
        if all_done then
            best_idx = indices[1]
        end
    end
    if not best_idx then return nil, nil end
    local now_f2 = os.clock()
    if st.last_correct_flash_key and (now_f2 - (st.last_correct_flash_time or 0)) < 0.1 then
        if Fn.decodeSafe(st.last_correct_flash_key) == Fn.decodeSafe(keyName) then
            return {
                ui.correct_color[1], ui.correct_color[2], ui.correct_color[3],
                (ui.correct_color[4] or 1) * ui.keyboard_key_alpha[0]
            }, best_idx
        end
    end
    if st.error_state.is_error and st.wrong_part_index == st.current_part_index then
        local ws = st.wrong_slot
        if ws then
            if ws == best_idx then
                return {
                    ui.error_color[1], ui.error_color[2], ui.error_color[3],
                    (ui.error_color[4] or 1) * ui.keyboard_key_alpha[0]
                }, nil
            end
        elseif st.wrong_key and Fn.decodeSafe(st.wrong_key) == Fn.decodeSafe(keyName) then
            return {
                ui.error_color[1], ui.error_color[2], ui.error_color[3],
                (ui.error_color[4] or 1) * ui.keyboard_key_alpha[0]
            }, nil
        end
    end
    local col = st.key_states[best_idx]
    if col == S.KEY_COLORS.HELD then
        return nil, best_idx
    elseif col == 0x00FF00 then
        return {
            ui.correct_color[1], ui.correct_color[2], ui.correct_color[3],
            (ui.correct_color[4] or 1) * ui.keyboard_key_alpha[0]
        }, best_idx
    elseif col == 0xFF0000 then
        return {
            ui.error_color[1], ui.error_color[2], ui.error_color[3],
            (ui.error_color[4] or 1) * ui.keyboard_key_alpha[0]
        }, best_idx
    end
    return nil, best_idx
end









Fn.KS = (function()
    local KS = {}

    KS.SETTLE         = 1.5
    KS.RUN_TIMEOUT    = 3.0
    KS.TAP_MAX        = 0.5
    KS.HOLD_SLACK     = 0.25
    KS.HEAT_MIN_SCALE = 30
    KS.AUTOSAVE_SEC   = 30

    KS.enabled      = Lib.new.bool(false)
    KS.show_counts   = Lib.new.bool(false)
    KS.counts       = {}
    KS.combo_counts = {}
    KS.max          = 0
    KS.total        = 0
    KS.dirty        = false
    KS.last_save    = os.clock()
    KS.file         = tostring(Data.CBUGER_CONFIG_DIR or '') .. 'key_stats.json'

    local cur, prev = {}, {}
    local heat_prev, heat_active = {}, false
    local heat_last_frame, heat_fallback_frame, heat_fallback_time = nil, 0, -1
    local refresh_counts
    local poll, poll_ready = {}, false
    local id_code, id_cache = {}, {}
    local compiled, sig, sig_t = {}, nil, 0
    local runs, pending = {}, {}
    local seq = 0
    local active = false


    local function key_down(code)
        local api = Data.key_state_user32
        if api then
            local v = api.GetAsyncKeyState(code)
            return (tonumber(v) or 0) < 0
        end
        return isKeyDown(code) and true or false
    end

    local function recalc()
        local mx, mn, total = 0, nil, 0
        for _, n in pairs(KS.counts) do
            if n > mx then mx = n end
            if n > 0 and (mn == nil or n < mn) then mn = n end
            total = total + n
        end
        KS.max, KS.min, KS.total = mx, mn or 0, total
    end

    function KS.save()
        local keys = {}
        for code, n in pairs(KS.counts) do keys[tostring(code)] = n end
        local combos = {}
        for name, n in pairs(KS.combo_counts) do combos[tostring(name)] = n end
        local ok, js = pcall(encodeJson, {
            enabled = KS.enabled[0] and true or false,
            show_counts = KS.show_counts[0] and true or false,
            keys    = keys,
            combos  = combos,
        })
        if not ok or type(js) ~= 'string' then return false end
        local saved = CBUGER_SAFE_WRITE_FILE(KS.file, js)
        if not saved then return false end
        KS.dirty = false
        KS.last_save = os.clock()
        return true
    end

    function KS.load()
        local data = CBUGER_SAFE_LOAD_JSON(KS.file, function(value)
            return type(value.keys) == 'table' or type(value.combos) == 'table'
        end)
        if not data then return end
        KS.enabled[0] = (data.enabled == true)
        KS.show_counts[0] = (data.show_counts == true)
        if type(data.keys) == 'table' then
            for k, n in pairs(data.keys) do
                local code, cnt = tonumber(k), tonumber(n)
                if code and cnt and cnt > 0 then KS.counts[code] = math.floor(cnt) end
            end
        end
        if type(data.combos) == 'table' then
            for name, n in pairs(data.combos) do
                local cnt = tonumber(n)
                if cnt and cnt > 0 then KS.combo_counts[tostring(name)] = math.floor(cnt) end
            end
        end
        recalc()
    end


    local HEAT_STOPS = {
        { 0.00, 0.10, 0.80, 0.25 },
        { 0.35, 0.95, 0.90, 0.10 },
        { 0.65, 1.00, 0.55, 0.05 },
        { 1.00, 0.90, 0.08, 0.08 },
    }

    local function heat_rgb(t)
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        for i = 2, #HEAT_STOPS do
            local a, b = HEAT_STOPS[i - 1], HEAT_STOPS[i]
            if t <= b[1] then
                local k = (t - a[1]) / (b[1] - a[1])
                return a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, a[4] + (b[4] - a[4]) * k
            end
        end
        local l = HEAT_STOPS[#HEAT_STOPS]
        return l[2], l[3], l[4]
    end

    function KS.heat_color(code)
        if type(code) ~= 'number' then return nil end
        local n = KS.counts[code]
        if not n or n <= 0 then return nil end


        local mx, mn = KS.max, KS.min or 0
        local t = 0.5
        if mx > mn then t = (n - mn) / (mx - mn) end
        local r, g, b = heat_rgb(t)
        if cur[code] then
            r = r + (1 - r) * 0.35
            g = g + (1 - g) * 0.35
            b = b + (1 - b) * 0.35
        end
        local a = 1
        if ui.keyboard_key_alpha then a = ui.keyboard_key_alpha[0] end
        return { r, g, b, a }
    end


    function KS.display_text(code, fallback, secondary_code)
        if not (KS.enabled[0] and KS.show_counts[0]) or type(code) ~= 'number' then
            return fallback, nil, false
        end
        local n = math.floor(tonumber(KS.counts[code]) or 0)
        if type(secondary_code) == 'number' and secondary_code ~= code then
            n = n + math.floor(tonumber(KS.counts[secondary_code]) or 0)
        end
        local mx, mn = KS.max or 0, KS.min or 0
        local t = 0
        if n > 0 then
            t = 0.5
            if mx > mn then t = (n - mn) / (mx - mn) end
        end
        local r, g, b = heat_rgb(t)
        if cur[code] then
            r = r + (1 - r) * 0.35
            g = g + (1 - g) * 0.35
            b = b + (1 - b) * 0.35
        end
        local a = ui.text_alpha and tonumber(ui.text_alpha[0]) or 1
        local color = { r, g, b, a }
        return tostring(n), color, true
    end


    local orig_get_state_color = Fn.getKeyStateColor
    Fn.getKeyStateColor = function(keyName, comboVisualsActive, code)
        local color, idx = orig_get_state_color(keyName, comboVisualsActive, code)
        if color == nil and KS.enabled[0] and not KS.show_counts[0] then
            local hc = KS.heat_color(code)
            if hc then return hc, nil end
        end
        return color, idx
    end


    local function ensure_poll()
        if not poll_ready then
            poll_ready = true
            local function add(code)
                if type(code) == 'number' then poll[code] = true end
            end
            add(0x01); add(0x02); add(0x10); add(0x20)
            local kb = Data.full_keyboard
            if type(kb) == 'table' and type(kb.rows) == 'table' then
                for _, row in ipairs(kb.rows) do
                    for _, item in ipairs(row) do
                        add(item.code)
                        add(item.code2)
                    end
                end
            end
        end
        if type(keyboards) == 'table' then
            for _, line in ipairs(keyboards) do
                if type(line) == 'table' then
                    for _, v in ipairs(line) do
                        if type(v) == 'table' and type(v[2]) == 'number' then poll[v[2]] = true end
                    end
                end
            end
        end
        pcall(function()
            local sc = Fn.getSpaceCode()
            if type(sc) == 'number' then poll[sc] = true end
        end)
        for _, k in ipairs(S.all_monitored_keys or {}) do
            if type(k.code) == 'number' then poll[k.code] = true end
        end
    end

    refresh_counts = function(blocked, states, force)
        if not KS.enabled[0] then
            heat_active = false
            return
        end

        local frame_id
        local ok_frame, frame_value = pcall(function()
            return Lib.imgui.GetFrameCount()
        end)
        if ok_frame and type(frame_value) == 'number' then
            frame_id = 'imgui:' .. tostring(frame_value)
        else
            local now = os.clock()
            if heat_fallback_time < 0 or now - heat_fallback_time >= 0.005 then
                heat_fallback_time = now
                heat_fallback_frame = heat_fallback_frame + 1
            end
            frame_id = 'fallback:' .. tostring(heat_fallback_frame)
        end
        if not force and frame_id == heat_last_frame then return end
        heat_last_frame = frame_id

        ensure_poll()
        local paused = blocked and true or false
        local can_count = heat_active and not paused
        local changed = false
        for code in pairs(poll) do
            local down
            if type(states) == 'table' then
                down = states[code] and true or false
            else
                down = Fn.isPhysicalKeyDown(code) and true or false
            end
            if can_count and down and not heat_prev[code] then
                KS.counts[code] = (KS.counts[code] or 0) + 1
                KS.dirty = true
                changed = true
            end
            heat_prev[code] = down
        end
        if changed then recalc() end
        heat_active = not paused
    end

    function KS.refresh_display_counts()
        if refresh_counts then refresh_counts(KS.gate == true) end
    end

    local function name_id(name)
        local id = id_cache[name]
        if id == nil then
            id = Fn.decodeSafe(Fn.normalizeKeyName(name))
            id_cache[name] = id
        end
        return id
    end

    local function compile(combo)
        local data = combo and combo.data
        if type(data) ~= 'table' then return nil end
        local steps, parts = {}, {}
        for _, part in ipairs(data) do
            if type(part) == 'table' and #part > 0 then
                local pi = #parts + 1
                local first = #steps + 1
                for _, key in ipairs(part) do
                    local is_hold, ht = Fn.getKeyHoldSettings(key)
                    steps[#steps + 1] = {
                        id   = Fn.decodeSafe(Fn.normalizeKeyName(key)),
                        hold = is_hold and true or false,
                        time = tonumber(ht) or (S.state and S.state.DEFAULT_HOLD_TIME) or 0.5,
                        part = pi,
                    }
                end
                parts[pi] = { first = first, last = #steps }
            end
        end
        if #steps == 0 then return nil end

        for i, st in ipairs(steps) do
            if not st.hold then
                local p = parts[st.part]
                for j = p.first, p.last do
                    if j ~= i and steps[j].hold and steps[j].id == st.id then
                        st.bridge = true
                        break
                    end
                end
            end
        end
        return { name = combo.name, steps = steps, parts = parts, n = #steps }
    end

    local function combos_signature()
        local out = {}
        local list = S.combos_list or {}
        out[1] = tostring(#list)

        local function append_data_signature(data, prefix)
            if type(data) ~= 'table' then return end
            for _, part in ipairs(data) do
                local seg = {}
                if type(part) == 'table' then
                    for _, key in ipairs(part) do
                        if type(key) == 'table' then
                            seg[#seg + 1] = tostring(key.name)
                                .. (key.hold and ('~' .. tostring(key.time)) or '')
                        else
                            seg[#seg + 1] = tostring(key)
                        end
                    end
                end
                out[#out + 1] = (prefix or '') .. table.concat(seg, ',')
            end
        end

        for _, combo in ipairs(list) do
            out[#out + 1] = tostring(combo.name)
            append_data_signature(combo.data, 'data:')
            for variant_index, variant in ipairs(combo.keymap_alternatives or {}) do
                out[#out + 1] = 'alternative:' .. tostring(variant_index)
                append_data_signature(variant, 'alt:')
            end
        end
        return table.concat(out, '|')
    end

    local function reset_runs()
        runs, pending = {}, {}
    end

    local function refresh_compiled(now)
        if sig ~= nil and now - sig_t < 1.0 then return end
        sig_t = now
        local s = combos_signature()
        if s == sig then return end
        sig = s
        compiled = {}
        for i, combo in ipairs(S.combos_list or {}) do
            local c = compile(combo)
            if c then
                c.order = i
                compiled[#compiled + 1] = c
            end

            if type(combo.keymap_alternatives) == 'table' then
                for variant_index, variant_data in ipairs(combo.keymap_alternatives) do
                    if type(variant_data) == 'table' then
                        local variant_combo = { name = combo.name, data = variant_data }
                        local variant = compile(variant_combo)
                        if variant then
                            variant.order = i
                            variant.variant_index = variant_index
                            compiled[#compiled + 1] = variant
                        end
                    end
                end
            end
        end
        reset_runs()
    end

    local function accept(run, idx, now)
        local st = run.c.steps[idx]
        run.pos = idx + 1
        run.last_t = now
        if st.hold then
            run.holds[idx] = now
        elseif not st.bridge then
            run.taps[idx] = now
        end
    end


    local function try_press(run, id, now)
        if run.swap_wait then
            if id == run.swap_wait then
                run.swap_wait = nil
                run.last_t = now
                return true
            end
            return false
        end
        local steps = run.c.steps
        if run.pos > run.c.n then return false end
        local st = steps[run.pos]
        if st.id == id then
            accept(run, run.pos, now)
            return true
        end

        local nx = steps[run.pos + 1]
        if nx and not st.hold and not nx.hold and nx.part == st.part and id == nx.id
           and ((st.id == 'Q' and nx.id == 'E') or (st.id == 'E' and nx.id == 'Q')) then
            local p = run.pos
            accept(run, p + 1, now)
            run.pos = p + 2
            run.swap_wait = st.id
            return true
        end
        return false
    end

    local function on_press(id, now)
        seq = seq + 1
        local survivors = {}
        for _, run in ipairs(runs) do
            if try_press(run, id, now) then survivors[#survivors + 1] = run end
        end
        for _, c in ipairs(compiled) do
            if c.steps[1].id == id then
                local run = { c = c, pos = 1, start_seq = seq, last_t = now, holds = {}, taps = {} }
                accept(run, 1, now)
                survivors[#survivors + 1] = run
            end
        end
        while #survivors > 300 do table.remove(survivors, 1) end
        runs = survivors
    end


    local function tick_run(run, now)
        local c = run.c
        local steps = c.steps
        for idx, t0 in pairs(run.holds) do
            local st = steps[idx]
            if now - t0 > st.time + KS.HOLD_SLACK then return 'dead' end
            local code = id_code[st.id]
            if not (code and cur[code]) then
                local part = c.parts[st.part]
                if run.pos <= part.last then
                    local again = false
                    for j = run.pos, part.last do
                        if steps[j].id == st.id then
                            again = true
                            break
                        end
                    end
                    if not again then return 'dead' end
                end
                run.holds[idx] = nil
            end
        end
        for idx, t0 in pairs(run.taps) do
            local code = id_code[steps[idx].id]
            if code and cur[code] then
                if now - t0 >= KS.TAP_MAX then return 'dead' end
            else
                run.taps[idx] = nil
            end
        end
        if run.pos <= c.n or run.swap_wait then
            if now - run.last_t > KS.RUN_TIMEOUT then return 'dead' end
        elseif next(run.holds) == nil then
            return 'done'
        end
        return nil
    end

    local function covers(a, b)
        return a.start <= b.start and a.stop >= b.stop
    end

    local function add_candidate(cand)
        for i = #pending, 1, -1 do
            local p = pending[i]
            local a_cov, b_cov = covers(cand, p), covers(p, cand)
            if a_cov and b_cov then
                if cand.n > p.n or (cand.n == p.n and cand.order < p.order) then
                    table.remove(pending, i)
                else
                    return
                end
            elseif a_cov then
                table.remove(pending, i)
            elseif b_cov then
                return
            end
        end
        pending[#pending + 1] = cand
    end

    local function commit(x)
        local name = tostring(x.c.name)
        KS.combo_counts[name] = (KS.combo_counts[name] or 0) + 1
        KS.dirty = true
        local keep = {}
        for _, run in ipairs(runs) do
            if run.start_seq > x.stop then keep[#keep + 1] = run end
        end
        runs = keep
        local np = {}
        for _, p in ipairs(pending) do
            if p ~= x and p.start > x.stop then np[#np + 1] = p end
        end
        pending = np
    end




    local function settle_pending(now)
        if #pending > 1 then
            table.sort(pending, function(a, b)
                if a.start ~= b.start then return a.start < b.start end
                return a.stop < b.stop
            end)
        end
        local i = 1
        while i <= #pending do
            local x = pending[i]
            local blocked = false
            for _, run in ipairs(runs) do
                if run.start_seq <= x.start and (now - run.last_t) < KS.SETTLE then
                    blocked = true
                    break
                end
            end
            if blocked then
                i = i + 1
            else
                commit(x)
                i = 1
            end
        end
    end


    function KS.update(blocked)
        local now = os.clock()
        if KS.enabled[0] ~= KS.enabled_saved then
            KS.enabled_saved = KS.enabled[0]
            KS.dirty = true
            KS.save()
        end
        if KS.dirty and now - KS.last_save >= KS.AUTOSAVE_SEC then KS.save() end

        if not KS.enabled[0] then
            heat_active = false
            if active then
                active = false
                reset_runs()
            end
            return
        end

        ensure_poll()
        for code in pairs(poll) do cur[code] = key_down(code) end
        refresh_counts(blocked, cur, true)
        KS.frames = (KS.frames or 0) + 1

        local gate = blocked and true or false
        KS.gate = gate
        KS.stat = KS.stat or { ok = 0, menu = 0, guide = 0, chat = 0, script = 0 }
        if gate then
            local w = KS.why or 'chat'
            KS.stat[w] = (KS.stat[w] or 0) + 1
        else
            KS.stat.ok = KS.stat.ok + 1
        end
        if gate or not active then

            for code, d in pairs(cur) do prev[code] = d end
            active = not gate
            if gate then reset_runs() end
            return
        end



        local pressed = {}
        for code in pairs(poll) do
            if cur[code] and not prev[code] then
                pressed[code] = true
            end
        end

        for code, d in pairs(cur) do prev[code] = d end


        local events = {}
        for _, k in ipairs(S.all_monitored_keys or {}) do
            local id = name_id(k.name)
            id_code[id] = k.code
            if pressed[k.code] then events[#events + 1] = id end
        end
        for code, d in pairs(cur) do prev[code] = d end

        refresh_compiled(now)
        for _, id in ipairs(events) do on_press(id, now) end

        local alive = {}
        for _, run in ipairs(runs) do
            local r = tick_run(run, now)
            if r == 'done' then
                add_candidate({ c = run.c, start = run.start_seq, stop = seq, n = run.c.n, order = run.c.order })
            elseif r ~= 'dead' then
                alive[#alive + 1] = run
            end
        end
        runs = alive
        settle_pending(now)
    end

    function KS.safe_update(blocked)
        local ok, err = pcall(KS.update, blocked)
        if not ok then
            KS.last_err = tostring(err)
            if not KS.err_shown then
                KS.err_shown = true
                print('[CBUGER] KeyStats error: ' .. tostring(err))
            end
        end
    end

    function KS.reset()
        KS.counts = {}
        KS.combo_counts = {}
        KS.max, KS.total = 0, 0
        reset_runs()
        KS.dirty = true
        KS.save()
    end


    function KS.combo_rows()
        local rows, seen = {}, {}
        for i, combo in ipairs(S.combos_list or {}) do
            local key = tostring(combo.name)
            local n = KS.combo_counts[key]
            if n and n > 0 and not seen[key] then
                seen[key] = true
                rows[#rows + 1] = { name = combo.name, n = n, i = i }
            end
        end
        table.sort(rows, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.i < b.i
        end)
        return rows
    end

    function KS.draw_ui(alpha, main_alpha, cw)
        local im = Lib.imgui
        local cols = Data.neon_active_colors or {}
        local tcol = cols[im.Col.Text] or { 1, 1, 1, 1 }
        local dcol = cols[im.Col.TextDisabled] or { 0.6, 0.7, 0.9, 1 }

        im.SetWindowFontScale(0.9)
        if im.Checkbox(Fn.T(u8"Показывать количество нажатий цифрами") .. "##ks_count_labels", KS.show_counts) then
            KS.dirty = true
            KS.save()
        end
        im.Dummy(im.ImVec2(0, 4))
        if not KS.enabled[0] then
            im.TextColored(im.ImVec4(dcol[1], dcol[2], dcol[3], 0.8 * alpha),
                Fn.T(u8"Включите, чтобы считать нажатия и комбинации"))
            im.SetWindowFontScale(1.0)
            return
        end
        im.TextColored(im.ImVec4(dcol[1], dcol[2], dcol[3], 0.8 * alpha),
            Fn.T(u8"Чем чаще нажимаете клавишу, тем краснее она"))
        im.SetWindowFontScale(1.0)


        local dl = im.GetWindowDrawList()
        if Data.ofs_row then Data.ofs_row('gr_keymap_scale') end
        local p = im.GetCursorScreenPos()
        local w, h, seg = 170, 6, 17
        for i = 0, seg - 1 do
            local r, g, b = heat_rgb(i / (seg - 1))
            dl:AddRectFilled(
                im.ImVec2(p.x + i * w / seg, p.y + 2),
                im.ImVec2(p.x + (i + 1) * w / seg, p.y + 2 + h),
                Data.nfn.pack_color(r, g, b, 0.9, false, main_alpha), 2)
        end
        im.Dummy(im.ImVec2(w, h + 8))

        im.Dummy(im.ImVec2(0, 4))



        local armed = KS.reset_until ~= nil and os.clock() < KS.reset_until
        local label = armed and Fn.T(u8"Нажмите ещё раз для сброса") or Fn.T(u8"Сбросить статистику")
        local bw = (type(cw) == 'number') and (cw - 40) or math.max(40, im.GetContentRegionAvail().x)
        if Data.ofs_row then Data.ofs_row('bt_keymap_reset') end
        local clicked = im.Button(label .. "##ks_reset", im.ImVec2(bw, 28))
        if im.IsItemHovered() then Data.nfn.set_hand_cursor() end
        if clicked then
            if armed then
                KS.reset_until = nil
                KS.reset()
            else
                KS.reset_until = os.clock() + 3.0
            end
        end


        im.Dummy(im.ImVec2(0, 8))
        im.TextColored(im.ImVec4(dcol[1], dcol[2], dcol[3], alpha), Fn.T(u8"Комбинации") .. ":")
        local rows = KS.combo_rows()
        if #rows == 0 then
            im.SetWindowFontScale(0.9)
            im.TextColored(im.ImVec4(tcol[1], tcol[2], tcol[3], 0.5 * alpha),
                Fn.T(u8"Пока нет правильно выполненных комбинаций"))
            im.SetWindowFontScale(1.0)
        else
            local top = rows[1].n
            for _, r in ipairs(rows) do
                im.TextColored(im.ImVec4(tcol[1], tcol[2], tcol[3], alpha), Fn.decodeSafe(r.name))
                im.SameLine(0, 6)
                local rr, gg, bb = heat_rgb((r.n / math.max(top, 1)) ^ 0.6)
                im.TextColored(im.ImVec4(rr, gg, bb, alpha), "(" .. tostring(r.n) .. ")")
            end
        end
    end


    do
        local tr = {
            [u8"Статистика нажатий"]                         = "Key statistics",
            [u8"Тепловая карта клавиш"]                      = "Key heatmap",
            [u8"Включите, чтобы считать нажатия и комбинации"] = "Enable to count key presses and combos",
            [u8"Чем чаще нажимаете клавишу, тем краснее она"]  = "The more you press a key, the redder it gets",
            [u8"Показывать количество нажатий цифрами"] = "Show press counts as numbers",
            [u8"Сбросить статистику"]                        = "Reset statistics",
            [u8"Нажмите ещё раз для сброса"]                 = "Press again to reset",
            [u8"Комбинации"]                                 = "Combos",
            [u8"Пока нет правильно выполненных комбинаций"]  = "No correctly performed combos yet",
        }
        for k, v in pairs(tr) do
            local dk = Fn.decodeSafe(k)
            if not Data.UI_TRANSLATIONS[dk] then Data.UI_TRANSLATIONS[dk] = v end
        end
    end

    KS.load()
    KS.enabled_saved = KS.enabled[0]
    return KS
end)()
Data.full_keyboard = {
    row_h = 35,
    unit_w = 34,
    gap = 4,
    row_gap = 5,
    left = 0,
    rows = {
        {
            {label='ESC', code=0x1B, x=0, w=1},
            {label='F1', code=0x70, x=2, w=1}, {label='F2', code=0x71, x=3, w=1}, {label='F3', code=0x72, x=4, w=1}, {label='F4', code=0x73, x=5, w=1},
            {label='F5', code=0x74, x=6.5, w=1}, {label='F6', code=0x75, x=7.5, w=1}, {label='F7', code=0x76, x=8.5, w=1}, {label='F8', code=0x77, x=9.5, w=1},
            {label='F9', code=0x78, x=11, w=1}, {label='F10', code=0x79, x=12, w=1}, {label='F11', code=0x7A, x=13, w=1}, {label='F12', code=0x7B, x=14, w=1},
        },
        {
            {label='`', code=0xC0, x=0, w=1},
            {label='1', code=0x31, x=1, w=1}, {label='2', code=0x32, x=2, w=1}, {label='3', code=0x33, x=3, w=1}, {label='4', code=0x34, x=4, w=1}, {label='5', code=0x35, x=5, w=1},
            {label='6', code=0x36, x=6, w=1}, {label='7', code=0x37, x=7, w=1}, {label='8', code=0x38, x=8, w=1}, {label='9', code=0x39, x=9, w=1}, {label='0', code=0x30, x=10, w=1},
            {label='-', code=0xBD, x=11, w=1}, {label='=', code=0xBB, x=12, w=1}, {label='BACKSPACE', code=0x08, x=13, w=2},
            {label='INSERT', code=0x2D, x=15.5, w=1}, {label='HOME', code=0x24, x=16.5, w=1}, {label='PGUP', code=0x21, x=17.5, w=1},
            {label='NUM', code=0x90, x=19, w=1}, {label='/', code=0x6F, x=20, w=1}, {label='*', code=0x6A, x=21, w=1}, {label='-', code=0x6D, x=22, w=1},
        },
        {
            {label='TAB', code=0x09, x=0, w=1.5},
            {label='Q', code=0x51, x=1.5, w=1}, {label='W', code=0x57, x=2.5, w=1}, {label='E', code=0x45, x=3.5, w=1}, {label='R', code=0x52, x=4.5, w=1}, {label='T', code=0x54, x=5.5, w=1},
            {label='Y', code=0x59, x=6.5, w=1}, {label='U', code=0x55, x=7.5, w=1}, {label='I', code=0x49, x=8.5, w=1}, {label='O', code=0x4F, x=9.5, w=1}, {label='P', code=0x50, x=10.5, w=1},
            {label='[', code=0xDB, x=11.5, w=1}, {label=']', code=0xDD, x=12.5, w=1}, {label='\\', code=0xDC, x=13.5, w=1.5},
            {label='DELETE', code=0x2E, x=15.5, w=1}, {label='END', code=0x23, x=16.5, w=1}, {label='PGDN', code=0x22, x=17.5, w=1},
            {label='NUM7', code=0x67, code2=0x24, x=19, w=1}, {label='NUM8', code=0x68, code2=0x26, x=20, w=1}, {label='NUM9', code=0x69, code2=0x21, x=21, w=1}, {label='+', code=0x6B, x=22, w=1, h=2},
        },
        {
            {label='CAPS', code=0x14, x=0, w=1.75},
            {label='A', code=0x41, x=1.75, w=1}, {label='S', code=0x53, x=2.75, w=1}, {label='D', code=0x44, x=3.75, w=1}, {label='F', code=0x46, x=4.75, w=1}, {label='G', code=0x47, x=5.75, w=1},
            {label='H', code=0x48, x=6.75, w=1}, {label='J', code=0x4A, x=7.75, w=1}, {label='K', code=0x4B, x=8.75, w=1}, {label='L', code=0x4C, x=9.75, w=1},
            {label=';', code=0xBA, x=10.75, w=1}, {label="'", code=0xDE, x=11.75, w=1}, {label='ENTER', code=0x0D, x=12.75, w=2.25},
            {label='NUM4', code=0x64, code2=0x25, x=19, w=1}, {label='NUM5', code=0x65, code2=0x0C, x=20, w=1}, {label='NUM6', code=0x66, code2=0x27, x=21, w=1},
        },
        {
            {label='SHIFT', code=0x10, x=0, w=2.25},
            {label='Z', code=0x5A, x=2.25, w=1}, {label='X', code=0x58, x=3.25, w=1}, {label='C', code=0x43, x=4.25, w=1}, {label='V', code=0x56, x=5.25, w=1}, {label='B', code=0x42, x=6.25, w=1},
            {label='N', code=0x4E, x=7.25, w=1}, {label='M', code=0x4D, x=8.25, w=1}, {label=',', code=0xBC, x=9.25, w=1}, {label='.', code=0xBE, x=10.25, w=1}, {label='/', code=0xBF, x=11.25, w=1},
            {label='SHIFT', code=0x10, x=12.25, w=2.75},
            {label='UP', code=0x26, x=16.5, w=1},
            {label='NUM1', code=0x61, code2=0x23, x=19, w=1}, {label='NUM2', code=0x62, code2=0x28, x=20, w=1}, {label='NUM3', code=0x63, code2=0x22, x=21, w=1}, {label='ENTER', code=0x0D, x=22, w=1, h=2},
        },
        {
            {label='CTRL', code=0x11, x=0, w=1.25}, {label='WIN', code=0x5B, x=1.25, w=1.25}, {label='ALT', code=0x12, x=2.5, w=1.25},
            {label='SPACE', code=nil, x=3.75, w=6.25},
            {label='ALT', code=0x12, x=10, w=1.25}, {label='WIN', code=0x5C, x=11.25, w=1.25}, {label='MENU', code=0x5D, x=12.5, w=1.25}, {label='CTRL', code=0x11, x=13.75, w=1.25},
            {label='LEFT', code=0x25, x=15.5, w=1}, {label='DOWN', code=0x28, x=16.5, w=1}, {label='RIGHT', code=0x27, x=17.5, w=1},
            {label='NUM0', code=0x60, code2=0x2D, x=19, w=2}, {label='NUM.', code=0x6E, code2=0x2E, x=21, w=1},
        },
    }
}
local function full_key_size(w_units, scale, h_units)
    h_units = h_units or 1
    local gap = Data.full_keyboard.gap * scale
    local unit = Data.full_keyboard.unit_w * scale
    local width = unit * w_units + gap * math.max(0, w_units - 1)
    local rowStep = Data.full_keyboard.row_h + Data.full_keyboard.row_gap
    local height = (rowStep * h_units - Data.full_keyboard.row_gap) * scale
    return width, height
end
local function full_key_name(label)
    if label == 'SPACE' then
        return Fn.T(u8'ПРОБЕЛ')
    end
    if label == 'NUM.' then return '.' end
    if label:sub(1, 3) == 'NUM' and #label > 3 then
        return label:sub(4)
    end
    return label
end
local function render_full_key(item, scale, st, comboVisualsActive, dl, rowY, rowX)
    local keyCode = (item.label == 'SPACE') and Fn.getSpaceCode() or (item.code or 0x20)
    local keyNameForLogic = (item.label == 'SPACE') and Fn.decodeSafe(u8'ПРОБЕЛ') or item.label
    local text = Fn.getLocalizedName(full_key_name(item.label))
    local numeric_text_color, is_numeric_text
    text, numeric_text_color, is_numeric_text = Fn.KS.display_text(keyCode, text, item.code2)
    local isPressed = Fn.isPhysicalKeyDown(keyCode) or (item.code2 ~= nil and Fn.isPhysicalKeyDown(item.code2))
    local base_fill   = Fn.computePulsedColor(ui.key_fill_color,   ui.key_fill_rgb[0], ui.rgb_speed[0])
    local base_border = Fn.computePulsedColor(ui.key_border_color, ui.key_border_rgb[0], ui.rgb_speed[0])
    local base_text_c = Fn.computePulsedColor(ui.key_text_color,   ui.key_text_rgb[0], ui.rgb_speed[0])
    local buttonColor = {base_fill[1], base_fill[2], base_fill[3], (base_fill[4] or 1) * ui.keyboard_key_alpha[0]}
    if isPressed and ui.pressed_fill_enabled[0] then
        buttonColor = {ui.pressed_fill_color[1], ui.pressed_fill_color[2], ui.pressed_fill_color[3], ui.pressed_fill_color[4] * ui.keyboard_key_alpha[0]}
    end
    local stateColor = Fn.getKeyStateColor(keyNameForLogic, comboVisualsActive, keyCode)
    if stateColor then buttonColor = stateColor end
    local x = rowX + item.x * (Data.full_keyboard.unit_w + Data.full_keyboard.gap) * scale
    local y = rowY
    local width, height = full_key_size(item.w, scale, item.h)
    local pressedScale = isPressed and 1.04 or 1.0
    local cx, cy = x + width * 0.5, y + height * 0.5
    local w2, h2 = width * pressedScale, height * pressedScale
    local a = Lib.imgui.ImVec2(cx - w2 * 0.5, cy - h2 * 0.5)
    local b = Lib.imgui.ImVec2(cx + w2 * 0.5, cy + h2 * 0.5)
    if ui.wave_enabled[0] then
        table.insert(Data.wave_keys_list, {
            min = Lib.imgui.ImVec2(a.x + 1, a.y + 1),
            max = Lib.imgui.ImVec2(b.x - 1, b.y - 1)
        })
    end
    dl:AddRectFilled(
        Lib.imgui.ImVec2(a.x + 1, a.y + 1),
        Lib.imgui.ImVec2(b.x - 1, b.y - 1),
        Fn.getColorU32(buttonColor[1], buttonColor[2], buttonColor[3], buttonColor[4], true, 1),
        6
    )
    local b_mode = ui.border_mode[0]
    if (b_mode == 2) or (b_mode == 3 and isPressed) then
        local borderCol = {
            base_border[1], base_border[2], base_border[3],
            (base_border[4] or 1) * ui.keyboard_key_alpha[0]
        }
        if isPressed and ui.pressed_border_enabled[0] then
            borderCol = {
                ui.pressed_border_color[1], ui.pressed_border_color[2], ui.pressed_border_color[3],
                ui.pressed_border_color[4] * ui.keyboard_key_alpha[0]
            }
        end
        dl:AddRect(
            a, b,
            Fn.getColorU32(borderCol[1], borderCol[2], borderCol[3], borderCol[4], true, 1),
            6, nil, Data.border_thickness[0] * scale
        )
    end
    local ts = Lib.imgui.CalcTextSize(text)
    local availW = math.max(6, width - 8)
    local availH = math.max(6, height - 6)
    local fit = 1.0
    if ts.x > availW or ts.y > availH then
        fit = math.max(0.45, math.min(availW / math.max(ts.x, 1), availH / math.max(ts.y, 1), 1.0))
    end
    if fit < 0.999 then
        Lib.imgui.SetWindowFontScale(fit)
        ts = Lib.imgui.CalcTextSize(text)
    end
    local text_rgba = {
        base_text_c[1], base_text_c[2], base_text_c[3],
        (base_text_c[4] or 1) * ui.text_alpha[0]
    }
    if is_numeric_text then
        if numeric_text_color then text_rgba = numeric_text_color end
    else
        if isPressed and ui.pressed_text_enabled[0] then
            text_rgba = {
                ui.pressed_text_color[1], ui.pressed_text_color[2], ui.pressed_text_color[3],
                ui.pressed_text_color[4] * ui.text_alpha[0]
            }
        end
        text_rgba = Fn.applyWaveText(text_rgba, a.x + 1, a.y + 1)
    end
    local tc = Fn.getColorU32(text_rgba[1], text_rgba[2], text_rgba[3], text_rgba[4], false, 1)
    local textX = math.floor(cx - ts.x * 0.5 + 0.5)
    local textY = math.floor(cy - ts.y * 0.5 + 0.5)
    dl:AddText(Lib.imgui.ImVec2(textX, textY), tc, text)
    if fit < 0.999 then Lib.imgui.SetWindowFontScale(1.0) end
end
Fn.RenderGridKeyboard = function(rows, windowId, posKey)
    local st = S.state
    Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg, Lib.imgui.ImVec4(0,0,0,0))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(0,0,0,0))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.BorderShadow, Lib.imgui.ImVec4(0,0,0,0))
    Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(5, 2.4))
    Lib.imgui.SetNextWindowPos(ui[posKey], Lib.imgui.Cond.FirstUseEver, Lib.imgui.ImVec2(0,0))
    local flags = Lib.imgui.WindowFlags.NoResize + Lib.imgui.WindowFlags.NoTitleBar + Lib.imgui.WindowFlags.AlwaysAutoResize + Lib.imgui.WindowFlags.NoScrollbar + Lib.imgui.WindowFlags.NoScrollWithMouse + Lib.imgui.WindowFlags.NoBackground + (ui.move[0] and 0 or Lib.imgui.WindowFlags.NoMove)
    Lib.imgui.Begin(windowId, nil, flags)
    ui[posKey] = Lib.imgui.GetWindowPos()
    local dl = Lib.imgui.GetWindowDrawList()
    Data.wave_draw_list_ref = dl
    local scale = math.max(0.5, ui.keyboard_scale[0])
    local rowStep = (Data.full_keyboard.row_h + Data.full_keyboard.row_gap) * scale
    local origin = Lib.imgui.GetCursorScreenPos()
    local comboVisualsActive = st.current_combo ~= nil
    local maxX, maxY = origin.x, origin.y
    for ri, row in ipairs(rows) do
        local rowY = origin.y + (ri - 1) * rowStep
        local rowX = origin.x
        for _, item in ipairs(row) do
            render_full_key(item, scale, st, comboVisualsActive, dl, rowY, rowX)
            local x = rowX + item.x * (Data.full_keyboard.unit_w + Data.full_keyboard.gap) * scale
            local w, h = full_key_size(item.w, scale, item.h)
            maxX = math.max(maxX, x + w * 1.04)
            maxY = math.max(maxY, rowY + h * 1.04)
        end
    end
    Lib.imgui.Dummy(Lib.imgui.ImVec2(
        math.max(1, maxX - origin.x + 8 * scale),
        math.max(1, maxY - origin.y + 4 * scale)
    ))
    Lib.imgui.End()
    Lib.imgui.PopStyleVar()
    Lib.imgui.PopStyleColor(3)
end
local function filter_rows(rows, predicate)
    local out = {}
    for ri, row in ipairs(rows) do
        local newRow = {}
        for _, item in ipairs(row) do
            if predicate(item) then
                table.insert(newRow, {label = item.label, code = item.code, code2 = item.code2, x = item.x, w = item.w, h = item.h})
            end
        end
        if #newRow > 0 then table.insert(out, newRow) end
    end
    return out
end
Data.kb_no_numpad = filter_rows(Data.full_keyboard.rows, function(item) return item.x < 19 end)
 Fn.RenderKeyboard = function()
    Fn.KS.refresh_display_counts()
    local kt = ui.keyboard_type[0]
    if kt == 1 then
        Fn.RenderGridKeyboard(Data.full_keyboard.rows, '##keyboard_full', 'keyboard_pos')
        return
    elseif kt == 2 then
        Fn.RenderGridKeyboard(Data.kb_no_numpad, '##keyboard_no_numpad', 'keyboard_pos')
        return
    end
    local st = S.state
   Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg,   Lib.imgui.ImVec4(0, 0, 0, 0))
   Lib.imgui.PushStyleColor(Lib.imgui.Col.Border,     Lib.imgui.ImVec4(0, 0, 0, 0))
   Lib.imgui.PushStyleColor(Lib.imgui.Col.BorderShadow, Lib.imgui.ImVec4(0, 0, 0, 0))
   local kb_pos_cond = Data.force_keyboard_pos_once and Lib.imgui.Cond.Always or Lib.imgui.Cond.FirstUseEver
   Lib.imgui.SetNextWindowPos(ui.keyboard_pos, kb_pos_cond, Lib.imgui.ImVec2(0, 0))
    local kb_flags = Lib.imgui.WindowFlags.NoResize
        + Lib.imgui.WindowFlags.NoTitleBar
        + Lib.imgui.WindowFlags.AlwaysAutoResize
        + Lib.imgui.WindowFlags.NoScrollbar
        + Lib.imgui.WindowFlags.NoScrollWithMouse
        + Lib.imgui.WindowFlags.NoBackground
        + (ui.move[0] and 0 or Lib.imgui.WindowFlags.NoMove)
   Lib.imgui.Begin('##keyboard', nil, kb_flags)
        if Data.force_keyboard_pos_once then
            Data.force_keyboard_pos_once = false
        end
        ui.keyboard_pos = Lib.imgui.GetWindowPos()
       Data.wave_draw_list_ref = Lib.imgui.GetWindowDrawList()
        local comboVisualsActive = st.current_combo ~= nil
        for row_i, line in ipairs(keyboards[1]) do
            for col_i, v in ipairs(line) do
                if v.space then goto continue_kb_key end
                local keyName   = (v.space and u8"ПРОБЕЛ") or v[1]
                local spaceLabel = v.space and (ui.space_as_shift[0] and "SHIFT" or u8"ПРОБЕЛ") or nil
                local text      = Fn.getLocalizedName(spaceLabel or keyName)
                local keyCode   = v.space and Fn.getSpaceCode() or v[2]
                local numeric_text_color, is_numeric_text
                text, numeric_text_color, is_numeric_text = Fn.KS.display_text(keyCode, text)
                local size      = Lib.imgui.CalcTextSize(text)
                local isPressed = Fn.isPhysicalKeyDown(keyCode)
                local scale     = (isPressed and 1.1 or 1.0) * ui.keyboard_scale[0]
                local base_fill   = Fn.computePulsedColor(ui.key_fill_color,   ui.key_fill_rgb[0],   ui.rgb_speed[0])
                local base_border = Fn.computePulsedColor(ui.key_border_color, ui.key_border_rgb[0], ui.rgb_speed[0])
                local base_text_c = Fn.computePulsedColor(ui.key_text_color,   ui.key_text_rgb[0],   ui.rgb_speed[0])
                local final_fill_alpha   = (base_fill[4]   or 1) * ui.keyboard_key_alpha[0]
                local final_border_alpha = (base_border[4] or 1) * ui.keyboard_key_alpha[0]
                local final_text_alpha   = (base_text_c[4] or 1) * ui.text_alpha[0]
                local buttonColor = { base_fill[1], base_fill[2], base_fill[3], final_fill_alpha }
                if isPressed and ui.pressed_fill_enabled[0] then
                    buttonColor = { ui.pressed_fill_color[1], ui.pressed_fill_color[2], ui.pressed_fill_color[3], ui.pressed_fill_color[4] * ui.keyboard_key_alpha[0] }
                end
                local stateColor, stateIdx = Fn.getKeyStateColor(keyName, comboVisualsActive, keyCode)
                local isHeldState = (stateIdx and st.key_states and st.key_states[stateIdx] == S.KEY_COLORS.HELD)
                if stateColor then
                    buttonColor = stateColor
                end
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ChildBg, Lib.imgui.ImVec4(0, 0, 0, 0))
                local base_width  = v.space and (ui.space_as_shift[0] and math.floor(S.cfg.keyboard.space_width / 2) or S.cfg.keyboard.space_width) or S.cfg.keyboard.key_width
                local base_height = v.space and S.cfg.keyboard.space_height or S.cfg.keyboard.key_height
                local width  = base_width  * scale
                local height = base_height * scale
                if v[1] == "C" then
                   Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(
                       Lib.imgui.GetCursorPosX() + Data.c_pos_x[0] * ui.keyboard_scale[0],
                       Lib.imgui.GetCursorPosY() + Data.c_pos_y[0] * ui.keyboard_scale[0]
                    ))
                elseif v.space then
                   Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(
                       Lib.imgui.GetCursorPosX() + Data.space_pos_x[0] * ui.keyboard_scale[0],
                       Lib.imgui.GetCursorPosY() + Data.space_pos_y[0] * ui.keyboard_scale[0]
                    ))
                end
                local p         = Lib.imgui.GetCursorScreenPos()
                local draw_list = Lib.imgui.GetWindowDrawList()
                if ui.wave_enabled[0] then
                    table.insert(Data.wave_keys_list, {
                        min = Lib.imgui.ImVec2(p.x + 1, p.y + 1),
                        max = Lib.imgui.ImVec2(p.x + width - 1, p.y + height - 1)
                    })
                end
                draw_list:AddRectFilled(
                   Lib.imgui.ImVec2(p.x + 1, p.y + 1),
                   Lib.imgui.ImVec2(p.x + width - 1, p.y + height - 1),
                   Fn.getColorU32(buttonColor[1], buttonColor[2], buttonColor[3], buttonColor[4], true),
                    6
                )
                if isHeldState then
                    local now_t   = os.clock()
                    local reqTime = st.hold_durations[stateIdx] or S.state.DEFAULT_HOLD_TIME
                    local progress = 0
                    if st.hold_start_times[stateIdx] then
                        progress = math.min(1, (now_t - st.hold_start_times[stateIdx]) / reqTime)
                    end
                    if progress > 0 then
                        local pw = math.max(0, (width - 2) * progress)
                        draw_list:AddRectFilled(
                           Lib.imgui.ImVec2(p.x + 1, p.y + 1),
                           Lib.imgui.ImVec2(p.x + 1 + pw, p.y + height - 1),
                           Fn.getColorU32(ui.held_color[1], ui.held_color[2], ui.held_color[3],
                                (ui.held_color[4] or 1) * ui.keyboard_key_alpha[0], true),
                            6
                        )
                    end
                end
                local b_mode = ui.border_mode[0]
                local should_draw_border = (b_mode == 2) or (b_mode == 3 and isPressed)
                if should_draw_border then
                    local borderCol = { base_border[1], base_border[2], base_border[3], final_border_alpha }
                    if isPressed and ui.pressed_border_enabled[0] then
                        borderCol = { ui.pressed_border_color[1], ui.pressed_border_color[2], ui.pressed_border_color[3], ui.pressed_border_color[4] * ui.keyboard_key_alpha[0] }
                    end
                    draw_list:AddRect(
                       Lib.imgui.ImVec2(p.x, p.y),
                       Lib.imgui.ImVec2(p.x + width, p.y + height),
                       Fn.getColorU32(borderCol[1], borderCol[2], borderCol[3], borderCol[4], true),
                        6, nil, Data.border_thickness[0] * ui.keyboard_scale[0]
                    )
                end
               Lib.imgui.BeginChild('##kb_' .. row_i .. '_' .. col_i, Lib.imgui.ImVec2(width, height), false)
                    local text_pos = Lib.imgui.ImVec2(
                        math.floor((width - size.x) / 2 + 0.5),
                        math.floor((height - size.y) / 2 + 0.5)
                    )
                   Lib.imgui.SetCursorPos(text_pos)
                    local text_rgba = {base_text_c[1], base_text_c[2], base_text_c[3], final_text_alpha}
                    if is_numeric_text then
                        if numeric_text_color then text_rgba = numeric_text_color end
                    else
                        if isPressed and ui.pressed_text_enabled[0] then
                            text_rgba = {ui.pressed_text_color[1], ui.pressed_text_color[2], ui.pressed_text_color[3], ui.pressed_text_color[4] * ui.text_alpha[0]}
                        end
                        text_rgba = Fn.applyWaveText(text_rgba, p.x + 1, p.y + 1)
                    end
                    local text_col_final = Lib.imgui.ImVec4(text_rgba[1], text_rgba[2], text_rgba[3], text_rgba[4])
                   Lib.imgui.TextColored(text_col_final, text)
               Lib.imgui.EndChild()
               Lib.imgui.PopStyleColor()
                if col_i ~= #line then Lib.imgui.SameLine() end
                ::continue_kb_key::
            end
           Lib.imgui.NewLine()
        end
   Lib.imgui.End()
   Lib.imgui.PopStyleColor(3)
end
Data.wave_draw_list_ref = nil
local function scaled_layout_pos(base_pos, anchor_pos, scale)
    scale = tonumber(scale) or 1.0
    return Lib.imgui.ImVec2(
        anchor_pos.x + (base_pos.x - anchor_pos.x) * scale,
        anchor_pos.y + (base_pos.y - anchor_pos.y) * scale
    )
end
Fn.RenderSpaceKey = function()
    local st = S.state
   Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg,     Lib.imgui.ImVec4(0, 0, 0, 0))
   Lib.imgui.PushStyleColor(Lib.imgui.Col.Border,       Lib.imgui.ImVec4(0, 0, 0, 0))
   Lib.imgui.PushStyleColor(Lib.imgui.Col.BorderShadow, Lib.imgui.ImVec4(0, 0, 0, 0))
    local scale = ui.keyboard_scale[0] or 1.0
    local offset_x = (tonumber(Data.space_pos_x[0]) or 0.0) * scale
    local offset_y = (tonumber(Data.space_pos_y[0]) or 0.0) * scale
    local space_base_scaled = scaled_layout_pos(ui.space_pos, ui.keyboard_pos, scale)
    local space_window_pos = Lib.imgui.ImVec2(
        space_base_scaled.x + offset_x,
        space_base_scaled.y + offset_y
    )
    if ui.move[0] then
        local io = Lib.imgui.GetIO()
        local mx, my = io.MousePos.x, io.MousePos.y
        local hovered_space = mx >= space_window_pos.x and mx <= (space_window_pos.x + (S.cfg.keyboard.space_width * scale))
            and my >= space_window_pos.y and my <= (space_window_pos.y + (S.cfg.keyboard.space_height * scale))
        if hovered_space and Lib.imgui.IsMouseClicked(0) then
            ui.space_dragging = true
            ui.space_drag_offset.x = mx - space_window_pos.x
            ui.space_drag_offset.y = my - space_window_pos.y
        end
        if ui.space_dragging then
            if Lib.imgui.IsMouseDown(0) then
                local new_window_x = mx - ui.space_drag_offset.x
                local new_window_y = my - ui.space_drag_offset.y
                local kb = ui.keyboard_pos
                local safe_scale = math.max(0.001, scale)
                ui.space_pos.x = kb.x + ((new_window_x - kb.x - offset_x) / safe_scale)
                ui.space_pos.y = kb.y + ((new_window_y - kb.y - offset_y) / safe_scale)
                space_window_pos = Lib.imgui.ImVec2(new_window_x, new_window_y)
            else
                ui.space_dragging = false
                S.cfg.space.x = ui.space_pos.x
                S.cfg.space.y = ui.space_pos.y
                pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
            end
        end
    else
        ui.space_dragging = false
    end
    Lib.imgui.SetNextWindowPos(space_window_pos, Lib.imgui.Cond.Always, Lib.imgui.ImVec2(0, 0))
    local sp_flags = Lib.imgui.WindowFlags.NoResize
        + Lib.imgui.WindowFlags.NoTitleBar
        + Lib.imgui.WindowFlags.AlwaysAutoResize
        + Lib.imgui.WindowFlags.NoScrollbar
        + Lib.imgui.WindowFlags.NoScrollWithMouse
        + Lib.imgui.WindowFlags.NoBackground
        + (ui.move[0] and 0 or Lib.imgui.WindowFlags.NoMove)
   Lib.imgui.Begin('##spacekey', nil, sp_flags)
        local keyName   = u8"ПРОБЕЛ"
        local keyCode   = Fn.getSpaceCode()
        local label     = ui.space_as_shift[0] and "SHIFT" or Fn.getLocalizedName(keyName)
        local numeric_text_color, is_numeric_text
        label, numeric_text_color, is_numeric_text = Fn.KS.display_text(keyCode, label)
        local isPressed = Fn.isPhysicalKeyDown(keyCode)
        local scale     = (isPressed and 1.1 or 1.0) * ui.keyboard_scale[0]
        local base_fill   = Fn.computePulsedColor(ui.key_fill_color,   ui.key_fill_rgb[0],   ui.rgb_speed[0])
        local base_border = Fn.computePulsedColor(ui.key_border_color, ui.key_border_rgb[0], ui.rgb_speed[0])
        local base_text_c = Fn.computePulsedColor(ui.key_text_color,   ui.key_text_rgb[0],   ui.rgb_speed[0])
        local final_fill_alpha   = (base_fill[4]   or 1) * ui.keyboard_key_alpha[0]
        local final_border_alpha = (base_border[4] or 1) * ui.keyboard_key_alpha[0]
        local final_text_alpha   = (base_text_c[4] or 1) * ui.text_alpha[0]
        local buttonColor = { base_fill[1], base_fill[2], base_fill[3], final_fill_alpha }
        if isPressed and ui.pressed_fill_enabled[0] then
            buttonColor = { ui.pressed_fill_color[1], ui.pressed_fill_color[2], ui.pressed_fill_color[3], ui.pressed_fill_color[4] * ui.keyboard_key_alpha[0] }
        end
        local comboVisualsActive = st.current_combo ~= nil
        local stateColor, stateIdx = Fn.getKeyStateColor(keyName, comboVisualsActive, keyCode)
        local isHeldState = (stateIdx and st.key_states and st.key_states[stateIdx] == S.KEY_COLORS.HELD)
        if stateColor then buttonColor = stateColor end
        local base_w  = ui.space_as_shift[0] and math.floor(S.cfg.keyboard.space_width / 2) or S.cfg.keyboard.space_width
        local base_h  = S.cfg.keyboard.space_height
        local width   = base_w * scale
        local height  = base_h * scale
        local p         = Lib.imgui.GetCursorScreenPos()
        local draw_list = Lib.imgui.GetWindowDrawList()
        if ui.wave_enabled[0] then
            table.insert(Data.wave_keys_list, {
                min = Lib.imgui.ImVec2(p.x + 1, p.y + 1),
                max = Lib.imgui.ImVec2(p.x + width - 1, p.y + height - 1)
            })
        end
        draw_list:AddRectFilled(
           Lib.imgui.ImVec2(p.x + 1, p.y + 1),
           Lib.imgui.ImVec2(p.x + width - 1, p.y + height - 1),
           Fn.getColorU32(buttonColor[1], buttonColor[2], buttonColor[3], buttonColor[4], true), 6
        )
        if isHeldState then
            local now_t   = os.clock()
            local reqTime = st.hold_durations[stateIdx] or S.state.DEFAULT_HOLD_TIME
            local progress = 0
            if st.hold_start_times[stateIdx] then
                progress = math.min(1, (now_t - st.hold_start_times[stateIdx]) / reqTime)
            end
            if progress > 0 then
                local pw = math.max(0, (width - 2) * progress)
                draw_list:AddRectFilled(
                   Lib.imgui.ImVec2(p.x + 1, p.y + 1),
                   Lib.imgui.ImVec2(p.x + 1 + pw, p.y + height - 1),
                   Fn.getColorU32(ui.held_color[1], ui.held_color[2], ui.held_color[3],
                        (ui.held_color[4] or 1) * ui.keyboard_key_alpha[0], true), 6
                )
            end
        end
        local b_mode = ui.border_mode[0]
        if (b_mode == 2) or (b_mode == 3 and isPressed) then
            local borderCol = { base_border[1], base_border[2], base_border[3], final_border_alpha }
            if isPressed and ui.pressed_border_enabled[0] then
                borderCol = { ui.pressed_border_color[1], ui.pressed_border_color[2], ui.pressed_border_color[3], ui.pressed_border_color[4] * ui.keyboard_key_alpha[0] }
            end
            draw_list:AddRect(
               Lib.imgui.ImVec2(p.x, p.y), Lib.imgui.ImVec2(p.x + width, p.y + height),
               Fn.getColorU32(borderCol[1], borderCol[2], borderCol[3], borderCol[4], true),
                6, nil, Data.border_thickness[0] * ui.keyboard_scale[0]
            )
        end
       Lib.imgui.PushStyleColor(Lib.imgui.Col.ChildBg, Lib.imgui.ImVec4(0, 0, 0, 0))
       Lib.imgui.BeginChild('##sp_inner', Lib.imgui.ImVec2(width, height), false)
            local size     = Lib.imgui.CalcTextSize(label)
            local text_pos = Lib.imgui.ImVec2(
                math.floor((width - size.x) / 2 + 0.5),
                math.floor((height - size.y) / 2 + 0.5)
            )
           Lib.imgui.SetCursorPos(text_pos)
            local text_rgba = {base_text_c[1], base_text_c[2], base_text_c[3], final_text_alpha}
            if is_numeric_text then
                if numeric_text_color then text_rgba = numeric_text_color end
            else
                if isPressed and ui.pressed_text_enabled[0] then
                    text_rgba = {ui.pressed_text_color[1], ui.pressed_text_color[2], ui.pressed_text_color[3], ui.pressed_text_color[4] * ui.text_alpha[0]}
                end
                text_rgba = Fn.applyWaveText(text_rgba, p.x + 1, p.y + 1)
            end
            local text_col_final = Lib.imgui.ImVec4(text_rgba[1], text_rgba[2], text_rgba[3], text_rgba[4])
           Lib.imgui.TextColored(text_col_final, label)
       Lib.imgui.EndChild()
       Lib.imgui.PopStyleColor()
   Lib.imgui.End()
   Lib.imgui.PopStyleColor(3)
end
Data.wave_text_glow = {}
 Fn.waveKeyId = function(x, y)
    return math.floor(x / 4) .. ":" .. math.floor(y / 4)
end
 Fn.applyWaveText = function(col, x, y)
    if not ui.wave_enabled[0] then return col end
    local tgt = ui.wave_target[0] or 1
    if tgt ~= 3 and tgt ~= 4 then return col end
    local g = Data.wave_text_glow[Fn.waveKeyId(x, y)]
    if not g then return col end
    local t = math.max(0, math.min(1, g[4] or 0))
    return {
        col[1] + (g[1] - col[1]) * t,
        col[2] + (g[2] - col[2]) * t,
        col[3] + (g[3] - col[3]) * t,
        col[4],
    }
end
 Fn.RenderWave = function()
    if not ui.wave_enabled[0] or #Data.wave_keys_list == 0 then
       Data.wave_text_glow = {}
        return
    end
    local wdl = Lib.imgui.GetForegroundDrawList()
    if not wdl then return end
    local wr  = Data.wave_color[1]; local wg2 = Data.wave_color[2]
    local wb2 = Data.wave_color[3]; local wa  = ui.wave_transparency[0]
    local tail = math.max(1, math.floor(#Data.wave_keys_list * 0.3))
    local head = math.floor(Data.wave_key_index)
    local wm   = ui.wave_mode[0]
    local sorted = {}
    for i = 1, #Data.wave_keys_list do sorted[i] = Data.wave_keys_list[i] end
    if wm == 1 then
        table.sort(sorted, function(a, b)
            local dy = a.min.y - b.min.y
            if math.abs(dy) > 5 then return dy < 0 end
            return a.min.x < b.min.x
        end)
    elseif wm == 2 then
        table.sort(sorted, function(a, b)
            local dy = a.min.y - b.min.y
            if math.abs(dy) > 5 then return dy < 0 end
            return a.min.x > b.min.x
        end)
    elseif wm == 3 then
        table.sort(sorted, function(a, b)
            local dx = a.min.x - b.min.x
            if math.abs(dx) > 5 then return dx < 0 end
            return a.min.y < b.min.y
        end)
    elseif wm == 4 then
        table.sort(sorted, function(a, b)
            local dx = a.min.x - b.min.x
            if math.abs(dx) > 5 then return dx < 0 end
            return a.min.y > b.min.y
        end)
    end
    local sw2, sh2 = getScreenResolution()
    wdl:PushClipRect(Lib.imgui.ImVec2(0, 0), Lib.imgui.ImVec2(sw2, sh2), false)
    local target = ui.wave_target[0] or 1
    local glow_next = {}
    for t = 0, tail - 1 do
        local ki = head - t
        if ki >= 1 and ki <= #sorted then
            local alpha_f = (tail - t) / tail
            local r = sorted[ki]
            local kr, kg, kb = wr, wg2, wb2
            if ui.wave_random_colors[0] then
                local seed = ki * 12.9898 + (Data.wave_cycle or 0) * 78.233
                local x = math.sin(seed) * 43758.5453
                local hue = x - math.floor(x)
                kr, kg, kb = Fn.hsv_to_rgb(hue, 1, 1)
            end
            local col_fill   = Fn.getColorU32(kr, kg, kb, wa * alpha_f, true)
            local col_border = Fn.getColorU32(kr, kg, kb, math.min(1, wa * alpha_f * 1.4), true)
            if target == 1 then
                wdl:AddRectFilled(r.min, r.max, col_fill, 6)
            elseif target == 2 then
                wdl:AddRect(r.min, r.max, col_border, 6, 15, 2.0)
            elseif target == 3 then
                glow_next[Fn.waveKeyId(r.min.x, r.min.y)] = {kr, kg, kb, wa * alpha_f}
            else
                wdl:AddRectFilled(r.min, r.max, col_fill, 6)
                wdl:AddRect(r.min, r.max, col_border, 6, 15, 2.0)
                glow_next[Fn.waveKeyId(r.min.x, r.min.y)] = {kr, kg, kb, wa * alpha_f}
            end
        end
    end
    wdl:PopClipRect()
   Data.wave_text_glow = glow_next
end
 Fn.RenderMouse = function()
    Fn.KS.refresh_display_counts()
    local st = S.state
   Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg,     Lib.imgui.ImVec4(0, 0, 0, 0))
   Lib.imgui.PushStyleColor(Lib.imgui.Col.Border,       Lib.imgui.ImVec4(0, 0, 0, 0))
   Lib.imgui.PushStyleColor(Lib.imgui.Col.BorderShadow, Lib.imgui.ImVec4(0, 0, 0, 0))
   local scale = ui.keyboard_scale[0] or 1.0
   local mouse_scaled_pos = scaled_layout_pos(ui.mouse_pos, ui.keyboard_pos, scale)
   local scale_changed = (Data._mouse_layout_scale == nil) or (math.abs((Data._mouse_layout_scale or 1.0) - scale) > 0.0001)
   local mouse_pos_cond = (Data.mouse_force_pos_once or scale_changed) and Lib.imgui.Cond.Always or Lib.imgui.Cond.FirstUseEver
   Lib.imgui.SetNextWindowPos(mouse_scaled_pos, mouse_pos_cond, Lib.imgui.ImVec2(0, 0))
   Data.mouse_force_pos_once = false
   Data._mouse_layout_scale = scale
    local mouse_flags = Lib.imgui.WindowFlags.NoResize
        + Lib.imgui.WindowFlags.NoTitleBar
        + Lib.imgui.WindowFlags.AlwaysAutoResize
        + Lib.imgui.WindowFlags.NoScrollbar
        + Lib.imgui.WindowFlags.NoScrollWithMouse
        + Lib.imgui.WindowFlags.NoBackground
        + (ui.move[0] and 0 or Lib.imgui.WindowFlags.NoMove)
   Lib.imgui.Begin('##mouse', nil, mouse_flags)
        local mouse_actual_pos = Lib.imgui.GetWindowPos()
        local kb = ui.keyboard_pos
        local safe_scale = math.max(0.001, scale)
        ui.mouse_pos = Lib.imgui.ImVec2(
            kb.x + (mouse_actual_pos.x - kb.x) / safe_scale,
            kb.y + (mouse_actual_pos.y - kb.y) / safe_scale
        )
        Data.mouse_pos_x[0] = mouse_actual_pos.x
        Data.mouse_pos_y[0] = mouse_actual_pos.y
        if not Data.wave_draw_list_ref then
           Data.wave_draw_list_ref = Lib.imgui.GetWindowDrawList()
        end
        local mouse_buttons = {
            {text = u8'ЛКМ',    key = 0x01, width = S.cfg.mouse.lmb_width,  height = S.cfg.mouse.lmb_height},
            {text = u8'ПКМ',    key = 0x02, width = S.cfg.mouse.rmb_width,  height = S.cfg.mouse.rmb_height, close_gap = true},
        }
        local comboVisualsActive = st.current_combo ~= nil
        for i, btn in ipairs(mouse_buttons) do
            local localized_text = Fn.getLocalizedName(btn.text)
            local numeric_text_color, is_numeric_text
            localized_text, numeric_text_color, is_numeric_text = Fn.KS.display_text(btn.key, localized_text)
            local size      = Lib.imgui.CalcTextSize(localized_text)
            local isPressed = Fn.isPhysicalKeyDown(btn.key)
            local scale     = (isPressed and 1.1 or 1.0) * ui.keyboard_scale[0]
            local base_fill   = Fn.computePulsedColor(ui.key_fill_color,   ui.key_fill_rgb[0],   ui.rgb_speed[0])
            local base_border = Fn.computePulsedColor(ui.key_border_color, ui.key_border_rgb[0], ui.rgb_speed[0])
            local base_text_c = Fn.computePulsedColor(ui.key_text_color,   ui.key_text_rgb[0],   ui.rgb_speed[0])
            local final_fill_alpha   = (base_fill[4]   or 1) * ui.keyboard_key_alpha[0]
            local final_border_alpha = (base_border[4] or 1) * ui.keyboard_key_alpha[0]
            local final_text_alpha   = (base_text_c[4] or 1) * ui.text_alpha[0]
            local buttonColor = { base_fill[1], base_fill[2], base_fill[3], final_fill_alpha }
            local stateColor, stateIdx = Fn.getKeyStateColor(btn.text, comboVisualsActive, btn.key)
            local isHeldState = (stateIdx and st.key_states and st.key_states[stateIdx] == S.KEY_COLORS.HELD)
            if stateColor then
                buttonColor = stateColor
            elseif isPressed and ui.pressed_fill_enabled[0] then
                buttonColor = { ui.pressed_fill_color[1], ui.pressed_fill_color[2], ui.pressed_fill_color[3], ui.pressed_fill_color[4] * ui.keyboard_key_alpha[0] }
            end
           Lib.imgui.PushStyleColor(Lib.imgui.Col.ChildBg, Lib.imgui.ImVec4(0, 0, 0, 0))
            local width  = btn.width  * scale
            local height = btn.height * scale
            local p         = Lib.imgui.GetCursorScreenPos()
            local draw_list = Lib.imgui.GetWindowDrawList()
            if ui.wave_enabled[0] then
                table.insert(Data.wave_keys_list, {
                    min = Lib.imgui.ImVec2(p.x + 1, p.y + 1),
                    max = Lib.imgui.ImVec2(p.x + width - 1, p.y + height - 1)
                })
            end
            draw_list:AddRectFilled(
               Lib.imgui.ImVec2(p.x + 1, p.y + 1),
               Lib.imgui.ImVec2(p.x + width - 1, p.y + height - 1),
               Fn.getColorU32(buttonColor[1], buttonColor[2], buttonColor[3], buttonColor[4], true),
                6
            )
            if isHeldState then
                local now_t   = os.clock()
                local reqTime = st.hold_durations[stateIdx] or S.state.DEFAULT_HOLD_TIME
                local progress = 0
                if st.hold_start_times[stateIdx] then
                    progress = math.min(1, (now_t - st.hold_start_times[stateIdx]) / reqTime)
                end
                if progress > 0 then
                    local pw = math.max(0, (width - 2) * progress)
                    draw_list:AddRectFilled(
                       Lib.imgui.ImVec2(p.x + 1, p.y + 1),
                       Lib.imgui.ImVec2(p.x + 1 + pw, p.y + height - 1),
                       Fn.getColorU32(ui.held_color[1], ui.held_color[2], ui.held_color[3],
                            (ui.held_color[4] or 1) * ui.keyboard_key_alpha[0], true),
                        6
                    )
                end
            end
            local should_draw_border = (ui.border_mode[0] == 2) or (ui.border_mode[0] == 3 and isPressed)
            if should_draw_border then
                local borderCol = { base_border[1], base_border[2], base_border[3], final_border_alpha }
                if isPressed and ui.pressed_border_enabled[0] then
                    borderCol = { ui.pressed_border_color[1], ui.pressed_border_color[2], ui.pressed_border_color[3], ui.pressed_border_color[4] * ui.keyboard_key_alpha[0] }
                end
                draw_list:AddRect(
                   Lib.imgui.ImVec2(p.x, p.y),
                   Lib.imgui.ImVec2(p.x + width, p.y + height),
                   Fn.getColorU32(borderCol[1], borderCol[2], borderCol[3], borderCol[4], true),
                    6, nil, Data.border_thickness[0] * ui.keyboard_scale[0]
                )
            end
           Lib.imgui.BeginChild('##m' .. i, Lib.imgui.ImVec2(width, height), false)
                local text_pos = Lib.imgui.ImVec2((width - size.x) / 2, (height - size.y) / 2)
               Lib.imgui.SetCursorPos(text_pos)
                local mouse_text_rgba = {base_text_c[1], base_text_c[2], base_text_c[3], final_text_alpha}
                if is_numeric_text then
                    if numeric_text_color then mouse_text_rgba = numeric_text_color end
                else
                    if isPressed and ui.pressed_text_enabled[0] then
                        mouse_text_rgba = {ui.pressed_text_color[1], ui.pressed_text_color[2], ui.pressed_text_color[3], ui.pressed_text_color[4] * ui.text_alpha[0]}
                    end
                    mouse_text_rgba = Fn.applyWaveText(mouse_text_rgba, p.x + 1, p.y + 1)
                end
                local mouse_text_col = Lib.imgui.ImVec4(mouse_text_rgba[1], mouse_text_rgba[2], mouse_text_rgba[3], mouse_text_rgba[4])
               Lib.imgui.TextColored(mouse_text_col, localized_text)
           Lib.imgui.EndChild()
           Lib.imgui.PopStyleColor()
            local nextBtn = mouse_buttons[i + 1]
            if nextBtn and not nextBtn.newline_before then
                local gap = fixed_mouse_gap()
                Lib.imgui.SameLine(0, gap)
            end
        end
   Lib.imgui.End()
   Lib.imgui.PopStyleColor(3)
end
 Fn.RenderLogsWindow = function()
    if not ui.show_logs[0] then return end
    Lib.imgui.SetNextWindowPos(ui.logs_pos, Lib.imgui.Cond.Always)
    Lib.imgui.SetNextWindowSize(ui.logs_size, Lib.imgui.Cond.Always)
    local io = Lib.imgui.GetIO()
    local tc = neon_fx.tabs_color
    local cc = neon_fx.icon_cross_color
    local rc = neon_fx.icon_resize_color
    local wb = Data.neon_active_colors[Lib.imgui.Col.WindowBg] or {0.04, 0.04, 0.07, 0.97}
    local text_col = Data.neon_active_colors[Lib.imgui.Col.Text] or {1,1,1,1}
    local title_col = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or text_col
    Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg, Lib.imgui.ImVec4(0,0,0,0))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(0,0,0,0))
    if Lib.imgui.Col.BorderShadow then
        Lib.imgui.PushStyleColor(Lib.imgui.Col.BorderShadow, Lib.imgui.ImVec4(0,0,0,0))
    end
    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.Alpha, ui.interface_alpha[0])
    Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(0,0))
    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowRounding, 20)
    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowBorderSize, 0)
    local flags = Lib.imgui.WindowFlags.NoTitleBar
        + Lib.imgui.WindowFlags.NoCollapse
        + Lib.imgui.WindowFlags.NoScrollbar
    local opened = Lib.imgui.Begin(Fn.T(u8"Логи нажатий##logwin"), ui.show_logs, flags)
    Lib.imgui.PopStyleVar(3)
    if Lib.imgui.Col.BorderShadow then Lib.imgui.PopStyleColor() end
    Lib.imgui.PopStyleColor(2)
    if not opened then
        Lib.imgui.End()
        Lib.imgui.PopStyleVar()
        return
    end
    local dl0 = Lib.imgui.GetWindowDrawList()
    local pos0 = Lib.imgui.GetWindowPos()
    local size0 = Lib.imgui.GetWindowSize()
    local p0_min = pos0
    local p0_max = Lib.imgui.ImVec2(pos0.x + size0.x, pos0.y + size0.y)
    local bg0 = Data.nfn.pack_color(wb[1], wb[2], wb[3], wb[4] or 0.97, true, ui.interface_alpha[0])
    dl0:AddRectFilled(p0_min, p0_max, bg0, 20)
    Data.nfn.draw_police_ambient(dl0, p0_min, p0_max, ui.interface_alpha[0])
    Data.nfn.draw_neon_border(dl0, p0_min, p0_max, ui.interface_alpha[0])
    local title_pos0 = Lib.imgui.ImVec2(p0_min.x + 10, p0_min.y + 5)
    Lib.imgui.SetCursorScreenPos(title_pos0)
    Lib.imgui.InvisibleButton('##log_drag', Lib.imgui.ImVec2(math.max(120, size0.x - 82), 24))
    local drag_hovered0 = Lib.imgui.IsItemHovered()
    local mp0 = io.MousePos
    if drag_hovered0 and Lib.imgui.IsItemClicked(0) then
        ui.logs_dragging = true
        ui.logs_drag_offset = ui.logs_drag_offset or {x=0,y=0}
        ui.logs_drag_offset.x = mp0.x - pos0.x
        ui.logs_drag_offset.y = mp0.y - pos0.y
    end
    if ui.logs_dragging then
        if Lib.imgui.IsMouseDown(0) then
            ui.logs_pos.x = mp0.x - ui.logs_drag_offset.x
            ui.logs_pos.y = mp0.y - ui.logs_drag_offset.y
        else
            ui.logs_dragging = false
        end
    end
    if drag_hovered0 or ui.logs_dragging then Data.nfn.set_hand_cursor() end
    dl0:AddText(title_pos0, Data.nfn.pack_color(title_col[1], title_col[2], title_col[3], 1, false, ui.interface_alpha[0]), Fn.T(u8"Логи нажатий"))
    local close_p0 = Lib.imgui.ImVec2(p0_max.x - 24, p0_min.y + 22)
    Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(close_p0.x - 14, close_p0.y - 14))
    if Lib.imgui.InvisibleButton('##log_close_rebuilt', Lib.imgui.ImVec2(28, 28)) then
        ui.show_logs[0] = false
    end
    Data.nfn.draw_cross(dl0, close_p0, 12, Lib.imgui.IsItemHovered(), ui.interface_alpha[0])
    Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(p0_min.x + 10, p0_min.y + 34))
    ui.logs_size.x = size0.x; ui.logs_size.y = size0.y
    local log_push = 0
    if opened then
        local wsize = Lib.imgui.GetWindowSize()
        ui.logs_size.x = wsize.x; ui.logs_size.y = wsize.y
        local _ltxt = Data.neon_active_colors[Lib.imgui.Col.Text] or {1.0, 1.0, 1.0, 1.0}
       Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(_ltxt[1],_ltxt[2],_ltxt[3],_ltxt[4] or 1.0)); local content_push = 1
        local function renderLogsToolbar()
        Data.nfn.PushButtonBorder()
        if Lib.imgui.Button(Fn.T(u8"Очистить"), Lib.imgui.ImVec2(90, 22)) then
            S.log_buffer = {}
        end
        Data.nfn.PopButtonBorder()
       Lib.imgui.SameLine()
        local ldm = ui.logs_display_mode[0]
        local _lba  = Data.neon_active_colors[Lib.imgui.Col.Button]       or {0.2,0.2,0.2,0.9}
        local _lba_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.4,0.4,0.4,1.0}
        local _lact = Lib.imgui.ImVec4(_lba_a[1],_lba_a[2],_lba_a[3],_lba_a[4] or 1.0)
        if ldm == 1 then Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, _lact) end
        Data.nfn.PushButtonBorder()
        if Lib.imgui.Button(Fn.T(u8"Текст##lwm"), Lib.imgui.ImVec2(55, 22)) then
            ui.logs_display_mode[0] = 1; S.cfg.config.logs_display_mode = 1; Lib.inicfg.save(S.cfg, Data.iniFile)
        end
        Data.nfn.PopButtonBorder()
        if ldm == 1 then Lib.imgui.PopStyleColor() end
       Lib.imgui.SameLine()
        local ldm2 = ui.logs_display_mode[0]
        if ldm2 == 2 then Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, _lact) end
        Data.nfn.PushButtonBorder()
        if Lib.imgui.Button(Fn.T(u8"Плашки##lwm"), Lib.imgui.ImVec2(55, 22)) then
            ui.logs_display_mode[0] = 2; S.cfg.config.logs_display_mode = 2; Lib.inicfg.save(S.cfg, Data.iniFile)
        end
        Data.nfn.PopButtonBorder()
        if ldm2 == 2 then Lib.imgui.PopStyleColor() end
       Lib.imgui.SameLine()
        local lrev = ui.logs_reverse[0]
        if lrev then Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, _lact) end
        Data.nfn.PushButtonBorder()
        if Lib.imgui.Button("< >##lrev", Lib.imgui.ImVec2(30, 22)) then
            ui.logs_reverse[0] = not lrev
            S.cfg.config.logs_reverse = ui.logs_reverse[0]
           Lib.inicfg.save(S.cfg, Data.iniFile)
        end
        Data.nfn.PopButtonBorder()
        if lrev then Lib.imgui.PopStyleColor() end
       Lib.imgui.SameLine()
        do local _ltxt3 = Data.neon_active_colors[Lib.imgui.Col.Text] or {1.0,1.0,1.0,1.0}
       Lib.imgui.TextColored(Lib.imgui.ImVec4(_ltxt3[1],_ltxt3[2],_ltxt3[3],(_ltxt3[4] or 1.0)*0.7), Fn.T(u8"(" .. #S.log_buffer .. ")"))
        end
       Lib.imgui.Separator()
        end
       renderLogsToolbar()
       Lib.imgui.Spacing()
       Lib.imgui.SetCursorPosX(Lib.imgui.GetCursorPosX() + 4)
       Lib.imgui.BeginChild("##log_badges", Lib.imgui.ImVec2(-4, 0), false)
        local dl          = Lib.imgui.GetWindowDrawList()
        local limit       = math.max(1, ui.logs_limit_row[0])
        local max_display = math.max(1, ui.logs_max_display[0])
        local badge_pad_x = 6
        local badge_gap   = 4
        local text_h      = Lib.imgui.CalcTextSize("A").y
        local badge_h     = text_h + 6
        local row_h       = badge_h + 6
        local visible_logs = {}
        for i = 1, math.min(max_display, #S.log_buffer) do
            visible_logs[i] = S.log_buffer[i]
        end
        local function renderLogsTextMode()
            local log_scale = math.max(0.5, ui.keyboard_scale[0])
            local text_gap = math.max(4, math.floor(4 * log_scale + 0.5))
            local content_x = Lib.imgui.GetCursorScreenPos().x + 4
            local avail_w = math.max(1, Lib.imgui.GetContentRegionAvail().x - 4)
            local row_limit = math.max(1, ui.logs_limit_row[0])
            local packed_rows = {}
            local current_row = {}
            local current_w = 0
            local function flush_text_row()
                if #current_row == 0 then return end
                packed_rows[#packed_rows + 1] = current_row
                current_row = {}
                current_w = 0
            end
            for _, log in ipairs(visible_logs) do
                local txt = Fn.getLocalizedName(log.name)
                local tsz = Lib.imgui.CalcTextSize(txt)
                                                local slot_w = tsz.x
                local next_w = (#current_row > 0) and (current_w + text_gap + slot_w) or slot_w
                if #current_row > 0 and (#current_row >= row_limit or next_w > avail_w) then
                    flush_text_row()
                end
                current_row[#current_row + 1] = { log = log, txt = txt, slot_w = slot_w, tsz = tsz }
                current_w = current_w + (#current_row > 1 and text_gap or 0) + slot_w
            end
            flush_text_row()
            for _, row in ipairs(packed_rows) do
               Lib.imgui.Spacing()
                local row_n = #row
                for ri2 = 1, row_n do
                    local item = ui.logs_reverse[0] and row[row_n - ri2 + 1] or row[ri2]
                    if ri2 > 1 then Lib.imgui.SameLine(0, text_gap) end
                    if ri2 == 1 then
                       Lib.imgui.SetCursorPosX(Lib.imgui.GetCursorPosX() + 4)
                    end
                    local log = item.log
                    local txt = item.txt
                    if log.type == 'correct' then
                       Lib.imgui.TextColored(Lib.imgui.ImVec4(ui.correct_color[1],ui.correct_color[2],ui.correct_color[3],ui.correct_color[4]), txt)
                    elseif log.type == 'error' then
                       Lib.imgui.TextColored(Lib.imgui.ImVec4(ui.error_color[1],ui.error_color[2],ui.error_color[3],ui.error_color[4]), txt)
                    elseif log.type == 'held' then
                       Lib.imgui.TextColored(Lib.imgui.ImVec4(ui.held_color[1],ui.held_color[2],ui.held_color[3],ui.held_color[4] or 1), txt)
                    else
                       local log_text_col = {1,1,1,1}
                       if ui.logs_combo_rgb[0] and ui.key_text_rgb[0] then
                           log_text_col = Fn.computePulsedColor(ui.key_text_color, true, ui.rgb_speed[0])
                       elseif ui.logs_combo_rgb[0] then
                           log_text_col = {ui.key_text_color[1],ui.key_text_color[2],ui.key_text_color[3],ui.key_text_color[4] or 1}
                       end
                       Lib.imgui.TextColored(Lib.imgui.ImVec4(log_text_col[1],log_text_col[2],log_text_col[3],log_text_col[4] or 1), txt)
                    end
                end
            end
        end
        local function renderLogsBadgesMode()
            local log_scale = math.max(0.5, ui.keyboard_scale[0])
            local key_w = tonumber(S.cfg.keyboard.key_width) or 36
            local key_h = tonumber(S.cfg.keyboard.key_height) or 35
            local badge_pad_x = math.max(6, math.floor(6 * log_scale + 0.5))
            local badge_gap = math.max(4, math.floor(4 * log_scale + 0.5))
            local text_h = Lib.imgui.CalcTextSize("A").y
            local badge_h = math.max(text_h + 6, key_h * log_scale)
            local row_h = badge_h + math.max(6, math.floor(6 * log_scale + 0.5))
            local content_x = Lib.imgui.GetCursorScreenPos().x + 4
            local avail_w = math.max(1, Lib.imgui.GetContentRegionAvail().x - 4)
            local row_limit = math.max(1, ui.logs_limit_row[0])
            local packed_rows = {}
            local current_row = {}
            local current_w = 0
            local function flush_log_row()
                if #current_row == 0 then return end
                packed_rows[#packed_rows + 1] = current_row
                current_row = {}
                current_w = 0
            end
            for _, log in ipairs(visible_logs) do
                local txt = Fn.getLocalizedName(log.name)
                local tsz = Lib.imgui.CalcTextSize(txt)
                local bw = math.max(tsz.x + badge_pad_x * 2, key_w * log_scale)
                local next_w = (#current_row > 0) and (current_w + badge_gap + bw) or bw
                if #current_row > 0 and (#current_row >= row_limit or next_w > avail_w) then
                    flush_log_row()
                end
                current_row[#current_row + 1] = { log = log, txt = txt, bw = bw, tsz = tsz }
                current_w = current_w + (#current_row > 1 and badge_gap or 0) + bw
            end
            flush_log_row()
            for _, row in ipairs(packed_rows) do
               Lib.imgui.Spacing()
                local row_start_x = content_x
                local cx = row_start_x
                for ri2 = 1, #row do
                    local log = ui.logs_reverse[0] and row[#row - ri2 + 1] or row[ri2]
                    local txt = log.txt
                    local bw = log.bw
                    local tsz = log.tsz
                    local fill_col, text_col, text_use_alpha
                    if log.log.type == 'correct' then
                        fill_col = {ui.correct_color[1], ui.correct_color[2], ui.correct_color[3], ui.correct_color[4]}
                        text_col = {1, 1, 1, 1}
                        text_use_alpha = false
                    elseif log.log.type == 'error' then
                        fill_col = {ui.error_color[1], ui.error_color[2], ui.error_color[3], ui.error_color[4]}
                        text_col = {1, 1, 1, 1}
                        text_use_alpha = false
                    elseif log.log.type == 'held' then
                        fill_col = {ui.held_color[1], ui.held_color[2], ui.held_color[3], ui.held_color[4] or 1}
                        text_col = {1, 1, 1, 1}
                        text_use_alpha = false
                    else
                        if ui.logs_combo_rgb[0] and ui.key_fill_rgb[0] then
                            fill_col = Fn.computePulsedColor(ui.key_fill_color, true, ui.rgb_speed[0])
                        else
                            fill_col = {ui.key_fill_color[1], ui.key_fill_color[2], ui.key_fill_color[3], ui.key_fill_color[4]}
                        end
                        if ui.logs_combo_rgb[0] and ui.key_text_rgb[0] then
                            text_col = Fn.computePulsedColor(ui.key_text_color, true, ui.rgb_speed[0])
                        else
                            text_col = {ui.key_text_color[1], ui.key_text_color[2], ui.key_text_color[3], ui.key_text_color[4] or 1}
                        end
                        text_use_alpha = true
                    end
                    dl:AddRectFilled(
                       Lib.imgui.ImVec2(cx, Lib.imgui.GetCursorScreenPos().y),
                       Lib.imgui.ImVec2(cx + bw, Lib.imgui.GetCursorScreenPos().y + badge_h),
                       Fn.getColorU32Global(fill_col[1], fill_col[2], fill_col[3], (fill_col[4] or 1) * ui.keyboard_key_alpha[0], true),
                        4
                    )
                    if ui.border_mode[0] == 2 then
                        local bc
                        if ui.logs_combo_rgb[0] and ui.key_border_rgb[0] then
                            bc = Fn.computePulsedColor(ui.key_border_color, true, ui.rgb_speed[0])
                        else
                            bc = {ui.key_border_color[1], ui.key_border_color[2], ui.key_border_color[3], ui.key_border_color[4] or 1}
                        end
                        dl:AddRect(
                           Lib.imgui.ImVec2(cx, Lib.imgui.GetCursorScreenPos().y),
                           Lib.imgui.ImVec2(cx + bw, Lib.imgui.GetCursorScreenPos().y + badge_h),
                           Fn.getColorU32Global(bc[1], bc[2], bc[3], bc[4], true),
                            4, nil, Data.border_thickness[0]
                        )
                    end
                    local text_y = Lib.imgui.GetCursorScreenPos().y + math.max(2, (badge_h - tsz.y) * 0.5)
                    dl:AddText(
                       Lib.imgui.ImVec2(cx + (bw - tsz.x) * 0.5, text_y),
                       Fn.getColorU32Global(text_col[1], text_col[2], text_col[3], (text_col[4] or 1) * (text_use_alpha and ui.text_alpha[0] or 1), true),
                        txt
                    )
                    cx = cx + bw + badge_gap
                end
               Lib.imgui.Dummy(Lib.imgui.ImVec2(0, row_h))
            end
        end
        if #S.log_buffer == 0 then
           Lib.imgui.Spacing()
           Lib.imgui.SetCursorPosX(Lib.imgui.GetCursorPosX() + 4)
            do local _ltxt2 = Data.neon_active_colors[Lib.imgui.Col.Text] or {1.0,1.0,1.0,1.0}
           Lib.imgui.TextColored(Lib.imgui.ImVec4(_ltxt2[1],_ltxt2[2],_ltxt2[3],(_ltxt2[4] or 1.0)*0.5), Fn.T(u8"Нет нажатий..."))
            end
        elseif ui.logs_display_mode[0] == 1 then
            renderLogsTextMode()
        else
            renderLogsBadgesMode()
        end
       Lib.imgui.EndChild()
       Lib.imgui.PopStyleColor(content_push)
    end
    do
        local rst = CBUGER_PREPARE_WINDOW_SIZE("cbuger_logs", 300, 200)
        rst.w, rst.h = ui.logs_size.x, ui.logs_size.y
        CBUGER_DRAW_INVISIBLE_RESIZER("cbuger_logs", rst, 260, 160, ui.interface_alpha[0], true, ui.logs_size)
    end
   Lib.imgui.PopStyleColor(log_push)
   Lib.imgui.End()
    if not ui.show_logs[0] then
        S.cfg.config.show_logs = false
       Lib.inicfg.save(S.cfg, Data.iniFile)
    end
    S.cfg.logs.x = ui.logs_pos.x; S.cfg.logs.y = ui.logs_pos.y
    S.cfg.logs.w = ui.logs_size.x; S.cfg.logs.h = ui.logs_size.y
    Lib.imgui.PopStyleVar()
end
local GUIDE_DIR = Data.CBUGER_CONFIG_DIR
local GUIDE_SETTINGS_FILE = GUIDE_DIR .. 'guide_settings.txt'
pcall(function()
    local f = io.open(GUIDE_DIR .. '.keep', 'a')
    if f then f:close() end
end)
local function guide_load_text()
    local index = ui.current_guide_index
    if not index then return '' end
    local combo = S.combos_list[index]
    if not combo then return '' end
    return combo.guide_text or ''
end
local function guide_load_settings()
    local text = CBUGER_SAFE_READ_TEXT(GUIDE_SETTINGS_FILE, function(raw)
        return raw:match('[rR]%s*=') ~= nil or raw:match('[sS]ize%s*=') ~= nil
    end)
    if type(text) ~= 'string' then return end
    for line in (text .. '\n'):gmatch('([^\r\n]*)\r?\n') do
        local k, v = line:match('^(%w+)%s*=%s*(.+)$')
        v = tonumber(v)
        if k == 'r' then ui.guide_color[0] = v or 1
        elseif k == 'g' then ui.guide_color[1] = v or 1
        elseif k == 'b' then ui.guide_color[2] = v or 1
        elseif k == 'size' then ui.guide_size[0] = v or 1
        end
    end
    for i = 0, 2 do ui.guide_color[i] = math.max(0, math.min(1, tonumber(ui.guide_color[i]) or 1)) end
    ui.guide_size[0] = math.max(0.1, math.min(5.0, tonumber(ui.guide_size[0]) or 1))
    ui.guide_picker[0] = ui.guide_color[0]
    ui.guide_picker[1] = ui.guide_color[1]
    ui.guide_picker[2] = ui.guide_color[2]
    ui.guide_picker[3] = ui.guide_color[3]
end
local function guide_save()
    local index = ui.current_guide_index
    local combo = index and S.combos_list[index] or nil
    if not combo then return false end
    combo.guide_text = Lib.ffi.string(ui.guide_text_buffer)
    local combos_saved = Fn.saveCombos() ~= false
    local settings_text = table.concat({
        'r=' .. tostring(ui.guide_color[0]),
        'g=' .. tostring(ui.guide_color[1]),
        'b=' .. tostring(ui.guide_color[2]),
        'size=' .. tostring(ui.guide_size[0]),
        '',
    }, '\n')
    local settings_saved = CBUGER_SAFE_WRITE_FILE(GUIDE_SETTINGS_FILE, settings_text)
    return combos_saved and settings_saved
end
Lib.ffi.copy(ui.guide_text_buffer, '', 16383)
guide_load_settings()
Fn.RenderGuide = function()
    if not ui.guide_open[0] then
        ui.guide_resizing = false
    end
    local win_w, win_h = ui.guide_window_size.w, ui.guide_window_size.h
    Lib.imgui.SetNextWindowSize(Lib.imgui.ImVec2(win_w, win_h), Lib.imgui.Cond.Always)
    if ui.guide_drag_pos then
        Lib.imgui.SetNextWindowPos(
            Lib.imgui.ImVec2(ui.guide_drag_pos.x, ui.guide_drag_pos.y),
            Lib.imgui.Cond.Always
        )
    else
        Lib.imgui.SetNextWindowPos(Lib.imgui.ImVec2(200, 150), Lib.imgui.Cond.FirstUseEver)
    end
    local io = Lib.imgui.GetIO()
    local tc = neon_fx.tabs_color
    local cc = neon_fx.icon_cross_color
    local rc = neon_fx.icon_resize_color
    local wb = Data.neon_active_colors[Lib.imgui.Col.WindowBg] or {0.04, 0.04, 0.07, 0.97}
    local text_col = Data.neon_active_colors[Lib.imgui.Col.Text] or {1, 1, 1, 1}
    local section_col = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or text_col
    local title_col = section_col
    Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg, Lib.imgui.ImVec4(0, 0, 0, 0))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(0, 0, 0, 0))
    if Lib.imgui.Col.BorderShadow then
        Lib.imgui.PushStyleColor(Lib.imgui.Col.BorderShadow, Lib.imgui.ImVec4(0, 0, 0, 0))
    end
    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.Alpha, ui.interface_alpha[0])
    Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(0, 0))
    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowRounding, 20)
    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowBorderSize, 0)
    local flags = Lib.imgui.WindowFlags.NoTitleBar
        + Lib.imgui.WindowFlags.NoScrollbar
        + Lib.imgui.WindowFlags.NoScrollWithMouse
    local opened = Lib.imgui.Begin('##KeyBoardGuideRebuilt', ui.guide_open, flags)
    Lib.imgui.PopStyleVar(3)
    if Lib.imgui.Col.BorderShadow then Lib.imgui.PopStyleColor() end
    Lib.imgui.PopStyleColor(2)
    if not opened then
        Lib.imgui.End()
        Lib.imgui.PopStyleVar()
        return
    end
    local dl = Lib.imgui.GetWindowDrawList()
    local pos = Lib.imgui.GetWindowPos()
    local size = Lib.imgui.GetWindowSize()
    local p_min = pos
    local p_max = Lib.imgui.ImVec2(pos.x + size.x, pos.y + size.y)
    local bg = Data.nfn.pack_color(wb[1], wb[2], wb[3], wb[4] or 0.97, true, ui.interface_alpha[0])
    dl:AddRectFilled(p_min, p_max, bg, 20)
    Data.nfn.draw_police_ambient(dl, p_min, p_max, ui.interface_alpha[0])
    Data.nfn.draw_neon_border(dl, p_min, p_max, ui.interface_alpha[0])
    local title_text = ui.current_guide_name
    if not title_text and ui.context_menu_target and S.combos_list[ui.context_menu_target] then
        title_text = S.combos_list[ui.context_menu_target].name
    end
    title_text = title_text or u8('Инфо')
    title_text = Fn.T(u8('Гайд: ')) .. Fn.decodeSafe(title_text)
    local title_pos = Lib.imgui.ImVec2(p_min.x + 10, p_min.y + 5)
    Lib.imgui.SetCursorScreenPos(title_pos)
    Lib.imgui.InvisibleButton('##guide_drag', Lib.imgui.ImVec2(math.max(120, size.x - 82), 24))
    local drag_hovered = Lib.imgui.IsItemHovered()
    local mp = io.MousePos
    if drag_hovered and Lib.imgui.IsItemClicked(0) then
        ui.guide_dragging = true
        ui.guide_drag_offset.x = mp.x - pos.x
        ui.guide_drag_offset.y = mp.y - pos.y
        ui.guide_drag_pos = Lib.imgui.ImVec2(pos.x, pos.y)
    end
    if ui.guide_dragging then
        if Lib.imgui.IsMouseDown(0) then
            ui.guide_drag_pos = Lib.imgui.ImVec2(
                mp.x - ui.guide_drag_offset.x,
                mp.y - ui.guide_drag_offset.y
            )
        else
            ui.guide_dragging = false
        end
    end
    if drag_hovered or ui.guide_dragging then Data.nfn.set_hand_cursor() end
    dl:AddText(title_pos, Data.nfn.pack_color(title_col[1], title_col[2], title_col[3], 1, false, ui.interface_alpha[0]), title_text)
    local close_p = Lib.imgui.ImVec2(p_max.x - 24, p_min.y + 22)
    Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(close_p.x - 14, close_p.y - 14))
    if Lib.imgui.InvisibleButton('##guide_close_rebuilt', Lib.imgui.ImVec2(28, 28)) then
        guide_save()
        ui.guide_open[0] = false
        ui.current_guide_index = nil
        ui.current_guide_name = nil
    end
    Data.nfn.draw_cross(dl, close_p, 12, Lib.imgui.IsItemHovered(), ui.interface_alpha[0])
    local content_x = p_min.x + 10
    local content_y = p_min.y + 31
    Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(content_x, content_y))
    Lib.imgui.TextColored(Lib.imgui.ImVec4(section_col[1], section_col[2], section_col[3], section_col[4] or 1), Fn.T(u8('Описание:')))
    Lib.imgui.SameLine(0, 8)
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,
        Lib.imgui.ImVec4(ui.guide_color[0], ui.guide_color[1], ui.guide_color[2], 0.85))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered,
        Lib.imgui.ImVec4(math.min(1, ui.guide_color[0] + 0.2), math.min(1, ui.guide_color[1] + 0.2), math.min(1, ui.guide_color[2] + 0.2), 1))
    Data.nfn.PushButtonBorder()
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(1,1,1,0))
    local gcol_clicked = Lib.imgui.Button(Fn.T(u8'Цвет##gcol'), Lib.imgui.ImVec2(52, 20))
    Lib.imgui.PopStyleColor()
    local gcol_min = Lib.imgui.GetItemRectMin()
    local gcol_max = Lib.imgui.GetItemRectMax()
    local gcol_dl = Lib.imgui.GetWindowDrawList()
    local gcol_txt = Fn.T(u8('Цвет'))
    local gcol_ts = Lib.imgui.CalcTextSize(gcol_txt)
    local gcol_cx = (gcol_min.x + gcol_max.x) * 0.5 - gcol_ts.x * 0.5
    local gcol_cy = (gcol_min.y + gcol_max.y) * 0.5 - gcol_ts.y * 0.5
    for ox=-1,1 do for oy=-1,1 do
        if ox ~= 0 or oy ~= 0 then
            gcol_dl:AddText(Lib.imgui.ImVec2(gcol_cx+ox, gcol_cy+oy), CBUGER_ApplyGlobalAlphaU32(0xFF000000), gcol_txt)
        end
    end end
    local gcol_tc = text_col
    gcol_dl:AddText(Lib.imgui.ImVec2(gcol_cx, gcol_cy), Data.nfn.pack_color(text_col[1], text_col[2], text_col[3], text_col[4] or 1, true, CBUGER_GET_INTERFACE_ALPHA()), gcol_txt)
    Data.nfn.PopButtonBorder()
    if gcol_clicked then
        ui.guide_color_preview_active = true
        for i = 0, 3 do ui.guide_picker[i] = ui.guide_color[i] end
        Lib.imgui.OpenPopup('GuideColorPop')
    end
    Lib.imgui.PopStyleColor(2)
    if Lib.imgui.IsItemHovered and Lib.imgui.SetMouseCursor then
        pcall(function() Lib.imgui.SetMouseCursor((Lib.imgui.MouseCursor and Lib.imgui.MouseCursor.Hand) or 7) end)
    end
    Data.nfn.BeginColorPopupStyle()
    if Lib.imgui.BeginPopup('GuideColorPop') then
            Lib.imgui.TextColored(Lib.imgui.ImVec4(text_col[1], text_col[2], text_col[3], text_col[4] or 1), Fn.T(u8('Цвет гайда')))
        Lib.imgui.Separator()
        local flags_cp = 0
        if Lib.imgui.ColorEditFlags then
            flags_cp = (Lib.imgui.ColorEditFlags.NoSidePreview or 0) + (Lib.imgui.ColorEditFlags.NoSmallPreview or 0) + (Lib.imgui.ColorEditFlags.AlphaBar or 0)
        end
        if Lib.imgui.ColorPicker4('##gcpicker', ui.guide_picker, flags_cp) then
            for i = 0, 3 do ui.guide_color[i] = ui.guide_picker[i] end
            guide_save()
        end
        Lib.imgui.Spacing()
        Data.nfn.PushButtonBorder()
        if Lib.imgui.Button(Fn.T(u8'Белый##gcr'), Lib.imgui.ImVec2(-1, 0)) then
            ui.guide_picker[0], ui.guide_picker[1], ui.guide_picker[2] = 1, 1, 1
            ui.guide_color[0], ui.guide_color[1], ui.guide_color[2] = 1, 1, 1
            guide_save()
        end
        Data.nfn.PopButtonBorder()
        Lib.imgui.Spacing()
        local r, g, b = ui.guide_picker[0], ui.guide_picker[1], ui.guide_picker[2]
        Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, Lib.imgui.ImVec4(r, g, b, 0.9))
        Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(math.min(1, r + 0.15), math.min(1, g + 0.15), math.min(1, b + 0.15), 1))
        Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(1 - r * 0.5, 1 - g * 0.5, 1 - b * 0.5, 1))
        Data.nfn.PushButtonBorder()
        if Lib.imgui.Button(Fn.T(u8'Выбрать##gcapply'), Lib.imgui.ImVec2(-1, 0)) then
            for i = 0, 3 do ui.guide_color[i] = ui.guide_picker[i] end
            guide_save()
            Lib.imgui.CloseCurrentPopup()
        end
        Data.nfn.PopButtonBorder()
        Lib.imgui.PopStyleColor(3)
        Lib.imgui.EndPopup()
    else
        ui.guide_color_preview_active = false
    end
    Data.nfn.EndColorPopupStyle()
    Lib.imgui.SameLine(0, 8)
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,
        Lib.imgui.ImVec4(ui.guide_color[0], ui.guide_color[1], ui.guide_color[2], 0.85))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered,
        Lib.imgui.ImVec4(math.min(1, ui.guide_color[0] + 0.2), math.min(1, ui.guide_color[1] + 0.2), math.min(1, ui.guide_color[2] + 0.2), 1))
    Data.nfn.PushButtonBorder()
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(1,1,1,0))
    local gsize_clicked = Lib.imgui.Button(Fn.T(u8'Размер##gsize'), Lib.imgui.ImVec2(62, 20))
    Lib.imgui.PopStyleColor()
    local gsize_min = Lib.imgui.GetItemRectMin()
    local gsize_max = Lib.imgui.GetItemRectMax()
    local gsize_dl = Lib.imgui.GetWindowDrawList()
    local gsize_txt = Fn.T(u8('Размер'))
    local gsize_ts = Lib.imgui.CalcTextSize(gsize_txt)
    local gsize_cx = (gsize_min.x + gsize_max.x) * 0.5 - gsize_ts.x * 0.5
    local gsize_cy = (gsize_min.y + gsize_max.y) * 0.5 - gsize_ts.y * 0.5
    for ox=-1,1 do for oy=-1,1 do
        if ox ~= 0 or oy ~= 0 then
            gsize_dl:AddText(Lib.imgui.ImVec2(gsize_cx+ox, gsize_cy+oy), CBUGER_ApplyGlobalAlphaU32(0xFF000000), gsize_txt)
        end
    end end
    gsize_dl:AddText(Lib.imgui.ImVec2(gsize_cx, gsize_cy), Data.nfn.pack_color(text_col[1], text_col[2], text_col[3], text_col[4] or 1, true, CBUGER_GET_INTERFACE_ALPHA()), gsize_txt)
    Data.nfn.PopButtonBorder()
    if gsize_clicked then ui.guide_show_size = not ui.guide_show_size end
    Lib.imgui.PopStyleColor(2)
    if Lib.imgui.IsItemHovered and Lib.imgui.SetMouseCursor then
        pcall(function() Lib.imgui.SetMouseCursor((Lib.imgui.MouseCursor and Lib.imgui.MouseCursor.Hand) or 7) end)
    end
    if ui.guide_show_size then
        Lib.imgui.SameLine(0, 6)
        Lib.imgui.PushItemWidth(80)
        Lib.imgui.SliderFloat('##gscale', ui.guide_size, 0.6, 2.5, '%.1fx')
        Lib.imgui.PopItemWidth()
        if Lib.imgui.IsItemDeactivatedAfterEdit and Lib.imgui.IsItemDeactivatedAfterEdit() then guide_save() end
    end
    Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(content_x, content_y + 27))
    local area_pos = Lib.imgui.GetCursorScreenPos()
    local area_w = math.max(200, size.x - 20)
    local area_h = math.max(120, size.y - 79)
    local style = Lib.imgui.GetStyle()
    local fp_x = style.FramePadding.x or 4
    local fp_y = style.FramePadding.y or 3
    local field_frame = Data.neon_active_colors[Lib.imgui.Col.FrameBg] or {wb[1]*0.8, wb[2]*0.8, wb[3]*0.8, 0.95}
    local field_hover = Data.neon_active_colors[Lib.imgui.Col.FrameBgHovered] or field_frame
    local field_active = Data.neon_active_colors[Lib.imgui.Col.FrameBgActive] or field_frame
    local field_text = {ui.guide_color[0], ui.guide_color[1], ui.guide_color[2], ui.guide_color[3] or 1}
    Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(area_pos.x + fp_x, area_pos.y + fp_y))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.FrameBg, Lib.imgui.ImVec4(field_frame[1], field_frame[2], field_frame[3], field_frame[4] or 0.95))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.FrameBgHovered, Lib.imgui.ImVec4(field_hover[1], field_hover[2], field_hover[3], field_hover[4] or 0.95))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.FrameBgActive, Lib.imgui.ImVec4(field_active[1], field_active[2], field_active[3], field_active[4] or 0.95))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(0, 0, 0, 0))
    Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(field_text[1], field_text[2], field_text[3], field_text[4] or 1))
    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameBorderSize, 0)
    Lib.imgui.SetWindowFontScale(math.max(0.8, ui.guide_size[0]))
    local changed = Lib.imgui.InputTextMultiline('##guideinput', ui.guide_text_buffer, Lib.ffi.sizeof(ui.guide_text_buffer), Lib.imgui.ImVec2(area_w - fp_x * 2, area_h - fp_y * 2), Lib.imgui.InputTextFlags.AllowTabInput)
    Lib.imgui.SetWindowFontScale(1.0)
    Lib.imgui.PopStyleVar()
    Lib.imgui.PopStyleColor(5)
    if changed then guide_save() end
    do
        local rst = CBUGER_PREPARE_WINDOW_SIZE("cbuger_guide", 359, 250)
        rst.w, rst.h = ui.guide_window_size.w, ui.guide_window_size.h
        CBUGER_DRAW_INVISIBLE_RESIZER("cbuger_guide", rst, 300, 220, ui.interface_alpha[0], false, ui.guide_window_size)
    end
    local rca = rc[4] or 0.67
    local rc32 = Data.nfn.pack_color(rc[1], rc[2], rc[3], rca, true, ui.interface_alpha[0])
    dl:AddLine(Lib.imgui.ImVec2(p_max.x - 5, p_max.y - 2), Lib.imgui.ImVec2(p_max.x - 2, p_max.y - 5), rc32, 1.5)
    dl:AddLine(Lib.imgui.ImVec2(p_max.x - 9, p_max.y - 2), Lib.imgui.ImVec2(p_max.x - 2, p_max.y - 9), rc32, 1.0)
    Lib.imgui.End()
    Lib.imgui.PopStyleVar()
end
 Fn.vecNorm = function(x, y, z)
    local len = math.sqrt(x*x + y*y + z*z)
    if len < 0.0001 then return 0, 0, 0 end
    return x / len, y / len, z / len
end
 Fn.vecCross = function(ax, ay, az, bx, by, bz)
    return ay*bz - az*by, az*bx - ax*bz, ax*by - ay*bx
end
 Fn.buildAimBasis = function(camX, camY, camZ, tx, ty, tz)
    local dx, dy, dz = Fn.vecNorm(tx - camX, ty - camY, tz - camZ)
    if dx == 0 and dy == 0 and dz == 0 then return nil end
    local rx, ry, rz = Fn.vecNorm(Fn.vecCross(0, 0, 1, dx, dy, dz))
    if rx == 0 and ry == 0 and rz == 0 then
        rx, ry, rz = Fn.vecNorm(Fn.vecCross(1, 0, 0, dx, dy, dz))
        if rx == 0 and ry == 0 and rz == 0 then return nil end
    end
    local ux, uy, uz = Fn.vecNorm(Fn.vecCross(dx, dy, dz, rx, ry, rz))
    return dx, dy, dz, rx, ry, rz, ux, uy, uz
end
 Fn.angularDeviation = function(camX, camY, camZ, tx, ty, tz, dx, dy, dz, rx, ry, rz, ux, uy, uz)
    local sx, sy, sz = Fn.vecNorm(tx - camX, ty - camY, tz - camZ)
    if sx == 0 and sy == 0 and sz == 0 then return nil end
    local dot_front = sx*dx + sy*dy + sz*dz
    if dot_front < 0.05 then return nil end
    local perp_x = sx - dot_front*dx
    local perp_y = sy - dot_front*dy
    local perp_z = sz - dot_front*dz
    local dev_right = perp_x*rx + perp_y*ry + perp_z*rz
    local dev_up    = perp_x*ux + perp_y*uy + perp_z*uz
    local angle_h = math.deg(math.atan(dev_right, dot_front))
    local angle_v = math.deg(math.atan(dev_up,    dot_front))
    return angle_h, angle_v
end
 Fn.getRecoilBasePos = function()
    local ok, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
    if ok and type(x) == 'number' then
        return x, y, z + Data.RING_EYE
    end
    local okc, cx, cy, cz = pcall(getActiveCameraCoordinates)
    if okc and type(cx) == 'number' then return cx, cy, cz end
    return nil
end
 Fn.getRingSlope = function()
    return (Data.recoil_ring.height or 0) / Data.RING_RADIUS
end
 Fn.nudgeRecoilRing = function(delta)
   Data.recoil_ring.height = math.max(-4.0, math.min(4.0, (Data.recoil_ring.height or 0) + delta))
    S.cfg.config.recoil_ring_height = Data.recoil_ring.height
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
end
 Fn.getShotSlope = function(tx, ty, tz)
    local bx, by, bz = Fn.getRecoilBasePos()
    if not bx then return nil end
    local dx, dy = tx - bx, ty - by
    local horiz = math.sqrt(dx * dx + dy * dy)
    if horiz < 0.5 then return nil end
    return (tz - bz) / horiz
end
 Fn.projectWorldPoint = function(wx, wy, wz)
    local pok, vis, sx, sy, sz = pcall(convert3DCoordsToScreenEx, wx, wy, wz, false, false)
    if not pok or type(sx) ~= 'number' or type(sy) ~= 'number' then return nil end
    if sx ~= sx or sy ~= sy then return nil end
    if type(sz) == 'number' then
        if sz ~= sz or sz <= 0 then return nil end
    elseif vis == false then
        return nil
    end
    if math.abs(sx) > 20000 or math.abs(sy) > 20000 then return nil end
    return sx, sy
end
 Fn.placeRecoilRing = function(tx, ty, tz)
    local slope = Fn.getShotSlope(tx, ty, tz)
    if not slope then return false end
   Data.recoil_ring.height = math.max(-4.0, math.min(4.0, slope * Data.RING_RADIUS))
    S.cfg.config.recoil_ring_height = Data.recoil_ring.height
    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
    return true
end
 Fn.drawRecoilRing = function(dl, col, thickness)
    local bx, by, bz = Fn.getRecoilBasePos()
    if not bx then return false end
    local R  = Data.RING_RADIUS
    local zr = bz + (Data.recoil_ring.height or 0)
    local segs = Data.RING_SEGMENTS
    local prev_x, prev_y, drew = nil, nil, false
    for i = 0, segs do
        local a  = (i / segs) * math.pi * 2
        local wx = bx + math.cos(a) * R
        local wy = by + math.sin(a) * R
        local sx, sy = Fn.projectWorldPoint(wx, wy, zr)
        if sx and prev_x then
            dl:AddLine(Lib.imgui.ImVec2(prev_x, prev_y), Lib.imgui.ImVec2(sx, sy), col, thickness)
            drew = true
        end
        prev_x, prev_y = sx, sy
    end
    return drew
end
function SC_onSendBulletSync(data)
    if not data or not data.target then return end
    if Data.recoil_line_arm then
       Data.recoil_line_arm = false
       Fn.placeRecoilRing(data.target.x, data.target.y, data.target.z)
    end
    if not (ui.recoil_enabled[0] or ui.shotmap_enabled[0]) then return end
    if ui.recoil_enabled[0] then
        local above = nil
        local slope = Fn.getShotSlope(data.target.x, data.target.y, data.target.z)
        if slope then above = slope > Fn.getRingSlope() end
        if above ~= nil then
            if above then
                S.state.recoil_incorrect = (S.state.recoil_incorrect or 0) + 1
               Data.recoil_flash_time = os.clock()
            else
                S.state.recoil_correct = (S.state.recoil_correct or 0) + 1
            end
        end
    end
    if ui.shotmap_enabled[0] then
        local okCam, camX, camY, camZ = pcall(getActiveCameraCoordinates)
        if okCam then
            local tx, ty, tz = data.target.x, data.target.y, data.target.z
            local cur = Data.shotmap.current
            if not cur.ref then
                local dx, dy, dz, rx, ry, rz, ux, uy, uz = Fn.buildAimBasis(camX, camY, camZ, tx, ty, tz)
                if dx then
                   cur.ref = { camX=camX, camY=camY, camZ=camZ, dx=dx, dy=dy, dz=dz, rx=rx, ry=ry, rz=rz, ux=ux, uy=uy, uz=uz }
                    cur.ts  = os.time()
                end
            end
            local ref = cur.ref
            if ref then
                local devH, devV = Fn.angularDeviation(ref.camX, ref.camY, ref.camZ, tx, ty, tz,
                    ref.dx, ref.dy, ref.dz, ref.rx, ref.ry, ref.rz, ref.ux, ref.uy, ref.uz)
                if devH then
                    table.insert(cur.points, { x = devH, y = -devV })
                    Data.shotmap.dirty = true
                    local target_size = math.max(1, ui.shotmap_session_size[0])
                    if #cur.points >= target_size then
                        table.insert(Data.shotmap.sessions, cur)
                        if #Data.shotmap.sessions > Data.SHOTMAP_MAX_SESSIONS then
                            table.remove(Data.shotmap.sessions, 1)
                        end
                       Data.shotmap.current = { points = {}, ref = nil, ts = os.time() }
                        if ui.shotmap_view_mode[0] == 1 then
                            ui.shotmap_view_index[0] = Fn.shotmapCardCount()
                        end
                       Fn.save_shotmap_to_json()
                    end
                end
            end
        end
    end
end
local FIXED_ROW_X = {
    gr_lang           = 11.4,
    gr_ring           = 8.9,
    gr_line_height    = 10.0,
    gr_shot_modes     = 8.6,
    gr_shot_nav       = 10.0,
    gr_shot_current   = -15.0,
    gr_shot_card      = 8.9,
    gr_shot_metric    = 165.6,
    gr_stats_kpd      = 2.72,
    gr_stats_correct  = 2.72,
    gr_stats_incorrect = 2.72,
    gr_stats_reset    = 7.0,
    gr_shot_clear     = 10.0,
    gr_style_border   = 0.0,
    gr_wave_dir       = 0.0,
    gr_wave_target    = 0.0,
    gr_key_fill       = 0.0,
    gr_key_border     = 0.0,
    gr_key_text       = 0.0,
    gr_pressed_fill   = 0.0,
    gr_pressed_border = 0.0,
    gr_pressed_text   = 0.0,
}
local FIXED_SLIDER_X = {
    ls_keyboard_scale       = -10.2,
    ls_keyboard_alpha       = -10.8,
    ls_text_alpha            = 35.6,
    ls_border_thickness     = -12.1,
    ls_combo_scale           = -12.1,
    ls_wave_speed            = -12.1,
    ls_wave_transparency    = -12.1,
    ls_rgb_speed             = -12.1,
}
local FIXED_EDITOR_SLIDER_X = {
    le_color_interface_alpha = -8.3,
    le_fx_sparks_speed       = 0.0,
    le_fx_sparks_size        = 0.0,
    le_fx_waves_speed        = 0.0,
    le_fx_ambient_speed      = 0.0,
}
function fixed_row_x(key)
    return (Data.ofs_get and Data.ofs_get(key, FIXED_ROW_X[key] or 0.0)) or (FIXED_ROW_X[key] or 0.0)
end
function fixed_row_begin(key)
    local dx = fixed_row_x(key)
    if math.abs(dx) > 0.01 then
        Lib.imgui.SetCursorPosX(math.max(0, Lib.imgui.GetCursorPosX() + dx))
    end
    return dx
end
function fixed_slider_x(key)
    return (Data.ofs_get and Data.ofs_get(key, FIXED_SLIDER_X[key] or 0.0)) or (FIXED_SLIDER_X[key] or 0.0)
end
function fixed_slider_begin(key)
    Data.fixed_slider_pending_x = fixed_slider_x(key)
    return Data.fixed_slider_pending_x
end
function fixed_editor_slider_x(key)
    return FIXED_EDITOR_SLIDER_X[key] or 0.0
end
function fixed_editor_slider_begin(key)
    Data.fixed_slider_pending_x = fixed_editor_slider_x(key)
    return Data.fixed_slider_pending_x
end
function fixed_mouse_gap()
    if Data.mouse_gap then
        return tonumber(Data.mouse_gap[0]) or 5.0
    end
    return 5.0
end
function fixed_gap(key, default)
    local v = tonumber(default or 0) or 0
    if v > 0 then Lib.imgui.Dummy(Lib.imgui.ImVec2(0, v)) end
    return v
end

local combo_layout_gap_extra = Lib.new.float(tonumber(S.cfg.config.combo_text_layout_gap_extra) or 4.0)
local combo_layout_bottom_pad = Lib.new.float(tonumber(S.cfg.config.combo_text_layout_bottom_pad) or 8.0)

local combo_layout_last_stage_threshold_px = Lib.new.float(tonumber(S.cfg.config.combo_text_layout_last_stage_threshold_px) or -16.0)

S.cfg.config.combo_footer_safety_margin = 0.0
local combo_footer_fit_state = nil

local combo_layout_hide_step_auto = Lib.new.bool(false)
local combo_layout_hide_step_px = Lib.new.float(tonumber(S.cfg.config.combo_text_layout_hide_step_px) or 29.9)

local combo_layout_hide_step_adjust_px = Lib.new.float(tonumber(S.cfg.config.combo_text_layout_hide_step_adjust_px) or 0.0)
local combo_layout_error_reserve = Lib.new.float(18)
local combo_layout_error_always_reserve = Lib.new.bool(false)
local combo_layout_auto_rows = Lib.new.bool(true)
local combo_layout_manual_rows = Lib.new.int(2)

local plaque_layout_stage_h_px = Lib.new.float(tonumber(S.cfg.config.plaque_layout_stage_h) or 28.0)
local plaque_layout_gap_extra = Lib.new.float(tonumber(S.cfg.config.plaque_layout_gap_extra) or 4.0)
local plaque_layout_bottom_pad = Lib.new.float(tonumber(S.cfg.config.plaque_layout_bottom_pad) or 0.0)
local plaque_layout_last_stage_threshold_px = Lib.new.float(tonumber(S.cfg.config.plaque_layout_last_stage_threshold_px) or -16.0)
local plaque_layout_hide_step_auto = Lib.new.bool(S.cfg.config.plaque_layout_hide_step_auto ~= false)
local plaque_layout_hide_step_px = Lib.new.float(tonumber(S.cfg.config.plaque_layout_hide_step_px) or 29.9)

local plaque_layout_hide_step_adjust_px = Lib.new.float(tonumber(S.cfg.config.plaque_layout_hide_step_adjust_px) or 0.0)
local plaque_layout_error_reserve = Lib.new.float(tonumber(S.cfg.config.plaque_layout_error_reserve) or 18.0)
local plaque_layout_error_always_reserve = Lib.new.bool(S.cfg.config.plaque_layout_error_always_reserve == true)
local plaque_layout_error_offset = Lib.new.float(tonumber(S.cfg.config.plaque_layout_error_offset) or 10.0)
local plaque_footer_safety_margin = Lib.new.float(tonumber(S.cfg.config.plaque_footer_safety_margin) or 0.0)

local combo_mode_size_initialized = { [1] = false, [2] = false }
local function combo_mode_size_keys(mode)
    if tonumber(mode) == 2 then return 'combo_plaque_window_w', 'combo_plaque_window_h' end
    return 'combo_text_window_w', 'combo_text_window_h'
end
local function combo_mode_get_size(mode)
    local wk, hk = combo_mode_size_keys(mode)
    local w = tonumber(S.cfg.config[wk])
    local h = tonumber(S.cfg.config[hk])
    if w and h then return w, h end
    return nil, nil
end

local combo_identity_size_cache = {}
local combo_identity_size_cache_order = {}
local combo_active_identity_for_size_cache = nil
local COMBO_IDENTITY_SIZE_CACHE_LIMIT = 128
local function combo_identity_size_cache_key(identity, mode)
    return tostring(identity or '') .. "\31" .. (tonumber(mode) == 2 and '2' or '1')
end

local combo_identity_manual_size_cache = {}
local function combo_identity_was_manually_resized(identity, mode)
    return combo_identity_manual_size_cache[combo_identity_size_cache_key(identity, mode)] == true
end
local function combo_identity_get_size(identity, mode)
    if identity == nil or identity == '' then return nil, nil end
    local cached = combo_identity_size_cache[combo_identity_size_cache_key(identity, mode)]
    if type(cached) ~= 'table' then return nil, nil end
    return tonumber(cached.w), tonumber(cached.h)
end
local function combo_identity_store_size(identity, mode, w, h)
    if identity == nil or identity == '' then return end
    w, h = tonumber(w), tonumber(h)
    if not w or not h then return end
    local key = combo_identity_size_cache_key(identity, mode)
    if combo_identity_size_cache[key] == nil then
        combo_identity_size_cache_order[#combo_identity_size_cache_order + 1] = key
    end
    combo_identity_size_cache[key] = { w = w, h = h }
    while #combo_identity_size_cache_order > COMBO_IDENTITY_SIZE_CACHE_LIMIT do
        local oldest = table.remove(combo_identity_size_cache_order, 1)
        if oldest then combo_identity_size_cache[oldest] = nil end
    end
end
local function combo_mode_store_size(mode, w, h)
    w, h = tonumber(w), tonumber(h)
    if not w or not h then return end
    local wk, hk = combo_mode_size_keys(mode)
    S.cfg.config[wk], S.cfg.config[hk] = w, h
    combo_mode_size_initialized[tonumber(mode) == 2 and 2 or 1] = true

    if combo_active_identity_for_size_cache then
        combo_identity_store_size(combo_active_identity_for_size_cache, mode, w, h)
    end
end
combo_mode_size_initialized[1] = combo_mode_get_size(1) ~= nil
combo_mode_size_initialized[2] = combo_mode_get_size(2) ~= nil
local combo_initial_mode = (tonumber(ui.combo_window_display_mode[0]) == 2) and 2 or 1
if not combo_mode_size_initialized[combo_initial_mode] then
    combo_mode_store_size(combo_initial_mode, S.cfg.combo.w or 220, S.cfg.combo.h or 120)
end
local combo_mode_last_seen = nil

local combo_mode_last_combo_signature = nil

local combo_initial_fit_pending = nil

local combo_tail_auto_size = nil

local combo_layout_measured_geometry = { [1] = nil, [2] = nil }

S.state.combo_width_font_factor_by_mode = S.state.combo_width_font_factor_by_mode or {}

local combo_shared_row_capacity = {
    signature = nil,
    settings_signature = nil,
    window_w = nil,
    window_h = nil,
    rows = {},
    dimensions_by_mode = {},
}
local function combo_get_row_geometry(mode, stage_h, gap_h, fallback_step)
    mode = (tonumber(mode) == 2) and 2 or 1
    local state = combo_layout_measured_geometry[mode]
    if type(state) ~= 'table' then
        state = {
            base_stage_h = stage_h,
            base_gap_h = gap_h,
            row_h = math.max(1, stage_h),
            row_step = math.max(stage_h + gap_h, tonumber(fallback_step) or (stage_h + gap_h)),
            measured = false,
        }
        combo_layout_measured_geometry[mode] = state
        return state
    end

    local old_stage_h = tonumber(state.base_stage_h) or stage_h
    local old_gap_h = tonumber(state.base_gap_h) or gap_h
    local delta_h = stage_h - old_stage_h
    local delta_gap = gap_h - old_gap_h
    if math.abs(delta_h) > 0.01 or math.abs(delta_gap) > 0.01 then
        state.row_h = math.max(1, (tonumber(state.row_h) or old_stage_h) + delta_h)
        state.row_step = math.max(state.row_h,
            (tonumber(state.row_step) or (old_stage_h + old_gap_h)) + delta_h + delta_gap)
        state.base_stage_h = stage_h
        state.base_gap_h = gap_h
    end
    return state
end

local function combo_record_row_geometry(mode, row_top_y, row_bottom_y, measured_step)
    local state = combo_layout_measured_geometry[(tonumber(mode) == 2) and 2 or 1]
    if type(state) ~= 'table' then return end
    row_top_y = tonumber(row_top_y)
    row_bottom_y = tonumber(row_bottom_y)
    if row_top_y and row_bottom_y and row_bottom_y >= row_top_y then
        local row_h = row_bottom_y - row_top_y
        if row_h > 0.5 and row_h < 500 then state.row_h = row_h end
    end
    measured_step = tonumber(measured_step)
    if measured_step and measured_step > 0.5 and measured_step < 500 then
        state.row_step = math.max(tonumber(state.row_h) or 1, measured_step)
        state.measured = true
    end
end

local combo_manual_resize_lock = nil
local neon_render = Lib.imgui.OnFrame(
    function()
        return neon.target_main[0] or neon.target_editor[0]
            or (neon.main_alpha > 0.01) or (neon.editor_alpha > 0.01)
            or (neon.combo_editor_alpha > 0.01) or neon.target_combo_editor[0]
            or ui.show_logs[0]
            or ui.show_combo_window[0]
            or ui.keyboard[0]
            or ui.mouse[0]
            or ui.guide_open[0]
    end,
    function(player)
        local style = Lib.imgui.GetStyle()
        if neon.is_first_frame then
            for _, col in ipairs(Data.neon_lists.imgui_colors) do
                if col.id ~= nil then
                    local c = style.Colors[col.id]
                   Data.neon_active_colors[col.id] = {c.x, c.y, c.z, c.w}
                end
            end
           Data.nfn.ApplyGlobalTheme(neon_fx.global_base_color[1], neon_fx.global_base_color[2], neon_fx.global_base_color[3])
            neon_fx.title_button_color[1]=neon_fx.title_main_color[1]
            neon_fx.title_button_color[2]=neon_fx.title_main_color[2]
            neon_fx.title_button_color[3]=neon_fx.title_main_color[3]
            neon_fx.title_button_color[4]=neon_fx.title_main_color[4] or 1
            neon.is_first_frame = false
        end
       Data.neon_wave_color_tbl[1] = ui.wave_color_if4[0]
       Data.neon_wave_color_tbl[2] = ui.wave_color_if4[1]
       Data.neon_wave_color_tbl[3] = ui.wave_color_if4[2]
       Data.neon_wave_color_tbl[4] = ui.wave_color_if4[3]
        Data.neon_active_colors[Lib.imgui.Col.WindowBg] = {0.07, 0.07, 0.08, 1.0}
        Data.neon_active_colors[Lib.imgui.Col.Border]   = {0, 0, 0, 0}
        if Lib.imgui.Col.PopupBg then Data.neon_active_colors[Lib.imgui.Col.PopupBg] = {0.09, 0.09, 0.10, 1.0} end
        Data.neon_smooth_close[0] = false
        for id, clr in pairs(Data.neon_active_colors) do
            style.Colors[id] = Lib.imgui.ImVec4(clr[1] or 1, clr[2] or 1, clr[3] or 1, clr[4] or 1)
        end
       Data.neon_ui_anim.dt       = os.clock() - Data.neon_ui_anim.last_time
       Data.neon_ui_anim.last_time = os.clock()
        neon.settings_time    = neon.settings_time + Data.neon_ui_anim.dt
        if Data.neon_smooth_close[0] then
            neon._main_fade   = Data.nfn.anim_update(neon._main_fade,   neon.target_main[0]   and 1 or 0, CBUGER_GET_ANIM_RATE(15))
            neon._editor_fade = Data.nfn.anim_update(neon._editor_fade, neon.target_editor[0] and 1 or 0, CBUGER_GET_ANIM_RATE(15))
        else
            neon._main_fade   = neon.target_main[0]   and 1 or 0
            neon._editor_fade = neon.target_editor[0] and 1 or 0
        end
        neon.main_alpha   = neon._main_fade   * ui.interface_alpha[0]
        neon.editor_alpha = neon._editor_fade * ui.interface_alpha[0]
        local io = Lib.imgui.GetIO()
        if not Lib.imgui.IsMouseDown(0) then
            neon.is_dragging        = false; neon.is_resizing        = false
            neon.editor_is_dragging = false; neon.editor_is_resizing = false
        end
        pcall(function() style.WindowRounding   = 20 end)
        pcall(function() style.FrameRounding    =  8 end)
        pcall(function() style.GrabRounding     =  8 end)
        pcall(function() style.ChildRounding    =  8 end)
        pcall(function() style.WindowBorderSize =  0 end)
        pcall(function() style.FrameBorderSize  =  0 end)
        pcall(function() style.ChildBorderSize  =  0 end)
        pcall(function() style.PopupBorderSize = 0 end)
        local has_pushed_font = false
        local font_idx = neon.current_font_idx[0]
        local font_slot = font_idx
        if font_idx > 0 and font_slot <= #Data.neon_loaded_fonts then
            local fnt = Data.neon_loaded_fonts[font_slot]
            if fnt ~= nil then
                local ok = pcall(Lib.imgui.PushFont, fnt)
                if ok then has_pushed_font = true end
            end
        end
        local updated_cursor = false
        local function render_main_window()
        if neon.main_alpha > 0.01 then
            neon.current_rendering_window   = "main"
            neon.current_frame_max_w        = neon.window_size.w
            local target_global_alpha = 1.0
            neon._global_fade = Data.nfn.anim_update(neon._global_fade, target_global_alpha, CBUGER_GET_ANIM_RATE(10))
            neon.global_alpha = neon._global_fade * ui.interface_alpha[0]
            neon.is_any_slider_active = false
            neon.eye_anim_state = Data.nfn.anim_update(neon.eye_anim_state, neon.is_collapsed and 1 or 0, CBUGER_GET_ANIM_RATE(10))
            local actual_h = neon.window_size.h - (neon.window_size.h - 50) * neon.eye_anim_state
            if neon.is_resizing then
                neon.window_size.w = math.max(400, neon.resize_start_size.w + (io.MousePos.x - neon.resize_start_mouse.x))
                neon.window_size.h = math.max(400, neon.resize_start_size.h + (io.MousePos.y - neon.resize_start_mouse.y))
                actual_h = neon.window_size.h
            else
                if not neon.is_collapsed and neon.eye_anim_state < 0.1 then
                    neon.content_max_w = Data.nfn.anim_update(neon.content_max_w, neon.current_frame_max_w, 5)
                end
                neon.window_size.w = Data.nfn.anim_update(neon.window_size.w, math.max(neon.window_size.w, neon.content_max_w), 10)
            end
            if neon.is_dragging then
               Lib.imgui.SetNextWindowPos(Lib.imgui.ImVec2(io.MousePos.x - neon.drag_offset.x, io.MousePos.y - neon.drag_offset.y), Lib.imgui.Cond.Always)
            end
           Lib.imgui.SetNextWindowSize(Lib.imgui.ImVec2(neon.window_size.w, actual_h), Lib.imgui.Cond.Always)
            local pushes_count = 0
           Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg, Lib.imgui.ImVec4(0,0,0,0)); pushes_count = pushes_count + 1
            local pop_b_col = Data.neon_active_colors[Lib.imgui.Col.Border] or {1,1,1,1}
           Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(pop_b_col[1],pop_b_col[2],pop_b_col[3],(pop_b_col[4] or 1)*neon.main_alpha)); pushes_count = pushes_count + 1
            if Lib.imgui.Col.PopupBg then
                local pbc = Data.neon_active_colors[Lib.imgui.Col.PopupBg] or {0.08,0.08,0.1,0.98}
               Lib.imgui.PushStyleColor(Lib.imgui.Col.PopupBg, Lib.imgui.ImVec4(pbc[1],pbc[2],pbc[3],(pbc[4] or 0.98)*neon.main_alpha)); pushes_count = pushes_count + 1
            end
           Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(0,0))
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.Alpha, neon.main_alpha)
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowBorderSize, 0)
           Lib.imgui.Begin("##KeyBoardNeonMain", nil,
               Lib.imgui.WindowFlags.NoTitleBar + Lib.imgui.WindowFlags.NoResize +
               Lib.imgui.WindowFlags.NoMove     + Lib.imgui.WindowFlags.NoScrollbar +
               Lib.imgui.WindowFlags.NoScrollWithMouse)
                local dl       = Lib.imgui.GetWindowDrawList()
                local win_pos  = Lib.imgui.GetWindowPos()
                local win_size = Lib.imgui.GetWindowSize()
                local p_min    = win_pos
                local p_max    = Lib.imgui.ImVec2(win_pos.x + win_size.x, win_pos.y + win_size.y)
                local win_bg_c = Data.neon_active_colors[Lib.imgui.Col.WindowBg] or Data.neon_win_bg
                local DYNAMIC_COLOR_BG = Data.nfn.pack_color(win_bg_c[1],win_bg_c[2],win_bg_c[3],win_bg_c[4] or 0.97,true,neon.main_alpha)
                local mp = io.MousePos
                local wheel_ok = Data.nfn.scroll.wheel_allowed(p_min, p_max, mp)
                dl:AddRectFilled(p_min, p_max, DYNAMIC_COLOR_BG, 20)
               Data.nfn.draw_police_ambient(dl, p_min, p_max, neon.main_alpha)
               Data.nfn.draw_neon_border(dl, p_min, p_max, neon.main_alpha)
                local title_pos = Lib.imgui.ImVec2(p_min.x + 32, p_min.y + 12)
                local tmc = neon_fx.title_main_color
                local drag_hit = Lib.imgui.ImVec2(28, 24)
               Lib.imgui.SetCursorScreenPos(title_pos)
                if Lib.imgui.InvisibleButton("##neon_title_btn", drag_hit) then
                    neon.is_discord_layout = not neon.is_discord_layout
                end
                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                neon.title_anim_state = Data.nfn.anim_update(neon.title_anim_state, Lib.imgui.IsItemHovered() and 1 or 0, CBUGER_GET_ANIM_RATE(15))
                local dots_center = Lib.imgui.ImVec2(title_pos.x + drag_hit.x / 2, title_pos.y + drag_hit.y / 2)
                local dots_col = {
                   Data.nfn.lerp(tmc[1], 1, neon.title_anim_state),
                   Data.nfn.lerp(tmc[2], 1, neon.title_anim_state),
                   Data.nfn.lerp(tmc[3], 1, neon.title_anim_state),
                    (tmc[4] or 1) * neon.global_alpha
                }
               Data.nfn.draw_dots_toggle(dl, dots_center, neon.is_discord_layout, neon.title_anim_state, dots_col, neon.main_alpha)
                local lang_pos = Lib.imgui.ImVec2(title_pos.x + drag_hit.x + 10, title_pos.y - 2)
                local lang_hit = Lib.imgui.ImVec2(30, 24)
               Lib.imgui.SetCursorScreenPos(lang_pos)
                if Lib.imgui.InvisibleButton("##neon_lang_btn", lang_hit) then
                    ui.interface_lang[0] = (ui.interface_lang[0] == 2) and 1 or 2
                    S.cfg.config.interface_lang = ui.interface_lang[0]
                   Lib.inicfg.save(S.cfg, Data.iniFile)
                end
                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                neon.lang_anim_state = Data.nfn.anim_update(neon.lang_anim_state or 0, Lib.imgui.IsItemHovered() and 1 or 0, CBUGER_GET_ANIM_RATE(15))
                local lang_col = {
                   Data.nfn.lerp(tmc[1], 1, neon.lang_anim_state),
                   Data.nfn.lerp(tmc[2], 1, neon.lang_anim_state),
                   Data.nfn.lerp(tmc[3], 1, neon.lang_anim_state),
                    (tmc[4] or 1) * neon.global_alpha
                }
                local lang_label = (ui.interface_lang[0] == 2) and "EN" or "RU"
                local lang_txt_col = Data.nfn.pack_color(lang_col[1], lang_col[2], lang_col[3], lang_col[4], false, neon.main_alpha)
                local lang_txt_size = Lib.imgui.CalcTextSize(lang_label)
                local lang_txt_pos = Lib.imgui.ImVec2(lang_pos.x + (lang_hit.x - lang_txt_size.x) / 2, lang_pos.y + (lang_hit.y - lang_txt_size.y) / 2)
                dl:AddText(lang_txt_pos, lang_txt_col, lang_label)
                local cross_p = Lib.imgui.ImVec2(p_min.x + neon.window_size.w - 25, p_min.y + 25)
               Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(cross_p.x - 15, cross_p.y - 15))
                if Lib.imgui.InvisibleButton("##neon_close", Lib.imgui.ImVec2(30, 30)) then
                    neon.target_main[0] = false
                end
               Data.nfn.draw_cross(dl, cross_p, 12, Lib.imgui.IsItemHovered(), neon.main_alpha)
                local eye_p = Lib.imgui.ImVec2(p_min.x + neon.window_size.w - 65, p_min.y + 25)
               Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(eye_p.x - 15, eye_p.y - 15))
                if Lib.imgui.InvisibleButton("##neon_eye", Lib.imgui.ImVec2(30, 30)) then
                    neon.is_collapsed = not neon.is_collapsed
                end
               Data.nfn.draw_eye(dl, eye_p, 12, neon.eye_anim_state, Lib.imgui.IsItemHovered(), neon.main_alpha)
                if Lib.imgui.IsMouseClicked(0) and Lib.imgui.IsWindowHovered() then
                    if mp.y >= p_min.y and mp.y <= p_min.y + 45 and mp.x >= p_min.x and mp.x <= p_min.x + neon.window_size.w then
                        neon.is_dragging     = true
                        neon.drag_offset.x   = mp.x - win_pos.x
                        neon.drag_offset.y   = mp.y - win_pos.y
                    end
                end
                if not neon.is_collapsed then
                   Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(20, 55))
                    neon.slider_pos = Data.nfn.anim_update(neon.slider_pos, neon.current_tab, CBUGER_GET_ANIM_RATE(14))
                    local tp   = Lib.imgui.ImVec2(p_min.x + 20, p_min.y + 55)
                    local tc   = neon_fx.tabs_color
                    local tb_c = neon_fx.tab_buttons_text_color
                    if neon.is_discord_layout then
                        local sidebar_w = 110
                        dl:AddRectFilled(tp, Lib.imgui.ImVec2(tp.x+sidebar_w, tp.y+neon.window_size.h-75), Data.nfn.pack_color(1,1,1,0.04,false,neon.main_alpha), 15)
                        local item_h = 42
                        local s_min = Lib.imgui.ImVec2(tp.x+3, tp.y+(item_h*(neon.slider_pos-1))+3)
                        local s_max = Lib.imgui.ImVec2(tp.x+sidebar_w-3, tp.y+(item_h*neon.slider_pos)-3)
                        dl:AddRectFilled(s_min, s_max, Data.nfn.pack_color(tc[1],tc[2],tc[3],0.15,false,neon.main_alpha), 12)
                       Data.nfn.draw_wave_strings(dl, s_min, s_max, neon_fx.waves_color, neon.main_alpha)
                        for i = 1, 4 do
                           Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(tp.x, tp.y+item_h*(i-1)))
                            if Lib.imgui.InvisibleButton("ntab_"..i, Lib.imgui.ImVec2(sidebar_w, item_h)) then
                                Data.nfn.scroll.on_tab_click(neon.sc, i, neon.current_tab)
                                neon.current_tab = i
                            end
                            if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                            local tic  = neon_fx.tab_icon_color
                            local igs  = Lib.imgui.CalcTextSize(Data.neon_lists.tab_icons[i])
                            local tgs  = Lib.imgui.CalcTextSize(Fn.T(Data.neon_lists.tab_labels[i]))
                            local gap  = 6
                            local total_w = igs.x + gap + tgs.x
                            local tb_alpha = neon.current_tab == i and 1 or 0.4
                            local start_x  = tp.x + (sidebar_w - total_w) / 2
                            local center_y = tp.y + item_h*(i-1) + item_h/2
                            dl:AddText(Lib.imgui.ImVec2(start_x, center_y - igs.y/2),
                               Data.nfn.pack_color(tic[1],tic[2],tic[3],tb_alpha*(tic[4] or 1),false,neon.main_alpha), Data.neon_lists.tab_icons[i])
                            dl:AddText(Lib.imgui.ImVec2(start_x + igs.x + gap, center_y - tgs.y/2),
                               Data.nfn.pack_color(tb_c[1],tb_c[2],tb_c[3],tb_alpha*(tb_c[4] or 1),false,neon.main_alpha), Fn.T(Data.neon_lists.tab_labels[i]))
                        end
                    else
                        local tw   = neon.window_size.w - 40
                        dl:AddRectFilled(tp, Lib.imgui.ImVec2(tp.x + tw, tp.y + 42), Data.nfn.pack_color(1,1,1,0.04,false,neon.main_alpha), 21)
                        local iw   = tw / 4
                        local _TL = (function()
                            local n, tws, sum = 4, {}, 0
                            for k = 1, n do
                                local a1 = Lib.imgui.CalcTextSize(Data.neon_lists.tab_icons[k])
                                local a2 = Lib.imgui.CalcTextSize(Fn.T(Data.neon_lists.tab_labels[k]))
                                tws[k] = a1.x + 6 + a2.x
                                sum = sum + tws[k]
                            end
                            local pad = math.max(6, (tw - sum) / n)
                            local cs, cw, x = {}, {}, 0
                            for k = 1, n do cw[k] = tws[k] + pad; cs[k] = x; x = x + cw[k] end
                            local function cell(pos)
                                local i0 = math.max(1, math.min(n, math.floor(pos)))
                                local i1 = math.min(n, i0 + 1)
                                local f = math.max(0, math.min(1, pos - i0))
                                return cs[i0] + (cs[i1] - cs[i0]) * f, cw[i0] + (cw[i1] - cw[i0]) * f
                            end
                            return { cs = cs, cw = cw, cell = cell }
                        end)()
                        _TL.sx, _TL.sw = _TL.cell(neon.slider_pos)
                        local s_min = Lib.imgui.ImVec2(tp.x + _TL.sx + 3, tp.y + 3)
                        local s_max = Lib.imgui.ImVec2(tp.x + _TL.sx + _TL.sw - 3, tp.y + 39)
                        dl:AddRectFilled(s_min, s_max, Data.nfn.pack_color(tc[1],tc[2],tc[3],0.15,false,neon.main_alpha), 18)
                       Data.nfn.draw_wave_strings(dl, s_min, s_max, neon_fx.waves_color, neon.main_alpha)
                        for i = 1, 4 do
                           Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(tp.x + _TL.cs[i], tp.y))
                            if Lib.imgui.InvisibleButton("ntab_" .. i, Lib.imgui.ImVec2(_TL.cw[i], 42)) then
                                Data.nfn.scroll.on_tab_click(neon.sc, i, neon.current_tab)
                                neon.current_tab = i
                            end
                            if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                            local tic  = neon_fx.tab_icon_color
                            local igs  = Lib.imgui.CalcTextSize(Data.neon_lists.tab_icons[i])
                            local tgs  = Lib.imgui.CalcTextSize(Fn.T(Data.neon_lists.tab_labels[i]))
                            local gap  = 6
                            local total_w = igs.x + gap + tgs.x
                            local tb_alpha = neon.current_tab == i and 1 or 0.4
                            local start_x  = tp.x + _TL.cs[i] + (_TL.cw[i] - total_w)/2
                            local center_y = tp.y + 21
                            dl:AddText(Lib.imgui.ImVec2(start_x, center_y - igs.y/2),
                               Data.nfn.pack_color(tic[1],tic[2],tic[3],tb_alpha*(tic[4] or 1),false,neon.main_alpha), Data.neon_lists.tab_icons[i])
                            dl:AddText(Lib.imgui.ImVec2(start_x + igs.x + gap, center_y - tgs.y/2),
                               Data.nfn.pack_color(tb_c[1],tb_c[2],tb_c[3],tb_alpha*(tb_c[4] or 1),false,neon.main_alpha), Fn.T(Data.neon_lists.tab_labels[i]))
                        end
                    end
                    local content_x = neon.is_discord_layout and 140 or 20
                    local content_y = neon.is_discord_layout and 55  or 110
                    local child_w   = neon.is_discord_layout and (neon.window_size.w - 160) or (neon.window_size.w - 40)
                    local child_h   = neon.is_discord_layout and (neon.window_size.h - 90)  or (neon.window_size.h - 140)
                   Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(content_x, content_y))
                    local NS = Data.nfn.scroll
                    NS.begin_frame(neon.sc, neon.current_tab, child_h, io, wheel_ok)
                   Lib.imgui.BeginChild("##NeonMainArea", Lib.imgui.ImVec2(child_w, child_h), false,
                        Lib.imgui.WindowFlags.NoScrollbar + Lib.imgui.WindowFlags.NoScrollWithMouse)
                        local cw = child_w
                        neon.anim_tab_pos = Data.nfn.anim_update(neon.anim_tab_pos, neon.current_tab, CBUGER_GET_ANIM_RATE(12))
                        local sx = -(neon.anim_tab_pos - 1) * (cw + 40)
                        local function ndraw_p(idx, cb)
                           Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(sx + (cw + 40) * (idx - 1), -NS.offset(neon.sc, idx)))
                           Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(20, 20))
                           Lib.imgui.BeginChild("NPage_" .. idx, Lib.imgui.ImVec2(cw, NS.page_height(neon.sc, idx)), false,
                                Lib.imgui.WindowFlags.NoScrollbar + Lib.imgui.WindowFlags.NoScrollWithMouse)
                           Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(10, 15))
                           Lib.imgui.BeginGroup()
                            cb()
                           Lib.imgui.EndGroup()
                            local content_bottom = Lib.imgui.GetItemRectMax().y - Lib.imgui.GetWindowPos().y
                            NS.set_content(neon.sc, idx, content_bottom + NS.PAD_BOTTOM + ((Data.ofs_pad and Data.ofs_pad[idx]) or 0))
                           Lib.imgui.EndChild()
                           Lib.imgui.PopStyleVar()
                        end
                        section_header = function(icon, text)
                            local ic = neon_fx.section_icon_color
                            local td = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                            local start_pos = Lib.imgui.GetCursorScreenPos()
                           Lib.imgui.TextColored(
                               Lib.imgui.ImVec4(ic[1], ic[2], ic[3], (ic[4] or 1) * neon.global_alpha),
                                icon)
                           Lib.imgui.SameLine(0, 6)
                           Lib.imgui.TextColored(
                               Lib.imgui.ImVec4(td[1], td[2], td[3], (td[4] or 1) * neon.global_alpha),
                                text)
                            local text_max = Lib.imgui.GetItemRectMax()
                            local text_h   = Lib.imgui.GetItemRectSize().y
                            local dl2  = Lib.imgui.GetWindowDrawList()
                            local ly   = start_pos.y + text_h + 1
                            dl2:AddLine(
                               Lib.imgui.ImVec2(start_pos.x, ly),
                               Lib.imgui.ImVec2(text_max.x + 24, ly),
                               Data.nfn.pack_color(td[1], td[2], td[3], 0.35, false, neon.main_alpha), 1)
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 4))
                        end
                        local function card(draw_fn)
                            local tc2 = neon_fx.title_color
                            local bg  = Data.neon_active_colors[Lib.imgui.Col.WindowBg] or {0.04,0.04,0.07,0.97}
                            local dl2 = Lib.imgui.GetWindowDrawList()
                           Lib.imgui.SetCursorPosX(Lib.imgui.GetCursorPosX() + 4)
                           Lib.imgui.BeginGroup()
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 6))
                            draw_fn()
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 6))
                           Lib.imgui.EndGroup()
                            local rmin = Lib.imgui.GetItemRectMin()
                            local rmax = Lib.imgui.GetItemRectMax()
                            rmin.x = rmin.x - 8; rmax.x = rmax.x + 8
                            dl2:AddRectFilled(rmin, rmax,
                               Data.nfn.pack_color(bg[1]+0.05,bg[2]+0.05,bg[3]+0.07,0.65,false,neon.main_alpha), 10)
                        end
                        ndraw_p(1, function()
                            section_header(fa.GEAR, Fn.T(u8"Скрипт"))
                           Data.nfn.ios_toggle(Fn.T(u8"Общая активация"),  ui.script_enabled,     neon.main_alpha)
                           Data.applyScriptMaster(false)
                           fixed_gap("g01", 5)
                           Data.nfn.ios_toggle(Fn.T(u8"Клавиатура"),       ui.keyboard,           neon.main_alpha); fixed_gap("g02", 5)
                           Data.nfn.ios_toggle(Fn.T(u8"Мышь"),             ui.mouse,              neon.main_alpha); fixed_gap("g03", 5)
                           Data.nfn.ios_toggle(Fn.T(u8"Пробел = Shift"),   ui.space_as_shift,     neon.main_alpha); fixed_gap("g04", 5)
                           Data.nfn.ios_toggle(Fn.T(u8"Перемещение клавиатуры"), ui.move,               neon.main_alpha); fixed_gap("g05", 5)
                           Data.nfn.ios_toggle(Fn.T(u8"Сообщения в чате"), ui.show_chat_messages, neon.main_alpha)
                           fixed_gap("g06", 12)
                            section_header(fa.GLOBE, Fn.T(u8"Язык клавиатуры"))
                            do
                                fixed_row_begin("gr_lang")
                                local lm = ui.language_mode[0]
                                local _lba  = Data.neon_active_colors[Lib.imgui.Col.Button]       or {0.2,0.2,0.2,0.85}
                                local _lba_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.4,0.4,0.4,1.0}
                                local btn_act = Lib.imgui.ImVec4(_lba_a[1],_lba_a[2],_lba_a[3],_lba_a[4] or 0.95)
                                local btn_def = Lib.imgui.ImVec4(_lba[1],_lba[2],_lba[3],_lba[4] or 0.85)
                                local hw = (cw - 50) / 2
                               Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 10)
                                local _lang_h = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or {0.35,0.35,0.35,1.0}
                               Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        lm == 1 and btn_act or btn_def)
                               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_lang_h[1],_lang_h[2],_lang_h[3],_lang_h[4] or 1.0))
                               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  btn_act)
                                Data.nfn.PushButtonBorder()
                                if Lib.imgui.Button("RU##nlang", Lib.imgui.ImVec2(hw, 30)) then
                                    ui.language_mode[0] = 1; S.cfg.config.language_mode = 1; Lib.inicfg.save(S.cfg, Data.iniFile)
                                end
                                Data.nfn.PopButtonBorder()
                               Lib.imgui.PopStyleColor(3)
                               Lib.imgui.SameLine(0, 6)
                               Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        lm == 2 and btn_act or btn_def)
                               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_lang_h[1],_lang_h[2],_lang_h[3],_lang_h[4] or 1.0))
                               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  btn_act)
                                Data.nfn.PushButtonBorder()
                                if Lib.imgui.Button("EN##nlang", Lib.imgui.ImVec2(hw, 30)) then
                                    ui.language_mode[0] = 2; S.cfg.config.language_mode = 2; Lib.inicfg.save(S.cfg, Data.iniFile)
                                end
                                Data.nfn.PopButtonBorder()
                               Lib.imgui.PopStyleColor(3)
                               Lib.imgui.PopStyleVar()
                            end
                           fixed_gap("g07", 12)
                            section_header(fa.CLOCK_ROTATE_LEFT, Fn.T(u8"Логи нажатий"))
                           Data.nfn.ios_toggle(Fn.T(u8"Показывать логи"),      ui.show_logs,        neon.main_alpha); fixed_gap("g08", 5)
                           Data.nfn.ios_toggle(Fn.T(u8"RGB (Логи / Комбо)"),   ui.logs_combo_rgb,   neon.main_alpha); fixed_gap("g09", 7)
                           Data.nfn.ios_slider(Fn.T(u8"Кнопок в ряд"),         ui.logs_limit_row,    3, 20, neon.main_alpha); fixed_gap("g10", 7)
                           Data.nfn.ios_slider(Fn.T(u8"Показывать последних"), ui.logs_max_display,  1, 50, neon.main_alpha)
                           fixed_gap("g11", 12)
                           fixed_gap("g12", 16)
                        end)
                        ndraw_p(2, function()
                            local tc2 = neon_fx.title_color
                            section_header(fa.KEYBOARD, Fn.T(u8"Клавиатура"))
                            do
                                local kb_mode_names = {
                                    Fn.T(u8"Тренировочная (W A S D Q E / C / ПРОБЕЛ)"),
                                    Fn.T(u8"Вся клавиатура"),
                                    Fn.T(u8"Клавиатура без NumPad"),
                                }
                                local kb_mode_items = Lib.new["const char*"][#kb_mode_names](kb_mode_names)
                                Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 8)
                                                                Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(8, 0))
                                if Lib.imgui.Combo(Fn.T(u8"Вариант клавиатуры"), ui.keyboard_type, kb_mode_items, #kb_mode_names) then
                                    S.cfg.config.keyboard_type = ui.keyboard_type[0]
                                    if ui.keyboard_type[0] == 1 then
                                        ui.mouse[0] = true
                                        S.cfg.mouse.active = true
                                    end
                                    Lib.inicfg.save(S.cfg, Data.iniFile)
                                end
                                Lib.imgui.PopStyleVar()
                                Lib.imgui.PopStyleVar()
                            end
                            fixed_gap("s01", 7)
                           fixed_slider_begin("ls_keyboard_scale")
                           Data.nfn.ios_slider(Fn.T(u8"Размер"),              ui.keyboard_scale,     0.5, 2.0, neon.main_alpha); fixed_gap("s02", 7)
                           fixed_slider_begin("ls_keyboard_alpha")
                           Data.nfn.ios_slider(Fn.T(u8"Прозрачность клавиш"), ui.keyboard_key_alpha, 0.0, 1.0, neon.main_alpha); fixed_gap("s03", 7)
                           fixed_slider_begin("ls_text_alpha")
                           Data.nfn.ios_slider(Fn.T(u8"Прозрачность текста"),  ui.text_alpha,         0.0, 1.0, neon.main_alpha, true); fixed_gap("s04", 7)
                           fixed_slider_begin("ls_border_thickness")
                           Data.nfn.ios_slider(Fn.T(u8"Толщина обводки"),      Data.border_thickness,      0.5, 3.0, neon.main_alpha); fixed_gap("s05", 7)
                           fixed_slider_begin("ls_combo_scale")
                           Data.nfn.ios_slider(Fn.T(u8"Масштаб комбо"),        ui.combo_window_scale, 0.5, 2.0, neon.main_alpha); fixed_gap("s06", 7)
                            do
                                fixed_row_begin("gr_style_border")
                                local bm_names = {Fn.T(u8"Выкл"), Fn.T(u8"Вкл"), Fn.T(u8"При нажатии")}
                                do local td_=Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
Lib.imgui.TextColored(Lib.imgui.ImVec4(td_[1],td_[2],td_[3],(td_[4] or 1)),Fn.T(u8"Обводка:")) end
                               Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 8)
                                for bi = 1, 3 do
                                    if bi > 1 then Lib.imgui.SameLine(0, 4) end
                                    local active = ui.border_mode[0] == bi
                                    local _btn_n = Data.neon_active_colors[Lib.imgui.Col.Button]        or {0.2,0.2,0.2,0.85}
                                    local _btn_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive]  or {0.4,0.4,0.4,1.0}
                                    local _btn_h = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or {0.35,0.35,0.35,1.0}
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, active
                                        and Lib.imgui.ImVec4(_btn_a[1],_btn_a[2],_btn_a[3],_btn_a[4] or 0.95)
                                        or  Lib.imgui.ImVec4(_btn_n[1],_btn_n[2],_btn_n[3],_btn_n[4] or 0.85))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_btn_h[1],_btn_h[2],_btn_h[3],_btn_h[4] or 1.0))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(_btn_a[1],_btn_a[2],_btn_a[3],_btn_a[4] or 1.0))
                                    local bm_btn_w = (bi == 3) and 100 or 60
                                    Data.nfn.PushButtonBorder()
                                    if Lib.imgui.Button(bm_names[bi].."##bm"..bi, Lib.imgui.ImVec2(bm_btn_w, 24)) then
                                        ui.border_mode[0] = bi; S.cfg.config.border_mode = bi; Lib.inicfg.save(S.cfg, Data.iniFile)
                                    end
                                    Data.nfn.PopButtonBorder()
                                   Lib.imgui.PopStyleColor(3)
                                end
                               Lib.imgui.PopStyleVar()
                            end
                           fixed_gap("s07", 12)
                            section_header(fa.WAVE_SQUARE, Fn.T(u8"Волна на клавишах"))
                           Data.nfn.ios_toggle(Fn.T(u8"Включить волну"), ui.wave_enabled,      neon.main_alpha); fixed_gap("s08", 7)
                           fixed_slider_begin("ls_wave_speed")
                           Data.nfn.ios_slider(Fn.T(u8"Скорость"),        ui.wave_speed,        0.1, 4.0, neon.main_alpha); fixed_gap("s09", 7)
                           fixed_slider_begin("ls_wave_transparency")
                           Data.nfn.ios_slider(Fn.T(u8"Прозрачность"),    ui.wave_transparency, 0.0, 1.0, neon.main_alpha); fixed_gap("s10", 7)
                            do
                                fixed_row_begin("gr_wave_dir")
                                local wm_names = {Fn.T(u8"<>"), Fn.T(u8"><"), Fn.T(u8"^v"), Fn.T(u8"v^")}
                                local wm_btn_w = 44
                                do local td_=Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
Lib.imgui.TextColored(Lib.imgui.ImVec4(td_[1],td_[2],td_[3],(td_[4] or 1)),Fn.T(u8"Направление:")) end
                               Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 8)
                                for wi = 1, 4 do
                                    if wi > 1 then Lib.imgui.SameLine(0, 4) end
                                    local active = ui.wave_mode[0] == wi
                                    local _wm_n = Data.neon_active_colors[Lib.imgui.Col.Button]       or {0.2,0.2,0.2,0.85}
                                    local _wm_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.4,0.4,0.4,1.0}
                                    local _wm_h = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or {0.35,0.35,0.35,1.0}
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, active
                                        and Lib.imgui.ImVec4(_wm_a[1],_wm_a[2],_wm_a[3],_wm_a[4] or 0.95)
                                        or  Lib.imgui.ImVec4(_wm_n[1],_wm_n[2],_wm_n[3],_wm_n[4] or 0.85))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_wm_h[1],_wm_h[2],_wm_h[3],_wm_h[4] or 1.0))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(_wm_a[1],_wm_a[2],_wm_a[3],_wm_a[4] or 1.0))
                                    Data.nfn.PushButtonBorder()
                                    if Lib.imgui.Button(wm_names[wi].."##wm"..wi, Lib.imgui.ImVec2(wm_btn_w, 24)) then
                                        ui.wave_mode[0] = wi; S.cfg.config.wave_mode = wi; Lib.inicfg.save(S.cfg, Data.iniFile)
                                    end
                                    Data.nfn.PopButtonBorder()
                                   Lib.imgui.PopStyleColor(3)
                                end
                               Lib.imgui.PopStyleVar()
                            end
                           fixed_gap("s11", 7)
                            do
                                fixed_row_begin("gr_wave_target")
                                local wt_names = {Fn.T(u8"Клавиши"), Fn.T(u8"Обводка"), Fn.T(u8"Текст"), Fn.T(u8"Всё")}
                                do local td_=Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
Lib.imgui.TextColored(Lib.imgui.ImVec4(td_[1],td_[2],td_[3],(td_[4] or 1)),Fn.T(u8"Режим волны:")) end
                               Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 8)
                                for wi = 1, 4 do
                                    if wi > 1 then Lib.imgui.SameLine(0, 4) end
                                    local active = ui.wave_target[0] == wi
                                    local _wt_n = Data.neon_active_colors[Lib.imgui.Col.Button]       or {0.2,0.2,0.2,0.85}
                                    local _wt_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.4,0.4,0.4,1.0}
                                    local _wt_h = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or {0.35,0.35,0.35,1.0}
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, active
                                        and Lib.imgui.ImVec4(_wt_a[1],_wt_a[2],_wt_a[3],_wt_a[4] or 0.95)
                                        or  Lib.imgui.ImVec4(_wt_n[1],_wt_n[2],_wt_n[3],_wt_n[4] or 0.85))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_wt_h[1],_wt_h[2],_wt_h[3],_wt_h[4] or 1.0))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(_wt_a[1],_wt_a[2],_wt_a[3],_wt_a[4] or 1.0))
                                    Data.nfn.PushButtonBorder()
                                    local wt_text_sz = Lib.imgui.CalcTextSize(wt_names[wi])
                                    local wt_btn_w = math.max(52, wt_text_sz.x + 20)
                                    if Lib.imgui.Button(wt_names[wi].."##wt"..wi, Lib.imgui.ImVec2(wt_btn_w, 24)) then
                                        ui.wave_target[0] = wi; S.cfg.config.wave_target = wi; Lib.inicfg.save(S.cfg, Data.iniFile)
                                    end
                                    Data.nfn.PopButtonBorder()
                                   Lib.imgui.PopStyleColor(3)
                                end
                               Lib.imgui.PopStyleVar()
                            end
                           fixed_gap("s12", 7)
                           Data.nfn.ios_toggle(Fn.T(u8"RGB волна"), ui.wave_color_rgb, neon.main_alpha)
                           fixed_gap("s13", 7)
                           Data.nfn.ios_toggle(Fn.T(u8"Рандомные цвета волны"), ui.wave_random_colors, neon.main_alpha)
                           fixed_gap("s14", 7)
                            if Data.nfn.CustomColorPicker(Fn.T(u8"Цвет волны"), "wave_col", Data.neon_wave_color_tbl, true, neon.main_alpha) then
                                ui.wave_color_if4[0]=Data.neon_wave_color_tbl[1]; ui.wave_color_if4[1]=Data.neon_wave_color_tbl[2]
                                ui.wave_color_if4[2]=Data.neon_wave_color_tbl[3]; ui.wave_color_if4[3]=Data.neon_wave_color_tbl[4]
                                S.cfg.config.wave_r=Data.neon_wave_color_tbl[1]; S.cfg.config.wave_g=Data.neon_wave_color_tbl[2]
                                S.cfg.config.wave_b=Data.neon_wave_color_tbl[3]; S.cfg.config.wave_a=Data.neon_wave_color_tbl[4]
                               Lib.inicfg.save(S.cfg, Data.iniFile)
                            end
                           fixed_gap("s15", 12)
                            local function neon_color_popup(label, popup_id, if4, color_table, cfg_key)
                                local cpsize = Lib.imgui.ImVec2(26, 26)
                                local cppos  = Lib.imgui.GetCursorScreenPos()
                                local cpdl   = Lib.imgui.GetWindowDrawList()
                                cpdl:AddCircleFilled(Lib.imgui.ImVec2(cppos.x+13, cppos.y+13), 11,
                                   Fn.getColorU32Global(if4[0], if4[1], if4[2], if4[3], true), 24)
                                local _cbc = neon_fx.button_border_color
                                cpdl:AddCircle(Lib.imgui.ImVec2(cppos.x+13, cppos.y+13), 12,
                                   Data.nfn.pack_color(_cbc[1], _cbc[2], _cbc[3], (_cbc[4] or 1) * 0.8, false, neon.main_alpha), 24, 1)
                                if Lib.imgui.InvisibleButton("##ncp_"..popup_id, cpsize) then
                                   Lib.imgui.OpenPopup("ncp_popup_"..popup_id)
                                end
                                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                               Lib.imgui.SameLine(0, 8)
                               Lib.imgui.SetCursorPosY(Lib.imgui.GetCursorPosY() + 4)
                               Lib.imgui.Text(label)
                                Data.nfn.BeginColorPopupStyle()
                                if Lib.imgui.BeginPopup("ncp_popup_"..popup_id) then
                                    local popup_text_col = Data.neon_active_colors[Lib.imgui.Col.Text] or {1,1,1,1}
                                    Lib.imgui.TextColored(Lib.imgui.ImVec4(popup_text_col[1], popup_text_col[2], popup_text_col[3], 1), label)
                                    Lib.imgui.Separator()
                                    local combo_picker_flags = Lib.imgui.ColorEditFlags.NoSidePreview + Lib.imgui.ColorEditFlags.NoSmallPreview + (Lib.imgui.ColorEditFlags.AlphaBar or 0)
                                    if Lib.imgui.ColorPicker4("##ncp4_"..popup_id, if4, combo_picker_flags) then
                                        color_table[1]=if4[0]; color_table[2]=if4[1]
                                        color_table[3]=if4[2]; color_table[4]=if4[3]
                                        S.cfg.config[cfg_key.."_r"]=color_table[1]; S.cfg.config[cfg_key.."_g"]=color_table[2]
                                        S.cfg.config[cfg_key.."_b"]=color_table[3]; S.cfg.config[cfg_key.."_a"]=color_table[4]
                                       Lib.inicfg.save(S.cfg, Data.iniFile)
                                    end
                                   Lib.imgui.EndPopup()
                                end
                                Data.nfn.EndColorPopupStyle()
                            end
                            section_header(fa.CIRCLE_HALF_STROKE, Fn.T(u8"Цвета комбо-клавиш"))
                            neon_color_popup(Fn.T(u8"Удержание"), "held",    ui.held_color_if4,    ui.held_color,    "held");    fixed_gap("s16", 5)
                            neon_color_popup(Fn.T(u8"Правильно"), "correct", ui.correct_color_if4, ui.correct_color, "correct"); fixed_gap("s17", 5)
                            neon_color_popup(Fn.T(u8"Ошибка"),    "error",   ui.error_color_if4,   ui.error_color,   "error")
                           fixed_gap("s18", 12)
                            section_header(fa.DROPLET, Fn.T(u8"Цвета клавиш"))
                            do local td_=Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
Lib.imgui.TextColored(Lib.imgui.ImVec4(td_[1],td_[2],td_[3],(td_[4] or 1)),Fn.T(u8"Обычные:")) end; fixed_gap("s19", 4)
                            fixed_row_begin("gr_key_fill")
                            neon_color_popup(Fn.T(u8"Заливка"),  "key_fill",   ui.key_fill_if4,   ui.key_fill_color,   "key_fill")
                           Lib.imgui.SameLine(0, 14)
                            if Lib.imgui.Checkbox("RGB##fill",   ui.key_fill_rgb)   then S.cfg.config.key_fill_rgb   = ui.key_fill_rgb[0];   Lib.inicfg.save(S.cfg, Data.iniFile) end
                           fixed_gap("s20", 4)
                            fixed_row_begin("gr_key_border")
                            neon_color_popup(Fn.T(u8"Обводка"), "key_border", ui.key_border_if4, ui.key_border_color, "key_border")
                           Lib.imgui.SameLine(0, 14)
                            if Lib.imgui.Checkbox("RGB##border", ui.key_border_rgb) then S.cfg.config.key_border_rgb = ui.key_border_rgb[0]; Lib.inicfg.save(S.cfg, Data.iniFile) end
                           fixed_gap("s21", 4)
                            fixed_row_begin("gr_key_text")
                            neon_color_popup(Fn.T(u8"Текст"),   "key_text",   ui.key_text_if4,   ui.key_text_color,   "key_text")
                           Lib.imgui.SameLine(0, 14)
                            if Lib.imgui.Checkbox("RGB##text",   ui.key_text_rgb)   then S.cfg.config.key_text_rgb   = ui.key_text_rgb[0];   Lib.inicfg.save(S.cfg, Data.iniFile) end
                           fixed_gap("s22", 8)
                            do local td_=Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
Lib.imgui.TextColored(Lib.imgui.ImVec4(td_[1],td_[2],td_[3],(td_[4] or 1)),Fn.T(u8"При нажатии:")) end; fixed_gap("s23", 4)
                            fixed_row_begin("gr_pressed_fill")
                            neon_color_popup(Fn.T(u8"Заливка"),  "pressed_fill",   ui.pressed_fill_if4,   ui.pressed_fill_color,   "pressed_fill")
                           Lib.imgui.SameLine(0, 14)
                            Data.nfn.PushButtonBorder()
                            if Lib.imgui.Checkbox(Fn.T(u8"Вкл##pfill"),   ui.pressed_fill_enabled)   then S.cfg.config.pressed_fill_enabled   = ui.pressed_fill_enabled[0];   Lib.inicfg.save(S.cfg, Data.iniFile) end
                            Data.nfn.PopButtonBorder()
                           fixed_gap("s24", 4)
                            fixed_row_begin("gr_pressed_border")
                            neon_color_popup(Fn.T(u8"Обводка"), "pressed_border", ui.pressed_border_if4, ui.pressed_border_color, "pressed_border")
                           Lib.imgui.SameLine(0, 14)
                            Data.nfn.PushButtonBorder()
                            if Lib.imgui.Checkbox(Fn.T(u8"Вкл##pborder"), ui.pressed_border_enabled) then S.cfg.config.pressed_border_enabled = ui.pressed_border_enabled[0]; Lib.inicfg.save(S.cfg, Data.iniFile) end
                            Data.nfn.PopButtonBorder()
                           fixed_gap("s25", 4)
                            fixed_row_begin("gr_pressed_text")
                            neon_color_popup(Fn.T(u8"Текст"),   "pressed_text",   ui.pressed_text_if4,   ui.pressed_text_color,   "pressed_text")
                           Lib.imgui.SameLine(0, 14)
                            Data.nfn.PushButtonBorder()
                            if Lib.imgui.Checkbox(Fn.T(u8"Вкл##ptext"),   ui.pressed_text_enabled)   then S.cfg.config.pressed_text_enabled   = ui.pressed_text_enabled[0];   Lib.inicfg.save(S.cfg, Data.iniFile) end
                            Data.nfn.PopButtonBorder()
                           fixed_gap("s26", 8)
                           fixed_slider_begin("ls_rgb_speed")
                           Data.nfn.ios_slider(Fn.T(u8"Скорость RGB"), ui.rgb_speed, 0.1, 3.0, neon.main_alpha)
                           fixed_gap("s27", 6)
                        end)
                        ndraw_p(3, function()
                            local tc2 = neon_fx.title_color
                            local _cba = Data.neon_active_colors[Lib.imgui.Col.Button] or {tc2[1]*0.1,tc2[2]*0.1,tc2[3]*0.1,0.85}
                            local combo_header_origin = Lib.imgui.GetCursorScreenPos()
                            do
                                local _row_avail = Lib.imgui.GetContentRegionAvail().x
                                local _row_gap   = 6.0
                                local _btn_w_cfg = tonumber(Data.combo_action_btn_width[0]) or 160.0
                                local _btn_w_max = math.max(80.0, (_row_avail - _row_gap) / 2)
                                local _btn_w     = math.max(80.0, math.min(_btn_w_cfg, _btn_w_max))
                                local _group_w      = _btn_w * 2 + _row_gap
                                local _center_x     = math.max(0, (_row_avail - _group_w) * 0.5)
                                local _offset_x     = tonumber(Data.combo_action_btn_offset[0]) or 0.0
                                local _max_offset   = math.max(0, (_row_avail - _group_w) * 0.5)
                                local _group_x      = math.max(0, math.min(_center_x + _offset_x, _center_x + _max_offset))
                                _group_x             = math.min(_group_x, math.max(0, _row_avail - _group_w))
                                local _row_y         = Lib.imgui.GetCursorPosY()
                                local _base_x    = Lib.imgui.GetCursorPosX()
                                do
                                    local _nb = Data.neon_active_colors[Lib.imgui.Col.Button] or {tc2[1]*0.2,tc2[2]*0.2,tc2[3]*0.2,0.9}
                                    Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        Lib.imgui.ImVec4(_nb[1],_nb[2],_nb[3],_nb[4] or 0.9))
                                    Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(tc2[1]*0.4, tc2[2]*0.4, tc2[3]*0.4, 1.0))
                                    Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(tc2[1]*0.6, tc2[2]*0.6, tc2[3]*0.6, 1.0))
                                    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 10)
                                    Lib.imgui.SetCursorPosX(_base_x + _group_x)
                                    local _nb_btn_pos = Lib.imgui.GetCursorScreenPos()
                                    Data.nfn.PushButtonBorder()
                                    local _nb_clicked = Lib.imgui.Button("##new_combo_btn", Lib.imgui.ImVec2(_btn_w, 30))
                                    Data.nfn.PopButtonBorder()
                                    Lib.imgui.PopStyleVar(); Lib.imgui.PopStyleColor(3)
                                    if _nb_clicked then Fn.InitEditor(true, nil) end
                                    if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                                    do
                                        local _nb_dl    = Lib.imgui.GetWindowDrawList()
                                        local _nb_ico   = fa.CIRCLE_PLUS
                                        local _nb_txt   = Fn.T(u8"Новая комбинация")
                                        local _nb_gap   = 8
                                        local _nb_igs   = Lib.imgui.CalcTextSize(_nb_ico)
                                        local _nb_tgs   = Lib.imgui.CalcTextSize(_nb_txt)
                                        local _nb_total = _nb_igs.x + _nb_gap + _nb_tgs.x
                                        local _nb_start_x = _nb_btn_pos.x + math.max(4, (_btn_w - _nb_total) / 2)
                                        local _nb_center_y = _nb_btn_pos.y + 15
                                        local _nb_txt_col = Lib.imgui.ImVec4(1,1,1, neon.main_alpha or 1)
                                        local _nb_txt_u32 = Data.nfn.pack_color(_nb_txt_col.x,_nb_txt_col.y,_nb_txt_col.z,_nb_txt_col.w,false,1)
                                        local _nb_sic     = neon_fx.section_icon_color
                                        local _nb_ico_u32 = Data.nfn.pack_color(_nb_sic[1],_nb_sic[2],_nb_sic[3],(_nb_sic[4] or 1),false,neon.main_alpha)
                                        _nb_dl:AddText(Lib.imgui.ImVec2(_nb_start_x, _nb_center_y - _nb_igs.y/2), _nb_ico_u32, _nb_ico)
                                        _nb_dl:AddText(Lib.imgui.ImVec2(_nb_start_x + _nb_igs.x + _nb_gap, _nb_center_y - _nb_tgs.y/2), _nb_txt_u32, _nb_txt)
                                    end
                                end
                                Lib.imgui.SameLine(0, _row_gap)
                                do
                                    Lib.imgui.SetCursorPosY(_row_y)
                                    Lib.imgui.SetCursorPosX(_base_x + _group_x + _btn_w + _row_gap)
                                    Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        Lib.imgui.ImVec4(0.70, 0.06, 0.08, 0.96))
                                    Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(0.90, 0.10, 0.12, 1.00))
                                    Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(0.55, 0.03, 0.04, 1.00))
                                    Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 10)
                                    Data.nfn.PushButtonBorder()
                                    local _rc_clicked = Lib.imgui.Button(fa.ROTATE_LEFT .. " " .. Fn.T(u8"Сбросить комбо"), Lib.imgui.ImVec2(_btn_w, 30))
                                    Data.nfn.PopButtonBorder()
                                    Lib.imgui.PopStyleVar(); Lib.imgui.PopStyleColor(3)
                                    if _rc_clicked and S.state and S.state.current_combo then
                                        Fn.resetComboFull()
                                        ui.show_combo_window[0] = false
                                        ui.combo_open[0] = false
                                        ui.combo_pos_initialized = false
                                        ui.combo_size_initialized = false
                                        ui.combo_auto_size_signature = nil
                                        S.cfg.config.show_combo_window = false
                                        pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
                                    end
                                    if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                                end
                            end
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 4))
                            local count = #S.combos_list
                            do
                                local sic = neon_fx.section_icon_color
                                local ctd = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                               Lib.imgui.TextColored(Lib.imgui.ImVec4(sic[1], sic[2], sic[3], (sic[4] or 1) * neon.main_alpha), fa.LIST_OL)
                               Lib.imgui.SameLine(0, 6)
                               Lib.imgui.TextColored(Lib.imgui.ImVec4(ctd[1], ctd[2], ctd[3], (ctd[4] or 1) * neon.main_alpha),
                                   Fn.T(u8"Комбинаций: ") .. count)
                            end
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 6))
                            do
                                local count_sel = 0
                                for _, v in pairs(ui.selection.selected_indices) do
                                    if v then count_sel = count_sel + 1 end
                                end
                                if count_sel > 0 then
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        Lib.imgui.ImVec4(0.55,0.08,0.08,0.95))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(0.75,0.1,0.1,1))
                                   Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 8)
                                    local _del_avail = Lib.imgui.GetContentRegionAvail().x
                                    local _del_base  = _del_avail - 20
                                    local _del_w     = math.floor(_del_base * 0.69)
                                   Lib.imgui.SetCursorPosX(Lib.imgui.GetCursorPosX() + math.floor((_del_avail - _del_w) / 2))
                                    Data.nfn.PushButtonBorder()
                                    if Lib.imgui.Button(fa.TRASH_CAN .. " " .. Fn.T(u8"Удалить выделенные") .. " (" .. count_sel .. ")", Lib.imgui.ImVec2(_del_w, 28)) then
                                        local new_list = {}
                                        for idx, v in ipairs(S.combos_list) do
                                            if not ui.selection.selected_indices[idx] then
                                                table.insert(new_list, v)
                                            end
                                        end
                                        S.combos_list = new_list
                                        ui.selection.selected_indices = {}
                                       Fn.saveCombos()
                                    end
                                    Data.nfn.PopButtonBorder()
                                   Lib.imgui.PopStyleVar(); Lib.imgui.PopStyleColor(2)
                                   Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 4))
                                end
                            end
                            local style2 = Lib.imgui.GetStyle()
                            local old_sr = style2.ScrollbarSize; local old_srr = style2.ScrollbarRounding
                            style2.ScrollbarSize = 5; style2.ScrollbarRounding = 10
                            local view_avail = child_h - Lib.imgui.GetCursorPosY() - Data.nfn.scroll.PAD_BOTTOM
                            local list_h     = math.max(40, view_avail, (neon.combo_rows_h or 0) + 6)
                            local combo_tab_origin = Lib.imgui.GetCursorScreenPos()
                            local combo_tab_w      = cw - 20
                            local child_flags2 = Lib.imgui.WindowFlags.NoMove + Lib.imgui.WindowFlags.NoScrollWithMouse
                           Lib.imgui.BeginChild("##NeonComboList", Lib.imgui.ImVec2(cw - 20, list_h), false,
                                child_flags2 + Lib.imgui.WindowFlags.NoScrollbar)
                                local dl_combo    = Lib.imgui.GetWindowDrawList()
                                local cmpos2      = Lib.imgui.GetMousePos()
                                local any_hov2    = false
                                local child_pos2  = Lib.imgui.GetWindowPos()
                                local child_size2 = Lib.imgui.GetWindowSize()
                                for i, combo in ipairs(S.combos_list) do
                                    local is_sel_final = ui.selection.selected_indices[i] == true
                                    local is_prev      = ui.selection.preview_indices[i]  == true
                                    local disp_sel     = is_sel_final or is_prev
                                    local is_drag_this = (ui.dnd.drag_index == i)
                                    local is_active    = S.state.current_combo_index == i
                                    local num_colors = 0
                                    if is_drag_this then
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        Lib.imgui.ImVec4(0,0,0,0))
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(0,0,0,0))
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(0,0,0,0))
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.Text,          Lib.imgui.ImVec4(0,0,0,0))
                                        num_colors = 4
                                    elseif disp_sel then
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, Lib.imgui.ImVec4(tc2[1]*0.3,tc2[2]*0.3,0.0,0.9))
                                        num_colors = 1
                                    elseif is_active then
                                        local _bact_c = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.5,0.5,0.5,1.0}
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        Lib.imgui.ImVec4(_bact_c[1],_bact_c[2],_bact_c[3],_bact_c[4] or 1.0))
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_bact_c[1]*1.1,_bact_c[2]*1.1,_bact_c[3]*1.1,_bact_c[4] or 1.0))
                                        num_colors = 2
                                    else
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, Lib.imgui.ImVec4(_cba[1],_cba[2],_cba[3],_cba[4] or 0.85))
                                        num_colors = 1
                                    end
                                    local _bhov = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or {0.3,0.3,0.3,0.9}
                                    local _bact = Data.neon_active_colors[Lib.imgui.Col.ButtonActive]  or {0.5,0.5,0.5,1.0}
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_bhov[1],_bhov[2],_bhov[3],_bhov[4] or 0.9))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(_bact[1],_bact[2],_bact[3],_bact[4] or 1.0))
                                   Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 8)
                                    Data.nfn.PushButtonBorder()
                                   Lib.imgui.Button(Fn.decodeSafe(combo.name) .. "##nc_" .. i, Lib.imgui.ImVec2(-1, 30))
                                    Data.nfn.PopButtonBorder()
                                    local item_min2 = Lib.imgui.GetItemRectMin()
                                    local item_max2 = Lib.imgui.GetItemRectMax()
                                   Lib.imgui.PopStyleVar()
                                   Lib.imgui.PopStyleColor(num_colors + 2)
                                    if is_active and not is_drag_this then
                                        dl_combo:AddRectFilled(
                                           Lib.imgui.ImVec2(item_min2.x, item_min2.y + 4),
                                           Lib.imgui.ImVec2(item_min2.x + 3, item_max2.y - 4),
                                           Data.nfn.pack_color(tc2[1],tc2[2],tc2[3],0.9,false,neon.main_alpha), 2)
                                    end
                                    local is_hovered2 = Lib.imgui.IsItemHovered()
                                    if is_hovered2 then any_hov2 = true; Data.nfn.set_hand_cursor() end
                                    if is_hovered2 and Lib.imgui.IsMouseReleased(0) and
                                       not ui.selection.dragging and
                                       ui.dnd.drag_index == nil and
                                       not Lib.imgui.IsMouseDragging(0) then
                                       Fn.selectCombo(combo.data, combo.name, i)
                                    end
                                    if is_hovered2 and Lib.imgui.IsMouseDown(0) and Lib.imgui.IsMouseDragging(0) then
                                        if ui.dnd.drag_index == nil and not ui.selection.dragging then
                                            ui.dnd.drag_index = i
                                            ui.dnd.drag_offset = Lib.imgui.ImVec2(
                                                cmpos2.x - item_min2.x,
                                                cmpos2.y - item_min2.y)
                                        end
                                    end
                                    if ui.dnd.drag_index ~= nil and ui.dnd.drag_index ~= i then
                                        if cmpos2.x >= item_min2.x and cmpos2.x <= item_max2.x and
                                           cmpos2.y >= item_min2.y and cmpos2.y <= item_max2.y then
                                            dl_combo:AddRect(item_min2, item_max2,
                                               Data.nfn.pack_color(tc2[1],tc2[2],tc2[3],0.9,false,neon.main_alpha),
                                                8, 15, 2.5)
                                            if ui.dnd.last_hovered_index == i then
                                                ui.dnd.hover_timer = ui.dnd.hover_timer + Lib.imgui.GetIO().DeltaTime
                                                if ui.dnd.hover_timer >= 0.2 then
                                                    local item = table.remove(S.combos_list, ui.dnd.drag_index)
                                                    table.insert(S.combos_list, i, item)
                                                    ui.dnd.drag_index  = i
                                                    ui.dnd.hover_timer = 0
                                                   Fn.saveCombos()
                                                end
                                            else
                                                ui.dnd.hover_timer        = 0
                                                ui.dnd.last_hovered_index = i
                                            end
                                        end
                                    end
                                    if Lib.imgui.BeginPopupContextItem("nctx_" .. i) then
                                        ui.context_menu_target = i
                                       Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.FrameRounding, 6)
                                        local sic = neon_fx.section_icon_color
                                        local function ctx_icon_button(uid, icon, label)
                                            local w, h = 160, 26
                                            local pos = Lib.imgui.GetCursorScreenPos()
                                            Data.nfn.PushButtonBorder()
                                            local clicked = Lib.imgui.Button("##" .. uid, Lib.imgui.ImVec2(w, h))
                                            Data.nfn.PopButtonBorder()
                                            if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                                            local dlc  = Lib.imgui.GetWindowDrawList()
                                            local igs  = Lib.imgui.CalcTextSize(icon)
                                            local tgs  = Lib.imgui.CalcTextSize(label)
                                            local gap  = 8
                                            local total_w  = igs.x + gap + tgs.x
                                            local start_x  = pos.x + (w - total_w) / 2
                                            local center_y = pos.y + h / 2
                                            dlc:AddText(Lib.imgui.ImVec2(start_x, center_y - igs.y/2),
                                               Data.nfn.pack_color(sic[1], sic[2], sic[3], (sic[4] or 1), false, neon.main_alpha), icon)
                                            dlc:AddText(Lib.imgui.ImVec2(start_x + igs.x + gap, center_y - tgs.y/2),
                                               Data.nfn.pack_color(1,1,1,0.92,false,neon.main_alpha), label)
                                            return clicked
                                        end
                                        if ctx_icon_button("ctx_edit_"..i, fa.PEN, Fn.T(u8"Редактировать")) then
                                           Fn.InitEditor(false, i); Lib.imgui.CloseCurrentPopup()
                                        end
                                        if ctx_icon_button("ctx_dup_"..i, fa.COPY, Fn.T(u8"Дублировать")) then
                                            local src = S.combos_list[i]
                                            local copy = {
                                                name       = src.name,
                                                guide_text = src.guide_text or "",
                                                data       = Fn.deepcopy(src.data)
                                            }
                                            table.insert(S.combos_list, i + 1, copy)
                                           Fn.saveCombos(); Lib.imgui.CloseCurrentPopup()
                                        end
                                        if ctx_icon_button("ctx_guide_"..i, fa.BOOK, Fn.T(u8"Гайд")) then
                                           Fn.open_guide(i); Lib.imgui.CloseCurrentPopup()
                                        end
                                       Lib.imgui.Separator()
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        Lib.imgui.ImVec4(0.55,0.08,0.08,0.95))
                                       Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(0.75,0.1,0.1,1))
                                        if ctx_icon_button("ctx_del_"..i, fa.TRASH_CAN, Fn.T(u8"Удалить")) then
                                            table.remove(S.combos_list, i); Fn.saveCombos(); Lib.imgui.CloseCurrentPopup()
                                        end
                                       Lib.imgui.PopStyleColor(2)
                                       Lib.imgui.PopStyleVar()
                                       Lib.imgui.EndPopup()
                                    end
                                    if ui.selection.dragging then
                                        local smin_x = math.min(ui.selection.start_pos.x, ui.selection.current_pos.x)
                                        local smin_y = math.min(ui.selection.start_pos.y, ui.selection.current_pos.y)
                                        local smax_x = math.max(ui.selection.start_pos.x, ui.selection.current_pos.x)
                                        local smax_y = math.max(ui.selection.start_pos.y, ui.selection.current_pos.y)
                                        local overlap = not (item_max2.x < smin_x or item_min2.x > smax_x or
                                                             item_max2.y < smin_y or item_min2.y > smax_y)
                                        ui.selection.preview_indices[i] = overlap or nil
                                    end
                                   Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 2))
                                end
                                if ui.dnd.drag_index ~= nil then
                                    local dc = S.combos_list[ui.dnd.drag_index]
                                    if dc then
                                        local d_pos = Lib.imgui.ImVec2(cmpos2.x - ui.dnd.drag_offset.x,
                                                                   cmpos2.y - ui.dnd.drag_offset.y)
                                        local btn_w = Lib.imgui.GetContentRegionAvail().x
                                        local gb = neon_fx.global_base_color
                                        dl_combo:AddRectFilled(d_pos,
                                           Lib.imgui.ImVec2(d_pos.x + btn_w, d_pos.y + 30),
                                           Data.nfn.pack_color(gb[1]*0.35,gb[2]*0.35,gb[3]*0.35,0.75,true,CBUGER_GET_INTERFACE_ALPHA()), 8)
                                        dl_combo:AddRect(d_pos,
                                           Lib.imgui.ImVec2(d_pos.x + btn_w, d_pos.y + 30),
                                           Data.nfn.pack_color(gb[1],gb[2],gb[3],0.85,false,1), 8, 15, 1.5)
                                        local ts2 = Lib.imgui.CalcTextSize(Fn.decodeSafe(dc.name))
                                        dl_combo:AddText(Lib.imgui.ImVec2(d_pos.x + 8, d_pos.y + (30 - ts2.y)/2),
                                           Data.nfn.pack_color(1,1,1,0.9,false,1), Fn.decodeSafe(dc.name))
                                    end
                                    if not Lib.imgui.IsMouseDown(0) then
                                        ui.dnd.drag_index  = nil
                                        ui.dnd.hover_timer = 0
                                    end
                                end
                                neon.combo_rows_h = Lib.imgui.GetCursorPosY()
                                local avail2 = Lib.imgui.GetContentRegionAvail()
                                if avail2.y > 0 then
                                   Lib.imgui.Dummy(Lib.imgui.ImVec2(avail2.x, avail2.y))
                                end
                                local child_hov2 = Lib.imgui.IsWindowHovered()
                                if child_hov2 and Lib.imgui.IsMouseClicked(0) and not any_hov2
                                   and ui.dnd.drag_index == nil then
                                    ui.selection.selected_indices = {}
                                    ui.selection.dragging         = true
                                    ui.selection.start_pos        = cmpos2
                                    ui.selection.current_pos      = cmpos2
                                    ui.selection.preview_indices  = {}
                                end
                                do
                                    local hdr_min_x = combo_header_origin.x
                                    local hdr_min_y = combo_header_origin.y
                                    local hdr_max_x = combo_header_origin.x + combo_tab_w
                                    local hdr_max_y = child_pos2.y
                                    local in_header = cmpos2.x>=hdr_min_x and cmpos2.x<=hdr_max_x
                                                   and cmpos2.y>=hdr_min_y and cmpos2.y<=hdr_max_y
                                    if in_header and Lib.imgui.IsMouseClicked(0) and ui.dnd.drag_index == nil
                                       and not ui.selection.dragging then
                                        ui.selection.selected_indices = {}
                                        ui.selection.dragging         = true
                                        ui.selection.start_pos        = cmpos2
                                        ui.selection.current_pos      = cmpos2
                                        ui.selection.preview_indices  = {}
                                    end
                                end
                                if ui.selection.dragging then
                                    ui.selection.current_pos = cmpos2
                                    if not Lib.imgui.IsMouseDown(0) then
                                        ui.selection.dragging = false
                                        ui.selection.active   = false
                                        for k2, v2 in pairs(ui.selection.preview_indices) do
                                            if v2 then ui.selection.selected_indices[k2] = true end
                                        end
                                        ui.selection.preview_indices = {}
                                    else
                                        local p_min2 = Lib.imgui.ImVec2(
                                            math.min(ui.selection.start_pos.x, ui.selection.current_pos.x),
                                            math.min(ui.selection.start_pos.y, ui.selection.current_pos.y))
                                        local p_max2 = Lib.imgui.ImVec2(
                                            math.max(ui.selection.start_pos.x, ui.selection.current_pos.x),
                                            math.max(ui.selection.start_pos.y, ui.selection.current_pos.y))
                                        dl_combo:PushClipRect(child_pos2,
                                           Lib.imgui.ImVec2(child_pos2.x + child_size2.x, child_pos2.y + child_size2.y), true)
                                        local sc = neon_fx.selection_color
                                        dl_combo:AddRectFilled(p_min2, p_max2,
                                           Data.nfn.pack_color(sc[1],sc[2],sc[3],(sc[4] or 1)*0.18,false,neon.main_alpha))
                                        dl_combo:AddRect(p_min2, p_max2,
                                           Data.nfn.pack_color(sc[1],sc[2],sc[3],(sc[4] or 1)*0.85,false,neon.main_alpha))
                                        dl_combo:PopClipRect()
                                    end
                                end
                                if count == 0 then
                                   Lib.imgui.SetCursorPos(Lib.imgui.ImVec2((cw - Lib.imgui.CalcTextSize(Fn.T(u8"Нет комбинаций")).x)/2 - 10, 20))
                                   Lib.imgui.TextDisabled(Fn.T(u8"Нет комбинаций"))
                                end
                           Lib.imgui.EndChild()
                            style2.ScrollbarSize = old_sr; style2.ScrollbarRounding = old_srr
                        end)
                        ndraw_p(4, function()
                            local function tsec(id, icon, title)
                                local im = Lib.imgui
                                local open = Data.hm.open[id] == true
                                local p0 = im.GetCursorScreenPos()
                                section_header(icon, title)
                                local p1 = im.GetCursorScreenPos()
                                local w = cw - 40
                                im.SetCursorScreenPos(p0)
                                im.InvisibleButton('##tsec_' .. id, im.ImVec2(w, math.max(8, p1.y - p0.y)))
                                if im.IsItemHovered() then Data.nfn.set_hand_cursor() end
                                local _tsec_clicked = im.IsItemClicked()
                                do
                                    local _mh = Data.MODE_HINTS and Data.MODE_HINTS[id]
                                    if _mh then Fn.ModeHint('mode_' .. id, _mh) end
                                end
                                if _tsec_clicked then
                                    open = not open
                                    Data.hm.open[id] = open
                                    Data.hm.save(true)
                                end
                                local ic = neon_fx.section_icon_color

                                local _on = false
                                pcall(function()
                                    if id == 'target' then _on = Data.hm.v.obj_target[0] and true or false
                                    elseif id == 'recoil' then _on = ui.recoil_enabled[0] and true or false
                                    elseif id == 'shotmap' then _on = ui.shotmap_enabled[0] and true or false
                                    elseif id == 'hm' then _on = Data.hm.run[0] and true or false
                                    elseif id == 'cbug' then _on = Data.cbug.cfg.settings.active and true or false
                                    elseif id == 'board' then _on = Data.board.cfg.settings.active and true or false
                                    elseif id == 'keymap' then _on = Fn.KS.enabled[0] and true or false
                                    end
                                end)
                                if _on then ic = { 0.3, 1.0, 0.4, 1.0 } end
                                local chev = open and safe_icon({'CHEVRON_UP','ANGLE_UP'}, '^') or safe_icon({'CHEVRON_DOWN','ANGLE_DOWN'}, 'v')
                                local cs = im.CalcTextSize(chev)
                                im.GetWindowDrawList():AddText(im.ImVec2(p0.x + w - cs.x - 6, p0.y),
                                    Data.nfn.pack_color(ic[1], ic[2], ic[3], ic[4] or 1, false, neon.main_alpha), chev)
                                im.SetCursorScreenPos(p1)
                                return open
                            end
                            if tsec('target', safe_icon({"CROSSHAIRS", "BULLSEYE"}, fa.CROSSHAIRS or fa.GEAR), Fn.T(u8"Цель-объект")) then
                                Fn.drawObjTargetUI(cw)
                            end
                            fixed_gap("g_train_ot", 12)
                            if tsec('recoil', safe_icon({"COMPUTER_MOUSE", "MOUSE"}, fa.CIRCLE_HALF_STROKE), Fn.T(u8"Контроль +С")) then
                           Data.fixed_toggle_pending_x = Data.ofs_get('tg_vklyuchit_kontrol', 0.0); Data.nfn.ios_toggle(Fn.T(u8"Включить контроль"), ui.recoil_enabled, neon.main_alpha)
                           fixed_gap("g13", 7)
                           Data.fixed_toggle_pending_x = Data.ofs_get('tg_pokazyvat_liniyu', 0.0); Data.nfn.ios_toggle(Fn.T(u8"Показывать линию"), ui.recoil_show_line, neon.main_alpha)
                           fixed_gap("g14", 7)
                           fixed_gap("g15", 6)
                            do
                                local h   = Data.recoil_ring.height or 0
                                local ang = math.deg(math.atan(h / Data.RING_RADIUS))
                                local lbl = string.format("%+.2f", h) .. Fn.T(u8" м") ..
                                            string.format("  (%+.1f", ang) .. u8"°)"
                                fixed_row_begin("gr_line_height")
                               Lib.imgui.Text(Fn.T(u8"Высота черты: ") .. lbl)
                               fixed_gap("g16", 4)
                                fixed_row_begin("gr_ring")
                                local nudge_w = (cw - 48) / 3
                                if Lib.imgui.Button(safe_icon({"ARROW_UP","CARET_UP"}, "^") .. " " .. Fn.T(u8"Выше"), Lib.imgui.ImVec2(nudge_w, 26)) then
                                   Fn.nudgeRecoilRing(Data.RING_STEP)
                                end
                                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                               Lib.imgui.SameLine(0, 4)
                                if Lib.imgui.Button(safe_icon({"ARROW_DOWN","CARET_DOWN"}, "v") .. " " .. Fn.T(u8"Ниже"), Lib.imgui.ImVec2(nudge_w, 26)) then
                                   Fn.nudgeRecoilRing(-Data.RING_STEP)
                                end
                                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                               Lib.imgui.SameLine(0, 4)
                                if Lib.imgui.Button(Fn.T(u8"По центру") .. "##ringzero", Lib.imgui.ImVec2(nudge_w, 26)) then
                                   Data.recoil_ring.height = 0
                                    S.cfg.config.recoil_ring_height = 0
                                    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
                                end
                                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                            end
                           fixed_gap("g17", 8)
                           Data.fixed_slider_pending_x = Data.ofs_get('sl_tolschina_linii', 0.0); Data.nfn.ios_slider(Fn.T(u8"Толщина линии"),        ui.recoil_line_thickness, 0.5, 6.0, neon.main_alpha); fixed_gap("g18", 5)
                           Data.fixed_slider_pending_x = Data.ofs_get('sl_dlitelnost_vspyshki', 0.0); Data.nfn.ios_slider(Fn.T(u8"Длительность вспышки"), ui.recoil_flash_duration, 0.01, 0.5, neon.main_alpha); fixed_gap("g19", 5)
                           Data.fixed_slider_pending_x = Data.ofs_get('sl_yarkost_vspyshki', 0.0); Data.nfn.ios_slider(Fn.T(u8"Яркость вспышки"),      ui.recoil_flash_alpha,    0.0, 1.0, neon.main_alpha)
                           fixed_gap("g20", 7)
                            Data.ofs_row('cp_recoil_flash')
                            if Data.nfn.CustomColorPicker(Fn.T(u8"Цвет вспышки"), "recoil_flash_col", neon_fx.recoil_flash_color, true, neon.main_alpha) then
                                local rc = neon_fx.recoil_flash_color
                                S.cfg.neon.recoil_flash_r = rc[1]; S.cfg.neon.recoil_flash_g = rc[2]
                                S.cfg.neon.recoil_flash_b = rc[3]; S.cfg.neon.recoil_flash_a = rc[4]
                               Lib.inicfg.save(S.cfg, Data.iniFile)
                            end
                           fixed_gap("g21", 14)
                            do
                                local correct   = S.state.recoil_correct or 0
                                local incorrect = S.state.recoil_incorrect or 0
                                local total     = correct + incorrect
                                local kpd       = total > 0 and (correct / total * 100) or 0
                                local _stats_gap = 14
                                local _stats_base = Lib.imgui.GetCursorScreenPos()
                                local _stats_y = _stats_base.y
                                Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(
                                    _stats_base.x + fixed_row_x("gr_stats_correct") + 9.00, _stats_y))
                                Lib.imgui.TextColored(
                                    Lib.imgui.ImVec4(0.3,0.9,0.3,1),
                                    Fn.T(u8"Правильно: ") .. correct)
                                local _stats_x2 = Lib.imgui.GetItemRectMax().x + _stats_gap
                                    + fixed_row_x("gr_stats_incorrect") + 2.72
                                Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(_stats_x2, _stats_y))
                                Lib.imgui.TextColored(
                                    Lib.imgui.ImVec4(0.95,0.3,0.3,1),
                                    Fn.T(u8"Неправильно: ") .. incorrect)
                                local _stats_x3 = Lib.imgui.GetItemRectMax().x + _stats_gap
                                    + fixed_row_x("gr_stats_kpd") + 2.72
                                Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(_stats_x3, _stats_y))
                                Lib.imgui.TextColored(
                                    Fn.statColorVec(kpd, true),
                                    Fn.T(u8"КПД: ") .. string.format("%.1f%%", kpd))
                                fixed_gap("g22", 8)
                                fixed_row_begin("gr_stats_reset")
                                if Lib.imgui.Button(fa.ROTATE_LEFT .. " " .. Fn.T(u8"Сбросить статистику"), Lib.imgui.ImVec2(cw - 40, 28)) then
                                    S.state.recoil_correct   = 0
                                    S.state.recoil_incorrect = 0
                                    S.cfg.config.recoil_correct   = 0
                                    S.cfg.config.recoil_incorrect = 0
                                   Lib.inicfg.save(S.cfg, Data.iniFile)
                                end
                                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                            end
                            end
                           fixed_gap("g23", 12)
                            if tsec('shotmap', safe_icon({"TABLE_CELLS_LARGE","TABLE_CELLS","IMAGE"}, fa.TABLE_LIST), Fn.T(u8"Карта выстрелов")) then
                           Data.fixed_toggle_pending_x = Data.ofs_get('tg_zapisyvat_kartu', 0.0); Data.nfn.ios_toggle(Fn.T(u8"Записывать карту"), ui.shotmap_enabled, neon.main_alpha)
                           fixed_gap("g24", 7)
                           Data.fixed_slider_pending_x = Data.ofs_get('sl_vystrelov_na_kartochku', 0.0); Data.nfn.ios_slider(Fn.T(u8"Выстрелов на карточку"), ui.shotmap_session_size, 1, 100, neon.main_alpha)
                           fixed_gap("g25", 10)
                            do
                                fixed_row_begin("gr_shot_modes")
                                local sm_modes = {Fn.T(u8"По сессиям"), Fn.T(u8"Общий вид")}
                                local btn_w = (cw - 48) / 2
                                for mi = 1, 2 do
                                    if mi > 1 then Lib.imgui.SameLine(0, 4) end
                                    local active = ui.shotmap_view_mode[0] == mi
                                    local sm_btn = Data.neon_active_colors[Lib.imgui.Col.Button] or {0.2,0.2,0.2,0.9}
                                    local sm_btn_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or sm_btn
                                    local sm_btn_h = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or sm_btn
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,
                                        Lib.imgui.ImVec4(
                                            (active and sm_btn_a or sm_btn)[1],
                                            (active and sm_btn_a or sm_btn)[2],
                                            (active and sm_btn_a or sm_btn)[3],
                                            (active and sm_btn_a or sm_btn)[4] or 0.9))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered,
                                        Lib.imgui.ImVec4(sm_btn_h[1],sm_btn_h[2],sm_btn_h[3],sm_btn_h[4] or 1.0))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,
                                        Lib.imgui.ImVec4(sm_btn_a[1],sm_btn_a[2],sm_btn_a[3],sm_btn_a[4] or 1.0))
                                    if Lib.imgui.Button(sm_modes[mi] .. "##smview" .. mi, Lib.imgui.ImVec2(btn_w, 26)) then
                                        ui.shotmap_view_mode[0] = mi
                                    end
                                   Lib.imgui.PopStyleColor(3)
                                end
                            end
                           fixed_gap("g26", 8)
                            if ui.shotmap_view_mode[0] == 1 then
                                local gr_nav_dx = fixed_row_begin("gr_shot_nav")
                                local sm_total = Fn.shotmapCardCount()
                                local sm_idx   = ui.shotmap_view_index[0]
                                local _, sm_is_current = Fn.shotmapGetCard(sm_idx)
                                if Lib.imgui.Button("<##smprev", Lib.imgui.ImVec2(34, 26)) then
                                    ui.shotmap_view_index[0] = math.max(1, sm_idx - 1)
                                end
                               Lib.imgui.SameLine(0, 8)
                                local sm_label = sm_is_current and Fn.T(u8"Сейчас")
                                    or (Fn.T(u8"Карточка ") .. sm_idx .. "/" .. math.max(0, sm_total - 1))
                                local sm_lts = Lib.imgui.CalcTextSize(sm_label)
                                local gr_current_dx = sm_is_current and fixed_row_x("gr_shot_current") or 0
                               Lib.imgui.SetCursorPosX(math.max(0, math.max(Lib.imgui.GetCursorPosX(), (cw - sm_lts.x) / 2) + gr_nav_dx + gr_current_dx))
                               Lib.imgui.Text(sm_label)
                               Lib.imgui.SameLine(0, 0)
                               Lib.imgui.SetCursorPosX(math.max(0, cw - 40 - 34 + gr_nav_dx))
                                if Lib.imgui.Button(">##smnext", Lib.imgui.ImVec2(34, 26)) then
                                    ui.shotmap_view_index[0] = math.min(sm_total, sm_idx + 1)
                                end
                               fixed_gap("g27", 8)
                            end
                            do
                                local card_size = math.min(cw - 40, 260)
                                local card_dx = fixed_row_x("gr_shot_card")
                                local card_left_pad = math.max(0, (cw - 40 - card_size) / 2 + card_dx)
                               Lib.imgui.Dummy(Lib.imgui.ImVec2(card_left_pad, 0))
                               Lib.imgui.SameLine(0, 0)
                               Lib.imgui.InvisibleButton("##shotmap_card", Lib.imgui.ImVec2(card_size, card_size))
                                local sm_hovered = Lib.imgui.IsItemHovered()
                                if Lib.imgui.IsItemClicked() then
                                   Data.shotmap_chart_open = not Data.shotmap_chart_open
                                end
                                if sm_hovered then Data.nfn.set_hand_cursor() end
                                local sm_p_min = Lib.imgui.GetItemRectMin()
                                local sm_p_max = Lib.imgui.GetItemRectMax()
                                local sm_dl    = Lib.imgui.GetWindowDrawList()
                                if Data.shotmap_chart_open then
                                   Fn.drawShotmapChart(sm_dl, sm_p_min, sm_p_max, neon.main_alpha)
                                else
                                    local sm_points = Fn.shotmapVisiblePoints()
                                   Fn.drawShotmapCard(sm_dl, sm_p_min, sm_p_max, sm_points, neon.main_alpha)
                                    if sm_hovered then Fn.shotmapTooltip() end
                                end
                            end
                           fixed_gap("g28", 6)
                            if Data.shotmap_chart_open then
                                fixed_row_begin("gr_shot_metric")
                                local mnames = {Fn.T(u8"Разброс"), Fn.T(u8"КПД")}
                                local mw = (cw - 44) / 2
                                for mi = 1, 2 do
                                    if mi > 1 then Lib.imgui.SameLine(0, 4) end
                                    local active = Data.shotmap_chart_metric == mi
                                    local sm_btn = Data.neon_active_colors[Lib.imgui.Col.Button] or {0.2,0.2,0.2,0.9}
                                    local sm_btn_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or sm_btn
                                    local sm_btn_h = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or sm_btn
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,
                                        Lib.imgui.ImVec4(
                                            (active and sm_btn_a or sm_btn)[1],
                                            (active and sm_btn_a or sm_btn)[2],
                                            (active and sm_btn_a or sm_btn)[3],
                                            (active and sm_btn_a or sm_btn)[4] or 0.9))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered,
                                        Lib.imgui.ImVec4(sm_btn_h[1],sm_btn_h[2],sm_btn_h[3],sm_btn_h[4] or 1.0))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,
                                        Lib.imgui.ImVec4(sm_btn_a[1],sm_btn_a[2],sm_btn_a[3],sm_btn_a[4] or 1.0))
                                    if Lib.imgui.Button(mnames[mi] .. "##smmetric" .. mi, Lib.imgui.ImVec2(mw, 24)) then
                                       Data.shotmap_chart_metric = mi
                                    end
                                   Lib.imgui.PopStyleColor(3)
                                end
                               fixed_gap("g29", 6)
                            end
                            fixed_row_begin("gr_shot_clear")
                            if Lib.imgui.Button(fa.TRASH_CAN .. " " .. Fn.T(u8"Очистить карту"), Lib.imgui.ImVec2(cw - 40, 28)) then
                               Data.shotmap.sessions = {}
                               Data.shotmap.current  = {points = {}, ref = nil, ts = os.time()}
                                ui.shotmap_view_index[0] = 1
                               Data.shotmap_color_cache = { key = nil, colors = nil }
                               Data.shotmap_stats_cache = {}
                               Fn.save_shotmap_to_json()
                            end
                            if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                            end
                           fixed_gap("g30", 12)
                            if tsec('keymap', safe_icon({"FIRE", "KEYBOARD"}, fa.GEAR), Fn.T(u8"Тепловая карта клавиш")) then
                                Fn.drawKeymapUI(cw)
                            end
                            fixed_gap("g_train_keymap", 16)
                            if tsec('hm', safe_icon({"BULLSEYE", "CROSSHAIRS"}, fa.GEAR), Fn.T(u8"Хитмаркер")) then
                                Fn.drawHitmarkerUI(cw, tsec)
                            end
                            fixed_gap("g_train_hm", 12)
                            if tsec('cbug', safe_icon({"GAUGE_HIGH", "GAUGE"}, fa.GEAR), Fn.T(u8"Cbug Speed")) then
                                Fn.drawCbugUI(cw)
                            end
                            fixed_gap("g_train_cb", 16)
                            if tsec('board', safe_icon({"CHESS_BOARD", "TABLE_CELLS", "BORDER_ALL"}, fa.GEAR), Fn.T(u8"Шахматная доска")) then
                                Fn.drawBoardUI(cw)
                            end
                            fixed_gap("g_train_board", 16)
                        end)
                   Lib.imgui.EndChild()
                    if neon.eye_anim_state < 0.05 then
                        NS.draw_bar(neon.sc, neon.current_tab, dl,
                            p_min.x + neon.window_size.w - 10,
                            win_pos.y + content_y,
                            child_h, io, neon.main_alpha)
                    end
                    if neon.eye_anim_state < 0.05 then
                       Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(neon.window_size.w - 20, neon.window_size.h - 20))
                       Lib.imgui.InvisibleButton("##nresizer", Lib.imgui.ImVec2(20, 20))
                        if Lib.imgui.IsItemClicked() then
                            neon.is_resizing = true
                            neon.resize_start_size.w, neon.resize_start_size.h = neon.window_size.w, neon.window_size.h
                            neon.resize_start_mouse.x, neon.resize_start_mouse.y = io.MousePos.x, io.MousePos.y
                        end
                        if Lib.imgui.IsItemHovered() or neon.is_resizing then Data.nfn.set_resize_cursor() end
                        do
                            local rc = neon_fx.icon_resize_color
                            local rc32 = Data.nfn.pack_color(rc[1],rc[2],rc[3],rc[4] or 0.67,true,neon.main_alpha)
                            dl:AddLine(Lib.imgui.ImVec2(p_min.x+neon.window_size.w-5, p_min.y+neon.window_size.h-2),
                                      Lib.imgui.ImVec2(p_min.x+neon.window_size.w-2, p_min.y+neon.window_size.h-5), rc32, 1.5)
                            dl:AddLine(Lib.imgui.ImVec2(p_min.x+neon.window_size.w-9, p_min.y+neon.window_size.h-2),
                                      Lib.imgui.ImVec2(p_min.x+neon.window_size.w-2, p_min.y+neon.window_size.h-9), rc32, 1.0)
                        end
                    end
                    local author_text = "by Pryanix"
                    local author_size = Lib.imgui.CalcTextSize(author_text)
                    local footer_y    = neon.window_size.h - 24
                    local center_x    = p_min.x + neon.window_size.w / 2
                    local hover_w     = author_size.x + 24
                   Lib.imgui.SetCursorPos(Lib.imgui.ImVec2((neon.window_size.w - hover_w) / 2, footer_y - 5))
                   Lib.imgui.InvisibleButton("##nfooter", Lib.imgui.ImVec2(hover_w, author_size.y + 10))
                    local footer_hovered = Lib.imgui.IsItemHovered()
                    if footer_hovered then
                        neon.footer_timer = 1.0
                       Data.nfn.set_hand_cursor()
                    elseif neon.footer_timer > 0 then
                        neon.footer_timer = neon.footer_timer - Data.neon_ui_anim.dt
                    end
                    local show_icons = neon.footer_timer > 0
                    neon.footer_anim_state = Data.nfn.anim_update(neon.footer_anim_state, show_icons and 1 or 0, CBUGER_GET_ANIM_RATE(10))
                    local fa = (1 - neon.footer_anim_state) * neon.main_alpha
                    if fa > 0.01 then
                        local fx_start = center_x - author_size.x / 2
                        local fy_pos   = p_min.y + footer_y
                        local pc = neon_fx.pryanix_color
                        dl:AddText(Lib.imgui.ImVec2(fx_start, fy_pos),
                           Data.nfn.pack_color(pc[1] * 0.9, pc[2] * 0.9, pc[3] * 0.9, fa, true, CBUGER_GET_INTERFACE_ALPHA()), author_text)
                    end
                    if neon.footer_anim_state > 0.01 then
                        local icon_alpha = neon.footer_anim_state * neon.main_alpha
                        local slide_off  = 20 + 25 * neon.footer_anim_state
                        local yt_center  = Lib.imgui.ImVec2(center_x - slide_off, p_min.y + footer_y + author_size.y / 2)
                        local tg_center  = Lib.imgui.ImVec2(center_x + slide_off, p_min.y + footer_y + author_size.y / 2)
                        local yt_hovered, tg_hovered = false, false
                        if show_icons then
                           Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(yt_center.x - 14, yt_center.y - 14))
                            local yt_clicked = Fn.link_hitbox("##nyt_btn", Lib.imgui.ImVec2(28, 28), "https://youtube.com/@0rub?si=jhCgPIwEI_S5vi7R")
                            if Lib.imgui.IsItemHovered() then
                                yt_hovered = true
                                neon.footer_timer = 1.0
                            end
                           Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(tg_center.x - 14, tg_center.y - 14))
                            local tg_clicked = Fn.link_hitbox("##ntg_btn", Lib.imgui.ImVec2(28, 28), "https://t.me/kizarydetroys")
                            if Lib.imgui.IsItemHovered() then
                                tg_hovered = true
                                neon.footer_timer = 1.0
                            end
                        end
                        neon.footer_yt_anim = Data.nfn.anim_update(neon.footer_yt_anim or 0, yt_hovered and 1 or 0, CBUGER_GET_ANIM_RATE(12))
                        neon.footer_tg_anim = Data.nfn.anim_update(neon.footer_tg_anim or 0, tg_hovered and 1 or 0, CBUGER_GET_ANIM_RATE(12))
                        local yt_t = neon.footer_yt_anim
                        local tg_t = neon.footer_tg_anim
                        local _falib2 = CBUGER_CORE.libs.fa
                        local yt_r = Data.nfn.lerp(1.0,  1.0, yt_t)
                        local yt_g = Data.nfn.lerp(0.2,  1.0, yt_t)
                        local yt_b = Data.nfn.lerp(0.2,  1.0, yt_t)
                        local yt_u32 = Data.nfn.pack_color(yt_r, yt_g, yt_b, icon_alpha, true, CBUGER_GET_INTERFACE_ALPHA())
                        local yt_gl = _falib2.SQUARE_CARET_RIGHT or ""
                        if yt_gl ~= "" then
                            local gs = Lib.imgui.CalcTextSize(yt_gl)
                            dl:AddText(Lib.imgui.ImVec2(yt_center.x-gs.x/2, yt_center.y-gs.y/2), yt_u32, yt_gl)
                        end
                        local tg_r = Data.nfn.lerp(0.16, 1.0, tg_t)
                        local tg_g = Data.nfn.lerp(0.71, 1.0, tg_t)
                        local tg_b = Data.nfn.lerp(0.96, 1.0, tg_t)
                        local tg_u32 = Data.nfn.pack_color(tg_r, tg_g, tg_b, icon_alpha, true, CBUGER_GET_INTERFACE_ALPHA())
                        local tg_gl = _falib2.PAPER_PLANE or ""
                        if tg_gl ~= "" then
                            local gs2 = Lib.imgui.CalcTextSize(tg_gl)
                            dl:AddText(Lib.imgui.ImVec2(tg_center.x-gs2.x/2, tg_center.y-gs2.y/2), tg_u32, tg_gl)
                        end
                    end
                end
           Lib.imgui.End()
           Lib.imgui.PopStyleColor(pushes_count)
           Lib.imgui.PopStyleVar(3)
        end
        end
        render_main_window()
        local function render_style_editor()
        if neon.editor_alpha > 0.01 then
            neon.current_rendering_window      = "editor"
            neon.editor_current_frame_max_w    = 400
            if neon.editor_is_resizing then
                neon.editor_window_size.w = math.max(350, neon.editor_resize_start_size.w + (io.MousePos.x - neon.editor_resize_start_mouse.x))
                neon.editor_window_size.h = math.max(400, neon.editor_resize_start_size.h + (io.MousePos.y - neon.editor_resize_start_mouse.y))
            else
                neon.editor_content_max_w    = Data.nfn.anim_update(neon.editor_content_max_w, neon.editor_current_frame_max_w, 5)
                neon.editor_window_size.w    = Data.nfn.anim_update(neon.editor_window_size.w, math.max(neon.editor_window_size.w, neon.editor_content_max_w), 10)
            end
            if neon.editor_is_dragging then
               Lib.imgui.SetNextWindowPos(Lib.imgui.ImVec2(io.MousePos.x - neon.editor_drag_offset.x, io.MousePos.y - neon.editor_drag_offset.y), Lib.imgui.Cond.Always)
            end
           Lib.imgui.SetNextWindowSize(Lib.imgui.ImVec2(neon.editor_window_size.w, neon.editor_window_size.h), Lib.imgui.Cond.Always)
            local pushes_e = 0
           Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg, Lib.imgui.ImVec4(0,0,0,0)); pushes_e = pushes_e + 1
            local pop_b_col2 = Data.neon_active_colors[Lib.imgui.Col.Border] or {1,1,1,1}
           Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(pop_b_col2[1],pop_b_col2[2],pop_b_col2[3],(pop_b_col2[4] or 1)*neon.editor_alpha)); pushes_e = pushes_e + 1
            if Lib.imgui.Col.PopupBg then
                local pbc2 = Data.neon_active_colors[Lib.imgui.Col.PopupBg] or {0.08,0.08,0.1,0.98}
               Lib.imgui.PushStyleColor(Lib.imgui.Col.PopupBg, Lib.imgui.ImVec4(pbc2[1],pbc2[2],pbc2[3],(pbc2[4] or 0.98)*neon.editor_alpha)); pushes_e = pushes_e + 1
            end
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.Alpha, neon.editor_alpha)
           Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(0,0))
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowBorderSize, 0)
           Lib.imgui.Begin("##NeonStyleEditor", nil,
               Lib.imgui.WindowFlags.NoTitleBar + Lib.imgui.WindowFlags.NoCollapse +
               Lib.imgui.WindowFlags.NoResize   + Lib.imgui.WindowFlags.NoMove)
                local ed_p   = Lib.imgui.GetWindowPos()
                local ed_s   = Lib.imgui.GetWindowSize()
                local edl    = Lib.imgui.GetWindowDrawList()
                local ep_min = ed_p
                local ep_max = Lib.imgui.ImVec2(ed_p.x + ed_s.x, ed_p.y + ed_s.y)
                edl:AddRectFilled(ep_min, ep_max,
                   Data.nfn.pack_color(Data.neon_win_bg[1],Data.neon_win_bg[2],Data.neon_win_bg[3],Data.neon_win_bg[4],true,neon.editor_alpha), 20)
               Data.nfn.draw_police_ambient(edl, ep_min, ep_max, neon.editor_alpha)
               Data.nfn.draw_neon_border(edl, ep_min, ep_max, neon.editor_alpha)
                local ecross_p = Lib.imgui.ImVec2(ep_max.x - 25, ep_min.y + 25)
               Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(ecross_p.x - 15, ecross_p.y - 15))
                if Lib.imgui.InvisibleButton("##neon_closeeditor", Lib.imgui.ImVec2(30, 30)) then neon.target_editor[0] = false end
                local ehdr_hov = Lib.imgui.IsItemHovered()
                if ehdr_hov then Data.nfn.set_hand_cursor() end
               Data.nfn.draw_cross(edl, ecross_p, 12, ehdr_hov, neon.editor_alpha)
                if Lib.imgui.IsMouseClicked(0) and not ehdr_hov and Lib.imgui.IsWindowHovered() then
                    if io.MousePos.y >= ep_min.y and io.MousePos.y <= ep_min.y + 45 and
                       io.MousePos.x >= ep_min.x and io.MousePos.x <= ep_max.x then
                        neon.editor_is_dragging     = true
                        neon.editor_drag_offset.x   = io.MousePos.x - ed_p.x
                        neon.editor_drag_offset.y   = io.MousePos.y - ed_p.y
                    end
                end
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, 20))
                local etc = neon_fx.tabs_color
                do local _etd = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
               Lib.imgui.TextColored(Lib.imgui.ImVec4(_etd[1],_etd[2],_etd[3],_etd[4] or 1), Fn.T(u8"Редактор стиля")) end
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, 50))
                local etab_w      = (ed_s.x - 40) / 2
                local _etba_n = Data.neon_active_colors[Lib.imgui.Col.Button]       or {0.2,0.2,0.2,0.85}
                local _etba_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.4,0.4,0.4,1.0}
                local active_tab_col   = Lib.imgui.ImVec4(_etba_a[1],_etba_a[2],_etba_a[3],_etba_a[4] or 0.95)
                local inactive_tab_col = Lib.imgui.ImVec4(_etba_n[1],_etba_n[2],_etba_n[3],_etba_n[4] or 0.85)
                local _et_h = Data.neon_active_colors[Lib.imgui.Col.ButtonHovered] or {0.35,0.35,0.35,1.0}
               Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        neon.editor_tab == 1 and active_tab_col or inactive_tab_col)
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_et_h[1],_et_h[2],_et_h[3],_et_h[4] or 1.0))
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  active_tab_col)
                Data.nfn.PushButtonBorder()
                if Lib.imgui.Button(Fn.T(u8"Цвета"), Lib.imgui.ImVec2(etab_w, 35)) then neon.editor_tab = 1 end
                Data.nfn.PopButtonBorder()
               Lib.imgui.PopStyleColor(3)
                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
               Lib.imgui.SameLine(15 + etab_w + 10)
               Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        neon.editor_tab == 2 and active_tab_col or inactive_tab_col)
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(_et_h[1],_et_h[2],_et_h[3],_et_h[4] or 1.0))
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  active_tab_col)
                Data.nfn.PushButtonBorder()
                if Lib.imgui.Button(Fn.T(u8"Эффекты"), Lib.imgui.ImVec2(etab_w, 35)) then neon.editor_tab = 2 end
                Data.nfn.PopButtonBorder()
               Lib.imgui.PopStyleColor(3)
                if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, 95))
                local est = Lib.imgui.GetStyle()
                local old_ss = est.ScrollbarSize; local old_ssr = est.ScrollbarRounding
                est.ScrollbarSize = 6; est.ScrollbarRounding = 12
               Lib.imgui.BeginChild("##neon_style_scroll", Lib.imgui.ImVec2(ed_s.x - 30, ed_s.y - 110), false)
                   Lib.imgui.Indent(10)
                    if neon.editor_tab == 1 then
                        do local _td_on = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                       Lib.imgui.TextColored(Lib.imgui.ImVec4(_td_on[1],_td_on[2],_td_on[3],_td_on[4] or 1), Fn.T(u8"Общие настройки")) end
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5))
                       Data.nfn.ios_toggle(Fn.T(u8"Плавное закрытие окна"), Data.neon_smooth_close, neon.editor_alpha)
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5))
                        if Data.nfn.CustomColorPicker(Fn.T(u8"Базовый цвет интерфейса"), "neon_global_base", neon_fx.global_base_color, true, neon.editor_alpha) then
                           Data.nfn.ApplyGlobalTheme(neon_fx.global_base_color[1], neon_fx.global_base_color[2], neon_fx.global_base_color[3])
                        end
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5))
                       Fn.neon_FontCombo(Fn.T(u8"Выбор шрифта"), neon.current_font_idx)
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,8))
                       fixed_editor_slider_begin("le_color_interface_alpha")
                       Data.nfn.ios_slider(Fn.T(u8"Прозрачность интерфейса"), ui.interface_alpha, 0.1, 1.0, neon.editor_alpha)
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,10)); Lib.imgui.Separator(); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,10))
                        do local _td_rs = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                       Lib.imgui.TextColored(Lib.imgui.ImVec4(_td_rs[1],_td_rs[2],_td_rs[3],_td_rs[4] or 1), Fn.T(u8"Расширенные настройки цветов")) end
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5))
                        local categories = {
                            {id=1, name=Fn.T(u8"Фон и окна")},       {id=2, name=Fn.T(u8"Кнопки и элементы")},
                            {id=4, name=Fn.T(u8"Скроллбар")},         {id=5, name=Fn.T(u8"Текст и рамки")},
                        }
                        for _, cat in ipairs(categories) do
                           Data.nfn.record_width(Lib.imgui.CalcTextSize(cat.name).x + 100)
                            if Lib.imgui.TreeNodeStr(cat.name) then
                               Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                                for _, col in ipairs(Data.neon_lists.imgui_colors) do
                                    if col.cat == cat.id and col.id ~= nil then
                                       Lib.imgui.PushID("ncat_" .. tostring(col.id))
                                        local clr_table = Data.neon_active_colors[col.id]
                                        if clr_table then Data.nfn.CustomColorPicker(Fn.T(u8(col.name)), "ncustom_"..tostring(col.id), clr_table, true, neon.editor_alpha) end
                                       Lib.imgui.PopID()
                                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                                    end
                                end
                                if cat.id == 5 then
                                   Data.nfn.CustomColorPicker(Fn.T(u8"Рамка окна"),      "neon_border_col",   neon_fx.neon_border_color,   true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                                    if Data.nfn.CustomColorPicker(Fn.T(u8"Обводки кнопок"), "nbutton_border_col", neon_fx.button_border_color, true, neon.editor_alpha) then
                                        local bc_btn = neon_fx.button_border_color
                                        S.cfg.neon.button_border_r = bc_btn[1]; S.cfg.neon.button_border_g = bc_btn[2]
                                        S.cfg.neon.button_border_b = bc_btn[3]; S.cfg.neon.button_border_a = bc_btn[4] or 0.6
                                        Lib.inicfg.save(S.cfg, Data.iniFile)
                                    end
                                   Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                                end
                               Lib.imgui.TreePop()
                            end
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,2))
                        end
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5))
                       Data.nfn.record_width(Lib.imgui.CalcTextSize(Fn.T(u8"Иконки и элементы")).x + 100)
                        if Lib.imgui.TreeNodeStr(Fn.T(u8"Иконки и элементы")) then
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Цвет вкладок"),             "ntabs_col",         neon_fx.tabs_color,           true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Цвет анимаций вкладок"),        "neon_waves_col",    neon_fx.waves_color,          true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Крестик (закрытие)"),        "ncross_col",        neon_fx.icon_cross_color,     true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Глаз (свернуть)"),           "neye_col",          neon_fx.icon_eye_color,       true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Шестерёнка (настройки)"),    "ngear_col",         neon_fx.icon_gear_color,      true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Иконки"),             "nsecicon_col",      neon_fx.section_icon_color,   true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Иконки вкладок окна"),           "ntabicon_col",      neon_fx.tab_icon_color,        true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Прямоугольное выделение"),       "nsel_col",          neon_fx.selection_color,       true, neon.editor_alpha)
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Переключатель вкладок"),                  "ntitle_main_col",   neon_fx.title_main_color,      true, neon.editor_alpha); Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3))
                           Data.nfn.CustomColorPicker(Fn.T(u8"Подпись \"by Pryanix\""),           "npryanix_col",      neon_fx.pryanix_color,         true, neon.editor_alpha)
                           Lib.imgui.TreePop()
                        end
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,10))
                    elseif neon.editor_tab == 2 then
                        do local _td_fx = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                       Data.nfn.ios_toggle(Fn.T(u8"Курсор-частицы"), neon_fx.sparks_on, neon.editor_alpha, _td_fx) end
                        if neon_fx.sparks_on[0] then
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); fixed_editor_slider_begin("le_fx_sparks_speed"); Data.nfn.ios_slider(Fn.T(u8"Скорость частиц"), neon_fx.sparks_speed, 0.1, 3, neon.editor_alpha)
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); fixed_editor_slider_begin("le_fx_sparks_size"); Data.nfn.ios_slider(Fn.T(u8"Размер частиц"),   neon_fx.sparks_size,  0.5, 10, neon.editor_alpha)
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); Data.nfn.SafeCombo(Fn.T(u8"Режим курсора"),    neon_fx.cursor_fx_var, Fn.translateList(Data.neon_lists.cursor_fx))
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); Data.nfn.CustomColorPicker(Fn.T(u8"Цвет частиц"), "nsparks_col", neon_fx.sparks_color, true, neon.editor_alpha)
                        end
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,15))
                        do local _td_fx2 = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                       Data.nfn.ios_toggle(Fn.T(u8"Анимация вкладок"), neon_fx.waves_on, neon.editor_alpha, _td_fx2) end
                        if neon_fx.waves_on[0] then
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); fixed_editor_slider_begin("le_fx_waves_speed"); Data.nfn.ios_slider(Fn.T(u8"Скорость анимации"), neon_fx.waves_speed, 0.1, 3, neon.editor_alpha)
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); Data.nfn.SafeCombo(Fn.T(u8"Режим анимации"),     neon_fx.waves_var,   Fn.translateList(Data.neon_lists.waves_modes))
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); Data.nfn.CustomColorPicker(Fn.T(u8"Цвет анимаций вкладок"), "nwaves_col", neon_fx.waves_color, true, neon.editor_alpha)
                        end
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0,15))
                        do local _td_fx3 = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                       Data.nfn.ios_toggle(Fn.T(u8"Фоновое свечение"), neon_fx.ambient_on, neon.editor_alpha, _td_fx3) end
                        if neon_fx.ambient_on[0] then
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); fixed_editor_slider_begin("le_fx_ambient_speed"); Data.nfn.ios_slider(Fn.T(u8"Скорость свечения"), neon_fx.ambient_speed, 0.1, 3, neon.editor_alpha)
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); Data.nfn.SafeCombo(Fn.T(u8"Режим свечения"),   neon_fx.ambient_var,     Fn.translateList(Data.neon_lists.ambient_modes))
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,5)); Data.nfn.CustomColorPicker(Fn.T(u8"Цвет свечения (1)"),  "nambient_1", neon_fx.ambient_color_1, true, neon.editor_alpha)
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(0,3)); Data.nfn.CustomColorPicker(Fn.T(u8"Цвет свечения (2)"),  "nambient_2", neon_fx.ambient_color_2, true, neon.editor_alpha)
                        end
                    end
                   Lib.imgui.Unindent(10)
               Lib.imgui.EndChild()
                est.ScrollbarSize = old_ss; est.ScrollbarRounding = old_ssr
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(neon.editor_window_size.w - 20, neon.editor_window_size.h - 20))
               Lib.imgui.InvisibleButton("##neditor_resizer", Lib.imgui.ImVec2(20, 20))
                if Lib.imgui.IsItemClicked() then
                    neon.editor_is_resizing = true
                    neon.editor_resize_start_size.w, neon.editor_resize_start_size.h = neon.editor_window_size.w, neon.editor_window_size.h
                    neon.editor_resize_start_mouse.x, neon.editor_resize_start_mouse.y = io.MousePos.x, io.MousePos.y
                end
                if Lib.imgui.IsItemHovered() or neon.editor_is_resizing then Data.nfn.set_resize_cursor() end
                do
                    local rc = neon_fx.icon_resize_color
                    local rc32 = Data.nfn.pack_color(rc[1],rc[2],rc[3],rc[4] or 0.67,true,neon.editor_alpha)
                    edl:AddLine(Lib.imgui.ImVec2(ep_min.x+neon.editor_window_size.w-5, ep_min.y+neon.editor_window_size.h-2),
                               Lib.imgui.ImVec2(ep_min.x+neon.editor_window_size.w-2, ep_min.y+neon.editor_window_size.h-5), rc32, 1.5)
                    edl:AddLine(Lib.imgui.ImVec2(ep_min.x+neon.editor_window_size.w-9, ep_min.y+neon.editor_window_size.h-2),
                               Lib.imgui.ImVec2(ep_min.x+neon.editor_window_size.w-2, ep_min.y+neon.editor_window_size.h-9), rc32, 1.0)
                end
           Lib.imgui.End()
           Lib.imgui.PopStyleColor(pushes_e)
           Lib.imgui.PopStyleVar(3)
        end
        end
        render_style_editor()
        local function render_combo_editor()
        if Data.neon_smooth_close[0] then
            neon._combo_editor_fade = Data.nfn.anim_update(neon._combo_editor_fade or 0,
                (neon.target_combo_editor[0] and ui.editor.active) and 1 or 0, CBUGER_GET_ANIM_RATE(15))
        else
            neon._combo_editor_fade = (neon.target_combo_editor[0] and ui.editor.active) and 1 or 0
        end
        neon.combo_editor_alpha = (neon._combo_editor_fade or 0) * ui.interface_alpha[0]
        if not ui.editor.active then neon.target_combo_editor[0] = false end
        if neon.combo_editor_alpha > 0.01 then
            local ced_w = neon.combo_editor_window_size.w
            local ced_h = neon.combo_editor_window_size.h
            if neon.combo_editor_is_dragging then
               Lib.imgui.SetNextWindowPos(Lib.imgui.ImVec2(
                    io.MousePos.x - neon.combo_editor_drag_offset.x,
                    io.MousePos.y - neon.combo_editor_drag_offset.y), Lib.imgui.Cond.Always)
            end
           Lib.imgui.SetNextWindowSize(Lib.imgui.ImVec2(ced_w, ced_h), Lib.imgui.Cond.Always)
            local pushes_ce = 0
           Lib.imgui.PushStyleColor(Lib.imgui.Col.WindowBg, Lib.imgui.ImVec4(0,0,0,0)); pushes_ce = pushes_ce + 1
            local pop_bce = Data.neon_active_colors[Lib.imgui.Col.Border] or {1,1,1,1}
           Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(pop_bce[1],pop_bce[2],pop_bce[3],(pop_bce[4] or 1)*neon.combo_editor_alpha)); pushes_ce = pushes_ce + 1
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.Alpha, neon.combo_editor_alpha)
           Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(0,0))
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowBorderSize, 0)
           Lib.imgui.Begin("##NeonComboEditor", nil,
               Lib.imgui.WindowFlags.NoTitleBar + Lib.imgui.WindowFlags.NoResize +
               Lib.imgui.WindowFlags.NoMove     + Lib.imgui.WindowFlags.NoScrollbar)
                local combo_editor_text_col = Data.neon_active_colors[Lib.imgui.Col.Text] or {1,1,1,1}
               Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(combo_editor_text_col[1], combo_editor_text_col[2], combo_editor_text_col[3], combo_editor_text_col[4] or 1))
                local combo_editor_text_push = 1
                local cedl    = Lib.imgui.GetWindowDrawList()
                local ce_pos  = Lib.imgui.GetWindowPos()
                local ce_size = Lib.imgui.GetWindowSize()
                local ce_min  = ce_pos
                local ce_max  = Lib.imgui.ImVec2(ce_pos.x + ce_size.x, ce_pos.y + ce_size.y)
                cedl:AddRectFilled(ce_min, ce_max,
                   Data.nfn.pack_color(Data.neon_win_bg[1],Data.neon_win_bg[2],Data.neon_win_bg[3],Data.neon_win_bg[4],true,neon.combo_editor_alpha), 20)
               Data.nfn.draw_police_ambient(cedl, ce_min, ce_max, neon.combo_editor_alpha)
               Data.nfn.draw_neon_border(cedl, ce_min, ce_max, neon.combo_editor_alpha)
                local ce_title = ui.editor.is_new and Fn.T(u8"Новая комбинация") or Fn.T(u8"Редактор комбинации")
                local _cetd = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {1,1,1,1}
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(20, 18))
               Lib.imgui.TextColored(Lib.imgui.ImVec4(_cetd[1],_cetd[2],_cetd[3],_cetd[4] or 1), ce_title)
                local cecross_p = Lib.imgui.ImVec2(ce_max.x - 25, ce_min.y + 25)
               Lib.imgui.SetCursorScreenPos(Lib.imgui.ImVec2(cecross_p.x - 15, cecross_p.y - 15))
                if Lib.imgui.InvisibleButton("##neon_ce_close", Lib.imgui.ImVec2(30, 30)) then
                    Fn.closeComboEditor()
                end
               Data.nfn.draw_cross_fa(cecross_p, Lib.imgui.IsItemHovered())
                if Lib.imgui.IsMouseClicked(0) and Lib.imgui.IsWindowHovered() then
                    if io.MousePos.y >= ce_min.y and io.MousePos.y <= ce_min.y + 45 and
                       io.MousePos.x >= ce_min.x and io.MousePos.x <= ce_max.x then
                        neon.combo_editor_is_dragging     = true
                        neon.combo_editor_drag_offset.x   = io.MousePos.x - ce_pos.x
                        neon.combo_editor_drag_offset.y   = io.MousePos.y - ce_pos.y
                    end
                end
                if not Lib.imgui.IsMouseDown(0) then neon.combo_editor_is_dragging = false end
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, 50))
               Lib.imgui.BeginGroup()
                    Data.nfn.PushButtonBorder()
                    if Lib.imgui.Button(Fn.T(u8"< Назад"), Lib.imgui.ImVec2(90, 28)) then
                        Fn.closeComboEditor()
                    end
                    if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
                   Lib.imgui.SameLine(0, 8)
                    local _sba_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.4,0.4,0.4,1.0}
                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, Lib.imgui.ImVec4(_sba_a[1],_sba_a[2],_sba_a[3],_sba_a[4] or 0.9))
                    if Lib.imgui.Button(Fn.T(u8"Сохранить"), Lib.imgui.ImVec2(110, 28)) then
                        local name = Lib.ffi.string(ui.editor.name_buffer)
                        if #name == 0 then name = "Unnamed" end

                                                local cleaned_combo = Fn.cleanEmptyComboStages(ui.editor.temp_combo)
                        local saved_index
                        if ui.editor.is_new then
                            table.insert(S.combos_list, {
                                name       = name,
                                guide_text = "",
                                data       = Fn.deepcopy(cleaned_combo)
                            })
                            saved_index = #S.combos_list
                        else
                            saved_index = ui.editor.selected_index
                            local entry = S.combos_list[saved_index]
                            if entry then
                                entry.name = name
                                entry.data = Fn.deepcopy(cleaned_combo)
                            end
                        end
                        Fn.saveCombos()
                        if saved_index then Fn.refreshSavedCombo(saved_index, true) end
                        Fn.closeComboEditor()
                    end
                   Lib.imgui.PopStyleColor()
                    Data.nfn.PopButtonBorder()
                    if Lib.imgui.IsItemHovered() then Data.nfn.set_hand_cursor() end
               Lib.imgui.EndGroup()
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, 85))
               Lib.imgui.PushItemWidth(ced_w - 30)
               Lib.imgui.InputText(Fn.T(u8"##cename"), ui.editor.name_buffer, Lib.sizeof(ui.editor.name_buffer))
               Lib.imgui.PopItemWidth()
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, 113))
                local ced_txt = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {1,1,1,1}
               Lib.imgui.TextColored(Lib.imgui.ImVec4(ced_txt[1],ced_txt[2],ced_txt[3],0.7),
                   Fn.T(u8"2xЛКМ - настройки зажатия. ПКМ - удалить. Перетаскивание - перемещение."))
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, 133))
                local workspace_h = ced_h - 230
                local old_sr2 = Lib.imgui.GetStyle().ScrollbarSize; local old_srr2 = Lib.imgui.GetStyle().ScrollbarRounding
               Lib.imgui.GetStyle().ScrollbarSize = 6; Lib.imgui.GetStyle().ScrollbarRounding = 12
               Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(12, 8))
               Lib.imgui.BeginChild("##ce_workspace", Lib.imgui.ImVec2(ced_w - 30, workspace_h), true,
                   Lib.imgui.WindowFlags.HorizontalScrollbar)
               Lib.imgui.PopStyleVar()
                    local draw_list = Lib.imgui.GetWindowDrawList()
                    local mouse_pos = Lib.imgui.GetMousePos()
                    ui.editor.endzone_hovered_part    = nil
                    ui.editor.emptystage_hovered_part = nil
                    for part_idx, part in ipairs(ui.editor.temp_combo) do
                        local _ptd = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {1,1,1,1}
                       Lib.imgui.Dummy(Lib.imgui.ImVec2(0, 4))
                       Lib.imgui.TextColored(Lib.imgui.ImVec4(_ptd[1],_ptd[2],_ptd[3],(_ptd[4] or 1)*0.9),
                           Fn.T(u8"Этап ") .. part_idx)
                       Lib.imgui.SameLine(0, 6)
                       Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, Lib.imgui.ImVec4(0.55,0.08,0.08,0.9))
                       Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(0.75,0.1,0.1,1))
                        if Lib.imgui.SmallButton("X##part" .. part_idx) then
                            table.remove(ui.editor.temp_combo, part_idx); ui.editor.add_target_part = nil
                           Lib.imgui.PopStyleColor(2); break
                        end
                       Lib.imgui.PopStyleColor(2)
                       Lib.imgui.BeginChild("##ce_stage_" .. part_idx, Lib.imgui.ImVec2(0, 56), false,
                           Lib.imgui.WindowFlags.HorizontalScrollbar + Lib.imgui.WindowFlags.NoScrollWithMouse)
                            local sdl  = Lib.imgui.GetWindowDrawList()
                            local smp  = Lib.imgui.GetMousePos()
                            local hmp = smp
                            if ui.editor.add_row_dragging and ui.editor.add_row_drag_key then
                                local dk_hmp   = ui.editor.add_row_drag_key
                                local isSp_hmp = Fn.decodeSafe(dk_hmp)==Fn.decodeSafe(u8"ПРОБЕЛ") or dk_hmp=="SPACE"
                                local gw_hmp   = isSp_hmp and 70 or 50
                                local off_hmp  = ui.editor.add_row_drag_offset or Lib.imgui.ImVec2(0, 0)
                                hmp = Lib.imgui.ImVec2(smp.x - off_hmp.x + gw_hmp * 0.5,
                                                   smp.y - off_hmp.y + 20)
                            end
                            if #part == 0 then
                                local cmin2 = Lib.imgui.GetWindowPos(); local csz2 = Lib.imgui.GetWindowSize()
                                local dmin2 = cmin2; local dmax2 = Lib.imgui.ImVec2(cmin2.x+csz2.x, cmin2.y+csz2.y)
                                local overEmpty2 = smp.x>=dmin2.x and smp.x<=dmax2.x and smp.y>=dmin2.y and smp.y<=dmax2.y
                                local ghostHere = ui.editor.add_row_dragging and overEmpty2
                                if not ghostHere then
                                    local empty_txt = Fn.T(u8"(пустой — перетащите сюда)")
                                    local _et = Data.neon_active_colors[Lib.imgui.Col.Text] or {1,1,1,1}
                                    local _alpha = (_et[4] or 1) * 0.55
                                    local _win_size = Lib.imgui.GetWindowSize()
                                    Lib.imgui.SetWindowFontScale(2.0)
                                    local _ts = Lib.imgui.CalcTextSize(empty_txt)
                                    local _tx = math.max(0, (_win_size.x - _ts.x) * 0.5)
                                    local _ty = math.max(0, (_win_size.y - _ts.y) * 0.5)
                                    Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(_tx, _ty))
                                    Lib.imgui.TextColored(Lib.imgui.ImVec4(_et[1],_et[2],_et[3],_alpha), empty_txt)
                                    Lib.imgui.SetWindowFontScale(1.0)
                                end
                               Lib.imgui.Dummy(Lib.imgui.ImVec2(120, 40))
                                local overEmpty = overEmpty2
                                if overEmpty then ui.editor.emptystage_hovered_part = part_idx end
                                local isHoveredEmpty = (ui.editor.emptystage_hovered_part == part_idx)
                                if ui.editor.drag_key_index ~= nil then
                                    if isHoveredEmpty then
                                        local dpart_e = ui.editor.temp_combo[ui.editor.drag_part_index]
                                        local dkey_e  = dpart_e and dpart_e[ui.editor.drag_key_index]
                                        local dname_e = dkey_e and Fn.normalizeKeyName(dkey_e) or ""
                                        local d_sp_e  = (Fn.decodeSafe(dname_e)==Fn.decodeSafe(u8"ПРОБЕЛ") or dname_e=="SPACE")
                                        local dw_e    = d_sp_e and 70 or 50
                                        local ep_min  = Lib.imgui.ImVec2(dmin2.x+4, dmin2.y+(csz2.y-40)*0.5)
                                        local ep_max  = Lib.imgui.ImVec2(ep_min.x+dw_e, ep_min.y+40)
                                        local fdl_e   = Lib.imgui.GetForegroundDrawList()
                                        fdl_e:AddRectFilled(ep_min, ep_max, CBUGER_ApplyGlobalAlphaU32(0x4400FFFF), 4)
                                        fdl_e:AddRect(ep_min, ep_max, CBUGER_ApplyGlobalAlphaU32(0xFF00FFFF), 4, 15, 2)
                                    end
                                    if overEmpty then
                                        if ui.editor.last_hovered_part==part_idx and ui.editor.last_hovered_key==0 then
                                            ui.editor.hover_timer = ui.editor.hover_timer + Lib.imgui.GetIO().DeltaTime
                                            if ui.editor.hover_timer >= 0.15 then
                                                local src  = ui.editor.temp_combo[ui.editor.drag_part_index]
                                                local item = table.remove(src, ui.editor.drag_key_index)
                                                table.insert(part, item)
                                                ui.editor.drag_part_index = part_idx
                                                ui.editor.drag_key_index  = 1
                                                ui.editor.hover_timer     = 0
                                            end
                                        else
                                            ui.editor.hover_timer       = 0
                                            ui.editor.last_hovered_part = part_idx
                                            ui.editor.last_hovered_key  = 0
                                        end
                                    end
                                end
                                if ui.editor.add_row_dragging then
                                    local dk3 = ui.editor.add_row_drag_key
                                    if isHoveredEmpty then
                                        local isSpace3 = (Fn.decodeSafe(dk3)==Fn.decodeSafe(u8"ПРОБЕЛ") or dk3=="SPACE")
                                        local prev_w3  = isSpace3 and 70 or 50
                                        local fdl4 = Lib.imgui.GetForegroundDrawList()
                                        local ep3_min = Lib.imgui.ImVec2(dmin2.x+4, dmin2.y+(csz2.y-40)*0.5)
                                        local ep3_max = Lib.imgui.ImVec2(ep3_min.x+prev_w3, ep3_min.y+40)
                                        fdl4:AddRectFilled(ep3_min, ep3_max, CBUGER_ApplyGlobalAlphaU32(0x4400FFFF), 4)
                                        fdl4:AddRect(ep3_min, ep3_max, CBUGER_ApplyGlobalAlphaU32(0xFF00FFFF), 4, 15, 2)
                                    end
                                    if overEmpty and not Lib.imgui.IsMouseDown(0) then
                                        local kIsHold3 = Fn.getEditorAddIsHold(dk3)[0]
                                        local newKey3 = kIsHold3
                                            and {name=dk3, hold=true, time=Fn.getEditorAddHoldTime(dk3)[0]} or dk3
                                        table.insert(part, newKey3); ui.editor.add_target_part = part_idx
                                        ui.editor.add_row_dragging = false; ui.editor.add_row_drag_key = nil
                                    end
                                end
                            end
                            do
                                local dt_ag = Lib.imgui.GetIO().DeltaTime
                                if not ui.editor.anim_gap      then ui.editor.anim_gap      = 0   end
                                if not ui.editor.anim_gap_key  then ui.editor.anim_gap_key  = nil end
                                if not ui.editor.anim_gap_part then ui.editor.anim_gap_part = nil end
                                local hover_this_part = ui.editor.add_row_dragging
                                    and ui.editor.add_row_hover_part == part_idx
                                local tk  = hover_this_part and ui.editor.add_row_hover_key or nil
                                local dk_ag = ui.editor.add_row_drag_key
                                local isSp_ag = dk_ag and (Fn.decodeSafe(dk_ag)==Fn.decodeSafe(u8"ПРОБЕЛ") or dk_ag=="SPACE")
                                local target_w = (isSp_ag and 70 or 50) + 6
                                if tk then
                                    if ui.editor.anim_gap_part ~= part_idx or ui.editor.anim_gap_key ~= tk then
                                        ui.editor.anim_gap      = 0
                                        ui.editor.anim_gap_part = part_idx
                                        ui.editor.anim_gap_key  = tk
                                    end
                                    ui.editor.anim_gap = target_w
                                elseif ui.editor.anim_gap_part == part_idx then
                                    local spd = 20 * dt_ag
                                    ui.editor.anim_gap = ui.editor.anim_gap * math.max(0, 1 - spd)
                                    if ui.editor.anim_gap < 0.5 then
                                        ui.editor.anim_gap      = 0
                                        ui.editor.anim_gap_key  = nil
                                        ui.editor.anim_gap_part = nil
                                    end
                                end
                            end
                            Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(10, 8))
                            local prev_key_min_rect = nil
                            local prev_key_max_rect = nil
                            for key_idx = 1, #part do
                                local key = part[key_idx]
                                local is_dragging_this = (ui.editor.drag_part_index==part_idx and ui.editor.drag_key_index==key_idx)
                                local kname   = Fn.normalizeKeyName(key)
                                local isHold, holdTime = Fn.getKeyHoldSettings(key)
                                local isSpace = (Fn.decodeSafe(kname)==Fn.decodeSafe(u8"ПРОБЕЛ") or kname=="SPACE")
                                local btn_w   = isSpace and 70 or 50
                                local this_key_is_gap_target = ui.editor.add_row_dragging
                                    and ui.editor.anim_gap_part == part_idx
                                    and ui.editor.anim_gap_key  == key_idx
                                    and (ui.editor.anim_gap or 0) > 0.5
                                if this_key_is_gap_target then
                                    local gap_w   = ui.editor.anim_gap
                                    local item_sp = Lib.imgui.GetStyle().ItemSpacing.x
                                   Lib.imgui.SameLine(0, 0)
                                    local gap_start = Lib.imgui.GetCursorScreenPos()
                                   Lib.imgui.SameLine(0, item_sp + gap_w)
                                    local dk_prev = ui.editor.add_row_drag_key
                                    if dk_prev then
                                        local isSp_prev = (Fn.decodeSafe(dk_prev)==Fn.decodeSafe(u8"ПРОБЕЛ") or dk_prev=="SPACE")
                                        local pw = isSp_prev and 70 or 50
                                        local ph = 40
                                        local gb_prev = neon_fx.global_base_color
                                        local ratio   = math.min(1, gap_w / (pw + 6))
                                        local fill_a  = 0.25 * ratio
                                        local bord_a  = 0.7  * ratio
                                        local text_a  = 0.6  * ratio
                                        local total   = item_sp + gap_w
                                        local px = gap_start.x + (total - pw) * 0.5
                                        local py = gap_start.y
                                        local p_min = Lib.imgui.ImVec2(px, py)
                                        local p_max = Lib.imgui.ImVec2(px + pw, py + ph)
                                        local fill_c = Data.nfn.pack_color(gb_prev[1], gb_prev[2], gb_prev[3], fill_a, true, CBUGER_GET_INTERFACE_ALPHA())
                                        local bord_c = Data.nfn.pack_color(gb_prev[1], gb_prev[2], gb_prev[3], bord_a, true, CBUGER_GET_INTERFACE_ALPHA())
                                        local text_c = Data.nfn.pack_color(1, 1, 1, text_a, true, CBUGER_GET_INTERFACE_ALPHA())
                                        sdl:AddRectFilled(p_min, p_max, fill_c, 4)
                                        sdl:AddRect(p_min, p_max, bord_c, 4, 15, 1.5)
                                        local lbl_prev = Fn.getLocalizedName(dk_prev)
                                        local ts_prev = Lib.imgui.CalcTextSize(lbl_prev)
                                        sdl:AddText(Lib.imgui.ImVec2(px+(pw-ts_prev.x)*0.5, py+(ph-ts_prev.y)*0.5), text_c, lbl_prev)
                                    end
                                else
                                    if key_idx > 1 then
                                        Lib.imgui.SameLine()
                                    end
                                end
                                if is_dragging_this then
                                    local gb3 = neon_fx.global_base_color
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button,        Lib.imgui.ImVec4(gb3[1]*0.25,gb3[2]*0.25,gb3[3]*0.25,0.3))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonHovered, Lib.imgui.ImVec4(gb3[1]*0.25,gb3[2]*0.25,gb3[3]*0.25,0.3))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.ButtonActive,  Lib.imgui.ImVec4(gb3[1]*0.25,gb3[2]*0.25,gb3[3]*0.25,0.3))
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Text,          Lib.imgui.ImVec4(gb3[1]*0.5,gb3[2]*0.5,gb3[3]*0.5,0.4))
                                   Lib.imgui.Button(Fn.getLocalizedName(kname).."##ph_"..part_idx.."_"..key_idx, Lib.imgui.ImVec2(btn_w,40))
                                   Lib.imgui.PopStyleColor(4)
                                else
                                    local tc3 = neon_fx.tabs_color
                                    local _cba3 = Data.neon_active_colors[Lib.imgui.Col.Button] or {tc3[1]*0.2,tc3[2]*0.2,tc3[3]*0.2,0.9}
                                    local col = isHold
                                        and Lib.imgui.ImVec4(0.15, 0.45, 0.1, 1)
                                        or  Lib.imgui.ImVec4(_cba3[1], _cba3[2], _cba3[3], 1)
                                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, col)
                                    local btnLabel = Fn.getLocalizedName(kname)
                                    if isHold then btnLabel = btnLabel..string.format("\n(%.1fs)", holdTime or S.state.DEFAULT_HOLD_TIME) end
                                    if ui.editor.add_row_dragging then
                                        local bp_ar = Lib.imgui.GetCursorScreenPos()
                                       Lib.imgui.InvisibleButton(btnLabel.."##k_"..part_idx.."_"..key_idx, Lib.imgui.ImVec2(btn_w, 40))
                                        local ib_min = Lib.imgui.GetItemRectMin()
                                        local ib_max = Lib.imgui.GetItemRectMax()
                                        local fill_c = Data.nfn.pack_color(col.x, col.y, col.z, col.w, false, 1)
                                        sdl:AddRectFilled(ib_min, ib_max, fill_c, Lib.imgui.GetStyle().FrameRounding)
                                        local txt_c_tbl = Data.neon_active_colors[Lib.imgui.Col.Text] or {1,1,1,1}
                                        local txt_c = Data.nfn.pack_color(txt_c_tbl[1], txt_c_tbl[2], txt_c_tbl[3], 1, false, 1)
                                        local ts = Lib.imgui.CalcTextSize(btnLabel)
                                        sdl:AddText(Lib.imgui.ImVec2(ib_min.x+(btn_w-ts.x)*0.5, ib_min.y+(40-ts.y)*0.5), txt_c, btnLabel)
                                    else
                                       Lib.imgui.Button(btnLabel.."##k_"..part_idx.."_"..key_idx, Lib.imgui.ImVec2(btn_w, 40))
                                    end
                                    if ui.editor.drag_key_index ~= nil and
                                       not (ui.editor.drag_part_index==part_idx and ui.editor.drag_key_index==key_idx) then
                                        local min2 = Lib.imgui.GetItemRectMin(); local max2 = Lib.imgui.GetItemRectMax()
                                        if smp.x>=min2.x and smp.x<=max2.x and smp.y>=min2.y and smp.y<=max2.y then
                                            sdl:AddRect(min2, max2, CBUGER_ApplyGlobalAlphaU32(0xFF00FFFF), 2.0, 15, 3.0)
                                            if ui.editor.last_hovered_key==key_idx and ui.editor.last_hovered_part==part_idx then
                                                ui.editor.hover_timer = ui.editor.hover_timer + Lib.imgui.GetIO().DeltaTime
                                                if ui.editor.hover_timer >= 0.15 then
                                                    local src=ui.editor.temp_combo[ui.editor.drag_part_index]
                                                    local dst=ui.editor.temp_combo[part_idx]
                                                    local item=table.remove(src, ui.editor.drag_key_index)
                                                    table.insert(dst, key_idx, item)
                                                    ui.editor.drag_part_index=part_idx; ui.editor.drag_key_index=key_idx; ui.editor.hover_timer=0
                                                end
                                            else
                                                ui.editor.hover_timer=0; ui.editor.last_hovered_key=key_idx; ui.editor.last_hovered_part=part_idx
                                            end
                                        end
                                    end
                                    if ui.editor.add_row_dragging then
                                        local min2 = Lib.imgui.GetItemRectMin()
                                        local max2  = Lib.imgui.GetItemRectMax()
                                        local gap_ext = this_key_is_gap_target and (ui.editor.anim_gap or 0) or 0
                                        if smp.x >= (min2.x - gap_ext) and smp.x <= max2.x
                                           and smp.y >= min2.y and smp.y <= max2.y then
                                            ui.editor.add_row_hover_part = part_idx
                                            ui.editor.add_row_hover_key  = key_idx
                                            if not Lib.imgui.IsMouseDown(0) then
                                                local dk2 = ui.editor.add_row_drag_key
                                                local kIsHold2 = Fn.getEditorAddIsHold(dk2)[0]
                                                local newKey2 = kIsHold2 and {name=dk2,hold=true,time=Fn.getEditorAddHoldTime(dk2)[0]} or dk2
                                                table.insert(ui.editor.temp_combo[part_idx], key_idx, newKey2); ui.editor.add_target_part = part_idx
                                                ui.editor.add_row_dragging   = false
                                                ui.editor.add_row_drag_key   = nil
                                                ui.editor.add_row_hover_part = nil
                                                ui.editor.add_row_hover_key  = nil
                                                ui.editor.add_row_hover_timer = 0
                                            end
                                        else
                                            if ui.editor.add_row_hover_part == part_idx
                                               and ui.editor.add_row_hover_key == key_idx then
                                                ui.editor.add_row_hover_part = nil
                                                ui.editor.add_row_hover_key  = nil
                                            end
                                        end
                                    end
                                    if not is_dragging_this then
                                        prev_key_min_rect = Lib.imgui.GetItemRectMin()
                                        prev_key_max_rect = Lib.imgui.GetItemRectMax()
                                    end
                                    if Lib.imgui.IsItemHovered() then
                                        if Lib.imgui.IsMouseClicked(1) then
                                            table.remove(part, key_idx); ui.editor.add_target_part = part_idx; Lib.imgui.PopStyleColor(); break
                                        end
                                        if Lib.imgui.IsMouseDoubleClicked(0) and ui.editor.drag_key_index==nil then
                                            ui.editor.edit_time_val[0]      = holdTime or S.state.DEFAULT_HOLD_TIME
                                            ui.editor.edit_time_is_hold[0]  = isHold
                                            ui.editor.edit_time_target_part = part_idx
                                            ui.editor.add_target_part       = part_idx
                                            ui.editor.edit_time_target_key  = key_idx
                                            ui.editor.edit_time_popup       = true
                                        end
                                    end
                                    if Lib.imgui.IsItemActive() and Lib.imgui.IsMouseDragging(0) and ui.editor.drag_key_index==nil then
                                        ui.editor.drag_part_index=part_idx; ui.editor.drag_key_index=key_idx
                                        local bp=Lib.imgui.GetItemRectMin()
                                        ui.editor.drag_offset=Lib.imgui.ImVec2(smp.x-bp.x, smp.y-bp.y)
                                    end
                                   Lib.imgui.PopStyleColor()
                                end
                            end
                            if #part > 0 then
                                Lib.imgui.SameLine(0, Lib.imgui.GetStyle().ItemSpacing.x)
                                Lib.imgui.Dummy(Lib.imgui.ImVec2(10, 1))
                            end
                            local showEnd = (ui.editor.drag_key_index~=nil or ui.editor.add_row_dragging) and #part>0
                            if showEnd then
                               Lib.imgui.SameLine()
                                local avail_ez = math.max(80, Lib.imgui.GetContentRegionAvail().x)
                               Lib.imgui.Dummy(Lib.imgui.ImVec2(avail_ez, 40))
                                local ez_min=Lib.imgui.GetItemRectMin(); local ez_max=Lib.imgui.GetItemRectMax()
                                local ghost_min = Lib.imgui.ImVec2(
                                    prev_key_max_rect and (prev_key_max_rect.x + Lib.imgui.GetStyle().ItemSpacing.x) or ez_min.x,
                                    prev_key_min_rect and prev_key_min_rect.y or ez_min.y)
                                local is_over_ez = smp.x>=ez_min.x and smp.x<=ez_max.x and smp.y>=(ez_min.y-4) and smp.y<=(ez_max.y+4)
                                local add_row_is_over_ez = smp.x>=ez_min.x and smp.x<=ez_max.x and smp.y>=(ez_min.y-4) and smp.y<=(ez_max.y+4)
                                if is_over_ez or add_row_is_over_ez then ui.editor.endzone_hovered_part=part_idx end
                                if ui.editor.drag_key_index~=nil and not (ui.editor.drag_part_index==part_idx and ui.editor.drag_key_index==#part) then
                                    if ui.editor.endzone_hovered_part==part_idx then
                                        local dpart_ez = ui.editor.temp_combo[ui.editor.drag_part_index]
                                        local dkey_ez  = dpart_ez and dpart_ez[ui.editor.drag_key_index]
                                        local dname_ez = dkey_ez and Fn.normalizeKeyName(dkey_ez) or ""
                                        local dsp_ez   = (Fn.decodeSafe(dname_ez)==Fn.decodeSafe(u8"ПРОБЕЛ") or dname_ez=="SPACE")
                                        local dw_ez    = dsp_ez and 70 or 50
                                        local fdl5=Lib.imgui.GetForegroundDrawList()
                                        fdl5:AddRectFilled(ghost_min, Lib.imgui.ImVec2(ghost_min.x+dw_ez, ghost_min.y+40), CBUGER_ApplyGlobalAlphaU32(0x4400FFFF), 4)
                                        fdl5:AddRect(ghost_min, Lib.imgui.ImVec2(ghost_min.x+dw_ez, ghost_min.y+40), CBUGER_ApplyGlobalAlphaU32(0xFF00FFFF), 4, 15, 2)
                                    end
                                    if is_over_ez then
                                        if ui.editor.last_hovered_part==part_idx and ui.editor.last_hovered_key==(#part+1) then
                                            ui.editor.hover_timer=ui.editor.hover_timer+Lib.imgui.GetIO().DeltaTime
                                            if ui.editor.hover_timer>=0.15 then
                                                local src2=ui.editor.temp_combo[ui.editor.drag_part_index]
                                                local dst2=ui.editor.temp_combo[part_idx]
                                                local item2=table.remove(src2, ui.editor.drag_key_index)
                                                table.insert(dst2, item2)
                                                ui.editor.drag_part_index=part_idx; ui.editor.drag_key_index=#dst2; ui.editor.hover_timer=0
                                            end
                                        else
                                            ui.editor.hover_timer=0; ui.editor.last_hovered_part=part_idx; ui.editor.last_hovered_key=#part+1
                                        end
                                    end
                                end
                                if ui.editor.add_row_dragging and ui.editor.endzone_hovered_part==part_idx then
                                    local dk5=ui.editor.add_row_drag_key
                                    local isSp5=(Fn.decodeSafe(dk5)==Fn.decodeSafe(u8"ПРОБЕЛ") or dk5=="SPACE")
                                    local dw5 = isSp5 and 70 or 50
                                    local fdl6=Lib.imgui.GetForegroundDrawList()
                                    fdl6:AddRectFilled(ghost_min, Lib.imgui.ImVec2(ghost_min.x+dw5, ghost_min.y+40), CBUGER_ApplyGlobalAlphaU32(0x4400FFFF), 4)
                                    fdl6:AddRect(ghost_min, Lib.imgui.ImVec2(ghost_min.x+dw5, ghost_min.y+40), CBUGER_ApplyGlobalAlphaU32(0xFF00FFFF), 4, 15, 2)
                                    if add_row_is_over_ez and not Lib.imgui.IsMouseDown(0) then
                                        local kIsHold5=Fn.getEditorAddIsHold(dk5)[0]
                                        local newKey5=kIsHold5 and {name=dk5,hold=true,time=Fn.getEditorAddHoldTime(dk5)[0]} or dk5
                                        table.insert(ui.editor.temp_combo[part_idx], newKey5); ui.editor.add_target_part = part_idx
                                        ui.editor.add_row_dragging=false; ui.editor.add_row_drag_key=nil
                                    end
                                end
                            end
                       Lib.imgui.EndChild()
                       Lib.imgui.Spacing(); Lib.imgui.Separator()
                    end
                    if ui.editor.drag_key_index~=nil then
                        local dpart=ui.editor.temp_combo[ui.editor.drag_part_index]
                        if dpart and dpart[ui.editor.drag_key_index] then
                            local dkey=dpart[ui.editor.drag_key_index]
                            local dname=Fn.normalizeKeyName(dkey); local dlabel=Fn.getLocalizedName(dname)
                            local d_isHold,d_holdTime=Fn.getKeyHoldSettings(dkey)
                            if d_isHold then dlabel=dlabel..string.format("\n(%.1fs)", d_holdTime or 0.5) end
                            local d_isSpace=(Fn.decodeSafe(dname)==Fn.decodeSafe(u8"ПРОБЕЛ") or dname=="SPACE")
                            local psize=Lib.imgui.ImVec2(d_isSpace and 70 or 50, 40)
                            local d_pos=Lib.imgui.ImVec2(mouse_pos.x-ui.editor.drag_offset.x, mouse_pos.y-ui.editor.drag_offset.y)
                            local gb_drag = neon_fx.global_base_color
                            local bgcol=d_isHold and Fn.getColorU32Global(0.2,0.6,0.2,0.92, true) or Fn.getColorU32Global(gb_drag[1]*0.3,gb_drag[2]*0.3,gb_drag[3]*0.3,0.88, true)
                            local bordercol=d_isHold and CBUGER_ApplyGlobalAlphaU32(0xEEFFFFFF) or Data.nfn.pack_color(gb_drag[1],gb_drag[2],gb_drag[3],0.9,true,CBUGER_GET_INTERFACE_ALPHA())
                            local fsw,fsh=getScreenResolution()
                            draw_list:PushClipRect(Lib.imgui.ImVec2(0,0), Lib.imgui.ImVec2(fsw,fsh), false)
                            draw_list:AddRectFilled(d_pos, Lib.imgui.ImVec2(d_pos.x+psize.x,d_pos.y+psize.y), bgcol, 4)
                            draw_list:AddRect(d_pos, Lib.imgui.ImVec2(d_pos.x+psize.x,d_pos.y+psize.y), bordercol, 4, 15, 1.5)
                            local ts=Lib.imgui.CalcTextSize(dlabel)
                            draw_list:AddText(Lib.imgui.ImVec2(d_pos.x+(psize.x-ts.x)*0.5,d_pos.y+(psize.y-ts.y)*0.5), CBUGER_ApplyGlobalAlphaU32(0xFFFFFFFF), dlabel)
                            draw_list:PopClipRect()
                        end
                        if not Lib.imgui.IsMouseDown(0) then ui.editor.add_target_part = ui.editor.drag_part_index or ui.editor.add_target_part; ui.editor.drag_key_index=nil; ui.editor.drag_part_index=nil; ui.editor.hover_timer=0 end
                    end
                    if ui.editor.add_row_dragging and not Lib.imgui.IsMouseDown(0) then
                        ui.editor.add_row_dragging=false; ui.editor.add_row_drag_key=nil
                        ui.editor.add_row_hover_key=nil; ui.editor.add_row_hover_part=nil; ui.editor.add_row_hover_timer=0
                    end
                    if ui.editor.add_row_dragging and ui.editor.add_row_hover_part~=nil then
                    end
                    if ui.editor.edit_time_popup then
                        ui.editor.edit_time_popup=false; Lib.imgui.OpenPopup("CEEditTimePopup")
                    end
                    Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(18, 12))
                    if Lib.imgui.BeginPopup("CEEditTimePopup") then
                        local tp=ui.editor.temp_combo[ui.editor.edit_time_target_part]
                        local tpk=tp and tp[ui.editor.edit_time_target_key]
                       Lib.imgui.Text(Fn.T(u8"Настройки клавиши:")); Lib.imgui.Separator()
                        local holdActive=ui.editor.edit_time_is_hold[0]
                        local toggleLabel=holdActive and Fn.T(u8"Зажатие включено") or Fn.T(u8"Зажатие выключено")
                        local didPush=holdActive
                        if didPush then Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, Lib.imgui.ImVec4(0.2,0.6,0.2,1)) end
                        Data.nfn.PushButtonBorder()
                        if Lib.imgui.Button(toggleLabel, Lib.imgui.ImVec2(180,0)) then
                            local newHold=not holdActive; ui.editor.edit_time_is_hold[0]=newHold
                            local tp2=ui.editor.temp_combo[ui.editor.edit_time_target_part]
                            local tpk2=tp2 and tp2[ui.editor.edit_time_target_key]
                            if tp2 and tpk2 then
                                local kn2=Fn.normalizeKeyName(tpk2)
                                if newHold then tp2[ui.editor.edit_time_target_key]={name=kn2,hold=true,time=ui.editor.edit_time_val[0]}
                                else tp2[ui.editor.edit_time_target_key]=kn2 end
                            end
                        end
                        Data.nfn.PopButtonBorder()
                        if didPush then Lib.imgui.PopStyleColor() end
                       Lib.imgui.Spacing(); Lib.imgui.Text(Fn.T(u8"Время зажатия (сек):"))
                        if Lib.imgui.InputFloat("##CEeditTime", ui.editor.edit_time_val, 0.1, 0.5, "%.2f") then
                            ui.editor.edit_time_val[0]=math.max(0.1, ui.editor.edit_time_val[0])
                            if tp and tpk and type(tpk)=='table' then tpk.time=ui.editor.edit_time_val[0] end
                        end
                       Lib.imgui.Spacing()
                        Data.nfn.PushButtonBorder()
                        if Lib.imgui.Button(Fn.T(u8"Закрыть"), Lib.imgui.ImVec2(80,0)) then Lib.imgui.CloseCurrentPopup() end
                        Data.nfn.PopButtonBorder()
                       Lib.imgui.EndPopup()
                    end
                    Lib.imgui.PopStyleVar()
                    Data.nfn.PushButtonBorder()
                    if Lib.imgui.Button(Fn.T(u8"+ Добавить этап"), Lib.imgui.ImVec2(-1, 25)) then
                        table.insert(ui.editor.temp_combo, {}); ui.editor.add_target_part = nil
                    end
                    Data.nfn.PopButtonBorder()
               Lib.imgui.EndChild()
               Lib.imgui.GetStyle().ScrollbarSize=old_sr2; Lib.imgui.GetStyle().ScrollbarRounding=old_srr2
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, ced_h - 90))
                do local _addtd = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {1,1,1,1}
               Lib.imgui.TextColored(Lib.imgui.ImVec4(_addtd[1],_addtd[2],_addtd[3],(_addtd[4] or 1)*0.9), ((ui.editor.add_target_part and ui.editor.add_target_part >= 1 and ui.editor.add_target_part <= #ui.editor.temp_combo and ui.editor.add_target_part ~= #ui.editor.temp_combo) and (Fn.T(u8"Добавить клавишу в этап ") .. ui.editor.add_target_part .. ":") or Fn.T(u8"Добавить клавишу в последний этап:")))
                end
               Lib.imgui.SetCursorPos(Lib.imgui.ImVec2(15, ced_h - 68))
                local keys_to_add = {
                    {k=u8"ЛКМ", gap=0}, {k=u8"ПКМ", gap=12},
                    {k="W", gap=0}, {k="A", gap=0}, {k="S", gap=0}, {k="D", gap=12},
                    {k="C", gap=12},
                    {k=u8"ПРОБЕЛ", gap=12},
                    {k="Q", gap=0}, {k="E", gap=0},
                }
                local first_key = true
                for i, entry in ipairs(keys_to_add) do
                    local k = entry.k
                    if not first_key then
                        local prev_gap = keys_to_add[i-1].gap
                       Lib.imgui.SameLine(0, prev_gap > 0 and prev_gap or 4)
                    end
                    first_key = false
                    local btn_w2 = (Fn.decodeSafe(k)==Fn.decodeSafe(u8"ПРОБЕЛ")) and 70 or 50
                    local isHoldPtr = Fn.getEditorAddIsHold(k); local holdTimePtr = Fn.getEditorAddHoldTime(k)
                    local tc4 = neon_fx.tabs_color
                    local _cba4 = Data.neon_active_colors[Lib.imgui.Col.Button] or {tc4[1]*0.2,tc4[2]*0.2,tc4[3]*0.2,0.9}
                    local btnColor = isHoldPtr[0]
                        and Lib.imgui.ImVec4(0.15, 0.45, 0.1, 1)
                        or  Lib.imgui.ImVec4(_cba4[1], _cba4[2], _cba4[3], 1)
                   Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, btnColor)
                    local btnLabel2 = Fn.getLocalizedName(k)
                    if isHoldPtr[0] then btnLabel2=btnLabel2..string.format("\n%.1fs", holdTimePtr[0]) end
                    if Lib.imgui.Button(btnLabel2.."##ceadd_"..i, Lib.imgui.ImVec2(btn_w2, 40)) then
                        if #ui.editor.temp_combo==0 then table.insert(ui.editor.temp_combo, {}) end
                        local newKey6 = isHoldPtr[0] and {name=k,hold=true,time=holdTimePtr[0]} or k
                        local _tgt = ui.editor.add_target_part
                        if not _tgt or _tgt < 1 or _tgt > #ui.editor.temp_combo then _tgt = #ui.editor.temp_combo end
                        table.insert(ui.editor.temp_combo[_tgt], newKey6)
                    end
                    if Lib.imgui.IsItemActive() and Lib.imgui.IsMouseDragging(0) and not ui.editor.add_row_dragging then
                        local bp2=Lib.imgui.GetItemRectMin(); local mp2=Lib.imgui.GetMousePos()
                        ui.editor.add_row_dragging=true; ui.editor.add_row_drag_key=k
                        ui.editor.add_row_drag_offset=Lib.imgui.ImVec2(mp2.x-bp2.x, mp2.y-bp2.y)
                    end
                    if Lib.imgui.IsItemHovered() and Lib.imgui.IsMouseClicked(1) then
                       Lib.imgui.OpenPopup("CEAddKeyHold_"..i)
                    end
                   Lib.imgui.PopStyleColor()
                    Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.WindowPadding, Lib.imgui.ImVec2(18, 12))
                    if Lib.imgui.BeginPopup("CEAddKeyHold_"..i) then
                       Lib.imgui.Text(Fn.T(u8"Настройки для: ")..Fn.getLocalizedName(k)); Lib.imgui.Separator()
                        local hActive2=isHoldPtr[0]
                        local hLabel2=hActive2 and Fn.T(u8"Зажатие включено") or Fn.T(u8"Зажатие выключено")
                        if hActive2 then Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, Lib.imgui.ImVec4(0.2,0.6,0.2,1)) end
                        Data.nfn.PushButtonBorder()
                        if Lib.imgui.Button(hLabel2, Lib.imgui.ImVec2(180,0)) then isHoldPtr[0]=not hActive2 end
                        Data.nfn.PopButtonBorder()
                        if hActive2 then Lib.imgui.PopStyleColor() end
                       Lib.imgui.Spacing(); Lib.imgui.Text(Fn.T(u8"Время (сек):"))
                        if Lib.imgui.InputFloat("##ceht_"..i, holdTimePtr, 0.1, 0.5, "%.2f") then
                            holdTimePtr[0]=math.max(0.1, holdTimePtr[0])
                        end
                       Lib.imgui.Spacing()
                        Data.nfn.PushButtonBorder()
                        if Lib.imgui.Button(Fn.T(u8"OK"), Lib.imgui.ImVec2(80,0)) then Lib.imgui.CloseCurrentPopup() end
                        Data.nfn.PopButtonBorder()
                       Lib.imgui.EndPopup()
                    end
                    Lib.imgui.PopStyleVar()
                end
                if ui.editor.add_row_dragging and not Lib.imgui.IsMouseDown(0) then
                    ui.editor.add_row_dragging=false; ui.editor.add_row_drag_key=nil
                    ui.editor.add_row_hover_key=nil; ui.editor.add_row_hover_part=nil; ui.editor.add_row_hover_timer=0
                end
                Lib.imgui.PopStyleColor(combo_editor_text_push)
                do
                    local rst = CBUGER_PREPARE_WINDOW_SIZE("cbuger_combo_editor", 680, 560)
                    rst.w, rst.h = neon.combo_editor_window_size.w, neon.combo_editor_window_size.h
                    CBUGER_DRAW_INVISIBLE_RESIZER("cbuger_combo_editor", rst, 520, 360, neon.combo_editor_alpha, true, neon.combo_editor_window_size)
                end
           Lib.imgui.End()
           Lib.imgui.PopStyleColor(pushes_ce)
           Lib.imgui.PopStyleVar(3)
        end
        end
        render_combo_editor()
        local function render_keyboard_logs_combo()
        local X, Y  = getScreenResolution()
        local st    = S.state
       Data.wave_color = Fn.computePulsedColor(
            {ui.wave_color_if4[0], ui.wave_color_if4[1], ui.wave_color_if4[2], ui.wave_color_if4[3]},
            ui.wave_color_rgb[0], ui.rgb_speed[0])
       Data.wave_draw_list_ref = nil
        if ui.wave_enabled[0] then
            local dt    = Lib.imgui.GetIO().DeltaTime
            local speed = math.max(0.1, ui.wave_speed[0])
            if #Data.wave_keys_list > 0 then
               Data.wave_key_index = Data.wave_key_index + dt * speed * 8
                if Data.wave_key_index > #Data.wave_keys_list + 1 then
                   Data.wave_key_index = 1.0
                   Data.wave_cycle     = Data.wave_cycle + 1
                end
            else
               Data.wave_key_index = 1.0
            end
           Data.wave_keys_list = {}
        else
           Data.wave_keys_list = {}
           Data.wave_key_index = 1.0
        end
        if ui.guide_open[0] then Fn.RenderGuide() end
        if ui.keyboard[0] then Fn.RenderKeyboard() end
        if ui.keyboard[0] and ui.keyboard_type[0] == 0 then Fn.RenderSpaceKey() end
        if ui.mouse[0] then Fn.RenderMouse() end
       Fn.RenderWave()
       Fn.RenderLogsWindow()

        if st.current_combo and ui.show_combo_window[0] then
            local scale = math.max(0.6, math.min(2.5, ui.combo_window_scale[0] or 1.0))

            local combo_initial_position_pending = not ui.combo_pos_initialized
            if not ui.combo_pos_initialized then
                local sx2, sy2 = getScreenResolution()
                if S.cfg.combo.x < 0 or S.cfg.combo.y < 0 then
                    ui.combo_pos.x = (sx2 - (S.cfg.combo.w or 280)) / 2
                    ui.combo_pos.y = sy2 - (S.cfg.combo.h or 120) - 80
                else
                    ui.combo_pos.x = S.cfg.combo.x
                    ui.combo_pos.y = S.cfg.combo.y
                end
                ui.combo_pos_initialized = true
                ui.combo_open[0] = true
               Lib.imgui.SetNextWindowPos(Lib.imgui.ImVec2(ui.combo_pos.x, ui.combo_pos.y), Lib.imgui.Cond.Always)
            end
            local function update_combo_auto_size()
                local scale2 = math.max(0.6, math.min(2.5, ui.combo_window_scale[0] or 1.0))
                local mode = ui.combo_window_display_mode[0]
                local combo = st.current_combo or {}
                local display_groups = Fn.BuildComboDisplayGroups(combo)

                local desired_w = 148 * scale2
                local desired_h = 108 * scale2
                local content_w = 0
                local content_h = 0
                local outer_x = 12 * scale2
                local outer_y = 54 * scale2
                if mode == 2 then

                    local box_h = math.max(18, math.min(60, tonumber(plaque_layout_stage_h_px[0]) or 28.0)) * scale2
                    for _, group in ipairs(display_groups) do
                        local part = group.part
                        local row_w = 0
                        local item_spacing = (Lib.imgui.GetStyle().ItemSpacing.x or 4)
                        for i, key in ipairs(part) do
                            local kn = Fn.normalizeKeyName(key)
                            local display = Fn.getLocalizedName(kn)
                            local text_sz = Lib.imgui.CalcTextSize(display)
                            local box_w = math.max(40, text_sz.x + 12) * scale2
                            local safe_kn = Fn.decodeSafe(kn)
                            if safe_kn == Fn.decodeSafe(u8"ПРОБЕЛ") or safe_kn == "SPACE" then
                                box_w = math.max(80, text_sz.x + 24) * scale2
                            end
                            row_w = row_w + box_w + 6 * scale2
                            if i < #part then row_w = row_w + item_spacing end
                        end
                        if group.count > 1 then

                            local repeat_w = Lib.imgui.CalcTextSize("x" .. tostring(group.count)).x * 1.15 * scale2
                            row_w = row_w + item_spacing * scale2 + repeat_w
                        end
                        content_w = math.max(content_w, row_w)
                        content_h = content_h + box_h
                    end
                else
                    local line_h = Lib.imgui.GetTextLineHeight() * scale2
                    for _, group in ipairs(display_groups) do
                        local part = group.part
                        local row_w = 0
                        local item_spacing = (Lib.imgui.GetStyle().ItemSpacing.x or 4)
                        for i, key in ipairs(part) do
                            local display = Fn.getLocalizedName(Fn.normalizeKeyName(key))
                            local text_sz = Lib.imgui.CalcTextSize(display)
                            row_w = row_w + text_sz.x * scale2
                            if i < #part then row_w = row_w + 12 * scale2 + item_spacing end
                        end
                        if group.count > 1 then
                            local repeat_w = Lib.imgui.CalcTextSize("x" .. tostring(group.count)).x * scale2
                            row_w = row_w + item_spacing * scale2 + repeat_w
                        end
                        content_w = math.max(content_w, row_w)
                        content_h = content_h + line_h
                    end
                end
                local actual_row_gap = mode == 2
                    and math.max(0, tonumber(plaque_layout_gap_extra[0]) or 4.0)
                    or math.max(0, tonumber(combo_layout_gap_extra[0]) or 4.0)
                if #display_groups > 1 then
                    content_h = content_h + (#display_groups - 1) * actual_row_gap
                end

                local fit_stage_h = mode == 2
                    and math.max(18, math.min(60, tonumber(plaque_layout_stage_h_px[0]) or 28.0)) * scale2
                    or Lib.imgui.GetTextLineHeight() * scale2
                local fit_geometry = combo_get_row_geometry(mode, fit_stage_h, actual_row_gap,
                    fit_stage_h + actual_row_gap)
                local fit_row_h = math.max(fit_stage_h, tonumber(fit_geometry.row_h) or fit_stage_h)
                local fit_row_step
                if fit_geometry.measured then
                    fit_row_step = math.max(fit_row_h, tonumber(fit_geometry.row_step) or (fit_row_h + actual_row_gap))
                else
                    fit_row_step = fit_row_h * 2 + actual_row_gap
                end
                local full_geometry_content_h = #display_groups > 0
                    and (fit_row_h + math.max(0, #display_groups - 1) * fit_row_step) or 0
                content_h = math.max(content_h, full_geometry_content_h)

                local combo_bottom_padding = (mode == 2
                    and math.max(0, tonumber(plaque_layout_bottom_pad[0]) or 0.0)
                    or math.max(0, tonumber(combo_layout_bottom_pad[0]) or 8)) + 2.0

                local mini_error = st.combo_mini_error
                local error_label_active = mini_error and mini_error.key
                    and mini_error.part_index == st.current_part_index
                local reserve_error_always = mode == 2
                    and (plaque_layout_error_always_reserve[0] == true)
                    or (mode ~= 2 and combo_layout_error_always_reserve[0])
                if (mode == 1 or mode == 2) and (reserve_error_always or error_label_active) then
                    local style_for_error = Lib.imgui.GetStyle()
                    local error_line_gap = (style_for_error and style_for_error.ItemSpacing and style_for_error.ItemSpacing.y) or 4
                    local required_error_h = Lib.imgui.GetTextLineHeight() + error_line_gap
                    local configured_error_h = mode == 2
                        and math.max(0, tonumber(plaque_layout_error_reserve[0]) or 18)
                        or math.max(0, tonumber(combo_layout_error_reserve[0]) or 18)
                    content_h = content_h + math.max(configured_error_h, required_error_h)
                end
                desired_w = math.max(desired_w, content_w + outer_x * 2 + 2 * scale2)

                local final_row_safety = 20 * scale2
                desired_h = math.max(desired_h, content_h + outer_y + 12 * scale2 + combo_bottom_padding + final_row_safety)
                local sw, sh = getScreenResolution()
                local max_w = math.max(260 * scale2, sw - 32)
                local max_h = math.max(180 * scale2, sh - 48)
                desired_w = math.min(desired_w, max_w)
                desired_h = math.min(desired_h, max_h)
                S.cfg.combo.w = desired_w
                S.cfg.combo.h = desired_h
                ui.combo_size.x = desired_w
                ui.combo_size.y = desired_h
            end
            local current_combo_mode = (tonumber(ui.combo_window_display_mode[0]) == 2) and 2 or 1
            local combo_signature = tostring(current_combo_mode) .. ":" .. tostring(st.current_combo_name or "") .. ":"
            for _, part in ipairs(st.current_combo or {}) do
                combo_signature = combo_signature .. "["
                for _, key in ipairs(part) do
                    local kn = Fn.normalizeKeyName(key)
                    local is_hold, hold_time = Fn.getKeyHoldSettings(key)
                    combo_signature = combo_signature .. Fn.decodeSafe(kn) .. (is_hold and ("@" .. tostring(hold_time or 0)) or "") .. ","
                end
                combo_signature = combo_signature .. "]"
            end
            combo_signature = combo_signature .. ":scale=" .. tostring(scale)
            local combo_auto_size_changed = false
            local combo_identity_signature = combo_signature:gsub("^[12]:", "")
            combo_active_identity_for_size_cache = combo_identity_signature
            local same_combo_as_last_frame = combo_mode_last_combo_signature ~= nil
                and combo_mode_last_combo_signature == combo_identity_signature
            local mode_switched = combo_mode_last_seen ~= nil and combo_mode_last_seen ~= current_combo_mode
            if mode_switched then

                combo_tail_auto_size = nil
                combo_footer_fit_state = nil

                if type(combo_shared_row_capacity) == 'table' then
                    combo_shared_row_capacity.rows = {}
                end
            end
            if combo_manual_resize_lock and combo_manual_resize_lock.combo_signature ~= combo_signature then
                combo_manual_resize_lock = nil
            end
            local combo_disable_tail_compaction = (combo_manual_resize_lock ~= nil)
            if combo_disable_tail_compaction and combo_tail_auto_size then
                combo_tail_auto_size = nil
                combo_footer_fit_state = nil
            end
            if ui.combo_auto_size_signature ~= combo_signature then
                ui.combo_auto_size_signature = combo_signature
                combo_initial_fit_pending = nil

                local profile_w, profile_h = combo_identity_get_size(combo_identity_signature, current_combo_mode)
                local profile_manually_resized = combo_identity_was_manually_resized(
                    combo_identity_signature, current_combo_mode)
                if profile_w and profile_h and profile_manually_resized then

                    S.cfg.combo.w, S.cfg.combo.h = profile_w, profile_h
                    ui.combo_size.x, ui.combo_size.y = profile_w, profile_h
                else
                    local fit_geometry_before = combo_layout_measured_geometry[current_combo_mode]
                    local fit_was_measured = type(fit_geometry_before) == 'table'
                        and fit_geometry_before.measured == true
                    update_combo_auto_size()
                    combo_mode_store_size(current_combo_mode, S.cfg.combo.w, S.cfg.combo.h)
                    if not fit_was_measured then
                        combo_initial_fit_pending = {
                            signature = combo_signature,
                            mode = current_combo_mode,
                        }
                    end
                end
                ui.combo_size_initialized = true
                combo_auto_size_changed = true
            elseif not ui.combo_size_initialized then
                local fit_geometry_before = combo_layout_measured_geometry[current_combo_mode]
                local fit_was_measured = type(fit_geometry_before) == 'table'
                    and fit_geometry_before.measured == true
                update_combo_auto_size()
                combo_mode_store_size(current_combo_mode, S.cfg.combo.w, S.cfg.combo.h)
                if not fit_was_measured then
                    combo_initial_fit_pending = {
                        signature = combo_signature,
                        mode = current_combo_mode,
                    }
                end
                ui.combo_size_initialized = true
                combo_auto_size_changed = true
            end

            if combo_initial_fit_pending
                and combo_initial_fit_pending.signature == combo_signature
                and tonumber(combo_initial_fit_pending.mode) == current_combo_mode then
                if combo_manual_resize_lock and combo_manual_resize_lock.combo_signature == combo_signature then

                    combo_initial_fit_pending = nil
                else
                    local fit_geometry_after = combo_layout_measured_geometry[current_combo_mode]
                    if type(fit_geometry_after) == 'table' and fit_geometry_after.measured == true then
                        update_combo_auto_size()
                        combo_mode_store_size(current_combo_mode, S.cfg.combo.w, S.cfg.combo.h)
                        combo_initial_fit_pending = nil
                        combo_auto_size_changed = true
                    end
                end
            end

            if combo_auto_size_changed and type(combo_shared_row_capacity) == 'table' then
                combo_shared_row_capacity.rows = {}
            end
            combo_mode_last_combo_signature = combo_identity_signature
            combo_mode_last_seen = current_combo_mode
            local combo_rst = CBUGER_PREPARE_WINDOW_SIZE("cbuger_combo_runtime", S.cfg.combo.w or 280, S.cfg.combo.h or 120)
            if combo_auto_size_changed then
                combo_rst.w = tonumber(S.cfg.combo.w) or 280
                combo_rst.h = tonumber(S.cfg.combo.h) or 120
                combo_rst.resizing = false
            end
            combo_rst = CBUGER_APPLY_WINDOW_SIZE("cbuger_combo_runtime", combo_rst.w or S.cfg.combo.w or 280, combo_rst.h or S.cfg.combo.h or 120)
            if combo_initial_position_pending then
                local screen_w, screen_h = getScreenResolution()
                local window_w = tonumber(S.cfg.combo.w) or tonumber(combo_rst.w) or 280
                local window_h = tonumber(S.cfg.combo.h) or tonumber(combo_rst.h) or 120
                if S.cfg.combo.position_saved ~= true
                    or tonumber(S.cfg.combo.x) == nil or tonumber(S.cfg.combo.y) == nil
                    or S.cfg.combo.x < 0 or S.cfg.combo.y < 0 then

                    ui.combo_pos.x = math.max(0, (screen_w - window_w) * 0.5)
                    ui.combo_pos.y = math.max(0, screen_h - window_h - 80)
                else

                    ui.combo_pos.x = tonumber(S.cfg.combo.x) or 0
                    ui.combo_pos.y = tonumber(S.cfg.combo.y) or 0
                end
                ui.combo_pos_initialized = true
                ui.combo_open[0] = true
                Lib.imgui.SetNextWindowPos(
                    Lib.imgui.ImVec2(ui.combo_pos.x, ui.combo_pos.y), Lib.imgui.Cond.Always)
            end

            if ui.combo_dragging then
                if Lib.imgui.IsMouseDown(0) then
                    local drag_mouse = Lib.imgui.GetMousePos()
                    local drag_screen_w, drag_screen_h = getScreenResolution()
                    local drag_w = tonumber(combo_rst.w) or tonumber(S.cfg.combo.w) or 220
                    local drag_h = tonumber(combo_rst.h) or tonumber(S.cfg.combo.h) or 120
                    ui.combo_pos.x = math.max(0, math.min(math.max(0, drag_screen_w - drag_w),
                        drag_mouse.x - (tonumber(ui.combo_drag_offset.x) or 0)))
                    ui.combo_pos.y = math.max(0, math.min(math.max(0, drag_screen_h - drag_h),
                        drag_mouse.y - (tonumber(ui.combo_drag_offset.y) or 0)))
                    Lib.imgui.SetNextWindowPos(
                        Lib.imgui.ImVec2(ui.combo_pos.x, ui.combo_pos.y), Lib.imgui.Cond.Always)
                else
                    ui.combo_dragging = false
                    S.cfg.combo.position_saved = true
                    S.cfg.combo.x = ui.combo_pos.x
                    S.cfg.combo.y = ui.combo_pos.y
                    pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
                end
            end
            local crc = neon_fx.icon_resize_color
            local ctc = neon_fx.tabs_color
            local cwb = Data.neon_active_colors[Lib.imgui.Col.WindowBg] or {0.04,0.04,0.07,0.97}
            local combo_push = 0
           local combo_border = neon_fx.neon_border_color
           Lib.imgui.PushStyleColor(Lib.imgui.Col.Border, Lib.imgui.ImVec4(combo_border[1], combo_border[2], combo_border[3], combo_border[4] or 0.66)); combo_push = combo_push + 1
            if Lib.imgui.Col.ResizeGrip then
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ResizeGrip,        Lib.imgui.ImVec4(crc[1],crc[2],crc[3],(crc[4] or 0.67)*0.5)); combo_push = combo_push + 1
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ResizeGripHovered, Lib.imgui.ImVec4(crc[1],crc[2],crc[3],(crc[4] or 0.67)*0.8)); combo_push = combo_push + 1
               Lib.imgui.PushStyleColor(Lib.imgui.Col.ResizeGripActive,  Lib.imgui.ImVec4(crc[1],crc[2],crc[3], crc[4] or 0.67));       combo_push = combo_push + 1
            end
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowRounding, 12)
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.WindowBorderSize, 1.5)
           Lib.imgui.PushStyleVarFloat(Lib.imgui.StyleVar.Alpha, ui.interface_alpha[0])
            local open_combo = Lib.imgui.Begin(
                "##combowin",
                ui.combo_open,
               Lib.imgui.WindowFlags.NoCollapse + Lib.imgui.WindowFlags.NoScrollbar +
               Lib.imgui.WindowFlags.NoScrollWithMouse + Lib.imgui.WindowFlags.NoTitleBar + Lib.imgui.WindowFlags.NoResize +
               Lib.imgui.WindowFlags.NoNav
            )
            local combo_width_fit_style_pushes = 0
            if open_combo then

                do
                    local drag_pos = Lib.imgui.GetWindowPos()
                    local drag_size = Lib.imgui.GetWindowSize()
                    local drag_mouse = Lib.imgui.GetMousePos()
                    local drag_zone = drag_mouse.x >= drag_pos.x + 6
                        and drag_mouse.x <= drag_pos.x + drag_size.x - 30
                        and drag_mouse.y >= drag_pos.y + 4
                        and drag_mouse.y <= drag_pos.y + 28
                    if drag_zone and Lib.imgui.IsWindowHovered()
                        and Lib.imgui.IsMouseClicked(0) then
                        ui.combo_dragging = true
                        ui.combo_drag_offset.x = drag_mouse.x - drag_pos.x
                        ui.combo_drag_offset.y = drag_mouse.y - drag_pos.y
                    end
                end
                CBUGER_DRAW_INVISIBLE_RESIZER("cbuger_combo_runtime", combo_rst, 1, 100, ui.interface_alpha[0], true)
                if combo_rst and combo_rst.resizing then
                    combo_identity_manual_size_cache[combo_identity_size_cache_key(
                        combo_identity_signature, current_combo_mode)] = true

                    combo_manual_resize_lock = { combo_signature = combo_signature }
                    combo_disable_tail_compaction = true
                    combo_tail_auto_size = nil
                    combo_footer_fit_state = nil

                    if type(combo_shared_row_capacity) == 'table' then
                        combo_shared_row_capacity.rows = {}
                    end
                end
            end
            if not ui.combo_open[0] then
                ui.show_combo_window[0] = false
                S.cfg.config.show_combo_window = false
               Lib.inicfg.save(S.cfg, Data.iniFile)
                ui.combo_open[0] = true
            end
            if open_combo then
                local wpos2  = Lib.imgui.GetWindowPos()
                local wsize2 = Lib.imgui.GetWindowSize()
                ui.combo_pos.x = wpos2.x; ui.combo_pos.y = wpos2.y
                S.cfg.combo.x = wpos2.x; S.cfg.combo.y = wpos2.y
                S.cfg.combo.position_saved = true
                S.cfg.combo.w  = wsize2.x; S.cfg.combo.h  = wsize2.y
                ui.combo_size.x = wsize2.x; ui.combo_size.y = wsize2.y
                local profile_h = tonumber(wsize2.y) or tonumber(S.cfg.combo.h) or 120
                if not (combo_rst and combo_rst.resizing) then
                    if combo_tail_auto_size and combo_tail_auto_size.combo_signature == combo_signature
                        and tonumber(combo_tail_auto_size.original_h) then
                        profile_h = tonumber(combo_tail_auto_size.original_h)
                    elseif combo_footer_fit_state and combo_footer_fit_state.combo_signature == combo_signature
                        and tonumber(combo_footer_fit_state.base_h) then
                        profile_h = tonumber(combo_footer_fit_state.base_h)
                    end
                end
                combo_mode_store_size(ui.combo_window_display_mode[0], wsize2.x, profile_h)
                local combo_width_font_factor = 1.0
                local combo_title_font_factor = 1.0
                local combo_control_font_factor = 1.0
                local combo_horizontal_factor = 1.0
                local combo_title_font_scale = scale
                local combo_control_font_scale = scale
                local combo_body_font_scale = scale
                Lib.imgui.SetWindowFontScale(scale)
                do
                    local combo_name = Fn.decodeSafe(st.current_combo_name or "")
                    local combo_progress = ""
                    if #st.current_combo > 1 then
                        combo_progress = " (" .. tostring(st.current_part_index) .. "/" .. tostring(#st.current_combo) .. ")"
                    end
                    local combo_title_full = combo_name .. combo_progress
                    local avail_fit = tonumber(Lib.imgui.GetContentRegionAvail().x) or 1
                    local close_w = 20 * scale
                    local title_area_fit = math.max(1, avail_fit - close_w - 28 * scale)
                    local content_pad_fit = 8 * scale
                    local content_area_fit = math.max(1, avail_fit - content_pad_fit)
                    local fit_style = Lib.imgui.GetStyle()
                    local base_item_spacing = (fit_style and fit_style.ItemSpacing and tonumber(fit_style.ItemSpacing.x)) or 4
                    local base_item_spacing_y = (fit_style and fit_style.ItemSpacing and tonumber(fit_style.ItemSpacing.y)) or 4
                    local frame_padding_x = (fit_style and fit_style.FramePadding and tonumber(fit_style.FramePadding.x)) or 4
                    local frame_padding_y = (fit_style and fit_style.FramePadding and tonumber(fit_style.FramePadding.y)) or 3

                    local function combo_fit_text_width(text)
                        local ok, size = pcall(Lib.imgui.CalcTextSize, tostring(text or ""))
                        if ok and size then return math.max(0, tonumber(size.x) or 0) end
                        return 0
                    end
                    local function fit_factor(text_width, available_width)
                        text_width = tonumber(text_width) or 0
                        available_width = math.max(0, tonumber(available_width) or 0)
                        if text_width <= 0 then return 1.0 end
                        return math.max(0.01, math.min(1.0, available_width / text_width))
                    end

                    combo_title_font_factor = fit_factor(combo_fit_text_width(combo_title_full), title_area_fit)
                    local btn_avail_fit = math.max(1, avail_fit - base_item_spacing)
                    local btn_w_fit = math.max(1, math.min(60 * scale, btn_avail_fit / 2))

                    combo_control_font_factor = 1.0

                    combo_width_font_factor = fit_factor(
                        combo_fit_text_width(Fn.T(u8"Нажмите последовательно:")), content_area_fit)
                    local groups_for_width_fit = Fn.BuildComboDisplayGroups(st.current_combo or {})
                    local max_stage_row_width = 0
                    local mode_for_width_fit = (tonumber(ui.combo_window_display_mode[0]) == 2) and 2 or 1
                    for _, group in ipairs(groups_for_width_fit) do
                        local part = group.part or {}
                        local row_w = 0
                        for i, key in ipairs(part) do
                            local display = Fn.getLocalizedName(Fn.normalizeKeyName(key))
                            local display_w = combo_fit_text_width(display)
                            if mode_for_width_fit == 2 then
                                local kn = Fn.normalizeKeyName(key)
                                local safe_kn = Fn.decodeSafe(kn)
                                local box_w = math.max(40, display_w + 12) * scale
                                if safe_kn == Fn.decodeSafe(u8"ПРОБЕЛ") or safe_kn == "SPACE" then
                                    box_w = math.max(80, display_w + 24) * scale
                                end
                                row_w = row_w + box_w + 6 * scale
                                if i < #part then row_w = row_w + base_item_spacing end
                            else
                                row_w = row_w + display_w
                                if i < #part then
                                    row_w = row_w + combo_fit_text_width(" ") + base_item_spacing * 2
                                end
                            end
                        end
                        if (tonumber(group.count) or 1) > 1 then
                            local repeat_width = combo_fit_text_width("x" .. tostring(group.count))
                            if mode_for_width_fit == 2 then repeat_width = repeat_width * 1.15 end
                            row_w = row_w + base_item_spacing + repeat_width
                        end
                        max_stage_row_width = math.max(max_stage_row_width, row_w)
                    end
                    combo_width_font_factor = math.min(combo_width_font_factor,
                        fit_factor(max_stage_row_width, content_area_fit))
                    local mini_error_fit = st.combo_mini_error
                    if mini_error_fit and mini_error_fit.key and mini_error_fit.part_index == st.current_part_index then
                        combo_width_font_factor = math.min(combo_width_font_factor,
                            fit_factor(combo_fit_text_width(Fn.T(u8"Ожидалась: ") .. Fn.getLocalizedName(mini_error_fit.key)), content_area_fit))
                    end

                    combo_title_font_factor = math.max(0.01, math.min(1.0, combo_title_font_factor))
                    combo_control_font_factor = math.max(0.01, math.min(1.0, combo_control_font_factor))
                    combo_width_font_factor = math.max(0.01, math.min(1.0, combo_width_font_factor))
                    combo_horizontal_factor = math.min(combo_width_font_factor, combo_control_font_factor)
                    combo_title_font_scale = scale * combo_title_font_factor
                    combo_control_font_scale = scale
                    combo_body_font_scale = scale * combo_width_font_factor

                    local width_factor_cache = S.state.combo_width_font_factor_by_mode
                    if type(width_factor_cache) ~= 'table' then
                        width_factor_cache = {}
                        S.state.combo_width_font_factor_by_mode = width_factor_cache
                    end
                    local previous_factor = width_factor_cache[mode_for_width_fit]
                    if previous_factor == nil or math.abs(previous_factor - combo_width_font_factor) > 0.015 then
                        combo_layout_measured_geometry[mode_for_width_fit] = nil
                        if type(combo_shared_row_capacity) == 'table' then
                            combo_shared_row_capacity.rows = {}
                            combo_shared_row_capacity.dimensions_by_mode = {}
                        end
                        width_factor_cache[mode_for_width_fit] = combo_width_font_factor
                    end

                    Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.ItemSpacing,
                        Lib.imgui.ImVec2(base_item_spacing * combo_horizontal_factor, base_item_spacing_y))
                    Lib.imgui.PushStyleVarVec2(Lib.imgui.StyleVar.FramePadding,
                        Lib.imgui.ImVec2(frame_padding_x * combo_control_font_factor, frame_padding_y))
                    combo_width_fit_style_pushes = 2

                    Lib.imgui.SetWindowFontScale(combo_title_font_scale)
                    local title_area_w = math.max(1, avail_fit - close_w - 28 * scale)
                    local title_size = Lib.imgui.CalcTextSize(combo_title_full)
                    local title_text_w = tonumber(title_size and title_size.x) or 0

                    if title_text_w > title_area_w and title_text_w > 0 then
                        combo_title_font_scale = combo_title_font_scale * math.max(0.001, title_area_w / title_text_w)
                        Lib.imgui.SetWindowFontScale(combo_title_font_scale)
                        title_size = Lib.imgui.CalcTextSize(combo_title_full)
                        title_text_w = tonumber(title_size and title_size.x) or 0
                    end
                    local title_style = Lib.imgui.GetStyle()
                    local title_left_inset = tonumber(Lib.imgui.GetCursorPosX())
                        or ((title_style and title_style.WindowPadding and tonumber(title_style.WindowPadding.x)) or 8)

                    local title_center_offset = math.max(0, (title_area_w - title_text_w) * 0.5)
                    Lib.imgui.SetCursorPosX(title_left_inset + title_center_offset)
                    do local cbc = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or neon_fx.global_base_color
                        Lib.imgui.TextColored(Lib.imgui.ImVec4(cbc[1],cbc[2],cbc[3],cbc[4] or 0.95), combo_title_full)
                    end
                    Lib.imgui.SameLine(avail_fit - close_w + Lib.imgui.GetStyle().WindowPadding.x)
                    Lib.imgui.SetWindowFontScale(1.0)
                    local btn_pos = Lib.imgui.GetCursorScreenPos()
                    local btn_sz  = 18
                    Lib.imgui.InvisibleButton("##cwclose", Lib.imgui.ImVec2(btn_sz, btn_sz))
                    local hovered = Lib.imgui.IsItemHovered()
                    local clicked = Lib.imgui.IsItemClicked()
                    local bdl_c   = Lib.imgui.GetWindowDrawList()
                    Data.nfn.draw_cross(bdl_c,
                        Lib.imgui.ImVec2(btn_pos.x + btn_sz*0.5, btn_pos.y + btn_sz*0.5),
                        btn_sz * 0.6, hovered, 1.0)
                    if clicked then
                        ui.show_combo_window[0] = false
                        S.cfg.config.show_combo_window = false
                        Lib.inicfg.save(S.cfg, Data.iniFile)
                    end
                    Lib.imgui.SetWindowFontScale(combo_control_font_scale)
                end
                local dm = ui.combo_window_display_mode[0]
                local _cba_n = Data.neon_active_colors[Lib.imgui.Col.Button]       or {0.2,0.2,0.2,0.9}
                local _cba_a = Data.neon_active_colors[Lib.imgui.Col.ButtonActive] or {0.4,0.4,0.4,1.0}
                local _cact = Lib.imgui.ImVec4(_cba_a[1],_cba_a[2],_cba_a[3],_cba_a[4] or 1.0)
                local _cwbc = Data.neon_active_colors[Lib.imgui.Col.Text] or {1.0,1.0,1.0,1.0}
               Lib.imgui.PushStyleColor(Lib.imgui.Col.Text, Lib.imgui.ImVec4(_cwbc[1],_cwbc[2],_cwbc[3],_cwbc[4] or 1.0)); local cw_txt_push = 1
                local combo_button_style = Lib.imgui.GetStyle()
                local combo_button_spacing = (combo_button_style and combo_button_style.ItemSpacing
                    and tonumber(combo_button_style.ItemSpacing.x)) or 4
                local combo_button_avail = tonumber(Lib.imgui.GetContentRegionAvail().x) or (120 * scale)
                local combo_mode_button_w = math.max(1, math.min(60 * scale,
                    (combo_button_avail - combo_button_spacing) / 2))
                local combo_mode_button_h = 20 * scale
                if dm == 1 then Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, _cact) end
                Data.nfn.PushButtonBorder()
                if Lib.imgui.Button(Fn.T(u8"Текст##cwm"), Lib.imgui.ImVec2(combo_mode_button_w, combo_mode_button_h)) then
                    ui.combo_window_display_mode[0] = 1
                    S.cfg.config.combo_window_display_mode = 1
                   Lib.inicfg.save(S.cfg, Data.iniFile)
                end
                Data.nfn.PopButtonBorder()
                if dm == 1 then Lib.imgui.PopStyleColor() end
               Lib.imgui.SameLine()
                local dm2 = ui.combo_window_display_mode[0]
                if dm2 == 2 then Lib.imgui.PushStyleColor(Lib.imgui.Col.Button, _cact) end
                Data.nfn.PushButtonBorder()
                if Lib.imgui.Button(Fn.T(u8"Плашки##cwm"), Lib.imgui.ImVec2(combo_mode_button_w, combo_mode_button_h)) then
                    ui.combo_window_display_mode[0] = 2
                    S.cfg.config.combo_window_display_mode = 2
                   Lib.inicfg.save(S.cfg, Data.iniFile)
                end
                Data.nfn.PopButtonBorder()
                if dm2 == 2 then Lib.imgui.PopStyleColor() end
               Lib.imgui.PopStyleColor(cw_txt_push)
                Lib.imgui.SetWindowFontScale(combo_body_font_scale)
               Lib.imgui.Separator()
               Lib.imgui.Spacing()
                local pad = 8 * scale * combo_width_font_factor
               Lib.imgui.SetCursorPosX(Lib.imgui.GetCursorPosX() + pad)
               Lib.imgui.BeginGroup()
                local function get_visible_combo_groups(display_mode)
                    local list_start_pos = Lib.imgui.GetCursorScreenPos()
                    local groups = Fn.BuildComboDisplayGroups(st.current_combo)
                    if combo_tail_auto_size and combo_tail_auto_size.combo_signature ~= combo_signature then
                        combo_tail_auto_size = nil
                    end

                    local raw_available_h = tonumber(Lib.imgui.GetContentRegionAvail().y) or 0
                    local available_h = math.max(0, raw_available_h)
                    local stage_scale = math.max(0.6, math.min(2.5, ui.combo_window_scale[0] or 1.0))
                    local stage_h
                    if display_mode == 2 then

                        stage_h = math.max(18, math.min(60, tonumber(plaque_layout_stage_h_px[0]) or 28.0)) * stage_scale
                    else
                        stage_h = Lib.imgui.GetTextLineHeight()
                    end

                    local style = Lib.imgui.GetStyle()
                    local base_gap_h = (style and style.ItemSpacing and style.ItemSpacing.y) or 4
                    local stage_gap_h = display_mode == 2
                        and math.max(0, tonumber(plaque_layout_gap_extra[0]) or 4.0)
                        or math.max(0, tonumber(combo_layout_gap_extra[0]) or 4.0)

                    local gap_h = stage_gap_h

                    local bottom_pad = (display_mode == 2
                        and math.max(0, tonumber(plaque_layout_bottom_pad[0]) or 0.0)
                        or math.max(0, tonumber(combo_layout_bottom_pad[0]) or 8)) + 2.0
                    local error_h = 0
                    local error_required_h = 0
                    local mini_error = st.combo_mini_error
                    local error_label_active = mini_error and mini_error.key
                        and mini_error.part_index == st.current_part_index
                    local reserve_error_always = false
                    local configured_error_h = 18
                    if display_mode == 2 then
                        reserve_error_always = plaque_layout_error_always_reserve[0] == true
                        configured_error_h = math.max(0, tonumber(plaque_layout_error_reserve[0]) or 18)
                    else
                        reserve_error_always = combo_layout_error_always_reserve[0] == true
                        configured_error_h = math.max(0, tonumber(combo_layout_error_reserve[0]) or 18)
                    end
                    local reserve_error_now = reserve_error_always or error_label_active
                    if (display_mode == 1 or display_mode == 2) and reserve_error_now then

                        local error_line_h = Lib.imgui.GetTextLineHeight()
                        error_required_h = base_gap_h + error_line_h
                        error_h = math.max(configured_error_h, error_required_h)
                    end

                    local last_stage_threshold = display_mode == 2
                        and math.max(-16, math.min(60, tonumber(plaque_layout_last_stage_threshold_px[0]) or -16.0))
                        or math.max(-16, math.min(60, tonumber(combo_layout_last_stage_threshold_px[0]) or -16.0))
                    local capacity_bottom_reserve = math.max(0, bottom_pad + last_stage_threshold)
                    local usable_h = math.max(0, available_h - capacity_bottom_reserve)
                    local natural_hide_step = math.max(1, stage_h + gap_h)

                    local fallback_step = natural_hide_step
                    local row_geometry = combo_get_row_geometry(display_mode, stage_h, gap_h, fallback_step)
                    local measured_stage_h = math.max(1, tonumber(row_geometry.row_h) or stage_h)
                    local measured_row_step = math.max(measured_stage_h,
                        tonumber(row_geometry.row_step) or natural_hide_step)

                    local tail_compaction_active = combo_tail_auto_size
                        and combo_tail_auto_size.combo_signature == combo_signature
                        and not combo_disable_tail_compaction
                        and not (combo_rst and combo_rst.resizing)
                    local threshold_available_h = available_h
                    if tail_compaction_active and tonumber(combo_tail_auto_size.original_available_h) then
                        local live_size_for_tail = Lib.imgui.GetWindowSize()
                        local live_h_for_tail = tonumber(live_size_for_tail and live_size_for_tail.y) or 0
                        local original_h_for_tail = tonumber(combo_tail_auto_size.original_h) or 0
                        local required_full_combo_h = measured_stage_h
                            + math.max(0, #groups - 1) * measured_row_step
                            + capacity_bottom_reserve

                        local window_restored = original_h_for_tail > 0
                            and live_h_for_tail >= original_h_for_tail - 1.0
                        local full_combo_fits_live = available_h >= required_full_combo_h - 0.5
                        if window_restored or full_combo_fits_live then
                            combo_tail_auto_size = nil
                            combo_footer_fit_state = nil
                            if type(combo_shared_row_capacity) == 'table' then
                                combo_shared_row_capacity.rows = {}
                            end
                            tail_compaction_active = false
                        else
                            threshold_available_h = tonumber(combo_tail_auto_size.original_available_h)
                        end
                    end
                    local threshold_usable_h = math.max(0, threshold_available_h - capacity_bottom_reserve)

                    local threshold_content_bottom_y = list_start_pos.y + threshold_available_h
                    local allowed_stage_bottom_y = threshold_content_bottom_y - capacity_bottom_reserve
                    local first_stage_bottom_y = list_start_pos.y + measured_stage_h
                    local row_limit_for_combo = math.max(1, #groups)
                    local formula_rows = 0
                    for row_idx = 1, row_limit_for_combo do
                        local candidate_bottom_y = first_stage_bottom_y + (row_idx - 1) * measured_row_step
                        if candidate_bottom_y <= allowed_stage_bottom_y + 0.5 then
                            formula_rows = row_idx
                        else
                            break
                        end
                    end
                    formula_rows = math.max(1, math.min(row_limit_for_combo, formula_rows))
                    local computed_rows = formula_rows
                    local hide_step_h = measured_row_step
                    local base_hide_step_h = measured_row_step
                    local hide_step_adjust_h = 0.0
                    local hide_boundary_h = capacity_bottom_reserve + measured_stage_h
                        + math.max(0, computed_rows - 1) * measured_row_step
                    local max_rows = computed_rows
                    local manual_row_limit = math.max(1, tonumber(combo_layout_manual_rows[0]) or 1)
                    if not combo_layout_auto_rows[0] then
                        max_rows = math.min(computed_rows, manual_row_limit)
                    end

                    local shared_combo_signature = combo_signature:gsub("^[12]:", "")
                    local shared_row_settings_signature = table.concat({
                        tostring(combo_layout_gap_extra[0]),
                        tostring(combo_layout_bottom_pad[0]),
                        tostring(combo_layout_last_stage_threshold_px[0]),
                        tostring(combo_layout_hide_step_auto[0]),
                        tostring(combo_layout_hide_step_px[0]),
                        tostring(combo_layout_hide_step_adjust_px[0]),
                        tostring(combo_layout_auto_rows[0]),
                        tostring(combo_layout_manual_rows[0]),
                        tostring(plaque_layout_stage_h_px[0]),
                        tostring(plaque_layout_gap_extra[0]),
                        tostring(plaque_layout_bottom_pad[0]),
                        tostring(plaque_layout_last_stage_threshold_px[0]),
                        tostring(plaque_layout_hide_step_auto[0]),
                        tostring(plaque_layout_hide_step_px[0]),
                        tostring(plaque_layout_hide_step_adjust_px[0]),
                    }, "|")
                    local shared_capacity_state = combo_shared_row_capacity
                    if shared_capacity_state.signature ~= shared_combo_signature
                        or shared_capacity_state.settings_signature ~= shared_row_settings_signature then
                        shared_capacity_state.signature = shared_combo_signature
                        shared_capacity_state.settings_signature = shared_row_settings_signature
                        shared_capacity_state.rows = {}
                        shared_capacity_state.window_w = nil
                        shared_capacity_state.window_h = nil
                        shared_capacity_state.dimensions_by_mode = {}
                    end

                    local current_window_size = Lib.imgui.GetWindowSize()
                    local capacity_window_w = tonumber(current_window_size and current_window_size.x)
                        or tonumber(S.cfg.combo.w) or 0
                    local capacity_window_h = tonumber(current_window_size and current_window_size.y)
                        or tonumber(S.cfg.combo.h) or 0
                    shared_capacity_state.dimensions_by_mode = shared_capacity_state.dimensions_by_mode or {}
                    local mode_dimensions = shared_capacity_state.dimensions_by_mode[display_mode] or {}
                    local previous_capacity_window_w = tonumber(mode_dimensions.w)
                    local previous_capacity_window_h = tonumber(mode_dimensions.h)
                    local window_dimensions_changed =
                        (previous_capacity_window_w and capacity_window_w > 0
                            and math.abs(capacity_window_w - previous_capacity_window_w) > 1.0)
                        or (previous_capacity_window_h and capacity_window_h > 0
                            and math.abs(capacity_window_h - previous_capacity_window_h) > 1.0)
                    if window_dimensions_changed then

                        shared_capacity_state.rows[1] = nil
                        shared_capacity_state.rows[2] = nil
                    end
                    mode_dimensions.w = capacity_window_w
                    mode_dimensions.h = capacity_window_h
                    shared_capacity_state.dimensions_by_mode[display_mode] = mode_dimensions
                    shared_capacity_state.window_w = capacity_window_w
                    shared_capacity_state.window_h = capacity_window_h

                    shared_capacity_state.rows[display_mode] = math.max(1, max_rows)
                    max_rows = math.max(1, math.min(#groups, max_rows))
                    if #groups == 0 then
                        return groups, 0
                    end

                    if max_rows >= #groups then

                        combo_tail_auto_size = nil
                        return groups, 0
                    end

                    local active_group_idx = math.max(1, math.min(#groups,
                        math.floor(tonumber(st.current_part_index) or 1)))
                    for idx, group in ipairs(groups) do
                        if Fn.ComboDisplayGroupContains(group, st.current_part_index) then
                            active_group_idx = idx
                            break
                        end
                    end

                    local visible_groups = {}
                    local visible_group_indices = {}
                    local active_group_position = active_group_idx
                    local start_idx = 1
                    if active_group_position > max_rows then
                        start_idx = math.floor((active_group_position - 1) / max_rows) * max_rows + 1
                    end
                    local last_idx = math.min(#groups, start_idx + max_rows - 1)

                    if combo_tail_auto_size
                        and combo_tail_auto_size.combo_signature == combo_signature
                        and active_group_idx >= (combo_tail_auto_size.start_idx or 1)
                        and not combo_disable_tail_compaction
                        and not (combo_rst and combo_rst.resizing) then
                        start_idx = math.max(active_group_idx, tonumber(combo_tail_auto_size.start_idx) or active_group_idx)
                        start_idx = math.min(#groups, start_idx)
                        last_idx = #groups
                    end

                    if active_group_idx < start_idx or active_group_idx > last_idx then
                        start_idx = active_group_idx
                        last_idx = math.min(#groups, start_idx + max_rows - 1)
                        if active_group_idx == #groups then
                            start_idx = #groups
                            last_idx = #groups
                        end
                    end
                    local visible_order_indices = {}

                    for idx = start_idx, last_idx do
                        visible_order_indices[#visible_order_indices + 1] = idx
                    end

                    for _, idx in ipairs(visible_order_indices) do
                        local group = groups[idx]
                        if group then
                            visible_groups[#visible_groups + 1] = group
                            visible_group_indices[idx] = true
                        end
                    end

                    local hidden_stages = 0
                    for idx, group in ipairs(groups) do
                        if not visible_group_indices[idx] then
                            hidden_stages = hidden_stages + math.max(1, tonumber(group.count) or 1)
                        end
                    end

                    local terminal_single_row_clipped = #groups > 1
                        and active_group_idx == #groups
                        and #visible_groups == 1
                        and raw_available_h < (measured_stage_h + bottom_pad + 4)
                    local page_is_partial_tail = last_idx == #groups
                        and (#visible_groups < max_rows or terminal_single_row_clipped)
                    if page_is_partial_tail and not (combo_rst and combo_rst.resizing)
                        and not combo_disable_tail_compaction then
                        if not combo_tail_auto_size or combo_tail_auto_size.combo_signature ~= combo_signature then
                            combo_tail_auto_size = {
                                combo_signature = combo_signature,
                                start_idx = start_idx,
                                original_h = (current_window_size and current_window_size.y) or (S.cfg.combo.h or 120),
                                original_available_h = available_h,
                            }
                        end
                    end

                    if combo_tail_auto_size and not combo_disable_tail_compaction then
                        local same_combo = combo_tail_auto_size.combo_signature == combo_signature
                        local still_on_tail = same_combo and active_group_idx >= (combo_tail_auto_size.start_idx or 1)
                        if still_on_tail and not (combo_rst and combo_rst.resizing) then
                            local row_count = #visible_groups

                            local live_window_h = tonumber(current_window_size and current_window_size.y)
                                or tonumber(combo_rst and combo_rst.h) or tonumber(S.cfg.combo.h) or 120
                            local fixed_header_h = math.max(0, live_window_h - raw_available_h)
                            local page_content_h = row_count > 0
                                and (measured_stage_h + math.max(0, row_count - 1) * measured_row_step)
                                or 0
                            local error_footer_h = error_h
                            local compact_safety_h = math.max(4, 6 * stage_scale)
                            local target_h = fixed_header_h + page_content_h + error_footer_h + bottom_pad + compact_safety_h
                            local _, screen_h = getScreenResolution()
                            target_h = math.max(100, math.min(math.max(100, (tonumber(screen_h) or 720) - 48), target_h))
                            local live_h = (current_window_size and tonumber(current_window_size.y)) or tonumber(combo_rst and combo_rst.h) or tonumber(S.cfg.combo.h) or 120
                            if math.abs(live_h - target_h) > 1 then
                                combo_rst.h = target_h
                                S.cfg.combo.h = target_h
                                ui.combo_size.y = target_h
                                if combo_tail_auto_size and tonumber(combo_tail_auto_size.original_h) then
                                    combo_mode_store_size(display_mode, S.cfg.combo.w or combo_rst.w, combo_tail_auto_size.original_h)
                                end
                            end
                        elseif not same_combo or (same_combo and active_group_idx < (combo_tail_auto_size.start_idx or 1)) then

                            if same_combo and not (combo_rst and combo_rst.resizing) then
                                local restore_h = tonumber(combo_tail_auto_size.original_h)
                                local live_h = (current_window_size and tonumber(current_window_size.y)) or tonumber(combo_rst and combo_rst.h) or 0
                                if restore_h and math.abs(restore_h - live_h) > 1 then
                                    combo_rst.h = restore_h
                                    S.cfg.combo.h = restore_h
                                    ui.combo_size.y = restore_h
                                    combo_mode_store_size(display_mode, S.cfg.combo.w or combo_rst.w, restore_h)
                                end
                            end
                            combo_tail_auto_size = nil
                        end
                    end
                    return visible_groups, hidden_stages
                end
                local function combo_next_stage_row(display_mode_for_gap)

                    Lib.imgui.NewLine()
                    local current_mode = display_mode_for_gap or ui.combo_window_display_mode[0]
                    local style_now = Lib.imgui.GetStyle()
                    local default_gap = (style_now and style_now.ItemSpacing and tonumber(style_now.ItemSpacing.y)) or 4.0
                    local target_gap = current_mode == 2
                        and math.max(0, tonumber(plaque_layout_gap_extra[0]) or 4.0)
                        or math.max(0, tonumber(combo_layout_gap_extra[0]) or 4.0)
                    local correction = target_gap - default_gap
                    if math.abs(correction) > 0.01 then
                        Lib.imgui.SetCursorPosY(math.max(0, Lib.imgui.GetCursorPosY() + correction))
                    end
                end

                local combo_all_stages_visible_for_error_footer = false
                local combo_error_footer_was_drawn = false
                if ui.combo_window_display_mode[0] == 1 then
                    do local _td_seq = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                   Lib.imgui.TextColored(Lib.imgui.ImVec4(_td_seq[1],_td_seq[2],_td_seq[3],_td_seq[4] or 1), Fn.T(u8"Нажмите последовательно:")) end
                    local _ctxt = {1.0, 1.0, 1.0, 1.0}
                    local _ctxt4 = Lib.imgui.ImVec4(1.0, 1.0, 1.0, 1.0)
                    local _ctxt4_dim = Lib.imgui.ImVec4(0.7, 0.7, 0.7, 1.0)
                    local function render_text_part(part)
                        for i, key in ipairs(part) do
                            if i > 1 then Lib.imgui.SameLine(); Lib.imgui.TextColored(Lib.imgui.ImVec4(1,1,1,0)," "); Lib.imgui.SameLine() end
                            local name2   = Fn.normalizeKeyName(key)
                            local display = Fn.getLocalizedName(name2)
                            local is_error_key = false
                            if st.error_state.is_error and st.wrong_part_index == st.current_part_index then
                                local ws = st.wrong_slot
                                if ws then
                                    is_error_key = (ws == i)
                                elseif st.wrong_key then
                                    is_error_key = Fn.decodeSafe(st.wrong_key) == Fn.decodeSafe(name2)
                                end
                            end
                            if is_error_key then
                               Lib.imgui.TextColored(Lib.imgui.ImVec4(ui.error_color[1],ui.error_color[2],ui.error_color[3],ui.error_color[4]), display)
                            else
                                local now_tf = os.clock()
                                local is_flash = st.last_correct_flash_key and (now_tf - (st.last_correct_flash_time or 0)) < 0.1
                                    and st.last_correct_flash_part_idx == st.current_part_index
                                    and st.last_correct_flash_key_idx  == i
                                if is_flash then
                                   Lib.imgui.TextColored(Lib.imgui.ImVec4(ui.correct_color[1],ui.correct_color[2],ui.correct_color[3],ui.correct_color[4]), display)
                                else
                                    local ks = st.key_states[i]
                                    if st.combo_started and ks == S.KEY_COLORS.HELD then
                                        local now2 = os.clock(); local progress = 0
                                        local reqTime = st.hold_durations[i] or st.DEFAULT_HOLD_TIME
                                        if st.hold_start_times[i] then progress = math.min(1,(now2-st.hold_start_times[i])/reqTime) end
                                       Fn.drawTextWithHoldProgress(name2, progress, _ctxt, ui.held_color)
                                    elseif st.combo_started and ks == 0x00FF00 then
                                       Lib.imgui.TextColored(Lib.imgui.ImVec4(ui.correct_color[1],ui.correct_color[2],ui.correct_color[3],ui.correct_color[4]), display)
                                    elseif st.combo_started and ks == 0xFF0000 then
                                       Lib.imgui.TextColored(Lib.imgui.ImVec4(ui.error_color[1],ui.error_color[2],ui.error_color[3],ui.error_color[4]), display)
                                    elseif ui.logs_combo_rgb[0] and ui.key_text_rgb[0] then
                                        local rc = Fn.computePulsedColor(ui.key_text_color, true, ui.rgb_speed[0])
                                       Lib.imgui.TextColored(Lib.imgui.ImVec4(rc[1],rc[2],rc[3],rc[4]), display)
                                    elseif st.combo_started and ks ~= nil then
                                       Lib.imgui.TextColored(_ctxt4_dim, display)
                                    elseif st.combo_started then
                                       Lib.imgui.TextColored(_ctxt4_dim, display)
                                    else
                                       Lib.imgui.TextColored(_ctxt4, display)
                                    end
                                end
                            end
                        end
                    end
                    local display_groups, hidden_stages = get_visible_combo_groups(1)
                    local all_display_groups = Fn.BuildComboDisplayGroups(st.current_combo)
                    combo_all_stages_visible_for_error_footer = (tonumber(hidden_stages) or 0) == 0
                        and #display_groups >= #all_display_groups
                    local previous_text_row_top_y = nil
                    for group_idx, group in ipairs(display_groups) do
                        if group_idx > 1 then combo_next_stage_row(1) end
                        local row_top_y = Lib.imgui.GetCursorScreenPos().y
                        local part = group.part
                        local row_is_active = Fn.ComboDisplayGroupContains(group, st.current_part_index)
                        if row_is_active then
                            render_text_part(part)
                        else
                            for i, key in ipairs(part) do
                                if i > 1 then Lib.imgui.SameLine(); Lib.imgui.TextColored(Lib.imgui.ImVec4(1,1,1,0)," "); Lib.imgui.SameLine() end
                               Lib.imgui.TextColored(Lib.imgui.ImVec4(0.4, 0.4, 0.4, 1.0), Fn.getLocalizedName(Fn.normalizeKeyName(key)))
                            end
                        end
                        local repeat_count = Fn.ComboDisplayGroupRemainingCount(group, st.current_part_index)
                        if group.count > 1 and repeat_count > 0 then
                            local repeat_text = "x" .. tostring(repeat_count)
                            local repeat_col = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5, 0.7, 0.9, 1.0}
                            Lib.imgui.SameLine()
                            Lib.imgui.TextColored(Lib.imgui.ImVec4(repeat_col[1], repeat_col[2], repeat_col[3], repeat_col[4] or 1.0), repeat_text)
                        end
                        local row_rect_max = Lib.imgui.GetItemRectMax()
                        local row_bottom_y = (row_rect_max and tonumber(row_rect_max.y)) or (row_top_y + Lib.imgui.GetTextLineHeight())
                        local measured_step = previous_text_row_top_y and (row_top_y - previous_text_row_top_y) or nil
                        combo_record_row_geometry(1, row_top_y, math.max(row_top_y, row_bottom_y), measured_step)
                        previous_text_row_top_y = row_top_y
                    end
                else
                    do local _td_seq = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5,0.7,0.9,1}
                        Lib.imgui.TextColored(Lib.imgui.ImVec4(_td_seq[1],_td_seq[2],_td_seq[3],_td_seq[4] or 1), Fn.T(u8"Нажмите последовательно:")) end
                    local combo    = st.current_combo
                    local box_h    = math.max(18, math.min(60, tonumber(plaque_layout_stage_h_px[0]) or 28.0)) * scale
                    local function render_boxed_part(part, part_index)
                       Lib.imgui.BeginGroup()
                        local row_width = 0
                        local item_spacing = (Lib.imgui.GetStyle().ItemSpacing.x or 4)
                        local bdl2 = Lib.imgui.GetWindowDrawList()
                        for i, key in ipairs(part) do
                            local kn      = Fn.normalizeKeyName(key)
                            local display = Fn.getLocalizedName(kn)
                            local idx     = (st.current_part_index == part_index) and i or nil
                            local display_col  = {ui.key_fill_color[1],   ui.key_fill_color[2],   ui.key_fill_color[3],   ui.key_fill_color[4]}
                            local border_col_b = {ui.key_border_color[1], ui.key_border_color[2], ui.key_border_color[3], ui.key_border_color[4]}
                            local text_col     = {ui.key_text_color[1],   ui.key_text_color[2],   ui.key_text_color[3],   ui.key_text_color[4]}
                            if ui.logs_combo_rgb[0] then
                                if ui.key_fill_rgb[0]   then display_col  = Fn.computePulsedColor(ui.key_fill_color,   true, ui.rgb_speed[0]) end
                                if ui.key_border_rgb[0] then border_col_b = Fn.computePulsedColor(ui.key_border_color, true, ui.rgb_speed[0]) end
                                if ui.key_text_rgb[0]   then text_col     = Fn.computePulsedColor(ui.key_text_color,   true, ui.rgb_speed[0]) end
                            end
                            local is_error_slot = false
                            if st.error_state.is_error and st.current_part_index == part_index
                       and st.wrong_part_index == part_index then
                                local ws = st.wrong_slot
                                if ws then
                                    is_error_slot = (ws == i)
                                elseif st.wrong_key then
                                    is_error_slot = Fn.decodeSafe(st.wrong_key) == Fn.decodeSafe(kn)
                                end
                            end
                            if is_error_slot then
                                display_col = {ui.error_color[1],ui.error_color[2],ui.error_color[3],ui.error_color[4]}
                            elseif idx and st.key_states[idx] then
                                local col = st.key_states[idx]
                                if col == S.KEY_COLORS.HELD then
                                elseif col == 0x00FF00 then
                                    display_col = {ui.correct_color[1],ui.correct_color[2],ui.correct_color[3],ui.correct_color[4]}
                                elseif col == 0xFF0000 then
                                    display_col = {ui.error_color[1],ui.error_color[2],ui.error_color[3],ui.error_color[4]}
                                end
                            else
                                local now_cf = os.clock()
                                if st.last_correct_flash_key and (now_cf - (st.last_correct_flash_time or 0)) < 0.1 then
                                    if st.last_correct_flash_part_idx == part_index and st.last_correct_flash_key_idx == i then
                                        display_col = {ui.correct_color[1],ui.correct_color[2],ui.correct_color[3],ui.correct_color[4]}
                                    end
                                end
                            end
                            if not is_error_slot and st.current_part_index ~= part_index then
                                display_col  = {display_col[1]*0.5,  display_col[2]*0.5,  display_col[3]*0.5,  display_col[4]}
                                border_col_b = {border_col_b[1]*0.5, border_col_b[2]*0.5, border_col_b[3]*0.5, border_col_b[4]}
                                text_col     = {text_col[1]*0.5,     text_col[2]*0.5,     text_col[3]*0.5,     text_col[4]}
                            end
                            local txt  = display

                            local text_font = Lib.imgui.GetFont()
                            local text_font_size = Lib.imgui.GetFontSize()
                            local size = text_font:CalcTextSizeA(text_font_size, 1000, 0, txt)
                            local horizontal_fit = combo_width_font_factor or 1.0
                            local boxW = math.max(40 * horizontal_fit, size.x + 12 * horizontal_fit) * ui.combo_window_scale[0]
                            local safe_kn = Fn.decodeSafe(kn)
                            if safe_kn == Fn.decodeSafe(u8"ПРОБЕЛ") or safe_kn == "SPACE" then
                                boxW = math.max(80 * horizontal_fit, size.x + 24 * horizontal_fit) * ui.combo_window_scale[0]
                            end
                            row_width = row_width + boxW + 6 * ui.combo_window_scale[0] * horizontal_fit
                            if i < #part then row_width = row_width + item_spacing end
                            local p2 = Lib.imgui.GetCursorScreenPos()
                            bdl2:AddRectFilled(Lib.imgui.ImVec2(p2.x,p2.y), Lib.imgui.ImVec2(p2.x+boxW,p2.y+box_h),
                               Fn.getColorU32Global(display_col[1],display_col[2],display_col[3],display_col[4], true), 6)
                            if idx and st.key_states[idx] == S.KEY_COLORS.HELD then
                                local now2 = os.clock(); local progress = 0
                                local reqTime = st.hold_durations[idx] or st.DEFAULT_HOLD_TIME
                                if st.hold_start_times[idx] then
                                    progress = math.min(1,(now2-st.hold_start_times[idx])/reqTime)
                                else
                                    local code2 = Fn.nameToCode(kn)
                                    if code2 and st.held_keys[code2] then progress = math.min(1,(now2-st.held_keys[code2])/reqTime) end
                                end
                                if progress > 0 then
                                    local pc = {ui.held_color[1],ui.held_color[2],ui.held_color[3],ui.held_color[4] or 1}
                                    bdl2:AddRectFilled(Lib.imgui.ImVec2(p2.x,p2.y), Lib.imgui.ImVec2(p2.x+boxW*progress,p2.y+box_h),
                                       Fn.getColorU32Global(pc[1],pc[2],pc[3],pc[4], true), 6)
                                end
                            end
                            local alpha = text_col[4] * ui.text_alpha[0]
                            bdl2:AddTextFontPtr(text_font, text_font_size,
                               Lib.imgui.ImVec2(p2.x+(boxW-size.x)/2,p2.y+(box_h-size.y)/2),
                               Fn.getColorU32Global(text_col[1],text_col[2],text_col[3],alpha, true), txt)
                            local should_draw_border = (ui.border_mode[0] == 2) or
                                (ui.border_mode[0] == 3 and idx and st.key_states[idx])
                            if should_draw_border then
                                bdl2:AddRect(Lib.imgui.ImVec2(p2.x,p2.y), Lib.imgui.ImVec2(p2.x+boxW,p2.y+box_h),
                                   Fn.getColorU32Global(border_col_b[1],border_col_b[2],border_col_b[3],border_col_b[4], true),
                                    6, nil, Data.border_thickness[0] * ui.combo_window_scale[0])
                            end
                           Lib.imgui.Dummy(Lib.imgui.ImVec2(boxW + 6 * ui.combo_window_scale[0] * horizontal_fit, box_h))
                            if i ~= #part then Lib.imgui.SameLine() end
                        end
                       Lib.imgui.EndGroup()
                       return row_width
                    end
                    local display_groups, hidden_stages = get_visible_combo_groups(2)
                    local all_display_groups = Fn.BuildComboDisplayGroups(st.current_combo)
                    combo_all_stages_visible_for_error_footer = (tonumber(hidden_stages) or 0) == 0
                        and #display_groups >= #all_display_groups
                    local previous_plaque_row_top_y = nil
                    for group_idx, group in ipairs(display_groups) do
                        if group_idx > 1 then combo_next_stage_row(2) end
                        local row_top_y = Lib.imgui.GetCursorScreenPos().y
                        local row_is_active = Fn.ComboDisplayGroupContains(group, st.current_part_index)
                        local render_part_index = row_is_active and st.current_part_index or group.start_idx
                        render_boxed_part(group.part, render_part_index)

                        local group_rect_max = Lib.imgui.GetItemRectMax()
                        local repeat_count = Fn.ComboDisplayGroupRemainingCount(group, st.current_part_index)
                        if group.count > 1 and repeat_count > 0 then
                            local repeat_text = "x" .. tostring(repeat_count)
                            local repeat_col = Data.neon_active_colors[Lib.imgui.Col.TextDisabled] or {0.5, 0.7, 0.9, 1.0}
                            local repeat_font = Lib.imgui.GetFont()
                            local repeat_font_size = Lib.imgui.GetFontSize() * 1.15
                            local repeat_text_size = repeat_font:CalcTextSizeA(repeat_font_size, 1000, 0, repeat_text)
                            local repeat_x = (group_rect_max and tonumber(group_rect_max.x)) or Lib.imgui.GetCursorScreenPos().x
                            local repeat_y = row_top_y + math.max(0, (box_h - repeat_text_size.y) * 0.5)
                            local item_spacing_x = (Lib.imgui.GetStyle().ItemSpacing.x or 4)
                            Lib.imgui.GetWindowDrawList():AddTextFontPtr(
                                repeat_font, repeat_font_size,
                                Lib.imgui.ImVec2(repeat_x + item_spacing_x, repeat_y),
                                Fn.getColorU32Global(repeat_col[1], repeat_col[2], repeat_col[3], repeat_col[4] or 1.0),
                                repeat_text)
                        end
                        local row_rect_max = Lib.imgui.GetItemRectMax()
                        local row_bottom_y = (row_rect_max and tonumber(row_rect_max.y)) or (row_top_y + box_h)
                        local measured_step = previous_plaque_row_top_y and (row_top_y - previous_plaque_row_top_y) or nil
                        combo_record_row_geometry(2, row_top_y, math.max(row_top_y, row_bottom_y), measured_step)
                        previous_plaque_row_top_y = row_top_y
                    end
                end

                local mini_error = st.combo_mini_error
                if mini_error and mini_error.key and mini_error.part_index == st.current_part_index then
                    Lib.imgui.NewLine()
                    local plaque_height_for_hint = math.max(18, math.min(60, tonumber(plaque_layout_stage_h_px[0]) or 28.0))
                        * math.max(0.6, math.min(2.5, ui.combo_window_scale[0] or 1.0))
                    local hint_up = (ui.combo_window_display_mode[0] == 2)
                        and (math.max(0, math.min(30, tonumber(plaque_layout_error_offset[0]) or 10.0))
                            * plaque_height_for_hint / 28.0)
                        or 10
                    Lib.imgui.SetCursorPosY(math.max(0, Lib.imgui.GetCursorPosY() - hint_up))
                    Lib.imgui.TextColored(Lib.imgui.ImVec4(1,0,0,1), Fn.T(u8"Ожидалась: ") .. Fn.getLocalizedName(mini_error.key))
                    combo_error_footer_was_drawn = true
                end
                local final_bottom_pad = (ui.combo_window_display_mode[0] == 2
                    and math.max(0, tonumber(plaque_layout_bottom_pad[0]) or 0.0)
                    or math.max(0, tonumber(combo_layout_bottom_pad[0]) or 8)) + 2.0
                Lib.imgui.Dummy(Lib.imgui.ImVec2(0, final_bottom_pad))
               Lib.imgui.EndGroup()

                if combo_all_stages_visible_for_error_footer
                    and combo_error_footer_was_drawn
                    and not combo_disable_tail_compaction then
                    local fit_size = Lib.imgui.GetWindowSize()
                    local fit_cursor_y = Lib.imgui.GetCursorPosY()
                    local fit_style = Lib.imgui.GetStyle()
                    local fit_bottom_pad = (fit_style and fit_style.WindowPadding and tonumber(fit_style.WindowPadding.y)) or 8
                    local live_fit_h = tonumber(fit_size.y) or tonumber(combo_rst and combo_rst.h) or tonumber(S.cfg.combo.h) or 120
                    local _, fit_screen_h = getScreenResolution()
                    local max_fit_h = math.max(100, (tonumber(fit_screen_h) or 720) - 48)
                    if combo_rst and combo_rst.resizing then

                        combo_footer_fit_state = nil
                    else
                        if not combo_footer_fit_state or combo_footer_fit_state.combo_signature ~= combo_signature then
                            combo_footer_fit_state = {
                                combo_signature = combo_signature,
                                base_h = live_fit_h,
                                last_auto_h = live_fit_h,
                            }
                        elseif combo_footer_fit_state.last_auto_h
                            and math.abs(live_fit_h - combo_footer_fit_state.last_auto_h) > 1.5 then

                            combo_footer_fit_state.base_h = live_fit_h
                        end

                        local safety_margin = ui.combo_window_display_mode[0] == 2
                            and math.max(0, math.min(24, tonumber(plaque_footer_safety_margin[0]) or 0.0))
                            or math.max(0, tonumber(S.cfg.config.combo_footer_safety_margin) or 0.0)
                        local content_fit_h = fit_cursor_y + fit_bottom_pad + safety_margin
                        local target_fit_h = math.max(tonumber(combo_footer_fit_state.base_h) or live_fit_h, content_fit_h)
                        target_fit_h = math.min(max_fit_h, target_fit_h)
                        if math.abs(target_fit_h - live_fit_h) > 0.5 then
                            combo_rst.h = target_fit_h
                            S.cfg.combo.h = target_fit_h
                            ui.combo_size.y = target_fit_h
                        end
                        combo_footer_fit_state.last_auto_h = target_fit_h
                    end
                elseif combo_rst and combo_rst.resizing then

                    combo_footer_fit_state = nil
                elseif combo_footer_fit_state and combo_footer_fit_state.combo_signature == combo_signature then

                    local current_size = Lib.imgui.GetWindowSize()
                    local current_h = tonumber(current_size and current_size.y) or tonumber(combo_rst and combo_rst.h) or 120
                    local last_auto_h = tonumber(combo_footer_fit_state.last_auto_h)
                    local base_h = tonumber(combo_footer_fit_state.base_h)
                    if last_auto_h and base_h and math.abs(current_h - last_auto_h) <= 1.5
                        and current_h > base_h + 0.5 then
                        combo_rst.h = base_h
                        S.cfg.combo.h = base_h
                        ui.combo_size.y = base_h
                        combo_mode_store_size(ui.combo_window_display_mode[0], S.cfg.combo.w or combo_rst.w, base_h)
                    end
                    combo_footer_fit_state = nil
                else
                    combo_footer_fit_state = nil
                end
               Lib.imgui.SetWindowFontScale(1.0)
            end
            if combo_width_fit_style_pushes > 0 then Lib.imgui.PopStyleVar(combo_width_fit_style_pushes) end
            if combo_push > 0 then Lib.imgui.PopStyleColor(combo_push) end
           Lib.imgui.PopStyleVar(3)
           Lib.imgui.End()
        end
        end
        render_keyboard_logs_combo()
        if has_pushed_font then
            pcall(Lib.imgui.PopFont)
        end
    end
)
neon_render.HideCursor = false
local phantom_render = Lib.imgui.OnFrame(
    function() return ui.editor.active and ui.editor.add_row_dragging end,
    function()
        local dk = ui.editor.add_row_drag_key
        if not dk then return end
        local mp       = Lib.imgui.GetMousePos()
        local kIsHold  = Fn.getEditorAddIsHold(dk)[0]
        local kTime    = Fn.getEditorAddHoldTime(dk)[0]
        local dlabel   = Fn.getLocalizedName(dk)
        if kIsHold then dlabel = dlabel .. string.format("\n(%.1fs)", kTime) end
        local d_isSpace = (Fn.decodeSafe(dk) == Fn.decodeSafe(u8"ПРОБЕЛ"))
        local psz  = Lib.imgui.ImVec2(d_isSpace and 70 or 50, 40)
        local d_pos = Lib.imgui.ImVec2(
            mp.x - ui.editor.add_row_drag_offset.x,
            mp.y - ui.editor.add_row_drag_offset.y
        )
        local dl = Lib.imgui.GetForegroundDrawList()
        local gb_ph = neon_fx.global_base_color
        local bgc = kIsHold
            and Fn.getColorU32Global(0.2, 0.6, 0.2, 0.95, true)
            or  Fn.getColorU32Global(gb_ph[1]*0.3, gb_ph[2]*0.3, gb_ph[3]*0.3, 0.88, true)
        local borderc = kIsHold and CBUGER_ApplyGlobalAlphaU32(0xEEFFFFFF) or Data.nfn.pack_color(gb_ph[1],gb_ph[2],gb_ph[3],0.9,true,CBUGER_GET_INTERFACE_ALPHA())
        dl:AddRectFilled(d_pos, Lib.imgui.ImVec2(d_pos.x+psz.x, d_pos.y+psz.y), bgc, 4)
        dl:AddRect(d_pos, Lib.imgui.ImVec2(d_pos.x+psz.x, d_pos.y+psz.y), borderc, 4, 15, 2)
        local ts = Lib.imgui.CalcTextSize(dlabel)
        dl:AddText(
           Lib.imgui.ImVec2(d_pos.x+(psz.x-ts.x)*0.5, d_pos.y+(psz.y-ts.y)*0.5),
            CBUGER_ApplyGlobalAlphaU32(0xFFFFFFFF), dlabel)
    end
)
phantom_render.HideCursor = false
local recoil_render = Lib.imgui.OnFrame(
    function() return ui.recoil_enabled[0] end,
    function(self)
        self.HideCursor = true
        local dl = Lib.imgui.GetForegroundDrawList()
        local sw, sh = getScreenResolution()
        if ui.recoil_show_line[0] then
            local lc = neon_fx.global_base_color
            local line_col = CBUGER_ApplyOverlayAlphaU32(
                Fn.getColorU32(lc[1], lc[2], lc[3], lc[4] or 0.95))
            Fn.drawRecoilRing(dl, line_col, ui.recoil_line_thickness[0])
        end
        if Data.recoil_flash_time then
            local dt  = os.clock() - Data.recoil_flash_time
            local dur = math.max(0.005, ui.recoil_flash_duration[0])
            if dt < dur then
                local fc = neon_fx.recoil_flash_color
                local a  = (1 - dt / dur) * ui.recoil_flash_alpha[0]
                dl:AddRectFilled(Lib.imgui.ImVec2(0, 0), Lib.imgui.ImVec2(sw, sh), Fn.getColorU32Global(fc[1], fc[2], fc[3], a, true))
            else
               Data.recoil_flash_time = nil
            end
        end
    end
)
recoil_render.HideCursor = true
recoil_render.ShowCursor = false

function CBUGER_ModeMsg(name, on)
    local WORD_ON  = '\226\234\235\254\247\229\237'
    local WORD_OFF = '\238\242\234\235\254\247\229\237'
    local label = tostring(name or '')

    if label:sub(1, 1) ~= '/' then label = '/' .. label end
    if ui and ui.interface_lang and ui.interface_lang[0] == 2 then WORD_ON, WORD_OFF = 'enabled', 'disabled' end
    local word  = on and WORD_ON or WORD_OFF
    local colored = '{32CD32}' .. label .. '{FFFFFF}: ' .. (on and '{00FF00}' or '{FF0000}') .. word
    if not pcall(sampAddChatMessage, colored, -1) then
        pcall(sampAddChatMessage, label .. ': ' .. word, -1)
    end
end

Data.MODE_HINTS = {
    target = '/target',
    recoil = '/control',
    shotmap = '/map',
    hm     = '/hm',
    cbug   = '/cbug',
    keymap = '/keymap',
    board  = '/board',
}
Data.mode_hint_pool = {}
Fn.ModeHint = function(str_id, text)
    local im = Lib.imgui
    local hovered = im.IsItemHovered()
    local rmin = im.GetItemRectMin()
    local rmax = im.GetItemRectMax()
    local pool = Data.mode_hint_pool
    local st = pool[str_id]
    if not st then
        st = { status = false, timer = 0, ax = (rmin.x + rmax.x) * 0.5 }
        pool[str_id] = st
    end
    local anim = 0.2
    local show = true
    if hovered then
        for k, v in pairs(pool) do
            if k ~= str_id and os.clock() - v.timer <= anim then show = false end
        end
    end
    if show and st.status ~= hovered then
        st.status = hovered
        st.timer = os.clock()
    end
    if not show then return end
    local between = os.clock() - st.timer
    local alpha
    if between <= anim then
        local f = between / anim
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
        alpha = hovered and f or (1 - f)
    elseif hovered then
        alpha = 1
    else
        return
    end
    if hovered then
        local mx = im.GetIO().MousePos.x
        local lo, hi = rmin.x + 14, rmax.x - 14
        if hi < lo then hi = lo end
        st.ax = math.max(lo, math.min(hi, mx))
    end
    alpha = alpha * math.max(0, math.min(1, neon.main_alpha or 1))
    if alpha <= 0.01 then return end
    local base = im.GetStyle().Colors[im.Col.PopupBg]
    local bg = im.ImVec4(base.x, base.y, base.z, 1)
    local lum = 1 - (0.299 * bg.x + 0.587 * bg.y + 0.114 * bg.z)
    local fg = lum < 0.5 and im.ImVec4(0, 0, 0, 1) or im.ImVec4(1, 1, 1, 1)
    local padx, pady = 8, 5
    local w = im.CalcTextSize(text).x + padx * 2
    local h = im.GetTextLineHeight() + pady * 2
    im.SetNextWindowPos(im.ImVec2(st.ax, rmin.y - 9 + (1 - alpha) * 3), im.Cond.Always, im.ImVec2(0.5, 1.0))
    im.SetNextWindowSize(im.ImVec2(w, h), im.Cond.Always)
    im.PushStyleColor(im.Col.PopupBg, bg)
    im.PushStyleColor(im.Col.Border, bg)
    im.PushStyleColor(im.Col.Text, fg)
    im.PushStyleVarVec2(im.StyleVar.WindowPadding, im.ImVec2(padx, pady))
    im.PushStyleVarFloat(im.StyleVar.WindowRounding, 6)
    im.PushStyleVarFloat(im.StyleVar.Alpha, alpha)
    local wf = im.WindowFlags
    local flags = wf.NoResize + wf.NoScrollbar + wf.NoTitleBar + wf.NoMove
        + (wf.Tooltip or 0) + (wf.NoInputs or 0) + (wf.NoSavedSettings or 0) + (wf.NoFocusOnAppearing or 0)
    im.Begin('##' .. str_id, nil, flags)
        im.SetCursorPos(im.ImVec2(padx, pady))
        im.Text(text)
        pcall(function()
            local wp, ws = im.GetWindowPos(), im.GetWindowSize()
            local dl = im.GetWindowDrawList()
            dl:PushClipRectFullScreen()
            dl:AddTriangleFilled(
                im.ImVec2(wp.x + ws.x * 0.5 - 6, wp.y + ws.y - 1),
                im.ImVec2(wp.x + ws.x * 0.5 + 6, wp.y + ws.y - 1),
                im.ImVec2(wp.x + ws.x * 0.5, wp.y + ws.y + 6),
                im.ColorConvertFloat4ToU32(im.ImVec4(bg.x, bg.y, bg.z, alpha)))
            dl:PopClipRect()
        end)
    im.End()
    im.PopStyleVar(3)
    im.PopStyleColor(3)
end

function CBUGER_CP(s)
    local ok, r = pcall(function() return u8:decode(s) end)
    if ok and r then return r end
    return s
end

do
    local HM = {}
    Data.hm = HM
    local imgui_ = Lib.imgui
    local V2 = imgui_.ImVec2
    local V4 = imgui_.ImVec4

    do
        local okI, ic = pcall(function() return fa.INFINITY end)
        if okI and type(ic) == 'string' and ic ~= '' then Data.INF_ICON = ic end
    end
    HM.run     = Lib.new.bool(false)
    HM.was_run = false
    HM.bullets, HM.initial, HM.holes = {}, {}, {}
    HM.pending_markers = {}
    HM.next_marker_place = 0.0

    HM.movement_epoch = os.clock()
    HM.hotkey      = Lib.new.int(0)
    HM.capturing   = false
    HM.open        = {}
    HM.json_path   = CBUGER_CONFIG .. 'Training_HitMarker.json'
    HM.VERSION     = 2

    local FIELDS = {
        {'hide_all',            'bool',  false, 0, 1},
        {'circle_radius',       'float', 4.0,   0.5, 100},
        {'max_markers',         'int',   20,    0, 200},
        {'marker_transparency', 'float', 1.0,   0.0, 1.0},
        {'max_hits',            'int',   0,     0, 200},
        {'degree_polygon',      'int',   32,    0, 40},
        {'marker_text_size',    'float', 10.0,  5.0, 100.0},
        {'enable_tracers',      'bool',  true,  0, 1},
        {'thickness',           'float', 1.4,   0.1, 20},
        {'random_hit_colors',   'bool',  false, 0, 1},
        {'movement_type',       'int',   0,     0, 3},
        {'movement_distance',   'float', 20.0,  0, 200},
        {'speed',               'float', 1.0,   0.1, 10},
        {'holes_enabled',       'bool',  true,  0, 1},
        {'hole_use_marker_style','bool',  true,  0, 1},
        {'hole_radius',         'float', 3.0,   0.5, 80},
        {'hole_transparency',   'float', 1.0,   0.0, 1.0},
        {'max_holes',           'int',   30,    0, 500},
        {'hole_fade_time',      'float', 10.0,  0.0, 120.0},
        {'hole_polygon',        'int',   8,     0, 40},
        {'obj_target',          'bool',  false, 0, 1},
    }
    local COLORS = {
        {'color_all',  {0.8, 0.8, 0.8, 1.0}},
        {'color_hit',  {1.0, 0.0, 0.0, 1.0}},
        {'color_text', {1.0, 1.0, 1.0, 1.0}},
        {'hole_color', {0.1, 0.1, 0.1, 1.0}},
    }
    HM.FIELDS = FIELDS
    HM.v   = {}
    HM.col = {}
    HM.text = Lib.new.char[256]()

    local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

    local function setText(s)
        s = tostring(s or '')
        local n = math.min(#s, 255)
        Lib.ffi.fill(HM.text, 256, 0)
        Lib.ffi.copy(HM.text, s, n)
    end

    function HM.defaults()
        for _, f in ipairs(FIELDS) do
            local name, kind, dv = f[1], f[2], f[3]
            if not HM.v[name] then
                HM.v[name] = (kind == 'bool' and Lib.new.bool(dv))
                          or (kind == 'int'  and Lib.new.int(dv))
                          or Lib.new.float(dv)
            else
                HM.v[name][0] = dv
            end
        end
        for _, c in ipairs(COLORS) do
            local d = c[2]
            HM.col[c[1]] = { d[1], d[2], d[3], d[4] }
        end
        setText('')
    end
    HM.defaults()

    local function payload()
        local t = { version = HM.VERSION, running = HM.run[0], hotkey_vk = HM.hotkey[0], values = {}, colors = {}, sections = {} }
        for k, x in pairs(HM.open) do if x then t.sections[k] = true end end
        for _, f in ipairs(FIELDS) do
            local x = HM.v[f[1]][0]
            if f[2] == 'bool' then t.values[f[1]] = x and true or false else t.values[f[1]] = tonumber(x) end
        end
        for _, c in ipairs(COLORS) do
            local k = HM.col[c[1]]
            t.colors[c[1]] = { k[1], k[2], k[3], k[4] }
        end
        t.marker_text = Lib.ffi.string(HM.text)
        return t
    end

    HM.last_json = nil
    HM.last_save_check = 0
    function HM.save(force)
        local ok, js = pcall(encodeJson, payload())
        if not ok or not js then return end
        if not force and js == HM.last_json then return end
        if not CBUGER_SAFE_WRITE_FILE(HM.json_path, js) then return false end
        HM.last_json = js
        return true
    end

    function HM.save_tick()
        local now = os.clock()
        if now - HM.last_save_check < 1.0 then return end
        HM.last_save_check = now
        HM.save(false)
    end

    function HM.load()
        local t = CBUGER_SAFE_LOAD_JSON(HM.json_path, function(value)
            return type(value.values) == 'table' or type(value.colors) == 'table'
                or type(value.sections) == 'table' or type(value.marker_text) == 'string'
        end)
        if not t then return end
        if type(t.values) == 'table' then
            for _, fd in ipairs(FIELDS) do
                local x = t.values[fd[1]]
                if x ~= nil then
                    if fd[2] == 'bool' then HM.v[fd[1]][0] = (x == true or x == 1)
                    else
                        x = tonumber(x)
                        if x then
                            x = clamp(x, fd[4], fd[5])
                            if fd[2] == 'int' then x = math.floor(x + 0.5) end
                            HM.v[fd[1]][0] = x
                        end
                    end
                end
            end
        end
        if type(t.colors) == 'table' then
            for _, c in ipairs(COLORS) do
                local k = t.colors[c[1]]
                if type(k) == 'table' then
                    for i = 1, 4 do
                        local n = tonumber(k[i])
                        if n then HM.col[c[1]][i] = clamp(n, 0, 1) end
                    end
                end
            end
        end
        if type(t.sections) == 'table' then
            for k, x in pairs(t.sections) do if x then HM.open[k] = true end end
        end
        if type(t.marker_text) == 'string' then setText(t.marker_text) end
        HM.hotkey[0] = math.floor(tonumber(t.hotkey_vk) or 0)
        HM.run[0] = (t.running == true)
        HM.was_run = HM.run[0]
    end

    function HM.clear_markers() HM.bullets = {}; HM.initial = {}; HM.pending_markers = {}; HM.next_marker_place = 0.0 end
    function HM.clear_holes()   HM.holes = {} end
    function HM.clear_all()     HM.bullets = {}; HM.initial = {}; HM.holes = {}; HM.pending_markers = {}; HM.next_marker_place = 0.0 end

    function HM.sync()
        if HM.run[0] ~= HM.was_run then
            HM.was_run = HM.run[0]
            if not HM.was_run then HM.clear_all() end
            HM.save(true)
            CBUGER_ModeMsg('hm', HM.was_run)
        end
    end

    function HM.reset_defaults()
        local was = HM.run[0]
        HM.defaults()
        HM.clear_all()
        HM.hotkey[0] = 0
        HM.run[0] = was
        HM.save(true)
    end

    local VK_NAMES = {
        [0x03]='Cancel',[0x04]='MButton',[0x05]='XButton1',[0x06]='XButton2',
        [0x08]='Backspace',[0x09]='Tab',[0x0D]='Enter',[0x10]='Shift',[0x11]='Ctrl',[0x12]='Alt',
        [0x14]='CapsLock',[0x1B]='Esc',[0x20]='Space',[0x21]='PgUp',[0x22]='PgDn',[0x23]='End',[0x24]='Home',
        [0x25]='Left',[0x26]='Up',[0x27]='Right',[0x28]='Down',[0x2D]='Insert',[0x2E]='Delete',
        [0xA0]='LShift',[0xA1]='RShift',[0xA2]='LCtrl',[0xA3]='RCtrl',[0xA4]='LAlt',[0xA5]='RAlt',
        [0xC0]='~',[0xBD]='-',[0xBB]='=',[0xDB]='[',[0xDD]=']',[0xBA]=';',[0xDE]="'",[0xBC]=',',[0xBE]='.',[0xBF]='/',[0xDC]='\\',
    }
    for i = 0, 9 do VK_NAMES[0x30 + i] = tostring(i); VK_NAMES[0x60 + i] = 'Num' .. i end
    for i = 0, 25 do VK_NAMES[0x41 + i] = string.char(65 + i) end
    for i = 1, 12 do VK_NAMES[0x6F + i] = 'F' .. i end
    function HM.key_name(vk)
        if not vk or vk == 0 then return Fn.T(u8"Не назначена") end
        return VK_NAMES[vk] or string.format('VK_%d', vk)
    end

    function HM.poll_hotkey()
        local vk = HM.hotkey[0]
        if vk == 0 or HM.capturing then return end
        if Data.samp_chat_is_open then return end
        if neon.target_editor[0] or neon.target_combo_editor[0] then return end
        if type(isPauseMenuActive) == 'function' and isPauseMenuActive() then return end
        if isKeyJustPressed(vk) then HM.run[0] = not HM.run[0] end
    end

    local function fixPos(p1, p2, d)
        d = math.abs(d)
        local dx, dy, dz = p2.x - p1.x, p2.y - p1.y, p2.z - p1.z
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len == 0 then return p1 end
        return { x = p1.x + dx / len * d, y = p1.y + dy / len * d, z = p1.z + dz / len * d }
    end

    local function U32(c)
        return CBUGER_ApplyOverlayAlphaU32(imgui_.ColorConvertFloat4ToU32(c))
    end

    local function newMarker(origin, target)
        local ca = HM.col.color_all
        return {
            hits = 0, hitTime = nil, hitColor = { 0, 0, 0, 0 },
            origin = { x = origin.x, y = origin.y, z = origin.z },
            target = { x = target.x, y = target.y, z = target.z },
            base_origin = { x = target.x, y = target.y, z = target.z },
            isVisible = false, screenX = nil, screenY = nil,
        }
    end

    local function processHit(data)
        local v, col = HM.v, HM.col
        local maxH = v.max_hits[0]
        local ok, hv, hX, hY, hZ = pcall(convert3DCoordsToScreenEx, data.target.x, data.target.y, data.target.z, false, false)
        if not ok or not hv or hZ <= 0 then return false end
        local hitDone = false
        local toRem = {}
        for i = #HM.bullets, 1, -1 do
            local m = HM.bullets[i]



            if m.isVisible and m.screenX and m.screenY then
                local r = v.circle_radius[0]
                local dx, dy = hX - m.screenX, hY - m.screenY
                if dx * dx + dy * dy <= r * r then
                    hitDone = true
                    m.hitTime = os.clock()
                    if v.random_hit_colors[0] then
                        m.hitColor = { math.random(), math.random(), math.random(), col.color_hit[4] }
                    else
                        local ch = col.color_hit
                        m.hitColor = { ch[1], ch[2], ch[3], ch[4] }
                    end
                    m.hits = m.hits + 1
                    if v.holes_enabled[0] then
                        local mx = v.max_holes[0]
                        if mx > 0 then while #HM.holes >= mx do table.remove(HM.holes, 1) end end
                        table.insert(HM.holes, {
                            worldPos = { x = data.target.x, y = data.target.y, z = data.target.z },
                            markerRef = m,


                            screenOffset = { x = hX - m.screenX, y = hY - m.screenY },
                            hitColor = { m.hitColor[1], m.hitColor[2], m.hitColor[3], m.hitColor[4] },
                            spawnTime = os.clock(),
                        })
                    end
                    if maxH > 0 and m.hits >= maxH then table.insert(toRem, i) end
                    break
                end
            end
        end
        if #toRem > 0 then
            table.sort(toRem, function(a, b) return a > b end)
            for _, idx in ipairs(toRem) do table.remove(HM.bullets, idx) end
            if #HM.bullets == 0 and #HM.initial > 0 then
                for _, ip in ipairs(HM.initial) do
                    table.insert(HM.pending_markers, {
                        origin = { x = ip.origin.x, y = ip.origin.y, z = ip.origin.z },
                        target = { x = ip.base_origin.x, y = ip.base_origin.y, z = ip.base_origin.z },
                        replay = true,
                    })
                end
            end
        end
        return hitDone
    end

    CBUGER_HM_onSendBulletSync = function(data)
        if not HM.run[0] or not data or not data.target or not data.origin then return end
        if #HM.bullets > 0 then
            if processHit(data) then return end
        end
        local maxM = HM.v.max_markers[0]
        if maxM == 0 or (#HM.initial + #HM.pending_markers) < maxM then
            table.insert(HM.pending_markers, {
                origin = { x = data.origin.x, y = data.origin.y, z = data.origin.z },
                target = { x = data.target.x, y = data.target.y, z = data.target.z },
            })
        end
    end

    local function drawShape(DL, cx, cy, r, colU32, segs)
        if segs > 2 then
            DL:AddCircleFilled(V2(cx, cy), r, colU32, segs)
        elseif segs == 0 then
            DL:AddRectFilled(V2(cx - r, cy - r), V2(cx + r, cy + r), colU32, 0.0)
        else
            DL:AddCircleFilled(V2(cx, cy), r, colU32, 12)
        end
    end

    local function drawOverlay()
        if not HM.run[0] then return end
        if #HM.bullets == 0 and #HM.holes == 0 and #HM.pending_markers == 0 then return end
        if type(isPauseMenuActive) == 'function' and isPauseMenuActive() then return end
        local DL = imgui_.GetBackgroundDrawList()
        local v, col = HM.v, HM.col
        local now = os.clock()
        if #HM.pending_markers > 0 and now >= (HM.next_marker_place or 0) then
            local pending = table.remove(HM.pending_markers, 1)
            if not pending.replay then
                table.insert(HM.initial, {
                    origin = { x = pending.origin.x, y = pending.origin.y, z = pending.origin.z },
                    base_origin = { x = pending.target.x, y = pending.target.y, z = pending.target.z },
                })
            end
            table.insert(HM.bullets, newMarker(pending.origin, pending.target))
            HM.next_marker_place = now + 0.5
        end
        local hideAll = v.hide_all[0]
        local mt, md, ms = v.movement_type[0], v.movement_distance[0], v.speed[0]

        for i = 1, #HM.bullets do
            local m = HM.bullets[i]
            local t = now - HM.movement_epoch
            local bo = m.base_origin
            if mt == 1 then
                m.target.x = bo.x + md * math.sin(t * ms); m.target.y = bo.y; m.target.z = bo.z
            elseif mt == 2 then
                m.target.x = bo.x; m.target.y = bo.y + md * math.sin(t * ms); m.target.z = bo.z
            elseif mt == 3 then
                m.target.x = bo.x + md * math.sin(t * ms); m.target.y = bo.y + md * math.cos(t * ms); m.target.z = bo.z
            else
                m.target.x, m.target.y, m.target.z = bo.x, bo.y, bo.z
            end
        end

        local radius   = v.circle_radius[0]
        local transp   = v.marker_transparency[0]
        local segs     = v.degree_polygon[0]
        local tracers  = v.enable_tracers[0]
        local ca, ch   = col.color_all, col.color_hit
        local mtext    = Lib.ffi.string(HM.text)

        for i = 1, #HM.bullets do
            local m = HM.bullets[i]
            local _, ov, oX, oY = pcall(convert3DCoordsToScreenEx, m.origin.x, m.origin.y, m.origin.z, false, false)
            local okT, tv, tX, tY, tZ = pcall(convert3DCoordsToScreenEx, m.target.x, m.target.y, m.target.z, false, false)
            local onScreen = okT and tv and tZ > 0
            if onScreen then
                m.screenX, m.screenY, m.isVisible = tX, tY, true
            else
                m.screenX, m.screenY, m.isVisible = nil, nil, false
            end
            if onScreen and not hideAll then
                if tracers then
                    local sX, sY = oX, oY
                    if not ov then
                        local fp = fixPos(m.origin, m.target, tZ)
                        local okF, fv, fX, fY = pcall(convert3DCoordsToScreenEx, fp.x, fp.y, fp.z, false, false)
                        if okF and fv then sX, sY = fX, fY end
                    end
                    if sX and sY then
                        DL:AddLine(V2(sX, sY), V2(tX, tY), U32(V4(ca[1], ca[2], ca[3], ca[4])), v.thickness[0])
                    end
                end
                local mcv
                if m.hitTime and (now - m.hitTime < 0.15) then
                    local hc = m.hitColor
                    mcv = V4(hc[1], hc[2], hc[3], hc[4] * transp)
                else
                    mcv = V4(ca[1], ca[2], ca[3], ca[4] * transp)
                    if m.hitTime then m.hitTime = nil end
                end
                drawShape(DL, tX, tY, radius, U32(mcv), segs)
                if #mtext > 0 then
                    local ct = col.color_text
                    local tcu = U32(V4(ct[1], ct[2], ct[3], ct[4] * transp))
                    local fsize = math.max(4.0, math.min(radius * (v.marker_text_size[0] / 150.0), 100.0))
                    local okFont, font = pcall(function()
                        return (CBUGER_GET_GLOBAL_FONT_OR and CBUGER_GET_GLOBAL_FONT_OR(imgui_.GetFont())) or imgui_.GetFont()
                    end)
                    if okFont and font then
                        local okS, tsz = pcall(function() return font:CalcTextSizeA(fsize, 10000.0, 0.0, mtext) end)
                        if okS and tsz then
                            pcall(function()
                                DL:AddTextFontPtr(font, fsize, V2(tX - tsz.x / 2, tY - tsz.y / 2), tcu, mtext)
                            end)
                        end
                    end
                end
            end
        end

        if v.holes_enabled[0] and not hideAll then
            local fade = v.hole_fade_time[0]
            local useMarkerStyle = true
            local hr = math.max(0.5, math.min(80, v.hole_radius[0]))
            local hsegs = v.degree_polygon[0]
            local hAlpha = v.marker_transparency[0]
            for i = #HM.holes, 1, -1 do
                local h = HM.holes[i]
                local elapsed = now - h.spawnTime
                if fade > 0 and elapsed >= fade then
                    table.remove(HM.holes, i)
                else
                    local holeX, holeY
                    if h.markerRef and h.screenOffset then



                        local m2 = h.markerRef
                        if m2.isVisible and m2.screenX and m2.screenY then
                            holeX = m2.screenX + h.screenOffset.x
                            holeY = m2.screenY + h.screenOffset.y
                        end
                    else

                        local wx, wy, wz = h.worldPos.x, h.worldPos.y, h.worldPos.z
                        if h.markerRef and h.localOffset then
                            local m2 = h.markerRef
                            wx = m2.target.x + h.localOffset.x
                            wy = m2.target.y + h.localOffset.y
                            wz = m2.target.z + h.localOffset.z
                        end
                        local okH, hv2, hSX, hSY, hSZ = pcall(convert3DCoordsToScreenEx, wx, wy, wz, false, false)
                        if okH and hv2 and hSZ > 0 then holeX, holeY = hSX, hSY end
                    end
                    local hc
                    if useMarkerStyle then
                        hc = v.random_hit_colors[0] and (h.hitColor or col.color_hit) or col.color_hit
                    else
                        hc = col.hole_color
                    end
                    local alpha
                    if fade <= 0 then alpha = hc[4] else alpha = math.max(0, 1.0 - elapsed / fade) * hc[4] end
                    alpha = alpha * hAlpha
                    if holeX and holeY then
                        drawShape(DL, holeX, holeY, hr, U32(V4(hc[1], hc[2], hc[3], alpha)), hsegs)
                    end
                end
            end
        end
    end

    local function hm_cond()
        HM.poll_hotkey()
        HM.sync()
        return HM.run[0]
    end

    Fn.drawHitmarkerUI = function(cw, tsec)
        local im = Lib.imgui
        local T  = Fn.T
        local a  = neon.main_alpha
        local v, col = HM.v, HM.col
        local function gap(n) im.Dummy(V2(0, n)) end
        local function hand() if im.IsItemHovered() then Data.nfn.set_hand_cursor() end end
        local function button(label, w)
            Data.ofs_row('bt_' .. (label:match('##(.+)$') or 'x'))
            local r = im.Button(label, V2(w or (cw - 40), 28))
            hand()
            return r
        end
        local INF = Data.INF_ICON or "inf"
        local function slider(id, label, ptr, mn, mx, fmt)
            Data.fixed_slider_pending_x = Data.ofs_get(id, 0.0)
            local text
            if type(label) == 'table' then text = T(label[1]) .. INF .. T(u8")") else text = T(label) end
            Data.nfn.ios_slider(text, ptr, mn, mx, a, nil, fmt)
            gap(5)
        end
        local function toggle(id, label, ptr)
            Data.fixed_toggle_pending_x = Data.ofs_get(id, 0.0)
            Data.nfn.ios_toggle(T(label), ptr, a)
            gap(7)
        end
        local function picker(label, id, tbl)
            Data.ofs_row('cp_' .. id)
            Data.nfn.CustomColorPicker(T(label), id, tbl, true, a)
            gap(6)
        end
        local function choice_row(id, names, ptr)
            Data.ofs_row('ch_' .. id)
            local n = #names
            local bw = (cw - 40 - 4 * (n - 1)) / n
            local cb  = Data.neon_active_colors[im.Col.Button]       or { 0.2, 0.2, 0.2, 0.9 }
            local cba = Data.neon_active_colors[im.Col.ButtonActive] or cb
            local cbh = Data.neon_active_colors[im.Col.ButtonHovered] or cb
            for i = 1, n do
                if i > 1 then im.SameLine(0, 4) end
                local act = ptr[0] == i - 1
                local c = act and cba or cb
                im.PushStyleColor(im.Col.Button,        V4(c[1], c[2], c[3], c[4] or 0.9))
                im.PushStyleColor(im.Col.ButtonHovered, V4(cbh[1], cbh[2], cbh[3], cbh[4] or 1))
                im.PushStyleColor(im.Col.ButtonActive,  V4(cba[1], cba[2], cba[3], cba[4] or 1))
                if im.Button(names[i] .. '##' .. id .. i, V2(bw, 26)) then ptr[0] = i - 1 end
                im.PopStyleColor(3)
                hand()
            end
        end

        toggle('tg_vklyuchit_hitmarker', u8"Включить хитмаркер", HM.run)
        HM.sync()
        im.TextDisabled(T(u8"Меток: ") .. #HM.bullets .. '/' .. (v.max_markers[0] == 0 and INF or v.max_markers[0]) ..
            T(u8"   Дыр: ") .. #HM.holes)
        gap(8)

        if tsec('hm_marks', safe_icon({ "CIRCLE_DOT", "CIRCLE" }, fa.GEAR), T(u8"Метки")) then
        slider('sl_radius_metki', u8"Радиус метки", v.circle_radius, 0.5, 100, '%.1f')
        slider('sl_maks_metok_0', { u8"Макс. меток (0=" }, v.max_markers, 0, 200)
        slider('sl_prozrachnost_metok', u8"Прозрачность меток", v.marker_transparency, 0.0, 1.0)
        slider('sl_popadaniy_do_udaleniya_0', { u8"Попаданий до удаления (0=" }, v.max_hits, 0, 200)
        slider('sl_ugly_0kvadrat', u8"Углы (0=квадрат)", v.degree_polygon, 0, 40)
        toggle('tg_skryt_metki_i_dyry', u8"Скрыть метки и дыры", v.hide_all)
        do

            local avail = im.GetContentRegionAvail().x
            local w = avail * 0.8
            local x0 = im.GetCursorPosX() + (avail - w) / 2 + Data.ofs_get('in_marker_text', 0.0)
            im.SetCursorPosX(x0)
            im.TextDisabled(T(u8"Текст внутри метки"))
            im.SetCursorPosX(x0)
            im.SetNextItemWidth(w)
            im.InputText('##hm_text', HM.text, 256)
        end
        gap(5)
        slider('sl_razmer_teksta', u8"Размер текста", v.marker_text_size, 5.0, 100.0, '%.1f')
        end
        gap(12)

        if tsec('hm_colors', safe_icon({ "PALETTE" }, fa.GEAR), T(u8"Цвета меток")) then
        picker(u8"Базовый цвет метки", 'hm_col_all', col.color_all)
        picker(u8"Цвет попадания", 'hm_col_hit', col.color_hit)
        picker(u8"Цвет текста в метке", 'hm_col_text', col.color_text)
        toggle('tg_sluchaynyy_cvet_pri_popadani', u8"Случайный цвет при попадании", v.random_hit_colors)
        end
        gap(12)

        if tsec('hm_tracers', safe_icon({ "ARROWS_LEFT_RIGHT", "MINUS" }, fa.GEAR), T(u8"Трейсеры")) then
        toggle('tg_otobrazhat_treysery', u8"Отображать трейсеры", v.enable_tracers)
        slider('sl_tolschina_treysera', u8"Толщина трейсера", v.thickness, 0.1, 20, '%.2f')
        end
        gap(12)

        if tsec('hm_move', safe_icon({ "UP_DOWN_LEFT_RIGHT", "ARROWS_UP_DOWN_LEFT_RIGHT" }, fa.GEAR), T(u8"Движение меток")) then
        choice_row('hm_mv', { T(u8"Нет"), 'X', 'Y', 'XY' }, v.movement_type)
        gap(8)
        slider('sl_distanciya_dvizheniya', u8"Дистанция движения", v.movement_distance, 0, 200, '%.0f')
        slider('sl_skorost_dvizheniya', u8"Скорость движения", v.speed, 0.1, 10, '%.1f')
        end
        gap(12)

        if tsec('hm_holes', safe_icon({ "CIRCLE_NOTCH", "CIRCLE" }, fa.GEAR), T(u8"Дыры от пуль")) then
        toggle('tg_vklyuchit_dyry_ot_pul', u8"Включить дыры от пуль", v.holes_enabled)

        v.hole_use_marker_style[0] = true
        slider('sl_radius_dyry', u8"Размер дыры", v.hole_radius, 0.5, 80, '%.1f')
        slider('sl_maks_dyr_0', { u8"Макс. дыр (0=" }, v.max_holes, 0, 500)
        slider('sl_ischezanie_sek_0vechno', u8"Исчезание, сек (0=вечно)", v.hole_fade_time, 0.0, 120.0, '%.1f')
        end
        gap(12)

        if tsec('hm_ctrl', safe_icon({ "KEYBOARD" }, fa.GEAR), T(u8"Управление хитмаркером")) then
        im.Text(T(u8"Горячая клавиша: ") .. HM.key_name(HM.hotkey[0]))
        gap(4)
        if HM.capturing then
            if button(T(u8"Нажмите любую клавишу...") .. '##hmcap') then HM.capturing = false end
            for vk = 3, 254 do
                if isKeyJustPressed(vk) then
                    if vk ~= 0x1B then HM.hotkey[0] = vk; HM.save(true) end
                    HM.capturing = false
                    break
                end
            end
        else
            if button(T(u8"Назначить клавишу") .. '##hmsetkey') then HM.capturing = true end
        end
        if HM.hotkey[0] ~= 0 then
            gap(4)
            if button(T(u8"Сбросить клавишу") .. '##hmclrkey') then HM.hotkey[0] = 0; HM.save(true) end
        end
        gap(8)
        if button(T(u8"Очистить метки") .. '##hmclrm') then HM.clear_markers() end
        gap(4)
        if button(T(u8"Очистить дыры") .. '##hmclrh') then HM.clear_holes() end
        gap(4)
        if button(T(u8"Очистить всё") .. '##hmclra') then HM.clear_all() end
        gap(8)
        gap(8)
        end
        gap(16)
        HM.save_tick()
    end

    do
        local tr = {
            ["Тренировка"] = "Training", ["Хитмаркер"] = "Hitmarker",
            ["Включить хитмаркер"] = "Enable hitmarker", ["Метки"] = "Markers",
            ["Радиус метки"] = "Marker radius", ["Макс. меток (0=?)"] = "Max markers (0=inf)",
            ["Прозрачность меток"] = "Marker opacity", ["Попаданий до удаления (0=?)"] = "Hits before removal (0=inf)",
            ["Углы (0=квадрат)"] = "Corners (0=square)", ["Скрыть метки и дыры"] = "Hide markers and holes",
            ["Текст внутри метки"] = "Text inside marker", ["Размер текста"] = "Text size",
            ["Цвета меток"] = "Marker colors", ["Базовый цвет метки"] = "Base marker color",
            ["Цвет попадания"] = "Hit color", ["Цвет текста в метке"] = "Marker text color",
            ["Случайный цвет при попадании"] = "Random hit color", ["Трейсеры"] = "Tracers",
            ["Отображать трейсеры"] = "Show tracers", ["Толщина трейсера"] = "Tracer thickness",
            ["Движение меток"] = "Marker movement", ["Нет"] = "None",
            ["Дистанция движения"] = "Movement distance", ["Скорость движения"] = "Movement speed",
            ["Дыры от пуль"] = "Bullet holes", ["Включить дыры от пуль"] = "Enable bullet holes",
            ["Размер дыры"] = "Hole size", ["Прозрачность дыр"] = "Hole opacity",
            ["Макс. дыр (0=?)"] = "Max holes (0=inf)", ["Исчезание, сек (0=вечно)"] = "Fade time, s (0=never)",
            ["Форма дыры (0=квадрат)"] = "Hole shape (0=square)", ["Цвет дыры"] = "Hole color",
            ["Управление хитмаркером"] = "Hitmarker control", ["Горячая клавиша: "] = "Hotkey: ",
            ["Не назначена"] = "Not set", ["Нажмите любую клавишу..."] = "Press any key...",
            ["Назначить клавишу"] = "Set hotkey", ["Сбросить клавишу"] = "Clear hotkey",
            ["Очистить метки"] = "Clear markers", ["Очистить дыры"] = "Clear holes", ["Очистить всё"] = "Clear all",
["Макс. меток (0="] = "Max markers (0=", ["Попаданий до удаления (0="] = "Hits before removal (0=", ["Макс. дыр (0="] = "Max holes (0=", ["Меток: "] = "Markers: ", ["   Дыр: "] = "   Holes: ",
        }
        for k, val in pairs(tr) do Data.UI_TRANSLATIONS[Fn.decodeSafe(u8(k))] = val end
    end

    local hm_render = Lib.imgui.OnFrame(hm_cond, function(self)
        self.HideCursor = true
        drawOverlay()
    end)
    hm_render.HideCursor = true
    hm_render.ShowCursor = false

    HM.load()
    HM.save(true)
    Data_hm_save = function() HM.save(true) end

    Data_hm_register = function()
        pcall(sampRegisterChatCommand, 'hm', function() HM.run[0] = not HM.run[0] end)
    end
end

do
    local im = Lib.imgui
    local baked = {
        bt_cbug_clear   = 10.0,
        bt_cbug_hudpos  = 10.0,
        bt_hmcap        = 10.0,
        bt_hmclra       = 10.0,
        bt_hmclrh       = 10.0,
        bt_hmclrm       = 10.0,
        bt_hmreset      = 10.0,
        bt_hmsetkey     = 10.0,
        bt_keymap_reset = 10.0,
        ch_cbug_hudmode = 10.0,
        ch_hm_mv        = 10.0,
        gr_ring         = 8.9,
        bt_board_crmove = 10.0,
        bt_board_rec    = 10.0,
        tg_keymap_active = 2.5,
        gr_keymap_scale = 2.5,
    }
    Data.ofs_pad = { -40.0, -15.0, -10.0, -45.0 }
    function Data.ofs_get(key, base)
        local v = baked[key]
        if v ~= nil then return v end
        return tonumber(base) or 0.0
    end
    function Data.ofs_row(key)
        local off = Data.ofs_get(key, 0.0)
        if math.abs(off) > 0.001 then im.SetCursorPosX(im.GetCursorPosX() + off) end
        return off
    end
end

do
    local CS = {}
    Data.cbug = CS
    local im = Lib.imgui
    local V2, V4 = im.ImVec2, im.ImVec4
    local CFG_NAME = 'cbug_speed'

    local default = {
        settings = {
            required_shots = 7, reset_delay = 300, active = false,
            hud_x = 500, hud_y = 800, font_size = 20, indicator_scale = 1.0,
            fail_timeout = 0.8,
            text_color_r = 0.2, text_color_g = 0.8, text_color_b = 0.2, text_color_a = 1.0,
            hud_mode = 1, show_streak = false, notify_record = false,
        },
        records = {},
        stats = { total_shots = 0, total_hits = 0, total_misses = 0, total_combos = 0, best_streak = 0, total_playtime = 0 },
    }
    local cfg = Lib.inicfg.load(default, CFG_NAME)
    if not cfg then cfg = default end
    cfg.settings = cfg.settings or {}
    cfg.stats    = cfg.stats or {}
    cfg.records  = cfg.records or {}
    for k, v in pairs(default.settings) do if cfg.settings[k] == nil then cfg.settings[k] = v end end
    for k, v in pairs(default.stats)    do if cfg.stats[k]    == nil then cfg.stats[k]    = v end end
    cfg.settings.active = false
    CS.cfg = cfg
    CS.session = { active = false, shots = 0, start_time = 0, last_shot_time = 0, blocked = false }
    CS.run = { session_shots = 0, session_hits = 0, session_combos = 0, streak = 0, session_start = os.clock() }
    CS.playtime_start = os.clock()

    local function save()
        local ok, result = pcall(Lib.inicfg.save, cfg, CFG_NAME)
        return ok and result == true
    end
    CS.save = save

    CS.p_active = Lib.new.bool(false)
    CS.p_req    = Lib.new.int(math.max(1, math.floor(tonumber(cfg.settings.required_shots) or 7)))
    CS.p_scale  = Lib.new.float(tonumber(cfg.settings.indicator_scale) or 1.0)
    CS.p_fail   = Lib.new.float(tonumber(cfg.settings.fail_timeout) or 0.8)
    CS.p_streak = Lib.new.bool(cfg.settings.show_streak and true or false)
    CS.p_notify = Lib.new.bool(cfg.settings.notify_record and true or false)
    CS.color = { tonumber(cfg.settings.text_color_r) or 0.2, tonumber(cfg.settings.text_color_g) or 0.8,
                 tonumber(cfg.settings.text_color_b) or 0.2, tonumber(cfg.settings.text_color_a) or 1.0 }

    function CS.set_active(on)
        cfg.settings.active = on and true or false
        CS.p_active[0] = cfg.settings.active
        CS.session.shots = 0; CS.session.active = false
        save()
        CBUGER_ModeMsg('cbug', cfg.settings.active)
    end

    local function U32(c) return CBUGER_ApplyOverlayAlphaU32(im.ColorConvertFloat4ToU32(c)) end

    local function drawHud()
        local font = (CBUGER_GET_GLOBAL_FONT and CBUGER_GET_GLOBAL_FONT()) or im.GetFont()
        if not font then return end
        local s, ss = cfg.settings, CS.session
        if ss.active and (os.clock() - ss.last_shot_time) > s.fail_timeout then
            ss.active = false; ss.shots = 0
        end
        local c = CS.color
        local colH   = U32(V4(c[1], c[2], c[3], c[4]))
        local colBg  = U32(V4(0.08, 0.08, 0.08, 0.85))
        local colDim = U32(V4(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, c[4] * 0.7))
        local colSh  = CBUGER_ApplyOverlayAlphaU32(0xFF000000)
        local colStr = U32(V4(1, 0.85, 0.1, 1))
        local dl     = im.GetBackgroundDrawList()
        local scale  = s.indicator_scale or 1.0
        local size   = s.font_size * scale
        local mode   = s.hud_mode or 1
        local hx, hy = s.hud_x, s.hud_y
        local total_ms = ss.active and math.floor((os.clock() - ss.start_time) * 1000) or 0
        local progress = math.min(ss.shots / math.max(s.required_shots, 1), 1)
        local run = CS.run
        local shots, streak = ss.shots, run.streak
        if CS.positioning then

            shots = math.max(1, math.floor(s.required_shots / 2))
            streak = 3
            total_ms = 250
        end
        progress = math.min(shots / math.max(s.required_shots, 1), 1)
        if mode == 3 then
            local bw, bh = 80 * scale, 8 * scale
            local bx = hx - bw / 2
            dl:AddRectFilled(V2(bx, hy), V2(bx + bw, hy + bh), colBg, 3)
            if progress > 0 then dl:AddRectFilled(V2(bx, hy), V2(bx + bw * progress, hy + bh), colH, 3) end
        elseif mode == 2 then
            local shots_str = string.format('%d / %d', shots, s.required_shots)
            local ms_str = ss.active and string.format('%.0f ms', total_ms) or '--'
            local sz = font:CalcTextSizeA(size, 1000, 0, shots_str)
            local px = hx - sz.x / 2
            local bw, bh = math.max(sz.x, 80 * scale), 5 * scale
            local bx, by = hx - bw / 2, hy - bh - 2
            dl:AddRectFilled(V2(bx, by), V2(bx + bw, by + bh), colBg, 3)
            if progress > 0 then dl:AddRectFilled(V2(bx, by), V2(bx + bw * progress, by + bh), colH, 3) end
            dl:AddTextFontPtr(font, size, V2(px + 1, hy + 1), colSh, shots_str)
            dl:AddTextFontPtr(font, size, V2(px, hy), colH, shots_str)
            local sz2 = font:CalcTextSizeA(size * 0.55, 1000, 0, ms_str)
            dl:AddTextFontPtr(font, size * 0.55, V2(hx - sz2.x / 2, hy + sz.y + 2), colDim, ms_str)
            if s.show_streak and streak > 0 then
                local st = 'x' .. streak
                local sz3 = font:CalcTextSizeA(size * 0.45, 1000, 0, st)
                dl:AddTextFontPtr(font, size * 0.45, V2(hx - sz3.x / 2, by - sz3.y - 2), colStr, st)
            end
        elseif mode == 4 then
            local info = string.format('%d / %d  |  %.0f ms', shots, s.required_shots, total_ms)
            local sz = font:CalcTextSizeA(size, 1000.0, 0.0, info)
            local px = hx - sz.x / 2
            dl:AddTextFontPtr(font, size, V2(px + 1, hy + 1), colSh, info)
            dl:AddTextFontPtr(font, size, V2(px, hy), colH, info)
            if s.show_streak and streak > 0 then
                local st = 'x' .. streak
                local sz2 = font:CalcTextSizeA(size * 0.4, 1000.0, 0.0, st)
                dl:AddTextFontPtr(font, size * 0.4, V2(hx - sz2.x / 2, hy + sz.y + 2), colStr, st)
            end
        else
            local info = string.format('%d / %d  |  %.0f ms', shots, s.required_shots, total_ms)
            local sz = font:CalcTextSizeA(size, 1000.0, 0.0, info)
            local px = hx - sz.x / 2
            local bw, bh = sz.x, 6
            local bx, by = px, hy - bh - 4
            dl:AddRectFilled(V2(bx, by), V2(bx + bw, by + bh), colBg, 3)
            if progress > 0 then dl:AddRectFilled(V2(bx, by), V2(bx + bw * progress, by + bh), colH, 3) end
            dl:AddTextFontPtr(font, size, V2(px + 1, hy + 1), colSh, info)
            dl:AddTextFontPtr(font, size, V2(px, hy), colH, info)
            if s.show_streak and streak > 0 then
                local st = 'x' .. streak
                local sz2 = font:CalcTextSizeA(size * 0.4, 1000.0, 0.0, st)
                dl:AddTextFontPtr(font, size * 0.4, V2(hx - sz2.x / 2, by - sz2.y - 2), colStr, st)
            end
        end
    end

    local function crdHud()
        CS.positioning = true
        neon.target_main[0] = false
        wait(250)
        while true do
            wait(0)
            sampSetCursorMode(3)
            cfg.settings.hud_x, cfg.settings.hud_y = getCursorPos()
            if isKeyJustPressed(1) then
                sampSetCursorMode(0)
                CS.positioning = false
                save()
                break
            end
        end
        wait(150)
        neon.target_main[0] = true
        Lib.imgui.Process = true
        neon.current_tab = 4
    end

    CBUGSPEED_onSendBulletSync = function(data)
        local s, ss, run = cfg.settings, CS.session, CS.run
        if not (s.active and not ss.blocked) then return end
        if not (data and data.weaponId == 24) then return end
        if run.session_start == 0 then run.session_start = os.clock() end
        run.session_shots = run.session_shots + 1
        if ss.shots == 0 then ss.start_time = os.clock(); ss.active = true end
        ss.shots = ss.shots + 1
        ss.last_shot_time = os.clock()
        if ss.shots >= s.required_shots then
            local final_ms = math.floor((os.clock() - ss.start_time) * 1000)
            local key = tostring(s.required_shots)
            local old = cfg.records[key]
            if not old or final_ms < tonumber(old) then
                cfg.records[key] = final_ms
                save()
                if s.notify_record then
                    local diff = old and (Fn.L(' (лучше на ', ' (better by ') .. (tonumber(old) - final_ms) .. ' ms)') or Fn.L(' (первый рекорд!)', ' (first record!)')
                    pcall(sampAddChatMessage, CBUGER_CP(('{32CD32}[CBug Speed]{FFFFFF} ' .. Fn.L('Рекорд для ', 'Record for ') .. key ..
                        Fn.L(' выстрелов: ', ' shots: ') .. '{32CD32}' .. final_ms .. ' ms{FFFFFF}' .. diff)), -1)
                end
            end
            run.session_combos = run.session_combos + 1
            run.streak = run.streak + 1
            if run.streak > (cfg.stats.best_streak or 0) then cfg.stats.best_streak = run.streak end
            ss.active = false; ss.shots = 0; ss.blocked = true
            lua_thread.create(function()
                wait(s.reset_delay); ss.blocked = false
            end)
        end
    end

    CBUGSPEED_onSendGiveDamage = function(targetId, damage, weapon, bodypart)
        if weapon == 24 and cfg.settings.active then
            CS.run.session_hits = CS.run.session_hits + 1
        end
    end

    function CS.save_stats()
        local st, run = cfg.stats, CS.run
        local session_shots = tonumber(run.session_shots) or 0
        local session_hits = tonumber(run.session_hits) or 0
        st.total_shots = (tonumber(st.total_shots) or 0) + session_shots
        st.total_hits = (tonumber(st.total_hits) or 0) + session_hits
        st.total_misses = (tonumber(st.total_misses) or 0)
            + math.max(0, session_shots - session_hits)
        st.total_combos = (tonumber(st.total_combos) or 0) + (tonumber(run.session_combos) or 0)
        st.total_playtime = (tonumber(st.total_playtime) or 0)
            + (CS.playtime_start > 0 and math.max(0, os.clock() - CS.playtime_start) or 0)
        run.session_shots, run.session_hits, run.session_combos = 0, 0, 0
        CS.playtime_start = os.clock()

        if not save() then
            CS.stats_dirty = true
            return false
        end
        CS.stats_dirty = false
        return true
    end
    Data_cbug_save_stats = function() return CS.save_stats() end
    if not CS.stats_autosave_started then
        CS.stats_autosave_started = true
        lua_thread.create(function()
            while true do
                wait(30000)
                local run = CS.run
                local has_session_data = (run.session_shots or 0) > 0
                    or (run.session_hits or 0) > 0 or (run.session_combos or 0) > 0
                if CS.stats_dirty or has_session_data or (os.clock() - (CS.playtime_start or os.clock())) >= 30 then
                    pcall(CS.save_stats)
                end
            end
        end)
    end

    Fn.drawCbugUI = function(cw)
        local T = Fn.T
        local a = neon.main_alpha
        local s = cfg.settings
        local function gap(n) im.Dummy(V2(0, n)) end
        local function hand() if im.IsItemHovered() then Data.nfn.set_hand_cursor() end end

        local stc = s.active and V4(0.3, 1.0, 0.4, 1.0) or V4(1.0, 0.35, 0.35, 1.0)
        im.TextColored(stc, s.active and T(u8"CBug АКТИВЕН") or T(u8"CBug ВЫКЛЮЧЕН"))
        im.SameLine(); im.TextDisabled(T(u8"(/cbug)"))
        gap(6)

        CS.p_active[0] = s.active
        Data.fixed_toggle_pending_x = Data.ofs_get('tg_cbug_active', 0.0)
        Data.nfn.ios_toggle(T(u8"Трекер активен"), CS.p_active, a)
        if CS.p_active[0] ~= s.active then CS.set_active(CS.p_active[0]) end
        gap(7)

        Data.ofs_row('cp_cbug_hud_col')
        if Data.nfn.CustomColorPicker(T(u8"Цвет HUD"), 'cbug_hud_col', CS.color, true, a) then
            s.text_color_r, s.text_color_g, s.text_color_b, s.text_color_a = CS.color[1], CS.color[2], CS.color[3], CS.color[4]
            save()
        end
        gap(8)

        Data.fixed_slider_pending_x = Data.ofs_get('sl_cbug_required', 0.0)
        Data.nfn.ios_slider(T(u8"Нужно выстрелов"), CS.p_req, 1, 50, a)
        if CS.p_req[0] >= 1 and CS.p_req[0] ~= s.required_shots then s.required_shots = CS.p_req[0]; save() end
        gap(5)
        Data.fixed_slider_pending_x = Data.ofs_get('sl_cbug_scale', 0.0)
        Data.nfn.ios_slider(T(u8"Масштаб HUD"), CS.p_scale, 0.3, 4.0, a, nil, '%.2f')
        if CS.p_scale[0] ~= s.indicator_scale then s.indicator_scale = CS.p_scale[0]; save() end
        gap(5)
        Data.fixed_slider_pending_x = Data.ofs_get('sl_cbug_timeout', 0.0)
        Data.nfn.ios_slider(T(u8"Таймаут сброса (сек)"), CS.p_fail, 0.1, 3.0, a, nil, '%.1f')
        if CS.p_fail[0] ~= s.fail_timeout then s.fail_timeout = CS.p_fail[0]; save() end
        gap(8)

        Data.ofs_row('bt_cbug_hudpos')
        if im.Button(T(u8"Позиция HUD") .. '##cbughudpos', V2(cw - 40, 28)) then
            lua_thread.create(crdHud)
        end
        hand()
        gap(8)

        im.TextDisabled(T(u8"Стиль HUD"))
        local seq = { { 3, T(u8"Мин") }, { 1, T(u8"Базовый") }, { 4, T(u8"Стандарт") }, { 2, T(u8"Расшир") } }
        Data.ofs_row('ch_cbug_hudmode')
        local bw = (cw - 40 - 4 * 3) / 4
        local cb  = Data.neon_active_colors[im.Col.Button]        or { 0.2, 0.2, 0.2, 0.9 }
        local cba = Data.neon_active_colors[im.Col.ButtonActive]  or cb
        local cbh = Data.neon_active_colors[im.Col.ButtonHovered] or cb
        for i, pr in ipairs(seq) do
            if i > 1 then im.SameLine(0, 4) end
            local act = (s.hud_mode == pr[1])
            local c = act and cba or cb
            im.PushStyleColor(im.Col.Button,        V4(c[1], c[2], c[3], c[4] or 0.9))
            im.PushStyleColor(im.Col.ButtonHovered, V4(cbh[1], cbh[2], cbh[3], cbh[4] or 1))
            im.PushStyleColor(im.Col.ButtonActive,  V4(cba[1], cba[2], cba[3], cba[4] or 1))
            if im.Button(pr[2] .. '##cbugmode' .. i, V2(bw, 26)) then s.hud_mode = pr[1]; save() end
            im.PopStyleColor(3)
            hand()
        end
        gap(8)

        CS.p_streak[0] = s.show_streak and true or false
        Data.fixed_toggle_pending_x = Data.ofs_get('tg_cbug_streak', 0.0)
        Data.nfn.ios_toggle(T(u8"Стрик на HUD"), CS.p_streak, a)
        if CS.p_streak[0] ~= s.show_streak then s.show_streak = CS.p_streak[0]; save() end
        gap(7)
        CS.p_notify[0] = s.notify_record and true or false
        Data.fixed_toggle_pending_x = Data.ofs_get('tg_cbug_notify', 0.0)
        Data.nfn.ios_toggle(T(u8"Уведомление о рекорде"), CS.p_notify, a)
        if CS.p_notify[0] ~= s.notify_record then s.notify_record = CS.p_notify[0]; save() end
        gap(8)

        im.TextDisabled(T(u8"Рекорды CBug"))
        local has = false
        local keys = {}
        for k in pairs(cfg.records) do keys[#keys + 1] = k end
        table.sort(keys, function(x, y) return (tonumber(x) or 0) < (tonumber(y) or 0) end)
        for _, k in ipairs(keys) do
            has = true
            im.TextColored(V4(0.2, 0.9, 0.2, 1), T(u8"Выстрелов: ") .. tostring(k) .. T(u8" | Время: ") ..
                tostring(tonumber(cfg.records[k]) or cfg.records[k]) .. ' ms')
        end
        if not has then im.TextDisabled(T(u8"Рекордов нет")) end
        gap(6)
        Data.ofs_row('bt_cbug_clear')
        if im.Button(T(u8"Очистить рекорды") .. '##cbugclr', V2(cw - 40, 28)) then
            cfg.records = {}; save()
        end
        hand()
        gap(16)
    end

    do
        local tr = {
            ["Cbug Speed"] = "Cbug Speed",
            ["CBug АКТИВЕН"] = "CBug ACTIVE", ["CBug ВЫКЛЮЧЕН"] = "CBug OFF",
            ["Трекер активен"] = "Tracker active",
            ["Цвет HUD"] = "HUD color", ["Нужно выстрелов"] = "Required shots", ["Масштаб HUD"] = "HUD scale",
            ["Таймаут сброса (сек)"] = "Reset timeout (s)", ["Позиция HUD"] = "HUD position",
            ["Стиль HUD"] = "HUD style", ["Мин"] = "Min", ["Базовый"] = "Basic", ["Стандарт"] = "Standard",
            ["Расшир"] = "Extended", ["Стрик на HUD"] = "Streak on HUD",
            ["Уведомление о рекорде"] = "Record notification", ["Рекорды CBug"] = "CBug records",
            ["Выстрелов: "] = "Shots: ", [" | Время: "] = " | Time: ", ["Рекордов нет"] = "No records",
            ["Очистить рекорды"] = "Clear records",
        }
        for k, val in pairs(tr) do Data.UI_TRANSLATIONS[Fn.decodeSafe(u8(k))] = val end
    end

    local cs_render = Lib.imgui.OnFrame(function() return cfg.settings.active or CS.positioning end, function(self)
        self.HideCursor = true
        drawHud()
    end)
    cs_render.HideCursor = true
    cs_render.ShowCursor = false
    Data_cbug_register = function()
        pcall(sampRegisterChatCommand, 'cbug', function(args)
            CS.set_active(not cfg.settings.active)
        end)
    end
end

do




    local B = {}
    Data.board = B
    local im = Lib.imgui
    local V2, V4 = im.ImVec2, im.ImVec4
    local CFG_NAME = 'cbuger_board'
    local INSET = 0.92
    local FX_TIME = 0.18
    local FAIL_WHITE = 0.1
    local FAIL_RED   = 0.9
    local FAIL_TOTAL = FAIL_WHITE + FAIL_RED


    local reaction_seed = ((os.time() or 1) * 1000 + math.floor((os.clock() or 0) * 1000000)) % 2147483647
    if reaction_seed <= 0 then reaction_seed = 1 end
    local function reaction_random(lo, hi)
        reaction_seed = (reaction_seed * 48271) % 2147483647
        return lo + (reaction_seed % (hi - lo + 1))
    end

    local default = {
        settings = {
            active = false, grid = 3, tiles = 1, cell_size = 0.6, board_alpha = 0.45,
            ui_buttons_y = 0.0, ui_sliders_y = 0.0, ui_bottom_gap = 8.0,
            checker = true, reaction_mode = false, pause_reload = true, reload_pause = 2.0, hud_scale = 1.0,
            tile_r = 0.02, tile_g = 0.02, tile_b = 0.02, tile_a = 1.0,
            light_r = 0.88, light_g = 0.88, light_b = 0.88, light_a = 1.0,
            dark_r = 0.45, dark_g = 0.45, dark_b = 0.45, dark_a = 1.0,
            cr_enabled = true, cr_size = 10, cr_gap = 4, cr_thick = 2,
            cr_outline = true, cr_outline_px = 2, cr_dot = false, cr_dot_size = 2,
            cr_r = 1.0, cr_g = 1.0, cr_b = 1.0, cr_a = 1.0, cr_off_x = 0, cr_off_y = 0,
        },
        records = { best_hits = 0, best_speed = 0.0, best_ms = 0, games = 0,
            reaction_total_ms = 0, reaction_total_hits = 0, reaction_avg_ms = 0, best_reaction_ms = 0 },
    }
    local cfg = Lib.inicfg.load(default, CFG_NAME)
    if type(cfg) ~= 'table' then cfg = default end
    cfg.settings = (type(cfg.settings) == 'table') and cfg.settings or {}
    cfg.records  = (type(cfg.records) == 'table') and cfg.records or {}
    B.cfg = cfg
    local s = cfg.settings
    local rec = cfg.records



    local function save()
        local ok, result = pcall(Lib.inicfg.save, cfg, CFG_NAME)
        return ok and result == true
    end
    B.save = save

    local function clampn(x, a, b) if x < a then return a elseif x > b then return b end return x end
    local function set_normalized(tbl, key, value)
        if tbl[key] ~= value then tbl[key] = value end
    end
    local function finite_number(value, fallback)
        local n = tonumber(value)
        if n == nil or n ~= n or n == math.huge or n == -math.huge then return fallback end
        return n
    end
    local function normalize_number(tbl, key, fallback, lo, hi, integer)
        local n = finite_number(tbl[key], fallback)
        if lo ~= nil and hi ~= nil then n = clampn(n, lo, hi) end
        if integer then n = math.floor(n + 0.5) end
        set_normalized(tbl, key, n)
    end
    local function normalize_boolean(tbl, key, fallback)
        local value = tbl[key]
        if type(value) ~= 'boolean' then value = fallback end
        set_normalized(tbl, key, value)
    end


    for k, v in pairs(default.settings) do
        if s[k] == nil then set_normalized(s, k, v) end
    end
    for k, v in pairs(default.records) do
        if rec[k] == nil then set_normalized(rec, k, v) end
    end


    normalize_number(s, 'grid', 3, 1, 8, true)
    normalize_number(s, 'tiles', 1, 1, 6, true)
    normalize_number(s, 'cell_size', 0.6, 0.1, 3.0)
    normalize_number(s, 'board_alpha', 0.45, 0.0, 1.0)
    normalize_number(s, 'ui_buttons_y', 0.0, -150.0, 150.0)
    normalize_number(s, 'ui_sliders_y', 0.0, -150.0, 150.0)
    normalize_number(s, 'ui_bottom_gap', 8.0, 0.0, 80.0)
    normalize_number(s, 'reload_pause', 2.0, 0.1, 10.0)
    normalize_number(s, 'hud_scale', 1.0, 0.5, 3.0)
    normalize_number(s, 'cr_size', 10, 2, 30, true)
    normalize_number(s, 'cr_gap', 4, 0, 15, true)
    normalize_number(s, 'cr_thick', 2, 1, 8, true)
    normalize_number(s, 'cr_outline_px', 2, 1, 6, true)
    normalize_number(s, 'cr_dot_size', 2, 1, 10, true)
    normalize_number(s, 'cr_off_x', 0, -10000, 10000, true)
    normalize_number(s, 'cr_off_y', 0, -10000, 10000, true)
    for _, key in ipairs({'tile_r','tile_g','tile_b','tile_a', 'light_r','light_g','light_b','light_a',
                          'dark_r','dark_g','dark_b','dark_a', 'cr_r','cr_g','cr_b','cr_a'}) do
        normalize_number(s, key, default.settings[key] or 1.0, 0.0, 1.0)
    end
    normalize_boolean(s, 'checker', true)
    normalize_boolean(s, 'reaction_mode', false)
    normalize_boolean(s, 'pause_reload', true)

    normalize_number(rec, 'best_hits', 0, 0, 2147483647, true)
    normalize_number(rec, 'best_speed', 0.0, 0.0, 1000000.0)
    normalize_number(rec, 'best_ms', 0, 0, 2147483647, true)
    normalize_number(rec, 'games', 0, 0, 2147483647, true)
    normalize_number(rec, 'reaction_total_ms', 0, 0, 2147483647, true)
    normalize_number(rec, 'reaction_total_hits', 0, 0, 2147483647, true)
    normalize_number(rec, 'reaction_avg_ms', 0, 0, 2147483647, true)
    normalize_number(rec, 'best_reaction_ms', 0, 0, 2147483647, true)


    set_normalized(s, 'cr_enabled', true)
    set_normalized(s, 'cr_size', 10)
    set_normalized(s, 'cr_gap', 4)
    set_normalized(s, 'cr_thick', 2)
    set_normalized(s, 'cr_outline', true)
    set_normalized(s, 'cr_outline_px', 2)
    set_normalized(s, 'cr_dot', false)


    set_normalized(s, 'active', false)




    save()

    local function grid_dims(n)
        n = math.max(1, math.floor(tonumber(n) or 1))
        if n == 1 then return 2, 1 end
        return n, n
    end
    B.p_active  = Lib.new.bool(false)
    B.p_grid    = Lib.new.int(s.grid)
    B.p_tiles   = Lib.new.int(s.tiles)
    B.p_cell    = Lib.new.float(s.cell_size)
    B.p_alpha   = Lib.new.float(s.board_alpha)
    B.p_checker  = Lib.new.bool(s.checker and true or false)
    B.p_reaction = Lib.new.bool(s.reaction_mode and true or false)
    B.p_pause    = Lib.new.bool(s.pause_reload and true or false)
    B.p_pdur    = Lib.new.float(s.reload_pause)
    B.p_hud     = Lib.new.float(s.hud_scale)
    B.p_cr_en   = Lib.new.bool(s.cr_enabled and true or false)
    B.p_cr_size = Lib.new.int(s.cr_size)
    B.p_cr_gap  = Lib.new.int(s.cr_gap)
    B.p_cr_th   = Lib.new.int(s.cr_thick)
    B.p_cr_out  = Lib.new.bool(s.cr_outline and true or false)
    B.p_cr_opx  = Lib.new.int(s.cr_outline_px)
    B.p_cr_dot  = Lib.new.bool(s.cr_dot and true or false)
    B.cr_col    = { s.cr_r, s.cr_g, s.cr_b, s.cr_a }
    B.tile_col  = { s.tile_r,  s.tile_g,  s.tile_b,  s.tile_a }
    B.light_col = { s.light_r, s.light_g, s.light_b, s.light_a }
    B.dark_col  = { s.dark_r,  s.dark_g,  s.dark_b,  s.dark_a }


    local G = { phase = 'idle', board = nil, tiles = {}, fx = {}, hits = 0,
                t0 = 0, paused = false, pause_t0 = 0, paused_total = 0,
                end_active = 0, over_t = 0, fail_t = 0, hud_o = nil, sum_ms = 0, last_ms = 0, new_record = false,
                prev_clip = -1, prev_wid = -1 }
    B.G = G

    local function reset_game()
        G.phase = 'idle'; G.board = nil; G.tiles = {}; G.fx = {}; G.hits = 0
        G.t0 = 0; G.paused = false; G.pause_t0 = 0; G.paused_total = 0
        G.end_active = 0; G.over_t = 0; G.fail_t = 0; G.hud_o = nil; G.sum_ms = 0; G.last_ms = 0; G.new_record = false
        G.prev_clip = -1; G.prev_wid = -1
        G.reaction_state = 'idle'; G.reaction_wait_until = 0
        G.reaction_target = nil; G.reaction_visible_at = 0
        G.reaction_fail_target = nil
    end
    B.reset = reset_game


    local HUD_CR_ADDR = 0x58E020
    local native_hidden = false
    local function setGtaCrosshairVisible(on)
        pcall(memory.setuint8, HUD_CR_ADDR, on and 0x83 or 0xC3, true)
        native_hidden = not on
    end
    local locked_x, locked_y = nil, nil
    B.dragging = false

    function B.set_active(on)
        s.active = on and true or false
        B.p_active[0] = s.active
        reset_game()
        locked_x, locked_y = nil, nil
        if not s.active then setGtaCrosshairVisible(true) end
        save()
        CBUGER_ModeMsg('board', s.active)
    end
    function B.set_reaction_mode(on)
        local enabled = on and true or false
        if enabled == (s.reaction_mode and true or false) then return end
        s.reaction_mode = enabled
        B.p_reaction[0] = enabled
        reset_game()
        locked_x, locked_y = nil, nil
        save()
    end
    function B.restore_native()
        if native_hidden then setGtaCrosshairVisible(true) end
    end

    function B.reset_records()
        rec.best_hits = 0; rec.best_speed = 0.0; rec.best_ms = 0; rec.games = 0
        rec.reaction_total_ms = 0; rec.reaction_total_hits = 0
        rec.reaction_avg_ms = 0; rec.best_reaction_ms = 0
        save()
    end

    local function norm(x, y, z)
        local l = math.sqrt(x * x + y * y + z * z)
        if l < 1e-9 then return 0, 0, 1 end
        return x / l, y / l, z / l
    end
    local function cross(ax, ay, az, bx, by, bz)
        return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    end

    local function elapsed(now)
        if G.phase == 'over' or G.phase == 'fail' then return G.end_active end
        if G.phase ~= 'run' then return 0 end
        local e = now - G.t0 - G.paused_total
        if G.paused then e = e - (now - G.pause_t0) end
        return math.max(0, e)
    end

    local function spawn_tile(avoid_i, avoid_j)
        local b = G.board
        if not b then return end
        local occ = {}
        for _, t in ipairs(G.tiles) do occ[t.i * 100 + t.j] = true end
        local free, free2 = {}, {}
        local bw, bh = b.W or b.N, b.H or b.N
        for i = 0, bw - 1 do
            for j = 0, bh - 1 do
                if not occ[i * 100 + j] then
                    free2[#free2 + 1] = { i, j }
                    if not (i == avoid_i and j == avoid_j) then free[#free + 1] = { i, j } end
                end
            end
        end
        local pool = (#free > 0) and free or free2
        if #pool == 0 then return end
        local c = pool[math.random(1, #pool)]
        G.tiles[#G.tiles + 1] = { i = c[1], j = c[2], t = os.clock() }
    end

    local function fill_tiles(avoid_i, avoid_j)
        local b = G.board
        if not b then return end
        local bw, bh = b.W or b.N, b.H or b.N
        local want = math.min(s.tiles, math.max(1, bw * bh - 1))
        while #G.tiles < want do
            local before = #G.tiles
            spawn_tile(avoid_i, avoid_j)
            if #G.tiles == before then break end
        end
    end

    local function schedule_reaction(now)
        G.reaction_state = 'waiting'
        G.reaction_target = nil
        G.reaction_fail_target = nil
        G.reaction_visible_at = 0

        G.reaction_wait_until = (tonumber(now) or os.clock()) + reaction_random(1000, 5000) / 1000
    end

    local function start_game(tx, ty, tz)
        local cx, cy, cz = getActiveCameraCoordinates()
        local nx, ny, nz = norm(cx - tx, cy - ty, cz - tz)
        local ux, uy, uz = 0, 0, 1
        if math.abs(nz) > 0.98 then ux, uy, uz = 0, 1, 0 end
        local rx, ry, rz = cross(ux, uy, uz, nx, ny, nz)
        rx, ry, rz = norm(rx, ry, rz)
        local vx, vy, vz = cross(nx, ny, nz, rx, ry, rz)
        local board_w, board_h = grid_dims(s.grid)
        G.board = {
            o = { x = tx, y = ty, z = tz }, n = { x = nx, y = ny, z = nz },
            r = { x = rx, y = ry, z = rz }, u = { x = vx, y = vy, z = vz },
            N = s.grid, W = board_w, H = board_h, cs = s.cell_size,
        }
        do
            local hh = G.board.H * G.board.cs * 0.5 + G.board.cs * 0.25
            G.hud_o = { x = tx + vx * hh, y = ty + vy * hh, z = tz + vz * hh }
        end
        G.tiles = {}; G.fx = {}; G.hits = 0; G.sum_ms = 0; G.last_ms = 0
        G.paused = false; G.paused_total = 0; G.new_record = false
        G.phase = 'run'; G.t0 = os.clock()
        G.prev_clip = -1; G.prev_wid = -1
        if s.reaction_mode then
            schedule_reaction(G.t0)
        else
            G.reaction_state = 'idle'
            G.reaction_target = nil
            G.reaction_fail_target = nil
            fill_tiles(-1, -1)
        end
    end


    local function apply_live()
        local b = G.board
        if not b then return end
        b.N, b.cs = s.grid, s.cell_size
        b.W, b.H = grid_dims(s.grid)
        local hh = b.H * b.cs * 0.5 + b.cs * 0.25
        G.hud_o = { x = b.o.x + b.u.x * hh, y = b.o.y + b.u.y * hh, z = b.o.z + b.u.z * hh }
        for k = #G.tiles, 1, -1 do
            local t = G.tiles[k]
            if t.i >= b.W or t.j >= b.H then table.remove(G.tiles, k) end
        end
        if G.phase == 'run' then
            if s.reaction_mode then
                G.tiles = {}
                schedule_reaction(os.clock())
            else
                local want = math.min(s.tiles, math.max(1, b.W * b.H - 1))
                while #G.tiles > want do table.remove(G.tiles) end
                fill_tiles(-1, -1)
            end
        end
    end
    B.apply_live = apply_live

    local function finish_game(now)
        G.end_active = elapsed(now)
        G.phase = 'fail'; G.fail_t = now
        rec.games = (tonumber(rec.games) or 0) + 1
        local el = G.end_active
        if G.hits > (tonumber(rec.best_hits) or 0) then rec.best_hits = G.hits; G.new_record = true end

        if not s.reaction_mode and G.hits >= 3 and el > 0.05 then
            local sp = G.hits / el
            if sp > (tonumber(rec.best_speed) or 0) then
                rec.best_speed = sp; G.new_record = true
            end
            local avg = math.floor(G.sum_ms / G.hits)
            if (tonumber(rec.best_ms) or 0) == 0 or avg < tonumber(rec.best_ms) then rec.best_ms = avg end
        end
        save()
    end


    local function shot_uv(tg)
        local b = G.board
        local cx, cy, cz = getActiveCameraCoordinates()
        local dx, dy, dz = tg.x - cx, tg.y - cy, tg.z - cz
        local dn = dx * b.n.x + dy * b.n.y + dz * b.n.z
        if math.abs(dn) < 1e-6 then return nil end
        local t = ((b.o.x - cx) * b.n.x + (b.o.y - cy) * b.n.y + (b.o.z - cz) * b.n.z) / dn
        if t <= 0 then return nil end
        local px, py, pz = cx + dx * t - b.o.x, cy + dy * t - b.o.y, cz + dz * t - b.o.z
        return px * b.r.x + py * b.r.y + pz * b.r.z, px * b.u.x + py * b.u.y + pz * b.u.z
    end

    CBUGER_BOARD_onSendBulletSync = function(data)
        if not s.active or not data or not data.target then return end
        if type(data.weaponId) == 'number' and data.weaponId >= 0 and data.weaponId <= 9 then return end
        local tg = data.target
        local now = os.clock()
        if G.phase == 'idle' or (G.phase == 'over' and now - G.over_t > 0.15) then
            start_game(tg.x, tg.y, tg.z)
            return
        end
        if G.phase ~= 'run' or G.paused then return end
        local b = G.board
        local u, v = shot_uv(tg)

        if s.reaction_mode then


            if G.reaction_state ~= 'visible' or not G.reaction_target then return end
            local rt = G.reaction_target
            local cu = (rt.i - ((b.W or b.N) - 1) / 2) * b.cs
            local cv = (rt.j - ((b.H or b.N) - 1) / 2) * b.cs
            local half = b.cs * 0.5 * INSET
            local correct = u ~= nil and v ~= nil
                and math.abs(u - cu) <= half and math.abs(v - cv) <= half
            if correct then
                G.hits = G.hits + 1
                G.last_ms = math.max(0, math.floor((now - G.reaction_visible_at) * 1000 + 0.5))
                G.sum_ms = G.sum_ms + G.last_ms
                rec.reaction_total_ms = (tonumber(rec.reaction_total_ms) or 0) + G.last_ms
                rec.reaction_total_hits = (tonumber(rec.reaction_total_hits) or 0) + 1
                rec.reaction_avg_ms = math.floor(rec.reaction_total_ms / math.max(1, rec.reaction_total_hits))
                if (tonumber(rec.best_reaction_ms) or 0) == 0
                    or G.last_ms < tonumber(rec.best_reaction_ms) then
                    rec.best_reaction_ms = G.last_ms
                    G.new_record = true
                end
                save()
                G.fx[#G.fx + 1] = { i = rt.i, j = rt.j, t = now }
                schedule_reaction(now)
            else
                G.reaction_fail_target = { i = rt.i, j = rt.j }
                G.reaction_state = 'failed'
                finish_game(now)
            end
            return
        end

        local hitIdx
        if u then
            local half = b.cs * 0.5 * INSET
            for idx, t in ipairs(G.tiles) do
                local cu = (t.i - ((b.W or b.N) - 1) / 2) * b.cs
                local cv = (t.j - ((b.H or b.N) - 1) / 2) * b.cs
                if math.abs(u - cu) <= half and math.abs(v - cv) <= half then hitIdx = idx; break end
            end
        end
        if hitIdx then
            local t = table.remove(G.tiles, hitIdx)
            G.hits = G.hits + 1
            G.last_ms = math.floor((now - t.t) * 1000)
            G.sum_ms = G.sum_ms + G.last_ms
            G.fx[#G.fx + 1] = { i = t.i, j = t.j, t = now }
            fill_tiles(t.i, t.j)
        else
            finish_game(now)
        end
    end


    local function poll_reload(now)
        if G.phase ~= 'run' then return end
        if not s.pause_reload then G.paused = false; return end
        local curClip = -1
        pcall(function()
            local wid = getCurrentCharWeapon(playerPed)
            if wid ~= G.prev_wid then G.prev_wid = wid; G.prev_clip = -1 end
            if not wid or wid <= 9 then return end
            local ptr = getCharPointer(playerPed)
            if not ptr or ptr == 0 then return end
            local slot = getWeapontypeSlot(wid)
            curClip = memory.getuint32(ptr + 0x5A0 + slot * 0x1C + 0x8)
        end)
        if curClip >= 0 then
            if not G.paused and G.prev_clip > 0 and curClip == 0 then
                G.paused = true; G.pause_t0 = now
            end
            G.prev_clip = curClip
        end
        if G.paused and now - G.pause_t0 >= s.reload_pause then
            local delta = now - G.pause_t0
            for _, t in ipairs(G.tiles) do t.t = t.t + delta end
            if s.reaction_mode then
                if G.reaction_state == 'waiting' then
                    G.reaction_wait_until = G.reaction_wait_until + delta
                elseif G.reaction_state == 'visible' then
                    G.reaction_visible_at = G.reaction_visible_at + delta
                end
            end
            G.paused_total = G.paused_total + delta
            G.paused = false
        end
    end


    local function U32(c) return CBUGER_ApplyOverlayAlphaU32(im.ColorConvertFloat4ToU32(c)) end

    local function proj(x, y, z)
        local ok, vis, sx, sy, sz = pcall(convert3DCoordsToScreenEx, x, y, z, false, false)
        if ok and vis and sz and sz > 0 then return sx, sy end
        return nil
    end

    local function cell_pts(b, i, j, scale)
        local cu = (i - ((b.W or b.N) - 1) / 2) * b.cs
        local cv = (j - ((b.H or b.N) - 1) / 2) * b.cs
        local h = b.cs * 0.5 * scale
        local pts = {}
        local cs4 = { { -h, -h }, { h, -h }, { h, h }, { -h, h } }
        for k = 1, 4 do
            local u, v = cu + cs4[k][1], cv + cs4[k][2]
            local x = b.o.x + b.r.x * u + b.u.x * v
            local y = b.o.y + b.r.y * u + b.u.y * v
            local z = b.o.z + b.r.z * u + b.u.z * v
            local sx, sy = proj(x, y, z)
            if not sx then return nil end
            pts[k] = V2(sx, sy)
        end
        return pts
    end

    local function drawCrossAt(DL, px, py, arm, gap, thick, col, ocol, outline_px, dot_sz, dcol)
        local half = thick * 0.5
        if outline_px and outline_px > 0 then
            local oth = outline_px
            DL:AddRectFilled(V2(px - half - oth, py - gap - arm - oth), V2(px + half + oth, py - gap), ocol)
            DL:AddRectFilled(V2(px - half - oth, py + gap), V2(px + half + oth, py + gap + arm + oth), ocol)
            DL:AddRectFilled(V2(px - gap - arm - oth, py - half - oth), V2(px - gap, py + half + oth), ocol)
            DL:AddRectFilled(V2(px + gap, py - half - oth), V2(px + gap + arm + oth, py + half + oth), ocol)
        end
        DL:AddRectFilled(V2(px - half, py - gap - arm), V2(px + half, py - gap), col)
        DL:AddRectFilled(V2(px - half, py + gap), V2(px + half, py + gap + arm), col)
        DL:AddRectFilled(V2(px - gap - arm, py - half), V2(px - gap, py + half), col)
        DL:AddRectFilled(V2(px + gap, py - half), V2(px + gap + arm, py + half), col)
        if dot_sz and dot_sz > 0 then DL:AddCircleFilled(V2(px, py), dot_sz, dcol, 16) end
    end

    local function gtaCrosshairScreenPos()
        if not CBUGER_NATIVE_READY then return nil end
        local ok, wx, wy, wz = pcall(function()
            local vec_out = ffi.new("float[3]")
            local tmp_vec = ffi.new("float[3]")
            ffi.cast("void (__thiscall*)(void*, float, float, float, float, float*, float*)", 0x514970)(
                ffi.cast("void*", 0xB6F028), 500.0, tmp_vec[0], tmp_vec[1], tmp_vec[2], tmp_vec, vec_out)
            return vec_out[0], vec_out[1], vec_out[2]
        end)
        if not ok or type(wx) ~= 'number' or wx ~= wx or wy ~= wy or wz ~= wz then return nil end
        local ok2, vis, sx, sy = pcall(convert3DCoordsToScreenEx, wx, wy, wz, false, false)
        if ok2 and vis and sx and sy then return sx, sy end
        return nil
    end

    local function crosshairBasePos(sw, sh)
        if not locked_x or not locked_y then
            local sx, sy = gtaCrosshairScreenPos()
            if sx and sy and sx > 0 and sx < sw and sy > 0 and sy < sh then
                locked_x, locked_y = sx, sy
            else
                return sw * 0.5, sh * 0.5
            end
        end
        return locked_x, locked_y
    end

    local function drawCrosshair()
        local sw, sh = getScreenResolution()
        local bx, by = crosshairBasePos(sw, sh)
        local cc = B.cr_col
        local DL = im.GetForegroundDrawList()
        local col  = U32(V4(cc[1], cc[2], cc[3], cc[4]))
        local ocol = U32(V4(0.02, 0.03, 0.05, 1.0))
        local oth = s.cr_outline and math.max(1, s.cr_outline_px) or 0
        local dsz = s.cr_dot and math.max(1, s.cr_dot_size) or 0
        drawCrossAt(DL, bx + s.cr_off_x, by + s.cr_off_y, s.cr_size, s.cr_gap, s.cr_thick, col, ocol, oth, dsz, col)
    end

    local function moveCrosshair()
        B.dragging = true
        local tab = neon.current_tab
        local ox, oy = s.cr_off_x, s.cr_off_y
        neon.target_main[0] = false
        wait(250)
        while true do
            wait(0)
            sampSetCursorMode(3)
            local mx, my = getCursorPos()
            local sw, sh = getScreenResolution()
            local bx, by = crosshairBasePos(sw, sh)
            if mx and my then s.cr_off_x, s.cr_off_y = math.floor(mx - bx), math.floor(my - by) end
            if isKeyJustPressed(1) then
                save(); break
            elseif isKeyJustPressed(2) then
                s.cr_off_x, s.cr_off_y = ox, oy; break
            end
        end
        sampSetCursorMode(0)
        B.dragging = false
        wait(150)
        neon.target_main[0] = true
        Lib.imgui.Process = true
        neon.current_tab = tab
    end

    local function drawText(DL, font, size, x, y, text, col)
        local tsz = font:CalcTextSizeA(size, 10000.0, 0.0, text)
        local px = x - tsz.x / 2
        DL:AddTextFontPtr(font, size, V2(px + 1, y + 1), U32(V4(0, 0, 0, 0.9)), text)
        DL:AddTextFontPtr(font, size, V2(px, y), col, text)
        return tsz.y
    end

    local function drawHud(DL, now)
        local font = (CBUGER_GET_GLOBAL_FONT and CBUGER_GET_GLOBAL_FONT()) or im.GetFont()
        if not font then return end
        local T = Fn.T
        local size = 20 * s.hud_scale
        local lines = {}
        local white = U32(V4(1, 1, 1, 1))
        local red   = U32(V4(1.0, 0.3, 0.3, 1))
        local gold  = U32(V4(1.0, 0.82, 0.2, 1))
        local green = U32(V4(0.35, 1.0, 0.45, 1))
        local el = elapsed(now)
        if G.phase == 'idle' then
            lines[1] = { T(u8"Доска: выстрелите, чтобы разместить её") .. " (" .. s.grid .. "x" .. s.grid .. ")", white }
        else
            if s.reaction_mode then
                if G.reaction_state == 'waiting' then
                    lines[#lines + 1] = { T(u8"Ожидание сигнала..."), white }
                elseif G.reaction_state == 'visible' then
                    lines[#lines + 1] = { T(u8"ЦЕЛЬ!"), green }
                end
                lines[#lines + 1] = { T(u8"Попаданий: ") .. G.hits, white }
                if G.hits > 0 then
                    lines[#lines + 1] = { T(u8"Реакция: ") .. tostring(G.last_ms) .. T(u8" мс"), green }
                    lines[#lines + 1] = { T(u8"Средняя реакция: ") .. tostring(math.floor(G.sum_ms / G.hits)) .. T(u8" мс"), white }
                end
                if G.phase == 'fail' or G.phase == 'over' then
                    lines[#lines + 1] = { T(u8"ПРОМАХ!"), red }
                    if G.new_record then lines[#lines + 1] = { T(u8"НОВЫЙ РЕКОРД!"), gold } end
                    if G.phase == 'over' then lines[#lines + 1] = { T(u8"Выстрелите, чтобы начать заново"), white } end
                end
            else
                if G.phase == 'over' or G.phase == 'fail' then
                    lines[#lines + 1] = { T(u8"ПРОМАХ!"), red }
                end
                lines[#lines + 1] = { T(u8"Попаданий: ") .. G.hits, white }
                local sp = (el > 0.05) and (G.hits / el) or 0
                local avg = (G.hits > 0) and math.floor(G.sum_ms / G.hits) or 0
                lines[#lines + 1] = { string.format("%s%.2f%s  %s%d%s  %s%.2f%s",
                    T(u8"Скорость: "), sp, T(u8" /с"), T(u8"Сред.: "), avg, T(u8" мс"), T(u8"Время: "), el, T(u8" с")), green }
                if G.phase == 'run' and G.paused then
                    lines[#lines + 1] = { string.format("%s %.1f", T(u8"ПАУЗА (перезарядка)"),
                        math.max(0, s.reload_pause - (now - G.pause_t0))), gold }
                end
                if G.phase == 'over' or G.phase == 'fail' then
                    if G.new_record then lines[#lines + 1] = { T(u8"НОВЫЙ РЕКОРД!"), gold } end
                    lines[#lines + 1] = { T(u8"Рекорд: ") .. (tonumber(rec.best_hits) or 0), gold }
                    if G.phase == 'over' then lines[#lines + 1] = { T(u8"Выстрелите, чтобы начать заново"), white } end
                end
            end
        end
        local lh = size * 1.15
        local sw, sh = getScreenResolution()
        local ax, ay
        local ho = G.hud_o
        if ho then
            local px, py = proj(ho.x, ho.y, ho.z)
            if px then ax, ay = px, py - lh * #lines end
        end
        if not ax then ax, ay = sw / 2, sh * 0.15 end
        ay = clampn(ay, 5, sh - lh * #lines - 5)
        for _, ln in ipairs(lines) do
            drawText(DL, font, size, ax, ay, ln[1], ln[2])
            ay = ay + lh
        end
    end

    local function drawBoard()
        if type(isPauseMenuActive) == 'function' and isPauseMenuActive() then return end
        local now = os.clock()
        if (s.active and s.cr_enabled) or B.dragging then
            if s.active and not native_hidden then setGtaCrosshairVisible(false) end
            drawCrosshair()
        elseif native_hidden then
            setGtaCrosshairVisible(true)
        end
        poll_reload(now)
        if s.reaction_mode and G.phase == 'run' and not G.paused
            and G.reaction_state == 'waiting' and now >= (G.reaction_wait_until or 0) then
            local board = G.board
            if board then
                G.reaction_target = {
                    i = reaction_random(0, (board.W or board.N) - 1),
                    j = reaction_random(0, (board.H or board.N) - 1),
                }
                G.reaction_visible_at = now
                G.reaction_state = 'visible'
            end
        end
        local DL = im.GetBackgroundDrawList()
        if G.phase == 'fail' and now - G.fail_t >= FAIL_TOTAL then

            G.phase = 'over'; G.over_t = now
            G.board = nil; G.tiles = {}; G.fx = {}
            G.reaction_target = nil; G.reaction_fail_target = nil; G.reaction_state = 'idle'
        end
        local b = G.board
        if b then
            local al = s.board_alpha
            local lc, dc, tc = B.light_col, B.dark_col, B.tile_col
            local bw, bh = b.W or b.N, b.H or b.N
            for i = 0, bw - 1 do
                for j = 0, bh - 1 do
                    local p = cell_pts(b, i, j, 1.0)
                    if p then
                        if s.checker then
                            local c = ((i + j) % 2 == 0) and lc or dc
                            DL:AddQuadFilled(p[1], p[2], p[3], p[4], U32(V4(c[1], c[2], c[3], (c[4] or 1) * al)))
                        else
                            DL:AddQuad(p[1], p[2], p[3], p[4], U32(V4(lc[1], lc[2], lc[3], math.max(0.25, al))), 1.0)
                        end
                    end
                end
            end
            for k = #G.fx, 1, -1 do
                local f = G.fx[k]
                local age = now - f.t
                if age >= FX_TIME then
                    table.remove(G.fx, k)
                else
                    local p = cell_pts(b, f.i, f.j, INSET * (1 - 0.35 * age / FX_TIME))
                    if p then
                        DL:AddQuadFilled(p[1], p[2], p[3], p[4], U32(V4(tc[1], tc[2], tc[3], (1 - age / FX_TIME) * (tc[4] or 1))))
                    end
                end
            end
            local tr_, tg_, tb_, ta_ = tc[1], tc[2], tc[3], (tc[4] or 1)
            if G.phase == 'fail' then

                if now - G.fail_t < FAIL_WHITE then tr_, tg_, tb_, ta_ = 1, 1, 1, 1
                else tr_, tg_, tb_, ta_ = 1, 0, 0, 1 end
            end
            for _, t in ipairs(G.tiles) do
                local p = cell_pts(b, t.i, t.j, INSET)
                if p then
                    DL:AddQuadFilled(p[1], p[2], p[3], p[4], U32(V4(tr_, tg_, tb_, ta_)))
                end
            end
            if s.reaction_mode and G.reaction_state == 'visible' and G.reaction_target then
                local rt = G.reaction_target
                local p = cell_pts(b, rt.i, rt.j, INSET)
                if p then
                    DL:AddQuadFilled(p[1], p[2], p[3], p[4], U32(V4(0.12, 1.0, 0.22, 0.98)))
                    DL:AddQuad(p[1], p[2], p[3], p[4], U32(V4(0.02, 0.28, 0.06, 1.0)), 2.0)
                end
            elseif s.reaction_mode and G.phase == 'fail' and G.reaction_fail_target then
                local rt = G.reaction_fail_target
                local p = cell_pts(b, rt.i, rt.j, INSET)
                if p then
                    local blink_on = (math.floor((now - G.fail_t) / 0.12) % 2) == 0
                    local fill = blink_on and V4(1.0, 0.035, 0.035, 0.98) or V4(0.38, 0.0, 0.0, 0.35)
                    DL:AddQuadFilled(p[1], p[2], p[3], p[4], U32(fill))
                    DL:AddQuad(p[1], p[2], p[3], p[4], U32(V4(0.35, 0.0, 0.0, 1.0)), 2.0)
                end
            end
            local fr = V4(1, 1, 1, 0.5)
            local c1 = cell_pts(b, 0, 0, 1.0)
            local c2 = cell_pts(b, (b.W or b.N) - 1, (b.H or b.N) - 1, 1.0)
            if c1 and c2 then
                DL:AddRect(V2(math.min(c1[1].x, c2[1].x, c1[3].x, c2[3].x), math.min(c1[1].y, c2[1].y, c1[3].y, c2[3].y)),
                           V2(math.max(c1[1].x, c2[1].x, c1[3].x, c2[3].x), math.max(c1[1].y, c2[1].y, c1[3].y, c2[3].y)),
                           U32(fr), 0.0, 0, 1.5)
            end
        end
        if s.active then drawHud(DL, now) end
    end

    local board_render = Lib.imgui.OnFrame(function() return s.active or B.dragging end, function(self)
        drawBoard()
    end)
    board_render.HideCursor = true
    board_render.ShowCursor = false


    Fn.drawBoardUI = function(cw)
        local T = Fn.T
        local a = neon.main_alpha
        local function gap(n) im.Dummy(V2(0, n)) end
        local function hand() if im.IsItemHovered() then Data.nfn.set_hand_cursor() end end
        local function shiftY(amount)
            amount = tonumber(amount) or 0
            if math.abs(amount) > 0.01 then im.SetCursorPosY(im.GetCursorPosY() + amount) end
        end

        local stc = s.active and V4(0.3, 1.0, 0.4, 1.0) or V4(1.0, 0.35, 0.35, 1.0)
        im.TextColored(stc, s.active and T(u8"Доска АКТИВНА") or T(u8"Доска ВЫКЛЮЧЕНА"))
        im.SameLine(); im.TextDisabled(T(u8"(/board)"))
        gap(6)

        B.p_active[0] = s.active
        Data.fixed_toggle_pending_x = Data.ofs_get('tg_board_active', 0.0)
        shiftY(s.ui_buttons_y); Data.nfn.ios_toggle(T(u8"Включить доску"), B.p_active, a)
        if B.p_active[0] ~= s.active then B.set_active(B.p_active[0]) end
        gap(7)

        Data.fixed_slider_pending_x = Data.ofs_get('sl_board_grid', 0.0)
        shiftY(s.ui_sliders_y); Data.nfn.ios_slider(T(u8"Размер доски (NxN; 1 = 2 клетки)"), B.p_grid, 1, 8, a)
        if B.p_grid[0] >= 1 and B.p_grid[0] ~= s.grid then s.grid = B.p_grid[0]; save(); apply_live() end
        gap(5)
        Data.fixed_slider_pending_x = Data.ofs_get('sl_board_tiles', 0.0)
        shiftY(s.ui_sliders_y); Data.nfn.ios_slider(T(u8"Плиток одновременно"), B.p_tiles, 1, 6, a)
        if B.p_tiles[0] >= 1 and B.p_tiles[0] ~= s.tiles then s.tiles = B.p_tiles[0]; save(); apply_live() end
        gap(5)
        Data.fixed_slider_pending_x = Data.ofs_get('sl_board_cell', 0.0)
        shiftY(s.ui_sliders_y); Data.nfn.ios_slider(T(u8"Размер клетки (м)"), B.p_cell, 0.1, 3.0, a, nil, '%.2f')
        if B.p_cell[0] ~= s.cell_size then s.cell_size = B.p_cell[0]; save(); apply_live() end
        gap(5)
        Data.fixed_slider_pending_x = Data.ofs_get('sl_board_alpha', 0.0)
        shiftY(s.ui_sliders_y); Data.nfn.ios_slider(T(u8"Прозрачность доски"), B.p_alpha, 0.0, 1.0, a, nil, '%.2f')
        if B.p_alpha[0] ~= s.board_alpha then s.board_alpha = B.p_alpha[0]; save() end
        gap(5)
        Data.fixed_slider_pending_x = Data.ofs_get('sl_board_hud', 0.0)
        shiftY(s.ui_sliders_y); Data.nfn.ios_slider(T(u8"Масштаб текста"), B.p_hud, 0.5, 3.0, a, nil, '%.2f')
        if B.p_hud[0] ~= s.hud_scale then s.hud_scale = B.p_hud[0]; save() end
        gap(8)

        B.p_checker[0] = s.checker and true or false
        Data.fixed_toggle_pending_x = Data.ofs_get('tg_board_checker', 0.0)
        shiftY(s.ui_buttons_y); Data.nfn.ios_toggle(T(u8"Шахматная раскраска"), B.p_checker, a)
        if B.p_checker[0] ~= s.checker then s.checker = B.p_checker[0]; save() end
        gap(7)
        B.p_reaction[0] = s.reaction_mode and true or false
        Data.fixed_toggle_pending_x = Data.ofs_get('tg_board_reaction', 0.0)
        shiftY(s.ui_buttons_y); Data.nfn.ios_toggle(T(u8"Режим реакции"), B.p_reaction, a)
        if B.p_reaction[0] ~= s.reaction_mode then B.set_reaction_mode(B.p_reaction[0]) end
        gap(7)
        B.p_pause[0] = s.pause_reload and true or false
        Data.fixed_toggle_pending_x = Data.ofs_get('tg_board_pause', 0.0)
        shiftY(s.ui_buttons_y); Data.nfn.ios_toggle(T(u8"Пауза при перезарядке"), B.p_pause, a)
        if B.p_pause[0] ~= s.pause_reload then s.pause_reload = B.p_pause[0]; save() end
        gap(7)
        if s.pause_reload then
            Data.fixed_slider_pending_x = Data.ofs_get('sl_board_pdur', 0.0)
            shiftY(s.ui_sliders_y); Data.nfn.ios_slider(T(u8"Длительность паузы (с)"), B.p_pdur, 0.1, 10.0, a, nil, '%.1f')
            if B.p_pdur[0] ~= s.reload_pause then s.reload_pause = B.p_pdur[0]; save() end
            gap(8)
        end

        local function picker(label, id, tbl, k)
            Data.ofs_row('cp_' .. id)
            if Data.nfn.CustomColorPicker(T(label), id, tbl, true, a) then
                s[k .. '_r'], s[k .. '_g'], s[k .. '_b'], s[k .. '_a'] = tbl[1], tbl[2], tbl[3], tbl[4]
                save()
            end
            gap(6)
        end
        picker(u8"Цвет плитки", 'board_tile_col', B.tile_col, 'tile')
        picker(u8"Цвет светлых клеток", 'board_light_col', B.light_col, 'light')
        picker(u8"Цвет тёмных клеток", 'board_dark_col', B.dark_col, 'dark')
        gap(2)


        im.TextDisabled(T(u8"Прицел"))
        gap(4)
        picker(u8"Цвет прицела", 'board_cr_col', B.cr_col, 'cr')
        Data.ofs_row('bt_board_crmove')
        shiftY(s.ui_buttons_y)
        if im.Button(T(u8"Переместить прицел") .. '##boardcrmove', V2(cw - 40, 28)) then lua_thread.create(moveCrosshair) end
        hand()
        gap(8)

        local avg = (tonumber(rec.best_ms) or 0)
        im.TextDisabled(T(u8"Рекорд попаданий: ") .. (tonumber(rec.best_hits) or 0) ..
            string.format("   %s%.2f%s", T(u8"Скорость: "), tonumber(rec.best_speed) or 0, T(u8" /с")))
        im.TextDisabled(T(u8"Лучшее среднее: ") .. avg .. T(u8" мс") .. T(u8"   Серий: ") .. (tonumber(rec.games) or 0))
        im.TextDisabled(T(u8"Средняя реакция: ") .. tostring(tonumber(rec.reaction_avg_ms) or 0) .. T(u8" мс"))
        im.TextDisabled(T(u8"Лучшая реакция: ") .. tostring(tonumber(rec.best_reaction_ms) or 0) .. T(u8" мс"))
        gap(8)

        Data.ofs_row('bt_board_rec')
        shiftY(s.ui_buttons_y)
        if im.Button(T(u8"Сбросить рекорды") .. '##boardrec', V2(cw - 40, 28)) then B.reset_records() end
        hand()
        gap(math.max(0, math.min(80, tonumber(s.ui_bottom_gap) or 8)))
    end


    do
        local tr = {
            ["Шахматная доска"] = "Chess Board",
            ["Доска АКТИВНА"] = "Board ACTIVE", ["Доска ВЫКЛЮЧЕНА"] = "Board OFF",
            ["Включить доску"] = "Enable board", ["Размер доски (NxN; 1 = 2 клетки)"] = "Board size (NxN; 1 = 2 cells)",
            ["Плиток одновременно"] = "Tiles at once", ["Размер клетки (м)"] = "Cell size (m)",
            ["Прозрачность доски"] = "Board opacity", ["Масштаб текста"] = "Text scale",
            ["Шахматная раскраска"] = "Checkerboard pattern", ["Режим реакции"] = "Reaction mode",
            ["Ожидание сигнала..."] = "Waiting for signal...", ["ЦЕЛЬ!"] = "TARGET!",
            ["Реакция: "] = "Reaction: ", ["Средняя реакция: "] = "Average reaction: ",
            ["Лучшая реакция: "] = "Best reaction: ",
            ["Пауза при перезарядке"] = "Pause on reload",
            ["Длительность паузы (с)"] = "Pause duration (s)", ["Цвет плитки"] = "Tile color",
            ["Цвет светлых клеток"] = "Light cell color", ["Цвет тёмных клеток"] = "Dark cell color",
            ["Рекорд попаданий: "] = "Best hits: ", ["Скорость: "] = "Speed: ", [" /с"] = " /s",
            ["Лучшее среднее: "] = "Best avg: ", [" мс"] = " ms", ["   Серий: "] = "   Runs: ",
            ["Прицел"] = "Crosshair", ["Включить прицел"] = "Enable crosshair", ["Размер"] = "Size", ["Зазор"] = "Gap",
            ["Толщина"] = "Thickness", ["Обводка"] = "Outline", ["Толщ. обв."] = "Outline thick.", ["Точка"] = "Dot",
            ["Цвет прицела"] = "Crosshair color", ["Смещение: "] = "Offset: ", ["Переместить прицел"] = "Move crosshair",
            ["Сброс позиции"] = "Reset position",
            ["Убрать доску"] = "Remove board", ["Сбросить рекорды"] = "Reset records",
            ["Первый выстрел ставит доску. Промах = конец серии."] = "First shot places the board. A miss ends the run.",
            ["Доска: выстрелите, чтобы разместить её"] = "Board: shoot to place it",
            ["ПРОМАХ!"] = "MISS!", ["Попаданий: "] = "Hits: ", ["Сред.: "] = "Avg: ", ["Время: "] = "Time: ",
            [" с"] = " s", ["ПАУЗА (перезарядка)"] = "PAUSE (reload)", ["НОВЫЙ РЕКОРД!"] = "NEW RECORD!",
            ["Рекорд: "] = "Best: ", ["Выстрелите, чтобы начать заново"] = "Shoot to restart",
        }
        for k, val in pairs(tr) do Data.UI_TRANSLATIONS[Fn.decodeSafe(u8(k))] = val end
    end

    Data_board_save = function() save(); B.restore_native() end
    Data_board_register = function()
        pcall(sampRegisterChatCommand, 'board', function()

            B.set_active(not s.active)
        end)
    end
end

do
    local OT = { target = nil, events = {}, miss_reported = false, error_reported = false }
    Data.ot = OT
    local im = Lib.imgui
    local V2, V4 = im.ImVec2, im.ImVec4
    local function U32(c) return CBUGER_ApplyOverlayAlphaU32(im.ColorConvertFloat4ToU32(c)) end

    local function safeField(value, key)
        if value == nil then return nil end
        local ok, result = pcall(function() return value[key] end)
        if ok then return result end
        return nil
    end
    local function readVec(v)
        if v == nil then return nil end
        local ok, x, y, z = pcall(function()
            local vx, vy, vz = v.x, v.y, v.z
            if vx == nil then vx = v[1] end
            if vy == nil then vy = v[2] end
            if vz == nil then vz = v[3] end
            return tonumber(vx), tonumber(vy), tonumber(vz)
        end)
        if ok and x ~= nil and y ~= nil and z ~= nil then return x, y, z end
        return nil
    end
    local function bulletVectors(data)
        local payload, origin, target_vec = data, nil, nil
        for _ = 1, 3 do
            origin = safeField(payload, 'origin') or safeField(payload, 'start') or safeField(payload, 'originPos')
            target_vec = safeField(payload, 'target') or safeField(payload, 'targetPos') or safeField(payload, 'targetPosition')
            if origin ~= nil and target_vec ~= nil then break end
            local nested = safeField(payload, 'data') or safeField(payload, 'bulletSync') or safeField(payload, 'bullet')
            if nested == nil then break end
            payload = nested
        end
        return origin, target_vec
    end
    local function bulletEndpoint(data)
        local _, tv = bulletVectors(data)
        if tv == nil then return nil end
        return readVec(tv)
    end

    local function objectFromBullet(data)
        if data == nil then return nil, 'invalid_bullet_data:nil' end
        local origin, target_vec = bulletVectors(data)
        if origin == nil or target_vec == nil then return nil, 'invalid_bullet_data' end
        local ox, oy, oz = readVec(origin)
        local tx, ty, tz = readVec(target_vec)
        if ox == nil or tx == nil then return nil, 'missing_bullet_vectors' end
        local dx, dy, dz = tx - ox, ty - oy, tz - oz
        local length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length < 0.05 then return nil, 'short_bullet_ray' end
        local ext = math.min(3.0, math.max(0.75, length * 0.015))
        local ex, ey, ez = tx + dx / length * ext, ty + dy / length * ext, tz + dz / length * ext
        if type(processLineOfSight) ~= 'function' then return nil, 'processLineOfSight_unavailable' end
        local ok, hit, col = pcall(function()
            return processLineOfSight(ox, oy, oz, ex, ey, ez, true, false, false, true, false, false, false)
        end)
        if not ok then return nil, 'los_error:' .. tostring(hit) end
        if not hit then return nil, 'los_no_hit' end
        if type(col) ~= 'table' then return nil, 'los_result_' .. type(col) end
        local ptr = tonumber(col.entity) or col.entity
        if ptr == 0 then ptr = nil end
        local hx, hy, hz = readVec(col.position)
        if type(hx) ~= 'number' then hx, hy, hz = tx, ty, tz end
        if ptr ~= nil then
            local okH, handle = pcall(getObjectPointerHandle, ptr)
            if okH and handle then
                local okE, exists = pcall(doesObjectExist, handle)
                if okE and exists then
                    return { kind = 'object', handle = handle, entity = ptr,
                             key = 'object:' .. tostring(handle), x = hx, y = hy, z = hz }
                end
            end
            local okP, ped = pcall(getCharPointerHandle, ptr)
            if okP and ped then
                local okE, exists = pcall(doesCharExist, ped)
                if okE and exists then return nil, 'ped_collision' end
            end
            local okV, veh = pcall(getVehiclePointerHandle, ptr)
            if okV and veh then
                local okE, exists = pcall(doesVehicleExist, veh)
                if okE and exists then return nil, 'vehicle_collision' end
            end
        end
        local key = ptr and ('world:' .. tostring(ptr)) or
            ('world-pos:' .. math.floor(hx * 2) .. ':' .. math.floor(hy * 2) .. ':' .. math.floor(hz * 2))
        return { kind = 'world', entity = ptr, key = key, x = hx, y = hy, z = hz }
    end

    local function chat(msg)
        pcall(sampAddChatMessage, '{00D7FF}[CBUGER]{FFFFFF} ' .. CBUGER_CP(tostring(msg or '')), -1)
    end

    local function pushScore(target, sx, sy, sz)
        local x, y, z = tonumber(sx) or tonumber(target.x), tonumber(sy) or tonumber(target.y), tonumber(sz) or tonumber(target.z)
        if x == nil or y == nil or z == nil then return end
        local ev
        for _, e in ipairs(OT.events) do if e.target_counter then ev = e; break end end
        if not ev then ev = { target_counter = true }; OT.events[#OT.events + 1] = ev end
        ev.x, ev.y, ev.z = x, y, z
        ev.hits = math.max(0, math.floor(tonumber(target.hits) or 0))
        ev.misses = math.max(0, math.floor(tonumber(target.misses) or 0))
        ev.ttl, ev.max_ttl = 1.35, 1.35
    end

    function OT.reset()
        OT.target = nil
        OT.miss_reported = false
        OT.error_reported = false
        OT.events = {}
    end

    local function onBullet(data)
        if not (Data.hm and Data.hm.v and Data.hm.v.obj_target[0]) then return end
        local target = OT.target
        local hit, reason = objectFromBullet(data)
        local shx, shy, shz
        if hit then shx, shy, shz = hit.x, hit.y, hit.z else shx, shy, shz = bulletEndpoint(data) end
        if not target then
            if not hit then
                if not OT.miss_reported then
                    OT.miss_reported = true
                    local why = tostring(reason or 'unknown')
                    if #why > 110 then why = why:sub(1, 110) end
                    chat(Fn.L('Объект не распознан по трассировке (', 'Object not recognized by trace (') .. why .. ').')
                end
                return
            end
            OT.target = {
                kind = hit.kind, handle = hit.handle, entity = hit.entity, key = hit.key,
                label = hit.handle and tostring(hit.handle) or 'MAP',
                x = hit.x, y = hit.y, z = hit.z, anchor_x = hit.x, anchor_y = hit.y, anchor_z = hit.z,
                hits = 0, misses = 0,
            }
            OT.miss_reported = false
            return
        end
        if target.kind == 'object' then
            local okE, exists = pcall(doesObjectExist, target.handle)
            if not okE or not exists then OT.target = nil; return end
        end
        local same = false
        if hit then
            same = hit.key == target.key
            if not same and target.kind == 'world' and hit.kind == 'world' then
                local ax = (tonumber(target.anchor_x) or 0) - (tonumber(hit.x) or 0)
                local ay = (tonumber(target.anchor_y) or 0) - (tonumber(hit.y) or 0)
                local az = (tonumber(target.anchor_z) or 0) - (tonumber(hit.z) or 0)
                same = (ax * ax + ay * ay + az * az) <= 9.0
            end
        end
        if same then target.hits = (tonumber(target.hits) or 0) + 1
        else target.misses = (tonumber(target.misses) or 0) + 1 end
        pushScore(target, shx, shy, shz)
    end

    CBUGER_OT_onSendBulletSync = function(data)
        local ok, err = pcall(onBullet, data)
        if not ok and not OT.error_reported then
            OT.error_reported = true
            chat('{FF5555}' .. Fn.L('Ошибка обработки цели-объекта: ', 'Target object processing error: ') .. tostring(err))
        end
    end

    local function drawEvents()
        local dl = im.GetBackgroundDrawList()
        local okF, font = pcall(function()
            return (CBUGER_GET_GLOBAL_FONT_OR and CBUGER_GET_GLOBAL_FONT_OR(im.GetFont())) or im.GetFont()
        end)
        if not okF or not font then return end
        local remove = {}
        for i = #OT.events, 1, -1 do
            local e = OT.events[i]
            e.ttl = e.ttl - 0.016
            if e.ttl <= 0 then
                remove[#remove + 1] = i
            else
                local ok, sx, sy = pcall(convert3DCoordsToScreen, e.x, e.y, e.z)
                if ok and type(sx) == 'number' and sx ~= 0 then
                    local a = math.max(0, math.min(1, e.ttl / e.max_ttl))
                    local fsz = 20
                    local hitT, slash, missT = tostring(e.hits), '/', tostring(e.misses)
                    local hw = font:CalcTextSizeA(fsz, 1000, 0, hitT).x
                    local sw = font:CalcTextSizeA(fsz, 1000, 0, slash).x
                    local mw = font:CalcTextSizeA(fsz, 1000, 0, missT).x
                    local tx = sx - (hw + sw + mw) * 0.5
                    local ty = sy - fsz * 0.5
                    local shadow = U32(V4(0, 0, 0, 0.80 * a))
                    local function part(text, xp, c)
                        dl:AddTextFontPtr(font, fsz, V2(xp + 1, ty + 1), shadow, text)
                        dl:AddTextFontPtr(font, fsz, V2(xp, ty), c, text)
                    end
                    part(hitT, tx, U32(V4(0.20, 1.00, 0.25, a)))
                    part(slash, tx + hw, U32(V4(0.95, 0.95, 0.95, a)))
                    part(missT, tx + hw + sw, U32(V4(1.00, 0.20, 0.20, a)))
                end
            end
        end
        for _, idx in ipairs(remove) do table.remove(OT.events, idx) end
    end
    local function ot_cond() return Data.hm and Data.hm.v.obj_target[0] and #OT.events > 0 end

    local ot_render = Lib.imgui.OnFrame(ot_cond, function(self)
        self.HideCursor = true
        drawEvents()
    end)
    ot_render.HideCursor = true
    ot_render.ShowCursor = false

    Fn.ModeSyncTarget = function()
        local HM = Data.hm
        if not (HM and HM.v and HM.v.obj_target) then return end
        local cur = HM.v.obj_target[0] and true or false
        if cur ~= OT.was_on then
            local first_sync = (OT.was_on == nil)
            OT.was_on = cur
            if not cur then OT.reset() end
            HM.save(true)
            if not first_sync then CBUGER_ModeMsg('target', cur) end
        end
    end
    Fn.ModeSyncControl = function()
        local cur = ui.recoil_enabled[0] and true or false
        if cur ~= Data.control_was_on then
            local first_sync = (Data.control_was_on == nil)
            Data.control_was_on = cur
            if not first_sync then
                S.cfg.config.recoil_enabled = cur
                pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
                CBUGER_ModeMsg('control', cur)
            end
        end
    end
    Fn.ModeSyncMap = function()
        local cur = ui.shotmap_enabled[0] and true or false
        if cur ~= Data.map_was_on then
            local first_sync = (Data.map_was_on == nil)
            Data.map_was_on = cur
            if not first_sync then
                S.cfg.config.shotmap_enabled = cur
                pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
                CBUGER_ModeMsg('map', cur)
            end
        end
    end
    Data_map_register = function()
        pcall(sampRegisterChatCommand, 'map', function()
            ui.shotmap_enabled[0] = not ui.shotmap_enabled[0]
            Fn.ModeSyncMap()
        end)
    end
    Fn.ModeSyncAll = function()
        if Data.hm and Data.hm.sync then Data.hm.sync() end
        Fn.ModeSyncTarget()
        Fn.ModeSyncControl()
        Fn.ModeSyncMap()
    end
    Data_target_register = function()
        pcall(sampRegisterChatCommand, 'target', function()
            local HM = Data.hm
            if not (HM and HM.v and HM.v.obj_target) then return end
            HM.v.obj_target[0] = not HM.v.obj_target[0]
            Fn.ModeSyncTarget()
        end)
    end
    Data_control_register = function()
        pcall(sampRegisterChatCommand, 'control', function()
            ui.recoil_enabled[0] = not ui.recoil_enabled[0]
            Fn.ModeSyncControl()
        end)
    end


    Fn.drawObjTargetUI = function(cw)
        local T = Fn.T
        local a = neon.main_alpha
        local HM = Data.hm
        local function gap(n) im.Dummy(V2(0, n)) end
        Data.fixed_toggle_pending_x = Data.ofs_get and Data.ofs_get('tg_objtarget', 0.0) or 0
        Data.nfn.ios_toggle(T(u8"Выбрать объект первым выстрелом"), HM.v.obj_target, a)
        Fn.ModeSyncTarget()
        gap(7)
        if HM.v.obj_target[0] then
            im.TextDisabled(T(u8"Первый выстрел по объекту закрепляет его как цель."))
            if OT.target then
                im.TextDisabled(T(u8"Выбран объект: ") .. tostring(OT.target.label or OT.target.handle or 'MAP') ..
                    T(u8"  |  попаданий: ") .. tostring(OT.target.hits or 0) ..
                    T(u8"  |  промахов: ") .. tostring(OT.target.misses or 0))
            else
                im.TextDisabled(T(u8"Цель ещё не выбрана."))
            end
            gap(4)
            if Data.ofs_row then Data.ofs_row('bt_objtarget_reset') end
            if im.Button(T(u8"Сбросить цель") .. '##ot_reset', V2(cw - 40, 28)) then OT.reset() end
            if im.IsItemHovered() then Data.nfn.set_hand_cursor() end
        end
    end

    do
        local tr = {
            ["Цель-объект"] = "Object target",
            ["Выбрать объект первым выстрелом"] = "Pick object with first shot",
            ["Первый выстрел по объекту закрепляет его как цель."] = "The first shot at an object pins it as the target.",
            ["Выбран объект: "] = "Selected object: ", ["  |  попаданий: "] = "  |  hits: ",
            ["  |  промахов: "] = "  |  misses: ", ["Цель ещё не выбрана."] = "No target selected yet.",
            ["Сбросить цель"] = "Reset target",
        }
        for k, val in pairs(tr) do Data.UI_TRANSLATIONS[Fn.decodeSafe(u8(k))] = val end
    end
end




do
    local im = Lib.imgui
    Fn.drawKeymapUI = function(cw)
        local T = Fn.T
        local KS = Fn.KS
        local a = neon.main_alpha
        local on = KS.enabled[0] and true or false
        local stc = on and im.ImVec4(0.3, 1.0, 0.4, 1.0) or im.ImVec4(1.0, 0.35, 0.35, 1.0)
        im.TextColored(stc, on and T(u8"Тепловая карта АКТИВНА") or T(u8"Тепловая карта ВЫКЛЮЧЕНА"))
        im.SameLine(); im.TextDisabled(T(u8"(/keymap)"))
        im.Dummy(im.ImVec2(0, 6))
        Data.fixed_toggle_pending_x = Data.ofs_get and Data.ofs_get('tg_keymap_active', 0.0) or nil
        Data.nfn.ios_toggle(T(u8"Включить карту"), KS.enabled, a)
        im.Dummy(im.ImVec2(0, 6))
        if on and not (ui.keyboard[0] or ui.mouse[0]) then
            im.TextColored(im.ImVec4(1.0, 0.75, 0.2, a),
                T(u8"Включите показ клавиатуры/мыши, чтобы видеть карту"))
            im.Dummy(im.ImVec2(0, 4))
        end
        KS.draw_ui(neon.global_alpha, a, cw)
        im.Dummy(im.ImVec2(0, 8))
    end

    Fn.ModeSyncKeymap = function()
        local cur = Fn.KS.enabled[0] and true or false
        if cur ~= Data.keymap_was_on then
            local first_sync = (Data.keymap_was_on == nil)
            Data.keymap_was_on = cur
            if not first_sync then CBUGER_ModeMsg('keymap', cur) end
        end
    end
    do
        local prevAll = Fn.ModeSyncAll
        Fn.ModeSyncAll = function()
            if prevAll then prevAll() end
            Fn.ModeSyncKeymap()
        end
    end
    Data_keymap_register = function()
        pcall(sampRegisterChatCommand, 'keymap', function()
            Fn.KS.enabled[0] = not Fn.KS.enabled[0]
            Fn.ModeSyncKeymap()
        end)
    end

    local tr = {
        ["Тепловая карта АКТИВНА"] = "Heatmap ACTIVE",
        ["Тепловая карта ВЫКЛЮЧЕНА"] = "Heatmap OFF",
        ["Включить карту"] = "Enable map",
        ["Включите показ клавиатуры/мыши, чтобы видеть карту"] = "Show the keyboard/mouse overlay to see the map",
    }
    for k, val in pairs(tr) do
        local dk = Fn.decodeSafe(u8(k))
        if not Data.UI_TRANSLATIONS[dk] then Data.UI_TRANSLATIONS[dk] = val end
    end
end




do
    local extra = {
        ["КПД"] = "Efficiency",
        ["Подпись \"by Pryanix\""] = "\"by Pryanix\" signature",
        ["Удалить выделенные"] = "Delete selected",
        ["Этап "] = "Stage ",
        ["Добавить клавишу в этап "] = "Add key to stage ",
        ["Описание:"] = "Description:",
        ["Цвет"] = "Color",
        ["Цвет гайда"] = "Guide color",
        ["Размер"] = "Size",
        ["Цель-объект"] = "Target object",
        ["Выбрать объект первым выстрелом##cbug_obj_target"] = "Select object with first shot##cbug_obj_target",
        ["Первый выстрел по объекту закрепляет его как цель."] = "The first shot at an object locks it as the target.",
        ["Выбран объект: "] = "Object selected: ",
        ["  |  попаданий: "] = "  |  hits: ",
        ["Цель ещё не выбрана."] = "No target selected yet.",
        ["Сбросить цель##cbug_obj_target_reset"] = "Reset target##cbug_obj_target_reset",
    }
    for k, val in pairs(extra) do
        local dk = Fn.decodeSafe(u8(k))
        if not Data.UI_TRANSLATIONS[dk] then Data.UI_TRANSLATIONS[dk] = val end
    end

        local names_old = {
            ["Обычный"] = "Normal",
            ["Крестики"] = "Crosses",
            ["Всплывающие кольца"] = "Rising rings",
            ["Капли"] = "Drops",
            ["Замедленный след"] = "Slow trail",
            ["Огонь"] = "Fire",
            ["Кольца"] = "Rings",
            ["Линии"] = "Lines",
            ["Туманность"] = "Nebula",
            ["Горизонтальные штрихи"] = "Horizontal dashes",
            ["Тёмная дыра"] = "Black hole",
            ["Случайный"] = "Random",
            ["Падающие штрихи"] = "Falling dashes",
            ["Диагональ"] = "Diagonal",
            ["Взрыв"] = "Explosion",
            ["Спираль"] = "Spiral",
            ["Крупные кольца"] = "Large rings",
            ["Зигзаг"] = "Zigzag",
            ["Конфетти"] = "Confetti",
            ["Шестиугольники"] = "Hexagons",
            ["Волны"] = "Waves",
            ["Эквалайзер"] = "Equalizer",
            ["Расходящиеся круги"] = "Expanding circles",
            ["Цифровой шум"] = "Digital noise",
            ["Кардиограмма"] = "Heartbeat",
            ["Двойная спираль"] = "Double helix",
            ["Радар"] = "Radar",
            ["Соты"] = "Honeycomb",
            ["Пузыри"] = "Bubbles",
            ["Тройные волны"] = "Triple waves",
            ["Маятник"] = "Pendulum",
            ["Лабиринт"] = "Maze",
            ["Звёздный поток"] = "Star stream",
            ["Пульсирующие круги"] = "Pulsing circles",
            ["Шестиугольники на волне"] = "Wave hexagons",
            ["Спектр"] = "Spectrum",
            ["Фигуры Лиссажу"] = "Lissajous figures",
            ["Деформация поля"] = "Field distortion",
            ["Полиция мигает"] = "Police flashing",
            ["Мигающие вспышки"] = "Flashing bursts",
            ["Вертикальный скан"] = "Vertical scan",
            ["Пульс"] = "Pulse",
            ["Стробоскоп"] = "Strobe",
            ["Световые полосы"] = "Light stripes",
            ["Расходящийся круг"] = "Expanding circle",
            ["Прожектор"] = "Spotlight",
            ["Острый импульс"] = "Sharp pulse",
            ["Молния"] = "Lightning",
            ["Световой мерцатель"] = "Light flicker",
            ["Горизонтальный скан"] = "Horizontal scan",
            ["Хроматик"] = "Chromatic",
            ["Кольцо"] = "Ring",
            ["Морзе"] = "Morse",
            ["Градиент"] = "Gradient",
        }
    for k, val in pairs(names_old) do
        Data.UI_TRANSLATIONS[Fn.decodeSafe(u8(k))] = val
    end
end

function CB.run()
    while not isSampAvailable() do wait(100) end
    pcall(function() if Data_hm_register then Data_hm_register() end; if Data_cbug_register then Data_cbug_register() end; if Data_board_register then Data_board_register() end; if Data_keymap_register then Data_keymap_register() end; if Data_target_register then Data_target_register() end; if Data_control_register then Data_control_register() end; if Data_map_register then Data_map_register() end end)
    CBUGER_WAIT_RUNTIME_READY()
    wait(250)
    local loaded = Fn.load_combos_from_json()
    if loaded then
        S.combos_list = loaded
    else
        S.combos_list = {}
    end
    local function CBUGER_LOWER_COMBO_NAME(value)
        value = tostring(value or '')

        local ru_case = {
            {"А","а"},{"Б","б"},{"В","в"},{"Г","г"},{"Д","д"},{"Е","е"},{"Ё","ё"},
            {"Ж","ж"},{"З","з"},{"И","и"},{"Й","й"},{"К","к"},{"Л","л"},{"М","м"},
            {"Н","н"},{"О","о"},{"П","п"},{"Р","р"},{"С","с"},{"Т","т"},{"У","у"},
            {"Ф","ф"},{"Х","х"},{"Ц","ц"},{"Ч","ч"},{"Ш","ш"},{"Щ","щ"},{"Ъ","ъ"},
            {"Ы","ы"},{"Ь","ь"},{"Э","э"},{"Ю","ю"},{"Я","я"},
        }
        for _, pair in ipairs(ru_case) do value = value:gsub(pair[1], pair[2]) end
        return value:lower():gsub('^%s+', ''):gsub('%s+$', '')
    end
    local function CBUGER_COMBO_BASE_NAME(name)
        local value = tostring(name or '')
        value = value:match('^(.-)%s*|') or value
        return CBUGER_LOWER_COMBO_NAME(value)
    end
    local function CBUGER_IS_STANDALONE_RYVOK(name)
        local full = CBUGER_LOWER_COMBO_NAME(name)
        return full == CBUGER_LOWER_COMBO_NAME(u8"Рывок")
            and not tostring(name or ''):find('|', 1, true)
    end
    local standard_combos_changed = false

    local refresh_presets_once = S.cfg.config.cbuger_combo_presets_20261123_keymap_alternatives_v1 ~= true

    local initialize_presets = refresh_presets_once or not loaded

    if refresh_presets_once then
        for i = #S.combos_list, 1, -1 do
            local existing = S.combos_list[i]
            if type(existing) == 'table' and CBUGER_IS_STANDALONE_RYVOK(existing.name) then
                table.remove(S.combos_list, i)
                standard_combos_changed = true
            end
        end
    end

    for _, standard in ipairs(S.default_combos) do
        local base = CBUGER_COMBO_BASE_NAME(standard.name)
        local found = nil
        for i, existing in ipairs(S.combos_list) do
            if type(existing) == 'table'
                and CBUGER_COMBO_BASE_NAME(existing.name) == base
                and not (base == CBUGER_LOWER_COMBO_NAME(u8"Рывок")
                    and CBUGER_IS_STANDALONE_RYVOK(existing.name)) then
                found = i
                break
            end
        end
        if found then
            if refresh_presets_once then
                local replacement = Fn.deepcopy(standard)

                if S.combos_list[found].name then replacement.name = S.combos_list[found].name end
                S.combos_list[found] = replacement
                standard_combos_changed = true
            end
        elseif initialize_presets then
            S.combos_list[#S.combos_list + 1] = Fn.deepcopy(standard)
            standard_combos_changed = true
        end
    end

    local preset_data_by_base = {}
    for _, standard in ipairs(S.default_combos) do
        preset_data_by_base[CBUGER_COMBO_BASE_NAME(standard.name)] = standard.data
    end

    local otvod_slide_data = {{u8"ЛКМ", u8"ПКМ", u8"А", "C"}}
    for _ = 1, 5 do
        otvod_slide_data[#otvod_slide_data + 1] = {u8"ПКМ", u8"ЛКМ", u8"А", "C"}
    end
    local otvod_slide_base = CBUGER_LOWER_COMBO_NAME(u8"Отвод + Слайд")
    local migrated_a_to_f = false
    for _, combo in ipairs(S.combos_list) do
        if type(combo) == 'table' then
            local full_name = tostring(combo.name or '')
            if refresh_presets_once then
                if CBUGER_COMBO_BASE_NAME(full_name) == otvod_slide_base then
                    combo.data = Fn.deepcopy(otvod_slide_data)
                    standard_combos_changed = true
                else
                    local preset_data = preset_data_by_base[CBUGER_COMBO_BASE_NAME(full_name)]
                    if preset_data then
                        combo.data = Fn.deepcopy(preset_data)
                        standard_combos_changed = true
                    end
                end
            end

            if type(combo.data) == 'table' then
                for _, part in ipairs(combo.data) do
                    if type(part) == 'table' then
                        for key_index, key in ipairs(part) do
                            if type(key) == 'string' and key == 'A' then
                                part[key_index] = u8"Ф"
                                migrated_a_to_f = true
                            elseif type(key) == 'table' then
                                if key.name == 'A' then key.name = u8"Ф"; migrated_a_to_f = true end
                                if key[1] == 'A' then key[1] = u8"Ф"; migrated_a_to_f = true end
                            end
                        end
                    end
                end
            end
        end
    end

    local cleaned_existing_combos = false
    for _, combo in ipairs(S.combos_list) do
        if type(combo) == 'table' and type(combo.data) == 'table' then
            local cleaned, changed = Fn.cleanEmptyComboStages(combo.data)
            if changed then
                combo.data = cleaned
                cleaned_existing_combos = true
            end
        end
    end

    local combos_saved = true
    if cleaned_existing_combos or standard_combos_changed or migrated_a_to_f then
        combos_saved = Fn.saveCombos() ~= false
    end
    if refresh_presets_once and combos_saved then

        S.cfg.config.cbuger_combo_presets_20261123_keymap_alternatives_v1 = true
        pcall(function() Lib.inicfg.save(S.cfg, Data.iniFile) end)
    end
    if not S.cfg.config.language_mode then S.cfg.config.language_mode = 1 end
    if not S.cfg.config.interface_alpha then S.cfg.config.interface_alpha = 1.0 end
    if not S.cfg.config.interface_lang then S.cfg.config.interface_lang = 1 end
    ui.language_mode[0] = S.cfg.config.language_mode
   Fn.load_shotmap_from_json()
    if not Data.shotmap_autosave_started then
        Data.shotmap_autosave_started = true
        lua_thread.create(function()
            while true do
                wait(5000)
                local sm = Data.shotmap
                if type(sm) == 'table' and sm.dirty
                    and os.clock() - (tonumber(sm.last_save) or 0) >= 4 then
                    pcall(Fn.save_shotmap_to_json)
                end
            end
        end)
    end
    S.state.recoil_correct   = S.cfg.config.recoil_correct   or 0
    S.state.recoil_incorrect = S.cfg.config.recoil_incorrect or 0
    ui.shotmap_view_index[0] = Fn.shotmapCardCount()
    do
        local nc = S.cfg.neon
        if nc then
           Data.neon_smooth_close[0]            = nc.smooth_close ~= false
            neon.current_font_idx[0]        = nc.font_idx or 0
            neon.window_size.w              = nc.win_w or 480
            neon.window_size.h              = nc.win_h or 520
            neon_fx.global_base_color       = { nc.base_r or 0, nc.base_g or 0.8, nc.base_b or 1, nc.base_a or 0.95 }
            neon_fx.neon_border_color       = { nc.border_r or 0, nc.border_g or 0.8, nc.border_b or 1, nc.border_a or 0.66 }
            neon_fx.button_border_color   = { nc.button_border_r or 0, nc.button_border_g or 0.32, nc.button_border_b or 0.4, nc.button_border_a or 0.6 }
            neon_fx.tabs_color              = { nc.tabs_r or 0, nc.tabs_g or 0.8, nc.tabs_b or 1, nc.tabs_a or 1 }
            neon_fx.title_color             = { nc.title_r or 0, nc.title_g or 0.8, nc.title_b or 1, nc.title_a or 1 }
            neon_fx.title_button_color      = { nc.title_r or 0, nc.title_g or 0.8, nc.title_b or 1, nc.title_a or 1 }
            neon_fx.icon_cross_color        = { nc.cross_r or 1, nc.cross_g or 0.2, nc.cross_b or 0.2, nc.cross_a or 1 }
            neon_fx.icon_eye_color          = { nc.eye_r or 0, nc.eye_g or 0.8, nc.eye_b or 1, nc.eye_a or 1 }
            neon_fx.icon_gear_color         = { nc.gear_r or 0, nc.gear_g or 0.8, nc.gear_b or 1, nc.gear_a or 1 }
            neon_fx.icon_resize_color       = { nc.resize_r or 0.7, nc.resize_g or 0, nc.resize_b or 1, nc.resize_a or 0.67 }
            neon_fx.section_icon_color      = { nc.sec_icon_r or 0, nc.sec_icon_g or 0.8, nc.sec_icon_b or 1, nc.sec_icon_a or 1 }
            neon_fx.tab_icon_color          = { nc.tab_icon_r or 1, nc.tab_icon_g or 1,   nc.tab_icon_b or 1, nc.tab_icon_a or 1 }
            neon_fx.selection_color         = { nc.sel_r or 0, nc.sel_g or 0.8, nc.sel_b or 1, nc.sel_a or 1.0 }
            neon_fx.recoil_flash_color      = { nc.recoil_flash_r or 1.0, nc.recoil_flash_g or 0.1, nc.recoil_flash_b or 0.1, nc.recoil_flash_a or 1.0 }
            neon_fx.sparks_on[0]            = nc.sparks_on ~= false
            neon_fx.sparks_speed[0]         = nc.sparks_speed or 1.0
            neon_fx.sparks_size[0]          = nc.sparks_size or 1.0
            neon_fx.cursor_fx_var[0]        = nc.cursor_fx or 0
            neon_fx.sparks_color            = { nc.sparks_r or 0, nc.sparks_g or 0.8, nc.sparks_b or 1, nc.sparks_a or 1 }
            neon_fx.waves_on[0]             = nc.waves_on ~= false
            neon_fx.waves_speed[0]          = nc.waves_speed or 1.0
            neon_fx.waves_var[0]            = nc.waves_var or 0
            neon_fx.waves_color             = { nc.waves_r or 0, nc.waves_g or 0.8, nc.waves_b or 1, nc.waves_a or 1 }
            neon_fx.ambient_on[0]           = nc.ambient_on ~= false
            neon_fx.ambient_speed[0]        = nc.ambient_speed or 1.0
            neon_fx.ambient_var[0]          = nc.ambient_var or 0
            neon_fx.ambient_color_1         = { nc.ambient1_r or 0, nc.ambient1_g or 0, nc.ambient1_b or 1, nc.ambient1_a or 1 }
            neon_fx.ambient_color_2         = { nc.ambient2_r or 1, nc.ambient2_g or 0, nc.ambient2_b or 0, nc.ambient2_a or 1 }
        end
    end
    sampRegisterChatCommand('cbg', function()
        neon.target_main[0] = not neon.target_main[0]
    end)
    sampRegisterChatCommand('gui', function()
        ui.guide_open[0] = not ui.guide_open[0]
    end)
    while true do
        wait(0)
        pcall(Fn.ModeSyncAll)
        S.state.runtime_frame = (S.state.runtime_frame or 0) + 1
       Data.space_as_shift_enabled = ui.space_as_shift[0] and ui.keyboard_type[0] == 0
        for _, k in ipairs(S.all_monitored_keys) do
            if k.name == u8"ПРОБЕЛ" then
                k.code = Fn.getSpaceCode()
                break
            end
        end
        local neon_open = neon.target_main[0] or neon.target_editor[0]
                       or neon.target_combo_editor[0]
                       or (neon.main_alpha > 0.01) or (neon.editor_alpha > 0.01)
                       or (neon.combo_editor_alpha > 0.01)
       Lib.imgui.Process = neon_open or ui.guide_open[0] or (
            ui.keyboard[0] or
            ui.mouse[0] or
            S.state.current_combo ~= nil or
            ui.show_logs[0] or
            ui.show_combo_window[0]
        )
       Lib.imgui.LockPlayer = neon_open or ui.guide_open[0]
       Data.samp_chat_is_open = false
        pcall(function()
           Data.samp_chat_is_open = sampIsChatInputActive() or sampIsDialogActive()
        end)

        if not Data.samp_chat_is_open and type(isPauseMenuActive) == 'function' then
            local ok_pause, pause_active = pcall(isPauseMenuActive)
            if ok_pause and pause_active then Data.samp_chat_is_open = true end
        end
        local samp_chat_open = Data.samp_chat_is_open
        do
                    local guide_is_open_now = ui.guide_open and ui.guide_open[0]
                    for _, lines in ipairs(keyboards) do
                        for _, line in ipairs(lines) do
                            for _, v in ipairs(line) do
                                local code = v[2]
                                if not Fn.isPhysicalKeyDown(code) then
                                    local nm = (v.space and u8"ПРОБЕЛ") or v[1]
                                    S.state.key_needs_release[Fn.decodeSafe(nm)] = nil
                                    S.state.held_keys[code]       = nil
                                    S.state.hold_triggered[code]  = nil
                                    S.state.blocked_held[code]    = nil
                                    if S.state.tap_keys_last_part[Fn.decodeSafe(nm)] then
                                        S.state.tap_keys_released[Fn.decodeSafe(nm)] = true
                                    end
                                elseif samp_chat_open then

                                    S.state.held_keys[code] = nil
                                    S.state.blocked_held[code] = true
                                    S.state.hold_triggered[code] = true
                                elseif not guide_is_open_now and not S.state.blocked_held[code] then
                                    if not S.state.held_keys[code] then
                                        S.state.held_keys[code] = os.clock()
                                        if S.state.current_combo and S.state.combo_started then
                                            local nm      = (v.space and u8"ПРОБЕЛ") or v[1]
                                            local indices = Fn.findKeyIndicesInCurrentPart(nm)
                                            local idx     = Fn.chooseBestIndexForKey(indices)
                                            if idx then S.state.last_combo_activity = os.clock() end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    local mouse_codes = {0x01, 0x02}
                    for _, code in ipairs(mouse_codes) do
                        if not Fn.isPhysicalKeyDown(code) then
                            local nm = Fn.codeToName(code)
                            S.state.key_needs_release[Fn.decodeSafe(nm)] = nil
                            S.state.held_keys[code]       = nil
                            S.state.hold_triggered[code]  = nil
                            S.state.blocked_held[code]    = nil
                            if S.state.tap_keys_last_part[Fn.decodeSafe(nm)] then
                                S.state.tap_keys_released[Fn.decodeSafe(nm)] = true
                            end
                        elseif samp_chat_open then
                            S.state.held_keys[code] = nil
                            S.state.blocked_held[code] = true
                            S.state.hold_triggered[code] = true
                        elseif not S.state.blocked_held[code] then
                            if not S.state.held_keys[code] then
                                S.state.held_keys[code] = os.clock()
                                if S.state.current_combo and S.state.combo_started then
                                    local nm      = Fn.codeToName(code)
                                    local indices = Fn.findKeyIndicesInCurrentPart(nm)
                                    local idx     = Fn.chooseBestIndexForKey(indices)
                                    if idx then S.state.last_combo_activity = os.clock() end
                                end
                            end
                        end
                    end
                    if not samp_chat_open and S.state.current_combo and S.state.combo_completed then


                        for _, info in ipairs(S.all_monitored_keys) do
                            if Fn.isPhysicalKeyDown(info.code) and not (S.state.completed_wait_keys or {})[info.code] then
                                S.state.hold_triggered[info.code] = true
                                S.state.blocked_held[info.code]   = true
                                S.state.held_keys[info.code]      = nil
                            end
                        end
                        local completion_key_down = false
                        for completed_code, _ in pairs(S.state.completed_wait_keys or {}) do
                            if Fn.isPhysicalKeyDown(completed_code) then
                                completion_key_down = true
                                break
                            end
                        end
                        if not completion_key_down and S.state.completed_at_frame ~= S.state.runtime_frame then
                            S.state.combo_completed = false
                            S.state.completed_wait_keys = {}
                            S.state.completed_at_frame = nil
                            Fn.restartCombo()
                        end
                    end
                    if samp_chat_open and S.state.current_combo and S.state.combo_started then
                        S.state.last_combo_activity = os.clock()
                    end
                    if not samp_chat_open and S.state.current_combo and S.state.combo_started and not S.state.combo_completed and S.state.last_combo_activity > 0 then
                        if os.clock() - S.state.last_combo_activity >= S.state.LAST_ACTIVITY_TIMEOUT then
                            S.state.combo_started      = false
                            S.state.current_part_index = 1
                            S.state.current_key_index  = 1
                            S.state.key_needs_release  = {}
                            S.state.tap_keys_last_part = {}; S.state.tap_keys_released = {}
                            S.state.pending_next_part_key = nil
                            for _, info in ipairs(S.all_monitored_keys) do
                                if Fn.isPhysicalKeyDown(info.code) then
                                    S.state.hold_triggered[info.code] = true
                                    S.state.blocked_held[info.code]   = true
                                    S.state.held_keys[info.code]      = nil
                                end
                            end
                           Fn.prepareCurrentPart()
                            if ui.show_chat_messages[0] then
                                sampAddChatMessage(Fn.L(Fn.cp(u8"[CBUGER]: Комбинация сброшена из-за простоя."), "[CBUGER]: Combo reset due to inactivity."), 0xFFFF00)
                            end
                            S.state.last_combo_activity = 0
                        end
                    end
                    if S.state.current_combo and S.state.combo_started then Fn.checkHoldProgress() end
                   Fn.processHeldErrors()
                    if not samp_chat_open and S.state.error_recovery_at and os.clock() >= S.state.error_recovery_at then
                        S.state.error_recovery_at    = nil
                        S.state.error_state.is_error = false
                       Fn.restartCombo()
                    end
                    if not guide_is_open_now and not samp_chat_open then
                        for _, k in ipairs(S.all_monitored_keys) do
                            local down = Fn.isPhysicalKeyDown(k.code)
                            if down and not S.prev_key_states[k.code] then
                               Fn.addComboLog(k.name)
                            end
                            S.prev_key_states[k.code] = down
                        end
                    else
                        for _, k in ipairs(S.all_monitored_keys) do
                            S.prev_key_states[k.code] = Fn.isPhysicalKeyDown(k.code)
                        end
                    end
        end

        do
            local why = ((ui.guide_open and ui.guide_open[0]) and 'guide')
                        or (Data.samp_chat_is_open and 'chat') or nil
            Fn.KS.why = why
            Fn.KS.safe_update(why ~= nil)
        end
        local any_ui_open = neon_open or ui.guide_open[0]
        neon_render.HideCursor = not any_ui_open
        neon_render.ShowCursor = any_ui_open
        if Data.cbuger_cursor_ui_was_open and not any_ui_open then
            CBUGER_FORCE_HIDE_CURSOR()
        end
        Data.cbuger_cursor_ui_was_open = any_ui_open and true or false
    end
end
function CB.terminate(s)
    if s == thisScript() then
       pcall(Fn.save_shotmap_to_json)
       pcall(function() Fn.KS.save() end)
        S.cfg.config.active              = ui.keyboard[0]
        S.cfg.mouse.active               = ui.mouse[0]
        S.cfg.config.move                = ui.move[0]
        S.cfg.config.border_thickness    = Data.border_thickness[0]
        S.cfg.config.border_mode         = ui.border_mode[0]
        S.cfg.config.text_alpha          = ui.text_alpha[0]
        S.cfg.pos.x,   S.cfg.pos.y       = ui.keyboard_pos.x, ui.keyboard_pos.y
        S.cfg.mouse.x, S.cfg.mouse.y     = ui.mouse_pos.x,    ui.mouse_pos.y
        Data.mouse_pos_x[0] = ui.mouse_pos.x
        Data.mouse_pos_y[0] = ui.mouse_pos.y
        S.cfg.mouse.lmb_width            = Data.lmb_width[0]
        S.cfg.mouse.lmb_height           = Data.lmb_height[0]
        S.cfg.mouse.rmb_width            = Data.rmb_width[0]
        S.cfg.mouse.rmb_height           = Data.rmb_height[0]
        S.cfg.mouse.mmb_width            = Data.mmb_width[0]
        S.cfg.mouse.mmb_height           = Data.mmb_height[0]
        S.cfg.mouse.side_width           = Data.side_width[0]
        S.cfg.mouse.side_height          = Data.side_height[0]
        S.cfg.config.mouse_gap           = Data.mouse_gap[0]
        S.cfg.keyboard.key_width         = Data.key_width[0]
        S.cfg.keyboard.key_height        = Data.key_height[0]
        S.cfg.keyboard.space_width       = Data.space_width[0]
        S.cfg.keyboard.space_height      = Data.space_height[0]
        S.cfg.keyboard.c_x               = Data.c_pos_x[0]
        S.cfg.keyboard.c_y               = Data.c_pos_y[0]
        S.cfg.keyboard.space_x           = Data.space_pos_x[0]
        S.cfg.keyboard.space_y           = Data.space_pos_y[0]
        S.cfg.config.held_r    = ui.held_color[1];    S.cfg.config.held_g    = ui.held_color[2]
        S.cfg.config.held_b    = ui.held_color[3];    S.cfg.config.held_a    = ui.held_color[4]
        S.cfg.config.correct_r = ui.correct_color[1]; S.cfg.config.correct_g = ui.correct_color[2]
        S.cfg.config.correct_b = ui.correct_color[3]; S.cfg.config.correct_a = ui.correct_color[4]
        S.cfg.config.error_r   = ui.error_color[1];   S.cfg.config.error_g   = ui.error_color[2]
        S.cfg.config.error_b   = ui.error_color[3];   S.cfg.config.error_a   = ui.error_color[4]
        S.cfg.config.key_fill_r   = ui.key_fill_color[1]
        S.cfg.config.key_fill_g   = ui.key_fill_color[2]
        S.cfg.config.key_fill_b   = ui.key_fill_color[3]
        S.cfg.config.key_fill_a   = ui.key_fill_color[4]
        S.cfg.config.key_border_r = ui.key_border_color[1]
        S.cfg.config.key_border_g = ui.key_border_color[2]
        S.cfg.config.key_border_b = ui.key_border_color[3]
        S.cfg.config.key_border_a = ui.key_border_color[4]
        S.cfg.config.key_text_r   = ui.key_text_color[1]
        S.cfg.config.key_text_g   = ui.key_text_color[2]
        S.cfg.config.key_text_b   = ui.key_text_color[3]
        S.cfg.config.key_text_a   = ui.key_text_color[4]
        S.cfg.config.pressed_fill_r   = ui.pressed_fill_color[1]
        S.cfg.config.pressed_fill_g   = ui.pressed_fill_color[2]
        S.cfg.config.pressed_fill_b   = ui.pressed_fill_color[3]
        S.cfg.config.pressed_fill_a   = ui.pressed_fill_color[4]
        S.cfg.config.pressed_border_r = ui.pressed_border_color[1]
        S.cfg.config.pressed_border_g = ui.pressed_border_color[2]
        S.cfg.config.pressed_border_b = ui.pressed_border_color[3]
        S.cfg.config.pressed_border_a = ui.pressed_border_color[4]
        S.cfg.config.pressed_text_r   = ui.pressed_text_color[1]
        S.cfg.config.pressed_text_g   = ui.pressed_text_color[2]
        S.cfg.config.pressed_text_b   = ui.pressed_text_color[3]
        S.cfg.config.pressed_text_a   = ui.pressed_text_color[4]
        S.cfg.config.pressed_fill_enabled   = ui.pressed_fill_enabled[0]
        S.cfg.config.pressed_border_enabled = ui.pressed_border_enabled[0]
        S.cfg.config.pressed_text_enabled   = ui.pressed_text_enabled[0]
        S.cfg.config.key_fill_rgb       = ui.key_fill_rgb[0]
        S.cfg.config.key_border_rgb     = ui.key_border_rgb[0]
        S.cfg.config.key_text_rgb       = ui.key_text_rgb[0]
        S.cfg.config.rgb_speed          = ui.rgb_speed[0]
        S.cfg.config.keyboard_type      = ui.keyboard_type[0]
        S.cfg.config.keyboard_scale     = ui.keyboard_scale[0]
        S.cfg.config.keyboard_key_alpha = ui.keyboard_key_alpha[0]
        S.cfg.config.wave_enabled       = ui.wave_enabled[0]
        S.cfg.config.wave_mode          = ui.wave_mode[0]
        S.cfg.config.wave_speed         = ui.wave_speed[0]
        S.cfg.config.wave_transparency  = ui.wave_transparency[0]
        S.cfg.config.wave_target        = ui.wave_target[0]
        S.cfg.config.wave_color_rgb     = ui.wave_color_rgb[0]
        S.cfg.config.wave_random_colors = ui.wave_random_colors[0]
        S.cfg.config.wave_r = ui.wave_color_if4[0]
        S.cfg.config.wave_g = ui.wave_color_if4[1]
        S.cfg.config.wave_b = ui.wave_color_if4[2]
        S.cfg.config.wave_a = ui.wave_color_if4[3]
        S.cfg.config.show_combo_window          = ui.show_combo_window[0]
        S.cfg.config.combo_window_scale         = ui.combo_window_scale[0]
        S.cfg.config.script_enabled             = ui.script_enabled[0]
        S.cfg.config.combo_window_display_mode  = ui.combo_window_display_mode[0]
        S.cfg.config.combo_text_layout_hide_step_px = tonumber(combo_layout_hide_step_px[0]) or 29.9
        S.cfg.config.combo_text_layout_hide_step_adjust_px = tonumber(combo_layout_hide_step_adjust_px[0]) or 0.0
        S.cfg.config.combo_text_layout_gap_extra = tonumber(combo_layout_gap_extra[0]) or 4.0
        S.cfg.config.combo_text_layout_last_stage_threshold_px = tonumber(combo_layout_last_stage_threshold_px[0]) or -16.0
        S.cfg.config.combo_text_layout_bottom_pad = tonumber(combo_layout_bottom_pad[0]) or 8.0
        S.cfg.config.plaque_layout_last_stage_threshold_px = tonumber(plaque_layout_last_stage_threshold_px[0]) or -16.0
        S.cfg.config.plaque_layout_hide_step_adjust_px = tonumber(plaque_layout_hide_step_adjust_px[0]) or 0.0
        S.cfg.config.show_chat_messages         = ui.show_chat_messages[0]
        S.cfg.config.show_logs                  = ui.show_logs[0]
        S.cfg.config.logs_limit_row             = ui.logs_limit_row[0]
        S.cfg.config.logs_max_display           = ui.logs_max_display[0]
        S.cfg.config.logs_style                 = ui.logs_style[0]
        S.cfg.config.logs_reverse               = ui.logs_reverse[0]
        S.cfg.config.logs_combo_rgb             = ui.logs_combo_rgb[0]
        S.cfg.config.language_mode              = ui.language_mode[0]
        S.cfg.config.interface_alpha            = ui.interface_alpha[0]
        S.cfg.config.interface_lang             = ui.interface_lang[0]
        S.cfg.config.space_as_shift             = ui.space_as_shift[0]
        S.cfg.config.recoil_enabled             = ui.recoil_enabled[0]
        S.cfg.config.recoil_line_thickness      = ui.recoil_line_thickness[0]
        S.cfg.config.recoil_show_line           = ui.recoil_show_line[0]
        S.cfg.config.recoil_flash_duration      = ui.recoil_flash_duration[0]
        S.cfg.config.recoil_flash_alpha         = ui.recoil_flash_alpha[0]
        S.cfg.config.recoil_correct             = S.state.recoil_correct or 0
        S.cfg.config.recoil_incorrect           = S.state.recoil_incorrect or 0
        S.cfg.config.recoil_ring_height         = Data.recoil_ring.height
        S.cfg.config.shotmap_enabled            = ui.shotmap_enabled[0]
        S.cfg.config.shotmap_session_size       = ui.shotmap_session_size[0]
        S.cfg.combo.x = ui.combo_pos.x;  S.cfg.combo.y = ui.combo_pos.y
        S.cfg.combo.w = ui.combo_size.x; S.cfg.combo.h = ui.combo_size.y
        S.cfg.logs.x  = ui.logs_pos.x;   S.cfg.logs.y  = ui.logs_pos.y
        S.cfg.logs.w  = ui.logs_size.x;  S.cfg.logs.h  = ui.logs_size.y
        S.cfg.space.x = ui.space_pos.x;  S.cfg.space.y = ui.space_pos.y
        S.cfg.neon.smooth_close    = Data.neon_smooth_close[0]
        S.cfg.neon.font_idx        = neon.current_font_idx[0]
        S.cfg.neon.win_w           = math.floor(neon.window_size.w)
        S.cfg.neon.win_h           = math.floor(neon.window_size.h)
        S.cfg.neon.base_r          = neon_fx.global_base_color[1]; S.cfg.neon.base_g = neon_fx.global_base_color[2]
        S.cfg.neon.base_b          = neon_fx.global_base_color[3]; S.cfg.neon.base_a = neon_fx.global_base_color[4] or 0.95
        S.cfg.neon.border_r        = neon_fx.neon_border_color[1];  S.cfg.neon.border_g = neon_fx.neon_border_color[2]
        S.cfg.neon.border_b        = neon_fx.neon_border_color[3];  S.cfg.neon.border_a = neon_fx.neon_border_color[4] or 0.66
        S.cfg.neon.button_border_r  = neon_fx.button_border_color[1]; S.cfg.neon.button_border_g = neon_fx.button_border_color[2]
        S.cfg.neon.button_border_b  = neon_fx.button_border_color[3]; S.cfg.neon.button_border_a = neon_fx.button_border_color[4] or 0.6
        S.cfg.neon.tabs_r          = neon_fx.tabs_color[1];  S.cfg.neon.tabs_g = neon_fx.tabs_color[2]
        S.cfg.neon.tabs_b          = neon_fx.tabs_color[3];  S.cfg.neon.tabs_a = neon_fx.tabs_color[4] or 1
        S.cfg.neon.title_r         = neon_fx.title_color[1]; S.cfg.neon.title_g = neon_fx.title_color[2]
        S.cfg.neon.title_b         = neon_fx.title_color[3]; S.cfg.neon.title_a = neon_fx.title_color[4] or 1
        S.cfg.neon.cross_r         = neon_fx.icon_cross_color[1]; S.cfg.neon.cross_g = neon_fx.icon_cross_color[2]
        S.cfg.neon.cross_b         = neon_fx.icon_cross_color[3]; S.cfg.neon.cross_a = neon_fx.icon_cross_color[4] or 1
        S.cfg.neon.eye_r           = neon_fx.icon_eye_color[1];   S.cfg.neon.eye_g  = neon_fx.icon_eye_color[2]
        S.cfg.neon.eye_b           = neon_fx.icon_eye_color[3];   S.cfg.neon.eye_a  = neon_fx.icon_eye_color[4] or 1
        S.cfg.neon.gear_r          = neon_fx.icon_gear_color[1];  S.cfg.neon.gear_g = neon_fx.icon_gear_color[2]
        S.cfg.neon.gear_b          = neon_fx.icon_gear_color[3];  S.cfg.neon.gear_a = neon_fx.icon_gear_color[4] or 1
        S.cfg.neon.resize_r        = neon_fx.icon_resize_color[1]; S.cfg.neon.resize_g = neon_fx.icon_resize_color[2]
        S.cfg.neon.resize_b        = neon_fx.icon_resize_color[3]; S.cfg.neon.resize_a = neon_fx.icon_resize_color[4] or 0.67
        S.cfg.neon.sec_icon_r      = neon_fx.section_icon_color[1]; S.cfg.neon.sec_icon_g = neon_fx.section_icon_color[2]
        S.cfg.neon.sec_icon_b      = neon_fx.section_icon_color[3]; S.cfg.neon.sec_icon_a = neon_fx.section_icon_color[4] or 1.0
        S.cfg.neon.tab_icon_r      = neon_fx.tab_icon_color[1]; S.cfg.neon.tab_icon_g = neon_fx.tab_icon_color[2]
        S.cfg.neon.tab_icon_b      = neon_fx.tab_icon_color[3]; S.cfg.neon.tab_icon_a = neon_fx.tab_icon_color[4] or 1.0
        S.cfg.neon.sel_r           = neon_fx.selection_color[1];   S.cfg.neon.sel_g    = neon_fx.selection_color[2]
        S.cfg.neon.sel_b           = neon_fx.selection_color[3];   S.cfg.neon.sel_a    = neon_fx.selection_color[4] or 1.0
        S.cfg.neon.pryanix_r       = neon_fx.pryanix_color[1];    S.cfg.neon.pryanix_g = neon_fx.pryanix_color[2]
        S.cfg.neon.pryanix_b       = neon_fx.pryanix_color[3];    S.cfg.neon.pryanix_a = neon_fx.pryanix_color[4] or 1.0
        S.cfg.neon.title_main_r    = neon_fx.title_main_color[1]; S.cfg.neon.title_main_g = neon_fx.title_main_color[2]
        S.cfg.neon.title_main_b    = neon_fx.title_main_color[3]; S.cfg.neon.title_main_a = neon_fx.title_main_color[4] or 1.0
        S.cfg.neon.recoil_flash_r  = neon_fx.recoil_flash_color[1]; S.cfg.neon.recoil_flash_g = neon_fx.recoil_flash_color[2]
        S.cfg.neon.recoil_flash_b  = neon_fx.recoil_flash_color[3]; S.cfg.neon.recoil_flash_a = neon_fx.recoil_flash_color[4] or 1.0
        S.cfg.neon.sparks_on       = neon_fx.sparks_on[0]
        S.cfg.neon.sparks_speed    = neon_fx.sparks_speed[0]; S.cfg.neon.sparks_size = neon_fx.sparks_size[0]
        S.cfg.neon.cursor_fx       = neon_fx.cursor_fx_var[0]
        S.cfg.neon.sparks_r        = neon_fx.sparks_color[1]; S.cfg.neon.sparks_g = neon_fx.sparks_color[2]
        S.cfg.neon.sparks_b        = neon_fx.sparks_color[3]; S.cfg.neon.sparks_a = neon_fx.sparks_color[4] or 1
        S.cfg.neon.waves_on        = neon_fx.waves_on[0]
        S.cfg.neon.waves_speed     = neon_fx.waves_speed[0]; S.cfg.neon.waves_var = neon_fx.waves_var[0]
        S.cfg.neon.waves_r         = neon_fx.waves_color[1]; S.cfg.neon.waves_g = neon_fx.waves_color[2]
        S.cfg.neon.waves_b         = neon_fx.waves_color[3]; S.cfg.neon.waves_a = neon_fx.waves_color[4] or 1
        S.cfg.neon.ambient_on      = neon_fx.ambient_on[0]
        S.cfg.neon.ambient_speed   = neon_fx.ambient_speed[0]; S.cfg.neon.ambient_var = neon_fx.ambient_var[0]
        S.cfg.neon.ambient1_r      = neon_fx.ambient_color_1[1]; S.cfg.neon.ambient1_g = neon_fx.ambient_color_1[2]
        S.cfg.neon.ambient1_b      = neon_fx.ambient_color_1[3]; S.cfg.neon.ambient1_a = neon_fx.ambient_color_1[4] or 1
        S.cfg.neon.ambient2_r      = neon_fx.ambient_color_2[1]; S.cfg.neon.ambient2_g = neon_fx.ambient_color_2[2]
        S.cfg.neon.ambient2_b      = neon_fx.ambient_color_2[3]; S.cfg.neon.ambient2_a = neon_fx.ambient_color_2[4] or 1
       Lib.inicfg.save(S.cfg, Data.iniFile)
    end
end
CB.neon = neon
CB.fx   = neon_fx
CB.ui   = ui
CB.interface_alpha = ui.interface_alpha
CB.Lib, CB.Fn, CB.Data, CB.state = Lib, Fn, Data, S.state
end

function sampev.onSendBulletSync(data)
    if SC_onSendBulletSync then pcall(SC_onSendBulletSync, data) end
    if CBUGER_HM_onSendBulletSync then pcall(CBUGER_HM_onSendBulletSync, data) end
    if CBUGSPEED_onSendBulletSync then pcall(CBUGSPEED_onSendBulletSync, data) end
    if CBUGER_BOARD_onSendBulletSync then pcall(CBUGER_BOARD_onSendBulletSync, data) end
    if CBUGER_OT_onSendBulletSync then pcall(CBUGER_OT_onSendBulletSync, data) end
end

function sampev.onSendGiveDamage(playerId, damage, weapon, bodypart)
    if CBUGSPEED_onSendGiveDamage then pcall(CBUGSPEED_onSendGiveDamage, playerId, damage, weapon, bodypart) end
end

local function cbuger_toggle_window()
    if type(CB) == 'table' and CB.neon and CB.neon.target_main then
        CB.neon.target_main[0] = not CB.neon.target_main[0]
        imgui.Process = true
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    CBUGER_RUNTIME_READY = false
    CBUGER_NATIVE_READY  = false
    CBUGER_RENDER_READY  = false

    local stable_ticks = 0
    while stable_ticks < 10 do
        if CBUGER_IS_GAME_STABLE() then
            stable_ticks = stable_ticks + 1
        else
            stable_ticks = 0
        end
        wait(100)
    end

    CBUGER_RUNTIME_READY = true
    CBUGER_NATIVE_READY  = true
    CBUGER_RENDER_READY  = true

    wait(500)
    sampRegisterChatCommand('cbuger', cbuger_toggle_window)
    lua_thread.create(CB.run)

    sampAddChatMessage(CB.Fn.L('{00CCFF}[CBUGER]{FFFFFF} Загружен. Меню: {00CCFF}/cbg{FFFFFF} (или /cbuger)', '{00CCFF}[CBUGER]{FFFFFF} Loaded. Menu: {00CCFF}/cbg{FFFFFF} (or /cbuger)'), -1)

    while true do
        wait(1000)
        if CBUGER_RETRY_PENDING_WRITES then pcall(CBUGER_RETRY_PENDING_WRITES) end
    end
end

function onScriptTerminate(script, quit_game)
    if script == thisScript() then
        pcall(function() imgui.Process = false end)
        pcall(sampSetCursorMode, 0)
        pcall(CB.terminate, script)
        pcall(function() if Data_hm_save then Data_hm_save() end; if Data_cbug_save_stats then Data_cbug_save_stats() end; if Data_board_save then Data_board_save() end end)
        pcall(CBUGER_RETRY_PENDING_WRITES, true)
        pcall(CBUGER_RESTORE_IMGUI_TRANSLATION_PATCH)
        pcall(CBUGER_RESTORE_SHOWCURSOR_PATCH)
    end
end
