#!/bin/bash
# Shell script to create a new Intershop Commerce Management project.

set -e

## Script variables
ARCHIVE_TYPES=(gz bz2 7z rar tar.gz tgz tar.bz2 tbz2 zip)
NEXUS="192.168.17.132:8081"
ICM_VERSION="7.7.2.5"
ICM_EDITION="b2x"
GRADLE_VERSION="2.7.1"
CI_BOOTSTRAP_VERSION="3.3.0"
STARTER_STORE_VERSION="2.2.5"
COMPONENT_SET="a_responsive"
ASSEMBLY_NAME="inspired-b2x"

SCRIPT_BASE="$(dirname $0)/.."

## Script usage explenation
## TODO: Update usage, this is copied as a template
usage() {
    ME=$(basename "$0")
    cat <<EOF
$ME
    distributes etc- and var-directory OMS to different file-systems.
    Information about target of etc-directory has to be passed at the command-
    line. Target of var-directory is read from installation.properties
    located at etc-directory.

SYNOPSIS
    $ME [--etc=<target for etc directory>] [-f|--force] [-h|--help]

DESCRIPTION
    --etc=<target for etc directory>
      

    -f|--force
      forefully remove content from the defined targets in \$OMS_ETC and 
      \$OMS_VAR.

    -h|--help
      Display this help and exit.
EOF
}

and_enter_message() {
	echo " and press [ENTER]: "
}

interactive() {
	echo "Please enter Nexus IP or DNS"; and_enter_message
	read NEXUS
	echo "Please enter ICM version number"; and_enter_message
	read ICM_VERSION
	echo "Which ICM edition do you want to deploy, b2c or b2x? [enter]"
	read ICM_VERSION
	echo "Please enter Gradle version number"; and_enter_message
	read GRADLE_VERSION
	echo "Please enter CI Bootstrap version number"; and_enter_message
	read CI_BOOTSTRAP_VERSION
	echo "Please enter Responsive Starter Store version number"; and_enter_message
	read STARTER_STORE_VERSION
	echo "Please enter Assembly name"; and_enter_message
	read ASSEMBLY_NAME
}

for OPT in "$@"; do
    case $OPT in
        --icm-version=*)
            ICM_VERSION="${OPT#*=}"
            shift
            ;;
        --icm-edition=*)
            ICM_EDITION="${OPT#*=}"
            shift
            ;;
        --gradle-version=*)
            GRADLE_VERSION="${OPT#*=}"
            shift
            ;;
        --ci-bootstrap-version=*)
            CI_BOOTSTRAP_VERSION="${OPT#*=}"
            shift
            ;;
        --starter-store-version=*)
            STARTER_STORE_VERSION="${OPT#*=}"
            shift
            ;;
        -i|--interactive)
        	INTERACTIVE=TRUE
			interactive
			shift
            ;;
        -f|--force)
            FORCE="TRUE"
            shift
            ;;
        -h|--help)
        	usage
            exit
            ;;
        *)
        	echo "invalid option $OPT" 
			echo 1>&2
			usage 1>&2
			exit 1
            ;;
    esac
done

exists() {
  command -v "$1" >/dev/null 2>&1
}

application_message() {
	if [ -z "$1" ]; then
		echo "File extension can't be resolved"
	elif [ -n "$1" | "$2" = "FAILED" ]; then
		echo "No program is available to execute '$1' files"
	else
		echo "Application is unkown. Please install application for '$1'"
	fi
	1>&2 
	exit 1
}

# resolve_value() {
# 	if [ "$3" ]; then
# 		return $3
# 	elif [ "$2" ]; then
# 		return $2
# 	else
# 		return $1
# 	fi
# }

download_file() {
	local CACHE_DIR="$SCRIPT_BASE/cache/$3"
	local CACHED_FILE="$CACHE_DIR/$2"
	if [ -e "$CACHED_FILE" ]; then
		echo "Copying $3"
		cp $CACHED_FILE $(pwd -P)
	else
		echo "Downloading $3"
		if exists wget; then
			wget $1/$2
		elif exists curl; then
			curl -O $1/$2
		else
			application_message $2 FAILED
		fi
		FILE_DOWNLOADED="TRUE"
	fi
	if [ "$FILE_DOWNLOADED" = "TRUE" ]; then
		if [ -e "$CACHE_DIR" ]; then
			echo "Adding $3 archive to cache directory"
			cp $2 $CACHE_DIR
		elif [ ! -w "$CACHE_DIR" ]; then
			echo "ERROR: Cache directory $CACHE_DIR is not writable!" 1>&2
		else
			echo "ERROR: Can't copy file to cache directory!" 1>&2
		fi
	fi
}

unpack_file() {
	case $1 in
        *.gz)
            # gzip
			if exists gunzip; then
				gunzip -k $1
			elif exists gzip; then
				gzip -dk $1
			else
				application_message $1 FAILED
			fi
            ;;
        *.bz2)
            # bzip2
            if exists gunzip; then
				bzip2 -dk $1
			else
				application_message $1 FAILED
			fi
            ;;
        *.7z)
            # 7z
            echo "TODO: Unpack 7z files"
            shift
            ;;
        *.rar)
            # RAR
            echo "TODO: Unpack 7z files"
            shift
            ;;
        *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2)
            # Tar with gzip or bzip2
            if exists tar; then
				if [ $1 = "*.tar"]; then
					tar -xvf $1
				else
					tar -xzvf $1
				fi
			else
				application_message $1 FAILED
			fi
            ;;
        *.zip)
            # ZIP
            if exists gunzip; then
				unzip $1
			else
				application_message $1 FAILED
			fi
            ;;
        *)  application_message $1
            exit 1
            ;;
    esac
    rm -Rf $1
}

add_gradle_wrapper() {
	cp -R $SCRIPT_BASE/templates/gradle $1
	sed -i -e "s/<NEXUS>/$NEXUS/" $1/gradle/wrapper/gradle-wrapper.properties
}

setup_componentset() {
	local DOWNLOAD_PATH="http://$1/nexus/content/repositories/ishrepo/com.intershop.public.source/a_responsive/$2/zips/"
	local DOWNLOAD_FILE="a_responsive-zip-src-$2.zip"

	if [ "$FORCE" = "TRUE" ]; then
		echo "Removing existing component set because of FORCE mode"
		rm -Rf $COMPONENT_SET
	fi

	if [ ! -e "$COMPONENT_SET" ]; then
		download_file $DOWNLOAD_PATH $DOWNLOAD_FILE componentset
		unpack_file $DOWNLOAD_FILE
		add_gradle_wrapper $COMPONENT_SET
	else
		{
			echo "ERROR: The component set already exists"
			echo
			echo 'Use "-f" to override! All changes will be removed!'
        } 1>&2
        exit 1
	fi
}

setup_assembly() {
	local DOWNLOAD_PATH="http://$1/nexus/content/repositories/ishrepo/com.intershop.public.source/inspired-$3/$2/zips"
	local DOWNLOAD_FILE="inspired-$3-zip-src-$2.zip"
	
	if [ "$FORCE" = "TRUE" ]; then
		echo "Removing existing assembly set because of FORCE mode"
		rm -Rf $ASSEMBLY_NAME
	fi
	
	if [ ! -e "$ASSEMBLY_NAME" ]; then
		download_file $DOWNLOAD_PATH $DOWNLOAD_FILE assembly
		unpack_file $DOWNLOAD_FILE
		add_gradle_wrapper $ASSEMBLY_NAME
		cp -R $SCRIPT_BASE/templates/environment.properties $ASSEMBLY_NAME
		cp -R $SCRIPT_BASE/templates/development.properties $ASSEMBLY_NAME
		
		# Change 'build.gradle'
		sed -i -e "s#nexus/nexus#$NEXUS/nexus#" $ASSEMBLY_NAME/build.gradle
	else
		{
			echo "ERROR: The assembly already exists"
			echo
			echo 'Use "-f" to override! All files will be removed and/or overwritten!'
        } 1>&2
        exit 1
	fi
}

add_developer_home() {
	cp -R $SCRIPT_BASE/templates/developer_home .
}

create_vagrantfile() {
	cp -R $SCRIPT_BASE/templates/Vagrantfile .
	sed -i -e "s/<COMPONENT_SET>/$COMPONENT_SET/g;s/<ASSEMBLY_NAME>/$ASSEMBLY_NAME/g" Vagrantfile
}

add_installation_scripts() {
	cp -R $SCRIPT_BASE/install .
	cp -R $SCRIPT_BASE/files .
}


setup_componentset $NEXUS $STARTER_STORE_VERSION
setup_assembly $NEXUS $STARTER_STORE_VERSION $ICM_EDITION
add_developer_home
create_vagrantfile
add_installation_scripts



echo
echo "Done."
echo
