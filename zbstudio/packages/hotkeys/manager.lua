local KEYMAP = {} do
  local config = ide:GetConfig()
  for _, key in pairs(config and config.keymap or {}) do
    KEYMAP[key] = true
  end
end

local HotKeyToggle = package_require 'hotkeys.hot_key_toggle'

local Keys = {}
Keys.__index = Keys

function Keys.new(class)
  local self = setmetatable({}, class)

  self:_reset()
  self.wait_interval = 30 -- Wait next key

  return self
end

function Keys:_reset()
  self.hot_keys     = {}
  self.chain        = ''
  self.chain_node   = self
  self.last_pos     = nil
  self.last_editor  = nil
  self.last_time    = nil
  self._keys        = {}
end

function Keys:_current_status(editor)
  editor = editor or ide:GetEditor()
  return editor, editor and editor:GetCurrentPos()
end

function Keys:clear_chain()
  if self.chain == '' then
    return
  end
  self.chain       = ''
  self.chain_node  = self
  self.last_time   = nil
  self.last_editor = nil
  self.last_pos    = nil
  ide:SetStatus('')
end

function Keys:is_chain_valid(editor)
  if self.chain == '' then
    return true
  end

  local interval = self:interval()
  if interval > self.wait_interval then
    return false
  end

  local e, p = self:_current_status(editor)

  if self.last_editor ~= e then
    return false
  end

  if self.last_pos ~= p then
    return false
  end

  return true
end

function Keys:set_chain(key, node)
  if self.chain == '' then
    self.chain = key
  else
    self.chain = self.chain .. ':' .. key
  end
  self.chain_node   = node
  self.last_time    = os.time()
  self.last_editor, self.last_pos = self:_current_status()
  ide:SetStatus(self.chain)
end

function Keys:interval()
  if not self.last_time then
    return 0
  end

  local now = os.time()
  if self.last_time > now then -- time shift
    return 3600
  end

  return os.difftime(now, self.last_time)
end

function Keys:handler(key)
  if not self:is_chain_valid() then
    self:clear_chain()
  end

  for i = 1, 2 do
    local node = self.chain_node._keys[key]
    if node then
      if node.is_last then
        self:clear_chain()
      else
        self:set_chain(key, node)
      end
      if node.action then
        node.action()
      end
      return true
    end
    if self.chain_node == self then
      break
    end
    self:clear_chain()
  end

  self:clear_chain()
  return false
end

function Keys:normalize_key(key)
  if #key == 1 then
    return key
  end

  -- Ctrl+A => CTRL-A
  return string.upper(key):gsub('%+', '-')
end

function Keys:get_package_by_key(key)
  for package, info in pairs(self.packages) do
    if info.full_keys[key] then
      return package
    end
  end
end

-- In the single chain actions can be belong to only one package
-- e.g. if Ctrl-K set by package 1 then only this package can set `Ctrl-K M`
-- But in package 1 set `Ctrl-K M` then any other package can set `Ctrl-K N`
-- TODO: Chain interrupt event

local function iter(root)
  coroutine.yield(root)
  if root._keys then
    for _, node in pairs(root._keys) do
      iter(node)
    end
  end
end

local function key_iterator(root)
  return coroutine.wrap(iter), root
end

function Keys:add_node(root, package, key, handler, ide_override, is_last)
  if KEYMAP[key] and not ide_override then
    return error(string.format("Fail to set hotkey %s for the package '%s'. Hotkey alrady has action in the IDE config", key, package and package.name or 'UNKNOWN'), 2)
  end

  local norm_key  = self:normalize_key(key)
  local full_key  = root.full_key  and root.full_key  .. ':' .. norm_key or norm_key
  local chain_key = root.chain_key and root.chain_key .. ' ' .. key or key

  local node = root._keys[norm_key] or {
    is_last   = is_last,
    full_key  = full_key,
    norm_key  = norm_key,
    chain_key = chain_key,
    key       = key,
    _keys     = {},
  }

  if is_last or node.action then
    for node in key_iterator(node) do
      if node.action and node.package ~= package then
        local package_name = node.package.name or 'UNKNOWN'
        return error(string.format(
            "Fail to set hotkey %s for the package '%s'. Hotkey '%s' alrady has an action for the package '%s'",
            key, package and package.name or 'UNKNOWN', node.chain_key , package_name),
        2)
      end
    end
  end

  if not is_last then
    node.is_last = false
  end

  root._keys[norm_key] = node

  if is_last then
    node.action  = handler
    node.package = package
  end

  -- create internal handler
  if #norm_key > 1 then
    if not self.hot_keys[norm_key] then
      self.hot_keys[norm_key] = HotKeyToggle:new(key):set(function() self:handler(norm_key) end)
    end
  end

  return node
end

function Keys:add(package, keys, handler, ide_override)
  assert(handler, 'no handler')

  if type(keys) == 'string' then
    local t = {}
    for k in string.gmatch(keys, '[^%s,]+') do
      table.insert(t, k)
    end
    keys = t
  end

  local tree = self
  for i, key in ipairs(keys) do
    tree = self:add_node(tree, package, key, handler, ide_override, i == #keys)
  end
end

local function remove_key(self, root, key)
  local node = root._keys[key]
  local hot_key = self.hot_keys[node.norm_key]
  if hot_key then
    hot_key:unset()
  end
  root._keys[key] = nil
end

local function remove_package(self, root, package)
  for key, node in pairs(root._keys) do
    if node.package == package then
      remove_key(self, root, key)
    else
      remove_package(self, node, package)
      if not next(node._keys) then
        remove_key(self, root, key)
      end
    end
  end
end

function Keys:close_package(package)
  assert(package ~= nil)
  for key, node in pairs(self._keys) do
    remove_package(self, self, package)
  end
end

function Keys:close()
  for _, hot_key in pairs(self.hot_keys) do
    hot_key:unset()
  end

  self:_reset()
end

-- Event Provided by onchar plugin
function Keys:onEditorKey(editor, event)
  if self.chain == '' then
    return true
  end

  local modifier = event:GetModifiers()
  if not (modifier == 0 or modifier == wx.wxMOD_SHIFT) then
    return true
  end

  local code = event:GetKeyCode()
  if code == 0 or code == nil or code == wx.WXK_SHIFT then
    return true
  end

  if code > 255 then
    self:clear_chain()
    return true
  end

  local key = string.char(code)
  if self:handler(key) then
    return false
  end

  return true
end

function Keys:onEditorKeyDown(editor, event)
  if self.chain == '' then
    return true
  end

  local modifier = event:GetModifiers()
  if modifier == 0 and event:GetKeyCode() == wx.WXK_ESCAPE then
    self:clear_chain()
    return true
  end

  if not self:is_chain_valid() then
    self:clear_chain()
  end

  return true
end

function Keys:onIdle(editor, event)
  if self.chain == '' then
    return
  end

  if not self:is_chain_valid() then
    self:clear_chain()
  end
end

function Keys:onEditorUpdateUI(editor, event)
  if self.chain == '' then
    return
  end

  if not self:is_chain_valid() then
    self:clear_chain()
  end
end

return Keys:new()
