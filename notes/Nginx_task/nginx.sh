#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'


# Define package arrays properly
userdir_array=(nginx-extras apache2-utils)
auth_array=(nginx-extras apache2-utils libssl-dev)
pam_array=(libnginx-mod-http-auth-pam libpam0g-dev)
cgi_array=(nginx-extras fcgiwrap spawn-fcgi)



# Flag variables to track which to install
install_userdir=false
install_auth=false
install_cgi=false
install_pam=false
configure_vhost=false
show_help=false



function menu() {
    printf "\n${GREEN}Nginx Installation and Configuration Script${NC}\n"
    printf "\nUsage: $0 [options]\n"
    printf "  -h, --help       Display this help message and exit\n"
    printf "  -u, --userdir    Install and configure user directory module\n"
    printf "  -a, --auth       Install and configure authentication module\n"
    printf "  -c, --cgi        Install and configure CGI module\n"
    printf "  -p, --pam        Install and configure PAM authentication\n"
    printf "  -v, --vhost      Configure a virtual host\n"
    printf "  --all            Install and configure all modules\n"
    printf "\nExample: $0 --userdir --cgi\n\n"
}



function prase_arguments(){

while [[ "$#" -ge 0 ]];do

case "$1" in

 -h|--help)
                show_help=true
                ;;
-u|--userdir)   
                install_userdir=true
                ;;

                *)
                printf "Unkown option"
                ;;

                esac
                done 












}



function check_os() {
       
 if ! [ -f /etc/os-release ]; then
   
     printf "\n{$RED} ERROR: /etc/os-release file bot found.\n{$NC} "

       return 1
 fi   

. /etc/os-release 

if  [[ "$NAME" == *"Debian"* ]] || [[  "$ID" == "debian"  ]];then 

        return 0
else         
       printf "n\{$RED}The script can run only on debian based distribution.\n{$NC}"
       
       return 1

fi

}










function check_priviliges() {
    if [[ $EUID -ne 0 ]]; then
        printf "\n${YELLOW}This script requires root privileges.\n"
        printf "Re-launching with sudo.\n\n"
        exec sudo "$0" "$@"  # Restart script with sudo
        exit 1
    fi
}

function check_nginx_installed() {
    printf "\n${GREEN}Checking if Nginx is installed.${NC}\n"
    
    if command -v nginx > /dev/null 2>&1; then
        printf "\n${GREEN}Nginx is already installed.${NC}\n"
        return 0
    else
        printf "\n${BLUE}Trying to install nginx.${NC}\n"
        sudo apt update && sudo apt install nginx -y
        
        if ! command -v nginx > /dev/null 2>&1; then
            printf "\n${RED}Nginx failed to be installed.${NC}\n" 
            return 1
        fi
        return 0
    fi
}

function check_vhost() {
    local website="/etc/nginx/sites-enabled/"
    
    # Check if any virtual hosts exist
    if [ -z "$(ls -A $website 2>/dev/null)" ]; then
        printf "\n${RED}Virtual host is not configured${NC}\n"
    fi

    if [ "$(ls -A $website 2>/dev/null | wc -l)" -gt 0 ]; then
    printf "\n${YELLOW}There is a Virtual host configured${NC}\n"

   
fi


    printf "\n${BLUE}To configure virtual host, enter the domain name for the virtual host (e.g., example.com): ${NC}"
    read domain_name
    
    if [ -z "$domain_name" ]; then
        echo -e "${RED}No domain name provided. Skipping virtual host configuration.${NC}"
        return 1
    fi

 
    
    # Create directory structure
    mkdir -p /var/www/$domain_name/html
    chown -R www-data:www-data /var/www/$domain_name
    chmod -R 755 /var/www/$domain_name
    
    # Create a sample index.html
    cat > /var/www/$domain_name/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $domain_name</title>
</head>
<body>
    <h1>Success! $domain_name is working!</h1>
</body>
</html>
EOF
    
    # Create the virtual host configuration file
    cat > /etc/nginx/sites-available/$domain_name << EOF
server {
    listen 80;
    listen [::]:80;
    
    root /var/www/$domain_name/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name $domain_name www.$domain_name;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    # Enable the virtual host
    if [ -d /etc/nginx/sites-enabled ]; then
        ln -s /etc/nginx/sites-available/$domain_name /etc/nginx/sites-enabled/
    fi
    
    # Test nginx configuration
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        echo -e "${GREEN}Virtual host for $domain_name has been configured successfully.${NC}"
        return 0
    else
        echo -e "${RED}Nginx configuration test failed. Please check the syntax.${NC}"
        return 1
    fi
}

function app_install() {
    local package_array=("$@")

    echo -e "\n${GREEN}Installing packages: \n ${package_array[@]}${NC}"

    for package in "${package_array[@]}"; do
        # Check if package is already installed
        if dpkg -l | grep -q "^ii  $package "; then
            echo -e "${GREEN}$package is already installed${NC}.\n"
            else 
             echo -e "\n${GREEN}Installing $package${NC}.\n"
             
        fi
        
       
        
        if ! sudo apt install -y $package; then
            echo -e "${RED}Failed to install $package${NC}.\n"
        fi
    done
}





# Combine all arrays
all_packages=(${userdir_array[@]} ${auth_array[@]} ${cgi_array[@]} ${pam_array[@]})

# Get unique packages
unique_packages=($(echo "${all_packages[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))


function main() {     
   
    menu
    check_os
    check_priviliges
    check_nginx_installed
    check_vhost

 declare -a packages_to_install=()

 if [[ $install_userdir == "true"  ]]; then

  packages_to_install+=("${userdir_array[@]}")

  packages_to_install+=("${userdir_array[@]}")


    app_install "${unique_packages[@]}"
}

main