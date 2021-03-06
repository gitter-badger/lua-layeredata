local coromake = require "coroutine.make"
local c3       = require "c3"

local Layer = setmetatable ({}, {
  __tostring = function () return "Layer" end
})
local Proxy = setmetatable ({}, {
  __tostring = function () return "Proxy" end
})
local Reference = setmetatable ({}, {
  __tostring = function () return "Reference" end
})
local Key = setmetatable ({}, {
  __tostring = function () return "Key" end
})

local IgnoreKeys   = { __mode = "k" }
local IgnoreValues = { __mode = "v" }

local Read_Only = {
  __index    = assert,
  __newindex = assert,
}

Reference.memo = setmetatable ({}, IgnoreValues)

Layer.key = setmetatable ({
  checks   = setmetatable ({}, Key),
  default  = setmetatable ({}, Key),
  labels   = setmetatable ({}, Key),
  messages = setmetatable ({}, Key),
  meta     = setmetatable ({}, Key),
  refines  = setmetatable ({}, Key),
}, Read_Only)

Layer.tag = setmetatable ({
  null      = {},
  computing = {},
}, Read_Only)

function Layer.new (t, options)
  assert (type (t) == "table")
  assert (options == nil or type (options) == "table")
  options = options or {}
  local layer = setmetatable ({
    __name    = t.name,
    __data    = Layer.import (t.data or {}),
    __root    = false,
    __proxies = setmetatable ({}, IgnoreValues),
    __debug   = options.debug,
    __indent  = {},
  }, Layer)
  local proxy = Proxy.__new (layer)
  layer.__root = proxy
  return proxy
end

function Layer.clear_caches (proxy)
  assert (proxy == nil or getmetatable (proxy) == Proxy)
  if proxy and proxy.__layer.__debug then
    print ("Clear Caches:", proxy)
  end
  Proxy.refines:clear ()
  Layer.caches = {
    index   = setmetatable ({}, IgnoreKeys),
    pairs   = setmetatable ({}, IgnoreKeys),
    ipairs  = setmetatable ({}, IgnoreKeys),
    len     = setmetatable ({}, IgnoreKeys),
    check   = setmetatable ({}, IgnoreKeys),
    perform = {
      noiterate_noresolve = setmetatable ({}, IgnoreKeys),
      noiterate_resolve   = setmetatable ({}, IgnoreKeys),
    },
  }
end

function Layer.import (data, ref, seen)
  if not ref then
    ref = Reference.new (false)
  end
  if not seen then
    seen = {}
  end
  if getmetatable (data) == Key then
    return data
  end
  if seen [data] then
    return seen [data]
  end
  local result
  if type (data) ~= "table" then
    return data
  elseif getmetatable (data) == Proxy then
    return data
  elseif getmetatable (data) == Reference then
    result = data
  elseif data.__proxy then
    assert (#data == 0)
    result = Proxy.layerof (data.__layer)
  elseif data.__reference then
    local reference = Reference.new (data.__from)
    for i = 1, #data do
      reference = reference [data [i]]
    end
    result = reference
  else
    seen [data] = ref
    local updates = {}
    for key, value in pairs (data) do
      if type (key  ) == "table" then
        updates [key] = Layer.import (key, ref, seen)
      end
      if type (value) == "table" then
        data    [key] = Layer.import (value, ref [key], seen)
      end
    end
    for old_key, new_key in pairs (updates) do
      local value = data [old_key]
      data [old_key] = nil
      data [new_key] = value
    end
    result = data
  end
  if not seen [data] then
    seen [data] = result
  end
  return result
end

function Layer.__tostring (layer)
  assert (getmetatable (layer) == Layer)
  return "layer:" .. tostring (layer.__name)
end

function Proxy.__new (t)
  assert (getmetatable (t) == Layer)
  return setmetatable ({
    __keys   = {},
    __layer  = t,
    __memo   = t.__proxies,
    __parent = false,
    __cache  = true,
  }, Proxy)
end

function Proxy.__tostring (proxy)
  assert (getmetatable (proxy) == Proxy)
  local result = {}
  result [1] = proxy.__layer
           and "<" .. tostring (proxy.__layer.__name) .. ">"
            or "<anonymous layer>"
  local keys = proxy.__keys
  for i = 1, #keys do
    result [i+1] = "[" .. tostring (keys [i]) .. "]"
  end
  return table.concat (result, " ")
end

function Layer.decode (string, layers)
  layers = layers or {}
  local loaded = assert (loadstring (string))
  local func   = assert (loaded ())
  return func (Proxy, layers)
end

function Layer.encode (proxy)
  assert (getmetatable (proxy) == Proxy)
  local key_name = {}
  for k, v in pairs (Layer.key) do
    key_name [v] = k
  end
  local function convert (x, is_key, indent)
    indent = indent or ""
    if getmetatable (x) == Key then
      return is_key
         and indent .. "[" .. key_name [x] .. "]"
          or key_name [x]
    elseif getmetatable (x) == Reference then
      assert (not is_key)
      local result = "Layer.reference ("
        .. (x.__from and string.format ("%q", x.__from) or tostring (x.__from))
        .. ")"
      for _, y in ipairs (x.__keys) do
        result = result .. " [" .. convert (y) .. "]"
      end
      return result
    elseif getmetatable (x) == Proxy then
      assert (not is_key)
      local result = "Layers [" .. string.format ("%q", x.__layer.__name) .. "]"
      for _, y in ipairs (x.__keys) do
        result = result .. " [" .. convert (y) .. "]"
      end
      return result
    elseif type (x) == "table" then
      assert (not is_key)
      local subresults = {}
      local seen       = {}
      local nindent    = indent .. "  "
      for k, v in pairs (x) do
        if getmetatable (k) == Key then
          subresults [#subresults+1] = convert (k, true, nindent) .. " = " .. convert (v, false, nindent)
          seen [k] = true
        end
      end
      for k, v in ipairs (x) do
        subresults [#subresults+1] = nindent .. convert (v, false, nindent)
        seen [k] = true
      end
      for _, oftype in ipairs { "number", "boolean", "string" } do
        for k, v in pairs (x) do
          if type (k) == oftype and not seen [k] then
            subresults [#subresults+1] = convert (k, true, nindent) .. " = " .. convert (v, false, nindent)
            seen [k] = true
          end
        end
      end
      for k in pairs (x) do
        assert (seen [k])
      end
      return "{\n" .. table.concat (subresults, ",\n") .. "\n" .. indent .. "}"
    elseif type (x) == "string" then
      return is_key
         and indent .. (x:match "^[_%a][_%w]*$" and x or "[" .. string.format ("%q", x) .. "]")
          or string.format ("%q", x)
    elseif type (x) == "number" then
      return is_key
         and indent .. "[" .. tostring (x) .. "]"
          or tostring (x)
    elseif type (x) == "boolean" then
      return is_key
         and indent .. "[" .. tostring (x) .. "]"
          or tostring (x)
    elseif type (x) == "function" then
      assert (not is_key)
      return indent .. string.format ("%q", string.dump (x))
    else
      assert (false)
    end
  end
  local result = [[
return function (Layer, Layers)
{{{LOCALS}}}
return Layer.new {
  name = {{{NAME}}},
  data = {{{BODY}}},
}
end
  ]]
  local locals    = {}
  local localsize = 0
  for k in pairs (Layer.key) do
    localsize = math.max (localsize, #k)
  end
  for k in pairs (Layer.key) do
    local pad = ""
    for _ = #k+1, localsize do
      pad = pad .. " "
    end
    locals [#locals+1] = "  local " .. k .. pad .. " = Layer.key." .. k
  end
  result = result:gsub ("{{{NAME}}}"  , string.format ("%q", proxy.__layer.__name))
  result = result:gsub ("{{{LOCALS}}}", table.concat (locals, "\n"))
  result = result:gsub ("{{{BODY}}}"  , convert (Proxy.export (proxy), false, "    "))
  return result
end

function Layer.dump (proxy)
  assert (getmetatable (proxy) == Proxy)
  local function convert (x, is_key)
    if getmetatable (x) == Key then
      assert (false)
    elseif getmetatable (x) == Reference then
      assert (not is_key)
      local result = "@" .. x.__from
      for _, y in ipairs (x.__keys) do
        result = result .. " / " .. tostring (convert (y))
      end
      return result
    elseif type (x) == "table" then
      assert (not is_key)
      local subresults = {}
      for k, v in pairs (x) do
        if getmetatable (k) ~= Key then
          subresults [convert (k, true)] = convert (v)
        end
      end
      return subresults
    elseif type (x) == "string" then
      return x
    elseif type (x) == "number" then
      return x
    elseif type (x) == "boolean" then
      return x
    elseif type (x) == "function" then
      assert (not is_key)
      local info = debug.getinfo (x)
      assert (info and info.what == "Lua")
      return info.source ..
               " [" .. tostring (info.linedefined) ..
               ".." .. tostring (info.lastlinedefined) ..
                "]"
    else
      assert (false)
    end
  end
  return convert (Proxy.export (proxy))
end

function Proxy.sub (proxy, key)
  assert (getmetatable (proxy) == Proxy)
  local proxies = proxy.__memo
  local found   = proxies [key]
  if not found then
    local cache = true
    local nkeys = {}
    for i = 1, #proxy.__keys do
      nkeys [i] = proxy.__keys [i]
      cache = cache and nkeys [i] ~= Layer.key.messages
    end
    nkeys [#nkeys+1] = key
    cache = cache and key ~= Layer.key.messages
    found = setmetatable ({
      __layer     = proxy.__layer,
      __keys      = nkeys,
      __memo      = setmetatable ({}, IgnoreValues),
      __parent    = proxy,
      __cache     = cache,
    }, Proxy)
    proxies [key] = found
  end
  return found
end

function Proxy.check (proxy)
  assert (getmetatable (proxy) == Proxy)
  local cache = Layer.caches.check
  if cache [proxy] then
    return
  end
  cache [proxy] = true
  for i = 1, #proxy.__keys do
    local key = proxy.__keys [i]
    if key == Layer.key.checks
    or key == Layer.key.default
    or key == Layer.key.labels
    or key == Layer.key.messages
    or key == Layer.key.meta
    or key == Layer.key.refines
    then
      return
    end
  end
  local checks = proxy [Layer.key.checks]
  if not checks then
    return
  end
  local messages = proxy [Layer.key.messages]
  if not messages then
    proxy [Layer.key.messages] = {}
    messages = proxy [Layer.key.messages]
  end
  for _, f in Proxy.__pairs (checks) do
    assert (type (f) == "function")
    local id, message = f (proxy)
    if id ~= nil then
      messages [id] = message
    end
  end
  if Proxy.__pairs (messages) (messages) == nil then
    proxy [Layer.key.messages] = nil
  end
end

function Proxy.__index (proxy, key)
  assert (getmetatable (proxy) == Proxy)
  local layer = proxy.__layer
  proxy = Proxy.sub (proxy, key)
  local cproxy = proxy
  if proxy.__cache then
    local cache  = Layer.caches.index
    local cached = cache [proxy]
    if cached == Layer.tag.null then
      return nil
    elseif cached == Layer.tag.computing then
      return nil
    elseif cached ~= nil then
      return cached
    end
    cache [proxy] = Layer.tag.computing
  end
  if layer.__debug then
    local co = coroutine.running ()
    if not layer.__indent [co] then
      layer.__indent [co] = ""
    end
    local indent = layer.__indent [co]
    print (">", indent .. tostring (proxy))
    layer.__indent [co] = indent .. "  "
  end
  local result
  while true do
    local _, c = Proxy.apply { proxy = proxy, resolve = true, iterate = false, }
    if getmetatable (c) == Proxy then
      proxy = c
    elseif type (c) ~= "table" then
      result = c
      break
    else
      result = proxy
      break
    end
  end
  if proxy.__cache then
    local cache = Layer.caches.index
    if result == nil then
      cache [cproxy] = Layer.tag.null
    else
      cache [cproxy] = result
    end
  end
  if layer.__debug then
    local co     = coroutine.running ()
    local indent = layer.__indent [co]
    layer.__indent [co] = indent:sub (1, #indent-2)
    if layer.__indent [co] == "" then
      layer.__indent [co] = nil
    end
  end
  if getmetatable (result) == Proxy then
    Proxy.check (result)
  end
  return result
end

function Proxy.__newindex (proxy, key, value)
  assert (getmetatable (proxy) == Proxy)
  assert ( type (key) ~= "table"
        or getmetatable (key) == Proxy
        or getmetatable (key) == Reference
        or getmetatable (key) == Key)
  proxy = Proxy.sub (proxy, key)
  key   = Layer.import (key  )
  value = Layer.import (value)
  local p, r = Proxy.apply { proxy = proxy, resolve = false, iterate = false, }
  if r == nil then
    p = proxy
  elseif getmetatable (r) == Reference and getmetatable (value) ~= Reference then
    p = Reference.resolve (r, proxy)
  end
  local current = proxy.__layer.__data
  local keys    = p.__keys
  for i = 1, #keys-1 do
    local k = keys [i]
    if current [k] == nil then
      current [k] = {}
    end
    current = current [k]
  end
  current [key] = value
  if proxy.__cache then
    Layer.clear_caches (proxy)
  end
end

function Proxy.replacewith (proxy, value)
  assert (getmetatable (proxy) == Proxy)
  Layer.clear_caches (proxy)
  value = Layer.import (value)
  local layer = proxy.__layer
  local keys  = proxy.__keys
  if #keys == 0 then
    assert (type (value) == "table")
    layer.__data = value
  else
    local current = layer.__data
    for i = 1, #keys-1 do
      current = current [keys [i]]
      assert (type (current) == "table" and getmetatable (current) ~= Reference)
    end
    current [keys [#keys]] = value
  end
end

function Proxy.export (proxy)
  assert (getmetatable (proxy) == Proxy)
  local keys     = proxy.__keys
  local current  = proxy.__layer.__data
  for i = 1, #keys do
    current = current [keys [i]]
    assert (type (current) == "table" and getmetatable (current) ~= Reference)
  end
  return current
end

function Proxy.is_prefix (lhs, rhs)
  assert (getmetatable (lhs) == Proxy)
  assert (getmetatable (rhs) == Proxy)
  if #lhs.__keys > #rhs.__keys then
    return false
  end
  for i = 1, #lhs.__keys do
    if lhs.__keys [i] ~= rhs.__keys [i] then
      return false
    end
  end
  return true
end

function Proxy.is_reference (proxy)
  assert (getmetatable (proxy) == Proxy)
  local _, r = Proxy.apply { proxy = proxy, resolve = false, iterate = false, }
  return getmetatable (r) == Reference
end

function Proxy.__lt (lhs, rhs)
  assert (getmetatable (lhs) == Proxy)
  assert (getmetatable (rhs) == Proxy)
  local parents = Proxy.refines (rhs)
  for i = 1, #parents-1 do -- last parent is self
    if parents [i] == lhs then
      return true
    end
  end
  return false
end

function Proxy.__le (lhs, rhs)
  if lhs == rhs then
    return true
  else
    return Proxy.__lt (lhs, rhs)
  end
end

Proxy.refines = c3.new {
  superclass = function (proxy)
    assert (getmetatable (proxy) == Proxy)
    local result  = {}
    local refines = proxy [Layer.key.refines]
    if not refines then
      return result
    end
    for i = 1, Layer.len (refines) do
      assert (getmetatable (refines [i]) == Proxy)
      result [i] = refines [i]
    end
    return result
  end,
}

function Proxy.apply (t)
  assert (getmetatable (t.proxy) == Proxy)
  local coroutine = t.iterate and coromake () or nil
  local resolve   = t.resolve
  local seen      = {}
  local noback    = {}
  local cache
  if not t.iterate and resolve then
    cache = Layer.caches.perform.noiterate_resolve
  elseif not t.iterate and not resolve then
    cache = Layer.caches.perform.noiterate_noresolve
  end
  for i = 1, #t.proxy.__keys do
    if t.proxy.__keys [i] == Layer.key.messages then
      cache = nil
    end
  end
  local function perform (proxy)
    if cache then
      local cached = cache [proxy]
      if cached then
        return cached.proxy, cached.current
      end
    end
    assert (getmetatable (proxy) == Proxy)
    if seen [proxy] then
      return nil
    end
    seen [proxy] = true
    local keys   = proxy.__keys
    -- Search in current layer:
    do
      local current = proxy.__layer.__data
      for i = 1, #keys do
        current = current [keys [i]]
        if getmetatable (current) == Reference and resolve then
          if i ~= #keys then
            print (i, proxy, current)
          end
          assert (i == #keys)
          current = Reference.resolve (current, proxy)
          break
        elseif i ~= #keys and type (current) ~= "table" then
          current = nil
          break
        end
      end
      if current ~= nil then
        if coroutine then
          coroutine.yield (proxy, current)
        else
          if cache then
            cache [proxy] = {
              proxy   = proxy,
              current = current,
            }
          end
          return proxy, current
        end
      end
    end
    -- Search in refined:
    local refines_proxies = {}
    do
      local current = proxy
      if not coroutine then
        current = current.__parent
      end
      while current do
        refines_proxies [#refines_proxies+1] = current
        local key = keys [#current.__keys]
        if key == Layer.key.checks or key == Layer.key.labels then
          refines_proxies [#refines_proxies] = nil
        elseif key == Layer.key.refines or key == Layer.key.messages then
          refines_proxies = {}
          break
        end
        current = current.__parent
      end
    end
    for k = #refines_proxies, 1, -1 do
      local current = refines_proxies [k]
      if current then
        local refines = Proxy.refines (current)
        for i = #refines-1, 1, -1 do
          local refined = refines [i]
          if not noback [refines [i]] then
            noback [refines [i]] = true
            for j = #current.__keys+1, #keys do
              local key = keys [j]
              refined = j == #keys
                    and Proxy.sub (refined, key)
                     or refined [key]
              if getmetatable (refined) ~= Proxy then
                refined = nil
                break
              end
            end
            if refined then
              local p, c = perform (refined)
              if p and not coroutine then
                if cache then
                  cache [proxy] = {
                    proxy   = p,
                    current = c,
                  }
                end
                return p, c
              end
            end
            noback [refines [i]] = nil
          end
        end
      end
    end
    -- Search in default:
    local default_proxies = {}
    do
      local current = proxy
      current = current.__parent
      while current do
        default_proxies [#default_proxies+1] = current
        local key = keys [#current.__keys+1]
        if key == Layer.key.checks
        or key == Layer.key.default
        or key == Layer.key.labels
        or key == Layer.key.meta
        or key == Layer.key.refines
        then
          default_proxies [#default_proxies] = false
        elseif key == Layer.key.messages then
          default_proxies = {}
          break
        end
        current = current.__parent
      end
    end
    for k = #default_proxies-1, 1, -1 do
      local current = default_proxies [k]
      if current then
        local default = current [Layer.key.default]
        if default then
          for j = #current.__keys+2, #keys do
            local key = keys [j]
            default = j == #keys
                  and Proxy.sub (default, key)
                   or default [key]
            if getmetatable (default) ~= Proxy then
              default = nil
              break
            end
          end
        end
        if default then
          local p, c = perform (default)
          if p and not coroutine then
            if cache then
              cache [proxy] = {
                proxy   = p,
                current = c,
              }
            end
            return p, c
          end
        end
      end
    end
    if cache then
      cache [proxy] = {}
    end
  end
  if coroutine then
    return coroutine.wrap (function ()
      perform (t.proxy)
    end)
  else
    return perform (t.proxy)
  end
end

function Proxy.__len (proxy)
  assert (getmetatable (proxy) == Proxy)
  local cache = Layer.caches.len
  if cache [proxy] then
    return cache [proxy]
  end
  for i = 1, math.huge do
    local result = proxy [i]
    if result == nil then
      cache [proxy] = i-1
      return i-1
    end
  end
  assert (false)
end

function Proxy.__ipairs (proxy)
  assert (getmetatable (proxy) == Proxy)
  local cache = Layer.caches.ipairs
  if cache [proxy] then
    return coroutine.wrap (function ()
      for i, v in ipairs (cache [proxy]) do
        coroutine.yield (i, v)
      end
    end)
  end
  local coroutine = coromake ()
  return coroutine.wrap (function ()
    local cached = {}
    for i = 1, math.huge do
      local result = proxy [i]
      if result == nil then
        break
      end
      cached [i] = result
      coroutine.yield (i, result)
    end
    cache [proxy] = cached
  end)
end

function Proxy.__pairs (proxy)
  assert (getmetatable (proxy) == Proxy)
  local coroutine = coromake ()
  local cache = Layer.caches.pairs
  if cache [proxy] then
    return coroutine.wrap (function ()
      for k, v in pairs (cache [proxy]) do
        coroutine.yield (k, v)
      end
    end)
  end
  return coroutine.wrap (function ()
    local cached = {}
    for p, t in Proxy.apply { proxy = proxy, resolve = true, iterate = true, } do
      if getmetatable (t) == Proxy then
        for k in Proxy.__pairs (t) do
          if cached [k] == nil and t [k] ~= nil then
            cached [k] = t [k]
            coroutine.yield (k, t [k])
          end
        end
      elseif type (t) == "table" then
        for k in pairs (t) do
          if cached [k] == nil and p [k] ~= nil then
            cached [k] = p [k]
            coroutine.yield (k, cached [k])
          end
        end
      end
    end
    cache [proxy] = cached
  end)
end

function Layer.contents (proxy)
  assert (getmetatable (proxy) == Proxy)
  local coroutine = coromake ()
  return coroutine.wrap (function ()
    for key, value in Proxy.__pairs (proxy) do
      if  key ~= Layer.key.checks
      and key ~= Layer.key.default
      and key ~= Layer.key.labels
      and key ~= Layer.key.messages
      and key ~= Layer.key.meta
      and key ~= Layer.key.refines
      then
        coroutine.yield (key, value)
      end
    end
  end)
end

function Layer.flatten (proxy, options)
  assert (getmetatable (proxy) == Proxy)
  if type (options) ~= "table" then
    options = {}
  end
  local iterate     = options.compact and Proxy.contents or Proxy.__pairs
  local references  = options.references
  local equivalents = {}
  local function f (p)
    if getmetatable (p) ~= Proxy then
      return p
    elseif equivalents [p] then
      return equivalents [p]
    end
    local result = {}
    equivalents [p] = result
    for k in iterate (p) do
      if options [k] ~= false then
        local v
        if references then
          local _, r = Proxy.apply { proxy = Proxy.sub (p, k), resolve = false, iterate = false }
          v = r
        else
          v = p [k]
        end
        if getmetatable (v) == Reference then
          result [f (k)] = v
        else
          result [f (k)] = f (v)
        end
      end
    end
    if not options.compact and options [Layer.key.meta] ~= false then
      result [Layer.key.meta] = f (p [Layer.key.meta])
    end
    return result
  end
  local result = f (proxy)
  return Layer.new {
    name = "flattened:" .. tostring (proxy.__layer.__name),
    data = result,
  }
end

function Reference.new (from)
  from = from or false
  local found = Reference.memo [from]
  if found then
    return found
  end
  local result = setmetatable ({
    __from   = from,
    __keys   = {},
    __memo   = setmetatable ({}, IgnoreValues),
    __parent = false,
  }, Reference)
  Reference.memo [from] = result
  return result
end

function Reference.__index (reference, key)
  assert (getmetatable (reference) == Reference)
  local references = reference.__memo
  local found      = references [key]
  if not found then
    local nkeys = {}
    for i = 1, #reference.__keys do
      nkeys [i] = reference.__keys [i]
    end
    nkeys [#nkeys+1] = key
    found = setmetatable ({
      __from   = reference.__from,
      __keys   = nkeys,
      __memo   = setmetatable ({}, IgnoreValues),
      __parent = reference,
    }, Reference)
    references [key] = found
  end
  return found
end


function Reference.resolve (reference, proxy)
  assert (getmetatable (reference) == Reference)
  assert (getmetatable (proxy    ) == Proxy    )
  for i = 1, #proxy.__keys do
    local key = proxy.__keys [i]
    if key == Layer.key.default
    or key == Layer.key.labels
    or key == Layer.key.messages
    or key == Layer.key.refines
    then
      for _ = #proxy.__keys, i, -1 do
        proxy = proxy.__parent
      end
      break
    end
  end
  local current
  if not reference.__from then -- absolute
    current = proxy.__layer.__root
  else -- relative
    current = proxy
    while current do
      if not Proxy.is_reference (current) then
        local labels = current [Layer.key.labels]
        if labels and labels [reference.__from] then
          break
        end
      end
      current = current.__parent
    end
  end
  local rkeys = reference.__keys
  for i = 1, #rkeys do
    if type (current) ~= "table" then
      return nil
    end
    current = current [rkeys [i]]
  end
  return current
end

function Reference.__tostring (reference)
  assert (getmetatable (reference) == Reference)
  local result = {}
  result [1] = tostring (reference.__from)
  result [2] = "->"
  local keys = reference.__keys
  for i = 1, #keys do
    result [i+2] = "[" .. tostring (keys [i]) .. "]"
  end
  return table.concat (result, " ")
end

Layer.Proxy     = Proxy
Layer.Reference = Reference
Layer.reference = Reference.new

-- Lua 5.1 compatibility:
Layer.len    = Proxy.__len
Layer.pairs  = Proxy.__pairs
Layer.ipairs = Proxy.__ipairs

Layer.clear_caches ()

return Layer
