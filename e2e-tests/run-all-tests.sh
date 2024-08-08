#!/bin/sh
T=./run-single-test.sh

$T config-sshport-image.yaml IMAGE=debian-11 SSHPORT=222
$T config-sshport-image.yaml IMAGE=debian-11 SSHPORT=22
$T config-sshport-image.yaml IMAGE=debian-12 SSHPORT=222
$T config-sshport-image.yaml IMAGE=ubuntu-20.04 SSHPORT=222
$T config-sshport-image.yaml IMAGE=ubuntu-22.04 SSHPORT=222
$T config-sshport-image.yaml IMAGE=ubuntu-24.04 SSHPORT=222
$T config-sshport-image.yaml IMAGE=alma-8 SSHPORT=22
$T config-sshport-image.yaml IMAGE=alma-8 SSHPORT=222
$T config-sshport-image.yaml IMAGE=alma-9 SSHPORT=22
$T config-sshport-image.yaml IMAGE=alma-9 SSHPORT=222
$T config-sshport-image.yaml IMAGE=rocky-8 SSHPORT=22
$T config-sshport-image.yaml IMAGE=rocky-8 SSHPORT=222
$T config-sshport-image.yaml IMAGE=rocky-9 SSHPORT=22
$T config-sshport-image.yaml IMAGE=fedora-38 SSHPORT=222
$T config-sshport-image.yaml IMAGE=fedora-39 SSHPORT=222
$T config-sshport-image.yaml IMAGE=fedora-40 SSHPORT=222
$T config-sshport-image.yaml IMAGE=centos-stream-8 SSHPORT=222
$T config-sshport-image.yaml IMAGE=centos-stream-9 SSHPORT=222
$T config-sshport-image.yaml IMAGE=centos-stream-8 SSHPORT=22
