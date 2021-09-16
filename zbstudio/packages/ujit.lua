--! @todo use editor.spec.lexer / editor:GetLexer()
local LEXERS_EXT = {
    perl = {
        '.pl', '.pm',
    };

    go_run = {
        '.go'
    };

    python_docker = {
        '.py'
    };

    prove = {
        '.t', '.tt'
    };

    jq = {
        '.json'
    };
}

local function os_command(t)
    return t[ide.osname:upper()] or t[1]
end

local function docker_command(cmd)
    return os_command{
        "exec {DOCKER_NAME} su - {DOCKER_USER} -c 'cd {PROJECT_DIR} && " .. cmd .. "'",
        WINDOWS = "exec {DOCKER_NAME} bash -c '\"" .. cmd .. "\"'";
    }
end

local APPS = {
    lua  = {'lua',
        lexer      = 'lua',
        app        = 'ujit',
    };

    perl = {'general',
        lexer      = 'perl',
        app        = 'perl',
        app_params = '-w "{FILE}"',
    };

    go_run = {'general',
        lexer      = 'go',
        app        = 'go',
        app_params = 'run "{FILE}"',
    };

    go_test = {'general',
        lexer      = 'go',
        app        = 'go',
        app_params = 'test -v "{FILE}"',
    };

    python = {'general',
        lexer      = 'python',
        app        = 'python3',
        app_params = '"{FILE}"',
    };

    python_docker = {'general',
        lexer      = 'python',
        app        = 'docker',
        app_params = docker_command 'python3 "{FILE}"'
    };

    prove = {'general',
        lexer      = 'perl',
        app        = 'docker',
        app_params = docker_command 'prove "{FILE}"',
    };

    jq = {'general',
        lexer      = 'json',
        app        = 'jq',
        app_params = '. "{FILE}"',
    };
}

local INTERPRETER = {
  name           = "uJIT",
  description    = "uJIT interpreter",
  api            = {"baselib", "sample", "userver"},
  luaversion     = '5.1',
  hasdebugger    = true,
  takeparameters = true,
}

local Package = {
  name        = "ujit",
  description = "uJIT",
  author      = "Alexey Melnichuk",
  version     = 0.17,
}

-----------------------------------------------------------------------------

local function prequire(m)
    local ok, mod = pcall(require, m)
    if ok then return mod, m end
    return nil, mod
end

local print = function(...)
    ide:Print(...)
end

local function printf(...)
    print(string.format(...))
end

local function apply_macros(str, macro)
    return (string.gsub(str, '{(.-)}', macro))
end

local function get(t, ...)
    for i = 1, select('#', ...) do
        local key = select(i, ...)
        if key == nil then
            return nil
        end
        if t == nil then
            return nil
        end
        t = t[key]
    end
    return t
end

local function GetFullPath(path)
    local filepath = path:GetFullPath()

    if ide.osname == 'Windows' then
        -- if running on Windows and can't open the file, this may mean that
        -- the file path includes unicode characters that need special handling
        local fh = io.open(filepath, "r")
        if fh then fh:close() else
            local winapi = prequire "winapi"
            if winapi and path:FileExists() then
                winapi.set_encoding(winapi.CP_UTF8)
                local shortpath = winapi.short_path(filepath)
                if shortpath == filepath then
                    printf(
                        "Can't get short path for a Unicode file name '%s' to open the file.",
                        filepath
                    )
                    printf(
                        "You can enable short names by using `fsutil 8dot3name set %s: 0` and recreate the file or directory.",
                        path:GetVolume()
                    )
                end
                filepath = shortpath
            end
        end
    end

    return filepath
end

local function CreateTempFile(startup_code)
    local tmpfile = wx.wxFileName()
    tmpfile:AssignTempFileName(".")
    local filepath = tmpfile:GetFullPath()
    local f, e = io.open(filepath, "w")
    if not f then
        printf(
            "Can't open temporary file '%s' for writing: %s.",
            filepath, e or 'unknown error'
        )
        return
    end
    f:write(startup_code)
    f:close()
    return filepath
end

local EXT_TO_LEXER = {}
for lexer, extensions in pairs(LEXERS_EXT) do
    for _, extension in ipairs(extensions) do
        EXT_TO_LEXER[extension] = lexer
    end
end

local function GetLexerName(path)
    local ext = path:GetExt() or ''
    if string.find(ext, '^[^.]') then
        ext = '.' .. ext
    end

    if ide.osname == 'Windows' then
        ext = string.lower(ext)
    end

    local name = path:GetFullName()
    if name and name:find('lua_unit+[A-Za-z_%d]+%.lua$') then
        return 'prove'
    end

    if name and name:find('_test%.go$') then
        return 'go_test'
    end

    return EXT_TO_LEXER[ext] or 'lua'
end

local function GeneralRunner(lexer, app, app_params, params)
    params = params and (params .. ' ') or ''

    return function(self, wfilename, rundebug)
        -- do not support debug
        if rundebug then
            printf('ZeroBraneStudio does not support debug `%s` code', lexer)
            return
        end

        local filepath = GetFullPath(wfilename)

        -- this parameters for script not for interpreter
        local params = params .. (self:GetCommandLineArg(lexer) or '')

        local app_params = apply_macros(app_params, {
            FILE        = filepath,
            DOCKER_USER = get(ide.config, 'iponweb', 'lua_dev', 'docker', 'user'),
            DOCKER_NAME = get(ide.config, 'iponweb', 'lua_dev', 'docker', 'container'),
            PROJECT_DIR = get(ide.config, 'iponweb', 'lua_dev', 'path'),
        })

        -- build command line string
        local cmd = string.format([["%s" %s %s]],
            app, app_params or '', params or ''
        )

        local cwd    = self:fworkdir(wfilename)

        -- CommandLineRun(cmd,wdir,tooutput,nohide,stringcallback,uid,endcallback)
        local pid = CommandLineRun(
            cmd,    -- command
            cwd,    -- work directory
            true,   -- to output
            false,  -- `true` - Show console window
            nil,    -- String callback
            nil,    -- uid
            nil     -- End callback
        )

        return pid
    end
end

local function GeneralLuaRunner(lexer, app, app_params, params)
    app_params = app_params or [[-e "io.stdout:setvbuf('no')"]]
    params = params and (params .. ' ') or ''

    return function(self, wfilename, rundebug)
        local filepath = GetFullPath(wfilename)

        local cleanup
        if rundebug then
            local startup_code = ('if arg then arg[0] = [[%s]] end ')
                :format(filepath) .. rundebug

            filepath = CreateTempFile(startup_code)
            if not filepath then return end

            cleanup = function() wx.wxRemoveFile(filepath) end

            -- get file form configuration file
            local runonstart = (ide.config.debugger.runonstart == true)

            ide:GetDebugger():SetOptions({runstart = runonstart})
        end

        -- this parameters for script not for interpreter
        local params = params .. (self:GetCommandLineArg(lexer) or '')

        -- build command line string
        local cmd = string.format([["%s" %s "%s" %s]],
            app, app_params or '', filepath, params or ''
        )

        local cwd    = self:fworkdir(wfilename)

        -- CommandLineRun(cmd,wdir,tooutput,nohide,stringcallback,uid,endcallback)
        local pid = CommandLineRun(
            cmd,    -- command
            cwd,    -- work directory
            true,   -- to output
            false,  -- `true` - Show console window
            nil,    -- String callback
            nil,    -- uid
            cleanup -- End callback
        )

        return pid
    end
end

local INTERPRETERS

INTERPRETER.frun = function(self, wfilename, rundebug)
    local lexer = GetLexerName(wfilename)
    local interpreter = INTERPRETERS[lexer]
    if interpreter then
        return interpreter(self, wfilename, rundebug)
    end
end

Package.onRegister = function(self)
    INTERPRETERS = {}

    for lexer, params in pairs(APPS) do
        local Runner = (params[1] == 'general')
            and GeneralRunner or GeneralLuaRunner
        INTERPRETERS[lexer] = Runner(
            lexer,
            params.app,
            params.app_params,
            params.params
        )
    end

    ide:AddInterpreter(Package.name, INTERPRETER)
end

Package.onUnRegister = function(self)
    ide:RemoveInterpreter(Package.name)
    INTERPRETERS = nil
end

return Package
