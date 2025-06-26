#!/bin/sh

BIN_TARGET=/usr/local/bin/oci_keeper

BIN_URL_ARM=https://mk386.github.io/binary/oci_keeper/oci_keeper.arm-aarch64
BIN_URL_X86=https://mk386.github.io/binary/oci_keeper/oci_keeper.x86-64

FILE_SERVICE_TARGET=/etc/systemd/system/oci_keeper.service


# to remove the legacy scripts
systemctl stop lookbusy.service > /dev/null 2>&1 &
systemctl disable --now lookbusy.service > /dev/null 2>&1 &
rm -fr /etc/systemd/system/lookbusy.service > /dev/null 2>&1 &
rm -fr /usr/local/bin/lookbusy > /dev/null 2>&1 &

# to remove the old scripts
systemctl stop oci_keeper.service > /dev/null 2>&1 &
systemctl disable --now oci_keeper.service > /dev/null 2>&1 &
rm -fr /etc/systemd/system/oci_keeper.service > /dev/null 2>&1 &
rm -fr /usr/local/bin/oci_keeper > /dev/null 2>&1 &


gen_service_script_setup()
{
cat > ${FILE_SERVICE_TARGET} <<EOL
[Unit]
Description=oci_keeper service

[Service]
Type=simple
ExecStart=/usr/local/bin/oci_keeper -c 15-19 -m ${1}MB
Restart=always
RestartSec=10
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOL

systemctl enable --now oci_keeper.service
}


gen_service_script_arm()
{
cat > ${FILE_SERVICE_TARGET} <<EOL
[Unit]
Description=oci_keeper service

[Service]
Type=simple
ExecStart=/usr/local/bin/oci_keeper -c 15-19 -m 4096MB
Restart=always
RestartSec=10
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOL

systemctl enable --now oci_keeper.service
}

gen_service_script_x86()
{
cat > ${FILE_SERVICE_TARGET} <<EOL
[Unit]
Description=oci_keeper service

[Service]
Type=simple
ExecStart=/usr/local/bin/oci_keeper -c 15-19
Restart=always
RestartSec=10
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOL

systemctl enable --now oci_keeper.service
}


setup_main()
{
    chmod 755 $BIN_TARGET
    chmod o+x $BIN_TARGET
}

#
export CPU=`uname -p`
export RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
export RAM_MB=$(expr $RAM_KB / 1024)
export RAM_GB=$(expr $RAM_MB / 1024)
export RAM_FT=$(expr $RAM_KB / 1000 / 1000 / 6)
export RAM_TH=$(expr $RAM_FT \* 1024)


if [ "$CPU" = 'aarch64' ]; then
    # ARM-based
    echo "ARM-based";
    curl -o $BIN_TARGET $BIN_URL_ARM
    setup_main
    gen_service_script_setup $RAM_TH
elif [ "$CPU" = 'x86_64' ]; then
    # AMD/x86-based
    echo "x86-based";
    curl -o $BIN_TARGET $BIN_URL_X86
    setup_main
    gen_service_script_setup $RAM_TH
else
    # Unknown
    echo "Unknown CPU (TODO)";  
fi


