#!/bin/bash
# mysql-transfer.sh
# Copyright (C) 2018 Webelop Ltd
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# USAGE:
#  mysql-transfer PATH FORCE
#  - Argument 1 - PATH:  configuration path. eg: ./sample-transfer
#  - Argument 2 - FORCE: optional "force" - bypass configuration questions and run all data migrations
#
# CONFIG FOLDER STRUCTURE:
#  - ./structure-data-tables.dist.txt > one table per line, containing all default tables to dump with data
#  - ./structure-only-tables.dist.txt > one table per line, containing all default tables to dump without data
#  - ./configuration.dist.sh > configuration file, contains clauses for dumping subsets of tables (eg: most recent data)
#  - ./data-updates.dist.sql > SQL queries to run after transfer
#
# NOTES:
#  - The config folder basename must be unique for each transfer, as it is used as a mysql "login path"
#  - All files can exist in 2 versions: *.dist.* files  and *.user.* files
#    *.user.* files have precedence and are ignored in git
#    *.dist.* files can be created from *.user.* files to share a transfer profile across a team
#  - mysqldump and mysql_config_editor MUST BE in the path
# ################################################################################################################ #

echo "mysql-transfer Copyright (C) 2018 Webelop Ltd."
echo "This program comes with ABSOLUTELY NO WARRANTY; This is free software,"
echo "and you are welcome to redistribute it under certain conditions;"
echo "Read LICENSE file for details"

CONFIG_DIR="$1"
INSTANCE=$(basename "$PROJECT_INSTANCE" | sed "s/[^a-zA-Z0-9]/_/")
if [ "$CONFIG_DIR" == "" ] || [ ! -d "$CONFIG_DIR" ]; then
    echo "Usage:"
    echo " - Argument 1: configuration path prefix. eg: ~/transfers/from-test"
    echo " - Argument 2: optional 'force' - bypass configuration questions and run all data migrations"
    exit;
fi

FORCE="$2"
MYSQLDUMP_OPTIONS="--quick --single-transaction --add-drop-table --skip-add-locks --skip-comments --skip-disable-keys --set-gtid-purged=OFF"
LIMITEDDATA_TABLES=()

# DEFAULT CONFIGURATION: Pull database to local
SRC_DB_PORT="3306"
DEST_DB_PORT="3306"
DEST_DB_USER="root"
DEST_HOST="localhost"

#READ CONFIG
STRUCTURE_DATA_TABLES=$(cat "$CONFIG_DIR/structure-data-tables.dist.txt" | grep "^[a-z0-9]")
STRUCTURE_ONLY_TABLES=$(cat "$CONFIG_DIR/structure-only-tables.dist.txt" | grep "^[a-z0-9]")

CONFIG_PATH="$CONFIG_DIR/configuration.dist.sh"
if [ -f "$CONFIG_PATH" ]; then
    . "$CONFIG_PATH"
else
    echo "Config file does not exist at $CONFIG_PATH"
fi

CONFIG_PATH="$CONFIG_DIR/import-config.user.sh"
if [ -f "$CONFIG_PATH" ]; then
    . "$CONFIG_PATH"
fi

function ask_config_question () {
    local VARNAME=$1
    local VARFILE=$2
    local VARDESCR=$3
    local CURRENTVALUE="${!VARNAME}"

    if [ ! -f "$VARFILE" ]; then
        if [ "$FORCE" == "1" ]; then
            echo "Missing $VARFILE!"
            exit
        fi
    else
        CURRENTVALUE=$(cat $VARFILE)
    fi

    # Check saved value
    if [ "$CURRENTVALUE" != "" ] && [ "$FORCE" == "0" ]; then
        echo "> Use $VARDESCR [$CURRENTVALUE]? (Y/n)";
        read USETHIS
        if [ "$USETHIS" == "n" ]; then
            CURRENTVALUE="";
        fi
    fi

    # Request user value
    if [ "$CURRENTVALUE" == "" ]; then
        echo "> What is the $VARDESCR?"
        read CURRENTVALUE;

        if [ "$CURRENTVALUE" != "" ]; then
            echo "$CURRENTVALUE" > $VARFILE
        fi
    fi

    # Exit if empty value provided
    if [ "$CURRENTVALUE" == "" ]; then
        echo "Missing dump host! Exiting..."
        exit;
    fi

    # Assign value
    eval "$VARNAME='$CURRENTVALUE'"
}

echo ">>>>>>> SOURCE CONFIGURATION >>>>>>>>"
ask_config_question "MYSQLDUMP_HOST" "mysqldump-host.user.txt" "mysqldump server (eg: localhost or username@ip_or_domain for ssh)"
ask_config_question "SRC_DB_NAME" "source-db-name.user.txt" "database name to import data from"

if [ "$MYSQLDUMP_HOST" != "" ] && [ "$MYSQLDUMP_HOST" != "localhost" ]; then
    SRC_LOGINPATH="${LOGINPATH}_ssh_dump_src"
else
    MYSQLDUMP_HOST=""
    SRC_LOGINPATH="${LOGINPATH}_dump_src"
    MYSQLDUMP_OPTIONS="$MYSQLDUMP_OPTIONS --compress"
fi
SRC_LOGIN_OPTION="--login-path=${SRC_LOGINPATH}"

#Helper function to execute a command locally or over ssh
function exec_on_src {
    if [ "$MYSQLDUMP_HOST" != "" ]; then
        ssh $MYSQLDUMP_HOST "$@"
    else
        eval "$@"
    fi
}

DUMPSRC="0"
exec_on_src "mysql $SRC_LOGIN_OPTION -ss $SRC_DB_NAME -e 'select 123'" | grep 123 > /dev/null && DUMPSRC="1"
if [ "$DUMPSRC" == "1" ]; then
    DUMPSRC="0"
    login=$(exec_on_src "mysql_config_editor print $SRC_LOGIN_OPTION")
    echo $login | grep "${SRC_LOGINPATH}" > /dev/null && DUMPSRC="1"
    if [ "$DUMPSRC" == "1" ] && [ "$FORCE" == "0" ]; then
        echo $login
        echo "> Import data FROM $SRC_LOGINPATH? (Y/n)"
        read USETHIS
        [ "$USETHIS" == "n" ] && DUMPSRC=0
    fi
fi
if [ "$DUMPSRC" == "0" ]; then
    if [ "$FORCE" == "1" ]; then
        echo "Ouch! Source database is undefined!"
        exit;
    fi

    echo "> What is the source database host? [$SRC_DB_HOST]"
    read NEWSRC_DB_HOST
    if [ "$NEWSRC_DB_HOST" != "" ]; then
        SRC_DB_HOST="$NEWSRC_DB_HOST"
    fi
    echo "> What is the source database port? [$SRC_DB_PORT]"
    read NEWSRC_DB_PORT
    if [ "$NEWSRC_DB_PORT" != "" ]; then
        SRC_DB_PORT="$NEWSRC_DB_PORT"
    fi
    echo "> What is the source database? [$SRC_DB_NAME]"
    read SRC_DB_NAME
    if [ "$SRC_DB_NAME" != "" ]; then
        SRC_DB_NAME="$SRC_DB_NAME"
    fi
    echo "> Who is the source database user? [$SRC_DB_USER]"
    read NEWSRC_DB_USER
    if [ "$NEWSRC_DB_USER" != "" ]; then
        SRC_DB_USER="$NEWSRC_DB_USER"
    fi

    SQLCMD="mysql_config_editor set $SRC_LOGIN_OPTION --host='$SRC_DB_HOST' --user='$SRC_DB_USER' --password --port='$SRC_DB_PORT'"
    echo $SQLCMD
    if [ "$MYSQLDUMP_HOST" != "" ] && [ "$MYSQLDUMP_HOST" != "localhost" ]; then
        ssh $MYSQLDUMP_HOST -t "$SQLCMD; exit"
    else
        $SQLCMD
    fi
fi

echo ">>>>>>> DESTINATION CONFIGURATION >>>>>>>>"
ask_config_question "DEST_DB_NAME" "dest-db-name.user.txt" "database name to import data to"
DEST_LOGINPATH="--login-path=${LOGINPATH}_dump_dst"
DUMPDEST="0"
mysql $DEST_LOGINPATH $DEST_DB_NAME -e 'select 123' | grep 123 > /dev/null 2>&1 && DUMPDEST=1
mysql_config_editor print $DEST_LOGINPATH
if [ "$DUMPDEST" == "1" ] && [ "$FORCE" == "0" ]; then
    echo "> Import data TO this database? (Y/n)"
    read USETHIS
    [ "$USETHIS" == "n" ] && DUMPDEST=0
fi
if [ "$DUMPDEST" == "0" ]; then
    if [ "$FORCE" == "1" ]; then
        echo "Ouch! Destination database is unconfigured!"
        exit;
    fi

    echo "> What is the destination database host? [$DEST_HOST]"
    read NEWDEST_HOST
    if [ "$NEWDEST_HOST" != "" ]; then
        DEST_HOST="$NEWDEST_HOST"
    fi
    echo "> What is the destination database port? [$DEST_DB_PORT]"
    read NEWDEST_DB_PORT
    if [ "$NEWDEST_DB_PORT" != "" ]; then
        DEST_DB_PORT="$NEWDEST_DB_PORT"
    fi
    echo "> Which is the destination database? [$DEST_DB_NAME]"
    read DEST_DB_NAME
    if [ "$DEST_DB_NAME" != "" ]; then
        DEST_DB_NAME="$DEST_DB_NAME"
    fi
    echo "> Who is the destination database user? [$DEST_DB_USER]"
    read NEWDEST_DB_USER
    if [ "$NEWDEST_DB_USER" != "" ]; then
        DEST_DB_USER="$NEWDEST_DB_USER"
    fi
    mysql_config_editor set $DEST_LOGINPATH --host="$DEST_HOST" --user="$DEST_DB_USER" --port="$DEST_DB_PORT" --password
    mysql_config_editor print $DEST_LOGINPATH
fi

DUMPED="0";
echo ">>>>>>> STRUCTURE ONLY >>>>>>>>"
if [ "$STRUCTURE_ONLY_TABLES" != "" ] && [ "$FORCE" == "0" ]; then
    echo "$STRUCTURE_ONLY_TABLES"
    echo "> Dump structure only for these tables? (y/N)"
    read YES
    if [ "$YES" != "y" ]; then
        STRUCTURE_ONLY_TABLES=""
    fi
fi

if [ "$STRUCTURE_ONLY_TABLES" == "" ] && [ "$FORCE" == "0" ]; then
    echo "> Dump structure only for custom table list? (empty to skip)"
    read STRUCTURE_ONLY_TABLES
fi
if [ "$STRUCTURE_ONLY_TABLES" != "" ] && [ "$FORCE" == "0" ]; then
    for table in $(echo "$STRUCTURE_ONLY_TABLES" | sed 's/\W\+/&\n/g'| grep -oiE '[a-z0-9_]+')
    do
        echo "< $(date '+%H:%M:%S') - Dumping structure of $table"
        exec_on_src "mysqldump $SRC_LOGIN_OPTION $MYSQLDUMP_OPTIONS --no-data $SRC_DB_NAME $table" | mysql $DEST_LOGINPATH $DEST_DB_NAME
    done
fi

echo ">>>>>>> STRUCTURE AND DATA >>>>>>>>"
if [ "$STRUCTURE_DATA_TABLES" != "" ] && [ "$FORCE" == "0" ]; then
    echo "$STRUCTURE_DATA_TABLES"
    echo "> Dump structure and data for these tables? (y/N)"
    read YES
    if [ "$YES" != "y" ]; then
        TABLES=""
    fi
fi

if [ "$STRUCTURE_DATA_TABLES" == "" ] && [ "$FORCE" == "0" ]; then
    echo "> Dump structure and data for custom table list? (empty to skip)"
    read TABLES
fi

if [ "$STRUCTURE_DATA_TABLES" != "" ]; then
    for table in $(echo "$STRUCTURE_DATA_TABLES" | sed 's/\W\+/&\n/g'| grep -oiE '[a-z0-9_]+')
    do
        echo "< $(date '+%H:%M:%S') - Dumping $table"
        SQLCMD="nice mysqldump $SRC_LOGIN_OPTION $MYSQLDUMP_OPTIONS $SRC_DB_NAME $table"
        if [ "$MYSQLDUMP_HOST" != "" ] && [ "$MYSQLDUMP_HOST" != "localhost" ]; then
            ssh $MYSQLDUMP_HOST "$SQLCMD | gzip" | gunzip | mysql $DEST_LOGINPATH $DEST_DB_NAME
        else
            $SQLCMD | mysql $DEST_LOGINPATH $DEST_DB_NAME
        fi
    done
fi

echo ">>>>>>> STRUCTURE AND RECENT DATA >>>>>>>>"
LIMITEDDATA_SQLCMD=()

# see ./configuration.dist.sh for exemples
for clause in "${LIMITEDDATA_TABLES[@]}"
do
    PLACEHOLDER=$(echo "$clause" | grep -oE '\{\{[^}]+\}\}' | sed 's#[{}]##g')
    if [ "$PLACEHOLDER" != "" ]; then
        VALUE=""
        if [ "${!PLACEHOLDER}" == "" ]
        then
            SQLVAR="${PLACEHOLDER}_QUERY"
            SQLSTMT=${!SQLVAR}
            if [ "$SQLSTMT" != "" ]
            then
                VALUE=$(exec_on_src "mysql $SRC_LOGIN_OPTION $SRC_DB_NAME -ss -e '$SQLSTMT'" | grep -oE '^[0-9]+$')
            fi
        else
            VALUE="${!PLACEHOLDER}"
        fi
        if [ "$VALUE" == "" ] && [ "$FORCE" == "0" ]
        then
            echo "< Value for $PLACEHOLDER in $clause? (Fill in numerical value, or 'n' to skip similar clauses)"
            read VALUE
        fi
        eval "$PLACEHOLDER='$VALUE'"
        NUMERICVALUE=0
        echo "$VALUE" | grep -oE '^[0-9]+$' > /dev/null && NUMERICVALUE=1
        if [ "$NUMERICVALUE" == "1" ]
        then
            echo "< $PLACEHOLDER = [$SQLSTMT]"
            clause=$(echo "$clause" | sed "s/{{$PLACEHOLDER}}/$VALUE/g")
        else
            echo "< $PLACEHOLDER is not numeric [$VALUE]... skipping!"
            continue;
        fi
    fi

    if [ "$FORCE" == "0" ]; then
        echo "> Dump recent data for $clause? (y/N)"
        read YES
        if [ "$YES" != 'y' ]; then
            continue;
        fi
    fi
    LIMITEDDATA_SQLCMD+=("$clause")
done

for clause in "${LIMITEDDATA_SQLCMD[@]}"; do
    echo "< $(date '+%H:%M:%S') - Dumping structure and data : $clause"
    SQLCMD="nice mysqldump $SRC_LOGIN_OPTION $MYSQLDUMP_OPTIONS $SRC_DB_NAME $clause"
    if [ "$MYSQLDUMP_HOST" != "" ] && [ "$MYSQLDUMP_HOST" != "localhost" ]; then
        ssh $MYSQLDUMP_HOST "$SQLCMD | bzip2" | bunzip2 | mysql $DEST_LOGINPATH $DEST_DB_NAME
    else
        eval "$SQLCMD" | mysql $DEST_LOGINPATH $DEST_DB_NAME
    fi
done

IMPORT_UPDATES_PATH="$CONFIG_DIR/import-updates.dist.sql"
if [ -f "$IMPORT_UPDATES_PATH" ]
then
    echo "< $(date '+%H:%M:%S') - Executing database updates at $IMPORT_UPDATES_PATH"
    mysql $DEST_LOGINPATH $DEST_DB_NAME < "$IMPORT_UPDATES_PATH" > /dev/null
else
    echo "< $(date '+%H:%M:%S') - Database update file does not exist at $IMPORT_UPDATES_PATH"
fi

IMPORT_UPDATES_PATH="$CONFIG_DIR/import-updates.user.sql"
if [ -f "$IMPORT_UPDATES_PATH" ]
then
    echo "< $(date '+%H:%M:%S') - Executing database updates at $IMPORT_UPDATES_PATH"
    mysql $DEST_LOGINPATH $DEST_DB_NAME < "$IMPORT_UPDATES_PATH" > /dev/null
fi
