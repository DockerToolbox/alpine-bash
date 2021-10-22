#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Description                                                                      #
# -------------------------------------------------------------------------------- #
# This is the core controller script for generating, building and publishing the   #
# docker containers.                                                               #
# -------------------------------------------------------------------------------- #

# -------------------------------------------------------------------------------- #
# Enable strict mode                                                               #
# -------------------------------------------------------------------------------- #
# errexit = Any expression that exits with a non-zero exit code terminates         #
# execution of the script, and the exit code of the expression becomes the exit    #
# code of the script.                                                              #
#                                                                                  #
# pipefail = This setting prevents errors in a pipeline from being masked. If any  #
# command in a pipeline fails, that return code will be used as the return code of #
# the whole pipeline. By default, the pipeline's return code is that of the last   #
# command - even if it succeeds.                                                   #
#                                                                                  #
# noclobber = Prevents files from being overwritten when redirected (>|).          #
#                                                                                  #
# nounset = Any reference to any variable that hasn't previously defined, with the #
# exceptions of $* and $@ is an error, and causes the program to immediately exit. #
# -------------------------------------------------------------------------------- #

set -o errexit -o pipefail -o noclobber -o nounset
IFS=$'\n\t'

# -------------------------------------------------------------------------------- #
# Repo Root                                                                        #
# -------------------------------------------------------------------------------- #
# Work out where the root of the repo is as we need this for reference later.      #
# -------------------------------------------------------------------------------- #

REPO_ROOT=$(r=$(git rev-parse --git-dir) && r=$(cd "$r" && pwd)/ && cd "${r%%/.git/*}" && pwd)

# -------------------------------------------------------------------------------- #
# Required commands                                                                #
# -------------------------------------------------------------------------------- #
# These commands MUST exist in order for the script to correctly run.              #
# -------------------------------------------------------------------------------- #

PREREQ_COMMANDS=( "docker" )

# -------------------------------------------------------------------------------- #
# Global variables                                                                 #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

SINGLE_OS=true
SINGLE_OS_NAME='alpine'
NO_OS_NAME_IN_CONTAINER=true

GENERATE=false
BUILD=false
CLEAN=false
LATEST=false
PUBLISH=false
SCAN=false
GHCR=false

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function check_template()
{
    if [[ ! -f "${1}" ]]; then
        abort "${1} is missing aborting Dockerfile generation for ${CONTAINER_OS_NAME}:${CONTAINER_OS_VERSION_ALT}"
    fi
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

    # Escape things that will upset sed - ORDER IF IMPORTANT!!

function escape_string()
{
    local orig="${1:-}"
    local clean="${orig}"

    # Escape \
    # shellcheck disable=SC1003
    clean="${clean//'\'/'\\'}"

    # Escape "
    # shellcheck disable=SC1003
    clean="${clean//'"'/'\"'}"

    echo "${clean}"
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function load_labels
{
    # shellcheck disable=SC1091
    source "${REPO_ROOT}"/Config/labels.cfg
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function generate_container()
{
    local CONTAINER_SHELL="bash"

    info "Generating new Dockerfile for ${LOCAL_CONTAINER_NAME}"

    check_template "Templates/Dockerfile.tpl"

    if [[ "${SINGLE_OS}" != true ]]; then
        check_template "Templates/cleanup.tpl"
        # shellcheck disable=2034
        CLEANUP=$(<Templates/cleanup.tpl)
    fi

    DOCKERFILE=$(<Templates/Dockerfile.tpl)

    [[ "${CONTAINER_OS_NAME}" == "alpine" ]] && CONTAINER_SHELL="ash"

    PACKAGES=$("${REPO_ROOT}"/Scripts/get-versions.sh -g "${REPO_ROOT}"/Scripts/version-grabber.sh -p -c "${REPO_ROOT}/Config/packages.cfg" -o "${CONTAINER_OS_NAME}" -t "${CONTAINER_OS_VERSION_ALT}" -s "${CONTAINER_SHELL}")
    if [[ -f "Templates/static-packages.tpl" ]]; then
        STATIC=$(<Templates/static-packages.tpl)
        PACKAGES=$(printf "%s\n%s" "${PACKAGES}" "${STATIC}")
    fi

    DOCKERFILE=$(escape_string "${DOCKERFILE}")

    load_labels

    eval "echo -e \"${DOCKERFILE}\"" >| Dockerfile

    info "Complete"
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function build_container()
{
    cmd='docker build '

    if [[ "${CLEAN}" = true ]]; then
        message_prefix='Clean building'
        cmd+='--no-cache '
    else
        message_prefix="Building"
    fi
    cmd+="--pull -t ${LOCAL_CONTAINER_NAME} ."

    info "${message_prefix} for ${LOCAL_CONTAINER_NAME}"

    eval "${cmd}"

    info "Complete"
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function scan_container()
{
    info "Scanning: ${LOCAL_CONTAINER_NAME}"
    docker scan "${LOCAL_CONTAINER_NAME}"
    info "Complete"
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function get_image_id()
{
    IMAGE_ID=$(docker images -q "${LOCAL_CONTAINER_NAME}")

    if [[ -z "${IMAGE_ID}" ]]; then
        abort "Unable to locate image ID - aborting"
    fi

    info "\tUsing image ID: ${IMAGE_ID}"
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function tag_image()
{
    tag=$1

    tag="${tag##*( )}" # Remove leading spaces
    tag="${tag%%*( )}" # Remove trailing spaces

    info "\tAdding tag ${PUBLISHED_CONTAINER_NAME_FULL}:${tag}"

    docker tag "${IMAGE_ID}" "${PUBLISHED_CONTAINER_NAME_FULL}":"${tag}"
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function push_image
{
    info "\tPushing ${PUBLISHED_CONTAINER_NAME_FULL}"

    docker push "${PUBLISHED_CONTAINER_NAME_FULL}" --all-tags
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function publish_container()
{
    local tag_string=${CONTAINER_OS_VERSION_RAW}

    if [[ "${GHCR}" = true ]]; then
        PUBLISHED_CONTAINER_NAME_FULL="ghcr.io/${GHCR_ORGNAME}/${PUBLISHED_CONTAINER_NAME}"
    else
        PUBLISHED_CONTAINER_NAME_FULL="${DOCKER_HUB_ORG}/${PUBLISHED_CONTAINER_NAME}"
    fi

    info "Publishing: ${LOCAL_CONTAINER_NAME}"

    if [[ "${LATEST}" = true ]]; then
        tag_string+=',latest'
    fi

    IFS="," read -ra tags <<< "${tag_string}"

    get_image_id

    for tag in "${tags[@]}"
    do
        tag_image "${tag}"
    done

    push_image

    info "Complete"
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function usage()
{
    [[ -n "${*}" ]] && error "Error: ${*}"

cat <<EOF

  Usage: manage.sh [ -h ] [ options ]

  Valid Options:
      -h | --help     : Print this screen
      -d | --debug    : Debug mode (set -x)
      -b | --build    : Build a container (Optional: -c or --clean)
      -g | --generate : Generate a Dockerfile
      -p | --publish  : Publish a container
      -s | --scan     : Scan a container
      -G | --ghcr     : Publish to Github Container Registry

EOF
    abort
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function test_getopt
{
    if getopt --test > /dev/null && true; then
        abort "'getopt --test' failed in this environment - Please ensure you are using the gnu getopt"
    fi
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function process_options()
{
    if [[ $# -eq 0 ]]; then
        usage
    fi

    test_getopt

    OPTIONS=hdbcgpslG
    LONGOPTS=help,debug,build,clean,generate,publish,scan,latest,ghcr

    if ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@") && true; then
        usage
    fi
    eval set -- "${PARSED}"
    while true; do
        case "${1}" in
            -h|--help)
                usage
                ;;
            -d|--debug)
                set -x
                shift
                ;;
            -b|--build)
                BUILD=true
                shift
                ;;
            -c|--clean)
                CLEAN=true
                shift
                ;;
            -g|--generate)
                GENERATE=true
                shift
                ;;
            -p|--publish)
                PUBLISH=true
                shift
                ;;
            -s|--scan)
                SCAN=true
                shift
                ;;
            -l|--latest)
                LATEST=true
                shift
                ;;
            -G|--ghcr)
                GHCR=true
                shift
                ;;
            --)
                shift
                break
                ;;
        esac
    done

    [[ "${GENERATE}" != true ]] && [[ "${BUILD}" != true ]] && [[ "${SCAN}" != true ]] && [[ "${PUBLISH}" != true ]] &&  usage "You must select generate, build, scan or publish"

    [[ "${GENERATE}" = true ]] && generate_container
    [[ "${BUILD}" = true ]] &&  build_container
    [[ "${SCAN}" = true ]] && scan_container
    [[ "${PUBLISH}" = true ]] &&  publish_container

    exit 0
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function init_colours()
{
    local ncolors

    fgRed=''
    fgGreen=''
    fgYellow=''
    fgCyan=''
    bold=''
    reset=''

    if ! test -t 1; then
        export TERM=xterm
#        return
    fi

    if ! tput longname > /dev/null 2>&1; then
        return
    fi

    ncolors=$(tput colors)

    if ! test -n "${ncolors}" || test "${ncolors}" -le 7; then
        return
    fi

    fgRed=$(tput setaf 1)
    fgGreen=$(tput setaf 2)
    fgYellow=$(tput setaf 3)
    fgCyan=$(tput setaf 6)

    bold=$(tput bold)
    reset=$(tput sgr0)
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function abort()
{
    notify 'error' "${@}"
    exit 1
}

function error()
{
    notify 'error' "${@}"
}

function warn()
{
    notify 'warning' "${@}"
}

function success()
{
    notify 'success' "${@}"
}

function info()
{
    notify 'info' "${@}"
}

# -------------------------------------------------------------------------------- #
# Show Warning                                                                     #
# -------------------------------------------------------------------------------- #
# A simple wrapper function to show something was a warning.                       #
# -------------------------------------------------------------------------------- #

function notify()
{
    local type="${1:-}"
    shift
    local message="${*:-}"
    local fgColor

    if [[ -n $message ]]; then
        case "${type}" in
            error)
                fgColor="${fgRed}";
                ;;
            warning)
                fgColor="${fgYellow}";
                ;;
            success)
                fgColor="${fgGreen}";
                ;;
            info)
                fgColor="${fgCyan}";
                ;;
            *)
                fgColor='';
                ;;
        esac
        printf '%s%b%s\n' "${fgColor}${bold}" "${message}" "${reset}" 1>&2
    fi
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
function load_config
{
    # shellcheck disable=SC1091
    source "${REPO_ROOT}"/Config/config.cfg
}

# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #
# -------------------------------------------------------------------------------- #

function setup_container_details()
{
    IFS="/" read -ra PARTS <<< "$(pwd)"


    if [[ "${SINGLE_OS}" != true ]]; then
        CONTAINER_OS_NAME=${PARTS[-2]}				# OS name
    else
        CONTAINER_OS_NAME=${SINGLE_OS_NAME}			# OS name
    fi

    CONTAINER_OS_VERSION=${PARTS[-1]}				# Version number
    CONTAINER_OS_VERSION_RAW="${CONTAINER_OS_VERSION}"		# Raw Version
    CONTAINER_OS_VERSION="${CONTAINER_OS_VERSION//.}"		# Remove .

    if [[ "${NO_OS_NAME_IN_CONTAINER}" = true ]]; then
        CONTAINER_TMP="${CONTAINER_PREFIX}-${CONTAINER_OS_VERSION}"
        PUBLISHED_CONTAINER_NAME="${CONTAINER_PREFIX}"
    else
        CONTAINER_TMP="${CONTAINER_PREFIX}-${CONTAINER_OS_NAME}-${CONTAINER_OS_VERSION}"
        PUBLISHED_CONTAINER_NAME="${CONTAINER_PREFIX}-${CONTAINER_OS_VERSION}"
    fi
    LOCAL_CONTAINER_NAME="${CONTAINER_TMP//.}"

    if [[ "${CONTAINER_OS_NAME}" == "debian" ]]; then
        case "${CONTAINER_OS_VERSION_RAW}" in
            9)
                CONTAINER_OS_VERSION_ALT='stretch'
                ;;
            9-slim)
                CONTAINER_OS_VERSION_ALT='stretch-slim'
                ;;
            10)
                CONTAINER_OS_VERSION_ALT='buster'
                ;;
            10-slim)
                CONTAINER_OS_VERSION_ALT='buster-slim'
                ;;
            11)
                CONTAINER_OS_VERSION_ALT='bullseye'
                ;;
            11-slim)
                CONTAINER_OS_VERSION_ALT='bullseye-slim'
                ;;
            12)
                CONTAINER_OS_VERSION_ALT='bookworm'
                ;;
            12-slim)
                CONTAINER_OS_VERSION_ALT='bookworm-slim'
                ;;
            *)
                abort "Unknown debian version ${CONTAINER_OS_VERSION_RAW} - update utils.sh - aborting"
        esac
    else
        CONTAINER_OS_VERSION_ALT=$CONTAINER_OS_VERSION_RAW
    fi
}

# -------------------------------------------------------------------------------- #
# Check Prerequisites                                                              #
# -------------------------------------------------------------------------------- #
# Check to ensure that the prerequisite commmands exist.                           #
# -------------------------------------------------------------------------------- #

function check_prereqs()
{
    local error_count=0

    for i in "${PREREQ_COMMANDS[@]}"
    do
        command=$(command -v "${i}" || true)
        if [[ -z $command ]]; then
            warn "${i} is not in your command path"
            error_count=$((error_count+1))
        fi
    done

    if [[ $error_count -gt 0 ]]; then
        abort "${error_count} errors located - fix before re-running";
    fi
}

# -------------------------------------------------------------------------------- #
# Main()                                                                           #
# -------------------------------------------------------------------------------- #
# The main function where all of the heavy lifting and script config is done.      #
# -------------------------------------------------------------------------------- #

function main()
{
    init_colours
    load_config
    setup_container_details
    check_prereqs
    process_options "${@}"
}

# -------------------------------------------------------------------------------- #
# Main()                                                                           #
# -------------------------------------------------------------------------------- #
# This is the actual 'script' and the functions/sub routines are called in order.  #
# -------------------------------------------------------------------------------- #

main "${@}"

# -------------------------------------------------------------------------------- #
# End of Script                                                                    #
# -------------------------------------------------------------------------------- #
# This is the end - nothing more to see here.                                      #
# -------------------------------------------------------------------------------- #
