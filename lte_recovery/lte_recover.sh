#!/bin/sh

# ✅ Function: Check if we have a usable WAN link
wait_for_data_connection() {
  echo "[RAIDBOT] ⏳ Waiting for usable WAN link (IP + route)..."
  for i in $(seq 1 20); do
    IP=$(ip -4 -o addr show dev wwan0 | awk '{print $4}')
    if [ -n "$IP" ]; then
      if ip r | grep -q "default via"; then
        if ip route get 8.8.8.8 2>/dev/null | grep -q "dev wwan0"; then
          echo "[RAIDBOT] ✅ WAN is up. IP: $IP"
          return 0
        fi
      fi
    fi
    echo "[RAIDBOT] ...not ready yet ($i/20)"
    sleep 2
  done
  echo "[RAIDBOT] ❌ Timed out waiting for usable link."
  return 1
}

# ✅ Function: Wait until the interface is truly down
wait_for_down() {
  echo "[RAIDBOT] ⏳ Waiting for wwan0 to go down..."
  for i in $(seq 1 10); do
    ip a show dev wwan0 | grep -q "inet " || {
      echo "[RAIDBOT] ✅ Interface down confirmed."
      return 0
    }
    sleep 3
  done
  echo "[RAIDBOT] ⚠️ Interface may still be up."
  return 1
}

# ✅ Function: Wait until modem detaches from PDP session
wait_for_detach() {
  echo "[RAIDBOT] ⏳ Waiting for modem to detach from network..."
  for i in $(seq 1 10); do
    STATUS=$(uqmi -d /dev/cdc-wdm0 --get-data-status 2>/dev/null | grep '"connected"' || true)
    if [ -z "$STATUS" ]; then
      echo "[RAIDBOT] ✅ Modem detached from PDP session."
      return 0
    fi
    echo "[RAIDBOT] ...still attached ($i/10)"
    sleep 2
  done
  echo "[RAIDBOT] ⚠️ Timed out waiting for modem to detach."
  return 1
}

# ✅ Function: Hang-proof stop-network
safe_stop_network() {
  STATUS=$(uqmi -d /dev/cdc-wdm0 --get-data-status 2>/dev/null | grep '"connected"' || true)
  if [ -z "$STATUS" ]; then
    echo "[RAIDBOT] ⚠️ Modem already disconnected — skipping stop-network."
    return 0
  fi

  echo "[RAIDBOT] 🔻 Issuing stop-network with timeout guard..."

  (
    uqmi -d /dev/cdc-wdm0 --stop-network 0xffffffff --autoconnect
  ) &
  STOP_PID=$!

  for i in $(seq 1 10); do
    if ! kill -0 $STOP_PID 2>/dev/null; then
      echo "[RAIDBOT] ✅ stop-network completed (in ${i}s)"
      wait_for_detach
      return 0
    fi
    echo "[RAIDBOT] ...waiting for stop-network to finish ($i/10)"
    sleep 1
  done

  echo "[RAIDBOT] ❌ stop-network hung — killing process..."
  kill -9 $STOP_PID 2>/dev/null
  wait $STOP_PID 2>/dev/null
  echo "[RAIDBOT] ⚠️ stop-network force killed — skipping wait_for_detach."
  return 1
}

# ✅ Function: Kill stuck uqmi and verify
kill_uqmi_safely() {
  echo "[RAIDBOT] 🔪 Killing any stuck uqmi processes..."
  killall -9 uqmi 2>/dev/null
  for i in $(seq 1 5); do
    if ! pgrep uqmi >/dev/null; then
      echo "[RAIDBOT] ✅ uqmi process gone."
      return 0
    fi
    echo "[RAIDBOT] ...still cleaning up ($i/5)"
    sleep 1
  done
  echo "[RAIDBOT] ⚠️ uqmi process may still be running!"
  return 1
}

# ✅ Function: Set APN and confirm it
set_apn_and_confirm() {
  local apn_value="$1"
  echo "[RAIDBOT] 📡 Setting APN to '$apn_value'..."
  uci set network.wwan.apn="$apn_value"
  uci commit network

  for i in $(seq 1 5); do
    CURRENT_APN=$(uci get network.wwan.apn 2>/dev/null)
    if [ "$CURRENT_APN" = "$apn_value" ]; then
      echo "[RAIDBOT] ✅ APN is now '$CURRENT_APN'."
      return 0
    fi
    echo "[RAIDBOT] ...verifying APN ($i/5)"
    sleep 1
  done

  echo "[RAIDBOT] ⚠️ APN setting failed (wanted '$apn_value', got '$CURRENT_APN')."
  return 1
}

# ✅ Function: Set raw_ip=Y and confirm it
set_raw_ip_mode() {
  echo "[RAIDBOT] ⚙️ Setting raw_ip=Y..."
  echo Y > /sys/class/net/wwan0/qmi/raw_ip

  for i in $(seq 1 5); do
    RAW=$(cat /sys/class/net/wwan0/qmi/raw_ip 2>/dev/null || echo "unknown")
    if [ "$RAW" = "Y" ]; then
      echo "[RAIDBOT] ✅ raw_ip confirmed as 'Y'."
      return 0
    fi
    echo "[RAIDBOT] ...verifying raw_ip ($i/5)"
    sleep 1
  done

  echo "[RAIDBOT] ⚠️ raw_ip mode failed to set (still '$RAW')."
  return 1
}

# --- Recovery Sequence Begins ---

kill_uqmi_safely

safe_stop_network

set_apn_and_confirm ''
set_raw_ip_mode

echo "[RAIDBOT] 🛑 ifdown wwan (blank run)..."
ifdown wwan
wait_for_down

echo "[RAIDBOT] 🚀 Bringing up blank APN..."
ifup wwan
if wait_for_data_connection; then
  echo "[RAIDBOT] 🔻 Re-stopping PDP (post-blank)..."
  safe_stop_network
else
  echo "[RAIDBOT] ⚠️ Skipping post-blank PDP stop — WAN never came up."
fi

set_apn_and_confirm 'mobile'
set_raw_ip_mode

echo "[RAIDBOT] 🛑 ifdown wwan (real APN)..."
ifdown wwan
wait_for_down

echo "[RAIDBOT] 🚀 Bringing up real APN (mobile)..."
ifup wwan
if ! wait_for_data_connection; then
  echo "[RAIDBOT] ❌ Final APN bring-up failed — WAN still unreachable."
  exit 1
fi

echo "[RAIDBOT] 🌐 Final ping test..."
ping -c3 8.8.8.8
