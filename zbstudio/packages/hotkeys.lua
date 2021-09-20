local HotKeys = package_require 'hotkeys.manager'

return {
  name = "HotKeys",
  description = "Support single place to manage all hot keys for all plagins.",
  author = "Alexey Melnichuk",
  version = '0.0.2',
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

  onIdle = function(self, editor, event)
    return HotKeys:onIdle(editor, event)
  end,

  onEditorUpdateUI = function(self, editor, event)
    return HotKeys:onEditorUpdateUI(editor, event)
  end,
}
