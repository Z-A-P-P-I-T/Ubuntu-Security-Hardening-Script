#!/bin/bash

# Update the package list
echo "Updating package list..."
sudo apt update

# Install Lynis if not installed
echo "Installing Lynis..."
sudo apt install -y lynis

# Run Lynis scan and save the output
echo "Running Lynis scan..."
sudo lynis audit system --quiet --logfile /var/log/lynis.log --report-file /var/log/lynis-report.dat > /tmp/lynis-output.txt

# Install recommended packages if available
echo "Installing recommended packages..."
sudo apt install -y libpam-tmpdir apt-listchanges needrestart rkhunter bsd-mailx apt-show-versions debsums

# Install and configure fail2ban if available
echo "Setting up fail2ban..."
if sudo apt install -y fail2ban; then
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    
    # Check if IPv6 is enabled on the system
    if [ -n "$(ip -6 addr show scope global)" ]; then
        echo "IPv6 is enabled on this system. Keeping IPv6 support in Fail2ban."
    else
        echo "IPv6 is not in use. Disabling IPv6 support in Fail2ban."
        sudo sed -i '/\[DEFAULT\]/a allowipv6 = no' /etc/fail2ban/jail.local
    fi

    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
else
    echo "Fail2ban package not found or could not be installed. Skipping..."
fi

# Enable sysstat for accounting
echo "Enabling sysstat..."
sudo apt install -y sysstat
sudo systemctl enable sysstat
sudo systemctl start sysstat

# Install and configure auditd if available
echo "Setting up auditd..."
if sudo apt install -y auditd; then
    echo "-w /etc/passwd -p wa -k passwd_changes" | sudo tee /etc/audit/rules.d/passwd_changes.rules
    echo "-w /etc/group -p wa -k group_changes" | sudo tee /etc/audit/rules.d/group_changes.rules
    echo "-w /etc/shadow -p wa -k shadow_changes" | sudo tee /etc/audit/rules.d/shadow_changes.rules
    sudo augenrules --load
    sudo systemctl enable auditd
    sudo systemctl start auditd
else
    echo "Auditd package not found or could not be installed. Skipping..."
fi

# Install rkhunter and update its configuration
echo "Installing rkhunter for malware scanning..."
sudo apt install -y rkhunter
sudo sed -i 's|WEB_CMD="/bin/true"|WEB_CMD=""|' /etc/rkhunter.conf
echo "Updating rkhunter data files..."
sudo rkhunter --update || echo "RKHunter update failed. Please check /var/log/rkhunter.log for details."
sudo rkhunter --propupd

# Configure legal banners
echo "Configuring legal banners..."
echo "Authorized access only. Unauthorized access is prohibited." | sudo tee /etc/issue
echo "Authorized access only. Unauthorized access is prohibited." | sudo tee /etc/issue.net

# Configure /etc/login.defs for password settings
echo "Configuring password settings in /etc/login.defs..."
sudo sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sudo sed -i 's/^UMASK.*/UMASK   027/' /etc/login.defs

# Disable core dumps if not needed
echo "Disabling core dumps if not required..."
echo '* hard core 0' | sudo tee -a /etc/security/limits.conf

# Manual intervention required for partitioning
echo "Consider adding separate partitions for /home, /tmp, and /var. This requires manual intervention."

# Disable unnecessary protocols (dccp, sctp, rds, tipc)
echo "Disabling unnecessary protocols..."
for protocol in dccp sctp rds tipc; do
    echo "blacklist $protocol" | sudo tee -a /etc/modprobe.d/blacklist.conf
done

# Harden CUPS configuration if applicable
if [ -f /etc/cups/cupsd.conf ]; then
    echo "Reviewing CUPS configuration..."
    sudo chmod 640 /etc/cups/cupsd.conf
    sudo systemctl restart cups
else
    echo "CUPS is not installed or configured on this system."
fi

# Enable process accounting
echo "Enabling process accounting..."
sudo apt install -y acct
sudo systemctl enable acct
sudo systemctl start acct

# Install AIDE for file integrity monitoring
echo "Installing AIDE for file integrity monitoring..."
sudo apt install -y aide
sudo aideinit
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Apply basic sysctl hardening
echo "Applying sysctl hardening..."
sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null <<EOF
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
EOF
sudo sysctl --system

# Restrict compiler access to root only
echo "Restricting compiler access to root only..."
sudo chmod o-rx /usr/bin/gcc /usr/bin/cc

# Check and restart services after library updates if needrestart is available
if command -v needrestart >/dev/null; then
    echo "Checking which services need restarting after library updates..."
    sudo needrestart -r a
else
    echo "Needrestart not found. Please install it manually or skip this step."
fi

# Final message
echo "Security hardening script completed. Please review manual steps and verify changes."
