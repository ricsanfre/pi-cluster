#!/bin/bash

# Execute ansible-runner command using bash shell with logging option
# runner user profile is loaded

CMD="docker exec -it ansible-runner \
     /bin/bash -lic"

# Execute docker run command
$CMD "$(printf ' %q' "$@")"
