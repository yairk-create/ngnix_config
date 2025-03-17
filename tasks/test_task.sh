#!/bin/bash
  
  
   echo "Checking if Nginx is installed..."
    if command -v nginx >/dev/null 2>&1; then
        echo  "Nginx is installed."
        return 0
        fi 
    
    
        echo  "Nginx is not installed."
        if [ "$CHECK_ONLY" = true ]; then
            return 1
        fi

