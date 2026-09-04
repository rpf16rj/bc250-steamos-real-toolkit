-- BC-250 global native-HDMI / realtime-AC3 output arbiter
-- Target: WirePlumber 0.5.17
-- BC-250 policy revision: v0.7
--
-- User-visible model:
--   * stock/native HDMI/DP sink (ACP, EDID/ELD driven)
--   * bc250_ac3: permanent virtual 5.1 sink
--
-- Hardware model:
--   * native ACP sink and hidden A52 backend both ultimately need hw:Generic,3
--   * they must NEVER be active on the hardware at the same time
--
-- Policy model:
--   * selecting the default sink is selecting a GLOBAL audio mode
--   * all normal application playback streams are forced to that global mode
--   * AC3 backend creation waits until native HDMI is SUSPENDED, then waits a
--     configurable guard interval + PipeWire sync before opening A52
--   * AC3 -> native destroys/unloads A52, syncs, waits the same guard, then
--     lets streams return to the still-visible native ACP sink
--   * rapid mode changes are serialized; the newest desired mode wins

local lutils = require ("linking-utils")
local log = Log.open_topic ("s-bc250-audio")

local cfg = Conf.get_section_as_properties ("bc250.audio.properties")

local NATIVE_PREFIX = cfg["native-node-prefix"] or
    "alsa_output.pci-0000_01_00.1.hdmi-"
local FRONTEND = cfg["ac3-frontend-node"] or "bc250_ac3"
local BACKEND_NAME = cfg["ac3-backend-node"] or "bc250_ac3_backend"
local A52_PATH = cfg["ac3-alsa-path"] or "plug:bc250_a52"
local SWITCH_DELAY_MS = tonumber (cfg["switch-delay-ms"] or "1000") or 1000
local POLL_MS = tonumber (cfg["native-poll-ms"] or "50") or 50
local RETRY_MS = tonumber (cfg["backend-retry-ms"] or "1000") or 1000
local ALSA_START_DELAY = tonumber (cfg["api-alsa-start-delay"] or "1536") or 1536
local STARTUP_SETTLE_MS = tonumber (cfg["startup-settle-ms"] or "1500") or 1500
local NATIVE_PROBE_TIMEOUT_MS = tonumber (cfg["native-probe-timeout-ms"] or "5000") or 5000

local AC3_LOCK_SETTING = "bc250.audio.ac3-hardware-lock"
local NATIVE_PROBE_SETTING = "bc250.audio.native-probe-request"

local nodes_om = ObjectManager {
  Interest { type = "node" }
}

-- The PipeWire "default" metadata contains both:
--   default.configured.audio.sink = persistent user choice (Steam/KDE/wpctl)
--   default.audio.sink            = current effective/automatic choice
-- v0.6 treats configured as authoritative whenever it exists. This is what
-- prevents a native HDMI hot-unplug from being mistaken for a user choosing
-- the always-present AC3 frontend when WirePlumber temporarily falls back.
local metadata_om = ObjectManager {
  Interest {
    type = "metadata",
    Constraint { "metadata.name", "=", "default", type = "pw-global" },
  },
}

local default_nodes_api = nil
local default_metadata = nil
local nodes_ready = false
local metadata_ready = false

-- At daemon startup the permanent AC3 frontend appears before the delayed
-- native HDMI node. That can make the AC3 frontend the *temporary* default.
-- Do not interpret those bootstrap default-node changes as a user request.
local startup_settled = false
local startup_settle_source = nil

-- Desired mode follows default.configured.audio.sink when present. If the
-- user has never configured a default (or explicitly runs wpctl clear-default),
-- WirePlumber's effective default is used as the automatic fallback.
local desired_mode = "other"      -- "native", "ac3", "other"
local desired_native_name = nil
local generation = 0

-- Effective target is what normal app streams are allowed to use RIGHT NOW.
-- During transitions it intentionally stays on the safe null AC3 frontend.
local effective_target = nil

local transition_busy = false
local backend = nil
local backend_pending = nil
local bridge = nil
local timer_source = nil

local function starts_with (s, prefix)
  return s ~= nil and s:sub (1, #prefix) == prefix
end

local function prop_is_true (v)
  return v == true or v == "true" or v == "1"
end

local function set_bool_setting (name, value)
  if Settings.get_boolean (name) == value then
    return true
  end
  local ok = Settings.set (name, Json.Boolean (value))
  if not ok then
    log:warning ("failed to set runtime setting " .. tostring (name) ..
        "=" .. tostring (value))
  end
  return ok
end

local function set_ac3_hardware_lock (value, reason)
  if Settings.get_boolean (AC3_LOCK_SETTING) == value then
    return
  end
  if set_bool_setting (AC3_LOCK_SETTING, value) then
    log:notice ("AC3 hardware lock -> " .. tostring (value) ..
        " (" .. tostring (reason) .. ")")
  end
end

local function clear_native_probe_request ()
  set_bool_setting (NATIVE_PROBE_SETTING, false)
end

local function cancel_timer ()
  if timer_source ~= nil then
    timer_source:destroy ()
    timer_source = nil
  end
end

local function request_destroy (node, why)
  if node == nil then
    return
  end
  local ok, err = pcall (function () node:request_destroy () end)
  if not ok then
    log:warning ("request_destroy failed (" .. tostring (why) .. "): " ..
        tostring (err))
  end
end

local function find_node_by_name (name)
  if name == nil then
    return nil
  end
  for node in nodes_om:iterate () do
    if node.properties["node.name"] == name then
      return node
    end
  end
  return nil
end

local function get_native_nodes ()
  local result = {}
  for node in nodes_om:iterate () do
    local name = node.properties["node.name"]
    if starts_with (name, NATIVE_PREFIX) then
      table.insert (result, node)
    end
  end
  return result
end

local function get_default_sink_name ()
  if default_nodes_api == nil or not nodes_ready then
    return nil
  end

  local id = default_nodes_api:call ("get-default-node", "Audio/Sink")
  if id == nil then
    return nil
  end

  local node = nodes_om:lookup {
    Constraint { "bound-id", "=", id, type = "gobject" }
  }
  if node == nil then
    return nil
  end

  return node.properties["node.name"]
end

local CONFIGURED_SINK_KEY = "default.configured.audio.sink"

local function parse_metadata_node_name (value)
  if value == nil then
    return nil
  end

  local ok, parsed = pcall (function ()
    return Json.Raw (value):parse ()
  end)

  if not ok or type (parsed) ~= "table" then
    log:warning ("could not parse configured default sink metadata: " ..
        tostring (value))
    return nil
  end

  local name = parsed["name"]
  if type (name) ~= "string" or name == "" then
    return nil
  end

  return name
end

local function get_configured_sink_name ()
  if default_metadata == nil or not metadata_ready then
    return nil
  end

  local value = default_metadata:find (0, CONFIGURED_SINK_KEY)
  return parse_metadata_node_name (value)
end

-- Return the sink name that is authoritative for the BC-250 mode and where
-- that authority came from. A configured default survives node disappearance,
-- so transient effective-default changes during HDMI hotplug cannot flip mode.
local function get_authoritative_sink_name ()
  local configured = get_configured_sink_name ()
  if configured ~= nil then
    return configured, "configured"
  end

  return get_default_sink_name (), "automatic/effective"
end

local function schedule_linking_rescan ()
  local source = Plugin.find ("standard-event-source")
  if source == nil then
    log:warning ("standard-event-source unavailable; cannot force linking rescan")
    return
  end

  local event = source:call ("create-event", "rescan-for-linking", nil, nil)
  if event ~= nil then
    EventDispatcher.push_event (event)
  end
end

local function set_effective_target (name, reason)
  if effective_target == name then
    return
  end
  effective_target = name
  log:notice ("effective target -> " .. tostring (name) ..
      " (" .. tostring (reason) .. ")")
  schedule_linking_rescan ()
end

local reconcile -- forward declaration

local function transition_finished (gen)
  transition_busy = false
  if gen ~= generation then
    reconcile ()
  end
end

local function unload_bridge ()
  if bridge ~= nil then
    log:notice ("unloading AC3 bridge")
    local ok, err = pcall (function () bridge:unload () end)
    if not ok then
      log:warning ("failed to unload AC3 bridge: " .. tostring (err))
    end
    bridge = nil
  end
end

local function destroy_backend ()
  if backend_pending ~= nil then
    request_destroy (backend_pending, "pending AC3 backend")
    backend_pending = nil
  end

  if backend ~= nil then
    pcall (function () backend:send_command ("Suspend") end)
    request_destroy (backend, "active AC3 backend")
    backend = nil
  end
end

local function create_bridge (gen)
  if gen ~= generation or desired_mode ~= "ac3" then
    transition_finished (gen)
    reconcile ()
    return
  end

  local args = string.format ([[
    node.description = "BC-250 AC3 bridge"
    audio.rate = 48000
    audio.channels = 6
    audio.position = [ FL FR RL RR FC LFE ]

    capture.props = {
      node.name = "bc250_ac3_bridge.capture"
      stream.capture.sink = true
      target.object = "%s"
      node.passive = true
      node.dont-reconnect = true
      node.dont-fallback = true
      stream.dont-remix = true
      state.restore-target = false
      bc250.internal = true
    }

    playback.props = {
      node.name = "bc250_ac3_bridge.playback"
      target.object = "%s"
      node.passive = true
      node.dont-reconnect = true
      node.dont-fallback = true
      stream.dont-remix = true
      state.restore-target = false
      bc250.internal = true
    }
  ]], FRONTEND, BACKEND_NAME)

  local ok, mod = pcall (function ()
    return LocalModule ("libpipewire-module-loopback", args, {})
  end)

  if not ok or mod == nil then
    log:warning ("failed to load AC3 bridge: " .. tostring (mod))
    destroy_backend ()
    transition_busy = false
    if desired_mode == "ac3" then
      cancel_timer ()
      timer_source = Core.timeout_add (RETRY_MS, function ()
        timer_source = nil
        reconcile ()
        return false
      end)
    end
    return
  end

  bridge = mod
  Core.sync (function (err)
    if gen ~= generation or desired_mode ~= "ac3" then
      unload_bridge ()
      destroy_backend ()
      transition_finished (gen)
      reconcile ()
      return
    end

    if err ~= nil then
      log:warning ("PipeWire sync failed after AC3 bridge load: " .. tostring (err))
      unload_bridge ()
      destroy_backend ()
      transition_busy = false
      reconcile ()
      return
    end

    log:notice ("AC3 mode READY: virtual frontend -> A52 backend -> hw:Generic,3")
    transition_busy = false
    -- effective target was already FRONTEND; rescan once more now that the
    -- monitor bridge is live so newly-created/lingering streams settle cleanly.
    schedule_linking_rescan ()
    reconcile ()
  end)
end

local function create_backend (gen)
  if gen ~= generation or desired_mode ~= "ac3" then
    transition_finished (gen)
    reconcile ()
    return
  end

  log:notice ("creating hidden A52 backend on " .. A52_PATH)

  local properties = {
    ["factory.name"] = "api.alsa.pcm.sink",
    ["node.name"] = BACKEND_NAME,
    ["node.description"] = "BC-250 AC3 hardware backend",
    ["node.nick"] = "BC-250 AC3 backend",
    ["media.class"] = "Audio/Sink/Internal",

    ["api.alsa.path"] = A52_PATH,
    ["api.alsa.start-delay"] = tostring (ALSA_START_DELAY),
    ["api.alsa.use-chmap"] = "false",

    ["audio.rate"] = "48000",
    ["audio.channels"] = "6",
    ["audio.position"] = "FL,FR,RL,RR,FC,LFE",

    ["node.always-process"] = "true",
    ["node.pause-on-idle"] = "false",
    ["node.suspend-on-idle"] = "false",
    ["session.suspend-timeout-seconds"] = "0",
    ["priority.session"] = "0",
    ["priority.driver"] = "0",
    ["bc250.internal"] = "true",
  }

  local node = Node ("adapter", properties)
  backend_pending = node

  node:activate (Features.ALL, function (n, err)
    if gen ~= generation or desired_mode ~= "ac3" then
      request_destroy (n or node, "obsolete AC3 backend activation")
      if backend_pending == node then
        backend_pending = nil
      end
      transition_finished (gen)
      reconcile ()
      return
    end

    if err ~= nil then
      log:warning ("A52 backend activation failed: " .. tostring (err))
      request_destroy (n or node, "failed AC3 backend")
      backend_pending = nil
      backend = nil
      transition_busy = false

      -- Fail safe: never fall through to native while the user selected AC3;
      -- leave streams on the null frontend and retry. This avoids EBUSY loops.
      cancel_timer ()
      timer_source = Core.timeout_add (RETRY_MS, function ()
        timer_source = nil
        reconcile ()
        return false
      end)
      return
    end

    backend_pending = nil
    backend = n

    Core.sync (function (sync_err)
      if gen ~= generation or desired_mode ~= "ac3" then
        destroy_backend ()
        transition_finished (gen)
        reconcile ()
        return
      end

      if sync_err ~= nil then
        log:warning ("PipeWire sync failed after A52 backend activation: " ..
            tostring (sync_err))
        destroy_backend ()
        transition_busy = false
        reconcile ()
        return
      end

      create_bridge (gen)
    end)
  end)
end

local function native_is_safely_suspended ()
  local all_suspended = true
  local found = false

  for _, node in ipairs (get_native_nodes ()) do
    found = true
    local state, err = node:get_state ()

    if state == "idle" then
      -- There should be no normal client links anymore; request immediate
      -- suspension instead of waiting for a session-manager timeout.
      pcall (function () node:send_command ("Suspend") end)
      all_suspended = false
    elseif state ~= "suspended" and state ~= "error" then
      all_suspended = false
      log:debug ("waiting for native HDMI to suspend; state=" ..
          tostring (state) .. " err=" .. tostring (err))
    end
  end

  -- If no native node exists (hotplug / TV absent), there is no hw owner to
  -- wait for. A52 open may still fail; its retry path remains fail-safe.
  return (not found) or all_suspended
end

local function start_ac3 (gen)
  transition_busy = true
  set_ac3_hardware_lock (true, "entering AC3 mode")

  -- First move every normal client stream away from native HDMI. Audio is
  -- buffered/consumed by the null frontend during the hardware handover.
  set_effective_target (FRONTEND, "entering AC3 mode")

  local function wait_native ()
    timer_source = nil

    if gen ~= generation or desired_mode ~= "ac3" then
      transition_finished (gen)
      reconcile ()
      return false
    end

    if not native_is_safely_suspended () then
      timer_source = Core.timeout_add (POLL_MS, wait_native)
      return false
    end

    log:notice ("native HDMI is suspended; starting " ..
        tostring (SWITCH_DELAY_MS) .. " ms hardware guard")

    timer_source = Core.timeout_add (SWITCH_DELAY_MS, function ()
      timer_source = nil

      if gen ~= generation or desired_mode ~= "ac3" then
        transition_finished (gen)
        reconcile ()
        return false
      end

      Core.sync (function (err)
        if gen ~= generation or desired_mode ~= "ac3" then
          transition_finished (gen)
          reconcile ()
          return
        end

        if err ~= nil then
          log:warning ("PipeWire sync failed before A52 open: " .. tostring (err))
          transition_busy = false
          reconcile ()
          return
        end

        create_backend (gen)
      end)

      return false
    end)

    return false
  end

  -- Give the linking rescan a chance to move application streams off native
  -- before looking at node state.
  timer_source = Core.timeout_add (POLL_MS, wait_native)
end

local function stop_ac3_then (gen, next_mode, next_native_name)
  transition_busy = true

  -- Keep clients on the safe null frontend until A52 is fully gone. This is
  -- what prevents a Firefox/Spotify split from reopening native too early.
  set_effective_target (FRONTEND, "leaving AC3 mode")

  unload_bridge ()

  Core.sync (function (err)
    if err ~= nil then
      log:warning ("PipeWire sync failed after bridge unload: " .. tostring (err))
    end

    destroy_backend ()

    Core.sync (function (destroy_err)
      if destroy_err ~= nil then
        log:warning ("PipeWire sync failed after A52 destroy: " ..
            tostring (destroy_err))
      end

      log:notice ("A52 backend gone; starting " ..
          tostring (SWITCH_DELAY_MS) .. " ms hardware guard")

      cancel_timer ()
      timer_source = Core.timeout_add (SWITCH_DELAY_MS, function ()
        timer_source = nil

        if gen ~= generation then
          transition_finished (gen)
          reconcile ()
          return false
        end

        -- A52 has been gone for the full guard interval. Native ACP is now
        -- allowed to open hw:Generic,3 (including a hotplug node that the ALSA
        -- monitor may have been holding pending).
        set_ac3_hardware_lock (false, "A52 destroyed and guard elapsed")
        clear_native_probe_request ()

        Core.sync (function (sync_err)
          if sync_err ~= nil then
            log:warning ("PipeWire sync failed before returning to target: " ..
                tostring (sync_err))
          end

          if gen ~= generation then
            transition_finished (gen)
            reconcile ()
            return
          end

          if next_mode == "native" then
            set_effective_target (next_native_name, "native mode ready")
            log:notice ("native mode READY: " .. tostring (next_native_name))
          else
            set_effective_target (nil, "non-BC250 output selected")
            log:notice ("BC-250 arbitration released for other output")
          end

          transition_busy = false
          schedule_linking_rescan ()
        end)

        return false
      end)
    end)
  end)
end

local function refresh_native_during_ac3 (gen)
  transition_busy = true
  set_effective_target (FRONTEND, "AC3 hotplug reprobe")

  log:notice ("native HDMI reprobe requested while AC3 is active; " ..
      "temporarily releasing A52")

  unload_bridge ()

  Core.sync (function (err)
    if err ~= nil then
      log:warning ("PipeWire sync failed before hotplug A52 release: " ..
          tostring (err))
    end

    destroy_backend ()

    Core.sync (function (destroy_err)
      if destroy_err ~= nil then
        log:warning ("PipeWire sync failed after hotplug A52 destroy: " ..
            tostring (destroy_err))
      end

      cancel_timer ()
      log:notice ("hotplug reprobe: A52 gone; starting " ..
          tostring (SWITCH_DELAY_MS) .. " ms release guard")

      timer_source = Core.timeout_add (SWITCH_DELAY_MS, function ()
        timer_source = nil

        if gen ~= generation or desired_mode ~= "ac3" then
          set_ac3_hardware_lock (false, "hotplug reprobe superseded")
          clear_native_probe_request ()
          transition_finished (gen)
          reconcile ()
          return false
        end

        set_ac3_hardware_lock (false, "hotplug native reprobe window")
        log:notice ("hotplug reprobe: native HDMI may open hardware now")

        local remaining = NATIVE_PROBE_TIMEOUT_MS
        local function wait_native_reprobe ()
          timer_source = nil

          if gen ~= generation or desired_mode ~= "ac3" then
            set_ac3_hardware_lock (false, "hotplug reprobe superseded")
            clear_native_probe_request ()
            transition_finished (gen)
            reconcile ()
            return false
          end

          local natives = get_native_nodes ()
          local found = #natives > 0
          local all_suspended = found

          for _, node in ipairs (natives) do
            local state, state_err = node:get_state ()
            if state == "idle" then
              pcall (function () node:send_command ("Suspend") end)
              all_suspended = false
            elseif state ~= "suspended" then
              all_suspended = false
              log:debug ("hotplug reprobe waiting for native HDMI; state=" ..
                  tostring (state) .. " err=" .. tostring (state_err))
            end
          end

          if found and all_suspended then
            clear_native_probe_request ()
            set_ac3_hardware_lock (true, "native reprobe complete; reclaiming AC3")
            log:notice ("hotplug reprobe: native HDMI is visible and suspended; " ..
                "starting " .. tostring (SWITCH_DELAY_MS) ..
                " ms AC3 reclaim guard")

            timer_source = Core.timeout_add (SWITCH_DELAY_MS, function ()
              timer_source = nil

              if gen ~= generation or desired_mode ~= "ac3" then
                set_ac3_hardware_lock (false, "AC3 reclaim superseded")
                transition_finished (gen)
                reconcile ()
                return false
              end

              Core.sync (function (sync_err)
                if gen ~= generation or desired_mode ~= "ac3" then
                  set_ac3_hardware_lock (false, "AC3 reclaim superseded")
                  transition_finished (gen)
                  reconcile ()
                  return
                end

                if sync_err ~= nil then
                  log:warning ("PipeWire sync failed before AC3 hotplug reclaim: " ..
                      tostring (sync_err))
                end

                log:notice ("hotplug reprobe complete; reopening A52 backend")
                create_backend (gen)
              end)
              return false
            end)
            return false
          end

          remaining = remaining - POLL_MS
          if remaining <= 0 then
            log:warning ("native HDMI hotplug reprobe timed out after " ..
                tostring (NATIVE_PROBE_TIMEOUT_MS) ..
                " ms; resuming AC3 fail-safe")
            clear_native_probe_request ()
            set_ac3_hardware_lock (true, "native reprobe timeout; resuming AC3")

            timer_source = Core.timeout_add (SWITCH_DELAY_MS, function ()
              timer_source = nil
              if gen ~= generation or desired_mode ~= "ac3" then
                set_ac3_hardware_lock (false, "reprobe timeout recovery superseded")
                transition_finished (gen)
                reconcile ()
                return false
              end
              create_backend (gen)
              return false
            end)
            return false
          end

          timer_source = Core.timeout_add (POLL_MS, wait_native_reprobe)
          return false
        end

        timer_source = Core.timeout_add (POLL_MS, wait_native_reprobe)
        return false
      end)
    end)
  end)
end

reconcile = function ()
  if not nodes_ready or default_nodes_api == nil then
    return
  end
  if transition_busy then
    return
  end

  -- The hardware lock is an ownership assertion, not a remembered preference.
  -- If the newest user choice is no longer AC3 and there is no A52 object left
  -- to tear down, make absolutely sure a cancelled/superseded transition cannot
  -- strand native HDMI behind a stale lock.
  if desired_mode ~= "ac3" and
      backend == nil and backend_pending == nil and bridge == nil then
    set_ac3_hardware_lock (false, "non-AC3 mode with no A52 owner")
    clear_native_probe_request ()
  end

  local gen = generation

  if desired_mode == "ac3" then
    if Settings.get_boolean (NATIVE_PROBE_SETTING) and
        (backend ~= nil or backend_pending ~= nil or bridge ~= nil) then
      refresh_native_during_ac3 (gen)
      return
    end

    if backend ~= nil and bridge ~= nil then
      set_effective_target (FRONTEND, "AC3 already active")
      return
    end
    start_ac3 (gen)
    return
  end

  if backend ~= nil or backend_pending ~= nil or bridge ~= nil then
    stop_ac3_then (gen, desired_mode, desired_native_name)
    return
  end

  if desired_mode == "native" then
    set_effective_target (desired_native_name, "native mode")
  else
    set_effective_target (nil, "other output")
  end
end

local function refresh_desired_from_authority (force)
  if default_nodes_api == nil or not nodes_ready or not metadata_ready then
    return
  end

  if not startup_settled and not force then
    return
  end

  local name, authority = get_authoritative_sink_name ()
  local mode
  local native_name = nil

  if name == FRONTEND then
    mode = "ac3"
  elseif starts_with (name, NATIVE_PREFIX) then
    mode = "native"
    native_name = name
  else
    mode = "other"
  end

  if mode == desired_mode and native_name == desired_native_name then
    return
  end

  generation = generation + 1

  -- IMPORTANT: never cancel the timer that currently owns an in-flight
  -- transition. Its callback observes the generation mismatch, drops
  -- transition_busy and reconciles the newest request. Cancelling such a
  -- timer can strand the policy in a permanently busy state.
  if not transition_busy then
    cancel_timer ()
  end

  desired_mode = mode
  desired_native_name = native_name

  log:notice (tostring (authority) .. " output -> " .. tostring (name) ..
      "; desired mode=" .. tostring (mode) ..
      "; generation=" .. tostring (generation))

  if transition_busy then
    log:notice ("mode changed during transition; current phase will unwind safely")
  end

  reconcile ()
end

local function schedule_startup_settle (reason)
  if startup_settled then
    return
  end
  if default_nodes_api == nil or not nodes_ready or not metadata_ready then
    return
  end

  -- Startup is not considered stable until there have been no relevant
  -- default-node / BC-250 sink graph changes for STARTUP_SETTLE_MS.
  -- This matters because the permanent virtual AC3 sink appears immediately,
  -- while the native HDMI node is intentionally delayed by the ALSA monitor
  -- guard. A fixed delay from daemon start can therefore still expire too soon.
  if startup_settle_source ~= nil then
    startup_settle_source:destroy ()
    startup_settle_source = nil
    log:debug ("startup settle reset: " .. tostring (reason or "graph changed"))
  else
    log:notice ("startup settle: waiting for " ..
        tostring (STARTUP_SETTLE_MS) .. " ms of stable output state")
  end

  startup_settle_source = Core.timeout_add (STARTUP_SETTLE_MS, function ()
    startup_settle_source = nil
    startup_settled = true

    log:notice ("startup settle complete; evaluating configured/default output")
    refresh_desired_from_authority (true)
    reconcile ()
    return false
  end)
end

-- Enforce GLOBAL output semantics for both normal client playback streams and
-- sink-monitor capture streams. The latter matters on KDE / pavucontrol: level
-- meters commonly create Stream/Input/Audio nodes with stream.capture.sink=true.
-- If such a monitor remains linked to native HDMI while AC3 owns hw:Generic,3,
-- PipeWire can wake the suspended native ALSA node and hit EBUSY. Redirecting
-- sink-monitor captures to the current global output keeps native HDMI visible
-- but dormant while AC3 is active.
--
-- This hook intentionally runs before find-defined-target and overwrites any
-- per-application / per-monitor target choice while the selected global mode is
-- native/AC3. Internal BC-250 bridge streams bypass it.
SimpleEventHook {
  name = "linking/bc250-global-output",
  before = "linking/find-defined-target",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function (event)
    local source, om, si, si_props, si_flags, target =
        lutils:unwrap_select_target_event (event)

    if si == nil or si_props == nil then
      return
    end

    if si_props["bc250.internal"] == "true" then
      return
    end

    local media_class = si_props["media.class"]
    local is_playback = media_class == "Stream/Output/Audio"
    local is_sink_monitor_capture =
        media_class == "Stream/Input/Audio" and
        prop_is_true (si_props["stream.capture.sink"])

    if not is_playback and not is_sink_monitor_capture then
      return
    end

    -- Refresh here too, so ordering of the default-nodes "changed" signal vs
    -- a linking rescan can never route a stream according to stale mode state.
    refresh_desired_from_authority ()

    local wanted = effective_target
    if wanted == nil then
      return
    end

    for linkable in om:iterate { type = "SiLinkable" } do
      if linkable.properties["node.name"] == wanted then
        event:set_data ("target", linkable)
        if is_sink_monitor_capture then
          log:debug (si, "sink-monitor capture follows global BC-250 output -> " ..
              tostring (wanted))
        end
        return
      end
    end

    -- During a transition the requested target can briefly be absent. Do not
    -- allow the stock hooks to fall back to the other hw:Generic,3 owner.
    -- Keeping the stream unlinked is safer than risking an EBUSY race.
    log:debug (si, "effective BC-250 target not linkable yet: " .. tostring (wanted))
    event:stop_processing ()
  end
}:register ()

nodes_om:connect ("installed", function (om)
  nodes_ready = true
  log:notice ("BC-250 node object manager ready")
  schedule_startup_settle ("node object manager ready")
end)

nodes_om:connect ("object-added", function (om, node)
  local name = node.properties["node.name"]
  if name == FRONTEND or starts_with (name, NATIVE_PREFIX) then
    if not startup_settled then
      schedule_startup_settle ("BC-250 sink added: " .. tostring (name))
    end
    Core.idle_add (function ()
      refresh_desired_from_authority ()
      reconcile ()
      return false
    end)
  end
end)

nodes_om:connect ("object-removed", function (om, node)
  local name = node.properties["node.name"]
  if name == FRONTEND or starts_with (name, NATIVE_PREFIX) then
    if not startup_settled then
      schedule_startup_settle ("BC-250 sink removed: " .. tostring (name))
    end
    Core.idle_add (function ()
      refresh_desired_from_authority ()
      reconcile ()
      return false
    end)
  end
end)

-- Track the persistent user-selected default directly from PipeWire metadata.
-- This is deliberately separate from default-nodes-api: get-default-node returns
-- the *effective* default, which can temporarily change when HDMI disappears.
local function attach_default_metadata (metadata)
  if default_metadata == metadata and metadata_ready then
    return
  end

  default_metadata = metadata
  metadata_ready = true

  metadata:connect ("changed", function (md, subject, key, value_type, value)
    if subject ~= 0 then
      return
    end
    if key ~= nil and key ~= CONFIGURED_SINK_KEY then
      return
    end

    -- Let the metadata proxy/default-node scripts finish their current event
    -- turn before reading the value back. This also coalesces the UI write and
    -- the consequent default-node rescan into the same desired-mode update.
    Core.idle_add (function ()
      if not startup_settled then
        schedule_startup_settle ("configured default metadata changed")
      else
        refresh_desired_from_authority ()
      end
      return false
    end)
  end)

  log:notice ("BC-250 default metadata ready")
  schedule_startup_settle ("default metadata ready")
end

metadata_om:connect ("object-added", function (om, metadata)
  attach_default_metadata (metadata)
end)

metadata_om:connect ("object-removed", function (om, metadata)
  if metadata == default_metadata then
    default_metadata = nil
    metadata_ready = false
    log:warning ("PipeWire default metadata disappeared; holding current BC-250 mode")
  end
end)

metadata_om:activate ()
nodes_om:activate ()

-- Scripts loaded inside the WirePlumber daemon must not use Core.require_api();
-- that helper is only supported by wpexec. The normal main profile already
-- loads default-nodes-api, so attach to the loaded plugin with Plugin.find().
-- Component ordering is not guaranteed, therefore retry briefly until it is
-- available instead of assuming it exists at this exact instant.
local default_api_retry_source = nil

local function attach_default_nodes_api ()
  if default_nodes_api ~= nil then
    return
  end

  local api = Plugin.find ("default-nodes-api")
  if api == nil then
    if default_api_retry_source == nil then
      default_api_retry_source = Core.timeout_add (100, function ()
        default_api_retry_source = nil
        attach_default_nodes_api ()
        return false
      end)
    end
    return
  end

  default_nodes_api = api

  -- The default-nodes API emits "changed" whenever the effective/default
  -- node selection changes. Re-read Audio/Sink because the signal is shared
  -- by multiple default-node classes.
  default_nodes_api:connect ("changed", function ()
    Core.idle_add (function ()
      if not startup_settled then
        schedule_startup_settle ("default-node selection changed")
      else
        refresh_desired_from_authority ()
      end
      return false
    end)
  end)

  log:notice ("BC-250 default-nodes API ready")
  schedule_startup_settle ("default-nodes API ready")
end


-- The ALSA monitor raises this request when ACP wants to create a native HDMI
-- node while A52 owns hw:Generic,3 (typically DP/HDMI unplug -> replug in AC3
-- mode). Reconcile performs a maintenance release/reprobe/reclaim cycle.
Settings.subscribe (NATIVE_PROBE_SETTING, function ()
  if Settings.get_boolean (NATIVE_PROBE_SETTING) then
    log:notice ("runtime native HDMI reprobe request received")
    Core.idle_add (function ()
      reconcile ()
      return false
    end)
  end
end)

Core.idle_add (function ()
  attach_default_nodes_api ()
  return false
end)
