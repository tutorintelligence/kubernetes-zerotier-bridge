#!/bin/bash

#zerotier-one
supervisord -c /etc/supervisor/supervisord.conf

[ -z "$ZTHOSTNAME" ] && echo "ZTHOSTNAME is empty, stopping" && exit 1

# Create arrays from NETWORK_IDS and ZTSTATICIP (comma-delimited)
# I learned a lot from https://stackoverflow.com/questions/10586153/how-to-split-a-string-into-an-array-in-bash
readarray -td, NETWORK_IDS_ARRAY <<<"$NETWORK_IDS,"
unset 'NETWORK_IDS_ARRAY[-1]'

if [ -n "$ZTSTATICIP" ]; then
  readarray -td, ZTSTATICIP_ARRAY <<<"$ZTSTATICIP,"
  unset 'ZTSTATICIP_ARRAY[-1]'

  # Assert that NETWORK_IDS_ARRAY and ZTSTATICIP_ARRAY have the same length
  [ ${#NETWORK_IDS_ARRAY[@]} != ${#ZTSTATICIP_ARRAY[@]} ] && echo "Please specify the same number of elements in NETWORK_IDS and ZTSTATICIP" && exit 1
else
  # Set ZTSTATICIP_ARRAY an empty array. All element accesses result in empty string.
  readarray ZTSTATICIP_ARRAY < /dev/null
fi

for (( NETWORK_INDEX = 0; NETWORK_INDEX < ${#NETWORK_IDS_ARRAY[@]}; NETWORK_INDEX++ ))
do
  NETWORK_ID=${NETWORK_IDS_ARRAY[NETWORK_INDEX]}
  ZTSTATICIP_FOR_NETWORK=${ZTSTATICIP_ARRAY[NETWORK_INDEX]}

  echo NETWORK_ID $NETWORK_ID
  echo ZTSTATICIP_FOR_NETWORK $ZTSTATICIP_FOR_NETWORK
  echo ---

  # Remove all nodes with this hostname from zerotier (avoid ip collisions)
  NODE_IDS=$( curl -X GET \
      -H "Authorization: Bearer $ZTAUTHTOKEN" \
      https://api.zerotier.com/api/v1/network/$NETWORK_ID/member | jq ".[] | select(.name==\"$ZTHOSTNAME\") | .config.id" )

  for ID in $( echo $NODE_IDS | sed 's/,/\t/g')
  do

      # Remove quotes
      ID="${ID%\"}"
      ID="${ID#\"}"
      echo "Deleting $ID..."
      curl -X DELETE \
          -H "Authorization: Bearer $ZTAUTHTOKEN" \
          https://api.zerotier.com/api/v1/network/$NETWORK_ID/member/$ID

  done


  { sleep 5; zerotier-cli join $NETWORK_ID || exit 1; }

  # waiting for Zerotier IP
  # why 2? because you have an ipv6 and an a ipv4 address by default if everything is ok
  IP_OK=0
  HOST_ID="$(zerotier-cli info | awk '{print $3}')"
  while [ $IP_OK -lt 1 ]
  do
    echo "No IP Assigned by Zerotier one, authenticating member..."

    ZTDEV=$( ip addr | grep -i zt | grep -i mtu | awk '{ print $2 }' | cut -f1 -d':' | tail -1 )
    IP_OK=$( ip addr show dev $ZTDEV | grep -i inet | wc -l )
    sleep 5

    echo $IP_OK

    echo "Auto accept the new client"
    curl -s -XPOST \
      -H "Authorization: Bearer $ZTAUTHTOKEN" \
      -d '{"hidden":"false","config":{"authorized":true}}' \
      "https://my.zerotier.com/api/network/$NETWORK_ID/member/$HOST_ID"

    echo "Set hostname to $ZTHOSTNAME"
    curl -s -XPOST \
      -H "Authorization: Bearer $ZTAUTHTOKEN" \
      -d "{\"name\":\"$ZTHOSTNAME\"}" \
      "https://my.zerotier.com/api/network/$NETWORK_ID/member/$HOST_ID"
  done
  echo "Zerotier successfuly joined by $HOST_ID"

  if [ -n "$ZTSTATICIP_FOR_NETWORK" ]; then
    CURR_IPS=$( curl -X GET -H "Authorization: Bearer $ZTAUTHTOKEN" https://api.zerotier.com/api/v1/network/$NETWORK_ID/member/$HOST_ID | jq ".config.ipAssignments" | jq ". += [\"$ZTSTATICIP_FOR_NETWORK\"]")
    echo "Assigning static ip $ZTSTATICIP_FOR_NETWORK to $HOST_ID and reauthenticating"
    curl -s -XPOST \
        -H "Authorization: Bearer $ZTAUTHTOKEN" \
        -d "{\"config\":{\"ipAssignments\":$CURR_IPS,\"authorized\":true}}" \
        "https://my.zerotier.com/api/network/$NETWORK_ID/member/$HOST_ID"
  fi

  sleep 5
  echo "Final Node $HOST_ID info: "
  curl -X GET \
      -H "Authorization: Bearer $ZTAUTHTOKEN" \
      https://api.zerotier.com/api/v1/network/$NETWORK_ID/member/$HOST_ID

done

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# something that keep the container running
tail -f /dev/null