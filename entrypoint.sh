#!/bin/sh

cp -R /tmp/.ssh /root/.ssh
chmod 700 /root/.ssh
chmod 600 /root/.ssh/*
chmod 644 /root/.ssh/*.pub

eval $(ssh-agent -s) 2&>1  > /dev/null

ssh-add ~/.ssh/* 2&>1  > /dev/null

hetzner-k3s "$@"
