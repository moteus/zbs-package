local HotKeys = package_require 'hotkeys.manager'

return {
  name = "HotKeys",
  description = "Support single place to manage all hot keys for all plagins.",
  author = "Alexey Melnichuk",
  version = '0.0.1',
  dependencies = "1.70",

  onRegister = function(package)end,

  onUnRegister = function(package)
    error('can not be unloaded')
  end,

  onEditorKeyDown = function(self, editor, event)
    return HotKeys:onEditorKeyDown(editor, event)
  end,

  onEditorKey = function(self, editor, event)
    return HotKeys:onEditorKey(editor, event)
  end,

  -- TODO need this in case of show current chain in status bar
  -- onIdle = function(self, editor, event)
  --   return HotKeys:onIdle(editor, event)
  -- end,
}

-- 1. How to detect that chain is failed? Currently I detect 
--   * hit escape key
--   * timeout for 5 second after last hot keys handler
--   * change current editor or cursor position (e.g mouse click tab)
--   * press any key (symbol excluding shift)

-- 2. How to handle hot key in case of failed chain? E.e. we have 
-- shortcuts `Ctrl-K Ctrl-M` and `Ctrl-J` and user enters `Ctrl-K Ctrl-J` sequence. Should we just
-- clear chain after `Ctrl-J` or we should try to handle `Ctrl-J` as a regular hot key?
-- Currently module try to find handler and if there no such it trying to set it as a new chain
