#!/usr/bin/env bash

# Waybar-like status bar using Rofi
# Requires: rofi, awk, free, nvidia-smi (optional), intel_gpu_top (optional), radeontop (optional)

# Icons (Nerdfonts)
icon_cpu=""
icon_mem=""
icon_gpu="󰢮"
icon_date="󰃭"
icon_time=""

# Dependency Check
for cmd in rofi awk free grep date sed; do
    if ! command -v "$cmd" >/dev/null; then
        echo "Error: Required command '$cmd' not found. Please install it." | rofi -dmenu -mesg "Missing Dependency: $cmd" -theme-str 'listview { lines: 0; }'
        exit 1
    fi
done

# Get CPU Usage & Name
cpu_name=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | sed -e 's/ with Radeon Graphics//' -e 's/AMD //' -e 's/Processor //' | xargs)
[[ -z "$cpu_name" ]] && cpu_name=$(lscpu | grep 'Model name' | cut -d: -f2 | xargs 2>/dev/null)
[[ -z "$cpu_name" ]] && cpu_name=$(uname -p)
cpu_usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%d%%", usage}')

# Get Memory Usage, Total, and Percentage
read -r mem_total mem_used <<< "$(free -b | awk '/Mem:/ {print $2, $3}')"
mem_total_gb=$(awk "BEGIN {printf \"%.1f\", $mem_total/1024/1024/1024}")
mem_used_gb=$(awk "BEGIN {printf \"%.1f\", $mem_used/1024/1024/1024}")
mem_usage_pct=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")

# Get GPU Usage & Name
gpu_name="GPU"
gpu_usage="N/A"
if command -v nvidia-smi >/dev/null; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | xargs)
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk '{print $1"%"}')
elif command -v glxinfo >/dev/null; then
    gpu_name=$(glxinfo -B | grep "Device" | cut -d: -f2 | xargs | cut -d'(' -f1 | sed 's/AMD //' | xargs)
fi

# Fallback for GPU usage if not Nvidia
if [[ "$gpu_usage" == "N/A" ]]; then
    # Intel/AMD patterns via sysfs
    amd_gpu_path=$(find /sys/class/drm/card*/device/hwmon/hwmon*/ -name "device/gpu_busy_percent" 2>/dev/null | head -n 1)
    intel_gpu_path=$(find /sys/class/drm/card*/device/ -name "i915_gpu_busy_percent" 2>/dev/null | head -n 1)
    
    if [[ -n "$amd_gpu_path" ]]; then
        gpu_usage=$(cat "$amd_gpu_path")"%"
    elif [[ -n "$intel_gpu_path" ]]; then
        gpu_usage=$(cat "$intel_gpu_path")"%"
    fi
fi

# Get Date, Time, Uptime, and OS Info
clock_time="$(date +"%H:%M")"
date_only="$(date +"%A, %d %B")"
boot_time=$(uptime -s | awk '{print $2}' | cut -d: -f1,2)
uptime_dur=$(uptime -p | sed 's/up //')
os_name=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
kernel_ver=$(uname -r)
os_technical="${os_name} ${kernel_ver}"

# Combine Clock and Uptime with Pango markup
clock_mesg="${clock_time}
<span font='JetBrainsMono Nerd Font 10' weight='light' foreground='#cccccc'>Active since <span foreground='#f9e2af'>${boot_time}</span> for <span foreground='#f9e2af'>${uptime_dur}</span></span>"

# Combine Date and OS with Pango markup (Using \\n for RASI compatibility)
# Moved date up with extra newline, OS info now 15pt and Pink (#f5c2e7)
date_os_str="${date_only}\\n\\n<span font='JetBrainsMono Nerd Font 15' weight='light' foreground='#f5c2e7'>${os_technical}</span>"

# Construct hardware items (Pure Text, Neutral Separators)
status_items=""
status_items+="<span color='#a6e3a1'>$icon_cpu  $cpu_name</span> | <span color='#a6e3a1'>$cpu_usage</span>\n"
status_items+="<span color='#89b4fa'>$icon_mem  RAM ${mem_total_gb}Gb</span> | <span color='#89b4fa'>${mem_used_gb}Gb ${mem_usage_pct}%</span>\n"
status_items+="<span color='#fab387'>$icon_gpu  $gpu_name</span> | <span color='#fab387'>$gpu_usage</span>"

# Launch Rofi
echo -e "$status_items" | rofi -dmenu \
    -markup-rows \
    -theme "$HOME/.config/rofi/statusbar.rasi" \
    -theme-str "textbox-date { content: \"$date_os_str\"; }" \
    -mesg "${clock_mesg}"
