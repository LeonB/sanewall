#!/bin/bash

if [ "$RUN_SUITE" != "OK" ]
then
  echo "Do not call this script directly"
  exit 1
fi


if [ ! -x "$1" ]
then
  echo "Executable program $1 not found"
  exit 1
fi
prog=$1
shift

if [ ! "$1" ]
then
  echo "No output directory specified"
  exit 1
fi

case "$1" in
   output/*)
      outdir="$1"
      shift
   ;;
   *)
      echo "Output directory must be output/something"
      exit 1
   ;;
esac

here=`pwd`
rm -rf $outdir

clear_all() {
  cat > /tmp/reset.$$ <<-!
	*nat
	:PREROUTING ACCEPT [0:0]
	:INPUT ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	:POSTROUTING ACCEPT [0:0]
	COMMIT
	*mangle
	:PREROUTING ACCEPT [0:0]
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	:POSTROUTING ACCEPT [0:0]
	COMMIT
	*filter
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	COMMIT
	!
  iptables-restore < /tmp/reset.$$
  st1=$?

  cat > /tmp/reset.$$ <<-!
	*mangle
	:PREROUTING ACCEPT [0:0]
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	:POSTROUTING ACCEPT [0:0]
	COMMIT
	*filter
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	COMMIT
	!
  ip6tables-restore < /tmp/reset.$$
  rm -f /tmp/reset.$$
  st2=$?

  if [ $st1 -ne 0 -o  $st2 -ne 0 ]
  then
    exit 2
  fi
}

myexit() {
  rm -f /tmp/sanewall-tests-save.$$
  rm -f /tmp/sanewall-tests-save6.$$
  rm -f /tmp/sanewall-tests-list.$$

  cd $here
  test -n "${SUDO_USER}" && chown -R ${SUDO_USER} output
  rm -rf "@SANEWALL_CONFIG_DIR@"
  clear_all
  exit 0
}

trap myexit SIGINT
trap myexit SIGHUP

cd $here
cd `dirname $prog` || myexit
progdir=`pwd`
progname=`basename $prog`
prog=$progdir/$progname

cd $here
> /tmp/sanewall-tests-list.$$
if [ $# -eq 0 ]
then
  find tests -type f -name '*.conf' >> /tmp/sanewall-tests-list.$$
fi

for i in "$@"
do
  if [ -f "$1" ]
  then
    echo "$i" >> /tmp/sanewall-tests-list.$$
  elif [ -d "$i" ]
  then
    find "$i" -type f -name '*.conf' >> /tmp/sanewall-tests-list.$$
  else
    echo "$i: Not a file or directory"
  fi
done

mkdir -p $outdir/ipv6 || myexit
mkdir -p $outdir/ipv4-no-nat || myexit
mkdir -p "@SANEWALL_CONFIG_DIR@/services"

iptables-save > /tmp/sanewall-tests-save.$$ || myexit
ip6tables-save > /tmp/sanewall-tests-save6.$$ || myexit

sort -u /tmp/sanewall-tests-list.$$ > /tmp/sanewall-tests-list.$$.srt
mv /tmp/sanewall-tests-list.$$.srt /tmp/sanewall-tests-list.$$
while read testfile
do
  i=`echo $testfile | sed -e 's;/;-;g' -e s'/.conf$//'`
  logfile="$outdir/$i.log"
  v4out="$outdir/$i.out"
  v6out="$outdir/ipv6/$i.out"
  v4nnout="$outdir/ipv4-no-nat/$i.out"
  echo ""
  echo "  Running $testfile"
  echo "      log $logfile"
  echo " v4result $v4out"
  echo " v6result $v6out"
  clear_all
  $prog "$here/$testfile" start >> "$logfile" 2>&1
  iptables-save > "$v4out"
  ip6tables-save > "$v6out"
  sed -i -e 's/^Sanewall: //' -e 's/^FireHOL: //' "$logfile"
  sed -i -e 's;/sbin/iptables;iptables_cmd;' "$logfile"
  sed -i -e 's/^# .*/#/' -e '/^:/s/\[[0-9][0-9]*:[0-9][0-9]*\]$/[0:0]/' "$v4out"
  sed -e '1d' -e '/^\*nat/,/^#/{d}' "$v4out" > "$v4nnout"
  sed -i -e 's/^# .*/#/' -e '/^:/s/\[[0-9][0-9]*:[0-9][0-9]*\]$/[0:0]/' "$v6out"
  sed -i -e 's/icmp6-/icmp-/' "$v6out"
  sed -i -e 's;::\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)/128;\1/32;' "$v6out"
done < /tmp/sanewall-tests-list.$$

iptables-restore < /tmp/sanewall-tests-save.$$
ip6tables-restore < /tmp/sanewall-tests-save6.$$
myexit
