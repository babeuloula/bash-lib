#!/usr/bin/env bash

# PROMPT COLOURS
readonly RESET='\033[0;0m'
readonly BLACK='\033[0;30m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[0;37m'

readonly DOCKER_MINIMAL_VERSION=18.04.0
readonly DOCKER_COMPOSE_MINIMAL_VERSION=1.24.0

function check_requirements() {
    check_docker
    check_docker_compose
}

function check_version() {
    local version=$1
    local require_version=$2
    local package=$3

    dpkg --compare-versions ${version} 'ge' ${require_version} \
        || (echo -e "${RED}Requirement: need '${package}:${require_version}', you have '${package}:${version}'.${RESET}" > /dev/tty && exit 1)
}

function check_docker() {
    if [[ -z $(which docker) ]]; then
        echo -e "${RED}Requirement: need 'docker:${DOCKER_MINIMAL_VERSION}' see https://docs.docker.com/install/linux/docker-ce/ubuntu.${RESET}" > /dev/tty
        exit 1
    fi

    check_version $(docker -v | sed -r 's/.* version ([^,]+),.*/\1/') ${DOCKER_MINIMAL_VERSION} 'docker'
}

function check_docker_compose() {
    if [[ -z $(which docker-compose) ]]; then
        echo -e "${RED}Requirement: need 'docker-compose:${DOCKER_COMPOSE_MINIMAL_VERSION}' see https://docs.docker.com/compose/install.${RESET}" > /dev/tty
        exit 1
    fi

    check_version $(docker-compose -v | sed -r 's/.* version ([^,]+),.*/\1/') ${DOCKER_COMPOSE_MINIMAL_VERSION} 'docker-compose'
}

function ask_value() {
    local message=$1
    local default_value=$2
    local value
    local default_value_message=''

    if [[ ! -z "${default_value}" ]]; then
        default_value_message=" (default: ${YELLOW}${default_value}${CYAN})"
    fi

    echo -e "${CYAN}${message}${default_value_message}: ${RESET}" > /dev/tty
    read value < /dev/tty

    if [[ -z "${value}" ]]; then
        value=${default_value}
    fi

    echo "${value}"
}

function add_host() {
    local host=$1

    if [[ $(grep -c ${host} /etc/hosts) -eq 0 ]]; then
        sudo /bin/sh -c "echo \"127.0.0.1 ${host}\" >> /etc/hosts"
    fi
}

function configure_env() {
    local key=$1
    local value=$2
    local env_to=$3

    if [[ ! -z "${env_to}" ]] && [[ -f "${env_to}" ]]; then
        sed -e "/^${key}=/d" -i "${env_to}"
    fi

    echo "${key}=${value}" >> ${env_to}
}

function get_env_value() {
    local key=$1
    local default_value=$2
    local env_to=$3

    case ${key} in
        DOCKER_UID)
            value=$(id -u)
        ;;
        *)
            if [[ ! -f ${env_to} ]] || [[ "$(cat ${env_to} | grep -Ec "^${key}=(.*)$")" -eq 0 ]]; then
                value=$(ask_value "Define the value of ${YELLOW}${key}${CYAN}" ${default_value})
            else
                value=$(cat ${env_to} | grep -E "^${key}=(.*)$" | awk -F "${key} *= *" '{print $2}')
            fi
        ;;
    esac

    if [[ -z ${value} ]]; then
        value=${default_value}
    fi

    echo ${value}
}

function parse_env() {
    local env_from=$1
    local env_to=$2

    if [[ -f "${env_from}" ]]; then
        for line in $(cat ${env_from})
        do
            key=$(echo ${line} | awk -F "=" '{print $1}')
            defaultValue=$(echo ${line} | awk -F "${key} *= *" '{print $2}')
            configure_env ${key} $(get_env_value "${key}" "${defaultValue}" "${env_to}") "${env_to}"
        done
    fi
}

function block() {
    local color=$1
    local text=$2
    local title_length=${#text}

    echo -en "\n\033[${color}m\033[1;37m    "
    for x in $(seq 1 ${title_length}); do echo -en " "; done;
    echo -en "\033[0m\n"

    echo -en "\033[${color}m\033[1;37m  ${text}  \033[0m\n"
    echo -en "\033[${color}m\033[1;37m    "
    for x in $(seq 1 ${title_length}); do echo -en " "; done;
    echo -en "\033[0m\n\n"
}

function block_error() {
    block "41" "${1}"
}

function block_success() {
    block "42" "${1}"
}

function block_warning() {
    block "43" "${1}"
}

function block_info() {
    block "44" "${1}"
}

function echo_error() {
    echo -e "${RED}${1} ${RESET}" > /dev/tty
}

function echo_success() {
    echo -e "${GREEN}${1} ${RESET}" > /dev/tty
}

function echo_warning() {
    echo -e "${YELLOW}${1} ${RESET}" > /dev/tty
}

function echo_info() {
    echo -e "${CYAN}${1} ${RESET}" > /dev/tty
}

function echo_replace() {
    echo  -e "$1 \r\c" > /dev/tty
}

function trap_exit() {
    if [[ $? -ne 0 ]]; then
        block_error "An error has occurred."
    fi
}

function aws_docker() {
    docker run --rm -t $(tty &>/dev/null && echo "-i") --user ${UID} -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" -e "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}" -v "$(pwd):/project" mesosphere/aws-cli ${1}
}

function wait_mysql() {
    echo -e "${BLUE}Wait for MySQL...${RESET}" > /dev/tty

    maxcounter=45
    counter=1
    while ! docker-compose exec mysql mysql --protocol TCP -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "show databases;" > /dev/null 2>&1; do
        sleep 1
        counter=`expr $counter + 1`
        if [ $counter -gt $maxcounter ]; then
            >&2 echo -e "${RED}We have been waiting for MySQL too long already; failing.${RESET}" > /dev/tty
            exit 1
        fi;
    done
}

check_is_sudo() {
    if [[ "${EUID}" -ne 0 ]]; then
        block_error "Please run as root."
        exit 1
    fi
}
