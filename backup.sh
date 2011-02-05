#!/bin/bash - 

#set -x
set -o nounset                              # Treat unset variables as an error

############ APPLICATIONS ##############
: ${BACKUPUTIL:=/usr/bin/rsnapshot}
: ${DF:=/bin/df}
: ${DPKG:=/usr/bin/dpkg}
: ${GAWK:=/usr/bin/gawk}
: ${GREP:=/bin/grep}
: ${SUDO:=/usr/bin/sudo}
: ${UDISKS:=/usr/bin/udisks}
: ${LS:=/bin/ls}
: ${LN:=/bin/ln}
: ${SYNC:=/bin/sync}
: ${RSYNC:=/usr/bin/rsync}
: ${LOGGER:=/usr/bin/logger}
: ${RM:=/bin/rm}
: ${TOUCH:=/usr/bin/touch}

############## INIT ###############

ME=${0##*/}
MY_LOCATION="${0%/*}"
MY_LIB="$HOME/lib"

source "$MY_LIB/shflags"

PID_FILE="$HOME/var/run/$ME"

############## HELPER-FUNCTIONS ###############

function debug { 
        echo "DEBUG: $@" >&2
        set -x 
}

############## FUNCTIONS ###############


#print info message and go on
function log_info {
  local MESSAGE="$1"
  local TAG=backup
  local PRIORITY="local1.info"

  echo "INFO: $MESSAGE" >&2
  "$LOGGER" -t "$TAG" -p "$PRIORITY" "$MESSAGE"
}

#print error message and exit
function log_error {
  local MESSAGE="$1"
  local TAG=backup
  local PRIORITY="local1.error"

  echo "ERROR: $MESSAGE" >&2
  "$LOGGER" -t "$TAG" -p "$PRIORITY" "$MESSAGE"
  exit 1
}

#print warning and go on
function log_warning {
  local MESSAGE="$1"
  local TAG=backup
  local PRIORITY="local1.warn"

  echo "WARNING: $MESSAGE" >&2
  "$LOGGER" -t "$TAG" -p "$PRIORITY" "$MESSAGE"

}

function check_storage {
local CHCKDIR=backup
local HDD_ID="$1"
local CRIT="$2"
local HDD_PATH="/media/$HDD_ID"

if [ -d "$HDD_PATH/$CHCKDIR" ]; then
	log_info "HDD '$HDD_ID' with dir '$CHCKDIR' exists"
else
    if [ "$CRIT" == "NOT_CRITICAL" ]; then
	    log_warning "HDD '$HDD_ID' with dir '$CHCKDIR' does not exist"
        return 128
    else
	    log_error "HDD '$HDD_ID' with dir '$CHCKDIR' does not exist"
    fi
fi

}


function get_installed_packages {
local RESULT=/var/apt/packages/installed_packages.log
log_info "Getting package information"
($SUDO $DPKG -l | $GREP -E "^ii" | $GAWK '{ print $2 }') > "$RESULT"
}


function backup {
local BACKUP_CONF="$1"
local DST_DIR="$2"
local CHCKDIR=backup

if [ -d  "$DST_DIR/$CHCKDIR" ]; then
  log_info "$DST_DIR exists. Starting backup with configfile '$BACKUP_CONF'."
  log_info "Disk utilization: $($DF -h | $GREP $DST_DIR)"
  "$SUDO" "$BACKUPUTIL" -c "$BACKUP_CONF" hourly

else
  log_error "$DST_DIR does NOT exist. Stopping backup."
fi
}


function mount_dir {
local HDD_ID="$1"
local HDD_DEVICE="/dev/disk/by-uuid/$HDD_ID"
local HDD_PATH="/media/$HDD_ID"

log_info "Mounting $HDD_PATH"
"$UDISKS" --mount "$HDD_DEVICE"; RESULT="$?"

if [ "$RESULT" == 0 ]; then
    log_info "Mounting $HDD_PATH successfull!"
else
    log_error "Mounting $HDD_PATH failed!"
fi

log_info "Please see files below HDD_PATH $HDD_PATH"
"$LS" -al "$HDD_PATH/" 2>/dev/null
}

function umount_dir {
local HDD_ID="$1"
local HDD_DEVICE="/dev/disk/by-uuid/$HDD_ID"
local HDD_PATH="/media/$HDD_ID"

log_info "Dismounting $HDD_PATH"
"$UDISKS" --unmount "$HDD_DEVICE"; RESULT="$?"

if [ "$RESULT" == 0 ]; then
    log_info "Dismounting $HDD_PATH successfull!"
else
    log_error "Dismounting $HDD_PATH failed!"
fi

"$LS" "$HDD_PATH/" 2>/dev/null
}

function set_backup_dir {

local ACTIVE_HDD_ID="$1"
local BACKUPDIR="$2"
local MOUNTPOINT=/media

"$LN" -snf "$MOUNTPOINT/$ACTIVE_HDD_ID" "$BACKUPDIR"

if [ -L  "$BACKUPDIR" ]; then
	log_info "$BACKUPDIR exists, but is a symlink. Going on."
else
	log_error "$BACKUPDIR does not exist or isn't a symlink. Exiting"
fi


}

function check_backup_dir {
local BACKUPDIR="$2"
local CHCKDIR=backup

if [ -d "$BACKUPDIR/$CHCKDIR" ]; then
	log_info "Directory '$BACKUPDIR' with dir '$CHCKDIR' exists"
else
	log_error "Directory'$BACKUPDIR' with dir '$CHCKDIR' does not exist"
fi

}

function sync_hdds {
    local TAG=backup
    local PRIORITY="local1.info"

    local HDD1_ID_LOCAL="$1"
    local HDD1_PATH_LOCAL="/media/$HDD1_ID_LOCAL"
    
    local HDD2_ID_LOCAL="$2"
    local HDD2_PATH_LOCAL="/media/$HDD2_ID_LOCAL"
    
    local RSYNC_LOG="$HOME/var/log/backup-hdd-sync.log"
    
    log_info "Starting sync ($HDD1_PATH_LOCAL => $HDD2_PATH_LOCAL)"

    "$TOUCH" "$RSYNC_LOG"

    "$SUDO" "$RSYNC" -H --quiet -a --delete --log-file="$RSYNC_LOG" "$HDD1_PATH_LOCAL/" "$HDD2_PATH_LOCAL/"; RC="$?"
    if [  "$RC" -ne 0 ];then
        log_warning "Errors, while running rsync. Please see $RSYNC_LOG for further details."
    #    $LOGGER -f $RSYNC_LOG -t $TAG -p $PRIORITY
        "$RM" "$RSYNC_LOG"
    else
        log_info "Sync ends successfull."
    fi
    
}

function get_hdd_usage {
    local HDD_ID="$1"
    local HDD_PATH="/media/$HDD_ID"

    log_info "On $HDD_PATH $($DF -h | $GREP $HDD_PATH | $GAWK '{ print "available: "$1", used: "$2", free: "$3 }')"
}


############ MAIN ##############

#### GLOBAL VARIABLES ####
HDD1_ID="3854824f-f3ea-4cc4-bd05-89d09dd305d1"
HDD2_ID="7256af06-3443-4cef-a55e-ec9d9a4d5195"
EXT_STORAGE_ID_1="9b4a6f28-033a-4d88-981e-e204a135d42e"

#### COMMANDLINE PARSING ####

# define a 'name' command-line string flag
DEFINE_boolean 'debug' false 'enable debug mode' 'd'
DEFINE_boolean 'help' false 'this help message' 'h'
DEFINE_boolean 'backup_external_only' false 'backup to external device only' 'e'
DEFINE_boolean 'hdd_backup_only' false 'backup to hdds only' 'b'
DEFINE_boolean 'full_backup' false 'backup to hdds and external device' 'f'

# parse the command-line
FLAGS "$@" || exit 1
eval set -- "${FLAGS_ARGV}"

#print message when in debug mode
if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ] ; then
    debug 'debug mode enabled'
fi

#### ACTIONS ####
function hdd_backup {

local HDD1_ID="$1"
local HDD2_ID="$2"
local BACKUP_DST_DIR="$3"

mount_dir "$HDD1_ID"
mount_dir "$HDD2_ID"

#first check if both hdds are available
#to start backup
check_storage "$HDD1_ID" "CRITICAL"
check_storage "$HDD2_ID" "CRITICAL"

set_backup_dir "$HDD2_ID" "$BACKUP_DST_DIR" 
check_backup_dir "$HDD2_ID" "$BACKUP_DST_DIR" 

get_installed_packages

#primary backup
BACKUP_CONF="$HOME/.config/rsnapshot/rsnapshot.conf"
backup "$BACKUP_CONF" "$BACKUP_DST_DIR"
BACKUP_CONF="/etc/rsnapshot.conf"
backup "$BACKUP_CONF" "$BACKUP_DST_DIR"

#double check if hdds are available
#to sync hdds
check_storage "$HDD1_ID" "CRITICAL"
check_storage "$HDD2_ID" "CRITICAL"

sync_hdds "$HDD2_ID" "$HDD1_ID"

get_hdd_usage "$HDD1_ID"
get_hdd_usage "$HDD2_ID"

#problems when using with external usb-storage
#$SYNC 

umount_dir "$HDD1_ID"
umount_dir "$HDD2_ID"
}

function ext_backup {
#secondary backup on external storage
check_storage "$EXT_STORAGE_ID_1" "NOT_CRITICAL"; RC="$?"

if [ "$RC" -eq 0 ]; then
    BACKUP_CONF="$HOME/.config/rsnapshot/rsnapshot_ext.conf"
    backup "$BACKUP_CONF" "$BACKUP_DST_DIR"
fi
}

if [ ${FLAGS_backup_external_only} -eq ${FLAGS_TRUE} ] ; then
    log_info "Starte Backup auf externen USB-Datenträger"
    BACKUP_DST_DIR="$HOME/mnt/backup_ext"
    ext_backup "$HDD1_ID" "$HDD2_ID" "$BACKUP_DST_DIR"
else
    if [ ${FLAGS_hdd_backup_only} -eq ${FLAGS_TRUE} ]; then
        log_info "Starte Backup auf externen HDD-Datenträger"
        BACKUP_DST_DIR="$HOME/mnt/backup"
        hdd_backup "$HDD1_ID" "$HDD2_ID" "$BACKUP_DST_DIR"
    else
        if [ ${FLAGS_full_backup} -eq ${FLAGS_TRUE} ]; then
            BACKUP_DST_DIR="$HOME/mnt/backup"
            hdd_backup "$HDD1_ID" "$HDD2_ID" "$BACKUP_DST_DIR"
            BACKUP_DST_DIR="$HOME/mnt/backup_ext"
            ext_backup "$HDD1_ID" "$HDD2_ID" "$BACKUP_DST_DIR"
        else
            #show help
            $0 -h
        fi
    fi
fi

