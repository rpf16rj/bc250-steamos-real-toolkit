-- WirePlumber
--
-- Copyright © 2021 Collabora Ltd.
--    @author George Kiagiadakis <george.kiagiadakis@collabora.com>
--
-- SPDX-License-Identifier: MIT

-- BC-250 downstream monitor guard v0.7
-- Rebased on the stock WirePlumber 0.5.17 monitors/alsa.lua.
-- The original file remains installed under /usr/share; this override adds only
-- BC-250 HDMI teardown/activation serialization and the AC3 hardware lock.

SPLIT_PCM_PARENT_OFFSET = 256
SPLIT_PCM_OFFSET = 512

cutils = require ("common-utils")
log = Log.open_topic ("s-monitors")

config = {}
config.reserve_device = Core.test_feature ("monitor.alsa.reserve-device")
config.properties = Conf.get_section_as_properties ("monitor.alsa.properties")
config.rules = Conf.get_section_as_json ("monitor.alsa.rules", Json.Array {})

-- unique device/node name tables
device_names_table = nil
node_names_table = nil

-- SPA ids to node names: name = id_name_table[device_id][node_id]
id_name_table = nil

-- Optional delayed activation for ALSA playback nodes.
--
-- This is used on the BC-250 HDMI audio device to serialize ACP profile
-- transitions. ACP may request creation of the new node before the previous
-- node has completely released the underlying ALSA PCM. Keeping the new
-- object pending for a short period prevents both profiles from opening the
-- same exclusive PCM at the same time.
local delayed_node_activations = {}

-- v0.5: the AC3 arbiter and this monitor communicate through WirePlumber's
-- runtime Settings API. Scripts are sandboxed from one another, so ordinary
-- Lua globals cannot safely be used as a cross-script lock.
local BC250_AC3_LOCK_SETTING = "bc250.audio.ac3-hardware-lock"
local BC250_NATIVE_PROBE_SETTING = "bc250.audio.native-probe-request"
local BC250_LOCK_POLL_MS = 50

local function isBc250NativeHdmiNode(properties)
  local name = properties["node.name"] or ""
  return name:find("^alsa_output%.pci%-0000_01_00%.1%.hdmi%-") ~= nil
end

local function bc250Ac3HardwareLocked(properties)
  return isBc250NativeHdmiNode(properties) and
      Settings.get_boolean(BC250_AC3_LOCK_SETTING)
end

local function requestBc250NativeProbe(properties)
  if not isBc250NativeHdmiNode(properties) then
    return
  end

  if not Settings.get_boolean(BC250_NATIVE_PROBE_SETTING) then
    local ok = Settings.set(BC250_NATIVE_PROBE_SETTING, Json.Boolean(true))
    if not ok then
      log:warning("Failed to request BC-250 native HDMI reprobe")
    end
  end
end

-- Nodes created with Node() are PipeWire global objects. Dropping the local
-- proxy or removing it from WpSpaDevice bookkeeping is not the same as
-- explicitly asking PipeWire to destroy the remote global. Use
-- request_destroy() so profile transitions cannot leave stale sink globals.
local function requestNodeDestroy(node, name)
  if node == nil then
    return
  end

  local ok, err = pcall(function()
    node:request_destroy()
  end)

  if ok then
    log:notice("Requested destruction of ALSA node " .. tostring(name))
  else
    log:warning("Failed to request destruction of ALSA node " ..
        tostring(name) .. ": " .. tostring(err))
  end
end

local function getNodeActivationDelayMs(dev_props, properties)
  local delay_ms =
      tonumber(dev_props["bc250.profile-switch-delay-ms"] or "0") or 0

  if delay_ms <= 0 then
    return 0
  end

  -- Only delay playback nodes.
  if properties["api.alsa.pcm.stream"] ~= "playback" then
    return 0
  end

  -- Only delay HDMI/DP ACP mappings. This includes our hdmi-ac3-surround
  -- mapping as well as native hdmi-stereo / hdmi-surround profiles.
  local profile = properties["device.profile.name"] or ""
  if not profile:find("^hdmi%-") then
    return 0
  end

  return delay_ms
end

local function cancelDelayedNodeActivation(parent_id, id)
  local pending_by_id = delayed_node_activations[parent_id]
  if pending_by_id == nil then
    return
  end

  local pending = pending_by_id[id]
  if pending ~= nil then
    if pending.source ~= nil then
      pending.source:destroy()
    end

    -- The Node() constructor already created a PipeWire global proxy.
    -- If this pending transition is superseded, destroy that global
    -- deterministically instead of waiting for Lua garbage collection.
    requestNodeDestroy(pending.node, pending.name)

    log:notice("Cancelled delayed ALSA node activation " ..
        tostring(pending.name))

    pending_by_id[id] = nil
  end

  if next(pending_by_id) == nil then
    delayed_node_activations[parent_id] = nil
  end
end

local function cancelAllDelayedNodeActivations(parent_id)
  local pending_by_id = delayed_node_activations[parent_id]
  if pending_by_id == nil then
    return
  end

  for _, pending in pairs(pending_by_id) do
    if pending.source ~= nil then
      pending.source:destroy()
    end
    requestNodeDestroy(pending.node, pending.name)
  end

  delayed_node_activations[parent_id] = nil
end

function nonempty(str)
  return str ~= "" and str or nil
end

function applyDefaultDeviceProperties (properties)
  properties["api.alsa.use-acp"] = true
  properties["api.acp.auto-profile"] = false
  properties["api.acp.auto-port"] = false
  properties["api.dbus.ReserveDevice1.Priority"] = -20
  properties["api.alsa.split-enable"] = true
end

function shouldShowHdmiAlsaName (profile, properties, dev_props)
  return profile:find("^hdmi%-") and
      nonempty(properties["alsa.name"]) and
      not properties["alsa.name"]:find("HDMI") and
      properties["alsa.name"] ~= nonempty(dev_props["device.description"]) and
      properties["alsa.name"] ~= properties["device.profile.description"]
end

function createSplitPCMHWNode(dev_props, properties)
  local skip_keys = {
    "api.alsa.split.position", "card.profile.device", "device.profile.description",
    "device.profile.name"
  }
  local props = {}

  for k, v in pairs(properties) do
    props[k] = v
  end
  for _, k in pairs(skip_keys) do
    props[k] = nil
  end

  -- create the underlying hidden ALSA node
  props["node.name"] = props["api.alsa.split.name"]
  props["node.description"] = string.format("%s %s", dev_props["device.description"],
        props["api.alsa.path"]:gsub("^[^,]*[,:]", ""))
  if props["api.alsa.pcm.stream"] == "capture" then
    props["media.class"] = "Audio/Source/Internal"
  else
    props["media.class"] = "Audio/Sink/Internal"
  end
  props["api.alsa.use-chmap"] = false
  props["api.alsa.split.parent"] = true
  props["audio.position"] = props["api.alsa.split.hw-position"]
  local channels = Json.Raw (props["api.alsa.split.hw-position"]):parse ()
  props["audio.channels"] = tostring(#channels)

  props = JsonUtils.match_rules_update_properties (config.rules, props)

  if cutils.parseBool (props ["node.disabled"]) then
    log:notice ("ALSA node " .. props ["node.name"] .. " disabled")
    return nil
  end

  return Node("adapter", props)
end

function createSplitPCMLoopback(parent, id, obj_type, factory, properties)
  local skip_keys = {
    -- not suitable for loopback
    "audio.rate",
    "clock.quantum-limit",
    "factory.name",
    "node.driver",
    "node.pause-on-idle",
    "node.want-driver",
    "port.group",
    "priority.driver",
    "resample.disable",
    "resample.prefill",
  }
  local args
  local props = {}

  props["node.virtual"] = false

  for k, v in pairs(properties) do
    props[k] = v
  end
  for _, k in pairs(skip_keys) do
    props[k] = nil
  end

  local split_props = {
    ["node.name"] = properties["node.name"] .. ".split",
    ["node.description"] = string.format(I18n.gettext("Split %s"), properties["node.description"]),
    ["audio.position"] = properties["api.alsa.split.position"],
    ["stream.dont-remix"] = true,
    ["node.passive"] = true,
    ["node.dont-fallback"] = true,
    ["node.linger"] = true,
    ["state.restore-props"] = false,
    ["target.object"] = properties["api.alsa.split.name"],
  }

  if properties["api.alsa.pcm.stream"] == "playback" then
    props["media.class"] = "Audio/Sink"
    split_props["media.class"] = "Stream/Output/Audio/Internal"
    args = Json.Object {
      ["capture.props"] = Json.Object (props),
      ["playback.props"] = Json.Object (split_props),
    }
  else
    props["media.class"] = "Audio/Source"
    split_props["media.class"] = "Stream/Input/Audio/Internal"
    args = Json.Object {
      ["playback.props"] = Json.Object (props),
      ["capture.props"] = Json.Object (split_props),
    }
  end

  return LocalModule("libpipewire-module-loopback", args:get_data(), {})
end

devices_om = ObjectManager {
  Interest {
    type = "device",
  }
}

split_nodes_om = ObjectManager {
  Interest {
    type = "node",
    Constraint { "api.alsa.split.position", "+", type = "pw" },
  }
}

split_nodes_om:connect ("object-added", function(_, node)
    -- Connect ObjectConfig events to the right node
    if not monitor then
      return
    end

    local interest = Interest {
      type = "device",
      Constraint { "object.id", "=", node.properties["device.id"] }
    }
    log:info("Split PCM node found: " .. tostring (node["bound-id"]))

    for device in devices_om:iterate (interest) do
      local device_id = device.properties["spa.object.id"]
      if not device_id then
        goto next_device
      end

      local spa_device = monitor:get_managed_object (tonumber (device_id))
      if not spa_device then
        goto next_device
      end

      local id = node.properties["card.profile.device"]
      if id ~= nil then
        log:info(".. assign to device: " .. tostring (device["bound-id"]) .. " node " .. tostring (id))
        spa_device:store_managed_object (id, node)
      end

      ::next_device::
    end
end)

function monitorNodeError (node)
  node:connect("state-changed", function (n, old_state, new_state)
    if new_state == "error" and old_state ~= "error" then
      local node_name = n:get_property ("node.name")
      local dev_id = n:get_property ("device.id")
      local curr_profile_index = nil

      log:info ("Error received on ALSA node " .. node_name)

      -- Find the device for this node
      local device = devices_om:lookup {
          Constraint { "bound-id", "=", dev_id, type = "gobject" }
      }
      if device == nil then
        log:warning ("Could not find ALSA device for node " .. node_name)
        return
      end

      -- Get current profile
      local dev_name = device:get_property ("device.name")
      for p in device:iterate_params ("Profile") do
        local curr_profile = cutils.parseParam (p, "Profile")
        curr_profile_index = curr_profile.index
        break
      end
      if curr_profile_index == nil then
        log:warning ("Could not get current profile on ALSA device "
            .. dev_name)
        return
      end

      -- Close the ALSA device by setting the profile to Off
      local param_off = Pod.Object {
        "Spa:Pod:Object:Param:Profile", "Profile",
        index = 0,
      }
      device:set_param ("Profile", param_off)
      log:info ("Profile set to Off on ALSA device " .. dev_name)

      -- Re-open the ALSA device by restoring the profile after one second
      Core.timeout_add (1000, function ()
        local param_curr = Pod.Object {
          "Spa:Pod:Object:Param:Profile", "Profile",
          index = curr_profile_index,
        }
        device:set_param ("Profile", param_curr)
        log:info ("Restored profile on ALSA device " .. dev_name)
      end)

    end
  end)
end

function createNode(parent, id, obj_type, factory, properties)
  local dev_props = parent.properties
  local parent_id = tonumber(dev_props["spa.object.id"])

  -- set the device id and spa factory name; REQUIRED, do not change
  properties["device.id"] = parent["bound-id"]
  properties["factory.name"] = factory

  -- set the default pause-on-idle setting
  properties["node.pause-on-idle"] = false

  -- try to negotiate the max amount of channels
  if dev_props["api.alsa.use-acp"] ~= "true" then
    properties["audio.channels"] = properties["audio.channels"] or "64"
  end

  local dev = properties["api.alsa.pcm.device"]
              or properties["alsa.device"] or "0"
  local subdev = properties["api.alsa.pcm.subdevice"]
                 or properties["alsa.subdevice"] or "0"
  local stream = properties["api.alsa.pcm.stream"] or "unknown"
  local profile = properties["device.profile.name"]
                  or (stream .. "." .. dev .. "." .. subdev)
  local profile_desc = properties["device.profile.description"]

  -- set priority
  if not properties["priority.driver"] then
    local priority = (dev == "0") and 1000 or 744
    if stream == "capture" then
      priority = priority + 1000
    end

    priority = priority - (tonumber(dev) * 16) - tonumber(subdev)

    if profile:find("^pro%-") then
      priority = priority + 500
    elseif profile:find("^analog%-") then
      priority = priority + 9
    elseif profile:find("^iec958%-") then
      priority = priority + 8
    end

    if dev_props["device.bus"] == "usb" then
      priority = priority + 100
    end

    properties["priority.driver"] = priority
    properties["priority.session"] = priority
  end

  -- ensure the node has a media class
  if not properties["media.class"] then
    if stream == "capture" then
      properties["media.class"] = "Audio/Source"
    else
      properties["media.class"] = "Audio/Sink"
    end
  end

  -- ensure the node has a name
  if not properties["node.name"] then
    local name =
        (stream == "capture" and "alsa_input" or "alsa_output")
        .. "." ..
        (dev_props["device.name"]:gsub("^alsa_card%.(.+)", "%1") or
         dev_props["device.name"] or
         "unnamed-device")
         .. "." ..
         profile

    -- sanitize name
    name = name:gsub("([^%w_%-%.])", "_")

    properties["node.name"] = name

    log:info ("Creating node " .. name)

    -- deduplicate nodes with the same name
    for counter = 2, 99, 1 do
      if node_names_table[properties["node.name"]] ~= true then
        break
      end
      properties["node.name"] = name .. "." .. counter
      log:info ("deduplicating node name -> " .. properties["node.name"])
    end
  else
    log:info ("Creating node " .. properties["node.name"])
  end

  -- and a nick
  local nick = nonempty(properties["node.nick"])
      or nonempty(properties["api.alsa.pcm.name"])
      or nonempty(properties["alsa.name"])
      or nonempty(profile_desc)
      or dev_props["device.nick"]
  if nick == "USB Audio" then
    nick = dev_props["device.nick"]
  end
  -- also sanitize nick, replace ':' with ' '
  properties["node.nick"] = nick:gsub("(:)", " ")

  -- ensure the node has a description
  if not properties["node.description"] then
    local desc = nonempty(dev_props["device.description"]) or "unknown"
    local name = nonempty(properties["api.alsa.pcm.name"]) or
                 nonempty(properties["api.alsa.pcm.id"]) or dev

    if profile_desc then
      desc = desc .. " " .. profile_desc

      -- Include "alsa.name" in description if HDMI node for better UX
      if shouldShowHdmiAlsaName(profile, properties, dev_props) then
        desc = desc .. " [" .. properties["alsa.name"] .. "]"
      end
    elseif subdev ~= "0" then
      desc = desc .. " (" .. name .. " " .. subdev .. ")"
    elseif dev ~= "0" then
      desc = desc .. " (" .. name .. ")"
    end

    -- also sanitize description, replace ':' with ' '
    properties["node.description"] = desc:gsub("(:)", " ")
  end

  -- add api.alsa.card.* and alsa.* properties for rule matching purposes
  for k, v in pairs(dev_props) do
    if k:find("^api%.alsa%.card%..*") or k:find("^alsa%..*") then
      properties[k] = v
    end
  end

  -- add device form-factor property for rule matching purposes
  local dev_form_factor = dev_props["device.form-factor"]
  if dev_form_factor ~= nil then
    properties["device.form-factor"] = dev_form_factor
  end

  -- add cpu.vm.name for rule matching purposes
  local vm_type = Core.get_vm_type()
  if nonempty(vm_type) then
    properties["cpu.vm.name"] = vm_type
  end

  -- apply properties from rules defined in JSON .conf file
  local orig_properties = {}
  for k, v in pairs(properties) do
    orig_properties[k] = v
  end
  properties = JsonUtils.match_rules_update_properties (config.rules, properties)

  if cutils.parseBool (properties ["node.disabled"]) then
    log:notice ("ALSA node " .. properties["node.name"] .. " disabled")
    return
  end

  local delay_ms = getNodeActivationDelayMs(dev_props, properties)

  -- BC-250 profile transition barrier. A profile replacement may arrive while
  -- the previous factory-created PipeWire global still exists. Destroy every
  -- older HDMI node for this card before the replacement is registered.
  if delay_ms > 0 then
    local new_name = properties["node.name"]
    local old_ids = {}

    for old_id, old_name in pairs(id_name_table[parent_id]) do
      if old_name ~= nil
          and old_name:find("^alsa_output%..*%.hdmi%-")
          and (old_id ~= id or old_name ~= new_name) then
        table.insert(old_ids, old_id)
      end
    end

    for _, old_id in ipairs(old_ids) do
      local old_name = id_name_table[parent_id][old_id]

      -- This also explicitly destroys a Node() global when the old object is
      -- still in the delayed/pending phase.
      cancelDelayedNodeActivation(parent_id, old_id)

      local old_node = parent:get_managed_object(old_id)
      requestNodeDestroy(old_node, old_name)

      -- Clear WpSpaDevice bookkeeping after the server-side destroy request.
      parent:store_managed_object(old_id, nil)
      node_names_table[old_name] = nil
      id_name_table[parent_id][old_id] = nil
    end
  end

  node_names_table[properties["node.name"]] = true
  id_name_table[parent_id][id] = properties["node.name"]

  -- handle split HW node
  if properties["api.alsa.split.position"] ~= nil then
    local split_hw_node_name = string.format("%s.%s",
      (stream == "capture" and "alsa_input" or "alsa_output"),
      properties["api.alsa.path"]:gsub("([:,])", "_"))
    properties["api.alsa.split.name"] = split_hw_node_name
    orig_properties["api.alsa.split.name"] = split_hw_node_name

    if not node_names_table [split_hw_node_name] then
      log:info ("Create ALSA SplitPCM HW node " .. split_hw_node_name)

      local node = createSplitPCMHWNode(dev_props, orig_properties)
      if node ~= nil then
        parent:set_managed_pending(SPLIT_PCM_PARENT_OFFSET + id)
        node:activate(Features.ALL, function (n, err)
          if err then
            log:warning ("Failed to create ALSA SplitPCM HW node " ..
                split_hw_node_name .. ": " .. tostring(err))
            parent:store_managed_object(SPLIT_PCM_PARENT_OFFSET + id, nil)
          else
            monitorNodeError (n)
            parent:store_managed_object(SPLIT_PCM_PARENT_OFFSET + id, n)
          end
        end)

        node_names_table[split_hw_node_name] = true
        id_name_table[parent_id][SPLIT_PCM_PARENT_OFFSET + id] = split_hw_node_name
      end
    end

    -- create split PCM node
    log:info ("Create ALSA SplitPCM split node " .. properties["node.name"])

    local loopback = createSplitPCMLoopback (parent, id, obj_type, factory, properties)
    parent:store_managed_object(SPLIT_PCM_OFFSET + id, loopback)
    parent:set_managed_pending(id)
    return
  end

  -- create the node
  local node = Node("adapter", properties)
  parent:set_managed_pending(id)

  local function activateNode()
    node:activate(Features.ALL, function (n, err)
      if err then
        log:warning ("Failed to create ALSA node " ..
            tostring(properties["node.name"]) .. ": " .. tostring(err))
        requestNodeDestroy(n or node, properties["node.name"])
        parent:store_managed_object(id, nil)
      else
        -- The profile may have changed again while this node was activating.
        -- Never resurrect a node that ACP has already removed/replaced.
        local names = id_name_table[parent_id]
        if names == nil or names[id] ~= properties["node.name"] then
          log:info ("Discarding obsolete activated ALSA node " ..
              tostring(properties["node.name"]))
          requestNodeDestroy(n, properties["node.name"])
          parent:store_managed_object(id, nil)
          return
        end

        monitorNodeError(n)
        parent:store_managed_object(id, n)
      end
    end)
  end


  if delay_ms > 0 then
    -- If ACP has already requested another node for this same object id,
    -- only the newest request is allowed to survive.
    cancelDelayedNodeActivation(parent_id, id)

    delayed_node_activations[parent_id] =
        delayed_node_activations[parent_id] or {}

    delayed_node_activations[parent_id][id] = {
      source = nil,
      node = node,
      name = properties["node.name"],
      probe_requested = false,
    }

    -- Keep a native HDMI re-creation pending while the hidden A52 backend owns
    -- hw:Generic,3. On hotplug, ACP wants to recreate the native node even
    -- though AC3 is still selected; opening it at that moment produces EBUSY.
    -- Ask the policy to perform a maintenance reprobe (temporarily release A52,
    -- enumerate/suspend native, then resume AC3), and poll the runtime lock.
    local scheduleActivationAttempt
    scheduleActivationAttempt = function(wait_ms)
      local source = Core.timeout_add(wait_ms, function()
        local pending_by_id = delayed_node_activations[parent_id]
        local pending = pending_by_id ~= nil and pending_by_id[id] or nil

        -- A newer profile/hotplug request superseded this one.
        if pending == nil or pending.node ~= node then
          return false
        end

        pending.source = nil

        if bc250Ac3HardwareLocked(properties) then
          if not pending.probe_requested then
            pending.probe_requested = true
            log:notice("Holding native HDMI activation while AC3 owns hardware: " ..
                tostring(properties["node.name"]))
            requestBc250NativeProbe(properties)
          end
          scheduleActivationAttempt(BC250_LOCK_POLL_MS)
          return false
        end

        Core.sync(function(err)
          local sync_pending_by_id = delayed_node_activations[parent_id]
          local sync_pending =
              sync_pending_by_id ~= nil and sync_pending_by_id[id] or nil

          if sync_pending == nil or sync_pending.node ~= node then
            return
          end

          -- AC3 can become active while the PipeWire barrier is in flight.
          -- Never race A52 just because the lock changed between the timer and
          -- Core.sync() callback.
          if bc250Ac3HardwareLocked(properties) then
            if not sync_pending.probe_requested then
              sync_pending.probe_requested = true
              log:notice("Holding native HDMI activation after sync; AC3 owns hardware: " ..
                  tostring(properties["node.name"]))
              requestBc250NativeProbe(properties)
            end
            scheduleActivationAttempt(BC250_LOCK_POLL_MS)
            return
          end

          sync_pending_by_id[id] = nil
          if next(sync_pending_by_id) == nil then
            delayed_node_activations[parent_id] = nil
          end

          if err ~= nil then
            log:warning("PipeWire sync failed before ALSA activation: " ..
                tostring(err))
            requestNodeDestroy(node, properties["node.name"])
            parent:store_managed_object(id, nil)
            return
          end

          -- ACP may have removed or replaced this object while the timeout /
          -- sync barrier was running.
          local names = id_name_table[parent_id]
          if names == nil or names[id] ~= properties["node.name"] then
            log:info("Skipping obsolete delayed ALSA node " ..
                tostring(properties["node.name"]))
            requestNodeDestroy(node, properties["node.name"])
            parent:store_managed_object(id, nil)
            return
          end

          log:notice("Activating ALSA node after " ..
              tostring(delay_ms) .. " ms + PipeWire sync: " ..
              tostring(properties["node.name"]))

          activateNode()
        end)

        return false
      end)

      local pending_by_id = delayed_node_activations[parent_id]
      local pending = pending_by_id ~= nil and pending_by_id[id] or nil
      if pending ~= nil and pending.node == node then
        pending.source = source
      else
        source:destroy()
      end
    end

    scheduleActivationAttempt(delay_ms)

    log:notice("Delaying ALSA node activation by " ..
        tostring(delay_ms) .. " ms: " ..
        tostring(properties["node.name"]))

  else
    activateNode()
  end
end

function removeNode(parent, id)
  local parent_id = tonumber(parent.properties["spa.object.id"])

  -- If this node has not been activated yet, cancel its pending timer and
  -- explicitly destroy the PipeWire global created by Node().
  cancelDelayedNodeActivation(parent_id, id)

  local ids = {id, SPLIT_PCM_PARENT_OFFSET + id, SPLIT_PCM_OFFSET + id}

  for _, j in pairs(ids) do
    local node_name = id_name_table[parent_id][j]
    local managed = parent:get_managed_object(j)

    -- WpSpaDevice emits object-removed before it drops the managed object.
    -- This is therefore the deterministic point to destroy a factory-created
    -- PipeWire Node global. Only do this for our delayed BC-250 HDMI nodes;
    -- split loopbacks / unrelated ALSA objects keep the stock behaviour.
    local delay_ms = tonumber(parent.properties["bc250.profile-switch-delay-ms"] or "0") or 0
    if delay_ms > 0
        and node_name ~= nil
        and node_name:find("^alsa_output%..*%.hdmi%-") then
      requestNodeDestroy(managed, node_name)
    end

    -- Keep the upstream bookkeeping cleanup. For the id that triggered this
    -- callback WpSpaDevice will also remove it internally after the signal;
    -- calling this is harmless and is still needed for associated split ids.
    parent:store_managed_object(j, nil)

    if node_name ~= nil then
      log:info ("Removing node " .. node_name)
      node_names_table[node_name] = nil
      id_name_table[parent_id][j] = nil
    end
  end
end

function createDevice(parent, id, factory, properties)
  id_name_table[id] = {}
  properties["spa.object.id"] = id
  local device = SpaDevice(factory, properties)
  if device then
    device:connect("create-object", createNode)
    device:connect("object-removed", removeNode)
    parent:set_managed_pending(id)
    device:activate(Features.ALL, function (d, err)
      if err then
        log:warning ("Failed to create ALSA device " ..
            tostring (properties["device.name"]) .. ": " .. tostring(err))
        parent:store_managed_object(id, nil)
      else
        parent:store_managed_object(id, device)
      end
    end)
  else
    log:warning ("Failed to create '" .. factory .. "' device")
  end
end

function removeDevice(parent, id)
  cancelAllDelayedNodeActivations(id)

  if id_name_table[id] ~= nil then
    for _, node_name in pairs(id_name_table[id]) do
      log:info ("Release " .. node_name)
      node_names_table[node_name] = nil
    end
    id_name_table[id] = nil
  end
end

function prepareDevice(parent, id, obj_type, factory, properties)
  -- ensure the device has an appropriate name
  local name = "alsa_card." ..
    (properties["device.name"] or
     properties["device.bus-id"] or
     properties["device.bus-path"] or
     tostring(id)):gsub("([^%w_%-%.])", "_")

  properties["device.name"] = name

  -- deduplicate devices with the same name
  for counter = 2, 99, 1 do
    if device_names_table[properties["device.name"]] ~= true then
      device_names_table[properties["device.name"]] = true
      break
    end
    properties["device.name"] = name .. "." .. counter
  end

  -- ensure the device has a description
  if not properties["device.description"] then
    local d = nil
    local f = properties["device.form-factor"]
    local c = properties["device.class"]
    local n = properties["api.alsa.card.name"]

    if n == "Loopback" then
      d = I18n.gettext("Loopback")
    elseif f == "internal" then
      d = I18n.gettext("Built-in Audio")
    elseif c == "modem" then
      d = I18n.gettext("Modem")
    end

    d = d or properties["device.product.name"]
          or properties["api.alsa.card.name"]
          or properties["alsa.card_name"]
          or "Unknown device"
    properties["device.description"] = d
  end

  -- ensure the device has a nick
  properties["device.nick"] =
      properties["device.nick"] or
      properties["api.alsa.card.name"] or
      properties["alsa.card_name"]

  -- set the icon name
  if not properties["device.icon-name"] then
    local icon = nil
    local icon_map = {
      -- form factor -> icon
      ["microphone"] = "audio-input-microphone",
      ["webcam"] = "camera-web",
      ["handset"] = "phone",
      ["portable"] = "multimedia-player",
      ["tv"] = "video-display",
      ["headset"] = "audio-headset",
      ["headphone"] = "audio-headphones",
      ["speaker"] = "audio-speakers",
      ["hands-free"] = "audio-handsfree",
    }
    local f = properties["device.form-factor"]
    local c = properties["device.class"]
    local b = properties["device.bus"]

    icon = icon_map[f] or ((c == "modem") and "modem") or "audio-card"
    properties["device.icon-name"] = icon .. "-analog" .. (b and ("-" .. b) or "")
  end

  -- apply properties from rules defined in JSON .conf file
  applyDefaultDeviceProperties (properties)
  properties = JsonUtils.match_rules_update_properties (config.rules, properties)

  if cutils.parseBool (properties ["device.disabled"]) then
    log:notice ("ALSA card/device " .. properties ["device.name"] .. " disabled")
    device_names_table [properties ["device.name"]] = nil
    return
  end

  -- override the device factory to use ACP
  if cutils.parseBool (properties ["api.alsa.use-acp"]) then
    log:info("Enabling the use of ACP on " .. properties["device.name"])
    factory = "api.alsa.acp.device"
  end

  -- use HDMI channel detection if enabled in settings
  if Settings.get_boolean ("monitor.alsa.autodetect-hdmi-channels") then
    properties["api.acp.use-eld-channels"] = true
  end

  -- use device reservation, if available
  if rd_plugin and properties["api.alsa.card"] then
    local rd_name = "Audio" .. properties["api.alsa.card"]
    local rd = rd_plugin:call("create-reservation",
        rd_name,
        cutils.get_application_name (),
        properties["device.name"],
        properties["api.dbus.ReserveDevice1.Priority"]);

    properties["api.dbus.ReserveDevice1"] = rd_name

    -- unlike pipewire-media-session, this logic here keeps the device
    -- acquired at all times and destroys it if someone else acquires
    rd:connect("notify::state", function (rd, pspec)
      local state = rd["state"]

      if state == "acquired" then
        -- create the device
        createDevice(parent, id, factory, properties)

      elseif state == "available" then
        -- attempt to acquire again
        rd:call("acquire")

      elseif state == "busy" then
        -- destroy the device
        removeDevice(parent, id)
        parent:store_managed_object(id, nil)
      end
    end)

    rd:connect("release-requested", function (rd)
        log:info("release requested")
        parent:store_managed_object(id, nil)
        rd:call("release")
    end)

    rd:call("acquire")
  else
    -- create the device
    createDevice(parent, id, factory, properties)
  end
end

function createMonitor ()
  local m = SpaDevice("api.alsa.enum.udev", config.properties)
  if m == nil then
    log:notice("PipeWire's ALSA SPA plugin is missing or broken. " ..
        "Sound cards will not be supported")
    return nil
  end

  -- handle create-object to prepare device
  m:connect("create-object", prepareDevice)

  -- handle object-removed to destroy device reservations and recycle device name
  m:connect("object-removed", function (parent, id)
    removeDevice(parent, id)

    local device = parent:get_managed_object(id)
    if not device then
      return
    end

    if rd_plugin then
      local rd_name = device.properties["api.dbus.ReserveDevice1"]
      if rd_name then
        rd_plugin:call("destroy-reservation", rd_name)
      end
    end
    device_names_table[device.properties["device.name"]] = nil
  end)

  -- reset the name tables to make sure names are recycled
  device_names_table = {}
  node_names_table = {}
  id_name_table = {}

  -- activate monitor
  log:info("Activating ALSA monitor")
  m:activate(Feature.SpaDevice.ENABLED)
  return m
end

-- if the reserve-device plugin is enabled, at the point of script execution
-- it is expected to be connected. if it is not, assume the d-bus connection
-- has failed and continue without it
if config.reserve_device then
  rd_plugin = Plugin.find("reserve-device")
end
if rd_plugin and rd_plugin:call("get-dbus")["state"] ~= "connected" then
  log:notice("reserve-device plugin is not connected to D-Bus, "
              .. "disabling device reservation")
  rd_plugin = nil
end

-- handle rd_plugin state changes to destroy and re-create the ALSA monitor in
-- case D-Bus service is restarted
if rd_plugin then
  local dbus = rd_plugin:call("get-dbus")
  dbus:connect("notify::state", function (b, pspec)
    local state = b["state"]
    log:info ("rd-plugin state changed to " .. state)
    if state == "connected" then
      log:info ("Creating ALSA monitor")
      monitor = createMonitor()
    elseif state == "closed" then
      log:info ("Destroying ALSA monitor")
      monitor = nil
    end
  end)
end

-- create the monitor
monitor = createMonitor()

devices_om:activate()
split_nodes_om:activate()
