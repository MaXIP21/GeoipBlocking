#!/bin/bash
##
## Ip lists are generated at https://www.ip2location.com/free/visitor-blocker (Select country and CIDR format) then download
##
_SOURCE_DIR=./sources
_IPLIST_DIR=./lists
_CLEANUP=true
_MAXIMUM_LANES=65536

function create_directory_if_not_exists {
  mkdir -p $1
}

function delete_ipset {
  if [[ $_CLEANUP == true ]]; then
    echo "[INFO] Cleaning up ipset"
    ipset -X $1 2>/dev/null
  fi
}

function test_ipset {
  echo "ipset list $1 >/dev/null" | bash
  _return=$?
}

function test_file_exists {
  _exist_return=0 
  if [ -f $1 ]; then
    _exist_return=1 
  fi
}

function check_if_iptables_exists {
  if [[ ${_TYPE} == ipv6 ]]; then 
    echo "[INFO] Checking if ip6tables $1 rule exists for $2."
    _ipt_lines=$(ip6tables -L $1 | grep $2 | wc -l)
  else
    echo "[INFO] Checking if iptables $1 rule exists for $2."
    _ipt_lines=$(iptables -L $1 | grep $2 | wc -l)
  fi
}

function get_ipv4_or_ipv6 {
  filename=$(basename -- "$1")
  if [[ $filename =~ "v6" ]]; then
    _TYPE=ipv6
  else
    _TYPE=ipv4
  fi
}

function get_REGION {
  filename=$(basename -- "$1")
  _REGION=$(echo $filename | sed 's/_.*//')
}

function extract_file_to_iplist_dir {
  gunzip -c $1 > $2
}

function clear_variables {
  _REGION=""
  _TYPE=""
}

function cut_file_to_multiple {
  create_directory_if_not_exists ./tmp
  filename=$(basename -- "$1" .txt)
  split -l $_MAXIMUM_LANES $1 ./tmp/${filename}_ext
  _counter=1
  for split_files in ./tmp/* ; 
  do 
    _file_basename=$(echo $split_files | sed 's/_.*//')
    _target_file_name=$(basename -- "$_file_basename")-${_counter}.txt
    echo $_target_file_name
    mv $split_files $_IPLIST_DIR/$_target_file_name
    let "_counter+=1"
  done
  rm $1
}

function divide_file_by_lane_number {
  _length=$(cat $1 | wc -l)
  if [[ $_length -le $_MAXIMUM_LANES ]]; then
    echo "[INFO] - File length of ($1) is less than $_MAXIMUM_LANES"
  else
    echo "[INFO] - File length of ($1) is larger than $_MAXIMUM_LANES, cutting to multiple files !"
    cut_file_to_multiple $1
  fi
}

function remove_comments_from_lists {
  sed -i -e '/^[ \t]*#/d' $1
}

function set_ipset {
  _filename=$1
  _IPSET_NAME=$(basename -- "$1" .txt)
  which ipset
  if [[ $? == 1 ]]; then
    echo "[ERROR] Ipset is not installet or can't be found in \$PATH, please check ! "
    exit 1
  fi
  echo "[INFO] Creating geoblocking for country: $_REGION"
  delete_ipset $_IPSET_NAME
  test_ipset $_IPSET_NAME
  if [[ $_return == 1 ]]; then
    echo "[INFO] Creating set $_IPSET_NAME"
    if [[ ${_TYPE} == ipv6 ]]; then 
      ipset create $_IPSET_NAME hash:net family inet6 timeout 86400
    else
      ipset create $_IPSET_NAME hash:net timeout 86400
    fi
  else
    echo "[WARNING] The set named ($_IPSET_NAME) already exists !"
  fi
 
  test_file_exists $_filename
  if [[ $_exist_return == 0 ]]; then 
    echo "[ERROR] Can't find file $_filename"
  else
    
    cat $_filename | grep -v ^# | awk {'print "ipset -exist add '$_IPSET_NAME' " $1'} | bash

    _CHAIN="INPUT"
    _ipt_lines=0
    check_if_iptables_exists $_CHAIN $_IPSET_NAME $_TYPE
    if [ $_ipt_lines == 0 ]; then 
      echo "[INFO] Creating IPtables $_CHAIN rule of $_IPSET_NAME"
      if [[ ${_TYPE} == ipv6 ]]; then 
        ip6tables -I INPUT -m set --match-set $_IPSET_NAME src -j DROP
      else
        iptables -I INPUT -m set --match-set $_IPSET_NAME src -j DROP
      fi
    else
      echo "[INFO] IPtables INPUT rule already exists for set $_IPSET_NAME"
    fi

    _CHAIN="OUTPUT"
    _ipt_lines=0
    check_if_iptables_exists $_CHAIN $_IPSET_NAME $_TYPE
    if [ $_ipt_lines == 0 ]; then 
      echo "[INFO] Creating IPtables $_CHAIN rule of $_IPSET_NAME"
      if [[ ${_TYPE} == ipv6 ]]; then 
        ip6tables -I OUTPUT -m set --match-set $_IPSET_NAME dst -j DROP
      else
        iptables -I OUTPUT -m set --match-set $_IPSET_NAME dst -j DROP
      fi
    else 
      echo "[INFO] IPtables OUTPUT rule already exists for set $_IPSET_NAME"
    fi
  fi
}

function prepare_lists {
  for input_file in $_SOURCE_DIR/blacklist/*.txt.gz; 
  do
    clear_variables
    get_REGION $input_file
    get_ipv4_or_ipv6 $input_file
    _CURRENT_LIST_FILENAME=${_IPLIST_DIR}/${_REGION}-${_TYPE}.txt
    extract_file_to_iplist_dir $input_file $_CURRENT_LIST_FILENAME
    remove_comments_from_lists $_CURRENT_LIST_FILENAME
  done
}

function create_sets {
  for input_file in $_IPLIST_DIR/*.txt; 
  do
    clear_variables
    get_REGION $input_file
    get_ipv4_or_ipv6 $input_file
    divide_file_by_lane_number $input_file
    set_ipset $input_file
  done
}



create_directory_if_not_exists $_IPLIST_DIR
prepare_lists
create_sets
