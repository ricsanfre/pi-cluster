#!/bin/bash

#ansible-runner wrapper script

# Get dir location
script_path=`readlink -f "${BASE_SOURCE:-$0}"`
DIR_PATH=`dirname $script_path`

#Define load environment variables file function
envup() {
  local file=$1

  if [ -f $file ]; then
    set -a
    source $file
    set +a
  else
    echo "No $file file found" 1>&2
    return 1
  fi
}

# Load ansible runner env file
envup ${DIR_PATH}/env

CMD="docker run -it --rm \
    --env-file ${DIR_PATH}/env \
    -v ${DIR_PATH}/../../ansible:/runner/project \
    -v ${DIR_PATH}/artifacts:/runner/artifacts \
    -v ${DIR_PATH}/.gnupg:/home/runner/.gnupg \
    -v ${DIR_PATH}/.vault:/home/runner/.vault \
    -v ${DIR_PATH}/scripts:/home/runner/scripts \
    ${DOCKER_IMG}"

# Execute docker run command
exec $CMD "${@}"