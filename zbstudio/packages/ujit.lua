local function prequire(m)
  local ok, mod = pcall(require, m)
  if ok then return mod, m end
  return nil, mod
end

local function print(...)
  ide:Print(...)
end

local function printf(...)
  print(string.format(...))
end

local interpreter = {
  name = "uJIT",
  description = "uJIT interpreter",
  api = {"baselib", "sample", "userver"},
  luaversion = '5.1',
  hasdebugger = true,

  frun = function(self, wfilename, rundebug)
    local exe = 'ujit'
    local filepath = wfilename:GetFullPath()

    if ide.osname == 'Windows' then
      -- if running on Windows and can't open the file, this may mean that
      -- the file path includes unicode characters that need special handling
      local fh = io.open(filepath, "r")
      if fh then fh:close() else
        local winapi = prequire "winapi"
        if winapi and wfilename:FileExists() then
          winapi.set_encoding(winapi.CP_UTF8)
          local shortpath = winapi.short_path(filepath)
          if shortpath == filepath then
            printf(
              "Can't get short path for a Unicode file name '%s' to open the file.",
              filepath)
            printf(
              "You can enable short names by using `fsutil 8dot3name set %s: 0` and recreate the file or directory.",
              wfilename:GetVolume())
          end
          filepath = shortpath
        end
      end
    end

    if rundebug then
      ide:GetDebugger():SetOptions({runstart = ide.config.debugger.runonstart == true})

      -- update arg to point to the proper file
      rundebug = ('if arg then arg[0] = [[%s]] end '):format(filepath) .. rundebug

      local tmpfile = wx.wxFileName()
      tmpfile:AssignTempFileName(".")
      filepath = tmpfile:GetFullPath()
      local f, e = io.open(filepath, "w")
      if not f then
        printf(
          "Can't open temporary file '%s' for writing: %s.",
          filepath, e or 'unknown error')
        return
      end
      f:write(rundebug)
      f:close()
    end

    local params = self:GetCommandLineArg("lua")
    local code = ([[-e "io.stdout:setvbuf('no')" "%s"]]):format(filepath)
    local cmd = '"'..exe..'" '..code..(params and " "..params or "")

    -- CommandLineRun(cmd,wdir,tooutput,nohide,stringcallback,uid,endcallback)
    local pid = CommandLineRun(cmd,self:fworkdir(wfilename),true,false,nil,nil,
      function() if rundebug then wx.wxRemoveFile(filepath) end end)

    return pid
  end,
}

return {
  name = "ujit",
  description = "uJIT",
  author = "Alexey Melnichuk",
  version = 0.15,

  onRegister = function(self)
    ide:AddInterpreter("ujit", interpreter)
  end,

  onUnRegister = function(self)
    ide:RemoveInterpreter("ujit")
  end,
}
