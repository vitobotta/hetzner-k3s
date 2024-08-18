fn_cloud="/var/lib/cloud/instance/boot-finished"
function await_cloud_init {
  echo "🕒 Awaiting cloud config (may take a minute...)"
  while true; do
    for _ in $(seq 1 10); do
      test -f $fn_cloud && return
      sleep 1
    done
    echo -n "."
  done
}
test -f $fn_cloud || await_cloud_init
echo "Cloud init finished: $(cat $fn_cloud)"
