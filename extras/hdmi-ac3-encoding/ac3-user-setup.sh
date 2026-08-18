#!/bin/bash
# AC-3 Surround Encoding — user-session setup script
# Runs as the real user (not root) to interact with PipeWire/WirePlumber.
# Called by start.sh install_ac3_surround and run_revert_ac3_surround.

ACTION="${1:-install}"
WP_CONF_DIR="${HOME}/.config/wireplumber/wireplumber.conf.d"
WP_CONF="${WP_CONF_DIR}/ac3-profile.conf"

case "$ACTION" in
    install)
        # Write WirePlumber config
        mkdir -p "$WP_CONF_DIR"
        cat > "$WP_CONF" << 'WPEOF'
# Enable AC-3 (Dolby Digital) encoding profiles for HDMI/DP audio.
# The BC-250 DMI identifies as "AMD BC-250" instead of "OEM F7F", so
# SteamOS's valve-fremont hardware profile (which sets device.profile-set
# to hdmi-ac3.conf) is never loaded. This config replicates those rules.
monitor.alsa.rules = [
  {
    matches = [
      {
        device.name = "~alsa_card.pci-.*"
        device.nick = "~HD-Audio Generic"
      }
    ]
    actions = {
      update-props = {
        device.description = "HDMI / DisplayPort"
        api.acp.disable-pro-audio = true
        device.profile-set = "hdmi-ac3.conf"
        device.routes.default-sink-volume = 1.0
      }
    }
  }
  {
    matches = [
      {
        node.name = "~alsa_output.pci-.*hdmi.*"
      }
    ]
    actions = {
      update-props = {
        # Keep sink alive for 1 hour after last sound to prevent receiver
        # from falling back to PCM between tracks/dialogue pauses.
        session.suspend-timeout-seconds = 3600
      }
    }
  }
  {
    matches = [
      {
        node.name = "~alsa_output.pci-.*hdmi.*"
        alsa.name = "~a52.*"
      }
    ]
    actions = {
      update-props = {
        # Collect one AC3 frame (1536 samples) before starting playback,
        # else the a52 plugin EPIPEs on startup.
        api.alsa.start-delay = 1536
      }
    }
  }
]
WPEOF

        # Restart WirePlumber
        systemctl --user restart wireplumber 2>/dev/null || true

        # Wait for WirePlumber to become active
        wp_ready=0
        for ((i=0; i<15; i++)); do
            sleep 1
            if systemctl --user is-active wireplumber 2>/dev/null | grep -q "active"; then
                wp_ready=1
                break
            fi
        done
        # Give WP extra time to probe the card with the new profile set
        sleep 3

        # Detect card name — get the first card with HDMI audio
        card_name=$(pactl list cards 2>/dev/null | grep "Name:" | awk '{print $2}' | head -1)
        if [[ -z "$card_name" ]]; then
            echo "ERROR: No HDMI/DP audio card found"
            exit 1
        fi
        echo "CARD=$card_name"

        # Select AC-3 profile
        if ! pactl set-card-profile "$card_name" output:hdmi-ac3-surround 2>/dev/null; then
            echo "WARN: Could not set output:hdmi-ac3-surround on $card_name, trying fallback..."
            pactl set-card-profile "$card_name" output:hdmi-ac3-surround 2>/dev/null || true
        fi
        sleep 1

        # Find and set AC-3 sink as default
        ac3_sink=$(pactl list sinks short 2>/dev/null | grep "hdmi-ac3-surround" | awk '{print $2}' | head -1)
        if [[ -n "$ac3_sink" ]]; then
            pactl set-default-sink "$ac3_sink" 2>/dev/null
            echo "SINK=$ac3_sink"
            echo "SUCCESS"
        else
            echo "ERROR: AC-3 profile selected but no sink created"
            exit 1
        fi
        ;;

    revert)
        # Remove WirePlumber config
        rm -f "$WP_CONF"

        # Restart WirePlumber
        systemctl --user restart wireplumber 2>/dev/null || true

        # Wait for WirePlumber
        for ((i=0; i<10; i++)); do
            sleep 1
            if systemctl --user is-active wireplumber 2>/dev/null | grep -q "active"; then
                break
            fi
        done

        # Restore stereo profile
        card_name=$(pactl list cards 2>/dev/null | grep "Name:" | awk '{print $2}' | head -1)
        if [[ -n "$card_name" ]]; then
            pactl set-card-profile "$card_name" output:hdmi-stereo 2>/dev/null || true
        fi
        sleep 1

        stereo_sink=$(pactl list sinks short 2>/dev/null | grep "hdmi-stereo" | awk '{print $2}' | head -1)
        if [[ -n "$stereo_sink" ]]; then
            pactl set-default-sink "$stereo_sink" 2>/dev/null
        fi
        echo "REVERTED"
        ;;

    detect)
        # Just detect the card
        card_name=$(pactl list cards 2>/dev/null | grep "Name:" | awk '{print $2}' | head -1)
        if [[ -n "$card_name" ]]; then
            echo "CARD=$card_name"
        else
            echo "CARD="
        fi

        # Check if AC-3 profile is active
        active=$(pactl list cards 2>/dev/null | grep "Active Profile" | grep -q "ac3" && echo "yes" || echo "no")
        echo "AC3_ACTIVE=$active"
        ;;

    diag)
        # Run diagnostic pactl commands for the diagnostic log
        echo "== Audio Card =="
        pactl list cards 2>/dev/null | grep -A30 "HD-Audio Generic" || echo "No HD-Audio Generic card found"
        echo ""
        echo "== PipeWire Sinks =="
        pactl list sinks short 2>/dev/null || echo "N/A"
        echo ""
        echo "== Default Sink =="
        pactl get-default-sink 2>/dev/null || echo "N/A"
        echo ""
        echo "== WirePlumber Status =="
        systemctl --user status wireplumber --no-pager 2>&1 | head -15 || true
        ;;

    test)
        # Run speaker-test
        ac3_sink="$2"
        timeout 15 speaker-test -D "$ac3_sink" -c 6 -t sine -l 1 -p 1 2>&1 || true
        ;;

    *)
        echo "Usage: $0 {install|revert|detect|diag|test [sink]}"
        exit 1
        ;;
esac
