#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to read password securely
read_password() {
    unset password
    prompt="$1"
    echo -e -n "${YELLOW}$prompt${NC}"
    while IFS= read -r -s -n 1 char; do
        # Check for Enter key (end of password input)
        if [[ -z $char ]]; then
            break
        fi
        # Check for Backspace (delete last character)
        if [[ $char == $'\177' ]]; then
            if [ ${#password} -gt 0 ]; then
                password=${password::-1}
                echo -en "\b \b"
            fi
        else
            password+="$char"
            echo -n "*"
        fi
    done
    echo
}

# User Prompt
echo -e "\n${YELLOW}Please enter database connection details:${NC}\n"
echo ""
echo -e -n "${YELLOW}DB Host URL: ${NC}"
read db_host
echo ""
echo -e -n "${YELLOW}Username: ${NC}"
read username
echo ""
read_password "Password: "
echo ""
echo -e -n "${YELLOW}Ticket Number: ${NC}"
read ticket_num

# Connection established animation
echo -n "Establishing connection..."

for i in {1..4}; do
    echo -n "."
    sleep 0.3
done
echo -e "\nConnection Established!"

# List databases
echo -e "\n${GREEN}Connection established successfully!!${NC}"
echo -e "\n${YELLOW}Available databases:${NC}"
databases=$(mysql -h "$db_host" -u "$username" -p"$password" -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database")

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to database. Please check your credentials.${NC}"
    exit 1
fi

echo "$databases"
echo ""

echo -e -n "${YELLOW}Enter database name from the above list: ${NC}"
echo ""

read db_name

# Generate backup filename
curr_date=$(date +"%d%b")
backup_file="${ticket_num}${db_name}${curr_date}.sql"
backup_path="/home/ubuntu/Backup/$backup_file"

# Take backup
echo -e "\n${GREEN}Starting database backup...${NC}\n"
time (/home/ubuntu/mysqldump-8.0.35/mysql-8.0.35-linux-glibc2.28-x86_64/bin/mysqldump -h"$db_host" -u"$username" -p"$password" "$db_name" --triggers --routines --events --opt --single-transaction --set-gtid-purged=OFF | pv -cN mysqldump >"$backup_path")

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}Backup completed successfully!${NC}\n"
else
    echo -e "\n${RED}Backup failed!${NC}"
    exit 1
fi

# Change permissions
chmod 777 "$backup_path"
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}Permissions updated successfully!${NC}\n"
else
    echo -e "\n${RED}Failed to update permissions!${NC}"
    exit 1
fi

# Remove definer
cd /home/ubuntu/Backup
echo -e "${GREEN}Removing Definer ...."
sed 's/\sDEFINER=`[^`]*`@`[^`]*`//g' -i "$backup_file"
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}Definer removed successfully!${NC}\n"
else
    echo -e "\n${RED}Failed to remove definer!${NC}\n"
    exit 1
fi

# Create 7z archive

backup_file="${ticket_num}${db_name}${curr_date}.sql"
z_file="${ticket_num}${db_name}${curr_date}.7z"

echo -e "\nCreating 7z archive..."
cd /home/ubuntu/Backup
7z a "$z_file" "$backup_file"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}7z archive created successfully!${NC}\n"
else
    echo -e "${RED}Failed to create 7z archive!${NC}\n"
    exit 1
fi

chmod 644 "/home/ubuntu/Backup/$z_file"


# Upload to S3
echo -e "Uploading to S3...\n"
aws s3 cp "/home/ubuntu/Backup/$z_file" "s3://readywire-rds-backup/" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}File uploaded to S3 successfully!${NC}\n"
else
    echo -e "${RED}Failed to upload file to S3!${NC}"
    exit 1
fi


#Generating Pre-signed URL

echo -e "${YELLOW}Creating Pre-signed URL...${NC}\n"
presigned_url=$(aws s3 presign "s3://readywire-rds-backup/$z_file" --expires-in 604800)
if [ $? -eq 0 ]; then
   echo -e "Presigned URL (valid for 7 days):\n${GREEN}$presigned_url${NC}\n"
else
   echo -e "${RED}Failed to generate presigned URL!${NC}"
   exit 1
fi


echo -e "\n \n${GREEN}All operations completed successfully!${NC}"
