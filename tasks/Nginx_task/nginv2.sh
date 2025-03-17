#!/bin/bash

# ANSI color codes for terminal output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# gathring information on the OS  
 source /etc/os-release && echo $NAME $ID 

# Define package arrays for each component
userdir_array=(nginx-extras apache2-utils)
auth_array=(nginx-extras apache2-utils libssl-dev)
pam_array=(libnginx-mod-http-auth-pam libpam0g-dev)
cgi_array=(nginx-extras fcgiwrap spawn-fcgi)

# Flag variables to track which components to install
install_userdir=false
install_auth=false
install_cgi=false
install_pam=false
configure_vhost=false
show_help=false

function display_help() {
    printf "\n${GREEN}Nginx Installation and Configuration Script${NC}\n"
    printf "\nUsage: $0 [options]\n"
    printf "\nOptions:\n"
    printf "  -h, --help       Display this help message and exit\n"
    printf "  -u, --userdir    Install and configure user directory module\n"
    printf "  -a, --auth       Install and configure authentication module\n"
    printf "  -c, --cgi        Install and configure CGI module\n"
    printf "  -p, --pam        Install and configure PAM authentication\n"
    printf "  -v, --vhost      Configure a virtual host\n"
    printf "  --all            Install and configure all modules\n"
    printf "\nExample: $0 --userdir --cgi\n\n"
}


function parse_arguments() {
    # Parse command line arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help=true
                ;;
            -u|--userdir)
                install_userdir=true
                ;;
            -a|--auth)
                install_auth=true
                ;;
            -c|--cgi)
                install_cgi=true
                ;;
            -p|--pam)
                install_pam=true
                ;;
            -v|--vhost)
                configure_vhost=true
                ;;
            --all)
                install_userdir=true
                install_auth=true
                install_cgi=true
                install_pam=true
                configure_vhost=true
                ;;
            *)
                printf "${RED}Unknown option: $1${NC}\n"
                display_help
                exit 1
                ;;
        esac
        shift
    done

    # If no arguments provided, display help
    if [[ "$install_userdir" == "false" && "$install_auth" == "false" && "$install_cgi" == "false" && "$install_pam" == "false" && "$configure_vhost" == "false" && "$show_help" == "false" ]]; then
        printf "${YELLOW}No options specified.${NC}\n"
        display_help
        exit 1
    fi

    # If help requested, display help and exit
    if [[ "$show_help" == "true" ]]; then
        display_help
        exit 0
    fi
}

function check_priviliges() {
    if [[ $EUID -ne 0 ]]; then
        printf "\n${YELLOW}This "$0" requires root privileges.\n"
        # printf "Re-launching with sudo.\n\n${NC}"
        exec sudo "$0" "$@"  # Restart script with sudo
        exit 1
    fi
}




function check_nginx_installed() {
    printf "\n${GREEN}Checking if Nginx is installed.${NC}\n"
    
    if command -v nginx > /dev/null 2>&1; then
        printf "${GREEN}Nginx is already installed.${NC}\n"
        return 0
    else
        printf "${BLUE}Trying to install nginx.${NC}\n"
        sudo apt update && sudo apt install nginx -y
        
        if ! command -v nginx > /dev/null 2>&1; then
            printf "${RED}Nginx failed to be installed.${NC}\n" 
            return 1
        fi
        printf "${GREEN}Nginx has been successfully installed.${NC}\n"
        return 0
    fi
}

function configure_vhost() {
    local website="/etc/nginx/sites-enabled/"
    
    printf "\n${GREEN}Configuring Virtual Host${NC}\n"

    # Check if any virtual hosts exist
    if [ "$(ls -A $website 2>/dev/null | wc -l)" -gt 0 ]; then
        printf "${YELLOW}There are existing virtual hosts configured. Do you want to continue? (y/n): ${NC}"
        read continue_config
        
        if [[ $continue_config != "y" && $continue_config != "Y" ]]; then
            printf "${YELLOW}Virtual host configuration skipped.${NC}\n"
            return 1
        fi
    fi

    printf "${BLUE}Enter the domain name for the virtual host (e.g., example.com): ${NC}"
    read domain_name
    
    if [ -z "$domain_name" ]; then
        printf "${RED}No domain name provided. Skipping virtual host configuration.${NC}\n"
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
        systemctl restart nginx
        printf "${GREEN}Virtual host for $domain_name has been configured successfully.${NC}\n"
        return 0
    else
        printf "${RED}Nginx configuration test failed. Please check the syntax.${NC}\n"
        return 1
    fi
}

function install_packages() {
    local package_array=("$@")

    printf "\n${GREEN}Installing packages: ${package_array[@]}${NC}\n"

    for package in "${package_array[@]}"; do
        # Check if package is already installed
        if dpkg -l | grep -q "^ii  $package "; then
            printf "${GREEN}$package is already installed${NC}.\n"
            continue
        fi
        
        printf "${BLUE}Installing $package${NC}.\n"
        
        if ! sudo apt install -y $package; then
            printf "${RED}Failed to install $package${NC}.\n"
        else
            printf "${GREEN}Successfully installed $package${NC}.\n"
        fi
    done
}

function configure_userdir() {
    printf "\n${GREEN}Configuring user directory module${NC}\n"
    
    # Enable userdir module if not already enabled
    if ! grep -q "userdir_module" /etc/nginx/modules-enabled/ 2>/dev/null; then
        printf "${BLUE}Enabling userdir module${NC}\n"
        
        # Create userdir configuration if it doesn't exist
        if [ ! -f /etc/nginx/conf.d/userdir.conf ]; then
            cat > /etc/nginx/conf.d/userdir.conf << EOF
# User directory configuration
server {
    listen 80;
    server_name localhost;

    location ~ ^/~(.+?)(/.*)?$ {
        alias /home/\$1/public_html\$2;
        index index.html index.htm;
        autoindex on;
    }
}
EOF
            printf "${GREEN}Created userdir configuration${NC}\n"
        fi
    else
        printf "${GREEN}Userdir module is already enabled${NC}\n"
    fi
    
    # Test nginx configuration
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl restart nginx
        printf "${GREEN}User directory module has been configured successfully.${NC}\n"
    else
        printf "${RED}Nginx configuration test failed. Please check the syntax.${NC}\n"
    fi
}

function configure_auth() {
    printf "\n${GREEN}Configuring authentication module${NC}\n"
    
    # Prompt for auth directory path
    printf "${BLUE}Enter the path to protect with authentication (e.g., /admin): ${NC}"
    read auth_path
    
    if [ -z "$auth_path" ]; then
        printf "${RED}No path provided. Skipping authentication configuration.${NC}\n"
        return 1
    fi
    
    # Prompt for auth realm name
    printf "${BLUE}Enter a realm name for the authentication: ${NC}"
    read realm_name
    
    if [ -z "$realm_name" ]; then
        realm_name="Restricted Area"
    fi
    
    # Create auth user
    printf "${BLUE}Enter a username for authentication: ${NC}"
    read auth_user
    
    if [[ -z "$auth_user" ]]; then
        printf "${RED}No username provided. Skipping authentication configuration.${NC}\n"
        return 1
    fi
    
    # Create htpasswd file if it doesn't exist
    if [[ ! -d /etc/nginx/auth ]]; then
        mkdir -p /etc/nginx/auth
    fi
    
    if [[ ! -f /etc/nginx/auth/.htpasswd ]]; then
        touch /etc/nginx/auth/.htpasswd
    fi
    
    printf "${BLUE}Creating password for user $auth_user${NC}\n"
    htpasswd -c /etc/nginx/auth/.htpasswd $auth_user
    
    # Update nginx configuration
    # Check if we have virtual hosts configured
    if [ "$(ls -A /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)" -gt 0 ]; then
        printf "${BLUE}Do you want to apply authentication to a specific virtual host? (y/n): ${NC}"
        read specific_vhost
        
        if [[ $specific_vhost == "y" || $specific_vhost == "Y" ]]; then
            printf "${BLUE}Available virtual hosts:${NC}\n"
            ls -1 /etc/nginx/sites-enabled/
            printf "${BLUE}Enter the virtual host name to modify: ${NC}"
            read vhost_name
            
            if [ -n "$vhost_name" ] && [ -f /etc/nginx/sites-available/$vhost_name ]; then
                # Backup original config
                cp /etc/nginx/sites-available/$vhost_name /etc/nginx/sites-available/$vhost_name.bak
                
                # Add auth configuration to the virtual host
                sed -i "/location $auth_path {/,/}/d" /etc/nginx/sites-available/$vhost_name
                
                # Append auth location to the server block
                sed -i "/server_name/a \\\n    # Authentication for $auth_path\n    location $auth_path {\n        auth_basic \"$realm_name\";\n        auth_basic_user_file /etc/nginx/auth/.htpasswd;\n    }" /etc/nginx/sites-available/$vhost_name
                
                printf "${GREEN}Added authentication to $vhost_name for path $auth_path${NC}\n"
            else
                printf "${RED}Virtual host not found.${NC}\n"
                return 1
            fi
        else
            # Add to default config
            if [[ -f /etc/nginx/sites-available/default ]]; then
                # Backup original config
                cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
                
                # Add auth configuration to the default site
                sed -i "/location $auth_path {/,/}/d" /etc/nginx/sites-available/default
                
                # Append auth location to the server block
                sed -i "/server_name/a \\\n    # Authentication for $auth_path\n    location $auth_path {\n        auth_basic \"$realm_name\";\n        auth_basic_user_file /etc/nginx/auth/.htpasswd;\n    }" /etc/nginx/sites-available/default
                
                printf "${GREEN}Added authentication to default site for path $auth_path${NC}\n"
            else
                printf "${RED}Default site configuration not found.${NC}\n"
                return 1
            fi
        fi
    else
        # No virtual hosts, create a simple auth configuration
        cat > /etc/nginx/conf.d/auth.conf << EOF
# Authentication configuration
server {
    listen 80;
    server_name localhost;

    location $auth_path {
        auth_basic "$realm_name";
        auth_basic_user_file /etc/nginx/auth/.htpasswd;
        
        # You may want to set the document root for this location
        root /var/www/html;
        index index.html;
    }
}
EOF
        printf "${GREEN}Created authentication configuration for path $auth_path${NC}\n"
    fi
    
    # Test nginx configuration
    nginx -t
    if [[ $? -eq 0 ]]; then
        systemctl restart nginx
        printf "${GREEN}Authentication has been configured successfully for path $auth_path${NC}\n"
    else
        printf "${RED}Nginx configuration test failed. Please check the syntax.${NC}\n"
    fi
}

function configure_cgi() {
    printf "\n${GREEN}Configuring CGI module${NC}\n"
    
    # First, make sure fcgiwrap service is running
    systemctl start fcgiwrap
    systemctl enable fcgiwrap
    
    # Prompt for CGI directory path
    printf "${BLUE}Enter the path for CGI scripts (e.g., /cgi-bin): ${NC}"
    read cgi_path
    
    if [[ -z "$cgi_path" ]]; then
        cgi_path="/cgi-bin"
    fi
    
    # Create the CGI directory if it doesn't exist
    mkdir -p /var/www/cgi-bin
    chown www-data:www-data /var/www/cgi-bin
    chmod 755 /var/www/cgi-bin
    
    # Create a sample CGI script
    cat > /var/www/cgi-bin/test.cgi << 'EOF'
#!/bin/bash
echo "Content-type: text/html"
echo ""
echo "<html><head><title>CGI Test</title></head>"
echo "<body>"
echo "<h1>CGI Script Test</h1>"
echo "<p>This is a test CGI script. If you can see this, CGI is working!</p>"
echo "<h2>Environment Variables:</h2>"
echo "<pre>"
env | sort
echo "</pre>"
echo "</body></html>"
EOF
    
    chmod +x /var/www/cgi-bin/test.cgi
    
    # Update nginx configuration
    # Check if we have virtual hosts configured
    if [[ "$(ls -A /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)" -gt 0 ]]; then
        printf "${BLUE}Do you want to apply CGI configuration to a specific virtual host? (y/n): ${NC}"
        read specific_vhost
        
        if [[ $specific_vhost == "y" || $specific_vhost == "Y" ]]; then
            printf "${BLUE}Available virtual hosts:${NC}\n"
            ls -1 /etc/nginx/sites-enabled/
            printf "${BLUE}Enter the virtual host name to modify: ${NC}"
            read vhost_name
            
            if  [[ -n "$vhost_name" ]] && [[ -f /etc/nginx/sites-available/$vhost_name ]]; then
                # Backup original config
                cp /etc/nginx/sites-available/$vhost_name /etc/nginx/sites-available/$vhost_name.bak
                
                # Add CGI configuration to the virtual host
                sed -i "/location $cgi_path {/,/}/d" /etc/nginx/sites-available/$vhost_name
                
                # Append CGI location to the server block
                sed -i "/server_name/a \\\n    # CGI configuration\n    location $cgi_path {\n        root /var/www;\n        fastcgi_pass unix:/var/run/fcgiwrap.socket;\n        include fastcgi_params;\n        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\n    }" /etc/nginx/sites-available/$vhost_name
                
                printf "${GREEN}Added CGI configuration to $vhost_name for path $cgi_path${NC}\n"
            else
                printf "${RED}Virtual host not found.${NC}\n"
                return 1
            fi
        else
            # Add to default config
            if [[ -f /etc/nginx/sites-available/default ]]; then
                # Backup original config
                cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
                
                # Add CGI configuration to the default site
                sed -i "/location $cgi_path {/,/}/d" /etc/nginx/sites-available/default
                
                # Append CGI location to the server block
                sed -i "/server_name/a \\\n    # CGI configuration\n    location $cgi_path {\n        root /var/www;\n        fastcgi_pass unix:/var/run/fcgiwrap.socket;\n        include fastcgi_params;\n        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\n    }" /etc/nginx/sites-available/default
                
                printf "${GREEN}Added CGI configuration to default site for path $cgi_path${NC}\n"
            else
                printf "${RED}Default site configuration not found.${NC}\n"
                return 1
            fi
        fi
    else
        # No virtual hosts, create a simple CGI configuration
        cat > /etc/nginx/conf.d/cgi.conf << EOF
# CGI configuration
server {
    listen 80;
    server_name localhost;

    location $cgi_path {
        root /var/www;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
        printf "${GREEN}Created CGI configuration for path $cgi_path${NC}\n"
    fi
    
    # Test nginx configuration
    nginx -t
    if [[ $? -eq 0 ]]; then
        systemctl restart nginx
        printf "${GREEN}CGI has been configured successfully for path $cgi_path${NC}\n"
        printf "${BLUE}You can test it by visiting: http://your-server$cgi_path/test.cgi${NC}\n"
    else
        printf "${RED}Nginx configuration test failed. Please check the syntax.${NC}\n"
    fi
}

function configure_pam() {
    printf "\n${GREEN}Configuring PAM authentication module${NC}\n"
    
    # Prompt for auth directory path
    printf "${BLUE}Enter the path to protect with PAM authentication (e.g., /secure): ${NC}"
    read pam_path
    
    if [[ -z "$pam_path" ]]; then
        printf "${RED}No path provided. Skipping PAM authentication configuration.${NC}\n"
        return 1
    fi
    
    # Create PAM configuration for Nginx if it doesn't exist
    if [[ ! -f /etc/pam.d/nginx ]]; then
        cat > /etc/pam.d/nginx << EOF
# PAM configuration for Nginx
@include common-auth
@include common-account
EOF
        printf "${GREEN}Created PAM configuration for Nginx${NC}\n"
    fi
    
    # Update nginx configuration
    # Check if we have virtual hosts configured
    if [[ "$(ls -A /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)" -gt 0 ]]; then
        printf "${BLUE}Do you want to apply PAM authentication to a specific virtual host? (y/n): ${NC}"
        read specific_vhost
        
        if [[ $specific_vhost == "y" || $specific_vhost == "Y" ]]; then
            printf "${BLUE}Available virtual hosts:${NC}\n"
            ls -1 /etc/nginx/sites-enabled/
            printf "${BLUE}Enter the virtual host name to modify: ${NC}"
            read vhost_name
            
            if [[ -n "$vhost_name" ]] && [[ -f /etc/nginx/sites-available/$vhost_name ]]; then
                # Backup original config
                cp /etc/nginx/sites-available/$vhost_name /etc/nginx/sites-available/$vhost_name.bak
                
                # Add PAM configuration to the virtual host
                sed -i "/location $pam_path {/,/}/d" /etc/nginx/sites-available/$vhost_name
                
                # Append PAM location to the server block
                sed -i "/server_name/a \\\n    # PAM authentication for $pam_path\n    location $pam_path {\n        auth_pam \"Secure Area\";\n        auth_pam_service_name \"nginx\";\n    }" /etc/nginx/sites-available/$vhost_name
                
                printf "${GREEN}Added PAM authentication to $vhost_name for path $pam_path${NC}\n"
            else
                printf "${RED}Virtual host not found.${NC}\n"
                return 1
            fi
        else
            # Add to default config
            if [[ -f /etc/nginx/sites-available/default ]]; then
                # Backup original config
                cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
                
                # Add PAM configuration to the default site
                sed -i "/location $pam_path {/,/}/d" /etc/nginx/sites-available/default
                
                # Append PAM location to the server block
                sed -i "/server_name/a \\\n    # PAM authentication for $pam_path\n    location $pam_path {\n        auth_pam \"Secure Area\";\n        auth_pam_service_name \"nginx\";\n    }" /etc/nginx/sites-available/default
                
                printf "${GREEN}Added PAM authentication to default site for path $pam_path${NC}\n"
            else
                printf "${RED}Default site configuration not found.${NC}\n"
                return 1
            fi
        fi
    else
        # No virtual hosts, create a simple PAM configuration
        cat > /etc/nginx/conf.d/pam_auth.conf << EOF
# PAM Authentication configuration
server {
    listen 80;
    server_name localhost;

    location $pam_path {
        auth_pam "Secure Area";
        auth_pam_service_name "nginx";
        
        # You may want to set the document root for this location
        root /var/www/html;
        index index.html;
    }
}
EOF
        printf "${GREEN}Created PAM authentication configuration for path $pam_path${NC}\n"
    fi
    
    # Test nginx configuration
    nginx -t
    if [[ $? -eq 0 ]]; then
        systemctl restart nginx
        printf "${GREEN}PAM authentication has been configured successfully for path $pam_path${NC}\n"
    else
        printf "${RED}Nginx configuration test failed. Please check the syntax.${NC}\n"
    fi
}

function main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check privileges
    check_priviliges
    
    # Ensure Nginx is installed
    check_nginx_installed
    
    # Determine which packages to install
    declare -a packages_to_install=()
    
    if [[ "$install_userdir" == "true" ]]; then
        packages_to_install+=("${userdir_array[@]}")
    fi
    
    if [[ "$install_auth" == "true" ]]; then
        packages_to_install+=("${auth_array[@]}")
    fi
    
    if [[ "$install_cgi" == "true" ]]; then
        packages_to_install+=("${cgi_array[@]}")
    fi
    
    if [[ "$install_pam" == "true" ]]; then
        packages_to_install+=("${pam_array[@]}")
    fi
    
    # Get unique packages
    unique_packages=($(echo "${packages_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    # Install required packages
    if [ ${#unique_packages[@]} -gt 0 ]; then
        install_packages "${unique_packages[@]}"
    fi
    
    # Configure virtual host if requested
    if [[ "$configure_vhost" == "true" ]]; then
        configure_vhost
    fi
    
    # Configure modules as requested
    if [[ "$install_userdir" == "true" ]]; then
        configure_userdir
    fi
    
    if [[ "$install_auth" == "true" ]]; then
        configure_auth
    fi
    
    if [[ "$install_cgi" == "true" ]]; then
        configure_cgi
    fi
    
    if [[ "$install_pam" == "true" ]]; then
        configure_pam
    fi
    
    printf "\n${GREEN}Nginx installation and configuration completed!${NC}\n"
}

# Call main function with all command line arguments
main "$@"