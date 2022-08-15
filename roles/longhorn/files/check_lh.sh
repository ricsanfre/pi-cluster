#!/bin/bash

verifyLonghorn()
{
    while [ $# -gt 0 ]; do
        case "$1" in
        --clustername*|-cname*)
            if [[ "$1" != *=* ]]; then shift; fi
            local __clustername="${1#*=}"
            ;;
        --debugMode|-dMode)
            local __debugMode="true"
            ;;
        --withRetry|-wr)
            local __withRetry="true"
            ;;            
        --help|-h)
            echo "Syntax: verifyLonghorn [--clustername|--debugMode|--withRetry|--help]"
            echo "Options:"
            echo "  --clustername, -cname         > The name of the cluster to work on."
            echo "  --debugMode, -dMode           > Indicates to the function that debug output should be displayed."
            echo "  --withRetry, -wr        > Indicates to getEtcdLeader that it should retry, on failure, until the retry limit is met."                        
            echo -e "\nExamples"
            echo -e '[1]: verifyLonghorn --clustername="test-test"'
            echo -e ">> Verifies that the cluster in context have a healthy Longhorn CSI running."
            echo -e ' ======================= || ======================= '
            echo -e '[2]: verifyLonghorn --clustername="test-test" --debugMode'
            echo -e '>> Verifies that the cluster in context have a healthy Longhorn CSI running. Using "--debugMode" indicates to verifyLonghorn that'
            echo -e '   debug output is wanted on stdout.'
            echo -e ' ======================= || ======================= '
            echo -e '[3]: verifyLonghorn --clustername="test-test" --withRetry'
            echo -e '>> Verifies that the cluster in context have a healthy Longhorn CSI running. Using "--withRetry" indicates to verifyLonghorn that'
            echo -e '   that it should continue controlling the health and state of Longhorn until the retry liimt is met.'            
            local __helpUsed="true"
            ;;
        *)
            >&2 printf "Error: Invalid argument\n"
            exit 6
            ;;
        esac
        shift
    done

    if [[ -z "$__helpUsed" ]]; then
        ####
        # Control parameters
        ####    

        # Control that the necessary prerequisites are present
        if [ ! "$(which kubectl)" ] || [ ! "$(which jq)" ]; then
            echo "You need to have kubectl & jq installed on your box."
            echo "The script will now exit - fix the above"
            exit 5
        fi

        # Assign a default value to '__debugMode'
        if [[ -z "${__debugMode}" ]]; then
            local __debugMode="false"
        fi

        # Assign a default value to '__withRetry'
        if [[ -z "${__withRetry}" ]]; then
            local __withRetry="false"
        fi        

        ###########
        # EXECUTE #
        ###########
        local JQ; JQ=${JQ:-jq}
        JQ=$(command -v "${JQ}")

        # Helper functions to reduce the amount of args we pass in to each jq call,
        # note we are calling whatever command -v /jq/etc.. found directly to avoid
        # recursion
        jq() {
            ${JQ} -r "$@"
        }

        # Looping through all of the must be deployed resources during 5 minutes with 10 seconds intervals
        local __count=0
        while [ "$__count" -lt 30 ]; do
            # Functions and variables to calculate the number of resource to determine the success of the deployment    
            local __DESIRED_RESORCE_NUMBER=0
            local __AVAILABLE_RESOURCE_NUMBER=0

            add_desired() {
                (( __DESIRED_RESORCE_NUMBER+$1 ))
            }

            add_available() {
                (( __AVAILABLE_RESOURCE_NUMBER+$1 ))
            }

            # Use check_replicas "resource_type" "resource_name" 
            # E.g: The Longhorn UI deployment: check_replicas "deployment" "longhorn-ui"
            check_replicas() {
                local __AVAILABLE_REPLICAS; __AVAILABLE_REPLICAS=$(kubectl get "${1}" "${2}" --namespace longhorn-system -o json \
                    | jq -r '.status.availableReplicas')
                local __DESIRED_REPLICAS; __DESIRED_REPLICAS=$(kubectl get "${1}" "${2}" --namespace longhorn-system -o json \
                    | jq -r '.spec.replicas')
                if [ -z "$__DESIRED_REPLICAS" ] || [ -z "$__AVAILABLE_REPLICAS" ]; then
                    if [[ "${__debugMode}" == "true" ]]; then
                        echo "Longhorn ${1} ${2} replicas not deployed yet"
                    fi
                elif [ "$__DESIRED_REPLICAS" -eq "$__AVAILABLE_REPLICAS" ]; then
                    if [[ "${__debugMode}" == "true" ]]; then
                        echo "Longhorn ${1} ${2} replicas deployed successfully"
                    fi
                    add_desired "$__DESIRED_REPLICAS"
                    add_available "$__AVAILABLE_REPLICAS"
                else
                    if [[ "${__debugMode}" == "true" ]]; then
                        echo "Longhorn ${1} ${2} replicas not fully deployed yet"
                    fi
                fi
            }

            ### Kubernetes nodes check
            # Generate a list of nodes 
            local __NODE_LIST; __NODE_LIST=$(kubectl get nodes -o json \
                | jq -r '.items[].metadata.name')

            # Iterate through nodes and determine if each node has Kubelet in Ready status
            for node in $__NODE_LIST; do
                local __NODE_STATUS; __NODE_STATUS=$(kubectl get nodes "$node" -o json \
                    | jq -r '
                        .status.conditions[] |
                        select(.reason == "KubeletReady") |
                        .status
                    ')
                add_desired "1"
                if [ -z "$__NODE_STATUS" ]; then
                    if [[ "${__debugMode}" == "true" ]]; then
                        echo "Node $node is not ready yet"
                    fi
                    break
                elif [ "$__NODE_STATUS" = "True" ]; then
                    if [[ "${__debugMode}" == "true" ]]; then
                        echo "Node $node is ready"
                    fi
                    add_available "1"
                else
                    if [[ "${__debugMode}" == "true" ]]; then
                        echo "Node $node is not ready yet"
                    fi
                    add_available "-1"
                fi
            done

            ### DAEMONSETS
            # Check the number of Longhorn Manager daemonsets
            local __DESIRED_LH_MANAGER_DS_NUMBER; __DESIRED_LH_MANAGER_DS_NUMBER=$(kubectl get daemonsets.apps longhorn-manager --namespace longhorn-system -o json \
                | jq -r '
                    .status |
                    .desiredNumberScheduled
                ')
            local __READY_LH_MANAGER_DS_NUMBER; __READY_LH_MANAGER_DS_NUMBER=$(kubectl get daemonsets longhorn-manager --namespace longhorn-system -o json \
                | jq -r '
                    .status |
                    .numberReady
                ')
            if [ -z "$__DESIRED_LH_MANAGER_DS_NUMBER" ] || [ -z "$__READY_LH_MANAGER_DS_NUMBER" ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn Manager deamonsets are not deployed yet"
                fi

                if [[ "${__withRetry}" == "true" ]]; then
                    # Start while loop again
                    (( __count++ ))
                    sleep 10
                    continue
                fi
            elif [ "$__DESIRED_LH_MANAGER_DS_NUMBER" -eq "$__READY_LH_MANAGER_DS_NUMBER" ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn Manager deamonsets are deployed"
                fi
                add_desired "$__DESIRED_LH_MANAGER_DS_NUMBER"
                add_available "$__READY_LH_MANAGER_DS_NUMBER"
            else
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn Manager deamonsets are not fully deployed yet"
                fi
            fi

            ### CRDs
            # Compare the desired Longhorn manager number of daemonsets to a number of nodes in longhorn-system namespace
            # If numbers match, proceed with checking nodes and instance-managers statuses
            local __LONGHORN_NODE_LIST_NUMBER; __LONGHORN_NODE_LIST_NUMBER=$(kubectl get nodes.longhorn.io -n longhorn-system -o json \
                | jq -r '.items[].spec.name' \
                | wc -l)

            if [ "$__LONGHORN_NODE_LIST_NUMBER" -eq 0 ] || [ "$__DESIRED_LH_MANAGER_DS_NUMBER" -ne "$__LONGHORN_NODE_LIST_NUMBER" ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn nodes CRDs are not deployed yet"
                fi
                if [[ "${__withRetry}" == "true" ]]; then
                    # Start while loop again
                    (( __count++ ))
                    sleep 10
                    continue
                fi
            else
                # Generate a list of nodes that Lonhorn is installed on
                local __LONGHORN_NODE_LIST; __LONGHORN_NODE_LIST=$(kubectl get nodes.longhorn.io -n longhorn-system -o json \
                    | jq -r '
                        .items[].spec.name
                    ')
                
                # Iterate through Longhorn nodes and determine if each node has Kubelet in Ready status
                for node in $__LONGHORN_NODE_LIST; do
                    local __LONGHORN_NODE_STATUS; __LONGHORN_NODE_STATUS=$(kubectl get nodes.longhorn.io/"${node}" -n longhorn-system -o json \
                        | jq -r '
                            .status.conditions[] |
                            select(.type == "Ready") |
                           .status
                        ')
                    add_desired "1"
                    if [ -z "$__LONGHORN_NODE_STATUS" ]; then
                        if [[ "${__debugMode}" == "true" ]]; then
                            echo "Longhorn Node $node is not deployed yet"
                        fi
                        break
                    elif [ "$__LONGHORN_NODE_STATUS" = "True" ]; then
                        if [[ "${__debugMode}" == "true" ]]; then
                            echo "Longhorn Node $node is deployed successfully"
                        fi
                        add_available "1"
                    else
                        if [[ "${__debugMode}" == "true" ]]; then
                            echo "Longhorn Node $node is not deployed yet"
                        fi
                        add_available "-1"
                    fi
                done

                # Iterate through nodes to see if instance-managers: engine and replica are deployed
                for node in $__LONGHORN_NODE_LIST; do
                    for manager in engine replica; do
                        STATUS=$(kubectl get instancemanagers -n longhorn-system -o json \
                            | jq -r "
                                .items[] |
                                select(.spec.nodeID == \"$node\") |
                                select(.spec.type == \"$manager\") |
                                .status.currentState
                            ")
                        add_desired "1"

                        # Variable STATUS will be empty when there are no resources deployed yet, therefore break out of the loop
                        if [ -z "$STATUS" ]; then
                            if [[ "${__debugMode}" == "true" ]]; then
                                echo "Node $node has instance manager $manager not deployed yet"
                            fi
                            break
                        elif [ "$STATUS" = "running" ]; then
                            if [[ "${__debugMode}" == "true" ]]; then
                                echo "Node $node has instance manager $manager deployed"
                            fi
                            add_available "1"
                        else
                            if [[ "${__debugMode}" == "true" ]]; then
                                echo "Node $node has instance manager $manager not fully deployed yet"
                            fi
                            add_available "-1"
                        fi
                    done
                done
            fi # End of conditional on __LONGHORN_NODE_LIST_NUMBER

            # Engine images status
            local __ENGINE_IMAGES_STATUS; __ENGINE_IMAGES_STATUS=$(kubectl get engineimages -n longhorn-system -o json \
                | jq -r '.items[].status.state')
            add_desired "1"
            if [ "$__ENGINE_IMAGES_STATUS" = "deployed" ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn Engine Images deployed successfully"
                fi
                add_available "1"
            else
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn Engine Images are not deployed yet"
                fi
                if [[ "${__withRetry}" == "true" ]]; then
                    # Start while loop again
                    (( __count++ ))
                    sleep 10
                    continue
                fi
            fi

            # Checking if Longhorn CSI Plugin is running on all nodes
            local __DESIRED_CSI_PLUGIN_NUMBER; __DESIRED_CSI_PLUGIN_NUMBER=$(kubectl get daemonsets longhorn-csi-plugin --namespace longhorn-system -o json \
                | jq -r '.status.desiredNumberScheduled')
            local __AVAILABLE_CSI_PLUGIN_NUMBER; __AVAILABLE_CSI_PLUGIN_NUMBER=$(kubectl get daemonsets longhorn-csi-plugin --namespace longhorn-system -o json \
                | jq -r '.status.numberAvailable')
            if [ -z "$__DESIRED_CSI_PLUGIN_NUMBER" ] || [ -z "$__AVAILABLE_CSI_PLUGIN_NUMBER" ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn CSI Plugin not deployed yet"
                fi
                if [[ "${__withRetry}" == "true" ]]; then
                    # Start while loop again
                    (( __count++ ))
                    sleep 10
                    continue
                fi
            elif [ "$__DESIRED_CSI_PLUGIN_NUMBER" -eq "$__AVAILABLE_CSI_PLUGIN_NUMBER" ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn CSI Plugin deployed successfully"
                fi
                add_desired "$__DESIRED_CSI_PLUGIN_NUMBER"
                add_available "$__AVAILABLE_CSI_PLUGIN_NUMBER"
            else
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Longhorn CSI Plugin not fully deployed yet"
                fi
            fi

            ### Volumes
            # Controls that all the Volumes in the cluster
            # are in state [healthy]
            local __LONGHORN_VOLUME_LIST_NUMBER; __LONGHORN_VOLUME_LIST_NUMBER=$(kubectl get volumes.longhorn.io -n longhorn-system -o json \
                | jq -r '.items[].metadata.name' \
                | wc -l)

            if [ "$__LONGHORN_VOLUME_LIST_NUMBER" -eq 0 ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "No Longhorn volumes are currently deployed"
                fi
            else
                # Get the volumes currently deployed
                local __LONGHORN_VOLUME_LIST; __LONGHORN_VOLUME_LIST=$(kubectl get volumes.longhorn.io -n longhorn-system -o json \
                    | jq -r '.items[].metadata.name')
                
                # Iterate through Longhorn volumes and determine if each node has Kubelet in Ready status
                for volume in $__LONGHORN_VOLUME_LIST; do
                    local __LONGHORN_VOLUME_STATUS; __LONGHORN_VOLUME_STATUS=$(kubectl get volumes.longhorn.io/"${volume}" -n longhorn-system -o json \
                        | jq -r '.status.robustness')
                    add_desired "1"
                    if [ "$__LONGHORN_VOLUME_STATUS" = "healthy" ]; then
                        if [[ "${__debugMode}" == "true" ]]; then
                            echo "The Longhorn Volume $volume is healthy"
                        fi
                        add_available "1"
                    else
                        if [[ "${__debugMode}" == "true" ]]; then
                            echo "The Longhorn Volume $volume is NOT healthy"
                        fi
                        add_available "-1"
                    fi
                done            
            fi # End of conditional on __LONGHORN_VOLUME_LIST_NUMBER

            # Longhorn UI deployment status
            check_replicas "deployment" "longhorn-ui"

            # Checking Longhorn CSI Attacher deployment status
            check_replicas "deployment" "csi-attacher"

            # Checking Longhorn CSI Provisioner deployment status
            check_replicas "deployment" "csi-provisioner"

            # Checking Longhorn CSI Resizer deployment status
            check_replicas "deployment" "csi-resizer"

            # Checking Longhorn CSI Snapshotter deployment status
            check_replicas "deployment" "csi-snapshotter"

            if [ "$__DESIRED_RESORCE_NUMBER" -eq "$__AVAILABLE_RESOURCE_NUMBER" ]; then
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "All Longhorn resources are healthy & fully deployed."
                fi
                local __result; __result="true"
                
                # Breaks the outermost while loop
                break
            else
                if [[ "${__debugMode}" == "true" ]]; then
                    echo "Not all Longhorn resources are healthy & fully deployed yet"
                fi
            fi

            if [[ "${__withRetry}" == "true" ]]; then
                (( __count++ ))
                sleep 10
            else
                local __result; __result="false"

                # Breaks the outermost while loop
                break
            fi
        done
        echo "${__result}"
    fi # End of conditional on the __helpUsed variable
}

verifyLonghorn $@
