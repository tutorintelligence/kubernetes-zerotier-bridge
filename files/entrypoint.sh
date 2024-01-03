#!/bin/bash

#zerotier-one
supervisord -c /etc/supervisor/supervisord.conf

for NETWORK_ID in $(echo $NETWORK_IDS | sed 's/,/\t/g')
do
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

  CURR_IPS=$( curl -X GET -H "Authorization: Bearer $ZTAUTHTOKEN" https://api.zerotier.com/api/v1/network/$NETWORK_ID/member/$HOST_ID | jq ".config.ipAssignments" | jq ". += [\"$ZTSTATICIP\"]")
  echo "Assigning static ip $ZTSTATICIP to $HOST_ID and reauthenticating"
  curl -s -XPOST \
      -H "Authorization: Bearer $ZTAUTHTOKEN" \
      -d "{\"config\":{\"ipAssignments\":$CURR_IPS,\"authorized\":true}}" \
      "https://my.zerotier.com/api/network/$NETWORK_ID/member/$HOST_ID"

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