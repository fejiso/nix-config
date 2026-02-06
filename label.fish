#!/usr/bin/env fish

# 1. Check for sudo/root. 
# Serial numbers are often hidden from standard users for security/hardware reasons.
if test (id -u) -ne 0
    echo (set_color yellow)"Note: Running without sudo. If Serial Numbers appear empty, try running with sudo."(set_color normal)
    echo ""
end

# 2. Print the Header
# We use printf to ensure the columns align perfectly.
printf (set_color blue)"%-12s %-25s %-20s %-30s\n"(set_color normal) "DEVICE" "MODEL" "SERIAL" "PARTITION LABELS"
echo (string repeat -n 90 "-")

# 3. Find all physical disks
# -d: nodeps (don't list partitions yet, just the disk)
# -n: no headings
# -o: output columns
for disk_path in (lsblk -d -n -o PATH,TYPE | string match -r ".* disk" | awk '{print $1}')

    # Extract Model and Serial for this specific disk
    set -l model (lsblk -d -n -o MODEL $disk_path | string trim)
    set -l serial (lsblk -d -n -o SERIAL $disk_path | string trim)

    # If info is missing, set a placeholder
    if test -z "$model"; set model "-"; end
    if test -z "$serial"; set serial "UNKNOWN"; end

    # 4. Find all labels associated with this disk
    # We list all children of the disk, grab the LABEL column, remove empty lines, and join them.
    set -l labels (lsblk -n -o LABEL $disk_path | string trim | string match -v "" | string join ", ")
    
    if test -z "$labels"; set labels "(No labels)"; end

    # 5. Print the row
    printf "%-12s %-25s %-20s %-30s\n" $disk_path $model $serial $labels
end
